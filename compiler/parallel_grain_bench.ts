import { dirname } from "node:path";
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Result = { readonly $: "Done"; readonly value: unknown } | {
  readonly $: "Fail";
  readonly error: unknown;
};
const compiler = compiled as unknown as {
  "check_scheduler.module_cost"(module: unknown): bigint;
  "check_scheduler.check_batch_with_grain"(
    tasks: BendList<unknown>,
    grain: bigint,
  ): BendList<{ readonly checked: Result }>;
  "wasm.compile_entries_with_grain"(
    grain: bigint,
    jobs: BendList<unknown>,
  ): Result;
  "wasm.prepare_jobs_with_grain"(
    grain: bigint,
    entries: BendList<unknown>,
    projection: unknown,
  ): Result;
};

// Mirrors fixture() in parallel_grain_bench.bend: the same 64 named functions,
// annotations, literal values and nested let names, without frontend timing.
function fixture(shape: string) {
  const jobs = [];
  const tasks = [];
  const entries = [];
  for (let index = 0; index < 64; index++) {
    const depth = shape === "tiny" ? 0 : index % 2 === 0 ? 8 : 64;
    let body: unknown = { $: "U32Expr", value: index };
    for (let level = 0; level < depth; level++) {
      body = {
        $: "LetExpr",
        name: `local_${level}`,
        value: { $: "U32Expr", value: index },
        body,
      };
    }
    const name = `bench_${index}`;
    const module = {
      $: "Module",
      constants: bendList([]),
      data_types: bendList([]),
      operations: bendList([]),
      functions: bendList([{
        $: "Function",
        name,
        exported: false,
        parameter: "value",
        parameter_type: { $: "Some", value: { $: "UnitTy" } },
        result_type: { $: "Some", value: { $: "U32Ty" } },
        body,
      }]),
    };
    jobs.push({
      $: "CodegenJob",
      key: `fn:${name}`,
      parameter: "value",
      body,
      captures: bendList([]),
    });
    entries.push({
      $: "Entry",
      key: `fn:${name}`,
      parameter: "value",
      body,
      captures: bendList([]),
    });
    tasks.push({
      $: "Task",
      position: BigInt(index),
      module,
      dependencies: bendList([]),
      cost: compiler["check_scheduler.module_cost"](module),
    });
  }
  return {
    jobs: bendList(jobs),
    tasks: bendList(tasks),
    entries: bendList(entries),
  };
}

