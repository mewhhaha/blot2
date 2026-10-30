import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { instantiateGuest } from "../compiler/guest.ts";
import { observeGuestAllocations } from "./bench/guest_heap_observer.ts";

const [baseArg, candidateArg, directoryArg] = Deno.args;
assert(baseArg && candidateArg && directoryArg);
const baseline = resolve(baseArg), candidate = resolve(candidateArg);
const directory = resolve(directoryArg);
const stdRoot = fileURLToPath(new URL("../std/", import.meta.url));
const prelude = fileURLToPath(new URL("../std/prelude.blot", import.meta.url));
const stdArray = fileURLToPath(new URL("../std/array.blot", import.meta.url));
await Deno.mkdir(directory);
const entry = `${directory}/main.blot`;
const source = `
import * as array from "std/array"
const replace = array.replace
const wrapped = func index -> value -> values => return replace index value values
entry const update = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := wrapped index (index + 1) values
  break values[count - 1]
`;
await Deno.writeTextFile(entry, source);
const compilers = [baseline, candidate];
const outputs = [`${directory}/baseline.wasm`, `${directory}/candidate.wasm`];
type Metrics = {
  total_us: number;
  wasm_bytes: number;
  memory: { allocations: number };
};
const builds: Metrics[][] = [[], []];
const decoder = new TextDecoder();
const median = (values: number[]) =>
  values.toSorted((a, b) => a - b)[Math.floor(values.length / 2)];
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function build(index: number) {
  const result = await new Deno.Command(compilers[index], {
    args: [
      "build-project",
      entry,
      outputs[index],
      "--std-root",
      stdRoot,
      "--prelude",
      prelude,
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  const output = decoder.decode(result.stdout);
  assert(result.success, output + decoder.decode(result.stderr));
  const metrics = JSON.parse(output.trim().split("\n").at(-1)!) as Metrics & {
    success: boolean;
  };
  assert(metrics.success);
  builds[index].push(metrics);
}
for (let pair = 0; pair < 9; pair++) {
  await build(pair % 2);
  await build(1 - pair % 2);
}
const bytes = await Promise.all(outputs.map((path) => Deno.readFile(path)));
const traffic = bytes.map((wasm) =>
  observeGuestAllocations(wasm, [["update", 512, 512]])
);
const guests = await Promise.all(bytes.map((wasm) => instantiateGuest(wasm)));
const times: number[][] = [[], []];
try {
  for (const guest of guests) {
    assert.equal(guest.call("update", 512), 512);
    for (let warm = 0; warm < 20; warm++) guest.call("update", 512);
  }
  function runtime(index: number) {
    const start = performance.now();
    let checksum = 0;
    for (let call = 0; call < 200; call++) {
      checksum += guests[index].call("update", 512) as number;
    }
    times[index].push(performance.now() - start);
    assert.equal(checksum, 102400);
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
    "One 512-element array built and updated through a source forwarding wrapper; 9 alternating fresh compiler-process pairs and 31 alternating runtime pairs of 200 guest calls after warmup",
  pins: {
    baseline: await hash(await Deno.readFile(baseline)),
    candidate: await hash(await Deno.readFile(candidate)),
    source: await hash(new TextEncoder().encode(source)),
    prelude: await hash(await Deno.readFile(prelude)),
    std_array: await hash(await Deno.readFile(stdArray)),
    baseline_wasm: await hash(bytes[0]),
    candidate_wasm: await hash(bytes[1]),
  },
  baseline: summary(0),
  candidate: summary(1),
  runtime_paired_ratio: median(times[1].map((value, i) => value / times[0][i])),
  compile_paired_ratio: median(
    builds[1].map((value, i) => value.total_us / builds[0][i].total_us),
  ),
};
await Deno.writeTextFile(
  `${directory}/report.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(JSON.stringify(report));
