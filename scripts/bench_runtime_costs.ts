// deno run --allow-read --allow-write --allow-run scripts/bench_runtime_costs.ts \
//   [COMPILER STD_ROOT OUTPUT_DIR]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { instantiateGuest } from "../compiler/guest.ts";

const compiler = resolve(Deno.args[0] ?? "zig-native/zig-out/bin/blotc");
const std = resolve(Deno.args[1] ?? "std");
const output = resolve(Deno.args[2] ?? "build/runtime-costs");
const source = fileURLToPath(
  new URL("./fixtures/runtime_costs.blot", import.meta.url),
);
await Deno.mkdir(output, { recursive: true });
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const pins: Record<string, string> = {};
for (
  const path of [
    compiler,
    source,
    ...["prelude", "list", "array", "vector"].map((name) =>
      `${std}/${name}.blot`
    ),
  ]
) {
  pins[path] = await hash(await Deno.readFile(path));
}
const compiled = await new Deno.Command(compiler, {
  args: [
    "build",
    source,
    `${output}/runtime.wasm`,
    "--prelude",
    `${std}/prelude.blot`,
    "--std-root",
    std,
  ],
  stdout: "piped",
  stderr: "piped",
}).output();
const log = new TextDecoder().decode(compiled.stdout);
await Deno.writeTextFile(`${output}/compilation.jsonl`, log);
assert(compiled.success, log + new TextDecoder().decode(compiled.stderr));
const compilation = log.trim().split("\n").map((line) => JSON.parse(line)).find(
  (row) => row.kind === "compilation",
);
assert.equal(compilation.memory.live_bytes, 0);
const bytes = await Deno.readFile(`${output}/runtime.wasm`);
const numbers = Uint32Array.from({ length: 8193 }, (_, i) => i);
const specs = [
  ["replace", 1025, Uint32Array.from({ length: 1025 }, (_, i) => i + 1)],
  ["checked", 1025, Uint32Array.from({ length: 1025 }, (_, i) => i + 1)],
  ["nested", 1025, Uint32Array.from({ length: 1025 }, (_, i) => i + 1)],
  ["append", 1025, Uint32Array.from({ length: 1025 }, (_, i) => i)],
  ["append_break", 1025, Uint32Array.from({ length: 1025 }, (_, i) => i)],
  ["append_shared", 1025, 1025 * 1024 / 2],
  ["singleton_lists", 1025, 1025],
  ["singleton_arrays", 1025, 1025],
  ["maybe_demand", 8193, 8193 * 8192 / 2],
  ["maybe_match", 8193, 8193 * 8192 / 2],
  ["mapped", numbers, numbers.map((x) => x + 1)],
  ["mapped_loop", numbers, numbers.map((x) => x + 1)],
  ["vector_loop", 8193, new Float32Array([2, 4, 6])],
] as const;
const rows = [];
try {
  for (const [name, arg, expected] of specs) {
    const guest = await instantiateGuest(bytes);
    rows.push({ name, arg, guest, samples_ms: [] as number[] });
    assert.deepEqual(guest.call(name, arg), expected, name);
  }
  for (let i = 0; i < 1000; i++) {
    for (const row of rows) row.guest.call(row.name, row.arg);
  }
  for (let sample = 0; sample < 31; sample++) {
    for (
      const row of sample % 2 === 0 ? rows : [...rows].reverse()
    ) {
      const start = performance.now();
      for (let i = 0; i < 16; i++) row.guest.call(row.name, row.arg);
      row.samples_ms.push((performance.now() - start) / 16);
    }
  }
  const report = rows.map(({ name, arg, guest, samples_ms }) => ({
    name,
    n: typeof arg === "number" ? arg : arg.length,
    median_ms: [...samples_ms].sort((a, b) => a - b)[15],
    memory_bytes: guest.memoryBytes(),
    samples_ms,
  }));
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
        versions: Deno.version,
        pins,
        compilation,
        wasm_sha256: await hash(bytes),
        boundary:
          "Independent guests of one module; 1,000 warmups, 31 alternating samples of 16 calls. Includes host/guest ABI copies. Memory is committed guest pages, not cumulative allocation or RSS. Compilation is one fresh process with warm filesystem caches, not a cold timing distribution.",
        results: report,
      },
      null,
      2,
    ) + "\n",
  );
  for (const { samples_ms, ...row } of report) console.log(JSON.stringify(row));
} finally {
  for (const row of rows) row.guest.dispose();
}
