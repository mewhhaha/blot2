// Bounded synthetic owned-backend call-graph profile.
// deno run --allow-all scripts/bench/scoped_calls.ts [--sizes 2,4,8]
// Optional: --depth 5 --timeout-ms 5000 --profile --blotc PATH
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const args = new Map<string, string | true>();
for (let at = 0; at < Deno.args.length; at++) {
  const key = Deno.args[at];
  if (
    !["--sizes", "--depth", "--timeout-ms", "--blotc", "--profile"].includes(
      key,
    )
  ) {
    throw new Error(`Unexpected argument: ${key}`);
  }
  if (key === "--profile") args.set(key, true);
  else {
    const value = Deno.args[++at];
    if (!value || value.startsWith("--")) {
      throw new Error(`${key} needs a value`);
    }
    args.set(key, value);
  }
}
const option = (name: string, fallback: string) =>
  String(args.get(name) ?? fallback);
const sizes = option("--sizes", "2,4,8").split(",").map(Number);
const depth = Number(option("--depth", "5"));
const timeoutMs = Number(option("--timeout-ms", "5000"));
if (
  !sizes.length || sizes.some((n) => !Number.isInteger(n) || n < 1 || n > 16)
) {
  throw new Error("--sizes must be comma-separated integers from 1 to 16");
}
if (!Number.isInteger(depth) || depth < 2 || depth > 12) {
  throw new Error("--depth must be an integer from 2 to 12");
}
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30_000) {
  throw new Error("--timeout-ms must be from 100 to 30000");
}

const repo = resolve(new URL("../..", import.meta.url).pathname);
const blotc = resolve(
  option("--blotc", `${repo}/zig-native/zig-out-dev/bin/blotc`),
);
const stdRoot = resolve(`${repo}/std`);
const entryPath = `${Deno.cwd()}/scoped-call-profile.blot`;
const hex = (bytes: Uint8Array) =>
  [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
const hashBytes = async (bytes: BufferSource) =>
  hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
const compilerSha256 = await hashBytes(await Deno.readFile(blotc));

function sourceFor(width: number): string {
  const lines = [
    "const leaf = func (value: U32): U32 => return @u32.add value 1",
  ];
  const tops: string[] = [];
  for (let lane = 0; lane < width; lane++) {
    let prior = "leaf";
    for (let level = 1; level <= depth; level++) {
      const name = `lane_${lane}_level_${level}`;
      lines.push(
        `const ${name} = func (value: U32): U32 => return do:`,
        `  let left = ${prior} value`,
        `  let right = ${prior} left`,
        "  return @u32.add left right",
      );
      prior = name;
    }
    tops.push(prior);
  }
  lines.push(
    "entry const answer = func (input: U32): U32 => return do:",
    "  let marker: GrowArray U32 = #[input]",
    "  let result = @u32.add input marker[0]",
  );
  for (const top of tops) {
    lines.push(`  result := @u32.add result (${top} input)`);
  }
  lines.push("  return result");
  return `${lines.join("\n")}\n`;
}

function expected(width: number, input: number): number {
  const leaf = (value: number) => (value + 1) >>> 0;
  let level = leaf;
  for (let i = 1; i <= depth; i++) {
    const previous = level;
    level = (value: number) => {
      const left = previous(value);
      const right = previous(left);
      return (left + right) >>> 0;
    };
  }
  let result = (input + input) >>> 0;
  for (let lane = 0; lane < width; lane++) {
    result = (result + level(input)) >>> 0;
  }
  return result;
}

for (const width of sizes) {
  const source = sourceFor(width);
  const sourceSha256 = await hashBytes(new TextEncoder().encode(source));
  const started = performance.now();
  let compiler:
    | Awaited<ReturnType<typeof createZigProjectCompiler>>
    | undefined;
  let guest: Awaited<ReturnType<typeof instantiateGuest>> | undefined;
  try {
    compiler = await createZigProjectCompiler({
      executable: blotc,
      entry: entryPath,
      prelude: `${stdRoot}/prelude.blot`,
      stdRoot,
      cacheDirectory: false,
      startupTimeoutMs: timeoutMs,
      profileBackend: args.has("--profile"),
    });
    const buildStarted = performance.now();
    const result = await compiler.build({
      signal: AbortSignal.timeout(timeoutMs),
      sources: { [entryPath]: source },
    });
    const buildMs = performance.now() - buildStarted;
    if (!result.success) {
      throw new Error(JSON.stringify(result.diagnostics.slice(0, 2)));
    }
    guest = await instantiateGuest(result.bytes);
    for (const input of [1, 7, 41]) {
      const actual = guest.call("answer", input);
      const want = expected(width, input);
      if (actual !== want) {
        throw new Error(`answer(${input})=${actual}; expected ${want}`);
      }
    }
    const report: Record<string, unknown> = {
      status: "complete",
      width,
      depth,
      latency_ms: performance.now() - started,
      build_ms: buildMs,
      wasm_bytes: result.bytes.length,
      work_counters: result.stats.workCounters,
      source_sha256: sourceSha256,
      compiler_sha256: compilerSha256,
    };
    if (args.has("--profile")) {
      report.phase_profile = result.stats.phaseProfile;
      report.backend_timing = result.stats.backendTiming;
    }
    console.log(JSON.stringify(report));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const timedOut = /abort|timed out/i.test(message);
    let status = "failed";
    if (timedOut) status = "timeout_incomplete";
    console.log(JSON.stringify({
      status,
      width,
      depth,
      latency_ms: performance.now() - started,
      timeout_ms: timeoutMs,
      error: message,
      source_sha256: sourceSha256,
      compiler_sha256: compilerSha256,
    }));
    Deno.exitCode = 1;
  } finally {
    guest?.dispose();
    await compiler?.dispose();
  }
}
