/** Layout propagation measurements against a built baseline checkout.
 * Integration CI compares the complete runtime changes with main 2d44737.
 * deno run --allow-read --allow-write=build compiler/layout_bench.ts /path/to/baseline
 */
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createSourceCompiler } from "./source.ts";
import { instantiateGuest } from "./guest.ts";

if (Deno.args.length !== 1) {
  throw new Error("Usage: layout_bench.ts /path/to/built/baseline-checkout");
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
  iterations_per_sample: number;
  warmup_calls: number[];
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
    const warmupCalls: number[] = [];
    for (const guest of [before, after]) {
      const start = performance.now();
      let calls = 0;
      // Give the Wasm optimizer time to publish tiered code. A fixed handful
      // of calls produced misleading ratios on the sub-millisecond controls.
      do {
        for (let i = 0; i < 8; i++) {
          equal(guest.call("run", turns), expected);
          calls++;
        }
        await new Promise((resolve) => setTimeout(resolve, 0));
      } while (calls < 32 || performance.now() - start < 200);
      warmupCalls.push(calls);
    }
    const pilot = (guest: typeof before) => {
      const start = performance.now();
      for (let i = 0; i < 4; i++) guest.call("run", turns);
      return (performance.now() - start) / 4;
    };
    // Use identical batch lengths, sized by the slower implementation so a
    // large speedup does not turn its baseline into an unbounded benchmark.
    const iterations = Math.max(
      1,
      Math.min(1024, Math.ceil(5 / Math.max(pilot(before), pilot(after)))),
    );
    const sample = (guest: typeof before) => {
      const results: unknown[] = new Array(iterations);
      const start = performance.now();
      for (let i = 0; i < iterations; i++) {
        results[i] = guest.call("run", turns);
      }
      const elapsed = (performance.now() - start) / iterations;
      // Validate every invocation, not only the last one, outside the timer.
      for (const result of results) {
        equal(result, expected);
        sink = (sink ^ (result as number)) >>> 0;
      }
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
      iterations_per_sample: iterations,
      warmup_calls: warmupCalls,
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
    const ratio = (bm / am).toFixed(2);
    console.log(
      `${name}: ${bm.toFixed(4)} -> ${am.toFixed(4)} ms (${ratio}x)`,
    );
  } finally {
    before.dispose();
    after.dispose();
  }
}

