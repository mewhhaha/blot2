import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { execute, variant } from "./effectful_dictionary_closure_helpers.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

for (const helper of ["fn value => Render.show value", "Render.show"]) {
  Deno.test(`effectful ${helper} preserves ordered closures through archives checkpoints and recovery`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-effectful-dictionary-",
    });
    const entry = `${directory}/main.blot`,
      library = `${directory}/render.blot`,
      dependencies = `${directory}/render.blotdep`;
    const full = variant(helper);
    const split = full.indexOf("\nconst render:");
    assert(split > 0);
    const producer = full.slice(0, split);
    const consumer = 'import {Read, Render, helper} from "./render"\n' +
      full.slice(split + 1);
    try {
      await Deno.writeTextFile(library, producer);
      await Deno.writeTextFile(entry, consumer);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, dependencies, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      for (const codegenTier of ["development", "optimized"] as const) {
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
        };
        const source = await createZigProjectCompiler(options);
        const archive = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        let checkpoint: Uint8Array<ArrayBuffer>,
          expected: Uint8Array<ArrayBuffer>;
        try {
          const live = await source.build(), frozen = await archive.build();
          assert(live.success, JSON.stringify(live));
          assert(frozen.success, JSON.stringify(frozen));
          assert(frozen.stats.cachedModules > 0);
          assert.deepEqual(live.bytes, frozen.bytes);
          await execute(live.bytes);
          await execute(frozen.bytes);
          expected = live.bytes;
          checkpoint = await archive.exportCheckpoint();
          const invalid = consumer.replace("helper value", "helper ()");
          const failedSource = await source.build({
            sources: { [entry]: invalid },
          });
          const failedArchive = await archive.build({
            sources: { [entry]: invalid },
          });
          assert(!failedSource.success && !failedArchive.success);
          assert.deepEqual(failedSource.diagnostics, failedArchive.diagnostics);
          assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
          const recovered = await archive.build({
            sources: { [entry]: consumer },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, expected);
        } finally {
          await source.dispose();
          await archive.dispose();
        }
        const restored = await createZigProjectCompiler({
          ...options,
          dependencies,
          checkpoint: checkpoint!,
        });
        try {
          const replayed = await restored.build();
          assert(replayed.success, JSON.stringify(replayed));
          assert.deepEqual(replayed.bytes, expected!);
          await execute(replayed.bytes);
        } finally {
          await restored.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
