// Source-to-Wasm latency, not compiler-build time or generated-program speed.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { benchmarkWorkloads } from "./benchmark_workloads.ts";
import { createNativeCompiler } from "./native.ts";
import {
  createNativeIncrementalCompiler,
  type NativeIncrementalStats,
} from "./native_incremental.ts";
import {
  matchingNativeChild,
  nativeCpuHz,
  nativeCpuMilliseconds,
  nativeCpuSample,
  nativeScheduler,
  ownedNativeChildren,
} from "./native_cpu_bench.ts";
import { loadSourceProject } from "./source_project.ts";
import type { Artifact } from "./host.ts";

const rounds = Number(Deno.args[2] ?? 5);
const threadCounts = (Deno.args[3] ?? "1,4").split(",").map(Number);
const reportPath = Deno.args[4] ?? "build/compile-time.json";
const selected = Deno.args[5]?.split(",");
if (
  Deno.args.length < 2 || Deno.args.length > 6 || !Number.isInteger(rounds) ||
  rounds < 3 || rounds > 20 ||
  threadCounts.some((n) => !Number.isInteger(n) || n < 1 || n > 64) ||
  new Set(threadCounts).size !== threadCounts.length
) {
  throw new Error(
    "Usage: symbol_compile_bench.ts BASELINE CANDIDATE [rounds:3..20] [threads:1,4] [report.json] [workloads,comma,separated]",
  );
}
const executables = Deno.args.slice(0, 2).map((p) => pathToFileURL(resolve(p)));
const options = { analysis: false, const_steps: 100_000n } as const;
const rows: Record<string, unknown>[] = [];
const names = [...benchmarkWorkloads.map((w) => w.name), "ecs_example"];
if (selected?.some((name) => !names.includes(name))) {
  throw new Error("Unknown benchmark workload");
}
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
}
function distribution(values: number[]) {
  const ordered = [...values].sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  return {
    median_ms: ordered.length % 2
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2,
    samples_ms: values,
  };
}
async function verify(
  artifact: Artifact,
  expected: Uint8Array<ArrayBuffer>,
  result?: number,
) {
  equal(artifact.bytes, expected, "source-to-Wasm artifact changed");
  const module = await WebAssembly.compile(artifact.bytes);
  if (result !== undefined) {
    equal(WebAssembly.Module.imports(module), []);
    const instance = await WebAssembly.instantiate(module);
    equal((instance.exports.entry_0 as (n: number) => number)(0), result);
  }
}
async function save() {
  await Deno.writeTextFile(
    reportPath,
    JSON.stringify(
      {
        versions: Deno.version,
        platform: Deno.build,
        rounds,
        thread_counts: threadCounts,
        native_cpu_resolution_ms: nativeCpuHz ? 1000 / nativeCpuHz : null,
        executable_sha256: await Promise.all(
          executables.map(async (p) => hash(await Deno.readFile(p))),
        ),
        methodology:
          "Alternating paired order. Fresh native process for cold calls. One untimed paired warmup per workload. Source loading and process/frontend initialization separately timed. Persistent sessions for body edits and unchanged hits. Same host sources for both native executables. Filesystem caches not flushed; Deno host stays alive. All Wasm equality/execution checks outside timed regions. Native CPU excludes frontend/host; short cases may round to zero ticks.",
        rows,
      },
      null,
      2,
    ) + "\n",
  );
}
for (const threads of threadCounts) {
  for (const name of names.filter((n) => !selected || selected.includes(n))) {
    const workload = benchmarkWorkloads.find((w) => w.name === name);
    const cold: number[][] = [[], []];
    const coldCpu: number[][] = [[], []];
    const startup: number[][] = [[], []];
    const load: number[][] = [[], []];
    const samples: unknown[] = [];
    let oracle: Uint8Array<ArrayBuffer> | undefined;
    let editedOracle: Uint8Array<ArrayBuffer> | undefined;
    for (let round = -1; round < rounds; round++) {
      for (const side of round % 2 ? [1, 0] : [0, 1]) {
        const children = await ownedNativeChildren();
        const initStart = performance.now();
        const compiler = await createNativeCompiler({
          executable: executables[side],
          threads,
          prelude: workload ? "none" : "default",
        });
        const initMs = performance.now() - initStart;
        try {
          const pid = await matchingNativeChild(executables[side], children);
          const loadStart = performance.now();
          const source = workload?.source ??
            await loadSourceProject(
              new URL("../examples/ecs.blot", import.meta.url),
              { imports: { "std/": new URL("../std/", import.meta.url) } },
            );
          const loadMs = performance.now() - loadStart;
          const before = await nativeCpuSample(pid);
          const begin = performance.now();
          const artifact = await compiler.compile(source, options);
          const wall = performance.now() - begin;
          const after = await nativeCpuSample(pid);
          const cpu = nativeCpuMilliseconds(before, after);
          oracle ??= artifact.bytes.slice();
          await verify(artifact, oracle, workload?.expected);
          if (round >= 0) {
            cold[side].push(wall);
            startup[side].push(initMs);
            load[side].push(loadMs);
            if (cpu !== null) coldCpu[side].push(cpu);
            samples.push({
              round,
              side,
              compile_ms: wall,
              native_cpu_ms: cpu,
              startup_ms: initMs,
              load_ms: loadMs,
              scheduler: nativeScheduler(after),
            });
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
    ok(oracle);
    const coldRow = {
      workload: name,
      threads,
      mode: "cold",
      source_sha256: workload
        ? await hash(new TextEncoder().encode(workload.source))
        : null,
      wasm_sha256: await hash(oracle),
      bytes: oracle.length,
      baseline: distribution(cold[0]),
      candidate: distribution(cold[1]),
      speedup: distribution(cold[0]).median_ms /
        distribution(cold[1]).median_ms,
      baseline_cpu: coldCpu[0].length ? distribution(coldCpu[0]) : null,
      candidate_cpu: coldCpu[1].length ? distribution(coldCpu[1]) : null,
      startup: startup.map(distribution),
      project_load: load.map(distribution),
      samples,
    };
    rows.push(coldRow);
    console.log(JSON.stringify(coldRow));
    await save();
    if (!workload) continue;
    const sessions: Awaited<
      ReturnType<typeof createNativeIncrementalCompiler>
    >[] = [];
    const pids: (number | undefined)[] = [];
    const first: number[] = [];
    const edits: number[][] = [[], []];
    const hits: number[][] = [[], []];
    const editSamples: unknown[] = [];
    try {
      for (const side of [0, 1]) {
        const children = await ownedNativeChildren();
        const session = await createNativeIncrementalCompiler({
          executable: executables[side],
          threads,
          prelude: "none",
        });
        sessions.push(session);
        pids.push(await matchingNativeChild(executables[side], children));
        const t = performance.now();
        const initial = await session.compile(workload.source, options);
        first.push(performance.now() - t);
        await verify(initial.artifact, oracle, workload.expected);
      }
      for (let round = -1; round < rounds; round++) {
        for (const side of round % 2 ? [1, 0] : [0, 1]) {
          await verify(
            (await sessions[side].compile(workload.source, options)).artifact,
            oracle,
            workload.expected,
          );
          const before = await nativeCpuSample(pids[side]);
          let t = performance.now();
          const edited: { artifact: Artifact; stats: NativeIncrementalStats } =
            await sessions[side].compile(
              workload.changed,
              options,
            );
          const editMs = performance.now() - t;
          const after = await nativeCpuSample(pids[side]);
          editedOracle ??= edited.artifact.bytes.slice();
          await verify(edited.artifact, editedOracle, workload.expected + 1);
          equal(
            edited.stats.result_reused,
            false,
            "body edit was served as an unchanged hit",
          );
          t = performance.now();
          const hit: { artifact: Artifact; stats: NativeIncrementalStats } =
            await sessions[side].compile(workload.changed, options);
          const hitMs = performance.now() - t;
          equal(hit.stats.result_reused, true);
          equal(hit.stats.groups_checked, 0);
          equal(hit.stats.entries_compiled, 0);
          await verify(hit.artifact, editedOracle, workload.expected + 1);
          if (round >= 0) {
            edits[side].push(editMs);
            hits[side].push(hitMs);
            editSamples.push({
              round,
              side,
              edit_ms: editMs,
              native_cpu_ms: nativeCpuMilliseconds(before, after),
              unchanged_ms: hitMs,
              stats: edited.stats,
            });
          }
        }
      }
      const row = {
        workload: name,
        threads,
        mode: "incremental",
        edited_wasm_sha256: await hash(editedOracle!),
        first_request_ms: first,
        first_request_note:
          "One observation per side; not a median or speedup claim",
        baseline_edit: distribution(edits[0]),
        candidate_edit: distribution(edits[1]),
        edit_speedup: distribution(edits[0]).median_ms /
          distribution(edits[1]).median_ms,
        baseline_unchanged: distribution(hits[0]),
        candidate_unchanged: distribution(hits[1]),
        samples: editSamples,
      };
      rows.push(row);
      console.log(JSON.stringify(row));
      await save();
    } finally {
      await Promise.all(sessions.map((s) => s.dispose()));
    }
  }
}
