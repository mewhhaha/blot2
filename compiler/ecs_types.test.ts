import { deepStrictEqual as equal, throws } from "node:assert/strict";
import {
  analyze,
  CompilerError,
  type CoreModule,
  type DataType,
  type Descriptor,
  type Effect,
  type Expr,
  type Type,
} from "./host.ts";
import {
  add,
  call,
  descriptor,
  fn,
  integer,
  local,
  module,
  read,
  u32Type,
  unit,
  unitType,
} from "./fixtures.ts";

const position = descriptor("Position");
const ghost = descriptor("Ghost");
const clock = descriptor("Clock", "Resource");

function wrapper(storage: Descriptor): DataType {
  return {
    identity: storage.identity,
    parameters: 0n,
    constructors: [{ name: storage.identity.declaration, payload: u32Type }],
  };
}

function declaredType(storage: Descriptor): Type {
  return { $: "AppliedTy", identity: storage.identity, arguments: [] };
}

function construct(storage: Descriptor, payload: Expr): Expr {
  return {
    $: "ConstructExpr",
    constructor: storage.identity.declaration,
    payload,
  };
}

function unwrap(storage: Descriptor, value: Expr, body: Expr): Expr {
  return {
    $: "MatchExpr",
    value,
    arms: [{
      pattern: {
        $: "ConstructorPattern",
        constructor: storage.identity.declaration,
        payload: { $: "BindingPattern", name: "payload" },
      },
      body,
    }],
  };
}

