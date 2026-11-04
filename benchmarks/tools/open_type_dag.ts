// Unused generic signatures share an open DAG; only checking grows with depth.
// deno run -A benchmarks/tools/open_type_dag.ts --blotc PATH [--depths 8,12,16,20]
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const options = new Map<string, string>();
for (let at = 0; at < Deno.args.length; at++) {
  const key = Deno.args[at];
  if (!["--blotc", "--depths", "--timeout-ms"].includes(key)) {
    throw new Error(`Unexpected argument: ${key}`);
  }
  const value = Deno.args[++at];
  if (!value || value.startsWith("--")) throw new Error(`${key} needs a value`);
  options.set(key, value);
}
const depths = (options.get("--depths") ?? "8,12,16,20").split(",").map(Number);
const timeoutMs = Number(options.get("--timeout-ms") ?? "5000");
if (
  !depths.length ||
  depths.some((depth) => !Number.isInteger(depth) || depth < 1 || depth > 24)
) throw new Error("--depths must contain integers from 1 to 24");
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 5000) {
  throw new Error("--timeout-ms must be from 100 to 5000");
}
const repo = resolve(new URL("../..", import.meta.url).pathname);
const executable = resolve(
  options.get("--blotc") ?? `${repo}/compiler/zig-out-native-dev/bin/blotc`,
);
const entry = `${repo}/build/bench/open-type-dag.blot`;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
const compilerSha256 = await hash(await Deno.readFile(executable));

for (const depth of depths) {
  const lines = ["const nest0 = func value => return (value, value)"];
  for (let level = 1; level < depth; level++) {
    lines.push(
      `const nest${level} = func value => return do:\n  let previous = nest${
        level - 1
      } value\n  return (previous, previous)`,
    );
  }
  lines.push(
    "entry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  return marker[0]",
  );
  const source = `${lines.join("\n")}\n`;
  const sourceSha256 = await hash(new TextEncoder().encode(source));
  let compiler:
    | Awaited<ReturnType<typeof createZigProjectCompiler>>
    | undefined;
  let guest: Awaited<ReturnType<typeof instantiateGuest>> | undefined;
  const started = performance.now();
  try {
    compiler = await createZigProjectCompiler({
      executable,
      entry,
      stdRoot: `${repo}/std`,
      prelude: `${repo}/std/prelude.blot`,
      cacheDirectory: false,
      codegenTier: "development",
      startupTimeoutMs: timeoutMs,
      profileBackend: true,
    });
    const buildStarted = performance.now();
    const result = await compiler.build({
      sources: { [entry]: source },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const buildMs = performance.now() - buildStarted;
    if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
    guest = await instantiateGuest(result.bytes);
    for (const input of [0, 1, 41, 0xffffffff, 0]) {
      if (guest.call("answer", input) !== input) {
        throw new Error(`Entry changed input ${input}`);
      }
    }
    console.log(
      JSON.stringify({
        status: "complete",
        workload: "unused_open_type_dag",
        depth,
        build_ms: buildMs,
        latency_ms: performance.now() - started,
        wasm_bytes: result.bytes.length,
        wasm_sha256: await hash(result.bytes),
        source_sha256: sourceSha256,
        compiler_sha256: compilerSha256,
        phase_profile: result.stats.phaseProfile,
        work_counters: result.stats.workCounters,
      }),
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    let status = "failed";
    if (/abort|timed out/i.test(message)) status = "timeout_incomplete";
    console.log(
      JSON.stringify({
        status,
        workload: "unused_open_type_dag",
        depth,
        latency_ms: performance.now() - started,
        timeout_ms: timeoutMs,
        error: message,
        source_sha256: sourceSha256,
        compiler_sha256: compilerSha256,
      }),
    );
    Deno.exitCode = 1;
  } finally {
    guest?.dispose();
    await compiler?.dispose();
  }
}
