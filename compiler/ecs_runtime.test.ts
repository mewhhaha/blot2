import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import {
  createEcsRuntime,
  EcsRuntimeError,
  type EcsRuntimeErrorCode,
  type EcsWorld,
} from "./ecs_runtime.ts";
import {
  compileEcs,
  type DataType,
  type Descriptor,
  type EcsArtifact,
  type Expr,
  type FunctionDefinition,
} from "./host.ts";
import {
  add,
  descriptor,
  fn,
  integer,
  local,
  module,
  u32Type,
  unit,
} from "./fixtures.ts";

const position = descriptor("Position");
const velocity = descriptor("Velocity");
const ghost = descriptor("Ghost");
const deltaTime = descriptor("DeltaTime", "Resource");
const counter = descriptor("Counter", "Resource");

function storageType(descriptor: Descriptor): DataType {
  return {
    identity: descriptor.identity,
    parameters: 0n,
    constructors: [{ name: descriptor.identity.declaration, payload: u32Type }],
  };
}

function read(storage: Descriptor, name: string, body: Expr): Expr {
  return {
    $: "UseExpr",
    name: `${name}_wrapped`,
    value: { $: "ReadExpr", identity: storage.identity },
    body: {
      $: "MatchExpr",
      value: local(`${name}_wrapped`),
      arms: [{
        pattern: {
          $: "ConstructorPattern",
          constructor: storage.identity.declaration,
          payload: { $: "BindingPattern", name },
        },
        body,
      }],
    },
  };
}

function store(
  storage: Descriptor,
  value: Expr,
  operation: "WriteExpr" | "InsertExpr" = "WriteExpr",
): Expr {
  return {
    $: operation,
    value: {
      $: "ConstructExpr",
      constructor: storage.identity.declaration,
      payload: value,
    },
  };
}

function artifact(
  functions: readonly FunctionDefinition[],
  descriptors: readonly Descriptor[],
): EcsArtifact {
  return compileEcs(
    module(functions, {
      descriptors,
      data_types: descriptors.map(storageType),
    }),
  );
}

const move = fn(
  "move",
  read(
    position,
    "position",
    read(
      velocity,
      "velocity",
      read(
        deltaTime,
        "time",
        store(
          position,
          add(local("position"), {
            $: "ScalarExpr",
            operator: { $: "Multiply" },
            left: local("velocity"),
            right: local("time"),
          }),
        ),
      ),
    ),
  ),
);
const resetVelocity = fn("reset_velocity", store(velocity, integer(2)));
const increment = fn(
  "increment",
  read(counter, "counter", store(counter, add(local("counter"), integer(1)))),
);
const double = fn(
  "double",
  read(
    counter,
    "counter",
    store(counter, {
      $: "ScalarExpr",
      operator: { $: "Multiply" },
      left: local("counter"),
      right: integer(2),
    }),
  ),
);
const addGhost = fn("add_ghost", store(ghost, integer(5), "InsertExpr"));
const tickGhost = fn(
  "tick_ghost",
  read(ghost, "ghost", store(ghost, add(local("ghost"), integer(1)))),
);

function runtimeError(code: EcsRuntimeErrorCode) {
  return (error: unknown) =>
    error instanceof EcsRuntimeError && error.code === code;
}

Deno.test("ECS runs inferred intersections, write-only queries, and once-per-world resources", async () => {
  const runtime = await createEcsRuntime(
    artifact([move, resetVelocity, increment, double], [
      position,
      velocity,
      deltaTime,
      counter,
    ]),
  );
  const positions = [10, 20, null, 40, 0];
  const initial = runtime.createWorld({
    entityCount: 5,
    components: [
      { identity: position.identity, values: positions },
      { identity: velocity.identity, values: [2, null, 9, 3, 0xffff_ffff] },
    ],
    resources: [
      { identity: deltaTime.identity, value: 2 },
      { identity: counter.identity, value: 1 },
    ],
  });
  positions[0] = 999;
  const advanced = runtime.run(initial);
  equal(
    Array.from(
      { length: 5 },
      (_, entity) => runtime.readComponent(advanced, position.identity, entity),
    ),
    [14, 20, null, 46, 0xffff_fffe],
  );
  equal(
    Array.from(
      { length: 5 },
      (_, entity) => runtime.readComponent(advanced, velocity.identity, entity),
    ),
    [2, null, 2, 2, 2],
  );
  equal(runtime.readResource(advanced, counter.identity), 4);
  equal(runtime.readComponent(initial, position.identity, 0), 10);
  equal(runtime.readComponent(initial, velocity.identity, 2), 9);
  equal(runtime.readResource(initial, counter.identity), 1);
  const again = runtime.run(advanced);
  equal(runtime.readComponent(again, position.identity, 0), 18);
  equal(runtime.readComponent(again, position.identity, 4), 2);
  equal(runtime.readResource(again, counter.identity), 10);
  equal(runtime.readResource(advanced, counter.identity), 4);
  equal(runtime.readComponent(runtime.run(initial), position.identity, 0), 14);
  ok(Object.isFrozen(initial));
  equal(Object.keys(initial), ["entityCount"]);
});

