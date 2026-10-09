// Paired compile benchmark: one harness for every compiler hill.
//
//   deno task bench:compile --baseline OLD/blotc --candidate NEW/blotc
//
// Alternating fresh-process pairs and retained-session phases are measured in
// child CPU time (user + system), never wall time, because wall samples on a
// shared host mostly measure contention. Both binaries must emit the same Wasm
// for every workload and phase, and a retained session must match a fresh
// build, or the run fails after writing its results. Linux only (uses bash
// Intentional cross-compiler differences require --allow-wasm-diff; output
// stability and each compiler's retained/restart parity always remain gates.
// `times` and /proc). Run with --allow-all: Deno gates /proc behind it, and the
// harness already executes arbitrary compilers.
//
// Workloads: the frozen gdev snapshot under build/bench/gdev-snapshot (private
// source, never committed; verified against scripts/bench/gdev-manifest.json)
// and the synthetic corpus in scripts/bench/corpus.ts.
import { cpSync } from "node:fs";
import { parseArgs } from "node:util";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { syntheticCorpus, type SyntheticProgram } from "./bench/corpus.ts";

const repo = resolve(fileURLToPath(new URL("..", import.meta.url)));
const snapshotRoot = `${repo}/build/bench/gdev-snapshot`;
const manifestPath = `${repo}/scripts/bench/gdev-manifest.json`;
const usage = `Usage: deno task bench:compile --baseline BLOTC --candidate BLOTC
  [--runs 5] [--workload all|gdev|synthetic|NAME] [--no-retained]
  [--out DIR] [--allow-wasm-diff] [--write-manifest] [--restart-cache]

  --baseline/--candidate  blotc executables. Pass one binary twice to measure noise.
  --workload              gdev snapshot, synthetic corpus, or one program by name.
  --no-retained           skip the retained-session phases.
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
    "no-retained": { type: "boolean", default: false },
    "allow-wasm-diff": { type: "boolean", default: false },
    "write-manifest": { type: "boolean", default: false },
    "restart-cache": { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
});

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

interface Edit {
  readonly search: string;
  readonly replace: string;
}
interface Workload {
  readonly name: string;
  readonly group: "gdev" | "synthetic";
  /** Directory holding every source; copied once to build the edited tree. */
  readonly root: string;
  readonly entry: string;
  /** File the retained phases overlay, and the edit applied to it. */
  readonly editFile: string;
  readonly edit: Edit;
  readonly stdRoot: string | null;
  readonly prelude: string;
  /** Import alias prefix to directory, relative to `root`. */
  readonly aliases: Readonly<Record<string, string>>;
  readonly command: "build" | "build-project";
}

function applyEdit(source: string, edit: Edit, label: string): string {
  const at = source.indexOf(edit.search);
  if (at < 0 || source.indexOf(edit.search, at + 1) >= 0) {
    throw new Error(`${label}: edit anchor must occur exactly once`);
  }
  return source.slice(0, at) + edit.replace +
    source.slice(at + edit.search.length);
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
To recreate it: copy the frozen iteration copy of the private gdev checkout
(its src/ and packages/ trees, including src/main.blot and src/robots.blot)
into build/bench/gdev-snapshot, then rerun. Every file is verified against the
sha256 manifest in scripts/bench/gdev-manifest.json. build/ is gitignored and
gdev source must never be committed to this public repository.`,
  );
}

function gdevWorkload(): Workload {
  return {
    name: "gdev",
    group: "gdev",
    root: snapshotRoot,
    entry: `${snapshotRoot}/src/main.blot`,
    editFile: `${snapshotRoot}/src/robots.blot`,
    edit: {
      search: "const floor_half_extent = 60.0",
      replace: "const floor_half_extent = 61.0",
    },
    stdRoot: `${repo}/std`,
    prelude: `${repo}/std/prelude.blot`,
    aliases: { "gdev/": "packages" },
    command: "build-project",
  };
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
    editFile: `${root}/main.blot`,
    edit: program.edit,
    stdRoot: null,
    prelude: `${repo}/std/prelude.blot`,
    aliases: {},
    command: "build",
  };
}

