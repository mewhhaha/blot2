// Archived compiler-coupled prototype; not part of the current compiler.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import type { EcsArtifact } from "./host.ts";

const source = (component: string) => `
#[component] data Position = Position F32
#[component] data Velocity = Velocity F32
const touch = fn () => do:
  use value <- @ecs.previous ${component}
  return ()
const start = fn () => ()
const event = fn () => ()
const update = fn () => @ecs.run touch
const render = fn () => ()
`;

function registrations(artifact: EcsArtifact) {
  return artifact.analysis.world.registrations.map((descriptor) =>
    descriptor.identity.declaration
  );
}

Deno.test("native app registrations include private systems and invalidate across effect/mode changes", async () => {
  const session = await createNativeIncrementalCompiler({ prelude: "none" });
  let clean: Awaited<ReturnType<typeof createNativeCompiler>> | undefined;
  try {
    clean = await createNativeCompiler({ prelude: "none" });
    const initial = await session.compileApp(source("Position"));
    equal(registrations(initial.artifact), ["Position"]);
    equal(
      initial.artifact.storage.map((storage) => storage.identity.declaration),
      ["Position"],
    );
    for (const system of initial.artifact.analysis.world.systems) {
      equal(system.query, []);
    }
    const changed = await session.compileApp(source("Velocity"));
    const fresh = await clean.compileApp(source("Velocity"));
    equal(changed.artifact.analysis, fresh.analysis);
    equal(changed.artifact.storage, fresh.storage);
    equal(changed.artifact.bytes, fresh.bytes);
    equal(registrations(changed.artifact), ["Velocity"]);
    ok(WebAssembly.validate(changed.artifact.bytes));
    const analyzed = await session.analyze(source("Velocity"));
    equal(analyzed.analysis.world.registrations, []);
    const appAgain = await session.compileApp(source("Velocity"));
    equal(registrations(appAgain.artifact), ["Velocity"]);
    equal(appAgain.artifact.bytes, fresh.bytes);
    equal(appAgain.stats.groups_checked, 0);
  } finally {
    await clean?.dispose();
    await session.dispose();
  }
});
