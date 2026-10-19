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
// restore the bytes, or the run fails after writing its results. Fresh gdev
// outputs (and expected rejections) must also match the per-entry hashes
// recorded in scripts/bench/gdev-wasm.json, so a hill cannot drift from the
// recorded baseline even when both of its binaries agree. Intentional output
// changes require --allow-wasm-diff (then --write-hashes re-records them);
// output stability, retained/restart parity and successful builds always
// remain gates.
// Linux only (reads /proc). Run with --allow-all: Deno gates /proc behind it,
// and the harness already executes arbitrary compilers.
//
// Workloads: the frozen gdev snapshot under build/bench/gdev-snapshot (private
// source, never committed; verified against scripts/bench/gdev-manifest.json)
// and the synthetic corpus in scripts/bench/corpus.ts. Retained sessions run
// the edit suite (scripts/bench/gdev.ts on the game, `edit_suite` in the
// corpus): population, no-op, then each scenario's edit and revert, reported
// with reuse and recheck counters. --shared-session also builds every selected
// test entry in turn in one session, as pen's test workers do (CT90).
import { parseArgs } from "node:util";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
  type ZigProjectCompiler,
} from "../compiler/zig_project_client.ts";
import {
  editSuite,
  syntheticCorpus,
  type SyntheticProgram,
  type SyntheticProject,
} from "./bench/corpus.ts";
import {
  editedSources,
  gdevWorkloads,
  sessionOptions,
  testWorkloads,
  type Workload,
} from "./bench/gdev.ts";
import {
  pairedCpuGuard,
  unexpectedBuildFailures,
} from "./bench/verification.ts";

const repo = resolve(fileURLToPath(new URL("..", import.meta.url)));
const manifestPath = `${repo}/scripts/bench/gdev-manifest.json`;
const hashesPath = `${repo}/scripts/bench/gdev-wasm.json`;
const usage = `Usage: deno task bench:compile --baseline BLOTC --candidate BLOTC
  [--runs 5] [--workload all|gdev|game|devtools|tests|synthetic|NAME,...]
  [--test-runs 1] [--no-retained] [--profile] [--out DIR] [--snapshot DIR]
  [--allow-wasm-diff] [--write-hashes] [--write-manifest] [--restart-cache]
  [--shared-session] [--guard-cpu] [--codegen-workers 4]

  --baseline/--candidate  blotc executables. Pass one binary twice to measure noise.
  --workload              comma-separated: gdev entries (game, devtools), every
                          gdev test entry (tests, about 170 s CPU per binary and
                          run), the synthetic corpus (with the edit_suite
                          project), or workloads by name (tests/NAME.blot).
                          all = gdev and synthetic.
  --test-runs             alternating pairs for test entries (default 1).
  --no-retained           skip the retained-session phases.
  --profile               open every session with profileBackend (detailed
                          clocks cost a few percent of CPU).
  --snapshot              gdev snapshot (default build/bench/gdev-snapshot).
  --allow-wasm-diff       report, but do not fail on, Wasm differing between
                          binaries or from scripts/bench/gdev-wasm.json.
  --write-hashes          record the candidate's fresh gdev Wasm hashes (and
                          expected rejections) for the measured entries in
                          scripts/bench/gdev-wasm.json.
  --restart-cache         measure isolated cold cache population and process restarts.
  --shared-session        also build the selected test entries in turn in one
                          session per variant and run, overlaying each at
                          src/test_fixture.blot as pen's test workers do; each
                          must equal its fresh build.
  --write-manifest        rewrite scripts/bench/gdev-manifest.json from the snapshot.
  --guard-cpu             require at least three paired fresh game builds; fail
                          if the median candidate/baseline CPU ratio exceeds 1.05.
                          Output-difference declarations never waive this guard.
  --codegen-workers       pin both compilers to 1..16 codegen workers (default 4).
Results: build/tmp/bench/<timestamp>/{results.json,samples.jsonl}.`;

