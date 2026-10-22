// Alternating baseline/candidate compilation and branch-heavy guest calls.
// Usage: deno run --allow-read --allow-write --allow-run scripts/bench_safe_local_sinking.ts BASELINE CANDIDATE
import { strict as assert } from "node:assert";
import { instantiateGuest } from "../compiler/guest.ts";

const [baseline, candidate] = Deno.args;
if (!baseline || !candidate) {
  throw new Error("Pass baseline and candidate blotc paths");
}

let expression = "input";
for (let index = 0; index < 48; index++) {
  expression = index % 2 === 0
    ? `@u32.mul (${expression}) 1664525`
    : `@u32.add (${expression}) 1013904223`;
}
const source = `entry const heavy = fn (input: U32) => do:
  let work = ${expression}
  if @u32.eq input 0:
    return 0
  return work
`;
const directory = await Deno.makeTempDir({ prefix: "blot-sink-bench-" });
const input = `${directory}/main.blot`;
await Deno.writeTextFile(input, source);
const tools = [baseline, candidate];
type Compilation = {
  total_us: number;
  wasm_bytes: number;
  memory: { allocations: number };
  work_counters: { safe_local_sinks?: number };
};
const builds: Compilation[][] = [[], []];
const paths = [`${directory}/baseline.wasm`, `${directory}/candidate.wasm`];
const decoder = new TextDecoder();
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}
async function compile(index: number): Promise<void> {
  const result = await new Deno.Command(tools[index], {
    args: ["build", input, paths[index], "--prelude", "none"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(
    result.success,
    decoder.decode(result.stdout) + decoder.decode(result.stderr),
  );
  const metrics = JSON.parse(decoder.decode(result.stdout).trim()) as
    & Compilation
    & { success: boolean };
  assert(metrics.success);
  builds[index].push(metrics);
}
try {
  for (let pair = 0; pair < 9; pair++) {
    await compile(pair % 2);
    await compile(1 - pair % 2);
  }
  const guests = await Promise.all(
    paths.map(async (path) => instantiateGuest(await Deno.readFile(path))),
  );
  try {
    const expected = guests[0].call("heavy", 7);
    assert.equal(guests[1].call("heavy", 7), expected);
    for (const guest of guests) {
      assert.equal(guest.call("heavy", 0), 0);
      for (let index = 0; index < 5000; index++) {
        guest.call("heavy", index % 10 === 0 ? 7 : 0);
      }
    }
    const timings: number[][] = [[], []];
    function runtime(index: number): void {
      const start = performance.now();
      let checksum = 0;
      for (let call = 0; call < 500000; call++) {
        const result = guests[index].call(
          "heavy",
          call % 10 === 0 ? 7 : 0,
        ) as number;
        checksum = (checksum + result) >>> 0;
      }
      timings[index].push(performance.now() - start);
      assert.equal(checksum, (Math.imul(expected as number, 50000)) >>> 0);
    }
    for (let pair = 0; pair < 31; pair++) {
      runtime(pair % 2);
      runtime(1 - pair % 2);
    }
    const summary = (index: number) => ({
      runtime_ms: median(timings[index]),
      compile_ms: median(builds[index].map((value) => value.total_us / 1000)),
      wasm_bytes: median(builds[index].map((value) => value.wasm_bytes)),
      compiler_allocations: median(
        builds[index].map((value) => value.memory.allocations),
      ),
      selected_sinks: median(
        builds[index].map((value) => value.work_counters.safe_local_sinks ?? 0),
      ),
    });
    const before = summary(0);
    const after = summary(1);
    console.log(JSON.stringify({
      fixture:
        "48 scalar operations, 90% skipped branch; 9 alternating fresh build pairs, 31 alternating runtime pairs of 500,000 calls",
      baseline: before,
      candidate: after,
      runtime_paired_ratio: median(
        timings[1].map((value, index) => value / timings[0][index]),
      ),
      compile_paired_ratio: median(
        builds[1].map((value, index) =>
          value.total_us / builds[0][index].total_us
        ),
      ),
    }));
  } finally {
    for (const guest of guests) guest.dispose();
  }
} finally {
  await Deno.remove(directory, { recursive: true });
}
