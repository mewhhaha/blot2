// Paired gdev compiler benchmark. Run only after both compiler executables are built:
// deno run --allow-all compiler/gdev_performance_bench.ts [samples=3] [threads=1] [baseline-root=build/gdev-optimization-baseline] [candidate-root=.] [report=build/gdev-performance-bench/results.json]
import { isDeepStrictEqual } from "node:util";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  decodeFrame,
  encodeFrame,
  parseCatalog,
  validateSchema,
  validateState,
} from "../../gdev/boundary.ts";
import { type Guest, instantiateGuest } from "./guest.ts";
import {
  matchingNativeChild,
  nativeCpuHz,
  nativeCpuMilliseconds,
  nativeCpuSample,
  nativeScheduler,
  ownedNativeChildren,
} from "./native_cpu_bench.ts";

const samples = Number(Deno.args[0] ?? "3");
const threads = Number(Deno.args[1] ?? "1");
const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const baselineRoot = resolve(
  Deno.args[2] ?? join(projectRoot, "build/gdev-optimization-baseline"),
);
const candidateRoot = resolve(Deno.args[3] ?? projectRoot);
const reportPath = resolve(
  Deno.args[4] ??
    join(projectRoot, "build/gdev-performance-bench/results.json"),
);
if (
  !Number.isInteger(samples) || samples < 1 || samples > 20 ||
  !Number.isInteger(threads) || threads < 1 || threads > 8
) {
  throw new Error(
    "Usage: gdev_performance_bench.ts [samples:1..20] [threads:1..8] [baseline-root] [candidate-root] [report-path]",
  );
}

const entry = resolve(projectRoot, "../gdev/src/main.blot");
const motionPath = resolve(projectRoot, "../gdev/src/motion.blot");
const catalogPath = resolve(projectRoot, "../gdev/src/assets/catalog.json");
// Keep module identities identical between snapshots: the workload imports
// one shared, unchanged standard library source tree.
const workloadStd = pathToFileURL(join(projectRoot, "std") + sep);
const baselineExecutable = pathToFileURL(
  join(baselineRoot, "generated/compiler/blotc"),
);
const candidateExecutable = pathToFileURL(
  join(candidateRoot, "generated/compiler/blotc"),
);
const motionOriginal = await Deno.readTextFile(motionPath);
const oldAxis = "y: 1.0";
const newAxis = "y: 0.9";
if (
  motionOriginal.split(oldAxis).length !== 2 ||
  oldAxis.length !== newAxis.length
) {
  throw new Error("Expected exactly one equal-width motion axis edit");
}
const motionEdited = motionOriginal.replace(oldAxis, newAxis);
const catalog = parseCatalog(JSON.parse(await Deno.readTextFile(catalogPath)));
const encode = new TextEncoder();
const now = () => performance.now();

function cpuMedian(rows: readonly Record<string, unknown>[]): number | null {
  const values = rows.map((row) => row.native_cpu_ms).filter((
    value,
  ): value is number => typeof value === "number");
  return values.length ? median(values) : null;
}

type Variant = "original" | "edited";
type Side = "baseline" | "candidate";
type Artifact = { readonly bytes: Uint8Array<ArrayBuffer> };
type SessionResult = Awaited<
  ReturnType<
    Awaited<
      ReturnType<
        typeof import("./native_project.ts")["createNativeProjectCompiler"]
      >
    >["compile"]
  >
>;

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.slice().buffer),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

async function sourceTreeHash(root: string): Promise<string> {
  const files: string[] = [];
  async function visit(path: string) {
    for await (const entry of Deno.readDir(path)) {
      const child = join(path, entry.name);
      if (entry.isDirectory) await visit(child);
      else if (entry.isFile && /\.(bend|ts)$/.test(entry.name)) {
        files.push(child);
      }
    }
  }
  await visit(join(root, "compiler"));
  files.sort();
  const rows = await Promise.all(
    files.map(async (file) =>
      `${relative(root, file).split(sep).join("/")}\0${await sha256(
        await Deno.readFile(file),
      )}`
    ),
  );
  return sha256(encode.encode(rows.join("\n")));
}

