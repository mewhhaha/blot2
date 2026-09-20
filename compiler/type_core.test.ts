import { deepStrictEqual as equal, throws } from "node:assert/strict";
import {
  analyze,
  CompilerError,
  type DataType,
  type Expr,
  type MatchArm,
} from "./host.ts";
import {
  add,
  boolType,
  call,
  fn,
  integer,
  local,
  module,
  position,
  read,
  u32Type,
  unit,
} from "./fixtures.ts";

const lambda = (identity: bigint, parameter: string, body: Expr): Expr => ({
  $: "LambdaExpr",
  identity,
  parameter,
  parameter_type: null,
  result_type: null,
  body,
});
const apply = (callee: Expr, argument: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});
const boolean = (value: boolean): Expr => ({ $: "BoolExpr", value });
const ctor = (constructor: string, payload: Expr | null = null): Expr => ({
  $: "ConstructExpr",
  constructor,
  payload,
});
const maybe: DataType = {
  identity: { $: "TypeId", module_name: "test", declaration: "Maybe" },
  parameters: 1n,
  constructors: [
    { name: "Some", payload: { $: "ParameterTy", index: 0n } },
    { name: "Nothing", payload: null },
  ],
};

function rejects(body: Expr, code: string, options = {}) {
  throws(
    () => analyze(module([fn("test", body)], options)),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

Deno.test("pure local let instantiates a fresh scheme at each use", () => {
  const checked = analyze(module([fn("test", {
    $: "LetExpr",
    name: "identity",
    value: lambda(1n, "x", local("x")),
    body: {
      $: "SequenceExpr",
      first: apply(local("identity"), boolean(true)),
      next: apply(local("identity"), integer(42)),
    },
  })]));
  equal(checked.functions[0].result, u32Type);
});

Deno.test("let does not generalize variables captured from its environment", () => {
  throws(
    () =>
      analyze(module([fn("test", {
        $: "LetExpr",
        name: "same",
        value: local("value"),
        body: {
          $: "SequenceExpr",
          first: apply(local("same"), boolean(true)),
          next: apply(local("same"), integer(42)),
        },
      }, { parameter_type: null })])),
    (error) => error instanceof CompilerError && error.code === "type_mismatch",
  );
});

Deno.test("self application is rejected by the occurs check", () => {
  rejects(lambda(2n, "x", apply(local("x"), local("x"))), "infinite_type");
});

Deno.test("forward references generalize by dependency component, not source order", () => {
  const checked = analyze(module([
    fn("number", call("identity", integer(42))),
    fn("truth", call("identity", boolean(true))),
    fn("identity", local("value"), { parameter_type: null, exported: false }),
  ]));
  equal(checked.functions[0].result, u32Type);
  equal(checked.functions[1].result, boolType);
  equal(checked.functions[2].variables.length, 1);
});

Deno.test("mutually recursive functions share monotypes inside their component", () => {
  const checked = analyze(module([
    fn("left", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: local("value"),
      alternative: call("right", local("value")),
    }, { parameter_type: null, exported: false }),
    fn("right", call("left", local("value")), {
      parameter_type: null,
      exported: false,
    }),
    fn("number", call("left", integer(42))),
    fn("truth", call("right", boolean(true))),
  ]));
  equal(checked.functions[2].result, u32Type);
  equal(checked.functions[3].result, boolType);
  equal(checked.functions[0].variables.length, 1);
});

Deno.test("repeated recursive dependencies form one inference component", () => {
  const checked = analyze(module([
    fn("repeat", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: local("value"),
      alternative: {
        $: "SequenceExpr",
        first: call("repeat", local("value")),
        next: call("repeat", local("value")),
      },
    }, { parameter_type: null, exported: false }),
    fn("number", call("repeat", integer(42))),
    fn("truth", call("repeat", boolean(true))),
  ]));
  equal(checked.functions[1].result, u32Type);
  equal(checked.functions[2].result, boolType);
  equal(checked.functions[0].variables.length, 1);
});

