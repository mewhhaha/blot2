// Same-host release comparison for task 109. Private issue repros stay outside
// the checkout; optionally supply one exporting guarded_sum(count: U32).
// deno run --allow-all scripts/bench_array_throughput.ts \
//   PINNED_BLOTC PRE_FIX_BLOTC CURRENT_BLOTC INK_ROOT OUTPUT [ISSUE_REPRO]
import { strict as assert } from "node:assert";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { cpuUsage } from "node:process";
import type { instantiateGuest } from "../compiler/guest.ts";

assert(Deno.args.length === 5 || Deno.args.length === 6);
const [pinned, before, current, ink, output, repro] = Deno.args.map((p) =>
  resolve(p)
);
const hash = async (path: string | URL) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ].map(
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
const median = (values: number[]) =>
  values.toSorted((a, b) => a - b)[Math.floor(values.length / 2)];
const variants = [
  { name: "pinned", compiler: pinned },
  { name: "before", compiler: before },
  { name: "current", compiler: current },
].map((variant) => ({
  ...variant,
  root: resolve(dirname(variant.compiler), "../../.."),
  std: resolve(dirname(variant.compiler), "../../../std"),
}));
const warmup = 400, rounds = 101, batch = 16;
await Deno.mkdir(output); // Refuse to mix separate campaigns.
const pins: Record<string, string> = {};
async function pinTree(directory: string) {
  for await (const item of Deno.readDir(directory)) {
    const path = `${directory}/${item.name}`;
    if (item.isDirectory) await pinTree(path);
    else if (item.isFile && /\.(blot|ts)$/.test(item.name)) {
      pins[path] = await hash(path);
    }
  }
}
for (const variant of variants) {
  await pinTree(variant.std);
  await pinTree(`${variant.root}/compiler`);
}
await pinTree(`${ink}/lib`);
pins[`${ink}/tools/compiler-probe.blot`] = await hash(
  `${ink}/tools/compiler-probe.blot`,
);
pins[new URL(import.meta.url).pathname] = await hash(new URL(import.meta.url));
for (const variant of variants) {
  pins[variant.compiler] = await hash(variant.compiler);
}
if (repro) pins[repro] = await hash(repro);
const compileRows: Record<string, unknown>[] = [];
const runtimeRows: Record<string, unknown>[] = [];
const summary: Record<string, unknown>[] = [];
const report = {
  schema: 1,
  recorded_at: new Date().toISOString(),
  versions: Deno.version,
  warmup,
  rounds,
  batch,
  notes:
    "Alternating paired guest calls include ABI decoding. Each compiler uses its matching std and guest API, against shared Ink and issue sources; release compilers.",
  issue_repro_supplied: Boolean(repro),
  affinity: (await Deno.readTextFile("/proc/self/status")).split("\n").find((
    line,
  ) => line.startsWith("Cpus_allowed_list:")),
  pins,
  variants,
  compile: compileRows,
  runtime: runtimeRows,
  summary,
};
const save = () =>
  Deno.writeTextFile(
    `${output}/results.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
await save();
const workloads = [{
  name: "ink",
  entry: `${ink}/tools/compiler-probe.blot`,
  probes: ["inline_writes", "break_writes", "unsigned_sort", "pathfinding"],
  counts: [1000, 2000],
}];
if (repro) {
  workloads.push({
    name: "issue",
    entry: repro,
    probes: ["guarded_sum"],
    counts: [128, 256],
  });
}
function witness(name: string, count: number, value: unknown) {
  if (name === "guarded_sum") {
    assert.equal(value, count * (count - 1) / 2);
    return value;
  }
  assert(ArrayBuffer.isView(value));
  const words = Array.from(value as Uint32Array);
  let expected: number[];
  if (name.endsWith("writes")) expected = [count - 1, count * (count - 1) / 2];
  else if (name === "pathfinding") expected = [count - 1, count, count];
  else expected = [count - 1, 0, count, count * (count * count - 1) / 6];
  assert.deepEqual(words, expected, `${name} ${count} witness`);
  return words;
}
for (const workload of workloads) {
  const guests: Awaited<ReturnType<typeof instantiateGuest>>[] = [];
  try {
    for (const variant of variants) {
      const std = variant.std;
      const wasm = `${output}/${workload.name}-${variant.name}.wasm`;
      const compiled = await new Deno.Command(variant.compiler, {
        args: [
          "build-project",
          workload.entry,
          wasm,
          "--std-root",
          std,
          "--prelude",
          `${std}/prelude.blot`,
          "--alias",
          `ink/=${ink}/lib/`,
        ],
        env: { BLOT_CACHE_DIR: "" },
        stdout: "piped",
        stderr: "piped",
      }).output();
      await Deno.writeFile(
        `${output}/${workload.name}-${variant.name}.jsonl`,
        compiled.stdout,
      );
      await Deno.writeFile(
        `${output}/${workload.name}-${variant.name}.stderr`,
        compiled.stderr,
      );
      assert(
        compiled.success,
        new TextDecoder().decode(compiled.stdout) +
          new TextDecoder().decode(compiled.stderr),
      );
      const metrics = JSON.parse(
        new TextDecoder().decode(compiled.stdout).trim().split("\n").at(-1)!,
      );
      assert.equal(
        metrics.memory.live_bytes,
        0,
        "Compiler teardown must release every allocation",
      );
      const bytes = await Deno.readFile(wasm);
      const module = new WebAssembly.Module(bytes);
      const ownership = WebAssembly.Module.customSections(
        module,
        "blot:ownership",
      );
      assert(ownership.length <= 1);
      const admission = ownership.length
        ? [...new Uint8Array(ownership[0])]
        : null;
      // The historical pinned toolchain predates this custom section. Both
      // counted-owner compilers must still declare the exact current mode.
      if (variant.name !== "pinned") assert.deepEqual(admission, [2, 2, 0]);
      const api = await import(
        pathToFileURL(`${variant.root}/compiler/guest.ts`).href
      );
      guests.push(await api.instantiateGuest(module));
      compileRows.push({
        workload: workload.name,
        variant: variant.name,
        wasm_bytes: bytes.length,
        wasm_sha256: await hash(wasm),
        ownership: admission,
        metrics,
      });
    }
    for (const name of workload.probes) {
      const expected = new Map<number, unknown>();
      for (let round = 0; round < warmup; round++) {
        for (const guest of guests) {
          for (const count of workload.counts) {
            const value = witness(name, count, guest.call(name, count));
            if (expected.has(count)) {
              assert.deepEqual(value, expected.get(count));
            } else expected.set(count, value);
          }
        }
      }
      const warmMemory = guests.map((guest) => guest.memoryBytes());
      for (const count of workload.counts) {
        const samples = variants.map(() => ({
          wall_ms: [] as number[],
          cpu_ms: [] as number[],
        }));
        for (let round = 0; round < rounds; round++) {
          const order = round % 2 ? [2, 1, 0] : [0, 1, 2];
          for (const index of order) {
            const startedCpu = cpuUsage(), started = performance.now();
            let value: unknown;
            for (let call = 0; call < batch; call++) {
              value = guests[index].call(name, count);
            }
            const elapsed = performance.now() - started,
              used = cpuUsage(startedCpu);
            assert.deepEqual(witness(name, count, value), expected.get(count));
            samples[index].wall_ms.push(elapsed / batch);
            samples[index].cpu_ms.push(
              (used.user + used.system) / 1000 / batch,
            );
          }
        }
        const medians = samples.map((s) => median(s.wall_ms));
        for (let index = 0; index < variants.length; index++) {
          assert.equal(
            guests[index].memoryBytes(),
            warmMemory[index],
            `${name}: memory must plateau after warmup`,
          );
          runtimeRows.push({
            workload: workload.name,
            name,
            count,
            variant: variants[index].name,
            ...samples[index],
            wall_ms_median: medians[index],
            cpu_ms_median: median(samples[index].cpu_ms),
            memory_bytes: guests[index].memoryBytes(),
            warm_memory_bytes: warmMemory[index],
            witness: expected.get(count),
          });
        }
        const row = {
          name,
          count,
          pinned_ms: medians[0],
          before_ms: medians[1],
          current_ms: medians[2],
          current_to_pinned: medians[2] / medians[0],
          paired_ratios: samples[2].wall_ms.map((value, round) =>
            value / samples[0].wall_ms[round]
          ),
          paired_ratio_median: median(
            samples[2].wall_ms.map((value, round) =>
              value / samples[0].wall_ms[round]
            ),
          ),
        };
        summary.push(row);
        await save();
        console.log(JSON.stringify({ ...row, paired_ratios: undefined }));
      }
    }
  } finally {
    for (const guest of guests) guest.dispose();
  }
}
await save();
