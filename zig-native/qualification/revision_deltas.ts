// Paired retained-revision metadata measurements for task 021.
//
//   deno run --allow-all zig-native/qualification/revision_deltas.ts \
//     BASELINE_PROBE CANDIDATE_PROBE OUT_DIR [REPETITIONS] [ROUNDS]
//
// Each repetition alternates the probe order; each probe run performs one
// population and ROUNDS edit/revert/rejected-edit/no-op rounds in one retained
// Session.
// Gates: both compilers emit identical Wasm per phase, and each run's retained
// live bytes plateau per phase after the first round.
import { resolve } from "node:path";

const [baseline, candidate, outArg, repetitionsArg, roundsArg] = Deno.args;
if (!outArg) throw new Error("usage: BASELINE_PROBE CANDIDATE_PROBE OUT [REPETITIONS] [ROUNDS]");
const repetitions = Number(repetitionsArg ?? "7");
const rounds = Number(roundsArg ?? "9");
const out = resolve(outArg);
await Deno.mkdir(out, { recursive: true });
const repo = resolve(new URL("../..", import.meta.url).pathname);
const workloads = [
  { name: "scalar-body", file: "scalar", search: "return 20", replace: "return 21" },
  { name: "scalar-constant", file: "scalar", search: "@u32.add 20 21", replace: "@u32.add 20 22" },
  { name: "ecs-literal", file: "ecs", search: "x: 10.0", replace: "x: 11.0" },
  { name: "tags-constant", file: "tags", search: "entry const answer: U32 = 20", replace: "entry const answer: U32 = 21" },
  { name: "monads-literal", file: "monads", search: "#Some 40", replace: "#Some 41" },
  { name: "lists-literal", file: "lists", search: "[1, 2, 3]", replace: "[1, 2, 4]" },
  { name: "requests-body", file: "requests", search: "if value == 0", replace: "if value == 1" },
  { name: "arrays-import", file: "arrays", search: 'import * as array from "std/array"', replace: 'import * as array from "std/array"\nimport * as path from "std/path"' },
];
const variants = [
  { name: "baseline", probe: resolve(baseline) },
  { name: "candidate", probe: resolve(candidate) },
];
type Row = Record<string, number | string | boolean>;
const rows: (Row & { workload: string; variant: string; repetition: number })[] = [];
const problems: string[] = [];
const loads: number[][] = [];
for (let repetition = 0; repetition < repetitions; repetition++) {
  loads.push((await Deno.readTextFile("/proc/loadavg")).split(" ").slice(0, 3).map(Number));
  const order = repetition % 2 ? [...variants].reverse() : variants;
  for (const workload of workloads) {
    for (const variant of order) {
      const result = await new Deno.Command(variant.probe, {
        args: [`${repo}/examples/${workload.file}.blot`, `${repo}/std/prelude.blot`, `${repo}/std`, workload.search, workload.replace, String(rounds)],
        stdout: "piped",
        stderr: "piped",
      }).output();
      if (!result.success) throw new Error(`${variant.name} ${workload.name}: ${new TextDecoder().decode(result.stderr)}`);
      const lines = new TextDecoder().decode(result.stdout).trim().split("\n").map((line) => JSON.parse(line) as Row);
      // Retained live bytes plateau per phase once rounds repeat.
      for (const phase of ["edit", "revert", "failed", "noop"]) {
        const live = new Set(lines.filter((row) => (row.round as number) >= 1 && row.phase === phase).map((row) => row.retained_live_bytes));
        if (live.size !== 1) problems.push(`${workload.name}/${variant.name}/${phase}: retained live bytes do not plateau ${[...live]}`);
      }
      for (const row of lines) {
        // The first round follows population; later rounds follow a revert.
        const phase = (row.round as number) === 0 && row.phase !== "population" ? `first_${row.phase}` : row.phase as string;
        rows.push({ ...row, phase, workload: workload.name, variant: variant.name, repetition });
      }
    }
  }
  console.log(`repetition ${repetition + 1}/${repetitions}`);
}
loads.push((await Deno.readTextFile("/proc/loadavg")).split(" ").slice(0, 3).map(Number));
const allPhases = ["population", "first_edit", "first_revert", "first_failed", "first_noop", "edit", "revert", "failed", "noop"];
await Deno.writeTextFile(`${out}/revision-deltas-raw.jsonl`, rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
const csv = ["workload,phase,variant,samples,cpu_ns,requested_bytes,allocations,peak_bytes,retained_live_bytes,snapshot_copy_bytes,metadata_shared_fields,metadata_shared_bytes,metadata_copied_fields,metadata_copied_bytes"];
const summary: Record<string, unknown>[] = [];
for (const workload of workloads) {
  for (const phase of allPhases) {
    const medians: Record<string, Record<string, number>> = {};
    const digests = new Set(rows.filter((row) => row.workload === workload.name && row.phase === phase).map((row) => row.wasm));
    if (digests.size !== 1) problems.push(`${workload.name}/${phase}: ${digests.size} Wasm digests`);
    for (const variant of variants) {
      const group = rows.filter((row) => row.workload === workload.name && row.phase === phase && row.variant === variant.name);
      const unique = (field: string) => {
        const values = [...new Set(group.map((row) => row[field] as number))];
        if (values.length !== 1) problems.push(`${workload.name}/${phase}/${variant.name}: ${field} varies ${values}`);
        return values[0];
      };
      const cpu = group.map((row) => row.cpu_ns as number).sort((a, b) => a - b);
      csv.push([workload.name, phase, variant.name, group.length, `"${JSON.stringify(cpu)}"`, unique("requested_bytes"), unique("allocations"), unique("peak_bytes"), unique("retained_live_bytes"), unique("snapshot_copy_bytes"), unique("metadata_shared_fields"), unique("metadata_shared_bytes"), unique("metadata_copied_fields"), unique("metadata_copied_bytes")].join(","));
      medians[variant.name] = { cpu_ns: median(cpu), requested_bytes: group[0].requested_bytes as number, peak_bytes: group[0].peak_bytes as number, retained_live_bytes: group[0].retained_live_bytes as number, metadata_shared_bytes: group[0].metadata_shared_bytes as number, metadata_copied_bytes: group[0].metadata_copied_bytes as number };
    }
    summary.push({ workload: workload.name, phase, ...medians, cpu_ratio: medians.candidate.cpu_ns / medians.baseline.cpu_ns });
  }
}
const geomean = (values: number[]) => Math.exp(values.reduce((sum, value) => sum + Math.log(value), 0) / values.length);
const ratios = Object.fromEntries(allPhases.map((phase) => [phase, geomean(summary.filter((row) => row.phase === phase).map((row) => row.cpu_ratio as number))]));
await Deno.writeTextFile(`${out}/revision-deltas.csv`, csv.join("\n") + "\n");
await Deno.writeTextFile(`${out}/revision-deltas.json`, JSON.stringify({ repetitions, rounds, loads, geomean_cpu_ratio: ratios, problems, summary }, null, 2) + "\n");
console.log(JSON.stringify({ geomean_cpu_ratio: ratios, problems }, null, 2));
if (problems.length) Deno.exit(1);
