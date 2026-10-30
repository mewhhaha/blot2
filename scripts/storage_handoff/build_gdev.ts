import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const parent = resolve(Deno.args[0] ?? "build/gdev-first-frame");
await Deno.mkdir(parent, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: parent, prefix: "main-" });
const root = resolve("../gdev");
const settings =
  JSON.parse(await Deno.readTextFile(`${root}/pen.json`)).compiler.settings;
const quote = (value: string) => `'${value.replaceAll("'", "'\\''")}'`;
const executable = `${evidence}/blotc`;
await Deno.writeTextFile(
  executable,
  `#!/bin/sh\nexec ${
    quote(resolve("zig-native/zig-out-dev/bin/blotc"))
  } "$@" 2>>${quote(`${evidence}/compiler-stderr.log`)}\n`,
);
await Deno.chmod(executable, 0o755);
const compiler = await createZigProjectCompiler({
  executable,
  entry: `${root}/src/main.blot`,
  prelude: resolve("std/prelude.blot"),
  stdRoot: resolve("std"),
  imports: Object.fromEntries(
    Object.entries(settings.imports).map((
      [key, path],
    ) => [key, resolve(root, path as string)]),
  ),
  nativeAssets: {
    roots: settings.nativeAssets.roots.map((path: string) =>
      resolve(root, path)
    ),
    imports: settings.nativeAssets.imports.map((
      item: Record<string, string>,
    ) => ({
      ...item,
      module: resolve(root, item.module),
      path: resolve(root, item.path),
    })),
  },
  inferenceBudget: settings.inferenceBudget,
  storage: settings.storage,
  cacheDirectory: false,
});
try {
  const result = await compiler.build();
  const report = result.success
    ? {
      evidence,
      identity: compiler.compilerIdentity,
      success: true,
      wasmBytes: result.bytes.length,
      assetCount: result.assets?.length ?? 0,
      stats: result.stats,
    }
    : {
      evidence,
      identity: compiler.compilerIdentity,
      success: false,
      diagnostics: result.diagnostics,
    };
  if (result.success) {
    await Deno.writeFile(`${evidence}/main.wasm`, result.bytes);
  }
  await Deno.writeTextFile(
    `${evidence}/result.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(JSON.stringify(report));
  if (!result.success) Deno.exitCode = 1;
} finally {
  await compiler.dispose();
}