function readVariant(variant: () => Variant) {
  return async (url: URL): Promise<string> => {
    if (fileURLToPath(url) === motionPath) {
      return variant() === "edited" ? motionEdited : motionOriginal;
    }
    return Deno.readTextFile(url);
  };
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length % 2 === 0
    ? (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2
    : sorted[(sorted.length - 1) / 2];
}

function checkGame(guest: Guest) {
  const schema = guest.read("state_schema");
  validateSchema(schema);
  const created = guest.call("create", null);
  validateState(created);
  const cleaned = guest.call("clean", created.slice());
  validateState(cleaned);
  const packet = guest.call(
    "frame",
    encodeFrame(
      { timestamp: 0, viewport: { width: 1280n, height: 720n }, events: [] },
      1 / 60,
      cleaned.slice(),
    ),
  );
  decodeFrame(packet, schema, catalog);
  return { schema, created, cleaned, packet, abi: guest.abi };
}

async function compareArtifacts(left: Artifact, right: Artifact) {
  const [leftHash, rightHash] = await Promise.all([
    sha256(left.bytes),
    sha256(right.bytes),
  ]);
  const leftGuest = await instantiateGuest(left.bytes);
  const rightGuest = await instantiateGuest(right.bytes);
  try {
    const a = checkGame(leftGuest);
    const b = checkGame(rightGuest);
    const result = {
      wasm_equal: leftHash === rightHash,
      abi_equal: isDeepStrictEqual(a.abi, b.abi),
      create_equal: isDeepStrictEqual(a.created, b.created),
      clean_equal: isDeepStrictEqual(a.cleaned, b.cleaned),
      frame_equal: isDeepStrictEqual(a.packet, b.packet),
    };
    if (!result.create_equal || !result.clean_equal || !result.frame_equal) {
      throw new Error(
        `Compiled game behavior differs: ${JSON.stringify(result)}`,
      );
    }
    return result;
  } finally {
    leftGuest.dispose();
    rightGuest.dispose();
  }
}

// Import each API from the same snapshot as its executable. The snapshots may
// use different native wire protocols, and their frontends must stay paired.
const baselineNative: typeof import("./native.ts") = await import(
  pathToFileURL(join(baselineRoot, "compiler/native.ts")).href
);
const baselineProject: typeof import("./source_project.ts") = await import(
  pathToFileURL(join(baselineRoot, "compiler/source_project.ts")).href
);
const candidateNative: typeof import("./native.ts") = await import(
  pathToFileURL(join(candidateRoot, "compiler/native.ts")).href
);
const candidateProject: typeof import("./source_project.ts") = await import(
  pathToFileURL(join(candidateRoot, "compiler/source_project.ts")).href
);
const candidateSession: typeof import("./native_project.ts") = await import(
  pathToFileURL(join(candidateRoot, "compiler/native_project.ts")).href
);

const roots = { baseline: baselineRoot, candidate: candidateRoot } as const;
const executables = {
  baseline: baselineExecutable,
  candidate: candidateExecutable,
} as const;
const sourceModules = {
  baseline: baselineProject,
  candidate: candidateProject,
} as const;
const summaries = {
  baseline: await sourceTreeHash(baselineRoot),
  candidate: await sourceTreeHash(candidateRoot),
};
const executableHashes = {
  baseline: await sha256(await Deno.readFile(baselineExecutable)),
  candidate: await sha256(await Deno.readFile(candidateExecutable)),
};
const beforeCompilers = await ownedNativeChildren();
const baselineCompiler = await baselineNative.createNativeCompiler({
  executable: baselineExecutable,
  threads,
});
const baselinePid = await matchingNativeChild(
  baselineExecutable,
  beforeCompilers,
);
const beforeCandidate = await ownedNativeChildren();
const candidateCompiler = await candidateNative.createNativeCompiler({
  executable: candidateExecutable,
  threads,
});
const candidatePid = await matchingNativeChild(
  candidateExecutable,
  beforeCandidate,
);
const compilers = { baseline: baselineCompiler, candidate: candidateCompiler };
const compilerPids = { baseline: baselinePid, candidate: candidatePid };
const compilerScheduler = {
  baseline: await nativeCpuSample(baselinePid),
  candidate: await nativeCpuSample(candidatePid),
};
console.log(JSON.stringify({
  event: "native_clean_children",
  baseline_pid: baselinePid,
  candidate_pid: candidatePid,
  baseline_scheduler: nativeScheduler(compilerScheduler.baseline),
  candidate_scheduler: nativeScheduler(compilerScheduler.candidate),
}));
let currentVariant: Variant = "original";
let session:
  | Awaited<ReturnType<typeof candidateSession.createNativeProjectCompiler>>
  | undefined;
const cleanRows: Array<Record<string, unknown>> = [];
const sessionRows: Array<Record<string, unknown>> = [];
const pairedEditBaselines: Array<Record<string, unknown>> = [];
const cleanArtifacts = new Map<`${Side}:${Variant}`, Artifact>();
const sessionArtifacts: Array<
  { variant: Variant; phase: string; artifact: Artifact }
> = [];
const comparisons: Array<Record<string, unknown>> = [];
const projectSourceHashes: Partial<Record<Variant, string>> = {};

try {
  // A retained process receives a fresh, stateless project compile each round.
  // Order alternates to reduce drift from background load.
  for (let round = 0; round <= samples; round++) {
    const variant: Variant = round % 2 === 0 ? "original" : "edited";
    const order: readonly Side[] = round % 2 === 0
      ? ["baseline", "candidate"]
      : ["candidate", "baseline"];
    for (const side of order) {
      const started = now();
      const project = await sourceModules[side].loadSourceProject(entry, {
        imports: { "std/": workloadStd },
        readSource: readVariant(() => variant),
      });
      const loaded = now();
      if (project.modules.length !== 16) {
        throw new Error(
          `Expected 16 gdev modules, got ${project.modules.length}`,
        );
      }
      const cpuBefore = await nativeCpuSample(compilerPids[side]);
      const compileStarted = now();
      const artifact = await compilers[side].compile(project, {
        const_steps: 100_000n,
      });
      const compiled = now();
      const cpuAfter = await nativeCpuSample(compilerPids[side]);
      const instantiateStarted = now();
      const guest = await instantiateGuest(artifact.bytes);
      guest.dispose();
      const instantiated = now();
      const sourceHash = await sha256(
        encode.encode(
          project.modules.map((module) => `${module.name}\0${module.source}`)
            .sort()
            .join("\0"),
        ),
      );
      if (
        projectSourceHashes[variant] !== undefined &&
        projectSourceHashes[variant] !== sourceHash
      ) throw new Error("Baseline and candidate loaded different gdev sources");
      projectSourceHashes[variant] = sourceHash;
      const row = {
        side,
        variant,
        round,
        phase: round === 0 ? "first_compile" : "steady_clean",
        load_ms: loaded - started,
        compile_ms: compiled - compileStarted,
        native_cpu_ms: nativeCpuMilliseconds(cpuBefore, cpuAfter),
        native_pid: compilerPids[side],
        native_scheduler: nativeScheduler(cpuBefore),
        instantiate_ms: instantiated - instantiateStarted,
        total_ms: (loaded - started) + (compiled - compileStarted) +
          (instantiated - instantiateStarted),
        instrumented_total_ms: instantiated - started,
        wasm_bytes: artifact.bytes.length,
        wasm_sha256: await sha256(artifact.bytes),
        functions: artifact.analysis.functions.length,
        modules: project.modules.length,
        source_chars: project.modules.reduce(
          (n, module) => n + module.source.length,
          0,
        ),
        cst_nodes: project.modules.reduce(
          (n, module) => n + Number(module.nodeCount),
          0,
        ),
      };
      cleanRows.push(row);
      cleanArtifacts.set(`${side}:${variant}`, artifact);
      console.log(JSON.stringify({ event: "clean", ...row }));
    }
  }

  // Keep both clean oracles for semantic comparisons, even with one sample.
  for (const variant of ["original", "edited"] as const) {
    for (const side of ["baseline", "candidate"] as const) {
      if (cleanArtifacts.has(`${side}:${variant}`)) continue;
      const project = await sourceModules[side].loadSourceProject(entry, {
        imports: { "std/": workloadStd },
        readSource: readVariant(() => variant),
      });
      cleanArtifacts.set(
        `${side}:${variant}`,
        await compilers[side].compile(project, { const_steps: 100_000n }),
      );
    }
    comparisons.push({
      kind: "baseline_vs_candidate_clean",
      variant,
      ...await compareArtifacts(
        cleanArtifacts.get(`baseline:${variant}`)!,
        cleanArtifacts.get(`candidate:${variant}`)!,
      ),
    });
  }

  const beforeSession = await ownedNativeChildren();
  session = await candidateSession.createNativeProjectCompiler({
    executable: candidateExecutable,
    threads,
    imports: { "std/": workloadStd },
    readSource: readVariant(() => currentVariant),
  });
  const cleanPids = new Set(
    [baselinePid, candidatePid].filter((pid): pid is number =>
      pid !== undefined
    ),
  );
  let sessionPid = await matchingNativeChild(
    candidateExecutable,
    beforeSession,
  );
  const sessionInitialPid = sessionPid;
  const sessionScheduler = await nativeCpuSample(sessionPid);
  console.log(JSON.stringify({
    event: "native_session_child",
    pid: sessionInitialPid,
    scheduler: nativeScheduler(sessionScheduler),
  }));
  async function sessionCompile(
    phase: string,
    variant: Variant,
    round: number,
  ) {
    currentVariant = variant;
    const started = now();
    const cpuBefore = await nativeCpuSample(sessionPid);
    const compileStarted = now();
    const result: SessionResult = await session!.compile(entry, {
      const_steps: 100_000n,
    });
    const compiled = now();
    const afterPid = await matchingNativeChild(candidateExecutable, cleanPids);
    const cpuAfter = await nativeCpuSample(afterPid);
    const recycled = sessionPid !== afterPid;
    sessionPid = afterPid;
    const instantiateStarted = now();
    const guest = await instantiateGuest(result.artifact.bytes);
    guest.dispose();
    const instantiated = now();
    const row = {
      phase,
      variant,
      round,
      compile_ms: compiled - compileStarted,
      native_cpu_ms: recycled
        ? null
        : nativeCpuMilliseconds(cpuBefore, cpuAfter),
      native_pid: sessionPid,
      native_pid_changed: recycled,
      native_scheduler: nativeScheduler(cpuBefore),
      instantiate_ms: instantiated - instantiateStarted,
      total_ms: (compiled - compileStarted) +
        (instantiated - instantiateStarted),
      instrumented_total_ms: instantiated - started,
      wasm_bytes: result.artifact.bytes.length,
      wasm_sha256: await sha256(result.artifact.bytes),
      cache_stats: result.stats,
    };
    sessionRows.push(row);
    sessionArtifacts.push({ phase, variant, artifact: result.artifact });
    console.log(JSON.stringify({ event: "session", ...row }));
    return result;
  }
  await sessionCompile("first_compile", "original", 0);
  async function pairedEditBaseline(variant: Variant, round: number) {
    const started = now();
    const project = await baselineProject.loadSourceProject(entry, {
      imports: { "std/": workloadStd },
      readSource: readVariant(() => variant),
    });
    const loaded = now();
    const cpuBefore = await nativeCpuSample(baselinePid);
    const compileStarted = now();
    const artifact = await compilers.baseline.compile(project, {
      const_steps: 100_000n,
    });
    const compiled = now();
    const cpuAfter = await nativeCpuSample(baselinePid);
    const instantiateStarted = now();
    const guest = await instantiateGuest(artifact.bytes);
    guest.dispose();
    const instantiated = now();
    const row = {
      variant,
      round,
      load_ms: loaded - started,
      compile_ms: compiled - compileStarted,
      native_cpu_ms: nativeCpuMilliseconds(cpuBefore, cpuAfter),
      native_pid: baselinePid,
      native_scheduler: nativeScheduler(cpuBefore),
      instantiate_ms: instantiated - instantiateStarted,
      total_ms: (loaded - started) + (compiled - compileStarted) +
        (instantiated - instantiateStarted),
      instrumented_total_ms: instantiated - started,
    };
    pairedEditBaselines.push(row);
    comparisons.push({
      kind: "paired_edit_baseline",
      variant,
      ...await compareArtifacts(
        artifact,
        cleanArtifacts.get(`baseline:${variant}`)!,
      ),
    });
    console.log(JSON.stringify({ event: "paired_edit_baseline", ...row }));
  }
  for (let round = 1; round <= samples; round++) {
    const variant: Variant = round % 2 === 1 ? "edited" : "original";
    // Keep a clean baseline adjacent to each edit, alternating order, so changes
    // in desktop load between the clean and session phases remain visible.
    if (round % 2 === 1) await pairedEditBaseline(variant, round);
    const changed = await sessionCompile("body_edit", variant, round);
    if (changed.stats.result_reused || changed.stats.declarations_sent < 1) {
      throw new Error("Body edit was not sent to the native project session");
    }
    if (round % 2 === 0) await pairedEditBaseline(variant, round);
    const unchanged = await sessionCompile("unchanged", variant, round);
    if (
      !unchanged.stats.result_reused || unchanged.stats.declarations_sent !== 0
    ) {
      throw new Error(
        "Unchanged project did not reuse the acknowledged result",
      );
    }
  }
  for (const item of sessionArtifacts) {
    comparisons.push({
      kind: "session_vs_candidate_clean",
      phase: item.phase,
      variant: item.variant,
      ...await compareArtifacts(
        item.artifact,
        cleanArtifacts.get(`candidate:${item.variant}`)!,
      ),
    });
  }

  const steady = (side: Side) =>
    cleanRows.filter((row) => row.side === side && row.phase === "steady_clean")
      .map((row) => row.total_ms as number);
  const times = (phase: string) =>
    sessionRows.filter((row) => row.phase === phase).map((row) =>
      row.total_ms as number
    );
  const report = {
    date: new Date().toISOString(),
    samples,
    threads,
    timing_note:
      "total_ms sums load, compile, and instantiate intervals; instrumented_total_ms also includes /proc CPU/PID probe overhead",
    native_cpu: {
      ticks_per_second: nativeCpuHz ?? null,
      baseline: {
        pid: baselinePid ?? null,
        scheduler: nativeScheduler(compilerScheduler.baseline),
      },
      candidate: {
        pid: candidatePid ?? null,
        scheduler: nativeScheduler(compilerScheduler.candidate),
      },
      session_initial: {
        pid: sessionInitialPid ?? null,
        scheduler: nativeScheduler(sessionScheduler),
      },
      note:
        "Process utime+stime; a session row with native_pid_changed has no complete CPU delta",
    },
    const_steps: 100_000,
    entry,
    edit: { file: motionPath, before: oldAxis, after: newAxis },
    project_source_sha256: projectSourceHashes,
    roots,
    executables: {
      baseline: {
        path: fileURLToPath(executables.baseline),
        sha256: executableHashes.baseline,
        source_sha256: summaries.baseline,
      },
      candidate: {
        path: fileURLToPath(executables.candidate),
        sha256: executableHashes.candidate,
        source_sha256: summaries.candidate,
      },
    },
    clean: cleanRows,
    session: sessionRows,
    paired_edit_baselines: pairedEditBaselines,
    comparisons,
    medians_ms: {
      baseline_clean: median(steady("baseline")),
      candidate_clean: median(steady("candidate")),
      paired_edit_baseline: median(
        pairedEditBaselines.map((row) => row.total_ms as number),
      ),
      session_body_edit: median(times("body_edit")),
      session_unchanged: median(times("unchanged")),
    },
    medians_cpu_ms: {
      baseline_clean: cpuMedian(
        cleanRows.filter((row) =>
          row.side === "baseline" && row.phase === "steady_clean"
        ),
      ),
      candidate_clean: cpuMedian(
        cleanRows.filter((row) =>
          row.side === "candidate" && row.phase === "steady_clean"
        ),
      ),
      paired_edit_baseline: cpuMedian(pairedEditBaselines),
      session_body_edit: cpuMedian(
        sessionRows.filter((row) => row.phase === "body_edit"),
      ),
      session_unchanged: cpuMedian(
        sessionRows.filter((row) => row.phase === "unchanged"),
      ),
    },
  };
  await Deno.mkdir(dirname(reportPath), { recursive: true });
  await Deno.writeTextFile(reportPath, JSON.stringify(report, null, 2) + "\n");
  console.log(
    JSON.stringify({
      event: "report",
      path: reportPath,
      medians_ms: report.medians_ms,
      medians_cpu_ms: report.medians_cpu_ms,
    }),
  );
} finally {
  await session?.dispose();
  await Promise.all([
    compilers.baseline.dispose(),
    compilers.candidate.dispose(),
  ]);
}
