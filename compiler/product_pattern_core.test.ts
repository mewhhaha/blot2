import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";
import {
  analyze,
  CompilerError,
  type CoreModule,
  type DataType,
  type Expr,
  type Pattern,
} from "./host.ts";
import {
  boolType,
  call,
  fn,
  integer,
  local,
  module,
  operation,
  u32Type,
  unit,
} from "./fixtures.ts";

const wildcard: Pattern = { $: "WildcardPattern" };
const bind = (name: string): Pattern => ({ $: "BindingPattern", name });
const tuplePattern = (...elements: Pattern[]): Pattern => ({
  $: "ProductPattern",
  elements,
});
const tuple = (...elements: Expr[]): Expr => ({ $: "ProductExpr", elements });
const match = (pattern: Pattern, body: Expr): Expr => ({
  $: "MatchExpr",
  values: [local("value")],
  arms: [{ patterns: [pattern], body }],
});
const boolPattern = (value: boolean): Pattern => ({ $: "BoolPattern", value });

function rejects(source: CoreModule, code: string) {
  throws(() => analyze(source), (error) => {
    ok(error instanceof CompilerError, String(error));
    equal(error.code, code, error.message);
    return true;
  });
}

Deno.test("tuple patterns infer unknown shape and preserve polymorphic field types", () => {
  const result = analyze(module([
    fn("first", match(tuplePattern(bind("first"), wildcard), local("first")), {
      parameter_type: null,
      exported: false,
    }),
    fn("number", call("first", tuple(integer(42), unit))),
    fn(
      "truth",
      call("first", tuple({ $: "BoolExpr", value: true }, integer(3))),
    ),
  ]));
  const first = result.functions[0];
  ok(first.parameter.$ === "ProductTy");
  equal(first.parameter.elements.length, 2);
  equal(first.result, first.parameter.elements[0]);
  equal(result.functions[1].result, u32Type);
  equal(result.functions[2].result, boolType);
});

Deno.test("tuple patterns nest through nominal constructor payloads", () => {
  const wrapped: DataType = {
    identity: { $: "TypeId", module_name: "patterns", declaration: "Wrapped" },
    parameters: 1n,
    constructors: [{
      name: "Wrapped",
      payload: { $: "ParameterTy", index: 0n },
    }],
  };
  const result = analyze(module([fn(
    "unpack",
    match(
      tuplePattern({
        $: "ConstructorPattern",
        constructor: "Wrapped",
        payload: tuplePattern(bind("answer"), wildcard),
      }, wildcard),
      {
        $: "ScalarExpr",
        operator: { $: "Add" },
        left: local("answer"),
        right: integer(1),
      },
    ),
    { parameter_type: null, exported: false },
  )], { data_types: [wrapped] }));
  const parameter = result.functions[0].parameter;
  ok(parameter.$ === "ProductTy");
  const nominal = parameter.elements[0];
  ok(nominal.$ === "AppliedTy");
  equal(nominal.identity, wrapped.identity);
  const payload = nominal.arguments[0];
  ok(payload.$ === "ProductTy");
  equal(payload.elements[0], u32Type);
  equal(result.functions[0].result, u32Type);
});

Deno.test("tuple patterns reject malformed arity and non-product scrutinees", () => {
  for (const elements of [[], [wildcard]]) {
    rejects(
      module([fn("invalid", match(tuplePattern(...elements), unit), {
        parameter_type: null,
      })]),
      "product_arity",
    );
  }
  rejects(
    module([fn("invalid", match(tuplePattern(wildcard, wildcard), unit), {
      parameter_type: { $: "ProductTy", elements: [u32Type, u32Type, u32Type] },
    })]),
    "product_arity",
  );
  rejects(
    module([fn("invalid", match(tuplePattern(wildcard, wildcard), unit), {
      parameter_type: u32Type,
    })]),
    "type_mismatch",
  );
  rejects(
    module([fn("invalid", {
      $: "MatchExpr",
      values: [local("value")],
      arms: [
        { patterns: [tuplePattern(wildcard, wildcard)], body: unit },
        { patterns: [tuplePattern(wildcard, wildcard, wildcard)], body: unit },
      ],
    }, { parameter_type: null })]),
    "product_arity",
  );
});