Deno.test("ECS resource-only systems run once when all entity queries are empty", async () => {
  const runtime = await createEcsRuntime(
    artifact([resetVelocity, increment, double], [velocity, counter]),
  );
  const initial = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 1 }],
  });
  equal(runtime.readResource(runtime.run(initial), counter.identity), 4);
  equal(runtime.readResource(initial, counter.identity), 1);
  equal(runtime.run(initial, { systems: [] }), initial);
});

Deno.test("ECS system selection preserves declared order and validates its scope", async () => {
  const runtime = await createEcsRuntime(
    artifact([increment, double], [counter]),
  );
  const initial = runtime.createWorld({
    entityCount: 1,
    resources: [{ identity: counter.identity, value: 1 }],
  });
  equal(
    runtime.readResource(
      runtime.run(initial, { systems: ["double", "increment"] }),
      counter.identity,
    ),
    4,
  );
  equal(
    runtime.readResource(
      runtime.run(initial, { systems: ["double"] }),
      counter.identity,
    ),
    2,
  );
  throws(
    () => runtime.run(initial, { systems: ["unknown"] }),
    runtimeError("unknown_system"),
  );
  throws(
    () => runtime.run(initial, { systems: ["double", "double"] }),
    runtimeError("duplicate_system"),
  );
  equal(runtime.readResource(runtime.run(initial), counter.identity), 4);
});

Deno.test("ECS insert-only systems require an explicit entity and later queries see inserts", async () => {
  const runtime = await createEcsRuntime(
    artifact([addGhost, tickGhost], [ghost]),
  );
  const initial = runtime.createWorld({ entityCount: 3 });
  throws(() => runtime.run(initial), runtimeError("entity_scope"));
  const advanced = runtime.runEntity(initial, 2);
  equal(runtime.readComponent(advanced, ghost.identity, 2), 6);
  equal(runtime.readComponent(advanced, ghost.identity, 0), null);
  equal(runtime.readComponent(initial, ghost.identity, 2), null);
  const ticked = runtime.run(advanced, { systems: ["tick_ghost"] });
  equal(runtime.readComponent(ticked, ghost.identity, 2), 7);
  equal(runtime.readComponent(advanced, ghost.identity, 2), 6);
});

Deno.test("ECS full-run insertion uses a real component query and affects later systems", async () => {
  const copyGhost = fn(
    "copy_ghost",
    read(position, "position", store(ghost, local("position"), "InsertExpr")),
  );
  const runtime = await createEcsRuntime(
    artifact([copyGhost, tickGhost, increment], [position, ghost, counter]),
  );
  const initial = runtime.createWorld({
    entityCount: 2,
    components: [
      { identity: position.identity, values: [42, null] },
      { identity: ghost.identity, values: [null, 7] },
    ],
    resources: [{ identity: counter.identity, value: 0 }],
  });
  const advanced = runtime.run(initial);
  equal(runtime.readComponent(advanced, ghost.identity, 0), 43);
  equal(runtime.readComponent(advanced, ghost.identity, 1), 8);
  equal(runtime.readComponent(initial, ghost.identity, 0), null);
  const one = runtime.runEntity(initial, 1);
  equal(runtime.readComponent(one, ghost.identity, 0), null);
  equal(runtime.readComponent(one, ghost.identity, 1), 8);
  equal(runtime.readResource(one, counter.identity), 1);
});

