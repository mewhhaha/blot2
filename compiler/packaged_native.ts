import { gunzipSync } from "node:zlib";
import { join } from "node:path";

// JSR caches and compiled virtual filesystems do not promise an executable
// file on disk, so expand the bundled Zig compiler before spawning it.
export async function extractNativeCompiler(): Promise<{
  readonly path: string;
  dispose(): Promise<void>;
}> {
  if (Deno.build.os !== "linux" || Deno.build.arch !== "x86_64") {
    throw new Error(
      "This @mewhhaha/blot package bundles a Zig compiler for Linux x86-64 only; provide an executable built for your platform",
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

/** A native child cannot read files embedded inside a Deno executable. */
export async function extractStandardLibrary(): Promise<{
  readonly path: string;
  dispose(): Promise<void>;
}> {
  const path = await Deno.makeTempDir({ prefix: "blot-std-" });
  async function copy(source: URL, target: string): Promise<void> {
    for await (const entry of Deno.readDir(source)) {
      const destination = join(target, entry.name);
      if (entry.isDirectory) {
        await Deno.mkdir(destination);
        await copy(new URL(`${entry.name}/`, source), destination);
      } else if (entry.isFile && entry.name.endsWith(".blot")) {
        await Deno.writeFile(
          destination,
          await Deno.readFile(new URL(entry.name, source)),
        );
      }
    }
  }
  try {
    await copy(new URL("../std/", import.meta.url), path);
  } catch (error) {
    await Deno.remove(path, { recursive: true });
    throw error;
  }
  return {
    path,
    dispose: () => Deno.remove(path, { recursive: true }),
  };
}
