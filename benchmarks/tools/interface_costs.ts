// Competing source interfaces on actual Ink math and the generated render producer.
// Fresh compiler per sample; no frontend cache. Five-second startup/build limits.
// deno run --no-config --no-lock -A benchmarks/tools/interface_costs.ts --compiler PATH
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
  type ZigProjectStats,
} from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const { values } = parseArgs({
  options: {
    compiler: { type: "string" },
    repetitions: { type: "string", default: "3" },
    output: { type: "string", default: "build/bench/interface-costs" },
    tier: { type: "string", default: "optimized" },
    workers: { type: "string", default: "1" },
  },
});
const repetitions = Number(values.repetitions);
if (!Number.isInteger(repetitions) || repetitions < 1 || repetitions > 9) {
  throw new Error("--repetitions must be from 1 to 9");
}
if (values.tier !== "optimized" && values.tier !== "development") {
  throw new Error("--tier must be optimized or development");
}
const workers = Number(values.workers);
if (!Number.isInteger(workers) || workers < 1 || workers > 16) {
  throw new Error("--workers must be from 1 to 16");
}
const repo = resolve(new URL("../..", import.meta.url).pathname);
const root = resolve(repo, "../gdev");
const executable = resolve(
  values.compiler ?? `${repo}/compiler/zig-out-native-dev/bin/blotc`,
);
const directory = resolve(values.output);
await Deno.mkdir(directory, { recursive: true });
const evidence = await Deno.makeTempDir({ dir: directory, prefix: "run-" });
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
const hashText = (source: string) => hash(new TextEncoder().encode(source));
const compilerSha256 = await hash(await Deno.readFile(executable));
const penBytes = await Deno.readFile(`${root}/pen.json`);
const settings =
  JSON.parse(new TextDecoder().decode(penBytes)).compiler.settings;
const producerPath = `${root}/pen/protocol_render.blot`;
const originalProducer = await Deno.readTextFile(producerPath);
let annotatedProducer = originalProducer;
const annotations = [];
for (const name of ["metadata_of", "matrix_of", "parameters_of", "extra_of"]) {
  const before = `let ${name} = func draw:`;
  const after = `let ${name} = func (draw: U32):`;
  if (annotatedProducer.split(before).length !== 2) {
    throw new Error(`Expected exactly one original ${name} binder`);
  }
  annotatedProducer = annotatedProducer.replace(before, after);
  annotations.push({ before, after });
}
const fields = "xx xy xz xw yx yy yz yw zx zy zz zw wx wy wz ww".split(" ");
const matrixSource = (leaf: string) => {
  const lines = [
    'import * as transform from "ink/transform"',
    'import * as math from "ink/math"',
    `const leaf = func (rows: GrowArray transform.Pose3) -> (at: U32) => return ${leaf}`,
  ];
  let previous = "leaf";
  for (let depth = 1; depth <= 6; depth++) {
    const next = `layer_${depth}`;
    lines.push(
      `const ${next} = func (rows: GrowArray transform.Pose3) -> (at: U32) => return do:`,
      `  let left = ${previous} rows at`,
      `  let right = ${previous} rows at`,
      `  return $math.Mat4 { ${
        fields.map((name) => `${name}: @f32.add left.${name} right.${name}`)
          .join(", ")
      } }`,
    );
    previous = next;
  }
  lines.push(
    "entry const answer = func (input: F32): F32 => return do:",
    "  let pose = $transform.Pose3 {position: math.zero3, rotation: math.identity_quat, scale: math.vec3 input 1.0 1.0}",
    "  let rows: GrowArray transform.Pose3 = #[pose]",
    `  let result = ${previous} rows 0`,
    "  return result.xx",
  );
  return `${lines.join("\n")}\n`;
};
const matrixBaseline = "transform.matrix rows[at]";
const matrixCandidate =
  "math.Mat4.compose (rows[at].position) (rows[at].rotation) (rows[at].scale)";
const renderEntry =
  'import * as render from "pen/protocol_render"\nentry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  return marker[0]\n';
