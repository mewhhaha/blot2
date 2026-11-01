// Compare the actual original and direct-destination kites.draw producers.
// Both builds retain the real import graph and native asset configuration.
// Compiler startup/build default to five seconds; integration caps at 30 seconds.
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    "baseline-compiler": { type: "string" },
    "timeout-ms": { type: "string", default: "5000" },
    trace: { type: "boolean", default: false },
    "baseline-ref": {
      type: "string",
      default: "fcebd8a7adc8d3e7fed7db85a314a892d15a2411",
    },
    "baseline-source": { type: "string" },
    output: { type: "string", default: "build/bench/kites-stream" },
    tier: { type: "string", default: "optimized" },
    workers: { type: "string", default: "1" },
  },
});
if (values.tier !== "optimized" && values.tier !== "development") {
  throw new Error("--tier must be optimized or development");
}
const timeoutMs = Number(values["timeout-ms"]);
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30_000) {
  throw new Error("--timeout-ms must be from 100 to 30000");
}
const workers = Number(values.workers);
if (!Number.isInteger(workers) || workers < 1 || workers > 16) {
  throw new Error("--workers must be from 1 to 16");
}
const repo = resolve(new URL("../..", import.meta.url).pathname);
const root = resolve(repo, "../gdev");
const executable = resolve(
  values.compiler ?? `${repo}/zig-native/zig-out-native-dev/bin/blotc`,
);
const baselineExecutable = resolve(values["baseline-compiler"] ?? executable);
const entry = `${root}/tests/kites_render.blot`;
const producer = `${root}/src/actors/kites.blot`;
const entrySource = await Deno.readTextFile(entry);
const candidate = await Deno.readTextFile(producer);
let baseline: string;
if (values["baseline-source"]) {
  baseline = await Deno.readTextFile(resolve(values["baseline-source"]));
} else {
  const original = await new Deno.Command("git", {
    cwd: root,
    args: ["show", `${values["baseline-ref"]}:src/actors/kites.blot`],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!original.success) {
    throw new Error(new TextDecoder().decode(original.stderr));
  }
  baseline = new TextDecoder().decode(original.stdout);
}
const penBytes = await Deno.readFile(`${root}/pen.json`);
const settings =
  JSON.parse(new TextDecoder().decode(penBytes)).compiler.settings;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const hashText = (source: string) => hash(new TextEncoder().encode(source));
const directory = resolve(values.output);
await Deno.mkdir(directory, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: directory, prefix: "pair-" });
await Deno.writeTextFile(`${evidence}/kites-original.blot`, baseline);
await Deno.writeTextFile(`${evidence}/kites-candidate.blot`, candidate);
await Deno.writeTextFile(`${evidence}/kites-render.blot`, entrySource);
const scenarios = [0, 1, 2, 4, 8, 16, 31];
const streams = new Map<string, Map<number, Float32Array>>();
const builds: Record<string, unknown>[] = [];
for (
  const [name, source] of [["baseline", baseline], ["candidate", candidate]]
) {
  let runExecutable = executable;
  if (name === "baseline") runExecutable = baselineExecutable;
  let compiler;
  let guest;
  let started;
  let elapsed;
  let outcome: Record<string, unknown>;
  try {
    compiler = await createZigProjectCompiler({
      executable: runExecutable,
      entry,
      prelude: `${repo}/std/prelude.blot`,
      stdRoot: `${repo}/std`,
      imports: Object.fromEntries(
        Object.entries(settings.imports).map(([key, path]) => [
          key,
          resolve(root, path as string),
        ]),
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
      startupTimeoutMs: timeoutMs,
      profileBackend: true,
      profileTrace: values.trace,
      codegenTier: values.tier,
      codegenWorkers: workers,
    });
    started = performance.now();
    const result = await compiler.build({
      sources: { [entry]: entrySource, [producer]: source },
      signal: AbortSignal.timeout(timeoutMs),
    });
    elapsed = performance.now() - started;
    if (!result.success) {
      outcome = { status: "failed", diagnostics: result.diagnostics };
      Deno.exitCode = 1;
    } else {
      await Deno.writeFile(`${evidence}/${name}.wasm`, result.bytes);
      guest = await instantiateGuest(result.bytes);
      const runs = [];
      const captured = new Map<number, Float32Array>();
      for (const scenario of scenarios) {
        const result = guest.call("stream", scenario);
        if (!(result instanceof Float32Array)) {
          throw new Error("stream must return Array F32");
        }
        const stream = result.slice();
        if (stream.length < 2 || stream[0] < 1 || stream[1] < 1) {
          throw new Error("missing original draw/vector prefixes");
        }
        for (const value of stream) {
          if (!Number.isFinite(value)) throw new Error("nonfinite draw lane");
        }
        const bytes = new Uint8Array(stream.buffer);
        await Deno.writeFile(`${evidence}/${name}-${scenario}.f32`, bytes);
        captured.set(scenario, stream);
        runs.push({
          scenario,
          draw_count: stream[0],
          vector_count: stream[1],
          lane_count: stream.length,
          sha256: await hash(bytes),
        });
      }
      streams.set(name, captured);
      outcome = {
        status: "complete",
        wasm_bytes: result.bytes.length,
        wasm_sha256: await hash(result.bytes),
        stats: result.stats,
        runs,
      };
    }
  } catch (error) {
    if (elapsed === undefined && started !== undefined) {
      elapsed = performance.now() - started;
    }
    let status = "failed";
    if (/abort|timed out/i.test(String(error))) status = "timeout_incomplete";
    outcome = { status, error: String(error) };
    Deno.exitCode = 1;
  } finally {
    guest?.dispose();
    await compiler?.dispose();
  }
  const build = {
    name,
    build_ms: elapsed,
    profileProgress: compiler?.profileProgress,
    ...outcome,
  };
  builds.push(build);
  console.log(JSON.stringify(build));
}
const comparisons = [];
const originalStreams = streams.get("baseline");
const candidateStreams = streams.get("candidate");
if (originalStreams && candidateStreams) {
  for (const scenario of scenarios) {
    const before = originalStreams.get(scenario)!;
    const after = candidateStreams.get(scenario)!;
    const beforeBits = new Uint32Array(before.buffer);
    const afterBits = new Uint32Array(after.buffer);
    let firstDifference = -1;
    for (let at = 0; at < Math.max(beforeBits.length, afterBits.length); at++) {
      if (beforeBits[at] !== afterBits[at]) {
        firstDifference = at;
        break;
      }
    }
    const equal = firstDifference === -1;
    if (!equal) Deno.exitCode = 1;
    comparisons.push({ scenario, equal, first_difference: firstDifference });
  }
}
let status = "incomplete";
if (comparisons.length === scenarios.length) {
  status = "complete";
  if (comparisons.some((comparison) => !comparison.equal)) status = "mismatch";
}
const report = {
  workload: "original_kites_draw_complete_stream",
  status,
  evidence,
  deadline_ms: timeoutMs,
  execution: "V8",
  codegen_tier: values.tier,
  codegen_workers: workers,
  baseline_ref: values["baseline-ref"],
  baseline_source: values["baseline-source"] ?? null,
  pins: {
    compiler_sha256: await hash(await Deno.readFile(executable)),
    baseline_compiler_sha256: await hash(
      await Deno.readFile(baselineExecutable),
    ),
    entry_sha256: await hashText(entrySource),
    baseline_producer_sha256: await hashText(baseline),
    candidate_producer_sha256: await hashText(candidate),
    pen_json_sha256: await hash(penBytes),
  },
  builds,
  comparisons,
};
await Deno.writeTextFile(
  `${evidence}/result.json`,
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(JSON.stringify({ status, evidence, comparisons }));