const compilationRows: unknown[] = [];
try {
  for (const length of [4096, 65536]) {
    await measure(
      `retained scalar through a local, ${length} words`,
      `
entry const run = fn (limit: U32) => do:
  let value = @u32.add limit 7
  let pinned = @array.fill ${length} value
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      return @array.get pinned ${length - 1}
    turn := @u32.add self 1
`,
      2048,
      2055,
    );
    await measure(
      `replaced scalar through a local, ${length} words`,
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
    let value = @u32.add turn 1
    state := (value, @array.fill ${length} value)
`,
      512,
      519,
    );
  }
  await measure(
    "retained scalar from tuple projection, 4096 words",
    `
entry const run = fn (limit: U32) => do:
  let pair = (@u32.add limit 7, @u32.add limit 8)
  let (value, other) = pair
  let pinned = @array.fill 4096 value
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      return @array.get pinned 4095
    turn := @u32.add self 1
`,
    2048,
    2055,
  );
  await measure(
    "retained sixteen-word scalar tuple",
    `
entry const run = fn (limit: U32) => do:
  let value = @u32.add limit 7
  let pinned = (${Array(16).fill("value").join(", ")})
  let turn = 0
  for ever:
    if @u32.eq turn limit:
      let (${Array.from({ length: 16 }, (_, i) => `a${i}`).join(", ")}) = pinned
      return a15
    turn := @u32.add self 1
`,
    2048,
    2055,
  );
  await measure(
    "unknown parameter remains conservative",
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
    "allocation-free scalar control",
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

  // Do not hide the compilation cost of the extra representation analysis.
  // These are full source compilations, separately timed from guest execution.
  for (const count of [16, 128]) {
    const source = Array.from({ length: count }, (_, i) => `
entry const f${i} = fn (input: U32) => do:
  let a = @u32.add input ${i}
  let pair = (a, @u32.add a 1)
  let (x, y) = pair
  return @array.fill 16 x
`).join("\n");
    for (let i = 0; i < 8; i++) {
      oldCompiler.compile(source);
      newCompiler.compile(source);
    }
    const b: number[] = [], a: number[] = [];
    const sample = (compiler: typeof newCompiler) => {
      const start = performance.now();
      const artifact = compiler.compile(source);
      return { artifact, ms: performance.now() - start };
    };
    for (let i = 0; i < 11; i++) {
      const before = (i & 1) === 0 ? sample(oldCompiler) : undefined;
      const after = sample(newCompiler);
      const previous = before ?? sample(oldCompiler);
      equal(after.artifact.analysis, previous.artifact.analysis);
      ok(WebAssembly.validate(previous.artifact.bytes));
      ok(WebAssembly.validate(after.artifact.bytes));
      b.push(previous.ms);
      a.push(after.ms);
    }
    const bm = median(b), am = median(a);
    compilationRows.push({
      name: `full source compilation, ${count} entries`,
      baseline_ms: b,
      candidate_ms: a,
      baseline_median_ms: bm,
      candidate_median_ms: am,
      speedup: bm / am,
    });
    console.log(
      `compile ${count} entries: ${bm.toFixed(4)} -> ${am.toFixed(4)} ms (${
        (bm / am).toFixed(2)
      }x)`,
    );
  }
  // The integration baseline also differs in its collector implementation.
  // Record byte identity and check both implementations against the ECS contract;
  // allocation-flag tests separately guard against tagging tiny products.
  const ecsOld = await baseline.createSourceCompiler();
  const ecsNew = await createSourceCompiler();
  let ecsBytes = 0, ecsBaselineBytes = 0, ecsIdentical = false;
  try {
    const ecsSource = await Deno.readTextFile(
      new URL("../examples/ecs.blot", import.meta.url),
    );
    const old = ecsOld.compile(ecsSource), current = ecsNew.compile(ecsSource);
    ecsIdentical = current.bytes.length === old.bytes.length &&
      current.bytes.every((byte, index) => byte === old.bytes[index]);
    ecsBaselineBytes = old.bytes.length;
    ecsBytes = current.bytes.length;
    const guests = await Promise.all(
      [old, current].map((artifact) => instantiateGuest(artifact.bytes)),
    );
    try {
      equal(guests[0].abi, guests[1].abi);
      for (const guest of guests) {
        equal(guest.call("snapshot", null), 6);
        equal(guest.call("ghost_count", 1), 4);
        for (const turns of [0, 100, 1000]) {
          equal(guest.call("run", turns), 33 + 6 * turns);
        }
      }
    } finally {
      for (const guest of guests) guest.dispose();
    }
    console.log(
      `ECS control: ${ecsBaselineBytes} -> ${ecsBytes} bytes (identical: ${ecsIdentical}), ABI and execution checks passed`,
    );
  } finally {
    ecsOld.dispose();
    ecsNew.dispose();
  }
  await Deno.mkdir("build", { recursive: true });
  await Deno.writeTextFile(
    "build/layout-performance.json",
    JSON.stringify(
      {
        toolchain: Deno.version,
        architecture: Deno.build,
        baseline_directory: baselineUrl.href,
        samples: 11,
        minimum_warmup_ms_per_implementation: 200,
        minimum_warmup_calls: 32,
        target_sample_ms_for_slower_implementation: 5,
        units:
          "milliseconds per complete invocation; full source compilation is reported separately",
        sink,
        rows,
        compilation_rows: compilationRows,
        application_control: {
          source: "examples/ecs.blot",
          wasm_byte_identical: ecsIdentical,
          baseline_wasm_bytes: ecsBaselineBytes,
          wasm_bytes: ecsBytes,
        },
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  oldCompiler.dispose();
  newCompiler.dispose();
}