type Probe = {
  name: string;
  entry: string;
  sources: Record<string, Record<string, string>>;
  inputs: number[];
  producerExecution: boolean;
};
const matrixEntry = `${evidence}/matrix6.blot`;
const renderPath = `${root}/.pen/bounded-interface-cost-render.blot`;
const probes: Probe[] = [{
  name: "ink_matrix6",
  entry: matrixEntry,
  sources: {
    baseline: { [matrixEntry]: matrixSource(matrixBaseline) },
    candidate: { [matrixEntry]: matrixSource(matrixCandidate) },
  },
  inputs: [0, 1, 3.5, -2, 0.125],
  producerExecution: true,
}, {
  name: "render_reader_annotations",
  entry: renderPath,
  sources: {
    baseline: { [renderPath]: renderEntry, [producerPath]: originalProducer },
    candidate: { [renderPath]: renderEntry, [producerPath]: annotatedProducer },
  },
  inputs: [0, 1, 41, 0xffffffff, 0],
  producerExecution: false,
}];
const sourcePins: Record<string, Record<string, string>> = {};
for (const probe of probes) {
  for (const variant of ["baseline", "candidate"]) {
    const files = probe.sources[variant];
    const pins: Record<string, string> = {};
    for (const [path, source] of Object.entries(files)) {
      pins[path] = await hashText(source);
      let filename = "entry.blot";
      if (path === producerPath) filename = "protocol_render.blot";
      await Deno.writeTextFile(
        `${evidence}/${probe.name}-${variant}-${filename}`,
        source,
      );
    }
    sourcePins[`${probe.name}/${variant}`] = pins;
  }
}
const sourceFiles = Object.fromEntries(
  await Promise.all([
    `${repo}/std/prelude.blot`,
    `${repo}/std/array.blot`,
    `${repo}/../ink/lib/transform.blot`,
    `${repo}/../ink/lib/math.blot`,
    producerPath,
    `${root}/pen/protocol.blot`,
    `${root}/pen/lanes.blot`,
    `${root}/pen/types.blot`,
  ].map(async (
    path,
  ) => [resolve(path), await hash(await Deno.readFile(path))])),
);
const object = (value: unknown): Record<string, unknown> => {
  if (value && typeof value === "object") {
    return value as Record<string, unknown>;
  }
  return {};
};
const numeric = (value: unknown): number | null => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
};
const metrics = (stats: ZigProjectStats) => {
  const profile = object(stats.phaseProfile);
  const checking = object(profile.checking);
  const normalization = object(checking.normalization);
  return {
    total_us: numeric(profile.total_us),
    check_us: numeric(object(object(profile.phases).check).us),
    type_nodes: numeric(checking.type_nodes),
    open_nodes_added: numeric(normalization.open_nodes_added),
    open_depth_entries: numeric(normalization.open_depth_entries),
    resolve_nodes_added: numeric(normalization.resolve_nodes_added),
    resolve_depth_entries: numeric(normalization.resolve_depth_entries),
    candidate_scans: numeric(checking.candidate_scans),
    candidates: numeric(checking.candidates),
    candidate_parts: numeric(checking.candidate_parts),
    candidate_variables: numeric(checking.candidate_variables),
    candidate_rows: numeric(checking.candidate_rows),
  };
};
type Sample = Record<string, unknown> & {
  probe: string;
  variant: string;
  status: string;
  metrics?: ReturnType<typeof metrics>;
};
const samples: Sample[] = [];
for (let repetition = 0; repetition < repetitions; repetition++) {
  let probeOrder = probes;
  let variantOrder = ["baseline", "candidate"];
  if (repetition % 2 === 1) {
    probeOrder = probes.toReversed();
    variantOrder = ["candidate", "baseline"];
  }
  for (const probe of probeOrder) {
    for (const variant of variantOrder) {
      const wallStarted = performance.now();
      let compiler;
      let guest;
      let buildStarted;
      let buildMs;
      let outcome: Record<string, unknown> & {
        status: string;
        metrics?: ReturnType<typeof metrics>;
      };
      try {
        let projectOptions: Partial<ZigProjectCompilerOptions> = {
          imports: { "ink/": resolve(repo, "../ink/lib") },
        };
        if (probe.name === "render_reader_annotations") {
          projectOptions = {
            inferenceBudget: settings.inferenceBudget,
            storage: settings.storage,
            imports: Object.fromEntries(
              Object.entries(settings.imports).map(
                ([key, path]) => [key, resolve(root, path as string)],
              ),
            ),
            nativeAssets: {
              roots: settings.nativeAssets.roots.map((path: string) =>
                resolve(root, path)
              ),
              imports: settings.nativeAssets.imports.map((
                item: Record<string, string>,
              ) => ({
                ...item,
                module: resolve(root, item.module),
                path: resolve(root, item.path),
              })),
            },
          };
        }
        compiler = await createZigProjectCompiler({
          ...projectOptions,
          executable,
          entry: probe.entry,
          prelude: `${repo}/std/prelude.blot`,
          stdRoot: `${repo}/std`,
          cacheDirectory: false,
          startupTimeoutMs: 5000,
          profileBackend: true,
          codegenTier: values.tier,
          codegenWorkers: workers,
        });
        buildStarted = performance.now();
        const result = await compiler.build({
          sources: probe.sources[variant],
          signal: AbortSignal.timeout(5000),
        });
        buildMs = performance.now() - buildStarted;
        if (!result.success) {
          outcome = { status: "failed", diagnostics: result.diagnostics };
          Deno.exitCode = 1;
        } else {
          guest = await instantiateGuest(result.bytes);
          const executed = [];
          for (const input of probe.inputs) {
            let expected = input;
            if (probe.name === "ink_matrix6") {
              expected = Math.fround(input * 64);
            }
            const actual = guest.call("answer", input);
            if (actual !== expected) {
              throw new Error(
                `${probe.name}/${variant}: ${input}: ${actual} != ${expected}`,
              );
            }
            executed.push({ input, expected, actual });
          }
          await Deno.writeFile(
            `${evidence}/${probe.name}-${variant}-${repetition}.wasm`,
            result.bytes,
          );
          outcome = {
            status: "complete",
            metrics: metrics(result.stats),
            wasm_bytes: result.bytes.length,
            wasm_sha256: await hash(result.bytes),
            executed,
            stats: result.stats,
          };
        }
      } catch (error) {
        if (buildMs === undefined && buildStarted !== undefined) {
          buildMs = performance.now() - buildStarted;
        }
        let status = "failed";
        if (/abort|timed out/i.test(String(error))) {
          status = "timeout_incomplete";
        }
        outcome = { status, error: String(error) };
        Deno.exitCode = 1;
      } finally {
        guest?.dispose();
        await compiler?.dispose();
      }
      const sample: Sample = {
        repetition,
        probe: probe.name,
        variant,
        producer_execution_qualified: probe.producerExecution &&
          outcome.status === "complete",
        build_ms: buildMs,
        wall_ms: performance.now() - wallStarted,
        ...outcome,
      };
      samples.push(sample);
      await Deno.writeTextFile(
        `${evidence}/${probe.name}-${variant}-${repetition}.json`,
        `${JSON.stringify(sample, null, 2)}\n`,
      );
      console.log(
        JSON.stringify({
          repetition,
          probe: probe.name,
          variant,
          status: sample.status,
          build_ms: buildMs,
          metrics: sample.metrics,
        }),
      );
    }
  }
}
const median = (numbers: number[]) => {
  const sorted = numbers.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
};
const summaries = [];
for (const probe of probes) {
  const medians: Record<string, Record<string, number | null>> = {};
  let complete = true;
  for (const variant of ["baseline", "candidate"]) {
    const matched = samples.filter((sample) =>
      sample.probe === probe.name && sample.variant === variant
    );
    if (matched.some((sample) => sample.status !== "complete")) {
      complete = false;
    }
    const numbers: Record<string, (number | null)[]> = {};
    for (const sample of matched) {
      const costs = {
        build_ms: numeric(sample.build_ms),
        wall_ms: numeric(sample.wall_ms),
        wasm_bytes: numeric(sample.wasm_bytes),
        ...sample.metrics,
      };
      for (const [key, value] of Object.entries(costs)) {
        (numbers[key] ??= []).push(value);
      }
    }
    medians[variant] = {};
    for (const [key, values] of Object.entries(numbers)) {
      medians[variant][key] = null;
      if (
        values.length === repetitions && values.every((value) => value !== null)
      ) {
        medians[variant][key] = median(values as number[]);
      }
    }
  }
  const before = medians.baseline.check_us;
  const after = medians.candidate.check_us;
  let improvement: number | null = null;
  let decision = "rejected_incomplete_checking_evidence";
  if (complete && before !== null && after !== null && before > 0) {
    improvement = 1 - after / before;
    decision = "rejected_missing_20_percent_checking_win";
    if (improvement >= 0.2) {
      decision = "checking_win_pending_full_qualification";
    }
  }
  summaries.push({
    probe: probe.name,
    complete,
    medians,
    checking_improvement: improvement,
    decision,
    producer_execution_qualified: probe.producerExecution && complete,
  });
}
if (await hash(await Deno.readFile(executable)) !== compilerSha256) {
  throw new Error("Compiler changed during paired measurements");
}
const report = {
  workload: "real_producer_interface_costs",
  diagnostic_only: true,
  evidence,
  compiler: executable,
  compiler_sha256: compilerSha256,
  codegen_tier: values.tier,
  codegen_workers: workers,
  deadline_ms_per_startup_and_build: 5000,
  repetitions,
  source_files: sourceFiles,
  source_overlays: sourcePins,
  pen_json_sha256: await hash(penBytes),
  candidates: {
    matrix_leaf: { before: matrixBaseline, after: matrixCandidate },
    generated_reader_inputs: annotations,
  },
  acceptance:
    "At least 20 percent lower median checking time, complete paired samples, and passing runtime witnesses; packet execution remains required before promoting generated annotations.",
  limitations: [
    "Matrix6 executes the actual original Ink math with independent expected results.",
    "Render probe checks actual original producer bodies; only a tiny identity executes. It does not qualify packet encoding or whole-game emission.",
    "Generated source overlays are experiments; a production change must edit generator inputs and pass packet witnesses.",
    "Normalization node growth includes nested operations; counters are not exclusive CPU timings.",
  ],
  summaries,
  samples,
};
await Deno.writeTextFile(
  `${evidence}/result.json`,
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(JSON.stringify({ evidence, summaries }));