const { values: args } = parseArgs({
  options: {
    baseline: { type: "string" },
    candidate: { type: "string" },
    runs: { type: "string", default: "5" },
    "test-runs": { type: "string", default: "1" },
    workload: { type: "string", default: "all" },
    out: { type: "string" },
    snapshot: { type: "string" },
    profile: { type: "boolean", default: false },
    "no-retained": { type: "boolean", default: false },
    "allow-wasm-diff": { type: "boolean", default: false },
    "write-manifest": { type: "boolean", default: false },
    "write-hashes": { type: "boolean", default: false },
    "restart-cache": { type: "boolean", default: false },
    "shared-session": { type: "boolean", default: false },
    "guard-cpu": { type: "boolean", default: false },
    "codegen-workers": { type: "string", default: "4" },
    help: { type: "boolean", default: false },
  },
});

const snapshotRoot = resolve(
  args.snapshot ?? `${repo}/build/bench/gdev-snapshot`,
);
const codegenWorkers = Number(args["codegen-workers"]);

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
    overlay: {},
    retained: true,
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

/** A multi-module synthetic project with its retained scenarios. */
async function projectWorkload(
  project: SyntheticProject,
  scratch: string,
): Promise<Workload> {
  const root = `${scratch}/synthetic/${project.name}`;
  await Deno.mkdir(root, { recursive: true });
  for (const [file, source] of Object.entries(project.files)) {
    await Deno.writeTextFile(`${root}/${file}`, source);
  }
  return {
    name: project.name,
    group: "synthetic",
    root,
    entry: `${root}/${project.entry}`,
    overlay: {},
    retained: true,
    stdRoot: `${repo}/std`,
    prelude: `${repo}/std/prelude.blot`,
    imports: {},
    nativeAssetRoots: null,
    scenarios: project.scenarios,
  };
}

// ------------------------------------------------------------- measurements

interface Variant {
  readonly name: "baseline" | "candidate";
  readonly executable: string;
  readonly sha256: Hash;
}
interface Sample {
  kind: "fresh" | "restart" | "retained" | "shared";
  workload: string;
  variant: string;
  run: number;
  /** `fresh`, `restart`, `shared`, or the retained phase name. */
  phase: string;
  cpu_ms: number;
  /** /proc tick time over the same interval; 10 ms resolution cross-check. */
  tick_cpu_ms: number;
  wall_ms: number;
  peak_rss_kib: number;
  wasm_bytes: number;
  /** A failed build records `failure:CODE` here and its diagnostic below. */
  wasm_sha256: Hash;
  failure?: Failure;
  stats: Record<string, unknown>;
}
/** A rejected build's first diagnostic, with its file relative to the root. */
interface Failure {
  code: string;
  stage: string;
  file: string;
  start: number;
  end: number;
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
    ...sessionOptions(variant.executable, workload),
    codegenWorkers,
    cacheDirectory,
    ...(args.profile ? { profileBackend: true } : {}),
  });
  return { compiler, variant, workload };
}