Deno.test("long forward chains generalize dependency-first without repeated SCC search", () => {
  const length = 64;
  const chain = Array.from({ length }, (_, index) =>
    fn(
      `chain_${index}`,
      index === length - 1
        ? local("value")
        : call(`chain_${index + 1}`, local("value")),
      { parameter_type: null, exported: false },
    ));
  const checked = analyze(module([
    fn("number", call("chain_0", integer(42))),
    fn("truth", call("chain_0", boolean(true))),
    ...chain,
  ]));
  equal(checked.functions[0].result, u32Type);
  equal(checked.functions[1].result, boolType);
  for (const inferred of checked.functions.slice(2)) {
    equal(inferred.variables.length, 1);
  }
});

Deno.test("a recursive component waits for its shared external generic dependency", () => {
  const checked = analyze(module([
    fn("number", call("left", integer(42))),
    fn("truth", call("right", boolean(true))),
    fn("left", {
      $: "IfExpr",
      condition: boolean(true),
      consequent: call("identity", local("value")),
      alternative: call("right", local("value")),
    }, { parameter_type: null, exported: false }),
    fn("right", call("left", local("value")), {
      parameter_type: null,
      exported: false,
    }),
    fn("identity", local("value"), { parameter_type: null, exported: false }),
  ]));
  equal(checked.functions[0].result, u32Type);
  equal(checked.functions[1].result, boolType);
  for (const inferred of checked.functions.slice(2)) {
    equal(inferred.variables.length, 1);
  }
});

Deno.test("constructor payloads instantiate independently and infer nominal arguments", () => {
  const checked = analyze(module([
    fn("number", ctor("Some", integer(42))),
    fn("truth", ctor("Some", boolean(true))),
  ], { data_types: [maybe] }));
  equal(checked.functions[0].result, {
    $: "AppliedTy",
    identity: maybe.identity,
    arguments: [u32Type],
  });
  equal(checked.functions[1].result, {
    $: "AppliedTy",
    identity: maybe.identity,
    arguments: [boolType],
  });
});

Deno.test("nested constructor coverage checks payloads, not only outer tags", () => {
  rejects(
    {
      $: "MatchExpr",
      value: ctor("Some", boolean(false)),
      arms: [
        {
          pattern: {
            $: "ConstructorPattern",
            constructor: "Some",
            payload: { $: "BoolPattern", value: true },
          },
          body: integer(1),
        },
        {
          pattern: {
            $: "ConstructorPattern",
            constructor: "Nothing",
            payload: null,
          },
          body: integer(0),
        },
      ],
    },
    "non_exhaustive_match",
    { data_types: [maybe] },
  );
});

Deno.test("full Bool payload coverage plus other constructors is exhaustive", () => {
  const arms: MatchArm[] = [true, false].map((value) => ({
    pattern: {
      $: "ConstructorPattern" as const,
      constructor: "Some",
      payload: { $: "BoolPattern" as const, value },
    },
    body: integer(value ? 1 : 0),
  }));
  arms.push({
    pattern: {
      $: "ConstructorPattern" as const,
      constructor: "Nothing",
      payload: null,
    },
    body: integer(0),
  });
  const checked = analyze(module([fn("test", {
    $: "MatchExpr",
    value: ctor("Some", boolean(false)),
    arms,
  })], { data_types: [maybe] }));
  equal(checked.functions[0].result, u32Type);
});

Deno.test("constructor arity and type template bounds are checked", () => {
  rejects(ctor("Some"), "constructor_arity", { data_types: [maybe] });
  rejects(ctor("Nothing", integer(1)), "constructor_arity", {
    data_types: [maybe],
  });
  rejects(unit, "invalid_annotation", {
    data_types: [{
      ...maybe,
      constructors: [{
        name: "Invalid",
        payload: { $: "ParameterTy", index: 1n },
      }],
    }],
  });
});

