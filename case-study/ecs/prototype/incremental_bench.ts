// Archived compiler-coupled prototype; not part of the current compiler.
import {
  deepStrictEqual as equal,
  notDeepStrictEqual,
  ok,
} from "node:assert/strict";
import { dirname } from "node:path";
import { createIncrementalCompiler } from "./incremental.ts";
import { createSourceCompiler } from "./source.ts";
import {
  createEcsRuntime,
  type EcsRuntime,
  type EcsWorld,
} from "./ecs_runtime.ts";
import { ecsWorkload } from "./ecs_workload.ts";
import type { Analysis, EcsArtifact, Type } from "./host.ts";

type IncrementalCompiler = Awaited<
  ReturnType<typeof createIncrementalCompiler>
>;
type CompilationStats = Awaited<
  ReturnType<IncrementalCompiler["compileEcs"]>
>["stats"];
type WorkerCount = 1 | 2 | 4 | 8;

interface Reference {
  readonly name: string;
  readonly source: string;
  readonly artifact: EcsArtifact;
  readonly runtime: EcsRuntime;
  readonly world: EcsWorld;
  readonly clean_compile_ms: number;
  readonly source_sha256: string;
  readonly wasm_sha256: string;
}

interface Sample {
  readonly startup_ms: number;
  readonly compile_ms: number;
  readonly reload_ms: number;
  readonly standalone_wasm_ms: number;
  readonly edit_to_ready_ms: number;
  readonly startup_to_ready_ms: number;
  readonly stats: CompilationStats;
}

const samples = Number(Deno.args[0] ?? 5);
const reportPath = Deno.args[1] ?? "build/incremental-bench.json";
const workerCounts = (Deno.args[2] ?? "1,2,4,8").split(",").map(Number);
if (
  Deno.args.length > 3 || !Number.isSafeInteger(samples) || samples < 1 ||
  samples > 100 || workerCounts.length === 0 ||
  workerCounts.some((count) => ![1, 2, 4, 8].includes(count)) ||
  new Set(workerCounts).size !== workerCounts.length
) {
  throw new Error(
    "Usage: compiler/incremental_bench.ts [samples: 1..100] [report.json] [workers: 1,2,4,8]",
  );
}

function replaceOnce(source: string, previous: string, next: string): string {
  const parts = source.split(previous);
  equal(parts.length, 2, `Expected exactly one edit target: ${previous}`);
  return parts[0] + next + parts[1];
}

const baseline = `data CompileMarker = CompileMarker U32
const movement_offset = 1
const advance = fn value => value + movement_offset
${
  replaceOnce(
    ecsWorkload(16),
    "Position0 (current + speed * seconds)",
    "Position0 (advance (current + speed * seconds))",
  )
}`;
const edits = [
  { name: "identical", source: baseline },
  { name: "trivia", source: "// Incremental trivia-only edit.\n" + baseline },
  {
    name: "body",
    source: replaceOnce(
      baseline,
      "const advance = fn value => value + movement_offset",
      "const advance = fn value => value + movement_offset + 1",
    ),
  },
  {
    name: "effect",
    source: replaceOnce(
      baseline,
      "const read_position_0 = fn () => @ecs.get Position0",
      `const read_position_0 = fn () => do:
  use @ecs.get Velocity1
  use position <- @ecs.get Position0
  return position`,
    ),
  },
  {
    // Adds a constructor tag before ECS storage, without changing its U32 ABI.
    name: "layout",
    source: replaceOnce(
      baseline,
      "data CompileMarker = CompileMarker U32",
      "data CompileMarker = CompileMarker U32 | CompileMarkerEmpty",
    ),
  },
  {
    name: "const",
    source: replaceOnce(
      baseline,
      "const movement_offset = 1",
      "const movement_offset = 2",
    ),
  },
  {
    name: "all_bodies",
    source: baseline.replaceAll(
      "current + speed * seconds",
      "current + speed * seconds + 1",
    ),
  },
];

