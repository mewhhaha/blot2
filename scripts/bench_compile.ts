// Paired compile benchmark: one harness for every compiler hill.
//
//   deno task bench:compile --baseline OLD/blotc --candidate NEW/blotc
//
// Every build runs through `serve-project`, as pen runs it: gdev builds open
// the project with the snapshot's pen.json imports and native asset roots.
// Fresh builds start a new process per sample; retained phases reuse one
// session. CPU is the child's per-thread schedstat time over the build itself
// (process start and open excluded), never wall time, because wall samples on
// a shared host mostly measure contention. Variants alternate within each pair.
//
// Both binaries must emit the same Wasm for every workload and phase, a
// retained session must match a fresh build, and restoring a source must
// restore the bytes, or the run fails after writing its results. Intentional
// cross-compiler differences require --allow-wasm-diff; output stability and
// each compiler's retained/restart parity always remain gates.
// Linux only (reads /proc). Run with --allow-all: Deno gates /proc behind it,
// and the harness already executes arbitrary compilers.
//
// Workloads: the frozen gdev snapshot under build/bench/gdev-snapshot (private
// source, never committed; verified against scripts/bench/gdev-manifest.json)
// and the synthetic corpus in scripts/bench/corpus.ts.
import { parseArgs } from "node:util";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
  type ZigProjectCompiler,
} from "../compiler/zig_project_client.ts";
import { syntheticCorpus, type SyntheticProgram } from "./bench/corpus.ts";

const repo = resolve(fileURLToPath(new URL("..", import.meta.url)));
const manifestPath = `${repo}/scripts/bench/gdev-manifest.json`;
const usage = `Usage: deno task bench:compile --baseline BLOTC --candidate BLOTC
  [--runs 5] [--workload all|gdev|game|devtools|synthetic|NAME] [--no-retained]
  [--profile] [--out DIR] [--snapshot DIR] [--allow-wasm-diff]
  [--write-manifest] [--restart-cache]

  --baseline/--candidate  blotc executables. Pass one binary twice to measure noise.
  --workload              gdev entries (game, devtools), the synthetic corpus,
                          or one workload by name.
  --no-retained           skip the retained-session phases.
  --profile               open every session with profileBackend (detailed
                          clocks cost a few percent of CPU).
  --snapshot              gdev snapshot (default build/bench/gdev-snapshot).
  --allow-wasm-diff       report, but do not fail on, Wasm differing between binaries.
  --restart-cache         measure isolated cold cache population and process restarts.
  --write-manifest        rewrite scripts/bench/gdev-manifest.json from the snapshot.
Results: build/tmp/bench/<timestamp>/{results.json,samples.jsonl}.`;

const { values: args } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    runs: { type: "string", default: "5" },
    workload: { type: "string", default: "all" },
    out: { type: "string" },
    snapshot: { type: "string" },
    profile: { type: "boolean", default: false },
    "no-retained": { type: "boolean", default: false },
    "allow-wasm-diff": { type: "boolean", default: false },
    "write-manifest": { type: "boolean", default: false },
    "restart-cache": { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
});

const snapshotRoot = resolve(
  args.snapshot ?? `${repo}/build/bench/gdev-snapshot`,
);

type Hash = string;
async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<Hash> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (b) => b.toString(16).padStart(2, "0"),
  )
    .join("");
}

// ---------------------------------------------------------------- workloads

interface Replacement {
  /** Path relative to the workload root. */
  readonly file: string;
  readonly search: string;
  readonly replace: string;
}
/** A retained edit: applied to the populated session, then reverted. */
interface Scenario {
  readonly name: string;
  readonly replacements: readonly Replacement[];
}
interface Workload {
  readonly name: string;
  readonly group: "gdev" | "synthetic";
  /** Directory holding every source of the workload. */
  readonly root: string;
  readonly entry: string;
  readonly stdRoot: string | null;
  readonly prelude: string;
  /** Import alias prefix to absolute directory. */
  readonly imports: Readonly<Record<string, string>>;
  readonly nativeAssetRoots: readonly string[] | null;
  /** Retained scenarios; an empty list measures population and no-op only. */
  readonly scenarios: readonly Scenario[];
}