Deno.test("latent effects cannot disappear through pure function values", () => {
  rejects(
    lambda(3n, "x", read(position.identity)),
    "effectful_function_value",
    {
      descriptors: [position],
    },
  );
  throws(
    () =>
      analyze(module([
        fn("read_position", read(position.identity), { exported: false }),
        fn("reference", { $: "FunctionExpr", name: "read_position" }),
      ], { descriptors: [position] })),
    (error) =>
      error instanceof CompilerError &&
      error.code === "effectful_function_value",
  );
});

Deno.test("guard fallback must exit and pattern names do not leak into it", () => {
  rejects({
    $: "GuardExpr",
    pattern: { $: "BindingPattern", name: "bound" },
    value: integer(1),
    alternative: integer(0),
    body: local("bound"),
  }, "guard_fallthrough");
  rejects({
    $: "BlockExpr",
    label: 1n,
    body: {
      $: "GuardExpr",
      pattern: { $: "BindingPattern", name: "bound" },
      value: integer(1),
      alternative: { $: "ReturnExpr", label: 1n, value: local("bound") },
      body: local("bound"),
    },
  }, "unknown_name");
});

Deno.test("a nested block propagating an outer return remains non-returning", () => {
  const checked = analyze(module([fn("test", {
    $: "BlockExpr",
    label: 10n,
    body: {
      $: "GuardExpr",
      pattern: { $: "U32Pattern", value: 0 },
      value: integer(1),
      alternative: {
        $: "BlockExpr",
        label: 11n,
        body: { $: "ReturnExpr", label: 10n, value: integer(42) },
      },
      body: integer(0),
    },
  })]));
  equal(checked.functions[0].result, u32Type);
});

Deno.test("a lambda cannot return into the do block that created it", () => {
  rejects({
    $: "BlockExpr",
    label: 20n,
    body: lambda(4n, "x", {
      $: "ReturnExpr",
      label: 20n,
      value: integer(42),
    }),
  }, "invalid_return");
});

Deno.test("duplicate lambda identities cannot alias different closure bodies", () => {
  rejects({
    $: "SequenceExpr",
    first: lambda(5n, "x", local("x")),
    next: lambda(5n, "x", add(local("x"), integer(1))),
  }, "duplicate_lambda");
});

Deno.test("internal inference types cannot be supplied as source annotations", () => {
  for (
    const annotation of [
      { $: "VariableTy" as const, index: 0n },
      { $: "NeverTy" as const },
      { $: "ParameterTy" as const, index: 0n },
    ]
  ) {
    rejects({
      $: "SourceExpr",
      offset: 0n,
      annotation: { $: "Some", value: annotation },
      value: integer(1),
    }, "invalid_annotation");
  }
});

Deno.test("resolved function and constant references preserve definition kinds", () => {
  const constants = [{
    name: "stored",
    exported: false,
    annotation: null,
    value: integer(42),
  }];
  rejects({ $: "FunctionExpr", name: "stored" }, "unknown_function", {
    constants,
  });
  rejects(call("stored"), "unknown_function", { constants });
  throws(
    () =>
      analyze(module([
        fn("named", integer(42)),
        fn("wrong_kind", { $: "ConstantExpr", name: "named" }),
      ])),
    (error) => error instanceof CompilerError && error.code === "unknown_name",
  );
});

Deno.test("unreachable local returns cannot make an escaping block reachable", () => {
  const checked = analyze(module([fn("test", {
    $: "BlockExpr",
    label: 30n,
    body: {
      $: "GuardExpr",
      pattern: { $: "U32Pattern", value: 0 },
      value: integer(1),
      alternative: {
        $: "BlockExpr",
        label: 31n,
        body: {
          $: "SequenceExpr",
          first: { $: "ReturnExpr", label: 30n, value: integer(42) },
          next: { $: "ReturnExpr", label: 31n, value: boolean(true) },
        },
      },
      body: integer(0),
    },
  })]));
  equal(checked.functions[0].result, u32Type);
});
