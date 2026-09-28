/** Compare native backends; never uses the synchronous JS parity adapter. */
import { deepStrictEqual as equal } from "node:assert/strict";
import { cpus } from "node:os";
import { dirname, resolve } from "node:path";
import { benchmarkWorkloads } from "../benchmark_workloads.ts";
import { createNativeCompiler } from "../native.ts";
import { createNativeIncrementalCompiler } from "../native_incremental.ts";
import type { AnalyzedArtifact } from "../host.ts";
import { NativeProcess } from "../native_process.ts";
import { createSourceFrontend } from "../source_frontend.ts";
import { decodeNativeResponse } from "../native_protocol.ts";

const [
  baselinePath,
  candidatePath,
  output,
  samplesText = "7",
  threadsText = "1,4",
  filter = "",
  ...extra
] = Deno.args;
const samples = Number(samplesText);
const threads = threadsText.split(",").map(Number);
const warmups = 2;
if (
  !baselinePath || !candidatePath || !output || extra.length ||
  !Number.isSafeInteger(samples) || samples < 1 || samples > 100 ||
  !threads.length ||
  threads.some((n) => !Number.isInteger(n) || n < 1 || n > 64) ||
  new Set(threads).size !== threads.length
) {
  throw new Error(
    "Usage: bench_compare.ts <baseline> <candidate> <report.json> [samples:1..100] [threads:1..64,...] [workload-substring|example:ecs]",
  );
}
interface Workload {
  name: string;
  source: string;
  changed: string;
  expected: number;
  changedExpected?: number;
  prelude?: "none" | "default";
  ecs?: boolean;
}
let workloads: Workload[];
if (filter === "example:ecs") {
  const ecs = await Deno.readTextFile(
    new URL("../../examples/ecs.blot", import.meta.url),
  );
  const initializer = "Time { seconds: 0.5 }";
  if (ecs.split(initializer).length !== 2) {
    throw new Error("Expected one ECS time initializer");
  }
  const adapter =
    "\nentry const entry_0 = fn (ignored: U32) -> F32 => run 100\n";
  workloads = [{
    name: "example_ecs",
    source: ecs + adapter,
    changed: ecs.replace(initializer, "Time { seconds: 1.0 }") + adapter,
    expected: 633,
    changedExpected: 1233,
    prelude: "default",
    ecs: true,
  }];
} else {
  workloads = benchmarkWorkloads.filter((w) => w.name.includes(filter));
}
if (!workloads.length) {
  throw new Error(`No workloads match ${JSON.stringify(filter)}`);
}
const paths = [resolve(baselinePath), resolve(candidatePath)] as const;
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
const executableHashes = await Promise.all(
  paths.map(async (path) => hash(await Deno.readFile(path))),
);
const sourceHash = (source: string) => hash(new TextEncoder().encode(source));
const distribution = (values: number[]) => {
  const sorted = [...values].sort((a, b) => a - b),
    mid = Math.floor(sorted.length / 2);
  return {
    median_ms: sorted.length % 2
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2,
    samples_ms: values,
  };
};
async function execute(
  artifact: AnalyzedArtifact,
  expected: number,
  workload: Workload,
) {
  const module = await WebAssembly.compile(artifact.bytes);
  equal(WebAssembly.Module.imports(module), []);
  const instance = await WebAssembly.instantiate(module);
  equal((instance.exports.entry_0 as (x: number) => number)(0), expected);
  if (workload.ecs) {
    equal((instance.exports.run as (ticks: number) => number)(100), expected);
    equal((instance.exports.run as (ticks: number) => number)(0), 33);
    equal((instance.exports.ghost_count as (ticks: number) => number)(1), 4);
    equal((instance.exports.snapshot as () => number)(), (expected - 33) / 100);
  }
}
const phases = [
  "startup",
  "fresh_process_compile",
  "repeated_full",
  "native_roundtrip",
  "analysis",
  "body_edit",
  "unchanged",
] as const;
const rows: unknown[] = [];
const report = {
  completed: false,
  harness_sha256: await hash(await Deno.readFile(new URL(import.meta.url))),
  workload_definitions_sha256: await hash(
    await Deno.readFile(new URL("../benchmark_workloads.ts", import.meta.url)),
  ),
  prelude_sha256: await hash(
    await Deno.readFile(new URL("../../std/prelude.blot", import.meta.url)),
  ),
  measured_at: new Date().toISOString(),
  runtime: Deno.version,
  system: {
    os: Deno.build.os,
    arch: Deno.build.arch,
    cpu: cpus()[0]?.model,
    logical_cpus: cpus().length,
  },
  baseline: { path: paths[0], sha256: executableHashes[0] },
  candidate: { path: paths[1], sha256: executableHashes[1] },
  samples,
  warmups,
  timing:
    "Sequential alternating baseline/candidate pairs. Source-to-Wasm includes the common frontend and transport. Startup is separate; fresh_process_compile is the first request in a new compiler process, not a cold OS page cache or fresh Deno runtime. Other phases use persistent processes. Parsing, verification, and Wasm execution outside each timed operation are excluded. native_roundtrip replays a pre-encoded request and includes native decoding/compilation/encoding plus pipe transport, but excludes frontend parsing and host response decoding. Synthetic compiler workloads by default. example:ecs measures the repository headless ECS example with its default prelude and an equal-width time-initializer edit; it is not the graphical application or gdev.",
  rows,
};
await Deno.mkdir(dirname(output), { recursive: true });
for (const workload of workloads) {
  for (const workers of threads) {
    const options = (i: number) => ({
      executable: paths[i],
      prelude: workload.prelude ?? "none",
      threads: workers,
    });
    const natives: Awaited<ReturnType<typeof createNativeCompiler>>[] = [];
    const transports: NativeProcess[] = [];
    const frontend = await createSourceFrontend({
      prelude: workload.prelude ?? "none",
    });
    const payload = (await frontend.prepareNative(workload.source)).encode(
      "compile",
      10_000n,
    );
    const sessions: Awaited<
      ReturnType<typeof createNativeIncrementalCompiler>
    >[] = [];
    const timings = paths.map(() =>
      Object.fromEntries(phases.map((p) => [p, [] as number[]])) as Record<
        typeof phases[number],
        number[]
      >
    );
    try {
      for (let i = 0; i < 2; i++) {
        natives.push(await createNativeCompiler(options(i)));
        transports.push(await NativeProcess.start(options(i)));
        sessions.push(await createNativeIncrementalCompiler(options(i)));
      }
      const original = await natives[0].compile(workload.source);
      const changed = await natives[0].compile(workload.changed);
      await execute(original, workload.expected, workload);
      await execute(
        changed,
        workload.changedExpected ?? workload.expected + 1,
        workload,
      );
      equal(await natives[1].compile(workload.source), original);
      equal(await natives[1].compile(workload.changed), changed);
      let editStats: unknown;
      for (let sample = -warmups; sample < samples; sample++) {
        const order = (sample + warmups) % 2 ? [1, 0] : [0, 1];
        let pairedCache: unknown;
        const restoredArtifacts: AnalyzedArtifact[] = [];
        const editedArtifacts: AnalyzedArtifact[] = [];
        for (const i of order) {
          const time = async <T>(
            phase: typeof phases[number],
            operation: () => Promise<T>,
          ) => {
            const start = performance.now();
            const result = await operation();
            const elapsed = performance.now() - start;
            if (sample >= 0) timings[i][phase].push(elapsed);
            return result;
          };
          const fresh = await time(
            "startup",
            () => createNativeCompiler(options(i)),
          );
          try {
            equal(
              await time(
                "fresh_process_compile",
                () => fresh.compile(workload.source),
              ),
              original,
            );
          } finally {
            await fresh.dispose();
          }
          equal(
            await time(
              "repeated_full",
              () => natives[i].compile(workload.source),
            ),
            original,
          );
          equal(
            await time("analysis", () => natives[i].analyze(workload.source)),
            original.analysis,
          );
          const decoded = decodeNativeResponse(
            await time(
              "native_roundtrip",
              () => transports[i].request(payload),
            ),
          );
          if (decoded.operation !== "compile") {
            throw new Error("Expected a compiled artifact");
          }
          equal(decoded.artifact, original);
          // Incremental syntax uses stable revision identities, not cold offsets.
          // Compare its bytes to the full build and its entire analysis to the
          // other backend after exactly the same revision history.
          const restored = await sessions[i].compile(workload.source);
          equal(restored.artifact.bytes, original.bytes);
          restoredArtifacts[i] = restored.artifact;
          const edit = await time(
            "body_edit",
            () => sessions[i].compile(workload.changed),
          );
          equal(edit.artifact.bytes, changed.bytes);
          editedArtifacts[i] = edit.artifact;
          const cache = Object.fromEntries(
            Object.entries(edit.stats).filter(([key]) => !key.endsWith("_ms")),
          );
          if (pairedCache === undefined) pairedCache = cache;
          else equal(cache, pairedCache);
          if (sample >= 0) editStats = cache;
          const same = await time(
            "unchanged",
            () => sessions[i].compile(workload.changed),
          );
          equal(same.artifact, edit.artifact);
          equal(same.stats.groups_checked, 0);
          equal(same.stats.entries_compiled, 0);
        }
        equal(restoredArtifacts[0], restoredArtifacts[1]);
        equal(editedArtifacts[0], editedArtifacts[1]);
      }
      const summary = Object.fromEntries(phases.map((phase) => {
        const baseline = distribution(timings[0][phase]),
          candidate = distribution(timings[1][phase]);
        return [phase, {
          baseline,
          candidate,
          speedup: baseline.median_ms / candidate.median_ms,
        }];
      }));
      const row = {
        workload: workload.name,
        prelude: workload.prelude ?? "none",
        threads: workers,
        source_sha256: await sourceHash(workload.source),
        changed_source_sha256: await sourceHash(workload.changed),
        wasm_sha256: await hash(original.bytes),
        changed_wasm_sha256: await hash(changed.bytes),
        phases: summary,
        edit_cache: editStats,
      };
      rows.push(row);
      console.log(
        JSON.stringify({
          workload: workload.name,
          threads: workers,
          repeated_full: summary.repeated_full,
          body_edit: summary.body_edit,
        }),
      );
      await Deno.writeTextFile(output, JSON.stringify(report, null, 2) + "\n");
    } finally {
      for (const session of sessions) await session.dispose();
      for (const native of natives) await native.dispose();
      for (const transport of transports) await transport.dispose();
      frontend.dispose();
    }
  }
}
// Detect executable replacement during the experiment.
equal(
  await Promise.all(paths.map(async (path) => hash(await Deno.readFile(path)))),
  executableHashes,
);

report.completed = true;
await Deno.writeTextFile(output, JSON.stringify(report, null, 2) + "\n");
