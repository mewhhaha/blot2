// Check the actual generated Gdev render producer while emitting a tiny identity.
// This measures imported body checking, not whole-game emission.
// deno run -A benchmarks/tools/render_producer.ts --compiler PATH
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
const repo = resolve(new URL("../../", import.meta.url).pathname);
const root = resolve(repo, "../gdev");
const penBytes = await Deno.readFile(`${root}/pen.json`);
const settings =
  JSON.parse(new TextDecoder().decode(penBytes)).compiler.settings;
let executable = resolve(repo, "compiler/zig-out-native-dev/bin/blotc");
if (Deno.args.length !== 0) {
  if (Deno.args.length !== 2 || Deno.args[0] !== "--compiler") {
    throw new Error("Expected --compiler PATH");
  }
  executable = resolve(repo, Deno.args[1]);
}
const entry = `${root}/.pen/bounded-render-producer.blot`;
const source =
  'import * as render from "pen/protocol_render"\nentry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  return marker[0]\n';
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
const pins = {
  compiler_sha256: await hash(await Deno.readFile(executable)),
  entry_sha256: await hash(new TextEncoder().encode(source)),
  producer_sha256: await hash(
    await Deno.readFile(`${root}/pen/protocol_render.blot`),
  ),
  pen_json_sha256: await hash(penBytes),
  source_files: Object.fromEntries(
    await Promise.all([
      `${repo}/std/prelude.blot`,
      `${repo}/std/array.blot`,
      `${root}/pen/protocol_render.blot`,
      `${root}/pen/protocol.blot`,
      `${root}/pen/lanes.blot`,
      `${root}/pen/types.blot`,
    ].map(async (path) => [path, await hash(await Deno.readFile(path))])),
  ),
};
let compiler;
let guest;
let buildMs;
let buildStarted;
let report;
try {
  compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: `${repo}/std/prelude.blot`,
    stdRoot: `${repo}/std`,
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
    startupTimeoutMs: 5000,
    profileBackend: true,
  });
  buildStarted = performance.now();
  const result = await compiler.build({
    sources: { [entry]: source },
    signal: AbortSignal.timeout(5000),
  });
  buildMs = performance.now() - buildStarted;
  if (!result.success) {
    report = { status: "failed", diagnostics: result.diagnostics };
  } else {
    guest = await instantiateGuest(result.bytes);
    for (const input of [0, 1, 41, 0xffffffff, 0]) {
      if (guest.call("answer", input) !== input) {
        throw new Error("bad identity result");
      }
    }
    report = {
      status: "complete",
      wasm_bytes: result.bytes.length,
      wasm_sha256: await hash(result.bytes),
      executed_inputs: [0, 1, 41, 0xffffffff, 0],
      stats: result.stats,
    };
  }
} catch (error) {
  if (buildStarted !== undefined) buildMs = performance.now() - buildStarted;
  let status = "failed";
  if (/abort|timed out/i.test(String(error))) status = "timeout_incomplete";
  report = { status, error: String(error) };
  Deno.exitCode = 1;
} finally {
  guest?.dispose();
  await compiler?.dispose();
}
console.log(
  JSON.stringify({
    workload: "render_producer_with_tiny_identity",
    diagnostic_only: true,
    deadline_ms: 5000,
    build_ms: buildMs,
    pins,
    ...report,
  }),
);
