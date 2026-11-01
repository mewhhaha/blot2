// Original Ink ECS descriptor readers, fresh matched compilers, five-second caps.
// deno run --no-config --no-lock -A scripts/bench/completed_readers.ts --compiler NEW --baseline OLD
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const root = resolve(new URL("../..", import.meta.url).pathname);
const { values } = parseArgs({
  args: Deno.args,
  options: {
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    baseline: { type: "string" },
    repetitions: { type: "string", default: "3" },
    output: { type: "string", default: "build/bench/completed-readers" },
    tier: { type: "string", default: "optimized" },
  },
});
const repetitions = Number(values.repetitions);
assert(Number.isInteger(repetitions) && repetitions >= 1 && repetitions <= 9);
assert(values.tier === "optimized" || values.tier === "development");
const compilers = [{
  label: "candidate",
  path: resolve(root, values.compiler!),
}];
if (values.baseline) {
  compilers.unshift({
    label: "baseline",
    path: resolve(root, values.baseline),
  });
}
const directory = resolve(root, values.output!);
await Deno.mkdir(directory, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: directory, prefix: "run-" });
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const compilerPins = Object.fromEntries(
  await Promise.all(
    compilers.map(async (
      compiler,
    ) => [compiler.label, await hash(await Deno.readFile(compiler.path))]),
  ),
);
// Pin the full source inventories, including dirty edits and transitive imports.
const sourceFiles: Record<string, string> = {};
async function pinSources(directory: string): Promise<void> {
  const pending = [];
  for await (const file of Deno.readDir(directory)) {
    const path = resolve(directory, file.name);
    if (file.isDirectory) pending.push(pinSources(path));
    else if (file.name.endsWith(".blot")) {
      pending.push((async () => {
        sourceFiles[path] = await hash(await Deno.readFile(path));
      })());
    }
  }
  await Promise.all(pending);
}
await Promise.all([
  pinSources(resolve(root, "../ink/lib")),
  pinSources(resolve(root, "std")),
]);