Deno.test("tuple pattern bindings must be unique within nested fields and across columns", () => {
  rejects(
    module([fn(
      "duplicate",
      match(
        tuplePattern(bind("same"), tuplePattern(wildcard, bind("same"))),
        unit,
      ),
      { parameter_type: null },
    )]),
    "duplicate_pattern_binding",
  );
  rejects(
    module([fn("duplicate", {
      $: "MatchExpr",
      values: [tuple(integer(1), integer(2)), integer(3)],
      arms: [{
        patterns: [tuplePattern(bind("same"), wildcard), bind("same")],
        body: unit,
      }],
    })]),
    "duplicate_pattern_binding",
  );
  rejects(
    module([fn("duplicate", {
      $: "BlockExpr",
      label: 1n,
      body: {
        $: "GuardExpr",
        pattern: tuplePattern(bind("same"), bind("same")),
        value: tuple(integer(1), integer(2)),
        alternative: { $: "ReturnExpr", label: 1n, value: unit },
        body: unit,
      },
    })]),
    "duplicate_pattern_binding",
  );
});

Deno.test("tuple coverage keeps correlations within fields and other scrutinees", () => {
  const diagonal: Expr = {
    $: "MatchExpr",
    values: [local("value")],
    arms: [true, false].map((value) => ({
      patterns: [tuplePattern(boolPattern(value), boolPattern(value))],
      body: integer(1),
    })),
  };
  rejects(
    module([fn("diagonal", diagonal, { parameter_type: null })]),
    "non_exhaustive_match",
  );
  const complete = analyze(module([fn("complete", {
    ...diagonal,
    arms: [...diagonal.arms, {
      patterns: [tuplePattern(wildcard, wildcard)],
      body: integer(0),
    }],
  }, { parameter_type: null, exported: false })]));
  equal(complete.functions[0].result, u32Type);
});

Deno.test("tuple destructuring preserves latent operation requirements", () => {
  const ask = operation("Reader.ask");
  const invoke: Expr = match(tuplePattern(bind("action"), wildcard), {
    $: "ApplyExpr",
    callee: local("action"),
    argument: unit,
  });
  const read = call(
    "invoke",
    tuple({ $: "OperationExpr", identity: ask.identity }, unit),
  );
  const functions = [
    fn("invoke", invoke, { parameter_type: null, exported: false }),
    fn("read", read),
  ];
  const result = analyze(module(functions, { operations: [ask] }));
  equal(result.functions[1].effect_row.operations, [ask.identity]);
  rejects(
    module([
      functions[0],
      fn("hidden", {
        $: "LetExpr",
        name: "hidden",
        value: read,
        body: local("hidden"),
      }),
    ], { operations: [ask] }),
    "let_effect",
  );
});

Deno.test("tuple matrix coverage agrees with finite correlated field enumeration", () => {
  const coverage = compiled as unknown as {
    "patterns.coverage"(fuel: bigint, work: unknown, types: unknown): unknown;
  };
  let seed = 937;
  const random = (bound: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return (seed >>> 8) % bound;
  };
  type Bit = boolean | null;
  const wire = (value: Bit): unknown =>
    value === null ? { $: "WildcardPattern" } : { $: "BoolPattern", value };
  for (let trial = 0; trial < 256; trial++) {
    const rows = Array.from(
      { length: random(12) },
      () =>
        Array.from({ length: 3 }, (): Bit => {
          const value = random(3);
          return value === 2 ? null : value === 1;
        }),
    );
    const complete = Array.from({ length: 8 }, (_, mask) => mask).every((
      mask,
    ) =>
      rows.some((row) =>
        row.every((pattern, column) =>
          pattern === null || pattern === ((mask & (1 << column)) !== 0)
        )
      )
    );
    const tupleType = {
      $: "ProductTy",
      elements: bendList([{ $: "BoolTy" }, { $: "BoolTy" }]),
    };
    equal(
      coverage["patterns.coverage"](65536n, {
        $: "Cover",
        inferred_types: bendList([tupleType, { $: "BoolTy" }]),
        rows: bendList(rows.map(([first, second, third]) =>
          bendList([
            {
              $: "ProductPattern",
              elements: bendList([wire(first), wire(second)]),
            },
            wire(third),
          ])
        )),
      }, bendList([])),
      { $: "Done", value: complete },
      `tuple matrix ${trial}`,
    );
  }
});
