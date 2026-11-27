import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
export async function compileAndRun(
  source: string,
  run: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array<ArrayBuffer>,
  ) => void | Promise<void>,
  options: { stdRoot: string; asynchronous?: boolean },
) {
  const directory = await Deno.makeTempDir({ prefix: "squid-rolling-" });
  const entry = `${directory}/main.sq`;
  try {
    {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        stdRoot: options.stdRoot,
        prelude: new URL("../../std/prelude.sq", import.meta.url).pathname,
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
