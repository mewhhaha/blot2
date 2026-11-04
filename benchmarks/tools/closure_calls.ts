// Bounded probe for repeated aggregate-returning literal closures.
//
//   deno run -A benchmarks/tools/closure_calls.ts --compiler PATH
//
// Each row compiles one fresh source with 1, 4, or 8 separate callsites of
// the same closure. The closure captures a Vec4 and returns a Mat4. A scalar
// closure in the same source controls for the already-supported closure path.
import { strict as assert } from "node:assert";
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const { values } = parseArgs({
  args: Deno.args,
  options: {
    compiler: {
      type: "string",
      default: "compiler/zig-out-native-dev/bin/blotc",
    },
    tier: { type: "string", default: "optimized" },
    workers: { type: "string", default: "1" },
    "timeout-ms": { type: "string", default: "5000" },
    output: { type: "string", default: "build/bench/closure-calls" },
  },
});
if (values.tier !== "optimized" && values.tier !== "development") {
  throw new Error("--tier must be optimized or development");
}
const workers = Number(values.workers);
if (!Number.isInteger(workers) || workers < 1 || workers > 16) {
  throw new Error("--workers must be an integer from 1 to 16");
}
const timeoutMs = Number(values["timeout-ms"]);
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 5000) {
  throw new Error("--timeout-ms must be an integer from 100 to 5000");
}

const compilerPath = resolve(root, values.compiler!);
const inkRoot = resolve(root, "../ink/lib");
const stdRoot = resolve(root, "std");
const outputRoot = resolve(root, values.output!);
await Deno.mkdir(outputRoot, { recursive: true });

type Hash = string;
async function sha256(bytes: BufferSource): Promise<Hash> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sourcePins(directory: string): Promise<Record<string, Hash>> {
  const pins: Record<string, Hash> = {};
  async function visit(at: string): Promise<void> {
    for await (const entry of Deno.readDir(at)) {
      const path = resolve(at, entry.name);
      if (entry.isDirectory) {
        await visit(path);
        continue;
      }
      if (!entry.isFile || !entry.name.endsWith(".blot")) continue;
      pins[path] = await sha256(await Deno.readFile(path));
    }
  }
  await visit(directory);
  return pins;
}

const compilerHash = await sha256(await Deno.readFile(compilerPath));
const importedPins = {
  ...(await sourcePins(inkRoot)),
  ...(await sourcePins(stdRoot)),
};
const harnessPath = fileURLToPath(import.meta.url);
const harnessHash = await sha256(await Deno.readFile(harnessPath));

function sourceFor(count: number): string {
  const calls: string[] = [];
  for (let index = 0; index < count; index++) {
    calls.push(
      `  let matrix_${index} = make offset (math.vec4 ${index + 4}.0 ${
        index + 5
      }.0 ${index + 6}.0 x)`,
    );
    calls.push(`  for lane in math.Mat4.lanes matrix_${index}:`);
    calls.push(`    output.push lane`);
    calls.push(`  output.push (scalar_x x)`);
  }
  return `import * as math from "ink/math"

const make = func (offset: math.Vec4) => return do:
  let captured = offset
  return func (w: math.Vec4): math.Mat4 => return
    math.Mat4.from_columns captured (math.vec4 0.0 0.0 0.0 0.0) (math.vec4 0.0 0.0 0.0 0.0) w
const scalar = func (captured: F32) => return func (value: F32): F32 => return captured

entry const main = func (x: F32) => return do:
  let offset = math.vec4 x 1.0 2.0 3.0
  let scalar_x = scalar x
  let output: GrowArray F32 = #[]
${calls.join("\n")}
  return @storage.freeze output
`;
}

function f32(value: number): number {
  return Math.fround(value);
}

function expected(count: number, input: number): number[] {
  const x = f32(input);
  const offset = [x, 1, 2, 3];
  const result: number[] = [];
  for (let index = 0; index < count; index++) {
    const w = [index + 4, index + 5, index + 6, x];
    result.push(...offset, 0, 0, 0, 0, 0, 0, 0, 0, ...w);
    result.push(x);
  }
  return result;
}

const inputs = [0, 1, -2, 0.125];
const rows: Record<string, unknown>[] = [];
for (const count of [1, 4, 8]) {
  const directory = resolve(outputRoot, `n${count}`);
  await Deno.mkdir(directory, { recursive: true });
  const entry = resolve(directory, "main.blot");
  const source = sourceFor(count);
  await Deno.writeTextFile(entry, source);
  const sourceHash = await sha256(new TextEncoder().encode(source));
  const compiler = await createZigProjectCompiler({
    executable: compilerPath,
    entry,
    imports: { "ink/": inkRoot },
    stdRoot,
    prelude: resolve(stdRoot, "prelude.blot"),
    cacheDirectory: false,
    profileBackend: true,
    codegenTier: values.tier,
    codegenWorkers: workers,
    startupTimeoutMs: timeoutMs,
  });
  try {
    const started = performance.now();
    const built = await compiler.build({
      signal: AbortSignal.timeout(timeoutMs),
    });
    const buildMs = performance.now() - started;
    if (!built.success) {
      throw new Error(`n=${count}: ${JSON.stringify(built.diagnostics)}`);
    }
    const wasmHash = await sha256(built.bytes);
    await Deno.writeFile(resolve(directory, "main.wasm"), built.bytes);
    const guest = await instantiateGuest(new WebAssembly.Module(built.bytes));
    try {
      const executions = [];
      for (const input of inputs) {
        const actual = guest.call("main", input);
        assert(actual instanceof Float32Array, "main must return Array F32");
        const want = new Float32Array(expected(count, input));
        assert.deepEqual(actual, want, `n=${count}, input=${input}`);
        executions.push({
          input,
          lanes: actual.length,
          outputSha256: await sha256(actual),
        });
      }
      rows.push({
        count,
        sourceHash,
        wasmBytes: built.bytes.length,
        wasmHash,
        buildMs,
        executionInputs: executions,
        stats: built.stats,
      });
      console.log(JSON.stringify(rows[rows.length - 1]));
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
}

const result = {
  method:
    "fresh optimized/development builds with distinct closure callsites; same literal closure node, Vec4 capture, Mat4 result; scalar closure control; four independent F32 inputs checked against lane-wise expected values",
  compiler: compilerPath,
  compilerSha256: compilerHash,
  harness: harnessPath,
  harnessSha256: harnessHash,
  tier: values.tier,
  workers,
  timeoutMs,
  inputs,
  importedSourceCount: Object.keys(importedPins).length,
  importedSourceSha256: await sha256(
    new TextEncoder().encode(JSON.stringify(importedPins)),
  ),
  rows,
};
await Deno.writeTextFile(
  resolve(outputRoot, "result.json"),
  JSON.stringify(result, null, 2) + "\n",
);
