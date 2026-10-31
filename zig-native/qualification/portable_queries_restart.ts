// Paired fresh, cache-population and restart measurements for task 019.
//
//   deno run --allow-all zig-native/qualification/portable_queries_restart.ts \
//     BASELINE_BLOTC CANDIDATE_BLOTC OUT_DIR [ROUNDS]
//
// Each round alternates the compiler order. Every workload runs three CLI
// phases per compiler: fresh (persistence disabled), cold cache population and
// a restart from that cache. CPU is child user+system rusage from wait4.
// Gates: every phase of both compilers emits the same Wasm, every restart
// loads its cache, and both compilers reuse the same principal/optimizer work.
import { resolve } from "node:path";

const [baseline, candidate, outArg, roundsArg] = Deno.args;
if (!baseline || !candidate || !outArg) {
  throw new Error("usage: BASELINE CANDIDATE OUT_DIR [ROUNDS]");
}
const rounds = Number(roundsArg ?? "15");
const out = resolve(outArg);
const repo = resolve(new URL("../..", import.meta.url).pathname);
await Deno.mkdir(`${out}/sources`, { recursive: true });

interface Workload {
  name: string;
  entry: string;
}
const workloads: Workload[] = [];
for (const entry of [...Deno.readDirSync(`${repo}/examples`)].sort((a, b) => a.name.localeCompare(b.name))) {
  if (entry.name.endsWith(".blot")) {
    workloads.push({ name: entry.name.slice(0, -5), entry: `${repo}/examples/${entry.name}` });
  }
}
// Principal-heavy families: each entry records a complete principal proof with
// a call publication; rows families add inferred effect-row mappings.
function principalFamily(count: number): string {
  const lines = ["type Box is data = $Box U32"];
  for (let i = 0; i < count; i++) {
    lines.push(`const extract${i} = func (box: Box) : U32 => return case box of\n  $Box value => @u32.add value ${i}`);
    lines.push(`entry const answer${i}: U32 where { type_rep U32 } = @u32.div 8 (extract${i} ($Box 2))`);
  }
  return lines.join("\n") + "\n";
}
// Nonempty inferred type mappings through type-directed dispatch.
function typesFamily(count: number): string {
  const lines = [
    'const from = func value => return @type.result "from" value',
    "const U32.from = func value => return @f32.to_u32 value",
    "const F32.from = func value => return @u32.to_f32 value",
    "const U32.add = func left => return func right => return @u32.add left right",
    "const F32.add = func left => return func right => return @f32.add left right",
    'const add = func left => return func right => return @type.call "add" left right',
    "const count = 10000",
  ];
  for (let i = 0; i < count; i++) lines.push(`entry const builder${i} = add (from (@f32.ceil (@f32.sqrt (from count)))) ${i}`);
  return lines.join("\n") + "\n";
}
function rowsFamily(count: number): string {
  const lines: string[] = [];
  for (let i = 0; i < count; i++) {
    lines.push(`entry const builder${i}: U32 where { type_rep U32 } = do:\n  let local = func value => return value\n  break local ${i}`);
  }
  return lines.join("\n") + "\n";
}
for (const [name, text] of [
  // Box and types checkpoints keep one portable record at any size.
  ["box8", principalFamily(8)],
  ["types8", typesFamily(8)],
  ["rows8", rowsFamily(8)],
  ["rows32", rowsFamily(32)],
  ["rows128", rowsFamily(128)],
] as const) {
  const entry = `${out}/sources/${name}.blot`;
  await Deno.writeTextFile(entry, text);
  workloads.push({ name, entry });
}

