import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { cpus } from "node:os";
import {
  nativeCpuHz,
  nativeCpuMilliseconds,
  nativeCpuSample,
  nativeScheduler,
} from "./native_cpu_bench.ts";
import { benchmarkWorkloads } from "./benchmark_workloads.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import type { Artifact } from "./host.ts";

// Compare Blot program compilation, not the time to build the compiler binary
// and not execution of the emitted program. The Deno host/filesystem stay warm;
// each full request and each initial/edit/cache sequence uses a fresh process.
const [
  baselineArg,
  candidateArg,
  reportArg,
  samplesArg = "7",
  threadsArg = "1,4",
  filter = "",
] = Deno.args;
const samples = Number(samplesArg);
const threadCounts = threadsArg.split(",").map(Number);
if (
  !baselineArg || !candidateArg || !reportArg || Deno.args.length > 6 ||
  !Number.isInteger(samples) || samples < 1 || samples > 31 ||
  threadCounts.some((n) => !Number.isInteger(n) || n < 1 || n > 64) ||
  new Set(threadCounts).size !== threadCounts.length
) {
  throw new Error(
    "Usage: compile_time_bench.ts baseline-executable candidate-executable report.json [samples:1..31] [threads:1..64,...] [workload-filter]",
  );
}
const executables = [resolve(baselineArg), resolve(candidateArg)] as const;
const reportPath = resolve(reportArg);
const encoder = new TextEncoder();
async function hash(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
function distribution(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  const midpoint = Math.floor(sorted.length / 2);
  return {
    median_ms: sorted.length % 2
      ? sorted[midpoint]
      : (sorted[midpoint - 1] + sorted[midpoint]) / 2,
    min_ms: sorted[0],
    max_ms: sorted.at(-1),
    samples_ms: values,
  };
}
interface Workload {
  name: string;
  source: string;
  changed?: string;
  prelude: "none" | "default";
  verify: (artifact: Artifact, changed: boolean) => Promise<void>;
}
async function runExport(
  artifact: Artifact,
  name: string,
  argument: number,
  expected: number,
) {
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  equal(
    (instance.exports[name] as (value: number) => number)(argument),
    expected,
  );
}
const workloads: Workload[] = benchmarkWorkloads.filter((workload) =>
  ["lexical_256", "balanced_64", "reader_64", "chain_64", "nominal_256"]
    .includes(workload.name)
).map((workload) => ({
  ...workload,
  prelude: "none",
  verify: (artifact, changed) =>
    runExport(artifact, "entry_0", 0, workload.expected + Number(changed)),
}));
for (const name of ["generic_effects", "ecs"]) {
  workloads.push({
    name: `example_${name}`,
    prelude: "default",
    source: await Deno.readTextFile(
      new URL(`../examples/${name}.blot`, import.meta.url),
    ),
    verify: (artifact) =>
      name === "ecs"
        ? runExport(artifact, "run", 100, 633)
        : runExport(artifact, "answer", 0, 42),
  });
}
const selected = workloads.filter((workload) =>
  !filter || workload.name.includes(filter)
);
if (selected.length === 0) throw new Error(`No workloads match ${filter}`);
const rows: unknown[] = [];
const report = {
  methodology:
    "Two unrecorded pairs then alternating pairs. Fresh native process/frontend for full compilation and for each initial/edit/unchanged/revert sequence. Warm Deno host and filesystem; no cache flush. analysis:false. Timers include parser, IPC, inference, specialization, Wasm emission and response decoding; process/frontend startup is separate. Execution, byte comparisons and Linux proc sampling are outside wall timers. Native CPU excludes frontend work; its tick resolution is reported. No timing thresholds.",
  baseline: {
    executable: executables[0],
    sha256: await hash(await Deno.readFile(executables[0])),
  },
  candidate: {
    executable: executables[1],
    sha256: await hash(await Deno.readFile(executables[1])),
  },
  host: {
    deno: Deno.version,
    os: Deno.build.os,
    arch: Deno.build.arch,
    cpu: cpus()[0]?.model,
    logical_cpus: cpus().length,
  },
  native_cpu_tick_ms: nativeCpuHz === undefined ? null : 1000 / nativeCpuHz,
  samples,
  threadCounts,
  rows,
};
await Deno.mkdir(dirname(reportPath), { recursive: true });
async function save() {
  await Deno.writeTextFile(reportPath, JSON.stringify(report, null, 2) + "\n");
}
for (const workload of selected) {
  for (const threads of threadCounts) {
    const full: number[][] = [[], []];
    const fullCpu: number[][] = [[], []];
    const initialCpu: number[][] = [[], []];
    const editCpu: number[][] = [[], []];
    const revertCpu: number[][] = [[], []];
    const schedulers: unknown[][] = [[], []];
    const startups: number[][] = [[], []];
    const initial: number[][] = [[], []];
    const edits: number[][] = [[], []];
    const unchanged: number[][] = [[], []];
    const reverts: number[][] = [[], []];
    const sessionStartups: number[][] = [[], []];
    const editStats: unknown[][] = [[], []];
    let reference: Uint8Array<ArrayBuffer> | undefined;
    let changedReference: Uint8Array<ArrayBuffer> | undefined;
    for (let sample = -2; sample < samples; sample++) {
      const order = sample % 2 === 0 ? [1, 0] : [0, 1];
      for (const side of order) {
        const options = {
          executable: executables[side],
          threads,
          priority: "inherit" as const,
          prelude: workload.prelude,
        };
        let start = performance.now();
        const compiler = await createNativeCompiler(options);
        const startupMs = performance.now() - start;
        try {
          const pid = Deno.build.os === "linux" ? compiler.pid : undefined;
          const before = await nativeCpuSample(pid);
          start = performance.now();
          const artifact = await compiler.compile(workload.source, {
            analysis: false,
          });
          const ms = performance.now() - start;
          const after = await nativeCpuSample(pid);
          const cpu = nativeCpuMilliseconds(before, after);
          reference ??= artifact.bytes;
          equal(
            artifact.bytes,
            reference,
            `${workload.name}: full artifact mismatch`,
          );
          await workload.verify(artifact, false);
          if (sample >= 0) {
            full[side].push(ms);
            if (cpu !== null) fullCpu[side].push(cpu);
            schedulers[side].push({
              before: nativeScheduler(before),
              after: nativeScheduler(after),
            });
            startups[side].push(startupMs);
          }
        } finally {
          await compiler.dispose();
        }
        if (workload.changed === undefined) continue;
        start = performance.now();
        const session = await createNativeIncrementalCompiler(options);
        const sessionStartupMs = performance.now() - start;
        try {
          const pid = Deno.build.os === "linux" ? session.pid : undefined;
          const beforeFirst = await nativeCpuSample(pid);
          start = performance.now();
          const first = await session.compile(workload.source, {
            analysis: false,
          });
          const firstMs = performance.now() - start;
          const afterFirst = await nativeCpuSample(pid);
          equal(first.artifact.bytes, reference);
          start = performance.now();
          const edited = await session.compile(workload.changed, {
            analysis: false,
          });
          const editMs = performance.now() - start;
          const afterEdit = await nativeCpuSample(pid);
          changedReference ??= edited.artifact.bytes;
          equal(
            edited.artifact.bytes,
            changedReference,
            `${workload.name}: edited artifact mismatch`,
          );
          await workload.verify(edited.artifact, true);
          ok(
            !edited.stats.result_reused,
            "Changed source must enter the native compiler",
          );
          start = performance.now();
          const cached = await session.compile(workload.changed, {
            analysis: false,
          });
          const cachedMs = performance.now() - start;
          equal(cached.artifact.bytes, changedReference);
          equal(cached.stats.result_reused, true);
          equal(cached.stats.groups_checked, 0);
          const beforeRevert = await nativeCpuSample(pid);
          start = performance.now();
          const reverted = await session.compile(workload.source, {
            analysis: false,
          });
          const revertMs = performance.now() - start;
          const afterRevert = await nativeCpuSample(pid);
          equal(reverted.artifact.bytes, reference);
          if (sample >= 0) {
            const firstCpu = nativeCpuMilliseconds(beforeFirst, afterFirst);
            const editedCpu = nativeCpuMilliseconds(afterFirst, afterEdit);
            const revertedCpu = nativeCpuMilliseconds(
              beforeRevert,
              afterRevert,
            );
            if (firstCpu !== null) initialCpu[side].push(firstCpu);
            if (editedCpu !== null) editCpu[side].push(editedCpu);
            if (revertedCpu !== null) revertCpu[side].push(revertedCpu);
            initial[side].push(firstMs);
            edits[side].push(editMs);
            unchanged[side].push(cachedMs);
            reverts[side].push(revertMs);
            sessionStartups[side].push(sessionStartupMs);
            editStats[side].push(edited.stats);
          }
        } finally {
          await session.dispose();
        }
      }
    }
    const compare = (values: number[][]) => ({
      baseline: distribution(values[0]),
      candidate: distribution(values[1]),
      speedup: distribution(values[1]).median_ms === 0
        ? null
        : distribution(values[0]).median_ms / distribution(values[1]).median_ms,
    });
    const row = {
      workload: workload.name,
      threads,
      prelude: workload.prelude,
      source_bytes: encoder.encode(workload.source).length,
      source_sha256: await hash(encoder.encode(workload.source)),
      changed_source_sha256: workload.changed === undefined
        ? undefined
        : await hash(encoder.encode(workload.changed)),
      wasm_sha256: await hash(reference!),
      changed_wasm_sha256: changedReference && await hash(changedReference),
      full: compare(full),
      native_cpu: nativeCpuHz === undefined
        ? undefined
        : { full: compare(fullCpu), schedulers },
      startup: compare(startups),
      incremental: workload.changed === undefined ? undefined : {
        initial: compare(initial),
        native_cpu: nativeCpuHz === undefined ? undefined : {
          initial: compare(initialCpu),
          edit: compare(editCpu),
          revert: compare(revertCpu),
        },
        edit: compare(edits),
        unchanged: compare(unchanged),
        revert: compare(reverts),
        startup: compare(sessionStartups),
        edit_stats: editStats,
      },
    };
    rows.push(row);
    await save();
    console.log(JSON.stringify({
      workload: row.workload,
      threads,
      full_ms: [row.full.baseline.median_ms, row.full.candidate.median_ms],
      full_speedup: row.full.speedup,
      edit_speedup: row.incremental?.edit.speedup,
      native_cpu_ms: row.native_cpu &&
        [
          row.native_cpu.full.baseline.median_ms,
          row.native_cpu.full.candidate.median_ms,
        ],
    }));
  }
}