/** Overlay sources (absolute path to text) for a scenario's edited files. */
async function editedSources(
  workload: Workload,
  scenario: Scenario,
): Promise<Record<string, string>> {
  const sources: Record<string, string> = {};
  for (const { file, search, replace } of scenario.replacements) {
    const path = `${workload.root}/${file}`;
    const original = sources[path] ?? await Deno.readTextFile(path);
    const at = original.indexOf(search);
    if (at < 0 || original.indexOf(search, at + 1) >= 0) {
      throw new Error(
        `${workload.name} ${scenario.name}: edit anchor must occur exactly once in ${file}: ${
          JSON.stringify(search)
        }`,
      );
    }
    sources[path] = original.slice(0, at) + replace +
      original.slice(at + search.length);
  }
  return sources;
}

async function verifySnapshot(): Promise<
  { status: "missing" } | { status: "verified"; files: number }
> {
  try {
    await Deno.stat(snapshotRoot);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    return { status: "missing" };
  }
  const manifest: Record<string, Hash> = {};
  if (args["write-manifest"]) {
    for await (const path of walk(snapshotRoot)) {
      const name = relative(snapshotRoot, path);
      if (name === "manifest.json") continue;
      manifest[name] = await sha256(await Deno.readFile(path));
    }
    const sorted = Object.fromEntries(Object.entries(manifest).sort());
    await Deno.writeTextFile(
      manifestPath,
      JSON.stringify(sorted, null, 2) + "\n",
    );
    console.log(`Wrote ${manifestPath} (${Object.keys(sorted).length} files)`);
  }
  const expected: Record<string, Hash> = JSON.parse(
    await Deno.readTextFile(manifestPath),
  );
  const problems: string[] = [];
  for (const [name, hash] of Object.entries(expected)) {
    try {
      const actual = await sha256(
        await Deno.readFile(`${snapshotRoot}/${name}`),
      );
      if (actual !== hash) problems.push(`modified: ${name}`);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      problems.push(`missing: ${name}`);
    }
  }
  for await (const path of walk(snapshotRoot)) {
    const name = relative(snapshotRoot, path);
    if (name !== "manifest.json" && !(name in expected)) {
      problems.push(`unlisted: ${name}`);
    }
  }
  if (problems.length) {
    throw new Error(
      `${snapshotRoot} does not match scripts/bench/gdev-manifest.json:\n  ${
        problems.join("\n  ")
      }\nA moved snapshot invalidates comparisons across runs. Restore it or pass --write-manifest to re-freeze deliberately.`,
    );
  }
  return { status: "verified", files: Object.keys(expected).length };
}

async function* walk(directory: string): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(directory)) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory) yield* walk(path);
    else if (entry.isFile) yield path;
  }
}

function printMissingSnapshot() {
  console.log(
    `gdev snapshot not found at ${snapshotRoot}; continuing with the synthetic corpus.
To recreate it: copy the private gdev checkout's src/, devtools/, pen/, tests/,
test_support/ and pen.json into build/bench/gdev-snapshot, with the Ink
library's lib/ as ink/, then rerun. Every file is verified against the sha256
manifest in scripts/bench/gdev-manifest.json. build/ is gitignored and gdev
source must never be committed to this public repository.`,
  );
}

/**
 * pen.json paths that point outside the game checkout, and where the snapshot
 * keeps them. The Ink library is frozen inside the snapshot as `ink/`.
 */
const relocated: Readonly<Record<string, string>> = { "../ink/lib/": "ink/" };