function seedWorld(runtime: EcsRuntime, artifact: EcsArtifact): EcsWorld {
  return runtime.createWorld({
    entityCount: 3,
    components: artifact.storage.filter((slot) =>
      slot.storage.$ === "Component"
    )
      .map((slot) => ({
        identity: slot.identity,
        values: [1, slot.identity.declaration === "Velocity1" ? null : 2, null],
      })),
    resources: artifact.storage.filter((slot) => slot.storage.$ === "Resource")
      .map((slot) => ({ identity: slot.identity, value: 1 })),
  });
}

function assertWorld(
  actual: { readonly runtime: EcsRuntime; readonly world: EcsWorld },
  expected: Reference,
): void {
  equal(actual.world.entityCount, expected.world.entityCount);
  const actualNext = actual.runtime.run(actual.world);
  const expectedNext = expected.runtime.run(expected.world);
  for (const slot of expected.artifact.storage) {
    if (slot.storage.$ === "Resource") {
      equal(
        actual.runtime.readResource(actual.world, slot.identity),
        expected.runtime.readResource(expected.world, slot.identity),
      );
      equal(
        actual.runtime.readResource(actualNext, slot.identity),
        expected.runtime.readResource(expectedNext, slot.identity),
      );
    } else {
      for (let entity = 0; entity < actual.world.entityCount; entity++) {
        equal(
          actual.runtime.readComponent(actual.world, slot.identity, entity),
          expected.runtime.readComponent(expected.world, slot.identity, entity),
        );
        equal(
          actual.runtime.readComponent(actualNext, slot.identity, entity),
          expected.runtime.readComponent(expectedNext, slot.identity, entity),
        );
      }
    }
  }
}

function alphaNormalized(analysis: Analysis): Analysis {
  return {
    ...analysis,
    functions: analysis.functions.map((signature) => {
      const quantified = new Set(signature.variables);
      equal(quantified.size, signature.variables.length, signature.name);
      const names = new Map<bigint, bigint>();
      function index(original: bigint): bigint {
        ok(
          quantified.has(original),
          `${signature.name}: unbound type variable`,
        );
        const existing = names.get(original);
        if (existing !== undefined) return existing;
        const fresh = BigInt(names.size);
        names.set(original, fresh);
        return fresh;
      }
      function type(value: Type): Type {
        switch (value.$) {
          case "VariableTy":
            return { ...value, index: index(value.index) };
          case "FunctionTy":
            return {
              ...value,
              parameter: type(value.parameter),
              result: type(value.result),
            };
          case "AppliedTy":
            return { ...value, arguments: value.arguments.map(type) };
          default:
            return value;
        }
      }
      return {
        ...signature,
        parameter: type(signature.parameter),
        result: type(signature.result),
        variables: signature.variables.map(index).sort((left, right) =>
          left < right ? -1 : left > right ? 1 : 0
        ),
      };
    }),
  };
}

async function measure(
  session: IncrementalCompiler,
  revision: Reference,
  previous: Reference,
  startup_ms = 0,
): Promise<Sample> {
  const started = performance.now();
  const result = await session.compileEcs(revision.source);
  const compiled = performance.now();
  const reloaded = await previous.runtime.reload(
    previous.world,
    result.artifact,
  );
  const ready = performance.now();
  // This secondary measurement follows reload and may reuse the engine's Wasm
  // compilation cache. It is deliberately excluded from edit-to-ready latency.
  const standaloneStarted = performance.now();
  const standalone = await createEcsRuntime(result.artifact);
  const standalone_wasm_ms = performance.now() - standaloneStarted;
  equal(
    result.artifact.bytes,
    revision.artifact.bytes,
    `${revision.name}: Wasm`,
  );
  equal(
    result.artifact.storage,
    revision.artifact.storage,
    `${revision.name}: storage`,
  );
  equal(
    alphaNormalized(result.artifact.analysis),
    alphaNormalized(revision.artifact.analysis),
    `${revision.name}: analysis`,
  );
  assertWorld(reloaded, revision);
  assertWorld({
    runtime: standalone,
    world: seedWorld(standalone, result.artifact),
  }, revision);
  return {
    startup_ms,
    compile_ms: compiled - started,
    reload_ms: ready - compiled,
    standalone_wasm_ms,
    edit_to_ready_ms: ready - started,
    startup_to_ready_ms: startup_ms + ready - started,
    stats: result.stats,
  };
}

