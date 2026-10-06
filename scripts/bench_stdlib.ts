// deno run --allow-read --allow-write --allow-run scripts/bench_stdlib.ts \
//   COMPILER STD_ROOT OUTPUT_DIR [BASELINE_COMPILER BASELINE_STD_ROOT]
// Runtime samples alternate variants after warming both Wasm instances. They
// include guest ABI copying; compiler timings are recorded separately.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { type Guest, instantiateGuest } from "../compiler/guest.ts";

const output = resolve(Deno.args[2] ?? "build/stdlib-bench");
const variants = [
  {
    name: "current",
    compiler: resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc"),
    std: resolve(Deno.args[1] ?? "std"),
  },
];
if (Deno.args[3] && Deno.args[4]) {
  variants.unshift({
    name: "baseline",
    compiler: resolve(Deno.args[3]),
    std: resolve(Deno.args[4]),
  });
} else if (Deno.args[3] || Deno.args[4]) {
  throw new Error("Supply both baseline compiler and standard-library paths");
}
await Deno.mkdir(output, { recursive: true });
const input = Uint32Array.from({ length: 8193 }, (_, i) => i);
const evens = [...input].filter((x) => x % 2 === 0);
const cases = [
  [
    "prefix_sums",
    "fn (values: Array U32) => array.prefix_sums values",
    input,
    [...input].map((i) => i * (i + 1) / 2),
  ],
  [
    "indices",
    "fn (values: Array U32) => array.indices (array.map (fn x => x % 2 == 0) values)",
    input,
    evens,
  ],
  [
    "filter",
    "fn (values: Array U32) => array.filter (fn x => x % 2 == 0) values",
    input,
    evens,
  ],
  [
    "filter_map",
    "fn (values: Array U32) => array.filter_map (fn x => if x % 2 == 0 then #Some (x + 1) else #Nothing) values",
    input,
    evens.map((x) => x + 1),
  ],
  ["concat", "fn (values: Array U32) => array.concat values values", input, [
    ...input,
    ...input,
  ]],
  [
    "flatten",
    "fn (values: Array U32) => array.flatten #[#[], values, #[], values, #[]]",
    input,
    [...input, ...input],
  ],
  ["push", "fn (values: Array U32) => array.push 42 values", input, [
    ...input,
    42,
  ]],
  [
    "list_append",
    "fn (count: U32) => do:\n  let values: List U32 = []\n  for i in 0..count:\n    values := list.append i values\n  return Array.from_list values",
    1025,
    Array.from({ length: 1025 }, (_, i) => i),
  ],
  [
    "array_replace",
    "fn (count: U32) => do:\n  let values = array.fill count 0\n  for i in 0..count:\n    values := array.replace i (i + 1) values\n  return values",
    1025,
    Array.from({ length: 1025 }, (_, i) => i + 1),
  ],
  [
    "vector_lerp",
    "fn (count: U32) => do:\n  let v = #Vec3 { x: 1.0, y: 2.0, z: 3.0 }\n  for i in 0..count:\n    v := lerp v (#Vec3 { x: 2.0, y: 4.0, z: 6.0 }) 0.5\n  return #[v.x, v.y, v.z]",
    8193,
    [2, 4, 6],
  ],
  [
    "result_iterate",
    "fn (count: U32) => do:\n  let result = Result.iterate 0 (fn i => #Ok (if i < count then #Continue (i + 1) else #Done i))\n  return #[Result.unwrap_or 0 result]",
    8193,
    [8193],
  ],
  [
    "tan",
    "fn (values: Array U32) => array.map (fn x => tan (F32.from x / 10000.0)) values",
    input,
    null,
  ],
] as const;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
const pins: Record<string, string> = {};
for (const variant of variants) {
  for (
    const path of [
      variant.compiler,
      ...["prelude", "array", "list", "vector"].map((name) =>
        `${variant.std}/${name}.blot`
      ),
    ]
  ) pins[path] = await hash(await Deno.readFile(path));
}
type Measurement = {
  variant: string;
  name: string;
  wasm_bytes: number;
  wasm_sha256: string;
  compilation: Record<string, unknown>;
  first_memory_bytes: number;
  warm_memory_bytes: number;
  samples_ms: number[];
  median_ms: number;
};
const measurements: Measurement[] = [];
for (const [name, body, argument, expected] of cases) {
  const guests: { guest: Guest; result: Measurement }[] = [];
  try {
    for (const variant of variants) {
      const stem = `${output}/${variant.name}-${name}`;
      await Deno.writeTextFile(
        `${stem}.blot`,
        `import * as array from "std/array"\nimport * as list from "std/list"\nimport { Vec3 } from "std/vector"\nentry const run = ${body}\n`,
      );
      const compiled = await new Deno.Command(variant.compiler, {
        args: [
          "build",
          `${stem}.blot`,
          `${stem}.wasm`,
          "--prelude",
          `${variant.std}/prelude.blot`,
          "--std-root",
          variant.std,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      const log = new TextDecoder().decode(compiled.stdout);
      await Deno.writeTextFile(`${stem}.jsonl`, log);
      assert(compiled.success, log + new TextDecoder().decode(compiled.stderr));
      const compilation = log.trim().split("\n").map((line) => JSON.parse(line))
        .find((row) => row.kind === "compilation");
      assert.equal(compilation.memory.live_bytes, 0);
      const bytes = await Deno.readFile(`${stem}.wasm`);
      const guest = await instantiateGuest(bytes);
      const result: Measurement = {
        variant: variant.name,
        name,
        wasm_bytes: bytes.length,
        wasm_sha256: await hash(bytes),
        compilation,
        first_memory_bytes: 0,
        warm_memory_bytes: 0,
        samples_ms: [],
        median_ms: 0,
      };
      guests.push({ guest, result });
      const actual = guest.call("run", argument) as Uint32Array | Float32Array;
      if (expected) assert.deepEqual([...actual], expected);
      else {for (let i = 0; i < actual.length; i++) {
          assert(
            Math.abs(actual[i] - Math.tan(Math.fround(i / 10000))) < 0.00002,
          );
        }}
      result.first_memory_bytes = guest.memoryBytes();
    }
    for (let i = 0; i < 1000; i++) {
      for (const { guest } of guests) guest.call("run", argument);
    }
    for (let sample = 0; sample < 31; sample++) {
      const order = sample % 2 === 0 ? guests : [...guests].reverse();
      for (const { guest, result } of order) {
        const start = performance.now();
        for (let i = 0; i < 16; i++) guest.call("run", argument);
        result.samples_ms.push((performance.now() - start) / 16);
      }
    }
    for (const { guest, result } of guests) {
      result.warm_memory_bytes = guest.memoryBytes();
      result.median_ms = [...result.samples_ms].sort((a, b) => a - b)[15];
      measurements.push(result);
      console.log(
        JSON.stringify({
          name,
          variant: result.variant,
          median_ms: result.median_ms,
          memory_bytes: result.warm_memory_bytes,
          wasm_bytes: result.wasm_bytes,
        }),
      );
    }
  } finally {
    for (const { guest } of guests) guest.dispose();
  }
}
// Fresh processes with warm filesystem caches. These inputs expose the const
// evaluator's storage cost, independently of runtime Wasm collection ownership.
const staged: {
  variant: string;
  length: number;
  source_sha256: string;
  samples: {
    success: boolean;
    wall_ms: number;
    compilation: Record<string, unknown>;
    diagnostics: unknown[];
  }[];
}[] = [];
for (const length of [256, 1024, 4096, 8193]) {
  const source = `${output}/staged-${length}.blot`;
  await Deno.writeTextFile(
    source,
    `const build = fn count => do:
  let values: List U32 = []
  for i in 0..count:
    values := [...self, i]
  return values
entry const answer = (Array.from_list (build ${length}))[${length - 1}]
`,
  );
  const sourceHash = await hash(await Deno.readFile(source));
  const lanes = variants.map((variant) => ({
    variant,
    result: {
      variant: variant.name,
      length,
      source_sha256: sourceHash,
      samples: [] as (typeof staged)[number]["samples"],
    },
  }));
  for (let sample = 0; sample < 7; sample++) {
    const order = sample % 2 === 0 ? lanes : [...lanes].reverse();
    for (const { variant, result } of order) {
      const stem = `${output}/${variant.name}-staged-${length}`;
      const start = performance.now();
      const compiled = await new Deno.Command(variant.compiler, {
        args: [
          "build",
          source,
          `${stem}.wasm`,
          "--prelude",
          `${variant.std}/prelude.blot`,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      const wall = performance.now() - start;
      const log = new TextDecoder().decode(compiled.stdout);
      await Deno.writeTextFile(`${stem}-${sample}.jsonl`, log);
      const records = log.trim().split("\n").map((line) => JSON.parse(line));
      const compilation = records.find((row) => row.kind === "compilation");
      const diagnostics = records.filter((row) => row.kind === "diagnostic");
      assert(compilation, new TextDecoder().decode(compiled.stderr));
      assert.equal(compilation.memory.live_bytes, 0);
      assert.equal(compilation.success, compiled.success);
      if (compiled.success) {
        const guest = await instantiateGuest(
          await Deno.readFile(`${stem}.wasm`),
        );
        try {
          assert.equal(guest.read("answer"), length - 1);
        } finally {
          guest.dispose();
        }
      } else {
        assert.equal(variant.name, "baseline", log);
        assert.equal(diagnostics.length, 1, log);
        assert.equal(diagnostics[0].code, "constant_fuel", log);
      }
      result.samples.push({
        success: compiled.success,
        wall_ms: wall,
        compilation,
        diagnostics,
      });
    }
  }
  for (const { result } of lanes) staged.push(result);
}
for (const [path, pin] of Object.entries(pins)) {
  assert.equal(
    await hash(await Deno.readFile(path)),
    pin,
    `${path} changed during measurement`,
  );
}
await Deno.writeTextFile(
  `${output}/report.json`,
  JSON.stringify(
    {
      boundary:
        "8,193 elements/iterations (1,025 for list_append and array_replace), 1,000 warmups per variant, 31 alternating samples of 16 calls. Guest ABI copies included. Memory is committed guest pages, not total allocations or compiler RSS. Compilation records are individual warm-filesystem builds, not a cold distribution.",
      staged_boundary:
        "7 alternating fresh processes per variant and length, warm filesystem caches, default evaluator limits. wall_ms includes process launch, compilation, output writing and teardown; result execution is checked outside that interval. Compilation memory counts requested compiler bytes, not allocator overhead or RSS. Baseline constant_fuel failures are retained as failures, not speedups.",
      versions: Deno.version,
      pins,
      measurements,
      staged,
    },
    null,
    2,
  ) + "\n",
);
