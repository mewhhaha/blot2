/** Source-to-Wasm latency, measured separately from building the compiler.
 * Uses persistent processes, three untimed warm-ups, and analysis:false for every
 * backend. Backend order rotates between samples to limit order/warmup bias. Guest execution and output comparisons are outside timed regions.
 */
import { deepStrictEqual, equal } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createCarpCompiler } from "../carp.ts";
import { createNativeCompiler } from "../native.ts";
import { instantiateGuest } from "../guest.ts";

const samples = Number(Deno.args[0] ?? "7");
if (!Number.isInteger(samples) || samples < 1 || samples > 100) {
  throw new RangeError("samples must be an integer in 1..100");
}
if ((Deno.args.length - 1) % 2 !== 0 && Deno.args.length > 1) {
  throw new Error(
    "Usage: bench.ts [samples] [reference executable reference label]...",
  );
}
const references = [];
for (let i = 1; i < Deno.args.length; i += 2) {
  references.push({ executable: Deno.args[i], label: Deno.args[i + 1] });
}
const workloads = [
  {
    name: "scalar",
    source: "entry const answer = fn () => @u32.add 40 2\n",
  },
  {
    name: "closures-and-polymorphism",
    source: `type Box a is data = Box a
const identity = fn value => value
const make = fn offset => fn (value: U32) => @u32.add offset value
entry const answer = fn () => do:
  let add = make 40
  let Box value = Box (identity 2)
  return add value
entry const flag = identity True
`,
  },
  {
    name: "64-independent-functions",
    source: Array.from(
      { length: 64 },
      (_, i) => `entry const f${i} = fn (value: U32) => @u32.add value ${i}`,
    ).join("\n") + "\nentry const answer = fn () => f40 2\n",
  },
];
const configurations = [
  {
    name: "Carp / 1 worker",
    create: () => createCarpCompiler({ prelude: "none", threads: 1 }),
  },
  {
    name: "Carp / 4 workers",
    create: () => createCarpCompiler({ prelude: "none", threads: 4 }),
  },
];
for (const reference of references) {
  configurations.push({
    name: `Reference / 1 worker / ${reference.label}`,
    create: () =>
      createNativeCompiler({
        prelude: "none",
        threads: 1,
        executable: pathToFileURL(resolve(reference.executable)),
      }),
  });
}
const results = [];
const compilers: Awaited<ReturnType<typeof createNativeCompiler>>[] = [];
try {
  for (const configuration of configurations) {
    compilers.push(await configuration.create());
  }
  for (const workload of workloads) {
    let expected: Uint8Array<ArrayBuffer> | undefined;
    const timings = configurations.map(() => [] as number[]);
    for (let warmup = 0; warmup < 3; warmup++) {
      for (const compiler of compilers) {
        const warm = await compiler.compile(workload.source, {
          analysis: false,
        });
        if (expected) deepStrictEqual(warm.bytes, expected);
        else expected = warm.bytes;
        const guest = await instantiateGuest(warm.bytes);
        try {
          equal(guest.call("answer", null), 42);
        } finally {
          guest.dispose();
        }
      }
    }
    for (let round = 0; round < samples; round++) {
      for (let position = 0; position < compilers.length; position++) {
        const index = (round + position) % compilers.length;
        const start = performance.now();
        const artifact = await compilers[index].compile(workload.source, {
          analysis: false,
        });
        timings[index].push(performance.now() - start);
        deepStrictEqual(artifact.bytes, expected);
      }
    }
    for (let index = 0; index < configurations.length; index++) {
      const milliseconds = timings[index];
      const sorted = [...milliseconds].sort((a, b) => a - b);
      const middle = Math.floor(sorted.length / 2);
      const median = sorted.length % 2
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
      results.push({
        backend: configurations[index].name,
        workload: workload.name,
        source_bytes: new TextEncoder().encode(workload.source).length,
        wasm_bytes: expected!.length,
        median_ms: median,
        min_ms: sorted[0],
        max_ms: sorted.at(-1),
        samples_ms: milliseconds,
      });
    }
  }
} finally {
  for (const compiler of compilers) await compiler.dispose();
}
console.log(JSON.stringify(
  {
    timestamp: new Date().toISOString(),
    host: Deno.build,
    deno: Deno.version.deno,
    samples,
    warmups: 3,
    measurement_order: "rotating backend order, requests run sequentially",
    analysis: false,
    frontend: "persistent shared frontend; repeated source warms its cache",
    note:
      "Measures these workloads on this host, not a language ranking. Reference optimization settings must be stated explicitly.",
    workloads,
    results,
  },
  null,
  2,
));