interface PenSettings {
  readonly imports: Record<string, string>;
  readonly nativeAssetRoots: string[];
}
async function penSettings(): Promise<PenSettings> {
  const pen = JSON.parse(await Deno.readTextFile(`${snapshotRoot}/pen.json`));
  const settings = pen?.compiler?.settings;
  if (!settings?.imports || !Array.isArray(settings.nativeAssets?.roots)) {
    throw new Error(`${snapshotRoot}/pen.json has no compiler settings`);
  }
  const inside = async (path: string, label: string) => {
    const local = relocated[path] ?? path;
    const absolute = resolve(snapshotRoot, local);
    if (!absolute.startsWith(`${snapshotRoot}/`)) {
      throw new Error(`${label} ${path} leaves the snapshot; relocate it`);
    }
    if (!(await Deno.stat(absolute)).isDirectory) {
      throw new Error(`${label} ${path} is not a snapshot directory`);
    }
    return absolute;
  };
  const imports: Record<string, string> = {};
  for (const [prefix, path] of Object.entries(settings.imports)) {
    imports[prefix] = await inside(String(path), `import ${prefix}`);
  }
  const nativeAssetRoots: string[] = [];
  for (const root of settings.nativeAssets.roots) {
    nativeAssetRoots.push(await inside(String(root), "native asset root"));
  }
  return { imports, nativeAssetRoots };
}

/** Retained edits on the game entry. Anchors must stay unique in the snapshot. */
const gameScenarios: readonly Scenario[] = [
  {
    name: "literal_constant",
    replacements: [{
      file: "src/robots.blot",
      search: "const floor_half_extent = 60.0",
      replace: "const floor_half_extent = 61.0",
    }],
  },
];

async function gdevWorkloads(): Promise<Workload[]> {
  const settings = await penSettings();
  const workload = (
    name: string,
    entry: string,
    scenarios: readonly Scenario[],
  ): Workload => ({
    name,
    group: "gdev",
    root: snapshotRoot,
    entry: `${snapshotRoot}/${entry}`,
    stdRoot: `${repo}/std`,
    prelude: `${repo}/std/prelude.blot`,
    imports: settings.imports,
    nativeAssetRoots: settings.nativeAssetRoots,
    scenarios,
  });
  return [
    workload("game", "src/main.blot", gameScenarios),
    workload("devtools", "devtools/main.blot", []),
  ];
}

async function syntheticWorkload(
  program: SyntheticProgram,
  scratch: string,
): Promise<Workload> {
  const label = `${program.name}_${program.size}`;
  const root = `${scratch}/synthetic/${label}`;
  await Deno.mkdir(root, { recursive: true });
  await Deno.writeTextFile(`${root}/main.blot`, program.source);
  return {
    name: label,
    group: "synthetic",
    root,
    entry: `${root}/main.blot`,
    stdRoot: null,
    prelude: `${repo}/std/prelude.blot`,
    imports: {},
    nativeAssetRoots: null,
    scenarios: [{
      name: "edit",
      replacements: [{ file: "main.blot", ...program.edit }],
    }],
  };
}

// ------------------------------------------------------------- measurements

interface Variant {
  readonly name: "baseline" | "candidate";
  readonly executable: string;
  readonly sha256: Hash;
}
interface Sample {
  kind: "fresh" | "restart" | "retained";
  workload: string;
  variant: string;
  run: number;
  /** `fresh`, `restart`, or the retained phase name. */
  phase: string;
  cpu_ms: number;
  /** /proc tick time over the same interval; 10 ms resolution cross-check. */
  tick_cpu_ms: number;
  wall_ms: number;
  peak_rss_kib: number;
  wasm_bytes: number;
  wasm_sha256: Hash;
  stats: Record<string, unknown>;
}

interface Usage {
  cpu_ns: number;
  ticks: number;
  peak_rss_kib: number;
}
const ticksPerSecond = 100; // Linux USER_HZ.
/**
 * Per-thread schedstat of every live compiler thread, in nanoseconds, and the
 * process's tick total (which also keeps time of exited threads).
 */