function distribution(values: readonly number[]) {
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return {
    median: sorted.length % 2
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2,
    p95: sorted[Math.ceil(sorted.length * 0.95) - 1],
    mean: sorted.reduce((sum, value) => sum + value, 0) / sorted.length,
  };
}

async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function summarize(
  mode: "fresh" | "edit",
  workers: number,
  revision: Reference,
  measurements: readonly Sample[],
) {
  return {
    mode,
    workers,
    workload: revision.name,
    lines: revision.source.trimEnd().split("\n").length,
    systems: revision.artifact.analysis.world.systems.length,
    bytes: revision.artifact.bytes.length,
    source_sha256: revision.source_sha256,
    wasm_sha256: revision.wasm_sha256,
    clean_reference_compile_ms: revision.clean_compile_ms,
    startup_ms: distribution(measurements.map((sample) => sample.startup_ms)),
    compile_ms: distribution(measurements.map((sample) => sample.compile_ms)),
    reload_ms: distribution(measurements.map((sample) => sample.reload_ms)),
    standalone_wasm_ms: distribution(
      measurements.map((sample) => sample.standalone_wasm_ms),
    ),
    edit_to_ready_ms: distribution(
      measurements.map((sample) => sample.edit_to_ready_ms),
    ),
    startup_to_ready_ms: distribution(
      measurements.map((sample) => sample.startup_to_ready_ms),
    ),
    samples: measurements,
  };
}

