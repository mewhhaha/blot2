import { gunzipSync } from "node:zlib";

// JSR caches and compiled virtual filesystems do not promise an executable
// file on disk, so expand the bundled Bend compiler before spawning it.
export async function extractNativeCompiler(): Promise<{
  readonly path: string;
  dispose(): Promise<void>;
}> {
  if (Deno.build.os !== "linux" || Deno.build.arch !== "x86_64") {
    throw new Error(
      "This @mewhhaha/blot package bundles a Bend compiler for Linux x86-64 only",
    );
  }
  const path = await Deno.makeTempFile({ prefix: "blotc-" });
  try {
    await Deno.writeFile(
      path,
      gunzipSync(
        await Deno.readFile(
          new URL("../generated/compiler/blotc.gz", import.meta.url),
        ),
      ),
    );
    await Deno.chmod(path, 0o700);
  } catch (error) {
    await Deno.remove(path);
    throw error;
  }
  return {
    path,
    async dispose() {
      await Deno.remove(path);
    },
  };
}