async function processUsage(pid: number): Promise<Usage> {
  let cpu_ns = 0;
  for await (const task of Deno.readDir(`/proc/${pid}/task`)) {
    try {
      const text = await Deno.readTextFile(
        `/proc/${pid}/task/${task.name}/schedstat`,
      );
      cpu_ns += Number(text.split(" ")[0]);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
  const columns = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  return {
    cpu_ns,
    ticks: Number(columns[11]) + Number(columns[12]),
    peak_rss_kib: Number(status.match(/^VmHWM:\s+(\d+)/m)?.[1] ?? 0),
  };
}

interface Session {
  readonly compiler: ZigProjectCompiler;
  readonly variant: Variant;
  readonly workload: Workload;
}
async function openSession(
  variant: Variant,
  workload: Workload,
  cacheDirectory: string | false = false,
): Promise<Session> {
  const compiler = await createZigProjectCompiler({
    executable: variant.executable,
    entry: workload.entry,
    prelude: workload.prelude,
    ...(workload.stdRoot ? { stdRoot: workload.stdRoot } : {}),
    imports: workload.imports,
    ...(workload.nativeAssetRoots
      ? { nativeAssets: { roots: workload.nativeAssetRoots } }
      : {}),
    cacheDirectory,
    ...(args.profile ? { profileBackend: true } : {}),
  });
  return { compiler, variant, workload };
}

type Measured = Omit<Sample, "kind" | "workload" | "variant" | "run" | "phase">;
async function measuredBuild(
  session: Session,
  sources: Record<string, string>,
  label: string,
): Promise<Measured> {
  const pid = session.compiler.pid;
  const before = await processUsage(pid);
  const started = performance.now();
  const result: ZigProjectBuildResult = await session.compiler.build({
    sources,
  });
  const wall_ms = performance.now() - started;
  const after = await processUsage(pid);
  if (!result.success) {
    throw new Error(
      `${session.variant.name} failed ${label} of ${session.workload.name}:\n${
        JSON.stringify(result.diagnostics.slice(0, 3), null, 2)
      }`,
    );
  }
  return {
    cpu_ms: (after.cpu_ns - before.cpu_ns) / 1e6,
    tick_cpu_ms: (after.ticks - before.ticks) * 1000 / ticksPerSecond,
    wall_ms,
    peak_rss_kib: after.peak_rss_kib,
    wasm_bytes: result.bytes.length,
    wasm_sha256: await sha256(result.bytes),
    stats: result.stats as Record<string, unknown>,
  };
}

/** One fresh process, one build. */
async function freshBuild(
  variant: Variant,
  workload: Workload,
  sources: Record<string, string> = {},
  cacheDirectory: string | false = false,
  label = "fresh build",
): Promise<Measured> {
  const session = await openSession(variant, workload, cacheDirectory);
  try {
    return await measuredBuild(session, sources, label);
  } finally {
    await session.compiler.dispose();
  }
}

async function retainedSession(
  variant: Variant,
  workload: Workload,
  run: number,
): Promise<Sample[]> {
  const session = await openSession(variant, workload);
  const samples: Sample[] = [];
  const phase = async (name: string, sources: Record<string, string>) => {
    samples.push({
      kind: "retained",
      workload: workload.name,
      variant: variant.name,
      run,
      phase: name,
      ...await measuredBuild(session, sources, `retained ${name}`),
    });
  };
  try {
    await phase("population", {});
    await phase("noop", {});
    for (const scenario of workload.scenarios) {
      await phase(
        `edit:${scenario.name}`,
        await editedSources(workload, scenario),
      );
      await phase(`revert:${scenario.name}`, {});
    }
  } finally {
    await session.compiler.dispose();
  }
  return samples;
}

// ------------------------------------------------------------------ driver

const median = (values: number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = sorted.length >> 1;
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
};
interface Spread {
  median: number;
  min: number;
  max: number;
  n: number;
}
function spread(values: number[]): Spread {
  return {
    median: median(values),
    min: Math.min(...values),
    max: Math.max(...values),
    n: values.length,
  };
}
const formatSpread = (cell: Spread | null) =>
  cell && cell.n
    ? `${cell.median.toFixed(1)} [${cell.min.toFixed(0)}-${
      cell.max.toFixed(0)
    }]`
    : "-";

/** A path relative to the working directory when it lies beneath it. */
function shown(path: string): string {
  const local = relative(Deno.cwd(), path);
  return local.startsWith("..") ? path : local;
}

function loadAverage(): number {
  return Deno.loadavg()[0];
}

async function main(): Promise<number> {
  if (args.help || !args.baseline || !args.candidate) {
    console.log(usage);
    return args.help ? 0 : 2;
  }
  const runs = Number(args.runs);
  if (!Number.isSafeInteger(runs) || runs < 1) {
    throw new Error("--runs must be positive");
  }
  const timestamp = new Date().toISOString().replaceAll(":", "-").replace(
    /\..*/,
    "",
  );
  const out = resolve(args.out ?? `${repo}/build/tmp/bench/${timestamp}`);
  await Deno.mkdir(out, { recursive: true });

  const variants: Variant[] = await Promise.all(
    (["baseline", "candidate"] as const).map(async (name) => {
      const executable = resolve(args[name]!);
      return {
        name,
        executable,
        sha256: await sha256(await Deno.readFile(executable)),
      };
    }),
  );

  const snapshot = await verifySnapshot();
  if (snapshot.status === "missing") printMissingSnapshot();
  const selected = args.workload!;
  const workloads: Workload[] = [];
  if (snapshot.status === "verified") {
    for (const workload of await gdevWorkloads()) {
      if (["all", "gdev", workload.name].includes(selected)) {
        workloads.push(workload);
      }
    }
  }
  for (const program of syntheticCorpus) {
    if (
      ["all", "synthetic", program.name, `${program.name}_${program.size}`]
        .includes(selected)
    ) workloads.push(await syntheticWorkload(program, out));
  }
  if (!workloads.length) {
    throw new Error(`No workload matches --workload ${selected}`);
  }

  const samples: Sample[] = [];
  const record = async (sample: Sample) => {
    samples.push(sample);
    await Deno.writeTextFile(
      `${out}/samples.jsonl`,
      JSON.stringify(sample) + "\n",
      { append: true },
    );
  };
  const loadStart = loadAverage();
  const cpus = navigator.hardwareConcurrency;
  console.log(
    `bench:compile ${runs} alternating pairs, out ${shown(out)}\n` +
      variants.map((v) =>
        `  ${v.name.padEnd(9)} ${v.sha256.slice(0, 12)} ${v.executable}`
      ).join("\n"),
  );
  if (loadStart > cpus / 2) {
    console.log(
      `  host load ${
        loadStart.toFixed(1)
      } on ${cpus} hardware threads: CPU time is reported, but expect cache/SMT noise; more --runs help.`,
    );
  }

  for (let run = 0; run < runs; run++) {
    const order = run % 2 ? [...variants].reverse() : variants;
    for (const workload of workloads) {
      for (const variant of order) {
        const cacheDirectory = args["restart-cache"]
          ? `${out}/cache/${variant.name}/${workload.name}/${run}`
          : false;
        if (cacheDirectory) {
          await Deno.mkdir(cacheDirectory, { recursive: true });
        }
        const base = { workload: workload.name, variant: variant.name, run };
        await record({
          kind: "fresh",
          phase: "fresh",
          ...base,
          ...await freshBuild(variant, workload, {}, cacheDirectory),
        });
        if (cacheDirectory) {
          await record({
            kind: "restart",
            phase: "restart",
            ...base,
            ...await freshBuild(
              variant,
              workload,
              {},
              cacheDirectory,
              "restart build",
            ),
          });
        }
      }
      if (!args["no-retained"]) {
        for (const variant of order) {
          for (const sample of await retainedSession(variant, workload, run)) {
            await record(sample);
          }
        }
      }
    }
  }

  // Wasm parity: baseline = candidate; fresh = retained; edit phases agree
  // with a fresh build of the edited tree; restoring the source restores bytes.
  const problems: string[] = [];
  const crossCompilerProblems = new Set<string>();
  const wasm: Record<string, Record<string, Hash>> = {};
  for (const workload of workloads) {
    const digests: Record<string, Hash> = {};
    for (const sample of samples) {
      if (sample.workload !== workload.name) continue;
      const key = `${sample.phase}/${sample.variant}`;
      const known = digests[key];
      if (known && known !== sample.wasm_sha256) {
        problems.push(
          `${workload.name} ${sample.phase}: ${sample.variant} output varies between runs`,
        );
      }
      digests[key] = sample.wasm_sha256;
    }
    if (!args["no-retained"]) {
      for (const scenario of workload.scenarios) {
        const sources = await editedSources(workload, scenario);
        for (const variant of variants) {
          const built = await freshBuild(
            variant,
            workload,
            sources,
            false,
            `fresh build of ${scenario.name}`,
          );
          digests[`fresh_edit:${scenario.name}/${variant.name}`] =
            built.wasm_sha256;
        }
      }
    }
    const compare = (
      left: string,
      right: string,
      why: string,
      crossCompiler = false,
    ) => {
      if (digests[left] && digests[right] && digests[left] !== digests[right]) {
        const problem = `${workload.name}: ${why} (${left} vs ${right})`;
        problems.push(problem);
        if (crossCompiler) crossCompilerProblems.add(problem);
      }
    };
    const phases = new Set(
      Object.keys(digests).map((key) => key.slice(0, key.lastIndexOf("/"))),
    );
    for (const variant of variants.map((v) => v.name)) {
      compare(
        `fresh/${variant}`,
        `restart/${variant}`,
        "process restart changed the bytes",
      );
      compare(
        `fresh/${variant}`,
        `population/${variant}`,
        "retained population differs from fresh build",
      );
      compare(
        `fresh/${variant}`,
        `noop/${variant}`,
        "no-op rebuild changed the bytes",
      );
      for (const scenario of workload.scenarios) {
        compare(
          `edit:${scenario.name}/${variant}`,
          `fresh_edit:${scenario.name}/${variant}`,
          "retained edit differs from fresh build of edited source",
        );
        compare(
          `fresh/${variant}`,
          `revert:${scenario.name}/${variant}`,
          "restoring the source did not restore the bytes",
        );
      }
    }
    for (const phase of phases) {
      compare(
        `${phase}/baseline`,
        `${phase}/candidate`,
        "baseline and candidate emitted different Wasm",
        true,
      );
    }
    wasm[workload.name] = digests;
  }

  // Medians and spreads of child CPU per workload and phase.
  const cell = (workload: string, variant: string, phase: string) => {
    const values = samples.filter((s) =>
      s.workload === workload && s.variant === variant && s.phase === phase
    ).map((s) => s.cpu_ms);
    return values.length ? spread(values) : null;
  };
  const medians: Record<
    string,
    Record<
      string,
      {
        baseline: Spread | null;
        candidate: Spread | null;
        ratio: number | null;
      }
    >
  > = {};
  const rows: string[][] = [[
    "workload",
    "phase",
    "baseline cpu ms",
    "candidate cpu ms",
    "cand/base",
  ]];
  for (const workload of workloads) {
    medians[workload.name] = {};
    const phases = [
      ...new Set(
        samples.filter((s) => s.workload === workload.name).map((s) => s.phase),
      ),
    ];
    for (const phase of phases) {
      const baseline = cell(workload.name, "baseline", phase);
      const candidate = cell(workload.name, "candidate", phase);
      const ratio = baseline && candidate && baseline.median > 0
        ? candidate.median / baseline.median
        : null;
      medians[workload.name][phase] = { baseline, candidate, ratio };
      rows.push([
        workload.name,
        phase,
        formatSpread(baseline),
        formatSpread(candidate),
        ratio === null ? "-" : ratio.toFixed(3),
      ]);
    }
  }
  printTable(rows);

  const counterRows: string[][] = [[
    "workload",
    "regions",
    "max scopes",
    "closed",
    "unresolved",
    "passes",
    "occurs",
    "peak RSS MiB",
  ]];
  const counters: Record<string, Record<string, number> | null> = {};
  for (const workload of workloads) {
    const sample = samples.findLast((s) =>
      s.kind === "fresh" && s.workload === workload.name &&
      s.variant === "candidate"
    );
    const c = (sample?.stats.workCounters ?? null) as
      | Record<string, number>
      | null;
    counters[workload.name] = c;
    if (!c) continue;
    counterRows.push([
      workload.name,
      String(c.inference_regions),
      String(c.max_region_scopes),
      String(c.call_collections_closed),
      String(c.call_collections_unresolved),
      String(c.solver_passes),
      String(c.occurs_steps),
      (sample!.peak_rss_kib / 1024).toFixed(0),
    ]);
  }
  if (counterRows.length > 1) {
    console.log("\ncandidate fresh-build work counters (deterministic)");
    printTable(counterRows);
  }
  const phases = args.profile ? phaseTables(workloads, samples) : {};

  const loadEnd = loadAverage();
  // Intentional backend changes may differ between binaries. They must never
  // excuse nondeterministic output or a broken retained/restart comparison.
  const unexpectedProblems = args["allow-wasm-diff"]
    ? problems.filter((problem) => !crossCompilerProblems.has(problem))
    : problems;
  await Deno.writeTextFile(
    `${out}/results.json`,
    JSON.stringify(
      {
        kind: "blot-compile-bench",
        version: 2,
        timestamp,
        runs,
        profile: args.profile,
        host: {
          deno: Deno.version.deno,
          os: Deno.build.os,
          cpus,
          load_start: loadStart,
          load_end: loadEnd,
        },
        variants,
        snapshot,
        workloads: workloads.map((w) => ({
          name: w.name,
          group: w.group,
          scenarios: w.scenarios.map((s) => s.name),
        })),
        medians,
        counters,
        phases,
        wasm,
        problems,
        unexpected_problems: unexpectedProblems,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `\nwrote ${shown(out)}/results.json (load ${loadStart.toFixed(1)} -> ${
      loadEnd.toFixed(1)
    })`,
  );
  if (problems.length) {
    console.log(
      `\nWasm verification ${
        unexpectedProblems.length
          ? "FAILED"
          : "cross-compiler differences (allowed)"
      }:\n  ${problems.join("\n  ")}`,
    );
    return unexpectedProblems.length ? 1 : 0;
  }
  console.log(
    `Wasm verified identical: baseline = candidate${
      args["no-retained"] ? "" : ", fresh = retained"
    }.`,
  );
  return 0;
}

interface PhaseProfile {
  total_us?: number;
  peak_rss_kib?: number;
  phases?: Record<
    string,
    {
      us: number;
      requested_bytes?: number;
      allocations?: number;
      rss_growth_kib?: number;
    }
  >;
}
interface PhaseCell {
  ms: number;
  requested_mib: number | null;
  allocations: number | null;
  rss_growth_mib: number | null;
}
/**
 * Median exclusive phase clocks and allocation counts of each variant's fresh
 * builds (profiled sessions only), and how much of the measured CPU the named
 * phases cover.
 */
function phaseTables(workloads: Workload[], samples: Sample[]) {
  type Table = {
    phases: Record<string, PhaseCell>;
    total_ms: number;
    named_over_cpu: number;
    peak_rss_mib: number | null;
  };
  const tables: Record<string, Record<string, Table>> = {};
  const optional = (values: (number | undefined)[], scale: number) =>
    values.every((value) => value !== undefined)
      ? median(values.map((value) => value! / scale))
      : null;
  for (const workload of workloads) {
    const byVariant: Record<string, Table> = {};
    for (const variant of ["baseline", "candidate"]) {
      const profiled = samples.filter((s) =>
        s.kind === "fresh" && s.workload === workload.name &&
        s.variant === variant &&
        (s.stats.phaseProfile as PhaseProfile | undefined)?.phases
      );
      if (!profiled.length) continue;
      const profiles = profiled.map((s) =>
        s.stats.phaseProfile as PhaseProfile
      );
      const phases: Record<string, PhaseCell> = {};
      for (const name of Object.keys(profiles[0].phases!)) {
        const cells = profiles.map((p) => p.phases![name]);
        phases[name] = {
          ms: median(cells.map((cell) => cell.us / 1000)),
          requested_mib: optional(
            cells.map((cell) => cell.requested_bytes),
            1048576,
          ),
          allocations: optional(cells.map((cell) => cell.allocations), 1),
          rss_growth_mib: optional(
            cells.map((cell) => cell.rss_growth_kib),
            1024,
          ),
        };
      }
      byVariant[variant] = {
        phases,
        total_ms: median(profiles.map((p) => p.total_us! / 1000)),
        named_over_cpu: median(
          profiled.map((s) => {
            const p = s.stats.phaseProfile as PhaseProfile;
            return (p.total_us! - p.phases!.other.us) / 1000 / s.cpu_ms;
          }),
        ),
        peak_rss_mib: optional(profiles.map((p) => p.peak_rss_kib), 1024),
      };
    }
    if (!Object.keys(byVariant).length) continue;
    tables[workload.name] = byVariant;
    const shown = byVariant.candidate ?? byVariant.baseline;
    const label = byVariant.candidate ? "candidate" : "baseline";
    const fixed = (value: number | null | undefined, digits = 1) =>
      value === null || value === undefined ? "-" : value.toFixed(digits);
    const rows = [[
      workload.name,
      "phase",
      "baseline ms",
      "candidate ms",
      `${label} req MiB`,
      `${label} allocs`,
      `${label} RSS+ MiB`,
    ]];
    for (const [name, cell] of Object.entries(shown.phases)) {
      rows.push([
        "",
        name,
        fixed(byVariant.baseline?.phases[name]?.ms),
        fixed(byVariant.candidate?.phases[name]?.ms),
        fixed(cell.requested_mib),
        fixed(cell.allocations, 0),
        fixed(cell.rss_growth_mib),
      ]);
    }
    const sum = (field: "requested_mib" | "allocations") =>
      Object.values(shown.phases).every((cell) => cell[field] !== null)
        ? Object.values(shown.phases).reduce(
          (total, cell) => total + cell[field]!,
          0,
        )
        : null;
    rows.push([
      "",
      "total",
      fixed(byVariant.baseline?.total_ms),
      fixed(byVariant.candidate?.total_ms),
      fixed(sum("requested_mib")),
      fixed(sum("allocations"), 0),
      fixed(shown.peak_rss_mib),
    ]);
    rows.push([
      "",
      "named/cpu",
      fixed(byVariant.baseline?.named_over_cpu, 3),
      fixed(byVariant.candidate?.named_over_cpu, 3),
      "",
      "",
      "",
    ]);
    console.log(
      "\nfresh-build phase profile (median, exclusive; RSS+ is peak RSS growth)",
    );
    printTable(rows);
  }
  return tables;
}

function printTable(rows: string[][]) {
  const widths = rows[0].map((_, column) =>
    Math.max(...rows.map((row) => row[column].length))
  );
  for (const row of rows) {
    console.log(
      row.map((text, column) =>
        column < 2 ? text.padEnd(widths[column]) : text.padStart(widths[column])
      ).join("  "),
    );
  }
}

Deno.exit(await main());
