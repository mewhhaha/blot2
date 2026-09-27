import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { toBendModel } from "./bend_abi.ts";
import {
  analyze,
  CompilerError,
  type CoreModule,
  type DataType,
  emptyRow,
  type Expr,
  type Type,
} from "./host.ts";
import {
  boolType,
  call,
  fn,
  integer,
  invoke,
  local,
  module,
  operation,
  u32Type,
  unit,
  unitType,
} from "./fixtures.ts";
import { bendList } from "./bend_list.ts";

const productType = (...elements: Type[]): Type => ({
  $: "ProductTy",
  elements,
});
const product = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const project = (value: Expr, index = 0n): Expr => ({
  $: "ProjectExpr",
  value,
  index,
});
const apply = (callee: Expr, argument: Expr = unit): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});
const lambda = (
  identity: bigint,
  body: Expr,
  parameter_type: Type | null = null,
): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter: "argument",
  parameter_type,
  result_type: null,
  body,
});
const boolean = (value: boolean): Expr => ({ $: "BoolExpr", value });

function rejects(source: CoreModule, code: string) {
  throws(
    () => analyze(source),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

Deno.test("products infer nested heterogeneous fields and statically project a known shape", () => {
  const pair = product(integer(42), product(boolean(true), unit));
  const analysis = analyze(module([
    fn("pair", pair, { exported: false }),
    fn("number", project(call("pair"))),
    fn("truth", project(project(call("pair"), 1n))),
    fn("annotated", project(local("value"), 1n), {
      parameter_type: productType(boolType, u32Type),
    }),
  ]));
  equal(analysis.functions.map((entry) => entry.result), [
    productType(u32Type, productType(boolType, unitType)),
    u32Type,
    boolType,
    u32Type,
  ]);
});

Deno.test("product expressions and annotations reject zero or one element without conflating Unit", () => {
  for (const elements of [[], [integer(1)]]) {
    rejects(module([fn("invalid", product(...elements))]), "product_arity");
  }
  for (const elements of [[], [u32Type]]) {
    rejects(
      module([fn("unused", unit, {
        exported: false,
        parameter_type: productType(...elements),
      })]),
      "product_arity",
    );
  }
  rejects(
    module([fn("invalid", unit, {
      result_type: productType(unitType, unitType),
    })]),
    "type_mismatch",
  );
  rejects(
    module([fn("invalid", product(integer(1), integer(2), integer(3)), {
      result_type: productType(u32Type, u32Type),
    })]),
    "product_arity",
  );
});

Deno.test("projection rejects unknown shapes, scalar targets, and all out-of-bounds indices", () => {
  rejects(
    module([fn("unknown", project(local("value")), {
      parameter_type: null,
      exported: false,
    })]),
    "unknown_product_shape",
  );
  rejects(module([fn("scalar", project(integer(42)))]), "type_mismatch");
  for (const index of [2n, 65536n, (1n << 48n) - 1n]) {
    rejects(
      module([fn("bounds", project(product(integer(1), integer(2)), index))]),
      "product_index",
    );
  }
  throws(
    () => analyze(module([fn("negative", project(product(unit, unit), -1n))])),
    RangeError,
  );
});

Deno.test("product types participate in occurs checks and pure-let polymorphism", () => {
  rejects(
    module([fn("recursive_type", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: local("value"),
      alternative: product(local("value"), unit),
    }, { parameter_type: null, exported: false })]),
    "infinite_type",
  );

  const analysis = analyze(module([fn("polymorphic", {
    $: "LetExpr",
    name: "pair",
    value: product(lambda(1n, local("argument")), unit),
    body: product(
      apply(project(local("pair")), integer(42)),
      apply(project(local("pair")), boolean(true)),
    ),
  }, { exported: false })]));
  equal(analysis.functions[0].result, productType(u32Type, boolType));

  rejects(
    module([fn("captured", {
      $: "LetExpr",
      name: "pair",
      value: product(local("value"), unit),
      body: product(
        apply(project(local("pair")), integer(42)),
        apply(project(local("pair")), boolean(true)),
      ),
    }, { parameter_type: null, exported: false })]),
    "type_mismatch",
  );
});

Deno.test("nominal constructor templates instantiate product payload types", () => {
  const wrapped: DataType = {
    identity: { $: "TypeId", module_name: "test", declaration: "Wrapped" },
    parameters: 1n,
    constructors: [{
      name: "Wrapped",
      payload: productType({ $: "ParameterTy", index: 0n }, boolType),
    }],
  };
  const analysis = analyze(module([fn("main", {
    $: "MatchExpr",
    values: [{
      $: "ConstructExpr",
      constructor: "Wrapped",
      payload: product(integer(42), boolean(true)),
    }],
    arms: [{
      patterns: [{
        $: "ConstructorPattern",
        constructor: "Wrapped",
        payload: { $: "BindingPattern", name: "pair" },
      }],
      body: project(local("pair")),
    }],
  })], { data_types: [wrapped] }));
  equal(analysis.functions[0].result, u32Type);
  rejects(
    module([], {
      data_types: [{
        ...wrapped,
        constructors: [{
          name: "Wrapped",
          payload: productType(unitType, { $: "ParameterTy", index: 1n }),
        }],
      }],
    }),
    "invalid_annotation",
  );
});

Deno.test("product creation preserves latent callback rows and projection does not discharge them", () => {
  const ask = operation("Reader.ask");
  const analysis = analyze(module([
    fn(
      "defer",
      product(
        lambda(1n, apply(local("value")), unitType),
        unit,
      ),
      { parameter_type: null, exported: false },
    ),
    fn(
      "read",
      apply(
        project(call("defer", { $: "OperationExpr", identity: ask.identity })),
      ),
    ),
  ], { operations: [ask] }));
  equal(analysis.functions[0].effect_row, emptyRow());
  equal(analysis.functions[1].effect_row.operations, [ask.identity]);
  const deferred = analysis.functions[0];
  ok(deferred.parameter.$ === "FunctionTy");
  ok(deferred.result.$ === "ProductTy");
  const action = deferred.result.elements[0];
  ok(action.$ === "FunctionTy");
  equal(action.effects.tail, deferred.parameter.effects.tail);

  rejects(
    module([fn("bad_let", {
      $: "LetExpr",
      name: "hidden",
      value: product(invoke(ask.identity), unit),
      body: unit,
    })], { operations: [ask] }),
    "let_effect",
  );
  rejects(
    module([], {
      operations: [ask],
      constants: [{
        name: "hidden",
        exported: false,
        annotation: null,
        value: product(unit, invoke(ask.identity)),
      }],
    }),
    "const_effect",
  );
});

Deno.test("pure callbacks inside products can be invoked alongside a declared effect", () => {
  const ask = operation("Reader.ask");
  const analysis = analyze(module([fn("read", {
    $: "UseExpr",
    name: "ignored",
    value: invoke(ask.identity),
    body: apply(project({ $: "ConstantExpr", name: "callbacks" })),
  })], {
    operations: [ask],
    constants: [{
      name: "callbacks",
      exported: false,
      annotation: null,
      value: product(lambda(1n, integer(42), unitType), unit),
    }],
  }));
  equal(analysis.functions[0].result, u32Type);
  equal(analysis.functions[0].effect_row.operations, [ask.identity]);
});

Deno.test("Foreign callbacks retain sealed effects inside annotated products", () => {
  const foreign = {
    $: "TypeId" as const,
    module_name: "blot:compiler",
    declaration: "Foreign",
  };
  const callback: Type = {
    $: "FunctionTy",
    parameter: unitType,
    result: u32Type,
    effects: { ...emptyRow(), operations: [foreign] },
  };
  const analysis = analyze(module([fn("call", apply(project(local("value"))), {
    parameter_type: productType(callback, unitType),
    exported: false,
  })]));
  equal(analysis.functions[0].effect_row.operations, [foreign]);
  rejects(
    module([fn("bad", {
      $: "LetExpr",
      name: "hidden",
      value: apply(project(local("value"))),
      body: unit,
    }, { parameter_type: productType(callback, unitType), exported: false })]),
    "let_effect",
  );
});

Deno.test("product dependency traversal validates duplicate nested lambdas", () => {
  rejects(
    module([fn(
      "duplicates",
      product(
        lambda(7n, integer(1)),
        lambda(7n, integer(2)),
      ),
      { exported: false },
    )]),
    "duplicate_lambda",
  );
});

Deno.test("product covariance preserves rows shared with a sibling callback input", () => {
  const types = compiled as unknown as {
    "types.close_generalized"(type: unknown, variables: unknown): unknown;
  };
  const row = {
    $: "EffectRow",
    operations: bendList([]),
    tail: { $: "RowVariable", index: 3n },
  };
  const scalar = { $: "U32Ty" };
  const action = {
    $: "FunctionTy",
    parameter: { $: "UnitTy" },
    result: scalar,
    effects: row,
  };
  const accepts = {
    $: "FunctionTy",
    parameter: action,
    result: scalar,
    effects: {
      $: "EffectRow",
      operations: bendList([]),
      tail: { $: "ClosedRow" },
    },
  };
  const original = { $: "ProductTy", elements: bendList([action, accepts]) };
  equal(
    types["types.close_generalized"](toBendModel(original), bendList([3n])),
    {
      $: "Done",
      value: toBendModel(original),
    },
  );
});
