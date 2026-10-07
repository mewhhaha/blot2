// deno run --allow-read --allow-write --allow-run scripts/bench_lifetimes.ts \
//   BASELINE_COMPILER CURRENT_COMPILER STD_ROOT OUTPUT_DIR
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { instantiateGuest } from "../compiler/guest.ts";

assert.equal(Deno.args.length, 4);
const [baseline, current, std, output] = Deno.args.map((path) => resolve(path));
await Deno.mkdir(output, { recursive: true });
const source = `import * as iter from "std/iter"
let retained = @list.generate 1000000 (fn index => index)
entry const storage_probe = fn (value: U32) => #[value]
entry const cursor = fn count => iter.fold_left add 0 (iter.take count retained.iter)
entry const range = fn count => iter.fold_left add 0 (iter.range 0 count)
entry const records = fn (count: U32) => do:
  let sum = 0
  for value in 0..count:
    let record = { a: value, b: value, c: value, d: value, e: value, f: value,
      g: value, h: value, i: value, j: value, k: value, l: value,
      m: value, n: value, o: value, p: value, q: value, r: value + 1 }
    let alias = record
    sum := self + alias.a + record.r
  return sum
const make_record = fn value => { a: value, b: value, c: value, d: value, e: value, f: value,
  g: value, h: value, i: value, j: value, k: value, l: value,
  m: value, n: value, o: value, p: value, q: value, r: value + 1 }
const read_record = fn record => record.a + record.b + record.c + record.d + record.e + record.f +
  record.g + record.h + record.i + record.j + record.k + record.l + record.m + record.n +
  record.o + record.p + record.q + record.r
entry const branches = fn (count: U32) => do:
  let sum = 0
  for value in 0..count:
    let record = make_record value
    if value % 2 == 0:
      sum := self + read_record record
    else:
      sum := self + read_record record + 1
  return sum
entry const shared = fn (count: U32) => do:
  let sum = 0
  for value in 0..count:
    let child = { a: value, b: value, c: value, d: value, e: value, f: value,
      g: value, h: value, i: value, j: value, k: value, l: value,
      m: value, n: value, o: value, p: value, q: value, r: value + 1 }
    let left = { child: child, a: value, b: value, c: value, d: value, e: value,
      f: value, g: value, h: value, i: value, j: value, k: value,
      l: value, m: value, n: value, o: value, p: value, q: value }
    let right = { child: child, a: value, b: value, c: value, d: value, e: value,
      f: value, g: value, h: value, i: value, j: value, k: value,
      l: value, m: value, n: value, o: value, p: value, q: value + 2 }
    if value % 2 == 0:
      let alias = left.child
      sum := self + alias.a + right.child.r + left.q + right.q
    else:
      sum := self + right.child.a + left.child.r + left.q + right.q
  return sum
`;
const input = `${output}/lifetimes.blot`;
await Deno.writeTextFile(input, source);
const sha256 = async (path: string) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ].map((value) => value.toString(16).padStart(2, "0")).join("");
const variants = [{ name: "baseline", compiler: baseline }, {
  name: "current",
  compiler: current,
}];
const binaries: Uint8Array<ArrayBuffer>[] = [];
const identities = [];
for (const variant of variants) {
  const wasm = `${output}/${variant.name}.wasm`;
  const result = await new Deno.Command(variant.compiler, {
    args: [
      "build",
      input,
      wasm,
      "--std-root",
      std,
      "--prelude",
      `${std}/prelude.blot`,
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(
    result.success,
    new TextDecoder().decode(result.stdout) +
      new TextDecoder().decode(result.stderr),
  );
  await Deno.writeFile(`${output}/${variant.name}.jsonl`, result.stdout);
  binaries.push(await Deno.readFile(wasm));
  identities.push({
    ...variant,
    compiler_sha256: await sha256(variant.compiler),
    wasm_sha256: await sha256(wasm),
  });
}
const results = [];
for (const name of ["cursor", "range", "records", "branches", "shared"]) {
  const guests = await Promise.all(
    binaries.map((bytes) => instantiateGuest(bytes)),
  );
  for (const guest of guests) {
    assert(
      guest.memoryBytes() > 0,
      "Memory measurements require an exported arena",
    );
  }
  try {
    const count = 100000;
    const expected = (name === "records"
      ? count * count
      : name === "branches"
      ? 9 * count * (count - 1) + count + Math.floor(count / 2)
      : name === "shared"
      ? 2 * count * count + count
      : count * (count - 1) / 2) >>> 0;
    for (const guest of guests) {
      assert.equal(guest.call(name, count), expected);
    }
    for (let round = 0; round < 10; round++) {
      for (const guest of guests) {
        guest.call(name, count);
      }
    }
    const samples: number[][] = [[], []];
    for (let round = 0; round < 25; round++) {
      for (const index of round % 2 ? [1, 0] : [0, 1]) {
        const start = performance.now();
        const result = guests[index].call(name, count);
        samples[index].push(performance.now() - start);
        assert.equal(result, expected);
      }
    }
    for (let index = 0; index < variants.length; index++) {
      results.push({
        name,
        count,
        variant: variants[index].name,
        samples_ms: samples[index],
        memory_bytes: guests[index].memoryBytes(),
      });
    }
  } finally {
    for (const guest of guests) guest.dispose();
  }
}
await Deno.writeTextFile(
  `${output}/report.json`,
  JSON.stringify(
    {
      identities,
      source_sha256: await sha256(input),
      versions: Deno.version,
      results,
      boundary:
        "10 warmups; 25 alternating pairs; startup million-element List outside timing; public guest round trip including reset",
    },
    null,
    2,
  ) + "\n",
);
for (const result of results) {
  const sorted = [...result.samples_ms].sort((left, right) => left - right);
  console.log(
    `${result.name} ${result.variant}: ${
      sorted[Math.floor(sorted.length / 2)].toFixed(3)
    } ms, ${result.memory_bytes} bytes`,
  );
}
