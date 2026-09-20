// Archived compiler-coupled prototype; not part of the current compiler.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { dirname, join } from "node:path";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import {
  createEcsRuntime,
  type EcsRuntime,
  type EcsWorld,
} from "./ecs_runtime.ts";
import type { Analysis, EcsArtifact, Type } from "./host.ts";

const samples = Number(Deno.args[0] ?? 7);
const destination = Deno.args[1] ?? "build/native-session-bench.json";
const baselineDirectory = Deno.args[2] ?? "build/case-study-baseline";
if (
  Deno.args.length > 3 || !Number.isInteger(samples) || samples < 1 ||
  samples > 100
) {
  throw new Error(
    "Usage: compiler/native_session_bench.ts [samples: 1..100] [report.json] [frozen-baseline-directory]",
  );
}

async function sha256(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function withoutUnusedFloatSignatures(bytes: Uint8Array<ArrayBuffer>) {
  // F32 support adds these three unused signatures to every module. Remove
  // exactly that verified section change before comparing the old U32 oracle.
  const current = new Uint8Array([
    1,
    27,
    5,
    96,
    2,
    127,
    127,
    1,
    127,
    96,
    1,
    127,
    1,
    127,
    96,
    1,
    125,
    1,
    127,
    96,
    1,
    127,
    1,
    125,
    96,
    1,
    125,
    1,
    125,
  ]);
  equal(
    bytes.slice(8, 8 + current.length),
    current,
    "unexpected Wasm signature section",
  );
  let cursor = 8;
  const unsigned = () => {
    let value = 0;
    let scale = 1;
    for (let count = 0; count < 5; count++) {
      ok(cursor < bytes.length, "truncated Wasm LEB");
      const byte = bytes[cursor++];
      value += (byte & 127) * scale;
      if (byte < 128) return value;
      scale *= 128;
    }
    throw new Error("invalid Wasm LEB");
  };
  while (cursor < bytes.length) {
    const section = bytes[cursor++];
    const length = unsigned();
    const end = cursor + length;
    ok(end <= bytes.length, "truncated Wasm section");
    if (section === 2 || section === 3) {
      const entries = unsigned();
      for (let entry = 0; entry < entries; entry++) {
        if (section === 2) {
          const moduleLength = unsigned();
          cursor += moduleLength;
          const fieldLength = unsigned();
          cursor += fieldLength;
          equal(bytes[cursor++], 0, "U32 workload imports only functions");
        }
        ok(
          unsigned() < 2,
          "a function refers to an F32 signature; cannot normalize this module",
        );
      }
      equal(cursor, end, "unexpected function/import section contents");
    }
    cursor = end;
  }
  const previous = new Uint8Array([
    1,
    12,
    2,
    96,
    2,
    127,
    127,
    1,
    127,
    96,
    1,
    127,
    1,
    127,
  ]);
  const normalized = new Uint8Array(
    bytes.length - current.length + previous.length,
  );
  normalized.set(bytes.subarray(0, 8));
  normalized.set(previous, 8);
  normalized.set(bytes.subarray(8 + current.length), 8 + previous.length);
  return normalized;
}

const manifest = JSON.parse(
  await Deno.readTextFile(join(baselineDirectory, "manifest.json")),
) as {
  commit: string;
  prelude_sha256: string;
  inputs: Record<string, string>;
};
const preludeHash = await sha256(
  await Deno.readFile(new URL("../std/prelude.blot", import.meta.url)),
);
equal(
  preludeHash,
  manifest.prelude_sha256,
  "Run an isolated compiler checkout with the frozen prelude; do not substitute the expanded prelude in the baseline comparison",
);

function normalized(analysis: Analysis): Analysis {
  return {
    ...analysis,
    functions: analysis.functions.map((signature) => {
      const names = new Map<bigint, bigint>();
      const index = (original: bigint): bigint => {
        ok(signature.variables.includes(original));
        if (!names.has(original)) names.set(original, BigInt(names.size));
        return names.get(original)!;
      };
      const type = (value: Type): Type => {
        switch (value.$) {
          case "VariableTy":
            return { ...value, index: index(value.index) };
          case "AppliedTy":
            return { ...value, arguments: value.arguments.map(type) };
          case "FunctionTy":
            return {
              ...value,
              parameter: type(value.parameter),
              result: type(value.result),
            };
          default:
            return value;
        }
      };
      return {
        ...signature,
        parameter: type(signature.parameter),
        result: type(signature.result),
        variables: signature.variables.map(index).sort((a, b) =>
          a < b ? -1 : a > b ? 1 : 0
        ),
      };
    }),
  };
}

function equivalent(actual: EcsArtifact, expected: EcsArtifact) {
  equal(actual.bytes, expected.bytes);
  equal(actual.storage, expected.storage);
  equal(normalized(actual.analysis), normalized(expected.analysis));
}

function seed(runtime: EcsRuntime, artifact: EcsArtifact): EcsWorld {
  return runtime.createWorld({
    entityCount: 3,
    components: artifact.storage.filter((slot) =>
      slot.storage.$ === "Component"
    ).map((slot) => ({
      identity: slot.identity,
      values: [1, slot.identity.declaration === "Velocity1" ? null : 2, null],
    })),
    resources: artifact.storage.filter((slot) => slot.storage.$ === "Resource")
      .map((slot) => ({ identity: slot.identity, value: 1 })),
  });
}

function execution(
  runtime: EcsRuntime,
  world: EcsWorld,
  artifact: EcsArtifact,
) {
  const next = runtime.run(world);
  return artifact.storage.map((slot) => ({
    identity: slot.identity,
    before: slot.storage.$ === "Resource"
      ? runtime.readResource(world, slot.identity)
      : Array.from(
        { length: world.entityCount },
        (_, entity) => runtime.readComponent(world, slot.identity, entity),
      ),
    after: slot.storage.$ === "Resource"
      ? runtime.readResource(next, slot.identity)
      : Array.from(
        { length: next.entityCount },
        (_, entity) => runtime.readComponent(next, slot.identity, entity),
      ),
  }));
}

function distribution(values: readonly number[]) {
  const sorted = values.toSorted((a, b) => a - b);
  return {
    median: (sorted[Math.floor((sorted.length - 1) / 2)] +
      sorted[Math.floor(sorted.length / 2)]) / 2,
    p95: sorted[Math.ceil(sorted.length * 0.95) - 1],
    samples: values,
  };
}

interface Reference {
  readonly name: string;
  readonly source: string;
  readonly artifact: EcsArtifact;
  readonly runtime: EcsRuntime;
  readonly world: EcsWorld;
  readonly source_sha256: string;
  readonly wasm_sha256: string;
  readonly baseline_wasm_sha256: string;
}

const revisions = [
  "identical",
  "trivia",
  "body",
  "effect",
  "layout",
  "const",
  "all_bodies",
];
const results: Record<string, unknown>[] = [];
const startup: Record<string, unknown>[] = [];
const js = await createSourceCompiler();
const full = await createNativeCompiler({ threads: 1 });
try {
  for (const systems of [16, 64]) {
    const old = JSON.parse(
      await Deno.readTextFile(
        join(baselineDirectory, `incremental${systems}.json`),
      ),
    ) as {
      measurements: { mode: string; workload: string; wasm_sha256: string }[];
    };
    const references: Reference[] = [];
    for (const name of revisions) {
      const filename = `ecs${systems}-${name}.blot`;
      const source = await Deno.readTextFile(
        join(baselineDirectory, "inputs", filename),
      );
      const source_sha256 = await sha256(new TextEncoder().encode(source));
      equal(source_sha256, manifest.inputs[filename], filename);
      const artifact = await full.compileEcs(source);
      equivalent(artifact, js.compileEcs(source));
      const wasm_sha256 = await sha256(artifact.bytes);
      const baseline_wasm_sha256 = await sha256(
        withoutUnusedFloatSignatures(artifact.bytes),
      );
      equal(
        baseline_wasm_sha256,
        old.measurements.find((entry) =>
          entry.mode === "edit" && entry.workload === name
        )?.wasm_sha256,
        `${systems}/${name}: original Wasm hash`,
      );
      const runtime = await createEcsRuntime(artifact);
      references.push({
        name,
        source,
        artifact,
        runtime,
        world: seed(runtime, artifact),
        source_sha256,
        wasm_sha256,
        baseline_wasm_sha256,
      });
    }
    const baseline = references[0];
    const started = performance.now();
    const session = await createNativeIncrementalCompiler({ threads: 1 });
    const startup_ms = performance.now() - started;
    try {
      const initialStart = performance.now();
      const first = await session.compileEcs(baseline.source);
      const first_ms = performance.now() - initialStart;
      equivalent(first.artifact, baseline.artifact);
      startup.push({ systems, startup_ms, first_ms, stats: first.stats });
      for (const reference of references) {
        console.log(
          `Measuring ${systems}-system ${reference.name}: native full and native incremental...`,
        );
        const fullTimes: number[] = [];
        for (let warmup = 0; warmup < 2; warmup++) {
          await full.compileEcs(reference.source);
        }
        for (let sample = 0; sample < samples; sample++) {
          const start = performance.now();
          const artifact = await full.compileEcs(reference.source);
          fullTimes.push(performance.now() - start);
          equivalent(artifact, reference.artifact);
        }
        const measurements = [];
        for (let sample = 0; sample < samples; sample++) {
          await session.compileEcs(baseline.source);
          const start = performance.now();
          const next = await session.compileEcs(reference.source);
          const compiled = performance.now();
          const reload = await baseline.runtime.reload(
            baseline.world,
            next.artifact,
          );
          const ready = performance.now();
          equivalent(next.artifact, reference.artifact);
          equal(
            execution(reload.runtime, reload.world, next.artifact),
            execution(reference.runtime, reference.world, reference.artifact),
          );
          measurements.push({
            compile_ms: compiled - start,
            reload_ms: ready - compiled,
            edit_to_ready_ms: ready - start,
            stats: next.stats,
          });
        }
        const last = measurements.at(-1)!;
        if (reference.name === "body") {
          equal(last.stats.groups_checked, 1);
          equal(last.stats.entries_compiled, 1);
        }
        if (
          reference.name === "const" || reference.name === "trivia" ||
          reference.name === "identical" || reference.name === "layout"
        ) {
          equal(last.stats.entries_compiled, 0);
        }
        results.push({
          systems,
          revision: reference.name,
          source_sha256: reference.source_sha256,
          wasm_sha256: reference.wasm_sha256,
          baseline_wasm_sha256: reference.baseline_wasm_sha256,
          bytes: reference.artifact.bytes.length,
          full_compile_ms: distribution(fullTimes),
          incremental_compile_ms: distribution(
            measurements.map((entry) => entry.compile_ms),
          ),
          reload_ms: distribution(measurements.map((entry) => entry.reload_ms)),
          edit_to_ready_ms: distribution(
            measurements.map((entry) => entry.edit_to_ready_ms),
          ),
          measurements,
        });
        console.log(
          `${systems}/${reference.name}: full ${
            distribution(fullTimes).median.toFixed(2)
          }ms, cached ${
            distribution(measurements.map((entry) => entry.compile_ms)).median
              .toFixed(2)
          }ms; ${last.stats.groups_checked} group(s), ${last.stats.entries_compiled} entry/entries`,
        );
      }
    } finally {
      await session.dispose();
    }
  }
} finally {
  js.dispose();
  await full.dispose();
}

await Deno.mkdir(dirname(destination), { recursive: true });
await Deno.writeTextFile(
  destination,
  JSON.stringify(
    {
      version: 1,
      deno: Deno.version,
      platform: Deno.build,
      measured_at: new Date().toISOString(),
      baseline_commit: manifest.commit,
      samples,
      threads: 1,
      full_warmups: 2,
      incremental_warmups: 0,
      prelude_sha256: preludeHash,
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
      parser_sha256: await sha256(
        await Deno.readFile(
          new URL("../generated/wasm/parser.wasm", import.meta.url),
        ),
      ),
      methodology: {
        compile:
          "Source parsing, encoding, IPC, native pipeline and response decoding; no startup, file I/O, oracle comparisons or runtime reload.",
        incremental:
          "Restore baseline outside every timed edit. One native process retains declaration/group/const/code caches; no source-string memoization. Identical and trivia are separate series.",
        reload:
          "Compile and instantiate emitted Wasm, remap immutable baseline world; validate preserved state and an executed transition outside timing.",
        equivalence:
          "Exact frozen source/prelude hashes; original Wasm hashes after removing the exact asserted 15-byte addition of three unused F32 function signatures. Current native/cache/JS Wasm and storage exact, public analysis modulo quantified type-variable alpha-renaming, and executed ECS transitions.",
      },
      startup,
      results,
    },
    null,
    2,
  ) + "\n",
);
console.log(`Wrote ${destination}`);
