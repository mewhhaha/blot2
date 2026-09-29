// The package and standalone CLI carry the matching native compiler as data.
// Copy it before spawning: package caches and compiled virtual filesystems do
// not promise an executable file on disk.
export async function extractNativeCompiler(): Promise<{
  readonly path: string;
  dispose(): Promise<void>;
}> {
  if (Deno.build.os !== "linux" || Deno.build.arch !== "x86_64") {
    throw new Error(
      "This @mewhhaha/blot release bundles OxCaml for Linux x86-64 only",
    );
  }
  const path = await Deno.makeTempFile({ prefix: "blotc-" });
  try {
    await Deno.writeFile(
      path,
      await Deno.readFile(
        new URL("../generated/compiler/blotc-oxcaml", import.meta.url),
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
