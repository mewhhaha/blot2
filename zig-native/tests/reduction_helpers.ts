import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
export async function compileAndRun(
  source: string,
  run: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array<ArrayBuffer>,
  ) => void | Promise<void>,
  options: { stdRoot: string; asynchronous?: boolean },
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-rolling-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        stdRoot: options.stdRoot,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        cacheDirectory: false,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes, {
          asynchronous: options.asynchronous,
        });
        try {
          await run(guest, built.bytes);
        } finally {
          guest.dispose();
        }
        await compiler.close();
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}