function sourceFor(callers: number): string {
  const lines = [
    'import * as ecs from "ink/ecs"',
    "entry const answer = func (input: U32) => return do:",
  ];
  const results = [];
  for (let at = 0; at < callers; at++) {
    lines.push(
      `  let metadata_${at}: ecs.Metadata = #[@u32.add input ${at}, @u32.add input ${
        at + 7
      }, @u32.add input ${at + 13}]`,
      `  let alive_${at}: ecs.Entities = #[true, false]`,
    );
    for (
      const [index, name] of [
        "epoch",
        "component_revision",
        "membership_revision",
      ].entries()
    ) {
      lines.push(`  let before_${at}_${index} = ecs.${name} metadata_${at}`);
      results.push(`before_${at}_${index}`);
    }
    lines.push(`  metadata_${at}[0] := @u32.add input ${at + 17}`);
    for (
      const [index, name] of [
        "epoch",
        "component_revision",
        "membership_revision",
      ].entries()
    ) {
      lines.push(`  let after_${at}_${index} = ecs.${name} metadata_${at}`);
      results.push(`after_${at}_${index}`);
    }
    for (const index of [0, 1, 2]) {
      lines.push(
        `  let live_${at}_${index} = if ecs.live alive_${at} ${index} then 1 else 0`,
      );
      results.push(`live_${at}_${index}`);
    }
  }
  lines.push(`  return #[${results.join(", ")}]`);
  return `${lines.join("\n")}\n`;
}
function expectedFor(callers: number, input: number): Uint32Array<ArrayBuffer> {
  const result = [];
  for (let at = 0; at < callers; at++) {
    result.push(
      input + at,
      input + at + 7,
      input + at + 13,
      input + at + 17,
      input + at + 7,
      input + at + 13,
      1,
      0,
      0,
    );
  }
  return new Uint32Array(result);
}
type Sample = {
  callers: number;
  label: string;
  repetition: number;
  status: string;
  buildMs?: number;
  wasmBytes?: number;
  completedPlans?: number;
  [key: string]: unknown;
};
const samples: Sample[] = [];
for (const callers of [1, 4, 8]) {
  const entry = resolve(evidence, `ecs-${callers}.blot`);
  const source = sourceFor(callers);
  await Deno.writeTextFile(entry, source);
  for (let repetition = 0; repetition < repetitions; repetition++) {
    let order = compilers;
    if (repetition % 2 === 1) order = compilers.toReversed();
    for (const executable of order) {
      const started = performance.now();
      let compiler;
      let guest;
      let sample: Sample = {
        callers,
        label: executable.label,
        repetition,
        status: "incomplete",
      };
      try {
        compiler = await createZigProjectCompiler({
          executable: executable.path,
          entry,
          imports: { "ink/": resolve(root, "../ink/lib") },
          stdRoot: resolve(root, "std"),
          prelude: resolve(root, "std/prelude.blot"),
          cacheDirectory: false,
          profileBackend: true,
          codegenTier: values.tier,
          codegenWorkers: 1,
          startupTimeoutMs: 5000,
        });
        const buildStarted = performance.now();
        const result = await compiler.build({
          signal: AbortSignal.timeout(5000),
        });
        sample.buildMs = performance.now() - buildStarted;
        if (!result.success) {
          sample.status = "failed";
          sample.diagnostics = result.diagnostics;
        } else {
          guest = await instantiateGuest(result.bytes);
          const executions = [];
          for (const input of [0, 1, 41, 0xfffffff0, 0xffffffff, 0]) {
            const actual: unknown = guest.call("answer", input);
            const expected = expectedFor(callers, input);
            assert.deepEqual(actual, expected);
            executions.push({
              input,
              words: [...expected],
              sha256: await hash(new Uint8Array(expected.buffer)),
            });
          }
          const counters = result.stats.workCounters as Record<string, number>;
          sample = {
            ...sample,
            status: "complete",
            wasmBytes: result.bytes.length,
            wasmSha256: await hash(result.bytes),
            completedPlans: counters.scoped_completed_call_plans ?? 0,
            planHits: counters.scoped_completed_call_plan_hits ?? 0,
            bodyVisits: counters.scoped_completed_call_body_visits ?? 0,
            declines: counters.scoped_completed_call_declines ?? 0,
            admissionVisits: counters.scoped_call_admission_nodes,
            emissionVisits: counters.scoped_emission_expressions,
            stats: result.stats,
            executions,
          };
          await Deno.writeFile(
            resolve(
              evidence,
              `ecs-${callers}-${executable.label}-${repetition}.wasm`,
            ),
            result.bytes,
          );
        }
      } catch (error) {
        sample.status = "failed_or_timeout";
        sample.error = String(error);
      } finally {
        guest?.dispose();
        await compiler?.dispose();
      }
      sample.wallMs = performance.now() - started;
      sample.sourceSha256 = await hash(new TextEncoder().encode(source));
      samples.push(sample);
      await Deno.writeTextFile(
        resolve(
          evidence,
          `ecs-${callers}-${executable.label}-${repetition}.json`,
        ),
        `${JSON.stringify(sample, null, 2)}\n`,
      );
      const { stats: _stats, executions: _executions, ...summary } = sample;
      console.log(JSON.stringify(summary));
    }
  }
}
function median(values: number[]): number {
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 !== 0) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
const summaries = [1, 4, 8].map((callers) => {
  const medians: Record<string, Record<string, number>> = {};
  for (const compiler of compilers) {
    const selected = samples.filter((sample) =>
      sample.callers === callers && sample.label === compiler.label &&
      sample.status === "complete"
    );
    if (selected.length !== repetitions) continue;
    medians[compiler.label] = {};
    for (
      const field of [
        "buildMs",
        "wasmBytes",
        "completedPlans",
        "planHits",
        "bodyVisits",
        "declines",
        "admissionVisits",
        "emissionVisits",
      ]
    ) {
      medians[compiler.label][field] = median(
        selected.map((sample) => Number(sample[field])),
      );
    }
  }
  let compileImprovement = null;
  let byteImprovement = null;
  let decision = "incomplete_or_unpaired";
  if (medians.baseline && medians.candidate) {
    compileImprovement = 1 -
      medians.candidate.buildMs / medians.baseline.buildMs;
    byteImprovement = 1 -
      medians.candidate.wasmBytes / medians.baseline.wasmBytes;
    decision = "rejected_missing_measured_win";
    if (
      medians.candidate.completedPlans > 0 &&
      (compileImprovement >= 0.2 || byteImprovement >= 0.3)
    ) decision = "win_pending_full_qualification";
    if (medians.candidate.completedPlans === 0) {
      decision = "rejected_no_completed_plan_activation";
    }
  }
  return { callers, medians, compileImprovement, byteImprovement, decision };
});
for (const compiler of compilers) {
  assert.equal(
    await hash(await Deno.readFile(compiler.path)),
    compilerPins[compiler.label],
    "Compiler changed during measurements",
  );
}
const report = {
  workload: "original_ink_ecs_metadata_and_liveness_readers",
  diagnosticOnly: true,
  evidence,
  compilers,
  compilerPins,
  sourceFiles,
  tier: values.tier,
  workers: 1,
  repetitions,
  deadlineMs: 5000,
  acceptance:
    "At least 20% lower median build latency or 30% fewer emitted bytes, complete matched samples, activated completed plans and independent runtime assertions.",
  limitations:
    "This bounded slice executes original imported ECS readers. It does not establish a whole-game result or guarantee activation of branch/operator readers.",
  summaries,
  samples,
};
await Deno.writeTextFile(
  resolve(evidence, "result.json"),
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(JSON.stringify({ evidence, summaries }));
if (samples.some((sample) => sample.status !== "complete")) Deno.exitCode = 1;