const sourceStartup = performance.now();
const clean = await createSourceCompiler();
const cleanStartupMs = performance.now() - sourceStartup;
try {
  async function reference(name: string, source: string): Promise<Reference> {
    const started = performance.now();
    const artifact = clean.compileEcs(source);
    const clean_compile_ms = performance.now() - started;
    ok(
      WebAssembly.validate(artifact.bytes),
      `${name}: clean compiler emitted invalid Wasm`,
    );
    const runtime = await createEcsRuntime(artifact);
    return {
      name,
      source,
      artifact,
      runtime,
      world: seedWorld(runtime, artifact),
      clean_compile_ms,
      source_sha256: await sha256(new TextEncoder().encode(source)),
      wasm_sha256: await sha256(artifact.bytes),
    };
  }
  const full = [
    await reference(
      "7-system scalar ECS example",
      await Deno.readTextFile(
        new URL("../examples/ecs_runtime.blot", import.meta.url),
      ),
    ),
    await reference("16 independent movement systems", ecsWorkload(16)),
    await reference("64 independent movement systems", ecsWorkload(64)),
  ];
  equal(
    full.map((revision) => revision.artifact.analysis.world.systems.length),
    [7, 16, 64],
  );
  const base = await reference("16-system incremental baseline", baseline);
  const revisions: Reference[] = [];
  for (const edit of edits) {
    revisions.push(await reference(edit.name, edit.source));
  }
  for (const revision of revisions) {
    if (revision.name === "identical" || revision.name === "trivia") {
      equal(revision.artifact.bytes, base.artifact.bytes, revision.name);
    } else {
      notDeepStrictEqual(
        revision.artifact.bytes,
        base.artifact.bytes,
        revision.name,
      );
    }
  }
  ok(
    revisions.find((revision) => revision.name === "layout")!.artifact.storage
      .some((slot, index) => slot.tag !== base.artifact.storage[index].tag),
    "Layout edit must change actual storage tags",
  );
  const measurements: ReturnType<typeof summarize>[] = [];
  const incrementalStartup = [];
  console.log(`Deno ${Deno.version.deno}, ${Deno.build.os}/${Deno.build.arch}`);
  console.log(
    `${samples} samples; workers ${
      workerCounts.join(", ")
    }; measurements run sequentially.`,
  );
  console.log("One lane runs inline; 2/4/8 lanes use persistent worker pools.");
  console.log(
    "Full rebuilds use fresh sessions. Edit samples reset to baseline outside timing, then compile and reload an immutable baseline world.",
  );
  console.log(
    "Reload includes Wasm compilation, instantiation and state remapping. Oracle checks, seeding, file I/O, and Bend bootstrap are excluded.",
  );
  for (const count of workerCounts) {
    const workers = count as WorkerCount;
    for (const revision of full) {
      console.log(
        `Measuring fresh ${revision.name} with ${workers} worker(s)...`,
      );
      const results: Sample[] = [];
      for (let index = 0; index < samples; index++) {
        const started = performance.now();
        const session = await createIncrementalCompiler({ workers });
        const startup_ms = performance.now() - started;
        try {
          results.push(await measure(session, revision, revision, startup_ms));
        } finally {
          session.dispose();
        }
      }
      measurements.push(summarize("fresh", workers, revision, results));
    }
    const started = performance.now();
    const session = await createIncrementalCompiler({ workers });
    const startup_ms = performance.now() - started;
    try {
      const first = await measure(session, base, base, startup_ms);
      incrementalStartup.push({ workers, first });
      for (const revision of revisions) {
        console.log(
          `Measuring ${revision.name} edit with ${workers} worker(s)...`,
        );
        const results: Sample[] = [];
        for (let index = 0; index < samples; index++) {
          // Alternate baseline/revision, so every real edit starts from the same
          // previous revision instead of measuring repeated-source cache hits.
          await session.compileEcs(base.source);
          results.push(await measure(session, revision, base));
        }
        measurements.push(summarize("edit", workers, revision, results));
      }
    } finally {
      session.dispose();
    }
  }
  console.table(measurements.map((series) => ({
    mode: series.mode,
    workers: series.workers,
    workload: series.workload,
    compile_ms: Number(series.compile_ms.median.toFixed(2)),
    reload_ms: Number(series.reload_ms.median.toFixed(2)),
    edit_to_ready_ms: Number(series.edit_to_ready_ms.median.toFixed(2)),
    groups_checked: series.samples.at(-1)!.stats.groups_checked,
    groups_reused: series.samples.at(-1)!.stats.groups_reused,
    entries_compiled: series.samples.at(-1)!.stats.entries_compiled,
    entries_reused: series.samples.at(-1)!.stats.entries_reused,
  })));
  await Deno.mkdir(dirname(reportPath), { recursive: true });
  await Deno.writeTextFile(
    reportPath,
    JSON.stringify(
      {
        version: 1,
        deno: Deno.version.deno,
        platform: Deno.build,
        samples,
        workers: workerCounts,
        warmups: 0,
        clean_startup_ms: cleanStartupMs,
        methodology: {
          workers:
            "One lane runs inline; 2/4/8 lanes use persistent worker pools.",
          full_rebuild:
            "Fresh compiler session per sample; startup reported separately.",
          incremental:
            "Baseline restored before every sample; one latest-revision transition per measurement.",
          total:
            "Compile plus reload, excluding compiler startup; startup_to_ready_ms includes both.",
          reload:
            "WebAssembly.compile + instantiate + compatible nominal state remapping.",
          standalone_wasm:
            "Secondary compile+instantiate after reload; may reuse the engine cache; not included in totals.",
          layout:
            "Adds a non-storage ADT constructor and shifts tags; stored U32 wrapper layouts remain compatible.",
          clean_reference:
            "Single un-warmed clean compilation per revision, for equivalence; not a statistical speed baseline.",
          equivalence:
            "Exact Wasm bytes, storage bindings, public analysis modulo per-signature quantified type-variable alpha-renaming, preserved world state, and one executed ECS transition.",
          excluded:
            "Bend bootstrap, process/module startup, file I/O, oracle checks and world seeding.",
        },
        incremental_startup: incrementalStartup,
        measurements,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(`Wrote ${reportPath}`);
} finally {
  clean.dispose();
}