async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}
// wait4 reports the child's user+system rusage in microseconds; bash `times`
// rounds to milliseconds, too coarse for builds of a few milliseconds.
const rusageScript = [
  "import os, subprocess, sys",
  "log = sys.argv[1]",
  "with open(log, 'wb') as out, open(log + '.err', 'wb') as err:",
  "    child = subprocess.Popen(sys.argv[2:], stdout=out, stderr=err)",
  "    _, status, usage = os.wait4(child.pid, 0)",
  "    child.returncode = os.waitstatus_to_exitcode(status)",
  "open(log + '.times', 'w').write(str(round((usage.ru_utime + usage.ru_stime) * 1e6)))",
  "sys.exit(child.returncode)",
].join("\n");
async function cacheBytes(directory: string): Promise<number> {
  let total = 0;
  async function walk(path: string) {
    for await (const entry of Deno.readDir(path)) {
      const child = `${path}/${entry.name}`;
      if (entry.isDirectory) await walk(child);
      else if (entry.name.endsWith(".blotcache")) total += (await Deno.stat(child)).size;
    }
  }
  try {
    await walk(directory);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return total;
}

type Phase = "fresh" | "population" | "restart";
interface Sample {
  workload: string;
  phase: Phase;
  variant: string;
  round: number;
  cpu_us: number;
  wall_us: number;
  wasm: string;
  requested_bytes: number;
  peak_bytes: number;
  allocations: number;
  cache_loaded: boolean;
  cache_saved: boolean;
  checkpoint_bytes: number;
  persisted_hits: number;
  persisted_declines: number;
  optimizer_reused: number;
  functions: number;
  selected_reused: number;
}
// Equal-length path labels keep requested path bytes identical across
// compilers and rounds.
const variants = [
  { name: "baseline", label: "v0", executable: resolve(baseline) },
  { name: "candidate", label: "v1", executable: resolve(candidate) },
];
const pad = (round: number) => String(round).padStart(3, "0");
async function run(variant: typeof variants[number], workload: Workload, phase: Phase, round: number, cache: string): Promise<Sample> {
  const output = `${out}/runs/${workload.name}-${variant.label}-${pad(round)}-${phase.slice(0, 3)}.wasm`;
  const log = `${output}.log`;
  const started = performance.now();
  const result = await new Deno.Command("python3", {
    args: ["-I", "-c", rusageScript, log, variant.executable, "build-project", workload.entry, output, "--prelude", `${repo}/std/prelude.blot`, "--std-root", `${repo}/std`],
    env: { LC_ALL: "C", BLOT_CACHE_DIR: cache },
  }).output();
  const wall_us = Math.round((performance.now() - started) * 1000);
  const record = (await Deno.readTextFile(log)).trim().split("\n").map((line) => JSON.parse(line)).find((item) => item.kind === "compilation");
  if (!result.success || !record?.success) throw new Error(`${variant.name} ${phase} ${workload.name} failed: ${await Deno.readTextFile(log)}${await Deno.readTextFile(`${log}.err`)}`);
  const sample: Sample = {
    workload: workload.name,
    phase,
    variant: variant.name,
    round,
    cpu_us: Number(await Deno.readTextFile(`${log}.times`)),
    wall_us,
    wasm: await sha256(await Deno.readFile(output)),
    requested_bytes: record.memory.allocated_bytes,
    peak_bytes: record.memory.peak_bytes,
    allocations: record.memory.allocations,
    cache_loaded: record.restart_cache.loaded,
    cache_saved: record.restart_cache.saved,
    checkpoint_bytes: phase === "fresh" ? 0 : await cacheBytes(cache),
    persisted_hits: record.principals.persisted_hits,
    persisted_declines: record.principals.persisted_declines,
    optimizer_reused: record.runtime_optimization.reused,
    functions: record.runtime_optimization.functions,
    selected_reused: record.selected_queries?.reused ?? 0,
  };
  await Deno.remove(output);
  for (const suffix of ["", ".err", ".times"]) await Deno.remove(`${log}${suffix}`);
  return sample;
}

await Deno.mkdir(`${out}/runs`, { recursive: true });
const samples: Sample[] = [];
const loads: number[][] = [];
for (let round = 0; round < rounds; round++) {
  loads.push((await Deno.readTextFile("/proc/loadavg")).split(" ").slice(0, 3).map(Number));
  const order = round % 2 ? [...variants].reverse() : variants;
  for (const workload of workloads) {
    for (const variant of order) {
      const cache = `${out}/cache/${variant.label}/${workload.name}/${pad(round)}`;
      samples.push(await run(variant, workload, "fresh", round, ""));
      samples.push(await run(variant, workload, "population", round, cache));
      samples.push(await run(variant, workload, "restart", round, cache));
      await Deno.remove(cache, { recursive: true });
    }
  }
  console.log(`round ${round + 1}/${rounds}`);
}
loads.push((await Deno.readTextFile("/proc/loadavg")).split(" ").slice(0, 3).map(Number));

const problems: string[] = [];
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
const rows: string[] = ["workload,phase,variant,samples,cpu_us,wall_us,requested_bytes,peak_bytes,allocations,checkpoint_bytes,persisted_hits,persisted_declines,optimizer_reused,functions,selected_reused"];
const summary: Record<string, unknown>[] = [];
for (const workload of workloads) {
  const digests = new Set(samples.filter((s) => s.workload === workload.name).map((s) => s.wasm));
  if (digests.size !== 1) problems.push(`${workload.name}: ${digests.size} distinct Wasm digests`);
  for (const phase of ["fresh", "population", "restart"] as const) {
    const medians: Record<string, Record<string, number>> = {};
    for (const variant of variants) {
      const group = samples.filter((s) => s.workload === workload.name && s.phase === phase && s.variant === variant.name);
      if (phase === "restart" && group.some((s) => !s.cache_loaded)) problems.push(`${workload.name}/${variant.name}: restart missed its cache`);
      if (phase === "population" && group.some((s) => !s.cache_saved)) problems.push(`${workload.name}/${variant.name}: population did not save`);
      const list = (field: keyof Sample) => JSON.stringify(group.map((s) => s[field] as number).sort((a, b) => a - b));
      const unique = (field: keyof Sample) => {
        const values = [...new Set(group.map((s) => s[field] as number))];
        if (values.length !== 1) problems.push(`${workload.name}/${phase}/${variant.name}: ${String(field)} varies ${values}`);
        return values[0];
      };
      rows.push([workload.name, phase, variant.name, group.length, `"${list("cpu_us")}"`, `"${list("wall_us")}"`, unique("requested_bytes"), unique("peak_bytes"), unique("allocations"), unique("checkpoint_bytes"), unique("persisted_hits"), unique("persisted_declines"), unique("optimizer_reused"), unique("functions"), unique("selected_reused")].join(","));
      medians[variant.name] = {
        cpu_us: median(group.map((s) => s.cpu_us)),
        wall_us: median(group.map((s) => s.wall_us)),
        requested_bytes: group[0].requested_bytes,
        peak_bytes: group[0].peak_bytes,
        checkpoint_bytes: group[0].checkpoint_bytes,
        persisted_hits: group[0].persisted_hits,
        optimizer_reused: group[0].optimizer_reused,
        selected_reused: group[0].selected_reused,
      };
    }
    if (phase === "restart") {
      for (const field of ["persisted_hits", "optimizer_reused"]) {
        if (medians.baseline[field] !== medians.candidate[field]) problems.push(`${workload.name}: restart ${field} ${medians.baseline[field]}→${medians.candidate[field]}`);
      }
    }
    summary.push({ workload: workload.name, phase, ...Object.fromEntries(Object.entries(medians).map(([k, v]) => [k, v])), cpu_ratio: medians.candidate.cpu_us / medians.baseline.cpu_us });
  }
}
function geomean(values: number[]): number {
  return Math.exp(values.reduce((sum, value) => sum + Math.log(value), 0) / values.length);
}
const ratios = Object.fromEntries((["fresh", "population", "restart"] as const).map((phase) => [phase, geomean(summary.filter((s) => s.phase === phase).map((s) => s.cpu_ratio as number))]));
await Deno.writeTextFile(`${out}/portable-queries-restart.csv`, rows.join("\n") + "\n");
const pins = {
  baseline: { executable: variants[0].executable, sha256: await sha256(await Deno.readFile(variants[0].executable)) },
  candidate: { executable: variants[1].executable, sha256: await sha256(await Deno.readFile(variants[1].executable)) },
  rounds,
  workloads: await Promise.all(workloads.map(async (w) => ({ name: w.name, sha256: await sha256(await Deno.readFile(w.entry)) }))),
  loads,
  nproc: navigator.hardwareConcurrency,
  geomean_cpu_ratio: ratios,
  problems,
};
await Deno.writeTextFile(`${out}/portable-queries-restart.json`, JSON.stringify({ pins, summary }, null, 2) + "\n");
console.log(JSON.stringify({ geomean_cpu_ratio: ratios, problems }, null, 2));
if (problems.length) Deno.exit(1);
