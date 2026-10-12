// Candidate-only erasure pairs. Compile overhead against a prior compiler is
// measured separately by bench_compile.ts; these pairs preserve source types.
// deno run --allow-all scripts/bench_module_abstraction.ts BLOTC OUTPUT_DIR
import { strict as assert } from "node:assert";
import { cpuUsage } from "node:process";
import { resolve } from "node:path";
import { Buffer } from "node:buffer";

assert.equal(Deno.args.length, 2);
const [compiler, directory] = Deno.args.map((path) => resolve(path));
await Deno.mkdir(directory, { recursive: true });
const cases = [
  {
    name: "scalar",
    count: 100000,
    plain:
      "type Token = F32\nconst make: F32 -> Token = fn value => value\nconst read: Token -> F32 = fn value => value\n",
    opaque:
      "opaque type Token = F32\nconst make: F32 -> Token = fn value => #Token value\nconst read: Token -> F32 = fn (#Token value) => value\n",
    body:
      "entry const run = fn (count: U32) => do:\n  let sum = 0.0\n  for index in 0..count:\n    sum := @f32.add self (read (make (@u32.to_f32 index)))\n  return sum\n",
    expected: Math.fround(4999890432),
  },
  {
    name: "reference",
    count: 16384,
    plain:
      "type Token = Array U32\nconst make: Array U32 -> Token = fn value => value\nconst read: Token -> Array U32 = fn value => value\n",
    opaque:
      "opaque type Token = Array U32\nconst make: Array U32 -> Token = fn value => #Token value\nconst read: Token -> Array U32 = fn (#Token value) => value\n",
    body:
      "entry const run = fn (count: U32) => do:\n  let original = @array.generate count (fn index => index)\n  let alias = read (make original)\n  return @u32.add (@array.length alias) (@array.get original (@u32.sub count 1))\n",
    expected: 32767,
  },
];
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
const rows = [];
for (const item of cases) {
  const variants = [];
  for (
    const [name, declarations] of [["plain", item.plain], [
      "opaque",
      item.opaque,
    ]]
  ) {
    const source = `${directory}/${item.name}-${name}.blot`;
    const output = `${directory}/${item.name}-${name}.wasm`;
    await Deno.writeTextFile(source, declarations + item.body);
    const result = await new Deno.Command(compiler, {
      args: ["build-project", source, output, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
    await Deno.writeFile(
      `${directory}/${item.name}-${name}.jsonl`,
      result.stdout,
    );
    const bytes = await Deno.readFile(output);
    const instance = await WebAssembly.instantiate(bytes, {});
    const run = instance.instance.exports.run as (count: number) => number;
    assert.equal(run(item.count), item.expected);
    for (let warm = 0; warm < 100; warm++) {
      assert.equal(run(item.count), item.expected);
    }
    variants.push({
      name,
      bytes,
      run,
      sha256: await hash(bytes),
      source_sha256: await hash(await Deno.readFile(source)),
    });
  }
  const samples = [];
  for (let pair = 0; pair < 15; pair++) {
    const order = variants.slice();
    if (pair % 2 !== 0) order.reverse();
    for (const variant of order) {
      const started = cpuUsage();
      const wall = performance.now();
      let result = 0;
      for (let iteration = 0; iteration < 64; iteration++) {
        result = variant.run(item.count);
      }
      const wall_us = (performance.now() - wall) * 1000 / 64;
      const cpu = cpuUsage(started);
      assert.equal(result, item.expected);
      samples.push({
        pair,
        variant: variant.name,
        cpu_us: (cpu.user + cpu.system) / 64,
        wall_us,
      });
    }
  }
  rows.push({
    name: item.name,
    count: item.count,
    byte_identical: Buffer.from(variants[0].bytes).equals(
      Buffer.from(variants[1].bytes),
    ),
    variants: variants.map(({ name, sha256, source_sha256, bytes }) => ({
      name,
      sha256,
      source_sha256,
      bytes: bytes.length,
    })),
    samples,
  });
}
await Deno.writeTextFile(
  `${directory}/results.json`,
  JSON.stringify(
    {
      compiler,
      compiler_sha256: await hash(await Deno.readFile(compiler)),
      load: Deno.readTextFileSync("/proc/loadavg").trim(),
      rows,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify(
    rows.map((row) => ({
      name: row.name,
      byte_identical: row.byte_identical,
      variants: row.variants,
      samples: row.samples,
    })),
    null,
    2,
  ),
);