Deno.test("ECS presence bitsets distinguish entities on both sides of word boundaries", async () => {
  const runtime = await createEcsRuntime(artifact([resetVelocity], [velocity]));
  const values = Array.from(
    { length: 65 },
    (_, index) => [0, 31, 32, 63, 64].includes(index) ? 9 : null,
  );
  const initial = runtime.createWorld({
    entityCount: values.length,
    components: [{ identity: velocity.identity, values }],
  });
  const advanced = runtime.run(initial);
  equal(
    values.map((value, entity) =>
      runtime.readComponent(advanced, velocity.identity, entity)
    ),
    values.map((value) => value === null ? null : 2),
  );
  equal(runtime.readComponent(initial, velocity.identity, 31), 9);
});

Deno.test("ECS accepts dense typed-array seeds without retaining mutable host arrays", async () => {
  const runtime = await createEcsRuntime(artifact([resetVelocity], [velocity]));
  const values = new Uint32Array([0, 0xffff_ffff]);
  const initial = runtime.createWorld({
    entityCount: 2,
    components: [{ identity: velocity.identity, values }],
  });
  values.fill(7);
  equal(runtime.readComponent(initial, velocity.identity, 0), 0);
  equal(runtime.readComponent(initial, velocity.identity, 1), 0xffff_ffff);
  equal(runtime.readComponent(runtime.run(initial), velocity.identity, 1), 2);
  equal(runtime.readComponent(initial, velocity.identity, 1), 0xffff_ffff);
});

Deno.test("ECS worlds stay separate within one runtime and cannot cross runtime instances", async () => {
  const compiled = artifact([increment], [counter]);
  const first = await createEcsRuntime(compiled);
  const second = await createEcsRuntime(compiled);
  const low = first.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 0 }],
  });
  const high = first.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 0xffff_ffff }],
  });
  equal(first.readResource(first.run(low), counter.identity), 1);
  equal(first.readResource(first.run(high), counter.identity), 0);
  equal(first.readResource(low, counter.identity), 0);
  equal(first.readResource(high, counter.identity), 0xffff_ffff);
  throws(() => second.run(low), runtimeError("foreign_world"));
  throws(
    () => second.readResource(low, counter.identity),
    runtimeError("foreign_world"),
  );
  throws(
    () => first.run({ entityCount: 0 } as EcsWorld),
    runtimeError("foreign_world"),
  );
});

Deno.test("ECS validates U32 seeds, identities, kinds, duplicates, and entity bounds", async () => {
  const runtime = await createEcsRuntime(
    artifact([resetVelocity, increment], [velocity, counter]),
  );
  for (const value of [-1, 0x1_0000_0000, 1.5, NaN, Infinity]) {
    throws(
      () =>
        runtime.createWorld({
          entityCount: 1,
          components: [{ identity: velocity.identity, values: [value] }],
        }),
      RangeError,
    );
    throws(
      () =>
        runtime.createWorld({
          entityCount: 0,
          resources: [{ identity: counter.identity, value }],
        }),
      RangeError,
    );
  }
  throws(() => runtime.createWorld({ entityCount: -1 }), RangeError);
  throws(
    () =>
      runtime.createWorld({
        entityCount: 1,
        components: [{ identity: velocity.identity, values: [] }],
      }),
    RangeError,
  );
  throws(
    () =>
      runtime.createWorld({
        entityCount: 0,
        resources: [{ identity: position.identity, value: 0 }],
      }),
    runtimeError("unknown_storage"),
  );
  throws(
    () =>
      runtime.createWorld({
        entityCount: 0,
        resources: [{ identity: velocity.identity, value: 0 }],
      }),
    runtimeError("storage_kind"),
  );
  throws(
    () =>
      runtime.createWorld({
        entityCount: 0,
        resources: [{ identity: counter.identity, value: 0 }, {
          identity: counter.identity,
          value: 1,
        }],
      }),
    runtimeError("duplicate_seed"),
  );
  const world = runtime.createWorld({ entityCount: 1 });
  for (const entity of [-1, 1, 1.5, NaN]) {
    throws(() => runtime.runEntity(world, entity), RangeError);
    throws(
      () => runtime.readComponent(world, velocity.identity, entity),
      RangeError,
    );
  }
  throws(
    () => runtime.readResource(world, counter.identity),
    runtimeError("missing_resource"),
  );
  throws(() => runtime.run(world), runtimeError("missing_resource"));
});

