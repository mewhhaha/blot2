// deno run -A benchmarks/intent/run.ts [path to squidc]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { captureIntents, sizes } from "./capture.ts";

const root = resolve("../gdev");
const work = await Deno.makeTempDir();
try {
  const binary = work + "/layout.wasm";
  const clang = new Deno.Command("clang", {
    args: [
      "--target=wasm32",
      "-O3",
      "-mbulk-memory",
      "-nostdlib",
      "-Wl,--no-entry",
      "-Wl,--export-all",
      "benchmarks/intent/layout.c",
      "-o",
      binary,
    ],
  });
  assert((await clang.output()).success);
  const { instance } = await WebAssembly.instantiate(
    await Deno.readFile(binary),
  );
  const wasm = instance.exports as Record<string, (...v: number[]) => number>;
  const trace = await captureIntents(
    root,
    resolve(Deno.args[0] ?? "compiler-goose/build/squidc-goose"),
  );
  // A second workload covers all four variants, including Rest and Deliver,
  // which the fixture above may never produce.
  const controls = [[0], [1, 11, 22, 33, 44], [2, 77], [3, 99]];
  const results = [];
  const count = 65536;
  for (
    const [name, events] of [["pile_handles", trace], [
      "balanced_control",
      controls,
    ]] as const
  ) {
    const distribution = [0, 0, 0, 0];
    for (const row of events) distribution[row[0]]++;
    let joinedHash = 0;
    for (let i = 0; i < count; ++i) {
      const original = (i + Math.floor(count / 3)) % count;
      for (const word of events[original % events.length]) {
        joinedHash = (Math.imul(joinedHash, 16777619) + word) >>> 0;
      }
    }
    const samples = [];
    for (let round = 0; round < 9; ++round) {
      for (let j = 0; j < 3; ++j) {
        const layout = (j + round) % 3;
        wasm.reset();
        let tags = 0, full = 0;
        for (let i = 0; i < count; ++i) {
          if (i === Math.floor(count / 3)) wasm.split();
          const row = events[i % events.length];
          wasm.append(layout, ...row);
          tags = (tags + row[0]) >>> 0;
          for (const word of row) full = (full + word) >>> 0;
        }
        const timed = (run: () => number, result: number) => {
          for (let i = 0; i < 5; i++) assert.equal(run() >>> 0, result);
          const start = performance.now();
          for (let i = 0; i < 100; i++) assert.equal(run() >>> 0, result);
          return (performance.now() - start) * 10;
        };
        const splitTag = events[Math.floor(count / 3) % events.length][0];
        const tagUs = timed(() => wasm.scan(layout, 0, 0), tags);
        const fullUs = timed(() => wasm.scan(layout, 1, 0), full);
        const concatUs = timed(() => wasm.concat(layout), splitTag);
        assert.equal(wasm.scan(layout, 1, 1) >>> 0, full);
        assert.equal(wasm.joined_hash(layout) >>> 0, joinedHash);
        samples.push({
          round,
          layout,
          bytes: wasm.bytes(layout),
          tagUs,
          fullUs,
          concatUs,
        });
      }
    }
    results.push({ name, distribution, samples });
  }
  console.log(
    JSON.stringify({ sizes, count, toolchain: Deno.version, results }),
  );
} finally {
  await Deno.remove(work, { recursive: true });
}
