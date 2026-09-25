import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Expr,
  type ScalarOp,
} from "./host.ts";
import {
  add,
  boolType,
  call,
  fn,
  integer,
  local,
  module,
  scalarExample,
  u32Type,
  unit,
  unitType,
} from "./fixtures.ts";

function rejects(source: CoreModule, code: string, options = {}) {
  throws(
    () => analyze(source, options),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

async function instantiate(source: CoreModule) {
  const artifact = compile(source);
  ok(WebAssembly.validate(artifact.bytes), "Bend must emit valid Wasm");
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  return {
    ...artifact,
    exports: instance.exports as Record<string, (value: number) => number>,
  };
}

Deno.test("Bend infers a parameter, evaluates a const, and emits executable Wasm", async () => {
  const compiled = await instantiate(scalarExample);
  equal(compiled.exports.increment(41), 42);
  equal(compiled.exports.answer(0), 42);
  equal(compiled.analysis.functions[0].parameter, u32Type);
  equal(compiled.analysis.functions[0].result, u32Type);
  equal(compiled.analysis.constants, [{
    name: "base",
    value: { $: "U32Value", value: 41 },
  }]);
});

Deno.test("core module marshalling accepts a for ever expression", () => {
  const source = module([fn("loop", {
    $: "ForeverExpr",
    state: "state",
    initial: integer(0),
    body: add(local("state"), integer(1)),
  }, { exported: false })]);
  equal(analyze(source).functions[0].name, "loop");
});

Deno.test("forward calls instantiate generic parameters and results", async () => {
  const compiled = await instantiate(module([
    fn("entry", call("identity", integer(42))),
    fn("identity", local("value"), { parameter_type: null, exported: false }),
  ]));
  equal(compiled.exports.entry(0), 42);
  equal(compiled.analysis.functions[0].result, u32Type);
  equal(compiled.analysis.functions[1].parameter.$, "VariableTy");
  equal(
    compiled.analysis.functions[1].result,
    compiled.analysis.functions[1].parameter,
  );
  equal(compiled.analysis.functions[1].variables.length, 1);
  equal(Object.keys(compiled.exports), ["entry"]);
});

Deno.test("let shadowing uses the old binding on its RHS", async () => {
  const source = module([fn("shadow", {
    $: "LetExpr",
    name: "value",
    value: add(local("value"), integer(1)),
    body: add(local("value"), local("value")),
  }, { parameter_type: u32Type })]);
  equal((await instantiate(source)).exports.shadow(20), 42);
});

Deno.test("rejects type mismatches in annotations, calls, operations, and branches", () => {
  rejects(
    module([fn("wrong_result", integer(1), { result_type: boolType })]),
    "type_mismatch",
  );
  rejects(
    module([
      fn("wrong_parameter", add(local("value"), integer(1)), {
        parameter_type: boolType,
      }),
    ]),
    "type_mismatch",
  );
  rejects(
    module([
      fn("wrong_call", call("identity", integer(1))),
      fn("identity", local("value"), { parameter_type: boolType }),
    ]),
    "type_mismatch",
  );
  rejects(
    module([
      fn("wrong_condition", {
        $: "IfExpr",
        condition: integer(1),
        consequent: unit,
        alternative: unit,
      }),
    ]),
    "type_mismatch",
  );
  rejects(
    module([
      fn("wrong_branch", {
        $: "IfExpr",
        condition: { $: "BoolExpr", value: true },
        consequent: integer(1),
        alternative: unit,
      }),
    ]),
    "type_mismatch",
  );
});

Deno.test("reports unknown and duplicate names without inventing bindings", () => {
  rejects(module([fn("unknown", local("missing"))]), "unknown_name");
  rejects(
    module([fn("unknown", { $: "ConstantExpr", name: "missing" })]),
    "unknown_name",
  );
  rejects(module([fn("unknown", call("missing"))]), "unknown_function");
  rejects(module([fn("same", unit), fn("same", unit)]), "duplicate_name");
  rejects(
    module([fn("same", unit)], {
      constants: [{
        name: "same",
        exported: false,
        annotation: null,
        value: unit,
      }],
    }),
    "duplicate_name",
  );
});

Deno.test("generic globals instantiate independently and private polymorphism has a word ABI", async () => {
  const identity = fn("identity", local("value"), {
    parameter_type: null,
    exported: false,
  });
  const compiled = await instantiate(module([
    identity,
    fn("number", call("identity", integer(1))),
    fn("boolean", call("identity", { $: "BoolExpr", value: true })),
  ]));
  equal(compiled.exports.number(0), 1);
  equal(compiled.exports.boolean(0), 1);
  equal(compiled.analysis.functions[0].variables.length, 1);
  const unresolved = module([identity]);
  equal(analyze(unresolved).functions[0].parameter.$, "VariableTy");
  ok(WebAssembly.validate(compile(unresolved).bytes));
  throws(
    () => compile(module([{ ...identity, exported: true }])),
    (error) => error instanceof CompilerError && error.code === "backend_type",
  );
});

Deno.test("const evaluation supports ordinary pure functions and forward references", () => {
  const source = module([
    fn("twice", add(local("value"), local("value")), { parameter_type: null }),
  ], {
    constants: [
      {
        name: "answer",
        exported: false,
        annotation: null,
        value: call("twice", { $: "ConstantExpr", name: "half" }),
      },
      { name: "half", exported: false, annotation: null, value: integer(21) },
    ],
  });
  equal(analyze(source).constants[0], {
    name: "answer",
    value: { $: "U32Value", value: 42 },
  });
});

Deno.test("const evaluation cannot capture a caller's locals", () => {
  const source = module([fn("bad", local("hidden"))], {
    constants: [{
      name: "answer",
      exported: false,
      annotation: null,
      value: {
        $: "LetExpr",
        name: "hidden",
        value: integer(42),
        body: call("bad"),
      },
    }],
  });
  rejects(source, "unknown_name");
});

Deno.test("const fuel counts siblings and is shared across definitions", () => {
  const source = module([], {
    constants: [{
      name: "sum",
      exported: false,
      annotation: null,
      value: add(integer(20), integer(22)),
    }],
  });
  rejects(source, "const_budget", { const_steps: 2n });
  equal(analyze(source, { const_steps: 3n }).remaining_steps, 0n);
  const siblings = module([], {
    constants: [
      { name: "a", exported: false, annotation: null, value: integer(1) },
      { name: "b", exported: false, annotation: null, value: integer(2) },
    ],
  });
  rejects(siblings, "const_budget", { const_steps: 1n });
  equal(analyze(siblings, { const_steps: 2n }).remaining_steps, 0n);
});

Deno.test("recursive consts stop at the budget but an unselected pure branch is not evaluated", () => {
  const forever = fn("forever", call("forever"), {
    result_type: u32Type,
    exported: false,
  });
  rejects(
    module([forever], {
      constants: [{
        name: "loop",
        exported: false,
        annotation: null,
        value: call("forever"),
      }],
    }),
    "const_budget",
    { const_steps: 100n },
  );
  rejects(
    module([], {
      constants: [{
        name: "cycle",
        exported: false,
        annotation: u32Type,
        value: { $: "ConstantExpr", name: "cycle" },
      }],
    }),
    "const_budget",
    { const_steps: 100n },
  );
  const source = module([forever], {
    constants: [{
      name: "selected",
      exported: false,
      annotation: null,
      value: {
        $: "IfExpr",
        condition: { $: "BoolExpr", value: true },
        consequent: integer(42),
        alternative: call("forever"),
      },
    }],
  });
  equal(analyze(source, { const_steps: 3n }).constants[0].value, {
    $: "U32Value",
    value: 42,
  });
});

Deno.test("all scalar operations agree between const evaluation and Wasm", async () => {
  const operators: ScalarOp["$"][] = [
    "Add",
    "Subtract",
    "Multiply",
    "Equal",
    "LessThan",
  ];
  for (const operator of operators) {
    for (
      const [left, right] of [
        [0, 1],
        [0xFFFFFFFF, 2],
        [0x80000000, 0x7FFFFFFF],
        [42, 42],
      ]
    ) {
      const body: Expr = {
        $: "ScalarExpr",
        operator: { $: operator },
        left: integer(left),
        right: integer(right),
      };
      const source = module([fn("operation", body)], {
        constants: [{
          name: "expected",
          exported: false,
          annotation: null,
          value: body,
        }],
      });
      const compiled = await instantiate(source);
      const expected = compiled.analysis.constants[0].value;
      ok(expected.$ === "U32Value" || expected.$ === "BoolValue");
      equal(compiled.exports.operation(0) >>> 0, Number(expected.value));
    }
  }
});

Deno.test("i32 constants preserve the full U32 bit pattern at signed LEB boundaries", async () => {
  const values = [
    0,
    63,
    64,
    127,
    128,
    16383,
    16384,
    0x7FFFFFFF,
    0x80000000,
    0xFFFFFFFF,
  ];
  const compiled = await instantiate(
    module(values.map((value, index) => fn(`value_${index}`, integer(value)))),
  );
  values.forEach((value, index) =>
    equal(compiled.exports[`value_${index}`](0) >>> 0, value)
  );
});

Deno.test("Wasm conditionals and sequential lets preserve immutable local scopes", async () => {
  const source = module([fn("choose", {
    $: "LetExpr",
    name: "outer",
    value: integer(20),
    body: {
      $: "IfExpr",
      condition: local("value"),
      consequent: {
        $: "LetExpr",
        name: "inner",
        value: integer(22),
        body: add(local("outer"), local("inner")),
      },
      alternative: {
        $: "SequenceExpr",
        first: integer(999),
        next: add(local("outer"), integer(1)),
      },
    },
  }, { parameter_type: boolType })]);
  const compiled = await instantiate(source);
  equal(compiled.exports.choose(1), 42);
  equal(compiled.exports.choose(0), 21);
});

Deno.test("section lengths, export names, and call indices use multibyte LEB and UTF-8", async () => {
  const functions = Array.from(
    { length: 130 },
    (_, index) => fn(`helper_${index}`, integer(index), { exported: false }),
  );
  const exportName = "åλ🎮".repeat(30);
  const compiled = await instantiate(
    module([...functions, fn(exportName, call("helper_129"))]),
  );
  equal(compiled.exports[exportName](0), 129);
});

Deno.test("repeated compilation is deterministic and does not mutate the core input", () => {
  const before = structuredClone(scalarExample);
  equal(compile(scalarExample), compile(scalarExample));
  equal(scalarExample, before);
});

Deno.test("a large emitted byte list crosses the FFI without recursive host traversal", async () => {
  let expression = integer(1);
  for (let depth = 0; depth < 10; depth++) {
    expression = add(expression, expression);
  }
  const compiled = await instantiate(module([fn("balanced", expression)]));
  equal(compiled.exports.balanced(0), 1024);
});

Deno.test("FFI rejects out-of-domain U32 literals, Nat budgets, and malformed names", () => {
  for (const value of [-1, 0x100000000, 1.5, NaN, Infinity]) {
    throws(
      () => compile(module([fn("invalid", integer(value))])),
      /U32 literal out of range/,
    );
  }
  throws(() => analyze(scalarExample, { const_steps: -1n }), /const_steps/);
  throws(
    () => analyze(scalarExample, { const_steps: 0x1000000000000n }),
    /const_steps/,
  );
  throws(() => compile(module([fn("\uD800", unit)])), /valid Unicode/);
  throws(() =>
    compile(module([], {
      constants: [{
        name: "\uD800",
        exported: true,
        annotation: null,
        value: unit,
      }],
    })), /valid Unicode/);
});

Deno.test("FFI validates nested patterns, type parameters, lambda identities, and block labels", () => {
  for (const invalid of [-1n, 0x1000000000000n]) {
    const expressions: Expr[] = [
      {
        $: "LambdaExpr",
        identity: invalid,
        parameter: "value",
        parameter_type: null,
        result_type: null,
        body: local("value"),
      },
      { $: "BlockExpr", label: invalid, body: unit },
      { $: "ReturnExpr", label: invalid, value: unit },
      {
        $: "SourceExpr",
        offset: invalid,
        annotation: { $: "None" },
        value: unit,
      },
    ];
    for (const expression of expressions) {
      throws(
        () => analyze(module([fn("invalid", expression)])),
        /must be a Nat/,
      );
    }
    throws(() =>
      analyze(module([], {
        data_types: [{
          identity: { $: "TypeId", module_name: "test", declaration: "Box" },
          parameters: invalid,
          constructors: [],
        }],
      })), /must be a Nat/);
    throws(() =>
      analyze(module([fn("invalid", unit, {
        parameter_type: { $: "ParameterTy", index: invalid },
      })])), /must be a Nat/);
  }
  for (const value of [-1, 0x100000000, NaN]) {
    throws(() =>
      analyze(module([fn("invalid", {
        $: "MatchExpr",
        values: [integer(0)],
        arms: [{ patterns: [{ $: "U32Pattern", value }], body: unit }],
      })])), /U32 literal out of range/);
  }
  throws(() =>
    analyze(module([fn("invalid", {
      $: "ConstructExpr",
      constructor: "\uD800",
      payload: null,
    })])), /valid Unicode/);
});

Deno.test("constant exports use independent global indices and multibyte section lengths", async () => {
  const constants = Array.from({ length: 140 }, (_, index) => ({
    name: `constant_${index}`,
    exported: index !== 1,
    annotation: null,
    value: integer(index),
  }));
  const artifact = compile(module([fn("entry", integer(42))], { constants }));
  ok(WebAssembly.validate(artifact.bytes));
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  equal(instance.exports.constant_1, undefined);
  equal(Object.keys(instance.exports).length, 140);
  for (const index of [0, 2, 127, 128, 139]) {
    const global = instance.exports[`constant_${index}`];
    ok(global instanceof WebAssembly.Global);
    equal(global.value, index);
  }
});

Deno.test("empty modules and Unit/Bool constants have executable representations", async () => {
  equal(Object.keys((await instantiate(module([]))).exports), []);
  const compiled = await instantiate(module([
    fn("nothing", { $: "ConstantExpr", name: "unit_value" }),
    fn("truth", { $: "ConstantExpr", name: "bool_value" }),
  ], {
    constants: [
      {
        name: "unit_value",
        exported: false,
        annotation: unitType,
        value: unit,
      },
      {
        name: "bool_value",
        exported: false,
        annotation: boolType,
        value: { $: "BoolExpr", value: true },
      },
    ],
  }));
  equal(compiled.exports.nothing(0), 0);
  equal(compiled.exports.truth(0), 1);
});
