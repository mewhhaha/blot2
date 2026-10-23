// Pair exact baseline/candidate compilers on a direct scalar record consumer.
// deno run --allow-read --allow-write --allow-run scripts/bench_scalar_record_reader.ts BASELINE CANDIDATE OUTPUT_DIRECTORY
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { instantiateGuest } from "../compiler/guest.ts";
import { observeGuestAllocations } from "./bench/guest_heap_observer.ts";

if (Deno.args.length !== 3) {
  throw new Error(
    "Pass baseline compiler, candidate compiler, and new output directory",
  );
}
const [baseline, candidate, directory] = Deno.args.map((path) => resolve(path));
await Deno.mkdir(directory);
const input = `${directory}/main.blot`;
const source =
  `const calculate = fn (args: { a: U32, b: U32, c: U32, d: U32 }) =>
  @u32.add (@u32.mul args.a args.b) (@u32.mul args.c args.d)
entry const answer = fn (value: U32) => calculate { d: 4, c: 3, b: 2, a: value }
`;
await Deno.writeTextFile(input, source);
const paths = [`${directory}/baseline.wasm`, `${directory}/candidate.wasm`];
const compilers = [baseline, candidate];
type Metrics = {
  total_us: number;
  wasm_bytes: number;
  memory: { allocations: number; allocated_bytes: number };
};
const builds: Metrics[][] = [[], []];
const decoder = new TextDecoder();
const median = (values: number[]) =>
  values.toSorted((a, b) => a - b)[Math.floor(values.length / 2)];
async function hash(bytes: Uint8Array): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  ].map((
    value,
  ) => value.toString(16).padStart(2, "0")).join("");
}
async function build(index: number): Promise<void> {
  const result = await new Deno.Command(compilers[index], {
    args: ["build", input, paths[index], "--prelude", "none"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  const output = decoder.decode(result.stdout);
  assert(result.success, output + decoder.decode(result.stderr));
  const metrics = JSON.parse(output.trim()) as Metrics & { success: boolean };
  assert(metrics.success);
  builds[index].push(metrics);
}
for (let pair = 0; pair < 9; pair++) {
  await build(pair % 2);
  await build(1 - pair % 2);
}
const bytes = await Promise.all(paths.map((path) => Deno.readFile(path)));
const traffic = bytes.map((value) =>
  observeGuestAllocations(value, [["answer", 5, 22]])
);
const guests = await Promise.all(bytes.map((value) => instantiateGuest(value)));
const times: number[][] = [[], []];
try {
  for (const guest of guests) {
    assert.equal(guest.call("answer", 5), 22);
    for (let warm = 0; warm < 5000; warm++) guest.call("answer", 5);
  }
  function runtime(index: number) {
    const start = performance.now();
    let checksum = 0;
    for (let call = 0; call < 500000; call++) {
      checksum += guests[index].call("answer", 5) as number;
    }
    times[index].push(performance.now() - start);
    assert.equal(checksum, 11_000_000);
  }
  for (let pair = 0; pair < 31; pair++) {
    runtime(pair % 2);
    runtime(1 - pair % 2);
  }
} finally {
  for (const guest of guests) guest.dispose();
}
const summary = (index: number) => ({
  runtime_ms: median(times[index]),
  compile_ms: median(builds[index].map((value) => value.total_us / 1000)),
  wasm_bytes: median(builds[index].map((value) => value.wasm_bytes)),
  compiler_allocations: median(
    builds[index].map((value) => value.memory.allocations),
  ),
  guest_traffic_per_100_calls: traffic[index],
});
const report = {
  fixture:
    "Four scalar fields passed to a direct helper; 9 alternating fresh process compile pairs and 31 alternating runtime pairs of 500,000 calls after warmup",
  pins: {
    baseline: await hash(await Deno.readFile(baseline)),
    candidate: await hash(await Deno.readFile(candidate)),
    source: await hash(new TextEncoder().encode(source)),
    baseline_wasm: await hash(bytes[0]),
    candidate_wasm: await hash(bytes[1]),
  },
  baseline: summary(0),
  candidate: summary(1),
  runtime_paired_ratio: median(
    times[1].map((value, index) => value / times[0][index]),
  ),
  compile_paired_ratio: median(
    builds[1].map((value, index) => value.total_us / builds[0][index].total_us),
  ),
};
await Deno.writeTextFile(
  `${directory}/report.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(JSON.stringify(report));
