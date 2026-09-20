import {
  deepStrictEqual as equal,
  notStrictEqual,
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

interface StorageDefinition {
  readonly descriptor: Descriptor;
  readonly constructor: string;
}

const position = {
  descriptor: descriptor("Position"),
  constructor: "Position",
};
const velocity = {
  descriptor: descriptor("Velocity"),
  constructor: "Velocity",
};
const ghost = { descriptor: descriptor("Ghost"), constructor: "Ghost" };
const counter = {
  descriptor: descriptor("Counter", "Resource"),
  constructor: "Counter",
};
const time = {
  descriptor: descriptor("Time", "Resource"),
  constructor: "Time",
};

function read(storage: StorageDefinition, name: string, body: Expr): Expr {
  return {
    $: "UseExpr",
    name: `${name}_wrapped`,
    value: { $: "ReadExpr", identity: storage.descriptor.identity },
    body: {
      $: "MatchExpr",
      value: local(`${name}_wrapped`),
      arms: [{
        pattern: {
          $: "ConstructorPattern",
          constructor: storage.constructor,
          payload: { $: "BindingPattern", name },
        },
        body,
      }],
    },
  };
}

function store(
  storage: StorageDefinition,
  value: Expr,
  operation: "WriteExpr" | "InsertExpr" = "WriteExpr",
): Expr {
  return {
    $: operation,
    value: {
      $: "ConstructExpr",
      constructor: storage.constructor,
      payload: value,
    },
  };
}

function increment(storage: StorageDefinition, amount = 1): FunctionDefinition {
  return fn(
    `increment_${storage.constructor.toLowerCase()}`,
    read(
      storage,
      "value",
      store(storage, add(local("value"), integer(amount))),
    ),
  );
}

function artifact(
  storage: readonly StorageDefinition[],
  functions: readonly FunctionDefinition[] = [],
): EcsArtifact {
  // Non-exported readers retain registration even when exported systems change
  // their effects; the runtime must not silently discard registered storage.
  return compileEcs(module([
    ...functions,
    ...storage.map((entry) =>
      fn(
        `retain_${entry.constructor.toLowerCase()}`,
        read(entry, "value", unit),
        {
          exported: false,
        },
      )
    ),
  ], {
    descriptors: storage.map((entry) => entry.descriptor),
    data_types: storage.map((entry) => ({
      identity: entry.descriptor.identity,
      parameters: 0n,
      constructors: [{ name: entry.constructor, payload: u32Type }],
    })),
  }));
}

function runtimeError(code: EcsRuntimeErrorCode) {
  return (error: unknown) =>
    error instanceof EcsRuntimeError && error.code === code;
}

Deno.test("ECS reload remaps tags and resource indexes while preserving snapshots and changed system behavior", async () => {
  const previous = artifact([position, velocity, counter, time], [
    increment(position),
    increment(counter),
  ]);
  const renamed = { ...position, constructor: "At" };
  const compiled = artifact([time, counter, velocity, renamed], [
    fn(
      "move",
      read(
        renamed,
        "position",
        read(
          velocity,
          "velocity",
          store(
            renamed,
            add(add(local("position"), local("velocity")), integer(10)),
          ),
        ),
      ),
    ),
    fn(
      "double_counter",
      read(
        counter,
        "counter",
        store(counter, add(local("counter"), local("counter"))),
      ),
    ),
    increment(counter),
  ]);
  const replacement = { ...compiled, storage: compiled.storage.toReversed() };
  notStrictEqual(
    previous.storage.find((slot) => slot.constructor === "Position")?.tag,
    replacement.storage.find((slot) => slot.constructor === "At")?.tag,
  );
  const runtime = await createEcsRuntime(previous);
  const initial = runtime.createWorld({
    entityCount: 4,
    components: [
      {
        identity: position.descriptor.identity,
        values: [10, null, 0xffff_ffff, 50],
      },
      { identity: velocity.descriptor.identity, values: [3, 4, 1, null] },
    ],
    resources: [
      { identity: counter.descriptor.identity, value: 2 },
      { identity: time.descriptor.identity, value: 0x8000_0000 },
    ],
  });
  const advanced = runtime.run(initial);
  const reloaded = await runtime.reload(advanced, replacement);
  equal(reloaded.world.entityCount, 4);
  equal(
    reloaded.runtime.readResource(reloaded.world, counter.descriptor.identity),
    3,
  );
  equal(
    reloaded.runtime.readResource(reloaded.world, time.descriptor.identity),
    0x8000_0000,
  );
  const changed = reloaded.runtime.run(reloaded.world);
  equal(
    [0, 1, 2, 3].map((entity) =>
      reloaded.runtime.readComponent(
        changed,
        position.descriptor.identity,
        entity,
      )
    ),
    [24, null, 11, 51],
  );
  equal(reloaded.runtime.readResource(changed, counter.descriptor.identity), 7);
  const oldChanged = runtime.run(advanced);
  equal(runtime.readComponent(oldChanged, position.descriptor.identity, 0), 12);
  equal(runtime.readResource(oldChanged, counter.descriptor.identity), 4);
  equal(runtime.readComponent(initial, position.descriptor.identity, 0), 10);
  equal(runtime.readComponent(advanced, position.descriptor.identity, 0), 11);
  equal(
    reloaded.runtime.readComponent(
      reloaded.world,
      position.descriptor.identity,
      0,
    ),
    11,
  );
  equal(
    reloaded.runtime.readResource(reloaded.world, counter.descriptor.identity),
    3,
  );
  equal(
    reloaded.runtime.readComponent(changed, position.descriptor.identity, 0),
    24,
  );
  throws(() => runtime.run(reloaded.world), runtimeError("foreign_world"));
  throws(() => reloaded.runtime.run(advanced), runtimeError("foreign_world"));
  ok(Object.isFrozen(reloaded));
  ok(Object.isFrozen(reloaded.world));
  equal(Object.keys(reloaded.world), ["entityCount"]);
});

Deno.test("ECS reload adds absent components and explicitly initialized resources without inventing presence", async () => {
  const runtime = await createEcsRuntime(artifact([position, counter]));
  const positions = Array.from(
    { length: 65 },
    (_, entity) => [0, 31, 32, 63, 64].includes(entity) ? entity : null,
  );
  const initial = runtime.createWorld({
    entityCount: 65,
    components: [{ identity: position.descriptor.identity, values: positions }],
  });
  const replacement = artifact([ghost, time, position, counter], [
    fn("insert_ghost", store(ghost, integer(7), "InsertExpr")),
    increment(ghost),
    increment(time),
  ]);
  const initializer = {
    identity: time.descriptor.identity,
    value: 0xffff_ffff,
  };
  const pending = runtime.reload(initial, replacement, {
    resources: [initializer],
  });
  initializer.value = 5;
  const reloaded = await pending;
  for (let entity = 0; entity < positions.length; entity++) {
    equal(
      reloaded.runtime.readComponent(
        reloaded.world,
        position.descriptor.identity,
        entity,
      ),
      positions[entity],
    );
    equal(
      reloaded.runtime.readComponent(
        reloaded.world,
        ghost.descriptor.identity,
        entity,
      ),
      null,
    );
  }
  equal(
    reloaded.runtime.readResource(reloaded.world, time.descriptor.identity),
    0xffff_ffff,
  );
  throws(
    () =>
      reloaded.runtime.readResource(
        reloaded.world,
        counter.descriptor.identity,
      ),
    runtimeError("missing_resource"),
  );
  const changed = reloaded.runtime.runEntity(reloaded.world, 32);
  equal(
    reloaded.runtime.readComponent(changed, ghost.descriptor.identity, 32),
    8,
  );
  equal(
    reloaded.runtime.readComponent(changed, ghost.descriptor.identity, 31),
    null,
  );
  equal(reloaded.runtime.readResource(changed, time.descriptor.identity), 0);
  equal(
    reloaded.runtime.readComponent(
      reloaded.world,
      ghost.descriptor.identity,
      32,
    ),
    null,
  );
  equal(runtime.readComponent(initial, position.descriptor.identity, 32), 32);
});

Deno.test("ECS reload rejects removed storage, kind changes and nominal identity changes even for empty worlds", async () => {
  const runtime = await createEcsRuntime(
    artifact([position, counter], [increment(counter)]),
  );
  const initial = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.descriptor.identity, value: 9 }],
  });
  const changedKind = {
    ...position,
    descriptor: descriptor("Position", "Resource"),
  };
  const changedModule = {
    ...position,
    descriptor: descriptor("Position", "Component", "another/module"),
  };
  for (
    const storage of [[position], [counter], [changedKind, counter], [
      changedModule,
      counter,
    ]]
  ) {
    await rejects(() => runtime.reload(initial, artifact(storage)), (error) => {
      ok(error instanceof EcsRuntimeError);
      equal(error.code, "incompatible_reload");
      ok(error.message.includes("explicit migration"));
      return true;
    });
    equal(
      runtime.readResource(runtime.run(initial), counter.descriptor.identity),
      10,
    );
    equal(runtime.readResource(initial, counter.descriptor.identity), 9);
  }
});