type Measured = Omit<Sample, "kind" | "workload" | "variant" | "run" | "phase">;
async function measuredBuild(
  session: Session,
  sources: Record<string, string>,
): Promise<Measured> {
  const pid = session.compiler.pid;
  const before = await processUsage(pid);
  const started = performance.now();
  const result: ZigProjectBuildResult = await session.compiler.build({
    sources: { ...session.workload.overlay, ...sources },
  });
  const wall_ms = performance.now() - started;
  const after = await processUsage(pid);
  const usage = {
    cpu_ms: (after.cpu_ns - before.cpu_ns) / 1e6,
    tick_cpu_ms: (after.ticks - before.ticks) * 1000 / ticksPerSecond,
    wall_ms,
    peak_rss_kib: after.peak_rss_kib,
  };
  if (!result.success) {
    const [first] = result.diagnostics;
    const failure: Failure = {
      code: first?.code ?? "unknown",
      stage: first?.stage ?? "",
      file: first ? relative(session.workload.root, first.filename) : "",
      start: first?.start ?? 0,
      end: first?.end ?? 0,
    };
    return {
      ...usage,
      wasm_bytes: 0,
      wasm_sha256: `failure:${failure.code}`,
      failure,
      stats: (result.attemptStats ?? {}) as Record<string, unknown>,
    };
  }
  return {
    ...usage,
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
): Promise<Measured> {
  const session = await openSession(variant, workload, cacheDirectory);
  try {
    return await measuredBuild(session, sources);
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
      ...await measuredBuild(session, sources),
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

/**
 * One session builds every test entry in turn, each overlaid at the shared
 * fixture entry, as each of pen's test workers does.
 */
async function sharedSession(
  variant: Variant,
  workloads: Workload[],
  run: number,
): Promise<Sample[]> {
  const session = await openSession(variant, workloads[0]);
  const samples: Sample[] = [];
  try {
    for (const workload of workloads) {
      samples.push({
        kind: "shared",
        workload: workload.name,
        variant: variant.name,
        run,
        phase: "shared",
        ...await measuredBuild({ ...session, workload }, {}),
      });
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
  const testRuns = Number(args["test-runs"]);
  if (
    !Number.isSafeInteger(runs) || runs < 1 ||
    !Number.isSafeInteger(testRuns) || testRuns < 1
  ) {
    throw new Error("--runs and --test-runs must be positive");
  }
  const timestamp = new Date().toISOString().replaceAll(":", "-").replace(
    /\..*/,
    "",
  );
  const out = resolve(args.out ?? `${repo}/build/tmp/bench/${timestamp}`);
  if (
    !Number.isInteger(codegenWorkers) || codegenWorkers < 1 ||
    codegenWorkers > 16
  ) {
    throw new Error("--codegen-workers must be an integer in 1..16");
  }
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
  const selected = args.workload!.split(",");
  const chosen = (...names: string[]) =>
    names.some((name) => selected.includes(name));
  const workloads: Workload[] = [];
  if (snapshot.status === "verified") {
    for (const workload of await gdevWorkloads(repo, snapshotRoot)) {
      if (chosen("all", "gdev", workload.name)) workloads.push(workload);
    }
    for (const workload of await testWorkloads(repo, snapshotRoot)) {
      if (chosen("tests", workload.name)) workloads.push(workload);
    }
  }
  for (const program of syntheticCorpus) {
    if (
      chosen(
        "all",
        "synthetic",
        program.name,
        `${program.name}_${program.size}`,
      )
    ) workloads.push(await syntheticWorkload(program, out));
  }
  if (chosen("all", "synthetic", editSuite.name)) {
    workloads.push(await projectWorkload(editSuite, out));
  }
  if (!workloads.length) {
    throw new Error(`No workload matches --workload ${args.workload}`);
  }
  if (
    args["guard-cpu"] && (runs < 3 || !workloads.some((w) => w.name === "game"))
  ) {
    throw new Error("--guard-cpu requires --runs >= 3 and the game workload");
  }
  const runsOf = (workload: Workload) =>
    workload.group === "tests" ? testRuns : runs;

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
    `bench:compile ${runs} alternating pairs${
      workloads.some((w) => w.group === "tests")
        ? ` (${testRuns} for test entries)`
        : ""
    }, out ${shown(out)}\n` +
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

  for (let run = 0; run < Math.max(...workloads.map(runsOf)); run++) {
    const order = run % 2 ? [...variants].reverse() : variants;
    for (const workload of workloads) {
      if (run >= runsOf(workload)) continue;
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
            ...await freshBuild(variant, workload, {}, cacheDirectory),
          });
        }
      }
      if (!args["no-retained"] && workload.retained) {
        for (const variant of order) {
          for (const sample of await retainedSession(variant, workload, run)) {
            await record(sample);
          }
        }
      }
    }
    const shared = workloads.filter((w) => w.group === "tests");
    if (args["shared-session"] && shared.length && run < testRuns) {
      for (const variant of order) {
        for (const sample of await sharedSession(variant, shared, run)) {
          await record(sample);
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
    if (!args["no-retained"] && workload.retained) {
      for (const scenario of workload.scenarios) {
        const sources = await editedSources(workload, scenario);
        for (const variant of variants) {
          const built = await freshBuild(variant, workload, sources);
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
      compare(
        `fresh/${variant}`,
        `shared/${variant}`,
        "shared test session differs from fresh build",
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

  // Recorded fresh outputs per gdev entry, and per edited entry.
  const manifestHash = await sha256(await Deno.readFile(manifestPath));
  const recorded = snapshot.status === "verified"
    ? await recordedHashes()
    : null;
  const expectedRejections = new Set<string>();
  const measuredHashes: Record<string, Hash> = {};
  const unrecorded = new Set<string>();
  const recordProblems = new Set<string>();
  if (recorded && recorded.manifest !== manifestHash) {
    problems.push(
      "scripts/bench/gdev-wasm.json was recorded for another snapshot manifest; re-record it with --write-hashes",
    );
  }
  for (const workload of workloads) {
    if (workload.group === "synthetic") continue;
    const keys: [string, string][] = [
      [workload.name, "fresh"],
      ...workload.scenarios.map((scenario): [string, string] => [
        `${workload.name} @ ${scenario.name}`,
        `fresh_edit:${scenario.name}`,
      ]),
    ];
    for (const [entry, phase] of keys) {
      const expected = recorded?.entries[entry];
      for (const variant of variants) {
        const actual = wasm[workload.name][`${phase}/${variant.name}`];
        if (!actual) continue;
        if (variant.name === "candidate") measuredHashes[entry] = actual;
        if (expected === undefined) {
          unrecorded.add(entry);
        } else if (actual !== expected) {
          const problem = `${entry}: ${variant.name} emitted ${
            outcome(actual)
          }, recorded ${outcome(expected)}`;
          problems.push(problem);
          crossCompilerProblems.add(problem);
          recordProblems.add(problem);
        } else if (actual.startsWith("failure:")) {
          expectedRejections.add(workload.name);
        }
      }
    }
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
    if (workload.group === "tests") {
      for (const variant of ["baseline", "candidate"] as const) {
        (medians[workload.name].fresh ??= {
          baseline: null,
          candidate: null,
          ratio: null,
        })[variant] = cell(workload.name, variant, "fresh");
      }
      const { baseline, candidate } = medians[workload.name].fresh;
      medians[workload.name].fresh.ratio =
        baseline && candidate && baseline.median > 0
          ? candidate.median / baseline.median
          : null;
      continue;
    }
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
    // Test entries are summarized in the test-suite table.
    if (!c || workload.group === "tests") continue;
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
  const tests = testTable(workloads, samples, medians);
  const shared = sharedTable(workloads, samples, variants);
  const failures = failureTable(samples);
  // A rejection never passes as an output change. Only rejections recorded
  // in gdev-wasm.json, or of unrecorded test entries, are expected.
  problems.push(
    ...unexpectedBuildFailures(
      failures,
      workloads,
      expectedRejections,
      unrecorded,
    ),
  );
  const reuse = reuseTables(workloads, samples, medians);
  const phases = args.profile ? phaseTables(workloads, samples) : {};
  const cpuGuard = args["guard-cpu"] ? pairedCpuGuard(samples) : null;
  if (cpuGuard) {
    problems.push(...cpuGuard.problems);
    console.log(
      `\nCPU guard: game paired median ${
        cpuGuard.median_ratio?.toFixed(3) ?? "unavailable"
      }; limit 1.050; ${cpuGuard.problems.length ? "FAILED" : "passed"}`,
    );
  }

  const loadEnd = loadAverage();
  // Intentional backend changes may differ between binaries. They must never
  // excuse nondeterministic output or a broken retained/restart comparison.
  const unexpectedProblems = args["allow-wasm-diff"]
    ? problems.filter((problem) => !crossCompilerProblems.has(problem))
    : problems;
  if (unrecorded.size && !args["write-hashes"]) {
    console.log(
      `\nno recorded hash for ${
        [...unrecorded].join(", ")
      }; --write-hashes records them.`,
    );
  }
  if (args["write-hashes"]) {
    // Never record an output that failed its own run's parity checks.
    const blocking = unexpectedProblems.filter((problem) =>
      !recordProblems.has(problem)
    );
    if (blocking.length) {
      console.log(
        `\nnot writing ${shown(hashesPath)}: the run has other problems.`,
      );
    } else {
      const entries = {
        ...(recorded?.manifest === manifestHash ? recorded.entries : {}),
        ...measuredHashes,
      };
      await Deno.writeTextFile(
        hashesPath,
        JSON.stringify(
          {
            manifest: manifestHash,
            recorded_by: variants[1].sha256,
            entries: Object.fromEntries(Object.entries(entries).sort()),
          },
          null,
          2,
        ) + "\n",
      );
      console.log(
        `\nwrote ${shown(hashesPath)} (${
          Object.keys(measuredHashes).length
        } measured entries)`,
      );
    }
  }
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
          codegen_workers: codegenWorkers,
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
        tests,
        shared,
        failures,
        reuse,
        phases,
        cpu_guard: cpuGuard,
        wasm,
        recorded_hashes: recorded
          ? { manifest_matches: recorded.manifest === manifestHash }
          : null,
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
      `\nBenchmark verification ${
        unexpectedProblems.length
          ? "FAILED"
          : "declared output differences (allowed by --allow-wasm-diff)"
      }:\n  ${problems.join("\n  ")}`,
    );
    return unexpectedProblems.length ? 1 : 0;
  }
  console.log(
    `Wasm verified identical: baseline = candidate${
      samples.some((s) => s.kind === "retained") ? ", fresh = retained" : ""
    }${recorded ? ", gdev = recorded hashes" : ""}.`,
  );
  return 0;
}

/** Recorded per-entry outputs: sha256 of the Wasm, or `failure:CODE`. */
interface RecordedHashes {
  /** sha256 of scripts/bench/gdev-manifest.json when recorded. */
  manifest: Hash;
  recorded_by: Hash;
  entries: Record<string, string>;
}
async function recordedHashes(): Promise<RecordedHashes | null> {
  try {
    return JSON.parse(await Deno.readTextFile(hashesPath));
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return null;
    throw error;
  }
}
const outcome = (digest: string) =>
  digest.startsWith("failure:") ? digest : `Wasm ${digest.slice(0, 12)}`;

/**
 * The test suite: per-entry median CPU, the suite total (sum of medians, for
 * entries both variants built) and the ten slowest entries.
 */
function testTable(
  workloads: Workload[],
  samples: Sample[],
  medians: Record<
    string,
    Record<string, { baseline: Spread | null; candidate: Spread | null }>
  >,
) {
  const entries = workloads.filter((w) => w.group === "tests");
  if (!entries.length) return null;
  const rss = (name: string) =>
    Math.max(
      0,
      ...samples.filter((s) => s.workload === name && s.variant === "candidate")
        .map((s) => s.peak_rss_kib),
    );
  const rows = entries.map((workload) => {
    const cell = medians[workload.name].fresh;
    const failed = samples.find((s) =>
      s.workload === workload.name && s.failure
    );
    return {
      name: workload.name,
      baseline_ms: cell.baseline?.median ?? null,
      candidate_ms: cell.candidate?.median ?? null,
      peak_rss_kib: rss(workload.name),
      outcome: failed ? failed.wasm_sha256 : "built",
    };
  });
  const total = (field: "baseline_ms" | "candidate_ms") =>
    rows.reduce((sum, row) => sum + (row[field] ?? 0), 0);
  const result = {
    entries: rows.length,
    failed: rows.filter((row) => row.outcome !== "built").length,
    total_baseline_ms: total("baseline_ms"),
    total_candidate_ms: total("candidate_ms"),
    per_entry: rows,
  };
  const slowest = [...rows].sort((a, b) =>
    (b.candidate_ms ?? b.baseline_ms ?? 0) -
    (a.candidate_ms ?? a.baseline_ms ?? 0)
  ).slice(0, 10);
  const fixed = (value: number | null) =>
    value === null ? "-" : value.toFixed(1);
  const ratio = (base: number | null, cand: number | null) =>
    base && cand ? (cand / base).toFixed(3) : "-";
  console.log(
    `\ntest suite: ${result.entries} entries (${result.failed} failed), ` +
      `total CPU ${fixed(result.total_baseline_ms)} / ${
        fixed(result.total_candidate_ms)
      } ms (baseline / candidate, ${
        ratio(result.total_baseline_ms, result.total_candidate_ms)
      })`,
  );
  printTable([
    ["slowest entries", "baseline ms", "candidate ms", "cand/base", "RSS MiB"],
    ...slowest.map((row) => [
      row.name,
      fixed(row.baseline_ms),
      fixed(row.candidate_ms),
      ratio(row.baseline_ms, row.candidate_ms),
      (row.peak_rss_kib / 1024).toFixed(0),
    ]),
  ]);
  return result;
}

/**
 * The shared test session against fresh builds: suite CPU (sum of per-entry
 * medians), the session's wall time and peak RSS per variant.
 */
function sharedTable(
  workloads: Workload[],
  samples: Sample[],
  variants: Variant[],
) {
  const entries = workloads.filter((w) => w.group === "tests");
  const shared = samples.filter((s) => s.kind === "shared");
  if (!entries.length || !shared.length) return null;
  const total = (variant: string, phase: string, field: "cpu_ms" | "wall_ms") =>
    entries.reduce((sum, workload) => {
      const values = samples.filter((s) =>
        s.workload === workload.name && s.variant === variant &&
        s.phase === phase
      ).map((s) => s[field]);
      return sum + (values.length ? median(values) : 0);
    }, 0);
  const result = Object.fromEntries(variants.map((variant) => [variant.name, {
    fresh_cpu_ms: total(variant.name, "fresh", "cpu_ms"),
    shared_cpu_ms: total(variant.name, "shared", "cpu_ms"),
    shared_wall_ms: total(variant.name, "shared", "wall_ms"),
    peak_rss_kib: Math.max(
      0,
      ...shared.filter((s) => s.variant === variant.name).map((s) =>
        s.peak_rss_kib
      ),
    ),
  }]));
  console.log(`
shared test session over ${entries.length} entries`);
  printTable([
    ["variant", "fresh cpu ms", "shared cpu ms", "shared wall ms", "RSS MiB"],
    ...variants.map((variant) => {
      const row = result[variant.name];
      return [
        variant.name,
        row.fresh_cpu_ms.toFixed(0),
        row.shared_cpu_ms.toFixed(0),
        row.shared_wall_ms.toFixed(0),
        (row.peak_rss_kib / 1024).toFixed(0),
      ];
    }),
  ]);
  return result;
}

/** One line per distinct rejected build (workload, phase, variant, code). */
function failureTable(samples: Sample[]) {
  const seen = new Map<
    string,
    { workload: string; phase: string; variant: string } & Failure
  >();
  for (const sample of samples) {
    if (!sample.failure) continue;
    const key = `${sample.workload}/${sample.phase}/${sample.variant}`;
    seen.set(key, {
      workload: sample.workload,
      phase: sample.phase,
      variant: sample.variant,
      ...sample.failure,
    });
  }
  const failures = [...seen.values()];
  if (failures.length) {
    console.log("\nrejected builds (first diagnostic)");
    printTable([
      ["workload", "phase", "variant", "code", "at"],
      ...failures.map((f) => [
        f.workload,
        f.phase,
        f.variant,
        f.code,
        `${f.file}:${f.start}-${f.end}`,
      ]),
    ]);
  }
  return failures;
}

/** What a retained revision reused and redid; deterministic per phase. */
interface Reuse {
  reused_named: number;
  fresh_named: number;
  reused_closures: number;
  fresh_closures: number;
  rebuilt_seed: boolean;
  reused_output: boolean;
  trivia_only: boolean;
  validated_modules: number;
  recheck_body_elaborations: number;
  reused_check_body_elaborations: number;
}
function reuseOf(stats: Record<string, unknown>): Reuse {
  const backend = (stats.backend ?? {}) as Record<string, number>;
  const attempt = (stats.attemptStats ?? {}) as Record<string, unknown>;
  const fallback = (attempt.fallback ?? {}) as Record<string, number>;
  return {
    reused_named: backend.reused_named,
    fresh_named: backend.fresh_named,
    reused_closures: backend.reused_closures,
    fresh_closures: backend.fresh_closures,
    rebuilt_seed: Boolean(attempt.rebuilt_seed),
    reused_output: Boolean(attempt.reused_output),
    trivia_only: Boolean(attempt.trivia_only),
    validated_modules: fallback.validated_modules,
    recheck_body_elaborations: fallback.recheck_body_elaborations,
    reused_check_body_elaborations: fallback.reused_check_body_elaborations,
  };
}
/**
 * The retained edit suite: CPU with reuse and recheck counters per phase. A
 * `*` marks a counter in which the baseline differed from the candidate.
 */
function reuseTables(
  workloads: Workload[],
  samples: Sample[],
  medians: Record<string, Record<string, { candidate: Spread | null }>>,
) {
  const tables: Record<string, Record<string, Record<string, Reuse>>> = {};
  const rows = [[
    "workload",
    "phase",
    "cand cpu ms",
    "reused/fresh named",
    "fresh closures",
    "seed",
    "output",
    "validated",
    "recheck",
  ]];
  for (const workload of workloads) {
    const phases = [
      ...new Set(
        samples.filter((s) =>
          s.kind === "retained" && s.workload === workload.name
        )
          .map((s) => s.phase),
      ),
    ];
    if (!phases.length) continue;
    tables[workload.name] = {};
    for (const phase of phases) {
      const byVariant: Record<string, Reuse> = {};
      for (const variant of ["baseline", "candidate"]) {
        const sample = samples.findLast((s) =>
          s.kind === "retained" && s.workload === workload.name &&
          s.variant === variant && s.phase === phase
        );
        if (sample) byVariant[variant] = reuseOf(sample.stats);
      }
      tables[workload.name][phase] = byVariant;
      const cand = byVariant.candidate, base = byVariant.baseline;
      const mark = (...fields: (keyof Reuse)[]) =>
        base && fields.some((field) => base[field] !== cand[field]) ? "*" : "";
      rows.push([
        workload.name,
        phase,
        medians[workload.name]?.[phase]?.candidate?.median.toFixed(1) ?? "-",
        `${cand.reused_named}/${cand.fresh_named}${
          mark("reused_named", "fresh_named")
        }`,
        `${cand.fresh_closures}${mark("fresh_closures")}`,
        `${cand.rebuilt_seed ? "rebuilt" : "kept"}${mark("rebuilt_seed")}`,
        `${
          cand.reused_output ? (cand.trivia_only ? "trivia" : "reused") : "new"
        }${mark("reused_output", "trivia_only")}`,
        `${cand.validated_modules}${mark("validated_modules")}`,
        `${cand.recheck_body_elaborations}${mark("recheck_body_elaborations")}`,
      ]);
    }
  }
  if (rows.length > 1) {
    console.log("\nretained edit suite (candidate counters, deterministic)");
    printTable(rows);
  }
  return tables;
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