Deno.test("ECS failed transitions discard earlier writes and clear the active provider", async () => {
  const fail = fn("fail", {
    $: "SequenceExpr",
    first: store(counter, integer(99)),
    next: read(deltaTime, "time", unit),
  });
  const runtime = await createEcsRuntime(
    artifact([fail, increment], [counter, deltaTime]),
  );
  const world = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 1 }],
  });
  throws(
    () => runtime.run(world, { systems: ["fail"] }),
    runtimeError("missing_resource"),
  );
  equal(runtime.readResource(world, counter.identity), 1);
  const recovered = runtime.run(world, { systems: ["increment"] });
  equal(runtime.readResource(recovered, counter.identity), 2);
  equal(runtime.readResource(world, counter.identity), 1);
});

// A tiny guest imports only write. "fail" writes42 then traps; "recover"
// writes7. This isolates provider cleanup from compiler or stack-limit behavior.
function trappingArtifact(): EcsArtifact {
  const effect = {
    $: "Effect",
    access: { $: "Write" },
    descriptor: counter,
  } as const;
  const systems = ["fail", "recover"].map((name) => ({
    name,
    effects: [effect],
    query: [],
  }));
  return {
    analysis: {
      functions: systems.map((system) => ({
        ...system,
        parameter: { $: "UnitTy" },
        result: { $: "UnitTy" },
        variables: [],
      })),
      constants: [],
      world: {
        registrations: [counter],
        systems,
        batches: [["fail"], ["recover"]],
      },
      remaining_steps: 0n,
    },
    storage: [{
      identity: counter.identity,
      storage: counter.storage,
      constructor: "Counter",
      tag: 0,
    }],
    bytes: new Uint8Array([
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
      1,
      12,
      2,
      96,
      2,
      127,
      127,
      1,
      127,
      96,
      1,
      127,
      1,
      127,
      2,
      18,
      1,
      8,
      98,
      108,
      111,
      116,
      58,
      101,
      99,
      115,
      5,
      119,
      114,
      105,
      116,
      101,
      0,
      0,
      3,
      3,
      2,
      1,
      1,
      7,
      18,
      2,
      4,
      102,
      97,
      105,
      108,
      0,
      1,
      7,
      114,
      101,
      99,
      111,
      118,
      101,
      114,
      0,
      2,
      10,
      21,
      2,
      10,
      0,
      65,
      0,
      65,
      42,
      16,
      0,
      26,
      0,
      11,
      8,
      0,
      65,
      0,
      65,
      7,
      16,
      0,
      11,
    ]),
  };
}

Deno.test("ECS Wasm traps roll back writes and a later invocation gets a fresh scope", async () => {
  const runtime = await createEcsRuntime(trappingArtifact());
  const world = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 1 }],
  });
  throws(
    () => runtime.run(world, { systems: ["fail"] }),
    WebAssembly.RuntimeError,
  );
  equal(runtime.readResource(world, counter.identity), 1);
  equal(
    runtime.readResource(
      runtime.run(world, { systems: ["recover"] }),
      counter.identity,
    ),
    7,
  );
  equal(runtime.readResource(world, counter.identity), 1);
});

Deno.test("ECS imports cannot use capabilities absent from the current system", async () => {
  const compiled = trappingArtifact();
  const tampered = {
    ...compiled,
    analysis: {
      ...compiled.analysis,
      world: {
        ...compiled.analysis.world,
        systems: compiled.analysis.world.systems.map((system) => ({
          ...system,
          effects: [],
        })),
      },
    },
  };
  const runtime = await createEcsRuntime(tampered);
  const world = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.identity, value: 1 }],
  });
  throws(
    () => runtime.run(world, { systems: ["recover"] }),
    runtimeError("effect_scope"),
  );
  equal(runtime.readResource(world, counter.identity), 1);
  await rejects(
    createEcsRuntime({
      ...compiled,
      storage: [...compiled.storage, compiled.storage[0]],
    }),
    runtimeError("invalid_artifact"),
  );
});
