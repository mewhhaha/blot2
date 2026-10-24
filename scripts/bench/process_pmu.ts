// Request-scoped process PMU groups. Internal compiler phases are not isolated.
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { fileDigest } from "../compiler_gate_state.ts";
import { editedSources, gdevWorkloads, sessionOptions } from "./gdev.ts";
import { verifySnapshotFiles } from "./snapshot.ts";
const { values } = parseArgs({
  options: {
    binary: { type: "string" },
    snapshot: { type: "string" },
    manifest: { type: "string" },
    hashes: { type: "string" },
    out: { type: "string" },
  },
});
for (
  const name of ["binary", "snapshot", "manifest", "hashes", "out"] as const
) {
  if (!values[name]) throw Error(`--${name} is required`);
}
const out = resolve(values.out!);
try {
  await Deno.stat(out);
  throw Error("Choose a new output directory");
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
}
await Deno.mkdir(out, { recursive: true });
const root = fileURLToPath(new URL("../../", import.meta.url));
const [workload] = await gdevWorkloads(root, resolve(values.snapshot!));
const manifest = JSON.parse(await Deno.readTextFile(values.manifest!));
await verifySnapshotFiles(workload.root, manifest);
const expected = JSON.parse(await Deno.readTextFile(values.hashes!));
if (expected.manifest !== await fileDigest(values.manifest!)) {
  throw Error("Output hashes belong to a different workload manifest");
}
const binary = resolve(values.binary!);
const compiler = await createZigProjectCompiler({
  ...sessionOptions(binary, workload),
  codegenWorkers: 4,
  cacheDirectory: false,
  profileBackend: false,
});
const pins = {
  binary,
  binary_sha256: await fileDigest(binary),
  manifest_sha256: await fileDigest(values.manifest!),
  hashes_sha256: await fileDigest(values.hashes!),
  scope: "whole build requests, all threads; internal phases are not isolated",
  profile_backend: false,
};
await Deno.writeTextFile(
  out + "/pins.json",
  JSON.stringify(pins, null, 2) + "\n",
);
const monitor = new Deno.Command("python3", {
  args: [root + "/scripts/bench/process_pmu.py", String(compiler.pid)],
  stdin: "piped",
  stdout: "piped",
  stderr: "inherit",
}).spawn();
const writer = monitor.stdin.getWriter();
const reader = monitor.stdout.pipeThrough(new TextDecoderStream()).getReader();
let buffer = "";
async function receive() {
  while (!buffer.includes("\n")) {
    const item = await reader.read();
    if (item.done) throw Error("PMU monitor closed");
    buffer += item.value;
  }
  const end = buffer.indexOf("\n");
  const result = JSON.parse(buffer.slice(0, end));
  buffer = buffer.slice(end + 1);
  return result;
}
async function send(command: string) {
  await writer.write(new TextEncoder().encode(command + "\n"));
}
try {
  const ready = await receive();
  if (!ready.ready) throw Error("PMU monitor not ready");
  await Deno.writeTextFile(
    out + "/scope.json",
    JSON.stringify(ready, null, 2) + "\n",
  );
  for (
    const phase of [
      "fresh",
      "literal_in_body",
      "literal_revert",
      "body_change",
      "body_revert",
    ]
  ) {
    const edit = workload.scenarios.find((s) => s.name === phase);
    const sources = edit ? await editedSources(workload, edit) : {};
    const before = await Deno.readTextFile(`/proc/${compiler.pid}/stat`);
    await send("start");
    await receive();
    const start = performance.now();
    const result = await compiler.build({ sources });
    const wall_ms = performance.now() - start;
    await send("stop");
    const counters = await receive();
    const after = await Deno.readTextFile(`/proc/${compiler.pid}/stat`);
    if (!result.success) throw Error(JSON.stringify(result.diagnostics));
    const hash = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", result.bytes)),
      (v) => v.toString(16).padStart(2, "0"),
    ).join("");
    const key = phase === "literal_in_body" || phase === "body_change"
      ? phase
      : "fresh";
    const control =
      expected.entries[key === "fresh" ? "game" : `game @ ${key}`];
    if (hash !== control) {
      throw Error(`Output mismatch ${phase}: ${hash} expected ${control}`);
    }
    await Deno.writeTextFile(
      out + "/samples.jsonl",
      JSON.stringify({
        phase,
        wall_ms,
        wasm_sha256: hash,
        before_stat: before,
        after_stat: after,
        counters,
        stats: result.stats,
      }) + "\n",
      { append: true },
    );
    console.log(JSON.stringify({ phase, wall_ms }));
  }
  await verifySnapshotFiles(workload.root, manifest);
  if (await fileDigest(binary) !== pins.binary_sha256) {
    throw Error("Compiler changed during measurement");
  }
  await Deno.writeTextFile(
    out + "/complete.json",
    JSON.stringify({ success: true, requests: 5 }) + "\n",
  );
} finally {
  try {
    await send("quit");
  } catch { /* Already failed. */ }
  await writer.close();
  const status = await monitor.status;
  await compiler.dispose();
  if (!status.success) throw Error("PMU monitor failed");
}
