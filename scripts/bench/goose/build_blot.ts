// Fresh-process adapter. Kernel execution/engine compilation are not build work.
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../../compiler/zig_project_client.ts";
const [executable, entry, artifact, stats] = Deno.args.slice(0, 4).map((p) =>
  resolve(p)
);
if (!executable || !entry || !artifact || !stats) {
  throw new Error("build_blot.ts compiler source artifact stats");
}
if (
  Deno.args.length > 5 ||
  (Deno.args[4] !== undefined && Deno.args[4] !== "--profile-backend")
) {
  throw new Error("unexpected build option");
}
const profileBackend = Deno.args[4] === "--profile-backend";
const repo = resolve(new URL("../../..", import.meta.url).pathname);
const started = performance.now();
const compiler = await createZigProjectCompiler({
  executable,
  entry,
  stdRoot: `${repo}/std`,
  prelude: `${repo}/std/prelude.blot`,
  cacheDirectory: false,
  codegenTier: "optimized",
  profileBackend,
  storage: {
    temporaryBytes: 32 * 1024 * 1024,
    persistentBytes: 1024 * 1024,
    transportBytes: 2 * 1024 * 1024,
    ownerCapacity: 4096,
  },
});
const opened = performance.now();
try {
  const result = await compiler.build({ signal: AbortSignal.timeout(30_000) });
  const finished = performance.now();
  if (!result.success) {
    await Deno.writeTextFile(
      stats,
      JSON.stringify(
        {
          success: false,
          compiler_identity: compiler.compilerIdentity,
          session_open_ms: opened - started,
          build_ms: finished - opened,
          diagnostics: result.diagnostics,
        },
        null,
        2,
      ) + "\n",
    );
    throw new Error(JSON.stringify(result.diagnostics));
  }
  await Deno.writeFile(artifact, result.bytes);
  await Deno.writeTextFile(
    stats,
    JSON.stringify(
      {
        session_open_ms: opened - started,
        build_ms: finished - opened,
        adapter_ms: finished - started,
        compiler_identity: compiler.compilerIdentity,
        wasm_bytes: result.bytes.length,
        profile_backend: profileBackend,
        stats: result.stats,
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  await compiler.dispose();
}