/** A copy of the workload with its edit applied, for fresh-vs-retained parity. */
async function editedCopy(
  workload: Workload,
  scratch: string,
): Promise<Workload> {
  const root = `${scratch}/edited/${workload.name}`;
  cpSync(workload.root, root, { recursive: true });
  const editFile = `${root}/${relative(workload.root, workload.editFile)}`;
  await Deno.writeTextFile(
    editFile,
    applyEdit(
      await Deno.readTextFile(editFile),
      workload.edit,
      workload.name,
    ),
  );
  return {
    ...workload,
    root,
    entry: `${root}/${relative(workload.root, workload.entry)}`,
    editFile,
  };
}

function aliasMap(workload: Workload): Record<string, string> {
  return Object.fromEntries(
    Object.entries(workload.aliases).map((
      [prefix, directory],
    ) => [prefix, `${workload.root}/${directory}`]),
  );
}

// ------------------------------------------------------------- measurements

interface Variant {
  readonly name: "baseline" | "candidate";
  readonly executable: string;
  readonly sha256: Hash;
}
interface FreshSample {
  kind: "fresh" | "restart";
  workload: string;
  variant: string;
  run: number;
  cpu_s: number;
  user_s: number;
  system_s: number;
  wall_ms: number;
  wasm_sha256: Hash;
  compiler_total_us: number;
  peak_bytes: number;
  allocated_bytes: number;
  type_nodes: number;
  work_counters: Record<string, number> | null;
}
interface RetainedSample {
  kind: "retained";
  workload: string;
  variant: string;
  run: number;
  phase: string;
  cpu_s: number;
  wall_ms: number;
  wasm_sha256: Hash;
  peak_rss_kib: number;
  work_counters: Record<string, number> | null;
}
type Sample = FreshSample | RetainedSample;

/**
 * Child CPU via bash `times` (getrusage(RUSAGE_CHILDREN)). It must run in the
 * shell itself: inside a pipeline or substitution it would read a subshell.
 */
const timesScript =
  'log=$1; shift; "$@" >"$log" 2>"$log.err"; status=$?; times >"$log.times"; exit $status';
const timePattern = /(\d+)m([\d.]+)s\s+(\d+)m([\d.]+)s/;

async function freshBuild(
  variant: Variant,
  workload: Workload,
  output: string,
  cacheDirectory = "",
): Promise<Omit<FreshSample, "kind" | "workload" | "variant" | "run">> {
  const log = `${output}.log`;
  const flags = [
    ...(workload.stdRoot ? ["--std-root", workload.stdRoot] : []),
    "--prelude",
    workload.prelude,
    ...Object.entries(aliasMap(workload)).flatMap((
      [prefix, directory],
    ) => ["--alias", `${prefix}=${directory}`]),
  ];
  const started = performance.now();
  const result = await new Deno.Command("bash", {
    args: [
      "-c",
      timesScript,
      "bench",
      log,
      variant.executable,
      workload.command,
      workload.entry,
      output,
      ...flags,
    ],
    env: { LC_ALL: "C", BLOT_CACHE_DIR: cacheDirectory },
    stdout: "piped",
    stderr: "piped",
  }).output();
  const wall_ms = performance.now() - started;
  const records = (await Deno.readTextFile(log)).trim().split("\n").filter(
    Boolean,
  )
    .map((line) => JSON.parse(line));
  const metrics = records.find((record) => record.kind === "compilation");
  if (!result.success || !metrics?.success) {
    throw new Error(
      `${variant.name} failed to build ${workload.name}:\n${
        records.map((r) => JSON.stringify(r)).join("\n")
      }\n${await Deno.readTextFile(`${log}.err`)}`,
    );
  }
  const times = (await Deno.readTextFile(`${log}.times`)).trim().split("\n");
  const match = times.at(-1)?.match(timePattern);
  if (!match) {
    throw new Error("Unable to read child CPU time from bash `times`");
  }
  const user_s = Number(match[1]) * 60 + Number(match[2]);
  const system_s = Number(match[3]) * 60 + Number(match[4]);
  const wasm_sha256 = await sha256(await Deno.readFile(output));
  // Only successful builds are cleaned up; a failure keeps its evidence.
  for (const path of [output, log, `${log}.err`, `${log}.times`]) {
    await Deno.remove(path);
  }
  return {
    cpu_s: user_s + system_s,
    user_s,
    system_s,
    wall_ms,
    wasm_sha256,
    compiler_total_us: metrics.total_us,
    peak_bytes: metrics.memory.peak_bytes,
    allocated_bytes: metrics.memory.allocated_bytes,
    type_nodes: metrics.type_nodes,
    work_counters: metrics.work_counters ?? null,
  };
}

