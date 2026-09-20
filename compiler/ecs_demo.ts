import { deepStrictEqual as equal } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import type { TypeId } from "./host.ts";

const identity = (declaration: string): TypeId => ({
  $: "TypeId",
  module_name: "main",
  declaration,
});
const compiler = await createNativeCompiler();
try {
  const source = await Deno.readTextFile(
    new URL("../examples/ecs_runtime.blot", import.meta.url),
  );
  const started = performance.now();
  const artifact = await compiler.compileEcs(source);
  const compileMs = performance.now() - started;
  const runtime = await createEcsRuntime(artifact);
  const initial = runtime.createWorld({
    entityCount: 4,
    components: [
      { identity: identity("Position"), values: [2, 100, 8, null] },
      { identity: identity("Velocity"), values: [3, null, 4, 99] },
      { identity: identity("Visits"), values: [0, 0, null, null] },
    ],
    resources: [
      { identity: identity("DeltaTime"), value: 2 },
      { identity: identity("Counter"), value: 0 },
    ],
  });
  const next = runtime.run(initial);
  const positions = [0, 1, 2, 3].map((entity) =>
    runtime.readComponent(next, identity("Position"), entity)
  );
  equal(positions, [8, 100, 16, null]);
  equal(runtime.readComponent(initial, identity("Position"), 0), 2);
  equal(runtime.readResource(next, identity("Counter")), 2);
  equal(runtime.readComponent(next, identity("Ghost"), 0), 3);
  await Deno.mkdir("build", { recursive: true });
  await Deno.writeFile("build/ecs.wasm", artifact.bytes);
  // The sidecar records this build's import tags and inferred plan for inspection.
  await Deno.writeTextFile(
    "build/ecs.plan.json",
    JSON.stringify(
      {
        storage: artifact.storage,
        world: artifact.analysis.world,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `Compiled ${artifact.analysis.world.systems.length} systems / ${artifact.storage.length} storage types in ${
      compileMs.toFixed(2)
    } ms (${artifact.bytes.length} Wasm bytes).`,
  );
  console.log(
    "Positions:",
    positions,
    "Counter:",
    runtime.readResource(next, identity("Counter")),
  );
  console.log(
    "Previous world unchanged; inserted Ghost is visible to tick_ghost.",
  );
  console.log("Inferred batches:", artifact.analysis.world.batches);
  console.log(
    "Wrote build/ecs.wasm and build/ecs.plan.json. The ECS provider is compiler/ecs_runtime.ts.",
  );
} finally {
  await compiler.dispose();
}