function median(values: readonly number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

const executable = Deno.args[0] ?? "build/parallel-grain-bench";
const reportPath = Deno.args[1] ?? "build/parallel-grains.json";
const iterations = Number(Deno.args[2] ?? 32);
const samples = Number(Deno.args[3] ?? 3);
const phases = (Deno.args[4] ?? "codegen,check,prepare").split(",");
if (
  Deno.args.length > 5 || !Number.isSafeInteger(iterations) || iterations < 1 ||
  !Number.isSafeInteger(samples) || samples < 1 ||
  phases.some((phase) => !["codegen", "check", "prepare"].includes(phase)) ||
  new Set(phases).size !== phases.length
) {
  throw new Error(
    "Usage: parallel_grain_bench.ts [executable] [report.json] [iterations] [samples] [phases:codegen,check,prepare]",
  );
}

const rows = [];
for (const phase of phases) {
  for (const shape of ["tiny", "uneven"]) {
    const prepared = fixture(shape);
    const run = (grain: bigint) => {
      if (phase === "codegen") {
        return compiler["wasm.compile_entries_with_grain"](
          grain,
          prepared.jobs,
        );
      }
      if (phase === "prepare") {
        return compiler["wasm.prepare_jobs_with_grain"](
          grain,
          prepared.entries,
          {
            $: "Metadata",
            lambdas: { $: "MTip" },
            constructors: { $: "MTip" },
          },
        );
      }
      return compiler["check_scheduler.check_batch_with_grain"](
        prepared.tasks,
        grain,
      );
    };
    const reference = run(0xFFFF_FFFF_FFFFn);
    if (reference.$ === "Con" || reference.$ === "Nil") {
      ok(bendArray(reference).every((outcome) => outcome.checked.$ === "Done"));
    } else {
      ok(reference.$ === "Done");
    }
    const javascript = new Map<
      string,
      { median_ms: number; samples_ms: number[] }
    >();
    for (const grain of ["serial", "0", "128", "512", "1024", "2048", "8192"]) {
      const cutoff = grain === "serial" ? 0xFFFF_FFFF_FFFFn : BigInt(grain);
      const timings: number[] = [];
      for (let sample = 0; sample < samples; sample++) {
        let elapsed = 0;
        for (let iteration = 0; iteration < iterations; iteration++) {
          const start = performance.now();
          const result = run(cutoff);
          elapsed += performance.now() - start;
          equal(result, reference);
        }
        timings.push(elapsed / iterations);
      }
      javascript.set(grain, {
        median_ms: median(timings),
        samples_ms: timings,
      });
    }
    for (const threads of [1, 2, 3, 4, 5, 6, 7, 8]) {
      for (
        const grain of ["serial", "0", "128", "512", "1024", "2048", "8192"]
      ) {
        const timings: number[] = [];
        for (let sample = 0; sample < samples; sample++) {
          const output = await new Deno.Command(executable, {
            args: [
              "--threads",
              String(threads),
              "--",
              phase,
              shape,
              grain,
              String(iterations),
            ],
            stdout: "piped",
            stderr: "piped",
          }).output();
          if (!output.success) {
            throw new Error(
              `Grain harness failed (${output.code}): ${
                new TextDecoder().decode(output.stderr)
              }`,
            );
          }
          const result = JSON.parse(new TextDecoder().decode(output.stdout));
          if (
            result.phase !== phase || result.shape !== shape ||
            result.iterations !== iterations || result.verified !== true ||
            result.grain !==
              (grain === "serial" ? 0xFFFF_FFFF_FFFF : Number(grain)) ||
            !Number.isSafeInteger(result.elapsed_ms) || result.elapsed_ms < 0
          ) {
            throw new Error("Grain harness returned an invalid measurement");
          }
          timings.push(result.elapsed_ms / iterations);
        }
        const js = javascript.get(grain)!;
        const nativeMedian = median(timings);
        const row = {
          phase,
          shape,
          threads,
          grain,
          median_ms: nativeMedian,
          samples_ms: timings,
          javascript: js,
          speedup_vs_js: nativeMedian > 0 ? js.median_ms / nativeMedian : null,
        };
        rows.push(row);
        console.log(JSON.stringify(row));
      }
    }
  }
}
const fingerprints: Record<string, string> = {};
for (
  const [name, path] of [
    ["executable_sha256", executable],
    [
      "javascript_sha256",
      new URL("../generated/compiler/compiler.js", import.meta.url),
    ],
  ] as const
) {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
  );
  fingerprints[name] = Array.from(
    digest,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
await Deno.mkdir(dirname(reportPath), { recursive: true });
await Deno.writeTextFile(
  reportPath,
  JSON.stringify(
    {
      measured_at: new Date().toISOString(),
      runtime: Deno.version,
      ...fingerprints,
      iterations,
      samples,
      timing:
        "64 identical independent jobs, sequential configurations. Compiler-only intervals averaged per iteration: native monotonic milliseconds, JS performance.now(). Fixture creation, serial reference, complete ordered result comparison and process startup are untimed. Each backend is verified against its own serial reference; cross-backend artifact parity is covered by native_bench.ts. Serial reference warms each process. No frontend, transport or linking is measured. Zero native intervals are below timer resolution, not zero-cost compilation.",
      rows,
    },
    null,
    2,
  ) + "\n",
);