const ticksPerSecond = 100; // Linux USER_HZ.
async function processUsage(pid: number) {
  const stat = await Deno.readTextFile(`/proc/${pid}/stat`);
  const columns = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  return {
    ticks: Number(columns[11]) + Number(columns[12]),
    peak_rss_kib: Number(status.match(/^VmHWM:\s+(\d+)/m)?.[1] ?? 0),
  };
}

async function retainedSession(
  variant: Variant,
  workload: Workload,
  run: number,
): Promise<RetainedSample[]> {
  const original = await Deno.readTextFile(workload.editFile);
  const edited = applyEdit(original, workload.edit, workload.name);
  const compiler = await createZigProjectCompiler({
    executable: variant.executable,
    entry: workload.entry,
    prelude: workload.prelude,
    ...(workload.stdRoot ? { stdRoot: workload.stdRoot } : {}),
    imports: aliasMap(workload),
    cacheDirectory: false,
  });
  const samples: RetainedSample[] = [];
  try {
    for (
      const [phase, source] of [
        ["population", original],
        ["first_edit", edited],
        ["subsequent_edit", original],
        ["noop", original],
      ] as const
    ) {
      const before = await processUsage(compiler.pid);
      const started = performance.now();
      const result = await compiler.build({
        sources: { [workload.editFile]: source },
      });
      const wall_ms = performance.now() - started;
      const after = await processUsage(compiler.pid);
      if (!result.success) {
        throw new Error(
          `${variant.name} retained ${phase} of ${workload.name}: ${
            JSON.stringify(result)
          }`,
        );
      }
      samples.push({
        kind: "retained",
        workload: workload.name,
        variant: variant.name,
        run,
        phase,
        cpu_s: (after.ticks - before.ticks) / ticksPerSecond,
        wall_ms,
        wasm_sha256: await sha256(result.bytes),
        peak_rss_kib: after.peak_rss_kib,
        work_counters: (result.stats.workCounters as Record<string, number>) ??
          null,
      });
    }
  } finally {
    await compiler.dispose();
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
  if (
    snapshot.status === "verified" && ["all", "gdev"].includes(selected)
  ) workloads.push(gdevWorkload());
  for (const program of syntheticCorpus) {
    if (
      ["all", "synthetic", program.name, `${program.name}_${program.size}`]
        .includes(
          selected,
        )
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
      {
        append: true,
      },
    );
  };
  const loadStart = loadAverage();
  const cpus = navigator.hardwareConcurrency;
  console.log(
    `bench:compile ${runs} alternating pairs, out ${
      relative(Deno.cwd(), out)
    }\n` +
      variants.map((v) =>
        `  ${v.name.padEnd(9)} ${v.sha256.slice(0, 12)} ${v.executable}`
      )
        .join("\n"),
  );
  if (loadStart > cpus) {
    console.log(
      `  host load ${
        loadStart.toFixed(1)
      } on ${cpus} cpus: CPU time is reported, but expect cache/SMT noise; more --runs help.`,
    );
  }

  for (let run = 0; run < runs; run++) {
    const order = run % 2 ? [...variants].reverse() : variants;
    for (const workload of workloads) {
      for (const variant of order) {
        const output =
          `${out}/fresh-${workload.name}-${variant.name}-${run}.wasm`;
        const cacheDirectory = args["restart-cache"]
          ? `${out}/cache/${variant.name}/${workload.name}/${run}`
          : "";
        const measured = await freshBuild(
          variant,
          workload,
          output,
          cacheDirectory,
        );
        await record({
          kind: "fresh",
          workload: workload.name,
          variant: variant.name,
          run,
          ...measured,
        });
        if (args["restart-cache"]) {
          await record({
            kind: "restart",
            workload: workload.name,
            variant: variant.name,
            run,
            ...await freshBuild(
              variant,
              workload,
              `${output}.restart.wasm`,
              cacheDirectory,
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
    const mark = (key: string, variant: string, digest: Hash) => {
      const label = `${workload.name} ${key}`;
      const known = digests[`${key}/${variant}`];
      if (known && known !== digest) {
        problems.push(`${label}: ${variant} output varies between runs`);
      }
      digests[`${key}/${variant}`] = digest;
    };
    for (const sample of samples) {
      if (sample.workload !== workload.name) continue;
      if (sample.kind !== "retained") {
        mark(sample.kind, sample.variant, sample.wasm_sha256);
      } else mark(sample.phase, sample.variant, sample.wasm_sha256);
    }
    const edited = await editedCopy(workload, out);
    for (const variant of variants) {
      const output = `${out}/edited-${workload.name}-${variant.name}.wasm`;
      const built = await freshBuild(variant, edited, output);
      digests[`fresh_edited/${variant.name}`] = built.wasm_sha256;
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
        `first_edit/${variant}`,
        `fresh_edited/${variant}`,
        "retained edit differs from fresh build of edited source",
      );
      compare(
        `fresh/${variant}`,
        `subsequent_edit/${variant}`,
        "restoring the source did not restore the bytes",
      );
      compare(
        `fresh/${variant}`,
        `noop/${variant}`,
        "no-op rebuild changed the bytes",
      );
    }
    for (
      const key of [
        "fresh",
        "restart",
        "population",
        "first_edit",
        "subsequent_edit",
        "noop",
        "fresh_edited",
      ]
    ) {
      compare(
        `${key}/baseline`,
        `${key}/candidate`,
        "baseline and candidate emitted different Wasm",
        true,
      );
    }
    wasm[workload.name] = digests;
  }

  // Medians.
  const cell = (workload: string, variant: string, phase: string) =>
    median(
      samples.filter((s) =>
        s.workload === workload && s.variant === variant &&
        (s.kind !== "retained" ? phase === s.kind : s.phase === phase)
      ).map((s) => s.cpu_s),
    );
  const phases = [
    "fresh",
    ...(args["restart-cache"] ? ["restart"] : []),
    "population",
    "first_edit",
    "subsequent_edit",
    "noop",
  ];
  const medians: Record<
    string,
    Record<
      string,
      {
        baseline_cpu_s: number;
        candidate_cpu_s: number;
        ratio: number | null;
      }
    >
  > = {};
  const rows: string[][] = [[
    "workload",
    "phase",
    "baseline cpu s",
    "candidate cpu s",
    "cand/base",
  ]];
  for (const workload of workloads) {
    medians[workload.name] = {};
    for (const phase of phases) {
      if (phase !== "fresh" && phase !== "restart" && args["no-retained"]) {
        continue;
      }
      const baseline_cpu_s = cell(workload.name, "baseline", phase);
      const candidate_cpu_s = cell(workload.name, "candidate", phase);
      // Retained phases tick at 10 ms; a zero median has no meaningful ratio.
      const ratio = baseline_cpu_s > 0 && candidate_cpu_s > 0
        ? candidate_cpu_s / baseline_cpu_s
        : null;
      medians[workload.name][phase] = {
        baseline_cpu_s,
        candidate_cpu_s,
        ratio,
      };
      rows.push([
        workload.name,
        phase,
        baseline_cpu_s.toFixed(3),
        candidate_cpu_s.toFixed(3),
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
    "alloc MiB",
  ]];
  const counters: Record<string, Record<string, number> | null> = {};
  for (const workload of workloads) {
    const sample = samples.findLast((s): s is FreshSample =>
      s.kind === "fresh" && s.workload === workload.name &&
      s.variant === "candidate"
    );
    const c = sample?.work_counters ?? null;
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
      (sample!.allocated_bytes / 1048576).toFixed(1),
    ]);
  }
  if (counterRows.length > 1) {
    console.log("\ncandidate fresh-build work counters (deterministic)");
    printTable(counterRows);
  }

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
        timestamp,
        runs,
        host: {
          deno: Deno.version.deno,
          os: Deno.build.os,
          cpus,
          load_start: loadStart,
          load_end: loadEnd,
        },
        variants,
        snapshot,
        workloads: workloads.map((w) => ({ name: w.name, group: w.group })),
        medians,
        counters,
        wasm,
        problems,
        unexpected_problems: unexpectedProblems,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `\nwrote ${relative(Deno.cwd(), out)}/results.json (load ${
      loadStart.toFixed(1)
    } -> ${loadEnd.toFixed(1)})`,
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

function printTable(rows: string[][]) {
  const widths = rows[0].map((_, column) =>
    Math.max(...rows.map((row) => row[column].length))
  );
  for (const row of rows) {
    console.log(
      row.map((text, column) =>
        column < 2 ? text.padEnd(widths[column]) : text.padStart(widths[column])
      )
        .join("  "),
    );
  }
}

Deno.exit(await main());
