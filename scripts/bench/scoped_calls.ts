// Bounded synthetic owned-backend call-graph profile.
// deno run --allow-all scripts/bench/scoped_calls.ts [--sizes 2,4,8]
// Field refinement: add --fields 72 (sizes count repeated calls); --nominal wraps Row.
// Optional: --depth 5 --timeout-ms 5000 --profile --blotc PATH
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const args = new Map<string, string | true>();
for (let at = 0; at < Deno.args.length; at++) {
  const key = Deno.args[at];
  if (
    ![
      "--sizes",
      "--fields",
      "--depth",
      "--timeout-ms",
      "--blotc",
      "--profile",
      "--nominal",
    ]
      .includes(
        key,
      )
  ) {
    throw new Error(`Unexpected argument: ${key}`);
  }
  if (key === "--profile" || key === "--nominal") args.set(key, true);
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
const fields = Number(option("--fields", "0"));
const nominal = args.has("--nominal");
const depth = Number(option("--depth", "5"));
const timeoutMs = Number(option("--timeout-ms", "5000"));
let maximumSize = 128;
if (fields === 0) maximumSize = 16;
if (
  !sizes.length ||
  sizes.some((n) => !Number.isInteger(n) || n < 1 || n > maximumSize)
) {
  throw new Error(
    `--sizes must be comma-separated integers from 1 to ${maximumSize}`,
  );
}
if (!Number.isInteger(fields) || fields < 0 || fields > 128) {
  throw new Error("--fields must be an integer from 0 to 128");
}
if (nominal && fields === 0) throw new Error("--nominal requires --fields");
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

function fieldSource(repetitions: number, fieldCount: number): string {
  const lines = [
    "const read = func row => return do:",
    "  let total = row.f0",
  ];
  if (nominal) {
    const members = Array.from(
      { length: fieldCount },
      (_, index) => `f${index}: U32`,
    ).join(", ");
    lines.unshift(`type Row is data = $Row {${members}}`);
  }
  for (let index = 1; index < fieldCount; index++) {
    lines.push(`  total := @u32.add total row.f${index}`);
  }
  lines.push("  return total");
  let deepest = "read";
  for (let level = 1; level <= depth; level++) {
    const stage = `stage_${level}`;
    lines.push(
      `const ${stage} = func row => return @u32.add (${deepest} row) (${deepest} row)`,
    );
    deepest = stage;
  }
  const record = Array.from(
    { length: fieldCount },
    (_, index) => `f${index}: @u32.add input ${index}`,
  ).join(", ");
  let constructor = "";
  if (nominal) constructor = "$Row ";
  lines.push(
    `const make = func (input: U32) => return ${constructor}{${record}}`,
  );
  lines.push(
    "entry const answer = func (input: U32): U32 => return do:",
    "  let marker: GrowArray U32 = #[input]",
    "  let result = @u32.add input marker[0]",
  );
  for (let call = 0; call < repetitions; call++) {
    lines.push(`  result := @u32.add result (${deepest} (make input))`);
  }
  lines.push("  return result");
  return `${lines.join("\n")}\n`;
}

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

function expectedFields(
  repetitions: number,
  fieldCount: number,
  depth: number,
  input: number,
) {
  let oneRead = 0;
  for (let index = 0; index < fieldCount; index++) {
    oneRead = (oneRead + input + index) >>> 0;
  }
  for (let level = 0; level < depth; level++) {
    oneRead = (oneRead + oneRead) >>> 0;
  }
  let result = (input + input) >>> 0;
  for (let call = 0; call < repetitions; call++) {
    result = (result + oneRead) >>> 0;
  }
  return result;
}

for (const width of sizes) {
  let source: string;
  if (fields === 0) source = sourceFor(width);
  else source = fieldSource(width, fields);
  let workload = "field_refinement";
  if (nominal) workload = "nominal_field_refinement";
  if (fields === 0) workload = "call_graph";
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
      let want = expectedFields(width, fields, depth, input);
      if (fields === 0) want = expected(width, input);
      if (actual !== want) {
        throw new Error(`answer(${input})=${actual}; expected ${want}`);
      }
    }
    const report: Record<string, unknown> = {
      status: "complete",
      workload,
      width,
      fields,
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
      workload,
      width,
      fields,
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