function rejects(source: CoreModule, code: string) {
  throws(
    () => analyze(source),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

const effectNames = (effects: readonly Effect[]) =>
  effects.map((effect) =>
    `${effect.access.$} ${effect.descriptor.identity.declaration}`
  ).sort();

Deno.test("declared component reads return the constructor's actual nominal type", () => {
  const checked = analyze(module([
    fn("read_position", read(position.identity)),
    fn(
      "read_payload",
      unwrap(position, read(position.identity), local("payload")),
    ),
  ], { descriptors: [position], data_types: [wrapper(position)] }));
  equal(checked.functions[0].result, declaredType(position));
  equal(checked.functions[1].result, u32Type);
  equal(effectNames(checked.functions[1].effects), ["Read Position"]);
  equal(checked.world.systems[1].query, [position]);
});

Deno.test("opaque descriptor-only reads retain the existing core representation", () => {
  const checked = analyze(module([
    fn("read_position", read(position.identity)),
  ], { descriptors: [position] }));
  equal(checked.functions[0].result, {
    $: "NominalTy",
    identity: position.identity,
  });
});

Deno.test("setters infer declared component targets through ordinary calls", () => {
  const checked = analyze(module([
    fn("get_position", read(position.identity), { exported: false }),
    fn("set_position", { $: "WriteExpr", value: local("value") }, {
      exported: false,
      parameter_type: null,
    }),
    fn("move", {
      $: "UseExpr",
      name: "current",
      value: call("get_position"),
      body: unwrap(
        position,
        local("current"),
        call(
          "set_position",
          construct(position, add(local("payload"), integer(1))),
        ),
      ),
    }),
  ], { descriptors: [position], data_types: [wrapper(position)] }));
  equal(checked.functions[1].parameter, declaredType(position));
  equal(checked.functions[1].result, unitType);
  equal(checked.functions[1].variables, []);
  equal(effectNames(checked.functions[2].effects), [
    "Read Position",
    "Write Position",
  ]);
  equal(checked.world.systems[0].query, [position]);
});

Deno.test("inserting a constructed component registers it without requiring it in the query", () => {
  const checked = analyze(module([
    fn("before", unit),
    fn("spawn", { $: "InsertExpr", value: construct(ghost, integer(42)) }),
    fn("after", unit),
  ], { descriptors: [ghost], data_types: [wrapper(ghost)] }));
  equal(effectNames(checked.functions[1].effects), ["Insert Ghost"]);
  equal(checked.world.registrations, [ghost]);
  equal(checked.world.systems[1].query, []);
  equal(checked.world.batches, [["before"], ["spawn"], ["after"]]);
});

Deno.test("one system keeps distinct targets for multiple declared component writes", () => {
  const checked = analyze(module([fn("update_both", {
    $: "UseExpr",
    name: "position",
    value: read(position.identity),
    body: {
      $: "UseExpr",
      name: "ghost",
      value: read(ghost.identity),
      body: {
        $: "SequenceExpr",
        first: { $: "WriteExpr", value: local("position") },
        next: { $: "WriteExpr", value: local("ghost") },
      },
    },
  })], {
    descriptors: [position, ghost],
    data_types: [wrapper(position), wrapper(ghost)],
  }));
  equal(effectNames(checked.functions[0].effects), [
    "Read Ghost",
    "Read Position",
    "Write Ghost",
    "Write Position",
  ]);
  equal(checked.world.systems[0].query, [ghost, position]);
});

Deno.test("declared resource reads and writes are effects but not entity query terms", () => {
  const checked = analyze(module([
    fn("advance_clock", {
      $: "UseExpr",
      name: "current",
      value: read(clock.identity),
      body: unwrap(clock, local("current"), {
        $: "WriteExpr",
        value: construct(clock, add(local("payload"), integer(1))),
      }),
    }),
  ], { descriptors: [clock], data_types: [wrapper(clock)] }));
  equal(effectNames(checked.functions[0].effects), [
    "Read Clock",
    "Write Clock",
  ]);
  equal(checked.world.registrations, [clock]);
  equal(checked.world.systems[0].query, []);
  rejects(
    module([
      fn("insert_resource", {
        $: "InsertExpr",
        value: construct(clock, integer(1)),
      }),
    ], { descriptors: [clock], data_types: [wrapper(clock)] }),
    "invalid_insert",
  );
});

Deno.test("constructor-backed reads and writes cannot be hidden in pure lets", () => {
  for (
    const value of [
      read(position.identity),
      { $: "WriteExpr" as const, value: construct(position, integer(1)) },
      { $: "InsertExpr" as const, value: construct(position, integer(1)) },
    ]
  ) {
    rejects(
      module([fn("pure_binding", {
        $: "LetExpr",
        name: "bound",
        value,
        body: unit,
      })], { descriptors: [position], data_types: [wrapper(position)] }),
      "let_effect",
    );
  }
});

Deno.test("constructor-backed storage effects remain forbidden in consts and callbacks", () => {
  rejects(
    module([], {
      descriptors: [position],
      data_types: [wrapper(position)],
      constants: [{
        name: "snapshot",
        exported: false,
        annotation: null,
        value: read(position.identity),
      }],
    }),
    "const_effect",
  );
  rejects(
    module([fn("callback", {
      $: "LambdaExpr",
      identity: 1n,
      parameter: "ignored",
      parameter_type: null,
      result_type: null,
      body: read(position.identity),
    })], { descriptors: [position], data_types: [wrapper(position)] }),
    "effectful_function_value",
  );
});

Deno.test("declared data still requires a storage registration for ECS access", () => {
  const options = { data_types: [wrapper(position)] };
  rejects(
    module([fn("missing_read", read(position.identity))], options),
    "unknown_storage",
  );
  rejects(
    module([
      fn("missing_write", {
        $: "WriteExpr",
        value: construct(position, integer(1)),
      }),
    ], options),
    "unknown_storage",
  );
  rejects(
    module([fn("scalar_write", { $: "WriteExpr", value: integer(1) })]),
    "invalid_storage_access",
  );
});

Deno.test("generic data cannot be registered without a concrete storage identity", () => {
  for (const storage of [position, clock]) {
    rejects(
      module([], {
        descriptors: [storage],
        data_types: [{
          identity: storage.identity,
          parameters: 1n,
          constructors: [{
            name: storage.identity.declaration,
            payload: { $: "ParameterTy", index: 0n },
          }],
        }],
      }),
      "generic_storage_type",
    );
  }
});

Deno.test("descriptor/data overlap does not permit duplicate declarations or registrations", () => {
  rejects(
    module([], {
      descriptors: [position],
      data_types: [wrapper(position), wrapper(position)],
    }),
    "duplicate_type",
  );
  rejects(
    module([], {
      descriptors: [position, position],
      data_types: [wrapper(position)],
    }),
    "duplicate_type",
  );
  rejects(
    module([], {
      descriptors: [position, { ...position, storage: { $: "Resource" } }],
      data_types: [wrapper(position)],
    }),
    "duplicate_type",
  );
});

Deno.test("declared storage uses AppliedTy annotations, not the opaque type form", () => {
  const options = { descriptors: [position], data_types: [wrapper(position)] };
  const checked = analyze(module([
    fn("set_position", { $: "WriteExpr", value: local("value") }, {
      parameter_type: declaredType(position),
    }),
  ], options));
  equal(checked.functions[0].parameter, declaredType(position));
  rejects(
    module([
      fn("set_position", { $: "WriteExpr", value: local("value") }, {
        parameter_type: { $: "NominalTy", identity: position.identity },
      }),
    ], options),
    "invalid_annotation",
  );
});

Deno.test("storage typing is independent of the backend's initial U32 wrapper layout", () => {
  const state = descriptor("State");
  const declared: DataType = {
    identity: state.identity,
    parameters: 0n,
    constructors: [
      { name: "Running", payload: u32Type },
      { name: "Paused", payload: null },
    ],
  };
  const checked = analyze(module([
    fn("get_state", read(state.identity)),
    fn("pause", {
      $: "WriteExpr",
      value: { $: "ConstructExpr", constructor: "Paused", payload: null },
    }),
  ], { descriptors: [state], data_types: [declared] }));
  equal(checked.functions[0].result, declaredType(state));
  equal(effectNames(checked.functions[1].effects), ["Write State"]);
});
