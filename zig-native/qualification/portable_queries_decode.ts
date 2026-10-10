// In-process checkpoint decode measurements for task 019.
//
//   deno run --allow-all zig-native/qualification/portable_queries_decode.ts \
//     BASELINE_BLOTC BASELINE_PROBE CANDIDATE_BLOTC CANDIDATE_PROBE \
//     GENERATED_SOURCES_DIR OUT_DIR [ROUNDS] [ITERATIONS]
//
// Each compiler populates its own restart cache for every public example and
// each generated source. Its probe (portable_queries_decode_probe.zig, built
// against the same tree) then decodes that checkpoint ITERATIONS times per
// round; rounds alternate the compiler order. Decoding is measured in process
// CPU nanoseconds per decode.
import { resolve } from "node:path";

const [baseline, baselineProbe, candidate, candidateProbe, generatedArg, outArg, roundsArg, iterationsArg] = Deno.args;
if (!outArg) throw new Error("usage: BASELINE BASELINE_PROBE CANDIDATE CANDIDATE_PROBE GENERATED OUT [ROUNDS] [ITERATIONS]");
const rounds = Number(roundsArg ?? "9");
const iterations = Number(iterationsArg ?? "400");
const out = resolve(outArg);
await Deno.mkdir(out, { recursive: true });
const repo = resolve(new URL("../..", import.meta.url).pathname);
const variants = [
  { name: "baseline", executable: resolve(baseline), probe: resolve(baselineProbe) },
  { name: "candidate", executable: resolve(candidate), probe: resolve(candidateProbe) },
];
const entries: { name: string; path: string }[] = [];
for (const directory of [`${repo}/examples`, resolve(generatedArg)]) {
  for (const item of [...Deno.readDirSync(directory)].sort((a, b) => a.name.localeCompare(b.name))) {
    if (item.name.endsWith(".blot")) entries.push({ name: item.name.slice(0, -5), path: `${directory}/${item.name}` });
  }
}
async function cacheFile(directory: string): Promise<{ path: string; compiler: string }> {
  const root = `${directory}/v1`;
  for await (const compiler of Deno.readDir(root)) {
    for await (const file of Deno.readDir(`${root}/${compiler.name}`)) {
      if (file.name.endsWith(".blotcache")) return { path: `${root}/${compiler.name}/${file.name}`, compiler: compiler.name };
    }
  }
  throw new Error(`no checkpoint in ${directory}`);
}
const caches: Record<string, Record<string, { path: string; compiler: string }>> = {};
for (const entry of entries) {
  caches[entry.name] = {};
  for (const variant of variants) {
    const directory = `${out}/cache/${variant.name}/${entry.name}`;
    await Deno.remove(directory, { recursive: true }).catch(() => {});
    const result = await new Deno.Command(variant.executable, {
      args: ["build-project", entry.path, `${out}/scratch.wasm`, "--prelude", `${repo}/std/prelude.blot`, "--std-root", `${repo}/std`],
      env: { BLOT_CACHE_DIR: directory },
      stdout: "null",
      stderr: "null",
    }).output();
    if (!result.success) throw new Error(`${variant.name} failed ${entry.name}`);
    caches[entry.name][variant.name] = await cacheFile(directory);
  }
}
type Probe = { checkpoint_bytes: number; median_ns: number; p25_ns: number; p75_ns: number; min_ns: number; requested_bytes: number; allocations: number; peak_bytes: number; principal_records: number; optimizer_records: number };
const samples: Record<string, Record<string, Probe[]>> = {};
const loads: number[][] = [];
for (let round = 0; round < rounds; round++) {
  loads.push((await Deno.readTextFile("/proc/loadavg")).split(" ").slice(0, 3).map(Number));
  const order = round % 2 ? [...variants].reverse() : variants;
  for (const entry of entries) {
    samples[entry.name] ??= { baseline: [], candidate: [] };
    for (const variant of order) {
      const cache = caches[entry.name][variant.name];
      const result = await new Deno.Command(variant.probe, { args: [cache.path, cache.compiler, String(iterations)], stdout: "piped", stderr: "piped" }).output();
      if (!result.success) throw new Error(`${variant.name} probe failed ${entry.name}: ${new TextDecoder().decode(result.stderr)}`);
      samples[entry.name][variant.name].push(JSON.parse(new TextDecoder().decode(result.stdout)));
    }
  }
  console.log(`round ${round + 1}/${rounds}`);
}
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
const rows = ["workload,variant,checkpoint_bytes,principal_records,optimizer_records,requested_bytes,allocations,peak_bytes,round_median_ns"];
const summary = entries.map((entry) => {
  const result: Record<string, unknown> = { workload: entry.name };
  for (const variant of variants) {
    const group = samples[entry.name][variant.name];
    const first = group[0];
    rows.push([entry.name, variant.name, first.checkpoint_bytes, first.principal_records, first.optimizer_records, first.requested_bytes, first.allocations, first.peak_bytes, `"${JSON.stringify(group.map((s) => s.median_ns).sort((a, b) => a - b))}"`].join(","));
    result[variant.name] = { checkpoint_bytes: first.checkpoint_bytes, principal_records: first.principal_records, optimizer_records: first.optimizer_records, requested_bytes: first.requested_bytes, allocations: first.allocations, peak_bytes: first.peak_bytes, median_ns: median(group.map((s) => s.median_ns)) };
  }
  const b = result.baseline as { median_ns: number };
  const c = result.candidate as { median_ns: number };
  result.ratio = c.median_ns / b.median_ns;
  return result;
});
const geomean = Math.exp(summary.reduce((sum, s) => sum + Math.log(s.ratio as number), 0) / summary.length);
await Deno.writeTextFile(`${out}/portable-queries-decode.csv`, rows.join("\n") + "\n");
await Deno.writeTextFile(`${out}/portable-queries-decode.json`, JSON.stringify({ rounds, iterations, loads, geomean_ratio: geomean, summary }, null, 2) + "\n");
console.log(JSON.stringify({ geomean_ratio: geomean }));
