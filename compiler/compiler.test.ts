import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  analyze,
  compile,
  CompilerError,
  type CoreModule,
  type Effect,
  effectsConflict,
  type Expr,
  type ScalarOp,
} from "./host.ts";
import {
  add,
  boolType,
  call,
  descriptor,
  ecsExample,
  fn,
  ghost,
  integer,
  local,
  module,
  position,
  read,
  scalarExample,
  time,
  u32Type,
  unit,
  unitType,
  velocity,
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

const names = (descriptors: readonly { identity: { declaration: string } }[]) =>
  descriptors.map((descriptor) => descriptor.identity.declaration);
const effectNames = (effects: readonly Effect[]) =>
  effects.map((effect) =>
    `${effect.access.$} ${effect.descriptor.identity.declaration}`
  ).sort();

Deno.test("scheduling composes getter/setter effects through ordinary helpers", () => {
  const checked = analyze(module([
    fn("get_position", read(position.identity), { exported: false }),
    fn("set_position", { $: "WriteExpr", value: local("value") }, {
      parameter_type: { $: "NominalTy", identity: position.identity },
      exported: false,
    }),
    fn("update", call("set_position", call("get_position"))),
    fn("render", call("get_position")),
  ], { descriptors: [position] }));
  equal(effectNames(checked.functions[2].effects), [
    "Read Position",
    "Write Position",
  ]);
  equal(checked.world.batches, [["update"], ["render"]]);
  equal(names(checked.world.systems[0].query), ["Position"]);
});

Deno.test("scheduling batches readers and disjoint accesses while preserving conflicts", () => {
  const checked = analyze(module([
    fn("read_a", read(position.identity)),
    fn("read_b", read(position.identity)),
    fn("write_position", { $: "WriteExpr", value: read(position.identity) }),
    fn("read_velocity", read(velocity.identity)),
    fn("read_after", read(position.identity)),
  ], { descriptors: [position, velocity] }));
  equal(checked.world.batches, [["read_a", "read_b"], [
    "write_position",
    "read_velocity",
  ], ["read_after"]]);
});

Deno.test("resource effects participate in scheduling but never entity queries", () => {
  const checked = analyze(module([
    fn("read_time", read(time.identity)),
    fn("write_time", { $: "WriteExpr", value: read(time.identity) }),
    fn("read_position", read(position.identity)),
  ], { descriptors: [time, position] }));
  equal(checked.world.batches, [["read_time"], [
    "write_time",
    "read_position",
  ]]);
  equal(checked.world.systems[0].query, []);
  equal(checked.world.systems[1].query, []);
});

Deno.test("insertion is a structural scheduling barrier even for another component", () => {
  const checked = analyze(module([
    fn("pure_before", unit),
    fn("insert", { $: "InsertExpr", value: local("value") }, {
      parameter_type: { $: "NominalTy", identity: ghost.identity },
    }),
    fn("read_position", read(position.identity)),
    fn("pure_after", unit),
  ], { descriptors: [ghost, position] }));
  equal(checked.world.batches, [["pure_before"], ["insert"], [
    "read_position",
    "pure_after",
  ]]);
  equal(checked.world.systems[1].query, []);
  equal(names(checked.world.registrations), ["Ghost", "Position"]);
});

Deno.test("schedules are deterministic and every batch is conflict free", () => {
  const operations = [
    read(position.identity),
    read(velocity.identity),
    { $: "WriteExpr", value: read(position.identity) } as const,
    { $: "WriteExpr", value: read(velocity.identity) } as const,
    unit,
  ];
  for (let shift = 0; shift < operations.length; shift++) {
    const ordered = [...operations.slice(shift), ...operations.slice(0, shift)];
    const source = module(ordered.map((body, i) => fn(`system_${i}`, body)), {
      descriptors: [position, velocity],
    });
    const first = analyze(source).world;
    equal(analyze(source).world, first);
    equal(first.batches.flat(), source.functions.map((fn) => fn.name));
    for (const batch of first.batches) {
      const systems = batch.map((name) =>
        first.systems.find((system) => system.name === name)!
      );
      for (let left = 0; left < systems.length; left++) {
        for (let right = left + 1; right < systems.length; right++) {
          for (const a of systems[left].effects) {
            for (const b of systems[right].effects) {
              ok(!effectsConflict(a, b));
            }
          }
        }
      }
    }
  }
  equal(analyze(module([])).world.batches, []);
});

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
  equal(compiled.analysis.world.registrations, []);
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

Deno.test("let rejects ECS operations while use preserves their effect rows", () => {
  for (
    const value of [
      read(position.identity),
      { $: "WriteExpr", value: read(position.identity) } as const,
      { $: "InsertExpr", value: read(position.identity) } as const,
    ]
  ) {
    const binding = { name: "bound", value, body: unit };
    rejects(
      module([fn("bad", { $: "LetExpr", ...binding })], {
        descriptors: [position],
      }),
      "let_effect",
    );
    const direct = analyze(module([fn("direct", value)], {
      descriptors: [position],
    }));
    const bound = analyze(module([fn("bound", { $: "UseExpr", ...binding })], {
      descriptors: [position],
    }));
    equal(bound.functions[0].result, unitType);
    equal(bound.functions[0].effects, direct.functions[0].effects);
    equal(bound.world.systems[0].query, direct.world.systems[0].query);
  }
});

Deno.test("let purity follows forward helpers and recursive effect cycles", () => {
  rejects(
    module([
      fn("bad", {
        $: "LetExpr",
        name: "position",
        value: call("relay"),
        body: unit,
      }),
      fn("relay", call("cycle"), { exported: false }),
      fn("cycle", {
        $: "SequenceExpr",
        first: read(position.identity),
        next: call("relay"),
      }, { exported: false }),
    ], { descriptors: [position] }),
    "let_effect",
  );
});

Deno.test("let purity includes call arguments, dead branches, and nested use", () => {
  for (
    const value of [
      call("identity", read(position.identity)),
      {
        $: "IfExpr",
        condition: { $: "BoolExpr", value: false },
        consequent: {
          $: "SequenceExpr",
          first: read(position.identity),
          next: unit,
        },
        alternative: unit,
      } as const,
      {
        $: "UseExpr",
        name: "position",
        value: read(position.identity),
        body: unit,
      } as const,
    ]
  ) {
    rejects(
      module([
        fn("bad", { $: "LetExpr", name: "bound", value, body: unit }),
        fn("identity", local("value"), {
          parameter_type: null,
          exported: false,
        }),
      ], { descriptors: [position] }),
      "let_effect",
    );
  }
});

Deno.test("let constrains only its RHS, and use cannot hide a bad inner let", () => {
  const checked = analyze(module([fn("allowed", {
    $: "LetExpr",
    name: "pure",
    value: integer(42),
    body: read(position.identity),
  })], { descriptors: [position] }));
  equal(effectNames(checked.functions[0].effects), ["Read Position"]);

  for (const location of ["value", "body"] as const) {
    rejects(
      module([fn("bad", {
        $: "UseExpr",
        name: "outer",
        value: unit,
        body: unit,
        [location]: {
          $: "LetExpr",
          name: "inner",
          value: read(position.identity),
          body: unit,
        },
      })], { descriptors: [position] }),
      "let_effect",
    );
  }
});

Deno.test("let purity resolves inferred write targets and reports the binding span", () => {
  throws(() =>
    analyze(module([
      fn("entry", call("write", read(position.identity))),
      fn("write", {
        $: "SourceExpr",
        offset: 23n,
        annotation: { $: "None" },
        value: {
          $: "LetExpr",
          name: "result",
          value: { $: "WriteExpr", value: local("value") },
          body: unit,
        },
      }, { parameter_type: null, exported: false }),
    ], { descriptors: [position] })), (error) => {
    ok(error instanceof CompilerError);
    equal(error.code, "let_effect");
    equal(error.subject, "offset:23");
    ok(error.message.includes("use name <- expression"));
    return true;
  });
});

Deno.test("use permits pure const evaluation but does not permit runtime const effects", async () => {
  const body: Expr = {
    $: "UseExpr",
    name: "value",
    value: add(local("value"), integer(1)),
    body: add(local("value"), local("value")),
  };
  const compiled = await instantiate(module([
    fn("twice_next", body, { parameter_type: u32Type }),
  ], {
    constants: [{
      name: "answer",
      exported: false,
      annotation: null,
      value: call("twice_next", integer(20)),
    }],
  }));
  equal(compiled.exports.twice_next(20), 42);
  equal(compiled.analysis.constants[0].value, { $: "U32Value", value: 42 });
  rejects(
    module([], {
      descriptors: [position],
      constants: [{
        name: "bad",
        exported: false,
        annotation: null,
        value: {
          $: "UseExpr",
          name: "position",
          value: read(position.identity),
          body: unit,
        },
      }],
    }),
    "const_effect",
  );
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

Deno.test("ECS requirements flow through helpers and become storage/query plans", () => {
  const checked = analyze(ecsExample);
  equal(names(checked.world.registrations), [
    "Ghost",
    "Position",
    "Time",
    "Velocity",
  ]);
  equal(checked.world.systems.map((system) => system.name), [
    "move",
    "insert_ghost",
  ]);
  equal(effectNames(checked.world.systems[0].effects), [
    "Read Position",
    "Read Time",
    "Read Velocity",
    "Write Position",
  ]);
  equal(names(checked.world.systems[0].query), ["Position", "Velocity"]);
  equal(names(checked.world.systems[1].query), []);
  equal(effectNames(checked.world.systems[1].effects), ["Insert Ghost"]);
});

Deno.test("storage access follows solved argument types, not local variable names", () => {
  const source = module([
    fn("store", { $: "WriteExpr", value: local("arbitrary_name") }, {
      parameter: "arbitrary_name",
      parameter_type: null,
      exported: false,
    }),
    fn("tick", call("store", read(position.identity))),
  ], { descriptors: [position] });
  const checked = analyze(source);
  equal(checked.functions[0].parameter, {
    $: "NominalTy",
    identity: position.identity,
  });
  equal(effectNames(checked.world.systems[0].effects), [
    "Read Position",
    "Write Position",
  ]);
});

Deno.test("resources can be written but never become entity filters", () => {
  const checked = analyze(
    module([fn("clock", { $: "WriteExpr", value: read(time.identity) })], {
      descriptors: [time],
    }),
  );
  equal(names(checked.world.registrations), ["Time"]);
  equal(checked.world.systems[0].query, []);
  equal(effectNames(checked.world.systems[0].effects), [
    "Read Time",
    "Write Time",
  ]);
});

Deno.test("inserts register components without requiring or initializing them", () => {
  const source = module([ecsExample.functions[2]], { descriptors: [ghost] });
  const checked = analyze(source);
  equal(checked.world.registrations, [ghost]);
  equal(checked.world.systems[0].query, []);
  equal(checked.constants, []);
});

Deno.test("unused private accesses do not change exported system storage", () => {
  const source = module([
    fn("tick", unit),
    fn("unused", read(ghost.identity), { exported: false }),
  ], { descriptors: [ghost] });
  equal(analyze(source).world.registrations, []);
});

Deno.test("recursive and duplicate call edges produce a finite deduplicated effect row", () => {
  const source = module([
    fn("first", {
      $: "SequenceExpr",
      first: read(position.identity),
      next: call("second"),
    }, { result_type: unitType }),
    fn("second", {
      $: "SequenceExpr",
      first: call("first"),
      next: call("first"),
    }, { result_type: unitType, exported: false }),
  ], { descriptors: [position] });
  const checked = analyze(source);
  equal(effectNames(checked.functions[0].effects), ["Read Position"]);
  equal(effectNames(checked.functions[1].effects), ["Read Position"]);
});

Deno.test("nominal identity includes module identity and rejects duplicate declarations", () => {
  const remotePosition = descriptor(
    "Position",
    "Component",
    "other/components",
  );
  const checked = analyze(
    module([
      fn("both", {
        $: "SequenceExpr",
        first: read(position.identity),
        next: read(remotePosition.identity),
      }),
    ], { descriptors: [position, remotePosition] }),
  );
  equal(checked.world.registrations.length, 2);
  rejects(module([], { descriptors: [position, position] }), "duplicate_type");
  rejects(
    module([], {
      descriptors: [position, { ...position, storage: { $: "Resource" } }],
    }),
    "duplicate_type",
  );
});

Deno.test("rejects unregistered, unresolved, scalar, and invalid resource accesses", () => {
  rejects(module([fn("missing", read(position.identity))]), "unknown_storage");
  rejects(
    module([
      fn("bad_annotation", unit, {
        parameter_type: { $: "NominalTy", identity: position.identity },
      }),
    ]),
    "unknown_storage",
  );
  rejects(
    module([fn("scalar_write", { $: "WriteExpr", value: integer(1) })]),
    "invalid_storage_access",
  );
  rejects(
    module([
      fn("unresolved_write", { $: "WriteExpr", value: local("value") }, {
        parameter_type: null,
      }),
    ]),
    "invalid_storage_access",
  );
  rejects(
    module([
      fn("insert_resource", { $: "InsertExpr", value: read(time.identity) }),
    ], { descriptors: [time] }),
    "invalid_insert",
  );
});

Deno.test("effect conflicts distinguish reads, writes, inserts, and nominal identity", () => {
  const accesses = ["Read", "Write", "Insert"] as const;
  for (const left of accesses) {
    for (const right of accesses) {
      const a: Effect = {
        $: "Effect",
        access: { $: left },
        descriptor: position,
      };
      const b: Effect = {
        $: "Effect",
        access: { $: right },
        descriptor: position,
      };
      equal(effectsConflict(a, b), left !== "Read" || right !== "Read");
      equal(effectsConflict(a, { ...b, descriptor: velocity }), false);
    }
  }
});

Deno.test("storage plans are canonical across definition order and refreshed after edits", () => {
  const before = analyze(ecsExample);
  equal(
    analyze({ ...ecsExample, functions: [...ecsExample.functions].reverse() })
      .world.registrations,
    before.world.registrations,
  );
  const changed = module([fn("read_position", read(velocity.identity))], {
    descriptors: [position, velocity],
  });
  equal(names(analyze(changed).world.registrations), ["Velocity"]);
  equal(analyze(ecsExample), before);
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

Deno.test("const definitions reject direct and transitive runtime effects", () => {
  rejects(
    module([], {
      descriptors: [position],
      constants: [{
        name: "bad",
        exported: false,
        annotation: null,
        value: read(position.identity),
      }],
    }),
    "const_effect",
  );
  rejects({
    ...ecsExample,
    constants: [{
      name: "bad",
      exported: false,
      annotation: null,
      value: call("move"),
    }],
  }, "const_effect");
  rejects(
    module([fn("read_position", read(position.identity))], {
      descriptors: [position],
      constants: [{
        name: "dead_branch",
        exported: false,
        annotation: null,
        value: {
          $: "IfExpr",
          condition: { $: "BoolExpr", value: true },
          consequent: unit,
          alternative: {
            $: "SequenceExpr",
            first: call("read_position"),
            next: unit,
          },
        },
      }],
    }),
    "const_effect",
  );
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

Deno.test("the backend refuses checked ECS code instead of emitting placeholders", () => {
  throws(
    () => compile(ecsExample),
    (error) =>
      error instanceof CompilerError && error.code === "backend_effect",
  );
  throws(
    () =>
      compile(
        module([
          fn("identity", local("value"), {
            parameter_type: { $: "NominalTy", identity: position.identity },
          }),
        ], { descriptors: [position] }),
      ),
    (error) => error instanceof CompilerError && error.code === "backend_type",
  );
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
        value: integer(0),
        arms: [{ pattern: { $: "U32Pattern", value }, body: unit }],
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
