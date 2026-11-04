import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import {
  expectedRenderStream,
  ownedRenderSource,
} from "./owned_render_copy_fixture.ts";

for (const operation of ["owned", "emit"] as const) {
  for (const tier of ["development", "optimized"] as const) {
    Deno.test(`original Ink render copies preserve full streams aliases and prefix borrows (${operation}/${tier})`, async () => {
      const root = resolve(new URL("../..", import.meta.url).pathname);
      const directory = await Deno.makeTempDir();
      let compiler;
      let guest;
      try {
        const entry = resolve(directory, "main.blot");
        compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          imports: { "ink/": resolve(root, "../ink/lib") },
          stdRoot: resolve(root, "std"),
          prelude: resolve(root, "std/prelude.blot"),
          cacheDirectory: false,
          codegenTier: tier,
          profileBackend: true,
          startupTimeoutMs: 5000,
        });
        const result = await compiler.build({
          sources: { [entry]: ownedRenderSource(4, operation) },
          signal: AbortSignal.timeout(10000),
        });
        assert(result.success, JSON.stringify(result));
        for (const asynchronous of [false, true]) {
          guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 17, 0]) {
              for (
                const name of [
                  "stream",
                  "overlap",
                  "self_rows",
                  "empty_after_freeze",
                ]
              ) {
                let actual;
                if (asynchronous) {
                  actual = await guest.callAsync(name, input);
                } else actual = guest.call(name, input);
                assert.deepEqual(
                  actual,
                  expectedRenderStream(name, 4, input, operation),
                );
              }
            }
          } finally {
            guest.dispose();
            guest = undefined;
          }
        }
      } finally {
        guest?.dispose();
        await compiler?.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
