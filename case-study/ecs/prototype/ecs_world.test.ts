// Archived compiler-coupled prototype; not part of the current compiler.
import {
  deepStrictEqual as equal,
  notStrictEqual,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import {
  createEcsRuntime,
  EcsRuntimeError,
  type EcsRuntimeErrorCode,
  type EcsWorld,
} from "./ecs_runtime.ts";
import type { TypeId } from "./host.ts";

const identity = (declaration: string): TypeId => ({
  $: "TypeId",
  module_name: "main",
  declaration,
});
const position = identity("Position");
const velocity = identity("Velocity");
const time = identity("Time");

async function createRuntime() {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compileEcs(`
#[component]
data Position = #Position U32
#[component]
data Velocity = #Velocity U32
#[resource]
data Time = #Time U32
const move = fn () => do:
  use wrapped_position <- @ecs.get #Position
  use wrapped_velocity <- @ecs.get #Velocity
  use wrapped_time <- @ecs.get #Time
  let #Position position = wrapped_position
  let #Velocity velocity = wrapped_velocity
  let #Time time = wrapped_time
  use @ecs.set (#Position (@u32.add position (@u32.mul velocity time)))
  return ()
`);
    return { runtime: await createEcsRuntime(artifact), artifact };
  } finally {
    compiler.dispose();
  }
}

const errorCode = (code: EcsRuntimeErrorCode) => (error: unknown) =>
  error instanceof EcsRuntimeError && error.code === code;

Deno.test("platform resource delivery is atomic and preserves old worlds", async () => {
  const { runtime } = await createRuntime();
  const original = runtime.createWorld({
    entityCount: 1,
    components: [{ identity: position, values: [2] }, {
      identity: velocity,
      values: [3],
    }],
    resources: [{ identity: time, value: 1 }],
  });
  const supplied = runtime.withResources(original, [{
    identity: time,
    value: 4,
  }]);
  equal(runtime.readResource(original, time), 1);
  equal(runtime.readResource(supplied, time), 4);
  equal(runtime.readComponent(runtime.run(supplied), position, 0), 14);
  equal(runtime.readComponent(original, position, 0), 2);
  equal(runtime.withResources(original, []), original);
  throws(() =>
    runtime.withResources(original, [
      { identity: time, value: 9 },
      { identity: time, value: 10 },
    ]), errorCode("duplicate_seed"));
  throws(
    () => runtime.withResources(original, [{ identity: position, value: 1 }]),
    errorCode("storage_kind"),
  );
  throws(() =>
    runtime.withResources(original, [
      { identity: time, value: 9 },
      { identity: identity("Missing"), value: 10 },
    ]), errorCode("unknown_storage"));
  throws(
    () => runtime.withResources(original, [{ identity: time, value: -1 }]),
    RangeError,
  );
  equal(runtime.readResource(original, time), 1);
  equal(runtime.readResource(supplied, time), 4);
});

Deno.test("spawn and despawn retain stable entity IDs and immutable presence across word boundaries", async () => {
  const { runtime } = await createRuntime();
  const original = runtime.createWorld({
    entityCount: 31,
    components: [{ identity: position, values: Array(31).fill(2) }, {
      identity: velocity,
      values: Array(31).fill(3),
    }],
    resources: [{ identity: time, value: 2 }],
  });
  const spawned = runtime.spawn(original, {
    entityCount: 3,
    components: [{ identity: position, values: [5, 6, 7] }, {
      identity: velocity,
      values: [1, null, 2],
    }],
  });
  equal(spawned.entities, [31, 32, 33]);
  equal(original.entityCount, 31);
  equal(spawned.world.entityCount, 34);
  const removed = runtime.despawn(spawned.world, 32);
  equal(runtime.isAlive(removed, 31), true);
  equal(runtime.isAlive(removed, 32), false);
  equal(runtime.isAlive(removed, 33), true);
  equal(runtime.isAlive(spawned.world, 32), true);
  equal(runtime.readComponent(removed, position, 32), null);
  equal(runtime.readComponent(spawned.world, position, 32), 6);
  const advanced = runtime.run(removed);
  equal(runtime.readComponent(advanced, position, 30), 8);
  equal(runtime.readComponent(advanced, position, 31), 7);
  equal(runtime.readComponent(advanced, position, 32), null);
  equal(runtime.readComponent(advanced, position, 33), 11);
  throws(() => runtime.runEntity(removed, 32), errorCode("missing_entity"));
  throws(() => runtime.despawn(removed, 32), errorCode("missing_entity"));
  const next = runtime.spawn(removed, { entityCount: 1 });
  equal(next.entities, [34]);
  equal(runtime.isAlive(next.world, 32), false);
  equal(runtime.isAlive(next.world, 34), true);
  equal(runtime.spawn(original, { entityCount: 0 }).world, original);
  throws(() =>
    runtime.spawn(original, {
      entityCount: 1,
      components: [{ identity: position, values: [1] }, {
        identity: velocity,
        values: [-1],
      }],
    }), RangeError);
  equal(runtime.readComponent(original, position, 0), 2);
});

Deno.test("exported world seeds are detached, round trip removed entities, and survive reload", async () => {
  const { runtime, artifact } = await createRuntime();
  const initial = runtime.createWorld({
    entityCount: 3,
    components: [{ identity: position, values: [2, 3, null] }, {
      identity: velocity,
      values: [4, 5, 6],
    }],
    resources: [{ identity: time, value: 2 }],
  });
  const world = runtime.despawn(initial, 1);
  const seed = runtime.exportWorld(world);
  equal(seed.alive, [true, false, true]);
  const restored = runtime.createWorld(seed);
  equal(runtime.exportWorld(restored), seed);
  const reloaded = await runtime.reload(world, artifact);
  equal(reloaded.runtime.exportWorld(reloaded.world), seed);
  notStrictEqual(reloaded.world, world);
  // The caller may retain and mutate both artifact and exported seed objects.
  const detached = structuredClone(seed);
  (detached.components![0].values as number[])[0] = 999;
  (detached.alive as boolean[])[0] = false;
  equal(runtime.readComponent(world, position, 0), 2);
  equal(runtime.isAlive(world, 0), true);
  (artifact.storage[0].identity as { declaration: string }).declaration =
    "Changed";
  equal(runtime.exportWorld(world), seed);
});

Deno.test("world lifecycle rejects malformed presence and foreign snapshots", async () => {
  const first = (await createRuntime()).runtime;
  const second = (await createRuntime()).runtime;
  throws(() => first.createWorld({ entityCount: 1, alive: [] }), RangeError);
  throws(
    () =>
      first.createWorld({ entityCount: 1, alive: [1] as unknown as boolean[] }),
    TypeError,
  );
  throws(() =>
    first.createWorld({
      entityCount: 1,
      alive: [false],
      components: [{ identity: position, values: [3] }],
    }), errorCode("missing_entity"));
  const world = first.createWorld({ entityCount: 1 });
  for (const candidate of [world, { entityCount: 1 } as EcsWorld]) {
    throws(() => second.exportWorld(candidate), errorCode("foreign_world"));
    throws(
      () => second.withResources(candidate, []),
      errorCode("foreign_world"),
    );
    throws(
      () => second.spawn(candidate, { entityCount: 1 }),
      errorCode("foreign_world"),
    );
    throws(() => second.despawn(candidate, 0), errorCode("foreign_world"));
    throws(() => second.isAlive(candidate, 0), errorCode("foreign_world"));
  }
  throws(() => first.isAlive(world, 1), RangeError);
  throws(() => first.despawn(world, -1), RangeError);
});
