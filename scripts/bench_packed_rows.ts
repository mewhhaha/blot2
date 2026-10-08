// deno run --allow-read --allow-write --allow-run scripts/bench_packed_rows.ts BASELINE CURRENT STD OUTPUT
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpuUsage } from "node:process";
import { instantiateGuest } from "../compiler/guest.ts";
const [baseline, current, std, output] = Deno.args.map((p) => resolve(p));
assert.equal(Deno.args.length, 4);
await Deno.mkdir(output, { recursive: true });
const fixtures = [
  {
    name: "retained_array_rows",
    count: 1,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
let rows = @array.generate 100000 (fn i => {c: i * 2, a: i, b: i + 1})
entry const run = fn factor => do:
  let result = 0
  for row in rows:
    result := self + row.a + row.b + row.c
  return result * factor
`,
  },
  {
    name: "retained_list_rows",
    count: 1,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
let rows = @list.generate 100000 (fn i => {c: i * 2, a: i, b: i + 1})
entry const run = fn factor => do:
  let result = 0
  for row in rows:
    result := self + row.a + row.b + row.c
  return result * factor
`,
  },
  {
    name: "retained_list_cursor",
    count: 100000,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
let rows = @list.generate 100000 (fn i => {c: i * 2, a: i, b: i + 1})
entry const run = fn count => do:
  let cursor = rows.iter
  let result = 0
  for i in 0..count:
    let row = @cursor.value cursor
    result := self + row.a + row.b + row.c
    cursor := @cursor.advance self
  return result
`,
  },
  {
    name: "generated_rows",
    count: 100000,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
const build = fn count => @array.generate count (fn i => {c: i * 2, a: i, b: i + 1})
const sum = fn values => do:
  let result = 0
  for row in values:
    result := self + row.a + row.b + row.c
  return result
entry const run = fn count => sum (build count)
`,
  },
  {
    name: "comprehension_rows",
    count: 100000,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
const build = fn count => #[(i, i + 1, i * 2) | i <- @array.generate count identity]
const sum = fn values => do:
  let result = 0
  for (a, b, c) in values:
    result := self + a + b + c
  return result
entry const run = fn count => sum (build count)
`,
  },
  {
    name: "indexed_rows",
    count: 100000,
    expected: (100000 * (2 * 100000 - 1)) >>> 0,
    source: `
const build = fn count => @array.generate count (fn i => {c: i * 2, a: i, b: i + 1})
entry const run = fn count => do:
  let rows = build count
  let result = 0
  for i in 0..count:
    result := self + rows[i].a + rows[i].b + rows[i].c
  return result
`,
  },
  {
    name: "list_roundtrip",
    count: 100000,
    expected: (100000 * 100000) >>> 0,
    source: `
const build = fn count => @array.generate count (fn i => {a: i, b: i + 1})
const sum = fn values => do:
  let result = 0
  for row in values:
    result := self + row.a + row.b
  return result
entry const run = fn count => sum (@array.from_list (@list.from_array (build count)))
`,
  },
  {
    name: "reference_rows",
    count: 100000,
    expected: (100000 * 100000) >>> 0,
    source: `
const build = fn count => @array.generate count (fn i => {a: #[i], b: i + 1})
entry const run = fn count => do:
  let result = 0
  for row in build count:
    result := self + row.a[0] + row.b
  return result
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
    const cpu: number[][] = [[], []];
    for (let round = -10; round < 25; round++) {
      for (const v of round % 2 ? [1, 0] : [0, 1]) {
        const used = cpuUsage();
        const start = performance.now();
        const result = guests[v].call("run", fixture.count);
        const elapsed = performance.now() - start;
        const work = cpuUsage(used);
        assert.equal(result, fixture.expected);
        if (round >= 0) {
          samples[v].push(elapsed);
          cpu[v].push((work.user + work.system) / 1000);
        }
      }
    }
    variants.forEach((variant, i) =>
      rows.push({
        kind: "runtime",
        fixture: fixture.name,
        count: fixture.count,
        variant: variant.name,
        samples_ms: samples[i],
        process_cpu_ms: cpu[i],
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
      note:
        "Ordinary source programs: flat scalar Array and List rows. Alternating warmed runtime samples, scalar host results, Wasm memory page high-water, compilation logs recorded separately. Compiler paths and hashes pinned below.",
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
    rows.filter((r) => r.kind === "runtime").map((
      { samples_ms, process_cpu_ms, ...row },
    ) => ({
      ...row,
      median_ms: (samples_ms as number[]).toSorted((a, b) => a - b)[12],
      median_process_cpu_ms:
        (process_cpu_ms as number[]).toSorted((a, b) => a - b)[12],
    })),
    null,
    2,
  ),
);
