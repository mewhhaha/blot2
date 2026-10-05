import { createZigProjectCompiler } from "./zig_project_client.ts";

/** Exercise the production byte protocol, including unsaved source inputs. */
export async function compile(
  source: string,
): Promise<{ bytes: Uint8Array<ArrayBuffer> }> {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0] ??
      new URL("../zig-native/zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
    return { bytes: result.bytes };
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
}