Deno.test("ECS reload validates new-resource seeds and cannot overwrite preserved resources", async () => {
  const runtime = await createEcsRuntime(artifact([position, counter]));
  const initial = runtime.createWorld({ entityCount: 0 });
  const replacement = artifact([time, position, counter]);
  await rejects(
    () => runtime.reload(initial, replacement),
    runtimeError("missing_resource"),
  );
  const resource = { identity: time.descriptor.identity, value: 0 };
  await rejects(
    () =>
      runtime.reload(initial, replacement, { resources: [resource, resource] }),
    runtimeError("duplicate_seed"),
  );
  await rejects(() =>
    runtime.reload(initial, replacement, {
      resources: [{ identity: counter.descriptor.identity, value: 2 }],
    }), runtimeError("incompatible_reload"));
  await rejects(() =>
    runtime.reload(initial, replacement, {
      resources: [{ identity: position.descriptor.identity, value: 2 }],
    }), runtimeError("storage_kind"));
  await rejects(() =>
    runtime.reload(initial, replacement, {
      resources: [{ identity: ghost.descriptor.identity, value: 2 }],
    }), runtimeError("unknown_storage"));
  for (const value of [-1, 0x1_0000_0000, 0.5, NaN, Infinity]) {
    await rejects(() =>
      runtime.reload(initial, replacement, {
        resources: [{ identity: time.descriptor.identity, value }],
      }), RangeError);
  }
  const reloaded = await runtime.reload(initial, replacement, {
    resources: [resource],
  });
  equal(
    reloaded.runtime.readResource(reloaded.world, time.descriptor.identity),
    0,
  );
  equal(reloaded.world.entityCount, 0);
  equal(reloaded.runtime.run(reloaded.world), reloaded.world);
  throws(
    () =>
      reloaded.runtime.readResource(
        reloaded.world,
        counter.descriptor.identity,
      ),
    runtimeError("missing_resource"),
  );
});

