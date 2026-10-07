// deno run --allow-read --allow-write --allow-run scripts/bench_list_transfers.ts BASELINE CURRENT STD OUTPUT
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { instantiateGuest } from "../compiler/guest.ts";
const [baseline, current, std, output] = Deno.args.map((p) => resolve(p));
assert.equal(Deno.args.length, 4);
await Deno.mkdir(output, { recursive: true });
const fixtures = [
  {
    name: "forks",
    count: 100000,
    expected: 19999900000 >>> 0,
    source: `
const skip = fn count => fn cursor => do:
  for index in 0..count:
    cursor := @cursor.advance self
  return cursor
let values = @list.generate 200000 identity
let origin = values.iter
let distant = skip 100000 origin
entry const run = fn count => do:
  let left = origin
  let right = distant
  let total = 0
  for index in 0..count:
    total := self + @cursor.value left + @cursor.value right
    left := @cursor.advance self
    right := @cursor.advance self
  return total
`,
  },
  {
    name: "small_helpers",
    count: 100000,
    expected: 10000000000 >>> 0,
    source: `
const pair = fn value => [value, value + 1]
const sum = fn (values: List U32) => do:
  let result = 0
  for value in values:
    result := self + value
  return result
entry const run = fn count => do:
  let result = 0
  for index in 0..count:
    result := self + sum (pair index)
  return result
`,
  },
  {
    name: "nested_builder",
    count: 500,
    expected: 250000,
    source: `
const build = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..count:
      result := [...self, x + y]
  return @array.from_list result
entry const run = fn count => (build count).length
`,
  },
];
const variants = [{ name: "before", compiler: baseline }, {
  name: "after",
  compiler: current,
}];
const rows: Record<string, unknown>[] = [];
for (const fixture of fixtures) {
  const path = `${output}/${fixture.name}.blot`;
  await Deno.writeTextFile(
    path,
    fixture.source + "\nentry const probe = fn (seed: U32) => #[seed]\n",
  );
  const guests: Awaited<ReturnType<typeof instantiateGuest>>[] = [];
  for (const variant of variants) {
    const wasm = `${output}/${fixture.name}-${variant.name}.wasm`;
    const start = performance.now();
    const result = await new Deno.Command(variant.compiler, {
      args: [
        "build",
        path,
        wasm,
        "--std-root",
        std,
        "--prelude",
        `${std}/prelude.blot`,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const wall_ms = performance.now() - start;
    const text = new TextDecoder().decode(result.stdout);
    assert(result.success, text + new TextDecoder().decode(result.stderr));
    await Deno.writeTextFile(
      `${output}/${fixture.name}-${variant.name}.jsonl`,
      text,
    );
    const bytes = await Deno.readFile(wasm);
    const metrics = JSON.parse(text.trim().split("\n").at(-1)!);
    if (variant.name === "after" && fixture.name === "nested_builder") {
      assert(
        metrics.optimization.exact_builders > 0,
        "Builder probe must exercise exact allocation",
      );
    }
    if (variant.name === "after" && fixture.name === "small_helpers") {
      assert(
        metrics.optimization.small_collections > 0,
        "Helper probe must exercise scalar collections",
      );
    }
    guests.push(await instantiateGuest(bytes));
    rows.push({
      kind: "compile",
      fixture: fixture.name,
      variant: variant.name,
      wall_ms,
      wasm_bytes: bytes.length,
      metrics,
    });
  }
  try {
    const samples: number[][] = [[], []];
    for (let round = -10; round < 25; round++) {
      for (const v of round % 2 ? [1, 0] : [0, 1]) {
        const start = performance.now();
        const result = guests[v].call("run", fixture.count);
        const elapsed = performance.now() - start;
        assert.equal(result, fixture.expected);
        if (round >= 0) samples[v].push(elapsed);
      }
    }
    variants.forEach((variant, i) =>
      rows.push({
        kind: "runtime",
        fixture: fixture.name,
        count: fixture.count,
        variant: variant.name,
        samples_ms: samples[i],
        memory_bytes: guests[i].memoryBytes(),
      })
    );
  } finally {
    for (const guest of guests) guest.dispose();
  }
}
await Deno.writeTextFile(
  `${output}/report.json`,
  JSON.stringify(
    {
      versions: Deno.version,
      compilers: await Promise.all(variants.map(async (variant) => ({
        ...variant,
        sha256: [
          ...new Uint8Array(
            await crypto.subtle.digest(
              "SHA-256",
              await Deno.readFile(variant.compiler),
            ),
          ),
        ].map((x) => x.toString(16).padStart(2, "0")).join(""),
      }))),
      rows,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify(
    rows.filter((r) => r.kind === "runtime").map(({ samples_ms, ...row }) => ({
      ...row,
      median_ms: (samples_ms as number[]).toSorted((a, b) => a - b)[12],
    })),
    null,
    2,
  ),
);
