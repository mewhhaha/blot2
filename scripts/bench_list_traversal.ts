// deno run --allow-read --allow-write --allow-run scripts/bench_list_traversal.ts \
//   BASELINE CURRENT STD OUTPUT [record|tuple] [REPEAT] [u32|f32]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpuUsage } from "node:process";
import { fileURLToPath } from "node:url";
import { instantiateGuest } from "../compiler/guest.ts";

assert(Deno.args.length >= 4 && Deno.args.length <= 7);
const [baseline, candidate, std, output] = Deno.args.slice(0, 4).map((p) =>
  resolve(p)
);
const shape = Deno.args[4] ?? "record";
assert(shape === "record" || shape === "tuple");
const repeat = Number(Deno.args[5] ?? 16);
assert(Number.isSafeInteger(repeat) && repeat > 0 && repeat <= 4096);
const scalar = Deno.args[6] ?? "u32";
assert(scalar === "u32" || scalar === "f32");
await Deno.mkdir(output, { recursive: true });
const hash = async (path: string | URL) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ]
    .map((x) => x.toString(16).padStart(2, "0")).join("");
const pins: Record<string, string> = {};
const scriptPath = fileURLToPath(import.meta.url);
pins[scriptPath] = await hash(scriptPath);
for (const path of [baseline, candidate]) pins[path] = await hash(path);
for await (const entry of Deno.readDir(std)) {
  if (entry.isFile && entry.name.endsWith(".blot")) {
    const path = `${std}/${entry.name}`;
    pins[path] = await hash(path);
  }
}
const variants = [
  { name: "baseline", compiler: baseline },
  { name: "candidate", compiler: candidate },
];
const rows: Record<string, unknown>[] = [];
const count = 16384;
const readLoad = async () => {
  try {
    return Number((await Deno.readTextFile("/proc/loadavg")).split(" ")[0]);
  } catch {
    return null;
  }
};
const loadStart = await readLoad();
const median = (values: number[]) =>
  [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

for (let width = shape === "tuple" ? 2 : 1; width <= 16; width++) {
  const fields = Array.from(
    { length: width },
    (_, i) => {
      const value = scalar === "f32" ? `@u32.to_f32 (i + ${i})` : `i + ${i}`;
      return shape === "tuple" ? value : `f${i}: ${value}`;
    },
  ).join(", ");
  const value = shape === "tuple" ? `(${fields})` : `{${fields}}`;
  const binder = shape === "tuple"
    ? `(${Array.from({ length: width }, (_, i) => `f${i}`).join(", ")})`
    : "row";
  const sum = Array.from(
    { length: width },
    (_, i) => shape === "tuple" ? `f${i}` : `row.f${i}`,
  ).join(" + ");
  const path = `${output}/width-${width}.blot`;
  await Deno.writeTextFile(
    path,
    `let rows = @list.generate ${count} (fn i => ${value})
entry const fold = fn repeat => do:
  let total = ${scalar === "f32" ? "0.0" : "0"}
  for pass in 0..repeat:
    for ${binder} in rows:
      total := self + ${sum}
  return total
entry const cursor = fn repeat => do:
  let total = ${scalar === "f32" ? "0.0" : "0"}
  for pass in 0..repeat:
    let cursor = rows.iter
    for i in 0..${count}:
      let ${binder} = @cursor.value cursor
      total := self + ${sum}
      cursor := @cursor.advance self
  return total
// An aggregate entry exposes the arena to the host memory measurement.
entry const memory_probe = fn (seed: U32) => #[seed]
`,
  );
  pins[path] = await hash(path);
  const guests: Awaited<ReturnType<typeof instantiateGuest>>[] = [];
  try {
    for (const variant of variants) {
      const wasm = `${output}/width-${width}-${variant.name}.wasm`;
      const started = performance.now();
      const compiled = await new Deno.Command(variant.compiler, {
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
        env: { BLOT_CACHE_DIR: "" },
      }).output();
      const wall_ms = performance.now() - started;
      const log = new TextDecoder().decode(compiled.stdout);
      await Deno.writeTextFile(
        `${output}/width-${width}-${variant.name}.jsonl`,
        log,
      );
      assert(compiled.success, log + new TextDecoder().decode(compiled.stderr));
      const bytes = await Deno.readFile(wasm);
      assert(WebAssembly.validate(bytes));
      const metrics = JSON.parse(log.trim().split("\n").at(-1)!);
      assert.equal(metrics.memory.live_bytes, 0);
      guests.push(await instantiateGuest(bytes));
      assert(
        guests.at(-1)!.memoryBytes() > 0,
        "Guest arena must be measurable",
      );
      rows.push({
        kind: "compile",
        shape,
        width,
        variant: variant.name,
        wall_ms,
        wasm_bytes: bytes.length,
        wasm_sha256: await hash(wasm),
        metrics,
      });
    }
    let expected = (repeat * (width * count * (count - 1) / 2 +
      count * width * (width - 1) / 2)) >>> 0;
    if (scalar === "f32") {
      expected = 0;
      for (let pass = 0; pass < repeat; pass++) {
        for (let index = 0; index < count; index++) {
          for (let field = 0; field < width; field++) {
            expected = Math.fround(expected + (index + field));
          }
        }
      }
    }
    for (const operation of ["fold", "cursor"]) {
      const samples = variants.map(() => ({
        process_cpu_ms: [] as number[],
        wall_ms: [] as number[],
      }));
      for (let round = -20; round < 31; round++) {
        for (const index of round % 2 ? [1, 0] : [0, 1]) {
          const before = cpuUsage();
          const started = performance.now();
          const result = guests[index].call(operation, repeat);
          const elapsed = performance.now() - started;
          const used = cpuUsage(before);
          assert.equal(result, expected);
          if (round >= 0) {
            samples[index].process_cpu_ms.push(
              (used.user + used.system) / 1000 / repeat,
            );
            samples[index].wall_ms.push(elapsed / repeat);
          }
        }
      }
      for (let index = 0; index < variants.length; index++) {
        rows.push({
          kind: "runtime",
          shape,
          operation,
          width,
          count,
          repeat,
          variant: variants[index].name,
          ...samples[index],
          memory_bytes: guests[index].memoryBytes(),
        });
      }
      console.log(JSON.stringify({
        width,
        operation,
        baseline_cpu_ms: median(samples[0].process_cpu_ms),
        candidate_cpu_ms: median(samples[1].process_cpu_ms),
        ratio: median(samples[1].process_cpu_ms) /
          median(samples[0].process_cpu_ms),
      }));
    }
  } finally {
    for (const guest of guests) guest.dispose();
  }
}
for (const [path, pin] of Object.entries(pins)) {
  assert.equal(await hash(path), pin, path);
}
await Deno.writeTextFile(
  `${output}/report.json`,
  JSON.stringify(
    {
      note:
        `${scalar.toUpperCase()} ${shape} rows, widths ${
          shape === "tuple" ? 2 : 1
        }–16, ` +
        "immutable retained Lists, full fold and explicit cursor. " +
        `20 warmups, 31 alternating paired samples, each ${repeat} traversals. ` +
        "Per-traversal process CPU includes V8/host overhead. " +
        "Guest memory is committed pages; compiler allocation is separate.",
      pins,
      count,
      repeat,
      versions: Deno.version,
      host: {
        os: Deno.build.os,
        arch: Deno.build.arch,
        load_start: loadStart,
        load_end: await readLoad(),
      },
      rows,
    },
    null,
    2,
  ) + "\n",
);