Deno.test("ECS reload publishes nothing when Wasm validation, instantiation or export checks fail", async () => {
  const previous = artifact([counter], [increment(counter)]);
  const runtime = await createEcsRuntime(previous);
  const initial = runtime.createWorld({
    entityCount: 0,
    resources: [{ identity: counter.descriptor.identity, value: 41 }],
  });
  await rejects(
    () => runtime.reload(initial, { ...previous, bytes: new Uint8Array([0]) }),
    WebAssembly.CompileError,
  );
  const header = [0, 97, 115, 109, 1, 0, 0, 0];
  const trapsOnStart = new Uint8Array([
    ...header,
    1,
    4,
    1,
    96,
    0,
    0,
    3,
    2,
    1,
    0,
    8,
    1,
    0,
    10,
    5,
    1,
    3,
    0,
    0,
    11,
  ]);
  ok(WebAssembly.validate(trapsOnStart));
  await rejects(
    () => runtime.reload(initial, { ...previous, bytes: trapsOnStart }),
    WebAssembly.RuntimeError,
  );
  await rejects(
    () =>
      runtime.reload(initial, { ...previous, bytes: new Uint8Array(header) }),
    runtimeError("invalid_artifact"),
  );
  equal(
    runtime.readResource(runtime.run(initial), counter.descriptor.identity),
    42,
  );
  equal(runtime.readResource(initial, counter.descriptor.identity), 41);
  const recovered = await runtime.reload(initial, previous);
  equal(
    recovered.runtime.readResource(
      recovered.runtime.run(recovered.world),
      counter.descriptor.identity,
    ),
    42,
  );
});

Deno.test("ECS concurrent reloads retain explicit world ownership and isolated snapshots", async () => {
  const previous = artifact([position, counter], [
    increment(position),
    increment(counter),
  ]);
  const runtime = await createEcsRuntime(previous);
  const initial = runtime.createWorld({
    entityCount: 1,
    components: [{ identity: position.descriptor.identity, values: [8] }],
    resources: [{ identity: counter.descriptor.identity, value: 13 }],
  });
  await rejects(
    () => runtime.reload({ entityCount: 1 } as EcsWorld, previous),
    runtimeError("foreign_world"),
  );
  const pending = [
    runtime.reload(initial, previous),
    runtime.reload(initial, previous),
  ];
  const oldAdvanced = runtime.run(initial);
  const [first, second] = await Promise.all(pending);
  await rejects(
    () => first.runtime.reload(second.world, previous),
    runtimeError("foreign_world"),
  );
  const firstAdvanced = first.runtime.run(first.world);
  equal(
    first.runtime.readComponent(firstAdvanced, position.descriptor.identity, 0),
    9,
  );
  equal(
    second.runtime.readComponent(second.world, position.descriptor.identity, 0),
    8,
  );
  equal(
    second.runtime.readResource(second.world, counter.descriptor.identity),
    13,
  );
  equal(runtime.readComponent(initial, position.descriptor.identity, 0), 8);
  equal(runtime.readComponent(oldAdvanced, position.descriptor.identity, 0), 9);
  const secondReload = await first.runtime.reload(firstAdvanced, previous);
  equal(
    secondReload.runtime.readComponent(
      secondReload.world,
      position.descriptor.identity,
      0,
    ),
    9,
  );
  equal(
    secondReload.runtime.readResource(
      secondReload.world,
      counter.descriptor.identity,
    ),
    14,
  );
});
