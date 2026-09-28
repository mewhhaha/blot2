/** Runtime loop/collection measurements. Compare to the previous PR head to
 * isolate layout-aware tracing from the earlier array and host-copy changes.
 * deno run --allow-read --allow-write=build compiler/gc_bench.ts /path/to/baseline
 */
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createSourceCompiler } from "./source.ts";
import { instantiateGuest } from "./guest.ts";

if (Deno.args.length !== 1) {
  throw new Error("Usage: gc_bench.ts /path/to/built/baseline-checkout");
}
const baselineUrl = pathToFileURL(resolve(Deno.args[0]) + "/");
const baseline = await import(
  new URL("compiler/source.ts", baselineUrl).href
) as {
  createSourceCompiler: typeof createSourceCompiler;
};
const oldCompiler = await baseline.createSourceCompiler({ prelude: "none" });
const newCompiler = await createSourceCompiler({ prelude: "none" });
const rows: {
  name: string;
  loop_iterations: number;
  baseline_ms: number[];
  candidate_ms: number[];
  baseline_median_ms: number;
  candidate_median_ms: number;
  speedup: number;
  baseline_memory_bytes: number;
  candidate_memory_bytes: number;
  baseline_wasm_bytes: number;
  candidate_wasm_bytes: number;
}[] = [];
const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[xs.length >>> 1];
let sink = 0;

async function measure(
  name: string,
  source: string,
  turns: number,
  expected: number,
) {
  // Force an exported memory/reset API on scalar-returning probes too.
  source +=
    "\nentry const memory_probe = fn (count: U32) => @array.fill count 0\n";
  const oldArtifact = oldCompiler.compile(source);
  const newArtifact = newCompiler.compile(source);
  const before = await instantiateGuest(oldArtifact.bytes);
  const after = await instantiateGuest(newArtifact.bytes);
  try {
    equal(after.abi, before.abi);
    for (const guest of [before, after]) {
      equal(guest.call("run", turns), expected);
      // Warmup also establishes reusable heap and GC metadata capacity.
      for (let i = 0; i < 3; i++) equal(guest.call("run", turns), expected);
    }
    const sample = (guest: typeof before) => {
      const start = performance.now();
      const result = guest.call("run", turns);
      const elapsed = performance.now() - start;
      equal(result, expected); // Correctness and observation outside the timer.
      sink = (sink ^ (result as number)) >>> 0;
      return elapsed;
    };
    const b: number[] = [], a: number[] = [];
    for (let round = 0; round < 11; round++) {
      if ((round & 1) === 0) {
        b.push(sample(before));
        a.push(sample(after));
      } else {
        a.push(sample(after));
        b.push(sample(before));
      }
    }
    ok(
      after.memoryBytes() <= before.memoryBytes(),
      "layout hints must not increase this workload's heap high-water mark",
    );
    const bm = median(b), am = median(a);
    rows.push({
      name,
      loop_iterations: turns,
      baseline_ms: b,
      candidate_ms: a,
      baseline_median_ms: bm,
      candidate_median_ms: am,
      speedup: bm / am,
      baseline_memory_bytes: before.memoryBytes(),
      candidate_memory_bytes: after.memoryBytes(),
      baseline_wasm_bytes: oldArtifact.bytes.length,
      candidate_wasm_bytes: newArtifact.bytes.length,
    });
    console.log(
      `${name}: ${bm.toFixed(4)} -> ${am.toFixed(4)} ms (${
        (bm / am).toFixed(2)
      }x)`,
    );
  } finally {
    before.dispose();
    after.dispose();
  }
}

try {
  for (const length of [1024, 65536]) {
    await measure(
      `pinned scalar array, ${length} words`,
      `
entry const run = fn (limit: U32) => do:
  let pinned = @array.fill ${length} 7
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      return @u32.add turn (@array.get pinned ${length - 1})
    turn := @u32.add self 1
`,
      2048,
      2055,
    );
    await measure(
      `replaced scalar array, ${length} words`,
      `
entry const run = fn (limit: U32) => do:
  let original = @array.fill ${length} 7
  let state = (0, @array.fill ${length} 0)
  for ever:
    let (turn, previous) = state
    if @u32.eq turn limit:
      return @u32.add (@array.get previous ${
        length - 1
      }) (@array.get original 0)
    state := (@u32.add turn 1, @array.fill ${length} (@u32.add turn 1))
`,
      512,
      519,
    );
  }
  await measure(
    "unknown local scalar fill (conservative control)",
    `
entry const run = fn (limit: U32) => do:
  let pinned = @array.fill 4096 limit
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      return @array.get pinned 4095
    turn := @u32.add self 1
`,
    2048,
    2048,
  );
  await measure(
    "nested reference arrays retain their children",
    `
entry const run = fn (limit: U32) => do:
  let original = @array.fill 32 7
  let state = (0, @array.fill 32 original)
  for ever:
    let (turn, previous) = state
    if @u32.eq turn limit:
      return @u32.add (@array.get (@array.get previous 31) 31) (@array.get original 0)
    state := (@u32.add turn 1, @array.fill 32 (@array.fill 32 (@u32.add turn 1)))
`,
    2048,
    2055,
  );
  await measure(
    "allocation-free scalar loop control",
    `
entry const run = fn (limit: U32) => do:
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      return turn
    turn := @u32.add self 1
`,
    16384,
    16384,
  );
  await Deno.mkdir("build", { recursive: true });
  await Deno.writeTextFile(
    "build/gc-performance.json",
    JSON.stringify(
      {
        toolchain: Deno.version,
        architecture: Deno.build,
        baseline_directory: baselineUrl.href,
        samples: 11,
        units: "milliseconds per complete run (compilation excluded)",
        sink,
        rows,
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  oldCompiler.dispose();
  newCompiler.dispose();
}
