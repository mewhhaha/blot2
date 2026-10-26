import { strict as assert } from "node:assert";
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

// Production counters are already exported: neither module is instrumented or
// rewritten. Runtime calls include the same ownership enter/leave host boundary.
const root = fileURLToPath(new URL("../../", import.meta.url));
const { values } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    "baseline-std": { type: "string", default: "std" },
    output: { type: "string", default: "build/bench/runtime-boundaries" },
    samples: { type: "string", default: "31" },
    batch: { type: "string", default: "5" },
  },
});
assert(
  values.baseline && values.candidate,
  "Provide --baseline and --candidate release compilers",
);
const samples = Number(values.samples), batch = Number(values.batch);
assert(Number.isSafeInteger(samples) && samples >= 3);
assert(Number.isSafeInteger(batch) && batch >= 1);
const output = resolve(root, values.output!);
await Deno.mkdir(output, { recursive: true });
const executable = {
  baseline: resolve(values.baseline),
  candidate: resolve(values.candidate),
};
const libraries = {
  baseline: resolve(root, values["baseline-std"]!),
  candidate: resolve(root, "std"),
};
const entry = resolve(root, "benchmarks/runtime-boundaries/main.blot");
const sha = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
const pins: Record<string, string> = {};
async function pin(path: string) {
  pins[path] = await sha(await Deno.readFile(path));
}
async function tree(path: string) {
  for await (const item of Deno.readDir(path)) {
    const child = resolve(path, item.name);
    if (item.isDirectory) await tree(child);
    else if (item.isFile) await pin(child);
  }
}
for (const path of Object.values(executable)) await pin(path);
if (libraries.baseline !== libraries.candidate) await tree(libraries.baseline);
for (const path of ["std", "compiler", "benchmarks/runtime-boundaries"]) {
  await tree(resolve(root, path));
}
await pin(fileURLToPath(import.meta.url));
const names = [
  "rc_retains",
  "rc_releases",
  "rc_destroyed",
  "cycle_passes",
  "cycle_vertices",
  "cycle_edges",
  "cycle_bytes",
] as const;
type Side = keyof typeof executable;
type Counts = Record<typeof names[number], number>;
type Guest = { exports: WebAssembly.Exports; bytes: Uint8Array<ArrayBuffer> };
const guests = {} as Record<Side, Guest>;
const report = {
  format: 1,
  complete: false,
  created_at: new Date().toISOString(),
  engine: Deno.version,
  scope:
    "Alternating release compiler builds and same-engine Wasm calls. No body instrumentation. Wall times include the host ownership boundary; counters measure traffic, not peak live bytes. Each compiler uses its pinned standard library.",
  samples,
  batch,
  pins,
  compilers: executable,
  standardLibraries: libraries,
  builds: [] as {
    side: Side;
    round: number;
    wall_ms: number;
    wasm_bytes: number;
    wasm_sha256: string;
  }[],
  rows: [] as {
    name: string;
    argument: number;
    expected: number;
    baseline: { counts: Counts; samples_ms: number[]; median_ms: number };
    candidate: { counts: Counts; samples_ms: number[]; median_ms: number };
  }[],
};
const save = () =>
  Deno.writeTextFile(
    resolve(output, "results.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
await save();
const order = (round: number): Side[] =>
  round % 2 ? ["candidate", "baseline"] : ["baseline", "candidate"];
for (let round = 0; round < 3; round++) {
  for (const side of order(round)) {
    const started = performance.now();
    const compiler = await createZigProjectCompiler({
      executable: executable[side],
      entry,
      cacheDirectory: false,
      codegenTier: "optimized",
      prelude: resolve(libraries[side], "prelude.blot"),
      stdRoot: libraries[side],
    });
    try {
      const built = await compiler.build();
      const wall_ms = performance.now() - started;
      assert(built.success, JSON.stringify(built));
      const hash = await sha(built.bytes);
      const previous = report.builds.find((row) => row.side === side);
      if (previous) {
        assert.equal(
          hash,
          previous.wasm_sha256,
          `${side}: nondeterministic output`,
        );
      }
      report.builds.push({
        side,
        round,
        wall_ms,
        wasm_bytes: built.bytes.length,
        wasm_sha256: hash,
      });
      if (!guests[side]) {
        const module = new WebAssembly.Module(built.bytes);
        assert.equal(WebAssembly.Module.imports(module).length, 0);
        guests[side] = {
          exports: new WebAssembly.Instance(module).exports,
          bytes: built.bytes,
        };
        await Deno.writeFile(resolve(output, `${side}.wasm`), built.bytes);
      }
    } finally {
      await compiler.dispose();
    }
    await save();
  }
}
const count = (guest: Guest, name: string) =>
  Number((guest.exports[`blot:${name}`] as WebAssembly.Global).value) >>> 0;
const counts = (guest: Guest) =>
  Object.fromEntries(names.map((name) => [name, count(guest, name)])) as Counts;
function invoke(
  guest: Guest,
  name: string,
  argument: number,
  expected: number,
) {
  (guest.exports["blot:ownership_enter"] as CallableFunction)();
  let outcome = 1;
  try {
    assert.equal(
      (guest.exports[name] as CallableFunction)(argument) >>> 0,
      expected >>> 0,
    );
    outcome = 0;
  } finally {
    (guest.exports["blot:ownership_leave"] as CallableFunction)(outcome);
  }
  assert.equal(count(guest, "rc_roots"), 0);
  assert.equal(count(guest, "rc_leases"), 0);
}
const triangular = (size: number) => size * (size + 1) / 2;
const cases: [string, number, number][] = [["pair_fixed", 0, triangular(2000)]];
for (const size of [32, 2000]) {
  for (
    const name of [
      "nominal_generate",
      "wide_generate",
      "scalar_generate",
      "optional_generate",
      "optional_scalar",
    ]
  ) cases.push([name, size, triangular(size)]);
}
for (const steps of [2, 100, 101]) {
  for (const name of ["direct", "selected", "indexed"]) {
    cases.push([name, steps, triangular(2000) * steps]);
  }
}
for (const size of [32, 2000]) {
  for (const name of ["pipeline", "pipeline_direct"]) {
    cases.push([name, size, size * 24 * (size * 24 - 1) / 2]);
  }
}
for (const steps of [32, 2000]) {
  for (const name of ["reference_scratch", "numeric_scratch"]) {
    cases.push([
      name,
      steps,
      Array.from({ length: steps }, (_, i) => i + i % 512).reduce(
        (a, b) => a + b,
        0,
      ),
    ]);
  }
}
for (const [name, argument, expected] of cases) {
  const measured = {} as Record<
    Side,
    { counts: Counts; samples_ms: number[]; median_ms: number }
  >;
  for (const side of order(0)) {
    const guest = guests[side];
    for (let i = 0; i < 5; i++) invoke(guest, name, argument, expected);
    const before = counts(guest);
    invoke(guest, name, argument, expected);
    const after = counts(guest);
    measured[side] = {
      counts: Object.fromEntries(
        names.map((key) => [key, (after[key] - before[key]) >>> 0]),
      ) as Counts,
      samples_ms: [],
      median_ms: 0,
    };
  }
  for (let round = 0; round < samples; round++) {
    for (const side of order(round)) {
      const started = performance.now();
      for (let i = 0; i < batch; i++) {
        invoke(guests[side], name, argument, expected);
      }
      measured[side].samples_ms.push((performance.now() - started) / batch);
    }
  }
  for (const side of order(0)) {
    measured[side].median_ms = measured[side].samples_ms.toSorted((a, b) =>
      a - b
    )[Math.floor(samples / 2)];
  }
  const c = measured.candidate.counts;
  if (
    [
      "direct",
      "indexed",
      "selected",
      "nominal_generate",
      "wide_generate",
      "scalar_generate",
      "numeric_scratch",
      "optional_generate",
      "pipeline",
    ].includes(name)
  ) assert.equal(c.rc_destroyed, 1, name);
  if (name === "reference_scratch") {
    assert.deepEqual([c.rc_retains, c.rc_releases, c.rc_destroyed], [
      512,
      1025,
      513,
    ]);
  }
  for (const side of order(0)) {
    assert.equal(measured[side].counts.cycle_passes, 0);
  }
  report.rows.push({ name, argument, expected, ...measured });
  await save();
  console.log(
    `${name}(${argument}): ${measured.baseline.median_ms.toFixed(4)} -> ${
      measured.candidate.median_ms.toFixed(4)
    } ms; retired ${measured.baseline.counts.rc_destroyed} -> ${c.rc_destroyed}`,
  );
}
for (const [path, hash] of Object.entries(pins)) {
  assert.equal(
    await sha(await Deno.readFile(path)),
    hash,
    `Input drift: ${path}`,
  );
}
report.complete = true;
await save();
console.log(`Report: ${resolve(output, "results.json")}`);
