// Archived compiler-coupled prototype; not part of the current compiler.
import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createEcsRuntime, EcsRuntimeError } from "./ecs_runtime.ts";
import type { TypeId } from "./host.ts";

const identity = (declaration: string): TypeId => ({
  $: "TypeId",
  module_name: "main",
  declaration,
});
const position = identity("Position");
const velocity = identity("Velocity");
const time = identity("Time");
const source = `
#[component]
data Position = #Position F32
#[component]
data Velocity = #Velocity F32
#[resource]
data Time = #Time F32
const move = fn () => do:
  use wrapped_position <- @ecs.get #Position
  use wrapped_velocity <- @ecs.get #Velocity
  use wrapped_time <- @ecs.get #Time
  let #Position position = wrapped_position
  let #Velocity velocity = wrapped_velocity
  let #Time time = wrapped_time
  use @ecs.set (#Position (@f32.add position (@f32.mul velocity time)))
  return ()
`;

Deno.test("F32 ECS imports preserve IEEE words and expose numeric immutable snapshots", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compileEcs(source);
    const runtime = await createEcsRuntime(artifact);
    const world = runtime.createWorld({
      entityCount: 4,
      components: [
        { identity: position, values: [-2.5, -0, Infinity, NaN] },
        { identity: velocity, values: [1.25, null, null, null] },
      ],
      resources: [{ identity: time, value: 0.1 }],
    });
    equal(runtime.readResource(world, time), Math.fround(0.1));
    equal(runtime.readComponent(world, position, 1), -0);
    equal(runtime.readComponent(world, position, 2), Infinity);
    ok(Number.isNaN(runtime.readComponent(world, position, 3)));
    const input = runtime.withResources(world, [{
      identity: time,
      value: 0.5,
    }]);
    const moved = runtime.run(input);
    equal(runtime.readComponent(moved, position, 0), -1.875);
    equal(runtime.readComponent(world, position, 0), -2.5);
    const exported = runtime.exportWorld(moved);
    equal(runtime.exportWorld(runtime.createWorld(exported)), exported);
    const added = runtime.spawn(moved, {
      entityCount: 1,
      components: [
        { identity: position, values: [-1.125] },
        { identity: velocity, values: [-3.5] },
      ],
    });
    equal(runtime.readComponent(runtime.run(added.world), position, 4), -2.875);
    const replacement = await runtime.reload(moved, artifact);
    equal(replacement.runtime.exportWorld(replacement.world), exported);
    const prepared = await runtime.prepareReload(artifact);
    // Compilation/instantiation may finish long after the world advanced.
    const latest = runtime.run(moved);
    const handedOff = prepared.apply(latest);
    equal(handedOff.runtime.readComponent(handedOff.world, position, 0), -1.25);
    equal(runtime.readComponent(moved, position, 0), -1.875);
  } finally {
    compiler.dispose();
  }
});

Deno.test("reload rejects scalar reinterpretation and accepts explicit F32 resource initialization", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compileEcs(source);
    const runtime = await createEcsRuntime(artifact);
    const world = runtime.createWorld({
      entityCount: 1,
      components: [
        { identity: position, values: [-0.5] },
        { identity: velocity, values: [2.25] },
      ],
      resources: [{ identity: time, value: 0.25 }],
    });
    const incompatible = compiler.compileEcs(
      source.replaceAll("F32", "U32").replaceAll("@f32.", "@u32."),
    );
    await rejects(
      runtime.reload(world, incompatible),
      (error) =>
        error instanceof EcsRuntimeError &&
        error.code === "incompatible_reload",
    );
    equal(runtime.readComponent(world, position, 0), -0.5);
    const expanded = compiler.compileEcs(`${source}
#[resource]
data Bias = Bias F32
const retain_bias = fn () => do:
  use _ <- @ecs.get Bias
  return ()
`);
    const replacement = await runtime.reload(world, expanded, {
      resources: [{ identity: identity("Bias"), value: -0.75 }],
    });
    equal(
      replacement.runtime.readResource(replacement.world, identity("Bias")),
      -0.75,
    );
    equal(
      replacement.runtime.readComponent(replacement.world, position, 0),
      -0.5,
    );
  } finally {
    compiler.dispose();
  }
});
