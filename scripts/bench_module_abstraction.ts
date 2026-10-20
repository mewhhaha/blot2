// Candidate-only erasure pairs. Compile overhead against a prior compiler is
// measured separately by bench_compile.ts; these pairs preserve source types.
// deno run --allow-all scripts/bench_module_abstraction.ts BLOTC OUTPUT_DIR
import { strict as assert } from "node:assert";
import { cpuUsage } from "node:process";
import { resolve } from "node:path";
import { Buffer } from "node:buffer";
import { observeGuestAllocations } from "./bench/guest_heap_observer.ts";

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
  {
    name: "generic_record",
    count: 16384,
    plain:
      "type Box a = { value: a }\nconst make: a -> Box a = fn value => { value }\nconst read: Box a -> a = fn box => box.value\n",
    opaque:
      "opaque type Box a = { value: a }\nconst make: a -> Box a = fn value => #Box { value }\nconst read: Box a -> a = fn (#Box box) => box.value\n",
    body:
      "entry const run = fn (count: U32) => do:\n  let original = @array.generate count (fn index => index)\n  let alias = read (make original)\n  original[0] := count\n  return @u32.add (@u32.add (@array.length alias) alias[0]) (@array.get original (@u32.sub count 1))\n",
    expected: 32767,
  },
  {
    name: "floating_identity",
    count: 42,
    plain:
      "type Token = F32\nconst make: F32 -> Token = fn value => value\nconst read: Token -> F32 = fn value => value\n",
    opaque:
      "opaque type Token = F32\nconst make: F32 -> Token = fn value => #Token value\nconst read: Token -> F32 = fn (#Token value) => value\n",
    body: "entry const run = fn (value: F32) => read (make value)\n",
    expected: 42,
  },
  {
    name: "unsigned_identity",
    count: 42,
    plain:
      "type Token = U32\nconst make: U32 -> Token = fn value => value\nconst read: Token -> U32 = fn value => value\n",
    opaque:
      "opaque type Token = U32\nconst make: U32 -> Token = fn value => #Token value\nconst read: Token -> U32 = fn (#Token value) => value\n",
    body: "entry const run = fn (value: U32) => read (make value)\n",
    expected: 42,
  },
];
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
const pinPaths = {
  compiler_sha256: compiler,
  harness_sha256: new URL(import.meta.url),
  observer_sha256: new URL("./bench/guest_heap_observer.ts", import.meta.url),
};
const pins = Object.fromEntries(
  await Promise.all(
    Object.entries(pinPaths).map(async (
      [name, path],
    ) => [name, await hash(await Deno.readFile(path))]),
  ),
);
async function executableSections(bytes: Uint8Array<ArrayBuffer>) {
  let cursor = 8;
  const sections = [];
  while (cursor < bytes.length) {
    const start = cursor, id = bytes[cursor++];
    let size = 0, shift = 0, next: number;
    do {
      next = bytes[cursor++];
      size += (next & 127) * 2 ** shift;
      shift += 7;
      assert(shift <= 35);
    } while (next & 128);
    cursor += size;
    assert(cursor <= bytes.length);
    if (id !== 0) {
      sections.push({
        id,
        bytes: cursor - start,
        sha256: await hash(bytes.slice(start, cursor)),
      });
    }
  }
  assert.equal(cursor, bytes.length);
  return sections;
}
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
    if (item.name === "floating_identity") {
      for (const value of [-0, Infinity, -Infinity, NaN]) {
        assert.equal(run(value), value);
      }
    }
    if (item.name === "unsigned_identity") {
      for (const value of [0, 0x7fffffff, 0xffffffff]) {
        assert.equal(run(value), value | 0);
      }
    }
    for (let warm = 0; warm < 100; warm++) {
      assert.equal(run(item.count), item.expected);
    }
    variants.push({
      name,
      bytes,
      run,
      sha256: await hash(bytes),
      source_sha256: await hash(await Deno.readFile(source)),
      sections: await executableSections(bytes),
      compiler_metrics: JSON.parse(
        new TextDecoder().decode(result.stdout).trim().split("\n").at(-1)!,
      ),
      allocation_traffic: observeGuestAllocations(bytes, [
        ["run", item.count, item.expected],
      ]),
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
    executable_identical: JSON.stringify(variants[0].sections) ===
      JSON.stringify(variants[1].sections),
    allocation_identical: JSON.stringify(variants[0].allocation_traffic) ===
      JSON.stringify(variants[1].allocation_traffic),
    variants: variants.map((
      {
        name,
        sha256,
        source_sha256,
        bytes,
        sections,
        compiler_metrics,
        allocation_traffic,
      },
    ) => ({
      name,
      sha256,
      source_sha256,
      bytes: bytes.length,
      sections,
      compiler_metrics,
      allocation_traffic,
    })),
    samples,
  });
}
for (const [name, path] of Object.entries(pinPaths)) {
  assert.equal(await hash(await Deno.readFile(path)), pins[name]);
}
await Deno.writeTextFile(
  `${directory}/results.json`,
  JSON.stringify(
    {
      compiler,
      ...pins,
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
