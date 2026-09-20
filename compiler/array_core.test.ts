import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  CompilerError,
  type CoreModule,
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

const arrayType = (element: Type): Type => ({ $: "ArrayTy", element });
const array = (...elements: Expr[]): Expr => ({ $: "ArrayExpr", elements });
const get = (array: Expr, index: Expr = integer(0)): Expr => ({
  $: "ArrayGetExpr",
  array,
  index,
});
const set = (array: Expr, value: Expr, index: Expr = integer(0)): Expr => ({
  $: "ArraySetExpr",
  array,
  index,
  value,
});
const length = (array: Expr): Expr => ({ $: "ArrayLengthExpr", array });
const boolean = (value: boolean): Expr => ({ $: "BoolExpr", value });
const apply = (callee: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument: unit,
});
const lambda = (identity: bigint, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter: "ignored",
  parameter_type: unitType,
  result_type: null,
  body,
});

function rejects(source: CoreModule, code: string) {
  throws(
    () => analyze(source),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

Deno.test("arrays infer homogeneous nested element types and generic access signatures", () => {
  const analysis = analyze(module([
    fn("nested", array(array(integer(1)), array(integer(2), integer(3))), {
      exported: false,
    }),
    fn("first", get(local("value")), { parameter_type: null, exported: false }),
    fn("number", call("first", array(integer(42)))),
    fn("truth", call("first", array(boolean(true)))),
    fn("size", length(local("value")), {
      parameter_type: null,
      exported: false,
    }),
  ]));
  equal(analysis.functions[0].result, arrayType(arrayType(u32Type)));
  const first = analysis.functions[1];
  ok(first.parameter.$ === "ArrayTy");
  equal(first.parameter.element, first.result);
  equal(first.variables.length, 1);
  equal(analysis.functions[2].result, u32Type);
  equal(analysis.functions[3].result, boolType);
  equal(analysis.functions[4].result, u32Type);
});

Deno.test("empty immutable arrays generalize their element type and annotations constrain it", () => {
  const analysis = analyze(module([
    fn("numbers", {
      $: "SourceExpr",
      offset: 0n,
      annotation: { $: "Some", value: arrayType(u32Type) },
      value: { $: "ConstantExpr", name: "empty" },
    }, { exported: false }),
    fn("truths", {
      $: "SourceExpr",
      offset: 0n,
      annotation: { $: "Some", value: arrayType(boolType) },
      value: { $: "ConstantExpr", name: "empty" },
    }, { exported: false }),
    fn("known", array(), { result_type: arrayType(unitType), exported: false }),
  ], {
    constants: [{
      name: "empty",
      exported: false,
      annotation: null,
      value: array(),
    }],
  }));
  equal(analysis.functions.map((entry) => entry.result), [
    arrayType(u32Type),
    arrayType(boolType),
    arrayType(unitType),
  ]);
  equal(analysis.constants[0].value, { $: "ArrayValue", elements: [] });
});

Deno.test("array get, set, and length reject nonarrays, non-U32 indexes, and heterogeneous values", () => {
  for (
    const expression of [
      get(integer(1)),
      set(integer(1), integer(2)),
      length(integer(1)),
    ]
  ) {
    rejects(module([fn("bad", expression)]), "type_mismatch");
  }
  for (
    const expression of [
      get(array(integer(1)), boolean(false)),
      set(array(integer(1)), integer(2), boolean(true)),
      array(integer(1), boolean(true)),
      set(array(integer(1)), boolean(true)),
    ]
  ) {
    rejects(module([fn("bad", expression)]), "type_mismatch");
  }
  rejects(
    module([fn("recursive", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: local("value"),
      alternative: array(local("value")),
    }, { parameter_type: null, exported: false })]),
    "infinite_type",
  );
});

Deno.test("immutable set preserves a fixed element type without constraining array length", () => {
  const analysis = analyze(module([
    fn("replace", set(local("value"), integer(42)), {
      parameter_type: null,
      exported: false,
    }),
    fn("left", call("replace", array(integer(1))), { exported: false }),
    fn("right", call("replace", array(integer(1), integer(2), integer(3))), {
      exported: false,
    }),
  ]));
  for (const entry of analysis.functions) {
    equal(entry.result, arrayType(u32Type));
  }
  equal(analysis.functions[0].parameter, arrayType(u32Type));
});

Deno.test("array literals carry element evaluation effects but not stored callback effects", () => {
  const ask = operation("Reader.ask");
  rejects(
    module([fn("bad_let", {
      $: "LetExpr",
      name: "hidden",
      value: array(invoke(ask.identity)),
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
        value: array(invoke(ask.identity)),
      }],
    }),
    "const_effect",
  );
  const analysis = analyze(module([
    fn("defer", array(lambda(1n, apply(local("value")))), {
      parameter_type: null,
      exported: false,
    }),
    fn(
      "read",
      apply(get(call("defer", { $: "OperationExpr", identity: ask.identity }))),
    ),
  ], { operations: [ask] }));
  equal(analysis.functions[0].effect_row, emptyRow());
  equal(analysis.functions[1].effect_row.operations, [ask.identity]);
  const deferred = analysis.functions[0];
  ok(deferred.parameter.$ === "FunctionTy");
  ok(
    deferred.result.$ === "ArrayTy" &&
      deferred.result.element.$ === "FunctionTy",
  );
  equal(deferred.result.element.effects.tail, deferred.parameter.effects.tail);
});

Deno.test("pure callbacks in arrays can be weakened alongside other effects", () => {
  const ask = operation("Reader.ask");
  const analysis = analyze(module([fn("read", {
    $: "UseExpr",
    name: "ignored",
    value: invoke(ask.identity),
    body: apply(get({ $: "ConstantExpr", name: "callbacks" })),
  })], {
    operations: [ask],
    constants: [{
      name: "callbacks",
      exported: false,
      annotation: null,
      value: array(lambda(1n, integer(42))),
    }],
  }));
  equal(analysis.functions[0].result, u32Type);
  equal(analysis.functions[0].effect_row.operations, [ask.identity]);
});

Deno.test("array dependency traversal validates nested lambdas and latent row annotation kinds", () => {
  rejects(
    module([
      fn("duplicates", array(lambda(7n, integer(1)), lambda(7n, integer(2))), {
        exported: false,
      }),
    ]),
    "duplicate_lambda",
  );
  const bad: Type = arrayType({ $: "ParameterTy", index: 0n });
  rejects(
    module([fn("unused", unit, { exported: false, parameter_type: bad })]),
    "invalid_annotation",
  );
});
