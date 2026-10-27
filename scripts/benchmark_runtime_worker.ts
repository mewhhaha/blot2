/** One fresh engine process per Wasm artifact; startup is outside runtime timing. */
import { seeds, workloads } from "./runtime_workloads.ts";
const [path, name, warmupArg, callsArg] = Deno.args;
const workload = workloads.find((item) => item.name === name);
const warmup = Number(warmupArg), calls = Number(callsArg);
if (
  !workload || !path ||
  ![warmup, calls].every((n) =>
    Number.isSafeInteger(n) && n >= 0 && n <= 1000000
  )
) {
  throw new Error("invalid runtime worker arguments");
}
const { instance } = await WebAssembly.instantiate(await Deno.readFile(path));
const run = instance.exports.run as (seed: number) => number;
const expected = seeds.map((seed) => workload.encode(workload.reference(seed)));
seeds.forEach((seed, index) => {
  if (workload.encode(run(seed)) !== expected[index]) {
    throw new Error(`${name}: reference mismatch for ${seed}`);
  }
});
function sweep(count: number) {
  let checksum = 0;
  for (let i = 0; i < count; i++) {
    checksum = (checksum + workload!.encode(run(seeds[i % seeds.length]))) >>>
      0;
  }
  return checksum;
}
function wanted(count: number) {
  const cycle = expected.reduce((sum, n) => (sum + n) >>> 0, 0);
  let checksum = Math.imul(cycle, Math.floor(count / seeds.length)) >>> 0;
  for (let i = 0; i < count % seeds.length; i++) {
    checksum = (checksum + expected[i]) >>> 0;
  }
  return checksum;
}
if (sweep(warmup) !== wanted(warmup)) {
  throw new Error("warmup checksum changed");
}
const start = performance.now();
const checksum = sweep(calls);
const elapsed = performance.now() - start;
if (checksum !== wanted(calls)) throw new Error("timed checksum changed");
console.log(
  JSON.stringify({
    expected,
    runtime_checksum: checksum,
    runtime_calls: calls,
    runtime_warmup_calls: warmup,
    ...(calls ? { runtime_ns_per_call: elapsed * 1e6 / calls } : {}),
  }),
);
