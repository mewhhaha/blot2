import { benchmarkWorkloads } from "./benchmark_workloads.ts";
import { deepStrictEqual as equal } from "node:assert/strict";
import { cpus } from "node:os";
import { dirname } from "node:path";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import type { Artifact } from "./host.ts";

const samples = Number(Deno.args[0] ?? 7);
const reportPath = Deno.args[1] ?? "build/native-bench.json";
const threadCounts = (Deno.args[2] ?? "1,2,3,4,5,6,7,8").split(",").map(Number);
const warmups = Number(Deno.args[3] ?? 2);
if (
  Deno.args.length > 4 || !Number.isSafeInteger(samples) || samples < 1 ||
  samples > 100 || !Number.isSafeInteger(warmups) || warmups < 0 ||
  warmups > 100 ||
  threadCounts.length === 0 ||
  threadCounts.some((n) => !Number.isInteger(n) || n < 1 || n > 8) ||
  new Set(threadCounts).size !== threadCounts.length
) {
  throw new Error(
    "Usage: compiler/native_bench.ts [samples:1..100] [report.json] [threads:1..8, comma-separated] [warmups:0..100]",
  );
}

const workloads = benchmarkWorkloads;

function distribution(values: readonly number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return {
    median_ms: sorted.length % 2
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2,
    p95_ms: sorted[Math.ceil(sorted.length * 0.95) - 1],
    samples_ms: values,
  };
}

async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

async function execute(artifact: Artifact, expected: number): Promise<void> {
  const compiled = await WebAssembly.compile(artifact.bytes);
  equal(WebAssembly.Module.imports(compiled), []);
  const instance = await WebAssembly.instantiate(compiled);
  equal((instance.exports.entry_0 as (unit: number) => number)(0), expected);
}

async function measure<T>(
  build: () => T | Promise<T>,
  verify: (result: T) => void | Promise<void>,
  prepare: () => void | Promise<void> = () => {},
) {
  const timings: number[] = [];
  for (let sample = -warmups; sample < samples; sample++) {
    await prepare();
    const started = performance.now();
    const artifact = await build();
    const elapsed = performance.now() - started;
    if (sample >= 0) timings.push(elapsed);
    await verify(artifact);
  }
  return distribution(timings);
}

const javascript = await createSourceCompiler({ prelude: "none" });
type Distribution = ReturnType<typeof distribution>;
interface BenchmarkRow {
  workload: string;
  source_sha256: string;
  wasm_sha256: string;
  threads: number;
  javascript: Distribution;
  native_startup_ms: number;
  native_full: Distribution;
  native_analysis: Distribution;
  native_first_incremental_ms: number;
  native_body_edit: Distribution;
  native_unchanged: Distribution;
  body_edit_cache: unknown;
}
const rows: BenchmarkRow[] = [];
try {
  for (const { name, source, changed, expected } of workloads) {
    const reference = javascript.compile(source);
    const changedReference = javascript.compile(changed);
    await execute(reference, expected);
    await execute(changedReference, expected + 1);
    const js = await measure(
      () => javascript.compile(source),
      (result) => equal(result, reference),
    );
    for (const threads of threadCounts) {
      const startup = performance.now();
      const native = await createNativeCompiler({ prelude: "none", threads });
      const startupMs = performance.now() - startup;
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
      });
      try {
        const full = await measure(
          () => native.compile(source),
          (result) => equal(result, reference),
        );
        const analysis = await measure(
          () => native.analyze(source),
          (result) => equal(result, reference.analysis),
        );
        const firstStart = performance.now();
        const first = await session.compile(source);
        const firstMs = performance.now() - firstStart;
        equal(first.artifact.bytes, reference.bytes);
        let editStats;
        const edits = await measure(
          () => session.compile(changed),
          async (edited) => {
            equal(edited.artifact.bytes, changedReference.bytes);
            await execute(edited.artifact, expected + 1);
            editStats = edited.stats;
          },
          async () => {
            await session.compile(source);
          },
        );
        const unchanged = await measure(
          () => session.compile(changed),
          (result) => {
            equal(result.artifact.bytes, changedReference.bytes);
            equal(result.stats.groups_checked, 0);
            equal(result.stats.entries_compiled, 0);
          },
        );
        const row = {
          workload: name,
          source_sha256: await sha256(new TextEncoder().encode(source)),
          wasm_sha256: await sha256(reference.bytes),
          threads,
          javascript: js,
          native_startup_ms: startupMs,
          native_full: full,
          native_analysis: analysis,
          native_first_incremental_ms: firstMs,
          native_body_edit: edits,
          native_unchanged: unchanged,
          body_edit_cache: editStats,
        };
        rows.push(row);
        console.log(JSON.stringify(row));
      } finally {
        await Promise.all([session.dispose(), native.dispose()]);
      }
    }
  }
} finally {
  javascript.dispose();
}
const scaling = rows.map((row) => {
  const serial = rows.find((candidate) =>
    candidate.workload === row.workload && candidate.threads === 1
  );
  return {
    workload: row.workload,
    threads: row.threads,
    javascript_ms: row.javascript.median_ms,
    native_ms: row.native_full.median_ms,
    speedup_vs_js: row.javascript.median_ms / row.native_full.median_ms,
    speedup_vs_native_1: serial
      ? serial.native_full.median_ms / row.native_full.median_ms
      : null,
  };
});
console.table(scaling);
await Deno.mkdir(dirname(reportPath), { recursive: true });
await Deno.writeTextFile(
  reportPath,
  JSON.stringify(
    {
      measured_at: new Date().toISOString(),
      runtime: Deno.version,
      system: {
        os: Deno.build.os,
        arch: Deno.build.arch,
        cpu: cpus()[0]?.model,
        logical_cpus: cpus().length,
      },
      compiler: {
        native_sha256: await sha256(
          await Deno.readFile(
            new URL("../generated/compiler/blotc", import.meta.url),
          ),
        ),
        javascript_sha256: await sha256(
          await Deno.readFile(
            new URL("../generated/compiler/compiler.js", import.meta.url),
          ),
        ),
      },
      samples,
      warmups,
      timing:
        "Sequential runs in reusable processes, source-to-Wasm including parsing/pipe transport; excludes bootstrap, startup, verification and Wasm execution. First incremental build is a separate single observation. Compiler-core fixtures, not an ECS or live game.",
      rows,
      scaling,
    },
    null,
    2,
  ) + "\n",
);
