import { fileURLToPath } from "node:url";
import { relative, resolve } from "node:path";
import { parseArgs } from "node:util";
import { type Phase, runPhase, together } from "./compiler_phase.ts";
import {
  failedGuestFiles,
  fileDigest,
  inputDigest,
  nativeInputs,
  NativeJournal,
  nativeToolchain,
  recentFailures,
} from "./compiler_gate_state.ts";
import { fixturesForGuestFiles } from "./compiler_fixtures.ts";
export { cacheStatus, runPhase } from "./compiler_phase.ts";

const root = fileURLToPath(new URL("../", import.meta.url));
const native = resolve(root, "zig-native");
const smokeFiles = [
  "zig-native/tests/zig_project_protocol.test.ts",
  "zig-native/tests/zig_project_client.test.ts",
  "zig-native/tests/stage_chain_budget.test.ts",
];

type Sweep = {
  kind: string;
  duration_ns: number;
  allocations: number;
  runs: number;
  completed: boolean;
  scenario: string;
  scenario_source?: { file_name: string; line: number; column: number } | null;
  source?: { file_name: string; line: number; column: number } | null;
};

export function sweepTimings(stderr: string): Sweep[] {
  const sweeps = [];
  for (const line of stderr.split("\n")) {
    const marker = line.indexOf("BLOT_OOM_PROFILE\t");
    if (marker < 0) continue;
    const sweep = JSON.parse(line.slice(marker + "BLOT_OOM_PROFILE\t".length));
    if (
      !Number.isFinite(sweep.duration_ns) || sweep.duration_ns < 0 ||
      !Number.isSafeInteger(sweep.allocations) || sweep.allocations < 0 ||
      !Number.isSafeInteger(sweep.runs) || sweep.runs < 1 ||
      typeof sweep.completed !== "boolean" || typeof sweep.scenario !== "string"
    ) throw new Error("Invalid OOM timing record");
    sweeps.push(sweep as Sweep);
  }
  return sweeps.sort((a, b) => b.duration_ns - a.duration_ns);
}

function testCommand(
  files: string[],
  compiler: string,
  jobs: number,
  filter?: string,
  junit?: string,
) {
  const args = [
    Deno.execPath(),
    "test",
    "--allow-read",
    "--allow-write",
    "--allow-run",
    "--allow-env=BLOT_CLIENT_TEST_AMBIENT",
    "--fail-fast",
  ];
  if (junit) args.push("--junit-path", junit);
  if (jobs > 1) args.push("--parallel");
  if (filter) args.push("--filter", filter);
  args.push(...files, "--", compiler);
  return args;
}

async function main() {
  const { values, positionals } = parseArgs({
    args: Deno.args,
    options: {
      dev: { type: "boolean", default: false },
      guest: { type: "boolean", default: false },
      jobs: { type: "string", default: "4" },
      "build-jobs": { type: "string", default: "2" },
      "native-shards": { type: "string", default: "2" },
      filter: { type: "string" },
      "native-filter": { type: "string", multiple: true },
      "native-suite": { type: "string", default: "all" },
      "native-llvm": { type: "boolean", default: false },
      "oom-profile": { type: "boolean", default: false },
      "force-native": { type: "boolean", default: false },
      resume: { type: "boolean", default: false },
      serial: { type: "boolean", default: false },
      preflight: { type: "string", multiple: true },
      "phase-seconds": { type: "string" },
      "budget-seconds": { type: "string" },
      "heartbeat-seconds": { type: "string", default: "15" },
      "timings-dir": { type: "string", default: "build/bench/iteration" },
      help: { type: "boolean", default: false },
    },
    allowPositionals: true,
  });
  if (values.help) {
    console.log(
      "test:compiler [--resume] [--serial] [--jobs 1..4] [--build-jobs N] [--native-shards 1..4] [--oom-profile] [--force-native]\n" +
        "test:compiler:dev [--native-suite all|syntax|types|runtime|checker|evaluator|backend|retained] [--native-filter NAME] [--native-llvm] [--filter NAME] [FILES...]\n" +
        "test:guest [--jobs 1..4] [--filter NAME] [FILES...]\n" +
        "All modes: [--budget-seconds N] [--phase-seconds N] [--heartbeat-seconds N] [--timings-dir PATH]\n" +
        "Full gate: [--preflight FILE] repeats recent failed guest files before LLVM builds.\n" +
        "Explicit development selectors run only requested checks; bare --dev runs smoke.\n" +
        "Development defaults to 60s total/per phase; full gates to 900s total/600s per phase.\n" +
        "--resume reuses successful native phases only when inputs, toolchain, binary and logs match.",
    );
    return;
  }
  const positive = (
    text: string | undefined,
    fallback: number,
    name: string,
  ) => {
    const number = Number(text ?? fallback);
    if (!Number.isFinite(number) || number <= 0) {
      throw new Error(`${name} must be positive`);
    }
    return number;
  };
  const jobs = positive(values.jobs, 4, "--jobs");
  const buildJobs = positive(values["build-jobs"], 2, "--build-jobs");
  const shards = positive(values["native-shards"], 2, "--native-shards");
  for (
    const [name, number, max] of [["jobs", jobs, 4], [
      "build-jobs",
      buildJobs,
      16,
    ], ["native-shards", shards, 4]] as const
  ) {
    if (!Number.isInteger(number) || number > max) {
      throw new Error(`--${name} must be 1 through ${max}`);
    }
  }
  let defaultBudget = 900;
  let defaultPhase = 600;
  if (values.dev) {
    defaultBudget = 60;
    defaultPhase = 60;
  }
  const budget = positive(
    values["budget-seconds"],
    defaultBudget,
    "--budget-seconds",
  );
  const phaseBudget = positive(
    values["phase-seconds"],
    defaultPhase,
    "--phase-seconds",
  );
  const heartbeat = positive(
    values["heartbeat-seconds"],
    15,
    "--heartbeat-seconds",
  );
  if (values.dev && values.guest) throw new Error("Choose --dev or --guest");
  if (values["native-llvm"] && !values.dev) {
    throw new Error("--native-llvm applies to development checks");
  }
  const suites = [
    "all",
    "syntax",
    "types",
    "runtime",
    "checker",
    "evaluator",
    "backend",
    "retained",
  ];
  if (!suites.includes(values["native-suite"])) {
    throw new Error(`--native-suite must be ${suites.join(", ")}`);
  }
  if (
    !values.dev && !values.guest &&
    (positionals.length || values.filter || values["native-filter"]?.length ||
      values["native-suite"] !== "all")
  ) {
    throw new Error(
      "The full compiler gate cannot be filtered; use test:compiler:dev",
    );
  }
  if (
    values.guest &&
    (values["native-filter"]?.length || values["native-suite"] !== "all")
  ) throw new Error("Guest mode has no native tests");
  for (const file of [...positionals, ...values.preflight ?? []]) {
    if (!file.endsWith(".test.ts")) {
      throw new Error(`Expected a test file: ${file}`);
    }
  }
  const requestedNative = Boolean(values["native-filter"]?.length) ||
    Deno.args.some((argument) =>
      argument === "--native-suite" || argument.startsWith("--native-suite=")
    );
  const requestedGuests = positionals.length > 0 || Boolean(values.filter);
  const smoke = !values.guest &&
    (!values.dev || (!requestedNative && !requestedGuests));
  const directory = resolve(root, values["timings-dir"]);
  await Deno.mkdir(directory, { recursive: true });
  const runDirectory = await Deno.makeTempDir({
    dir: directory,
    prefix: "run-",
  });
  const failurePath = resolve(directory, "recent-failures.json");
  let failures = await recentFailures(failurePath);
  const preflight = new Set<string>();
  for (const file of failures) {
    if (preflight.size >= 8) break;
    const path = relative(root, resolve(root, file));
    if (path.startsWith("..") || !path.endsWith(".test.ts")) continue;
    try {
      if ((await Deno.stat(resolve(root, path))).isFile) preflight.add(path);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  for (const file of values.preflight ?? []) preflight.add(file);
  const preflightFiles = [...preflight];
  const report = {
    mode: "full",
    native_suite: values["native-suite"],
    native_backend: "LLVM",
    native_shards: shards,
    jobs,
    build_jobs: buildJobs,
    overlap: !values.serial,
    resume: values.resume,
    budget_seconds: budget,
    phase_seconds: phaseBudget,
    started_at: new Date().toISOString(),
    wall_seconds: 0,
    success: false,
    active: [] as string[],
    phases: [] as Phase[],
    oom_profile: values["oom-profile"],
    oom_sweeps: 0,
    slowest_oom_sweeps: [] as Sweep[],
  };
  if (values.dev) report.mode = "development";
  if (values.guest) report.mode = "guest";
  const journal = new NativeJournal(
    resolve(directory, "native-successes.json"),
  );
  await journal.load();
  const started = performance.now();
  const controller = new AbortController();
  const abort = () => controller.abort();
  Deno.addSignalListener("SIGINT", abort);
  if (Deno.build.os !== "windows") Deno.addSignalListener("SIGTERM", abort);
  const deadline = setTimeout(() => controller.abort("budget"), budget * 1000);
  let toolchain: Promise<string> | undefined;
  let writes = Promise.resolve();
  const flush = () => {
    writes = writes.then(async () => {
      report.wall_seconds = (performance.now() - started) / 1000;
      const temporary = resolve(directory, `timings.${Deno.pid}.tmp`);
      const contents = JSON.stringify(report, null, 2) + "\n";
      await Deno.writeTextFile(resolve(runDirectory, "timings.json"), contents);
      await Deno.writeTextFile(temporary, contents);
      await Deno.rename(temporary, resolve(directory, "timings.json"));
    });
    return writes;
  };
  const guestSelections = new Map<
    string,
    { files: string[]; filter?: string; junit: string }
  >();
  const phase = async (
    name: string,
    command: string[],
    cwd = root,
    env: Record<string, string> = {},
  ) => {
    if (controller.signal.aborted) {
      throw new Error("Compiler gate cancelled before " + name);
    }
    report.active.push(name);
    await flush();
    const cacheable = !values.dev && !values.guest &&
      name.startsWith("native-");
    let key: string | undefined;
    let inputs: string[] = [];
    const qualifyKey = async () => {
      toolchain ??= nativeToolchain();
      inputs = await nativeInputs(root);
      return JSON.stringify({
        command,
        cwd,
        env,
        toolchain: await toolchain,
        inputs: await inputDigest(inputs),
      });
    };
    let result: Phase | undefined;
    const binary = resolve(native, "zig-out/bin/blot-tests");
    let executedBinary: string | undefined;
    if (cacheable) {
      key = await qualifyKey();
      if (values.resume && !(name === "native-run" && values["force-native"])) {
        result = await journal.reuse(name, key);
      }
      if (result) console.log(`${name}: resumed verified successful phase`);
    }
    try {
      if (cacheable && !result) await journal.invalidate(name);
      if (cacheable && name === "native-run") {
        executedBinary = await fileDigest(binary);
      }
      result ??= await runPhase(name, command, runDirectory, cwd, env, {
        seconds: phaseBudget,
        heartbeat,
        signal: controller.signal,
      });
      report.phases.push(result);
      if (name === "native-run" && values["oom-profile"]) {
        const stderr = await Deno.readTextFile(result.stderr);
        if (stderr.includes("BLOT_OOM_PROFILE_ERROR\t")) {
          throw new Error(
            "Native laws ran, but OOM timing output is incomplete",
          );
        }
        const sweeps = sweepTimings(stderr);
        report.oom_sweeps = sweeps.length;
        report.slowest_oom_sweeps = sweeps.slice(0, 10);
        if (!values.dev && result.code === 0 && sweeps.length === 0) {
          throw new Error(
            "The profiled full gate produced no OOM timing records",
          );
        }
      }
      const selected = guestSelections.get(name);
      if (selected) {
        let found: string[] = [];
        try {
          found = failedGuestFiles(
            await Deno.readTextFile(selected.junit),
            root,
          );
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) throw error;
        }
        if (result.code === 0 && !selected.filter) {
          failures = failures.filter((file) =>
            !selected.files.some((tested) =>
              file === tested || file.startsWith(tested + "/")
            )
          );
        }
        failures = [...new Set([...found, ...failures])];
        await Deno.writeTextFile(
          failurePath,
          JSON.stringify(failures, null, 2) + "\n",
        );
      }
      if (result.code !== 0) {
        const text = (await Deno.readTextFile(result.stdout)) +
          (await Deno.readTextFile(result.stderr));
        console.error(text.split("\n").slice(-50).join("\n"));
        throw new Error(`${name} failed; logs: ${runDirectory}`);
      }
      if (key) {
        if (key !== await qualifyKey()) {
          throw new Error(
            "Native inputs changed during " + name + "; retry qualification",
          );
        }
        if (executedBinary && executedBinary !== await fileDigest(binary)) {
          throw new Error(
            "Native executable changed during execution; retry qualification",
          );
        }
        if (result.cache !== "resumed") {
          await journal.record(key, result, [binary]);
        }
      }
      return result;
    } finally {
      report.active = report.active.filter((active) => active !== name);
      await flush();
    }
  };
  const build = (dev: boolean, files: string[]) => {
    const args = [
      Deno.execPath(),
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-run=zig",
      "scripts/build_compiler.ts",
    ];
    if (dev) args.push("--dev");
    args.push(
      `--fixtures=${fixturesForGuestFiles(files).join(",")}`,
      `--jobs=${buildJobs}`,
    );
    return args;
  };
  const guests = (
    name: string,
    files: string[],
    compiler: string,
    filter?: string,
  ) => {
    const junit = resolve(runDirectory, `${name}.junit.xml`);
    guestSelections.set(name, { files, filter, junit });
    return phase(
      name,
      testCommand(files, compiler, jobs, filter, junit),
      root,
      { DENO_JOBS: String(jobs) },
    );
  };
  const nativeOptions = [
    "-Doptimize=safe",
    "--summary",
    "all",
    `-j${buildJobs}`,
    `-Dtest-shards=${shards}`,
  ];
  if (values.dev && !values["native-llvm"]) {
    nativeOptions.push(
      "-Dllvm=false",
      "-fincremental",
      "--prefix",
      "zig-out-native-dev",
    );
    report.native_backend = "noLLVM";
  }
  if (values["native-suite"] !== "all") {
    nativeOptions.push(`-Dtest-suite=${values["native-suite"]}`);
  }
  if (values["oom-profile"]) nativeOptions.push("-Doom-profile=true");
  if (values["oom-profile"] || values["force-native"]) {
    nativeOptions.push("-Dtest-force-run=true");
  }
  for (const filter of values["native-filter"] ?? []) {
    nativeOptions.push(`-Dtest-filter=${filter}`);
  }
  try {
    let developmentFiles = positionals;
    if (!developmentFiles.length) developmentFiles = smokeFiles;
    if (smoke || (values.dev && requestedGuests)) {
      let name = "development-build";
      let files = developmentFiles;
      if (smoke) {
        name = "smoke-build";
        files = [...smokeFiles, ...preflightFiles];
      }
      await phase(name, build(true, files));
    } else if (values.dev && requestedNative) {
      const version = await phase("zig-version", ["zig", "version"]);
      const installed = (await Deno.readTextFile(version.stdout)).trim();
      if (!/^0\.17\.0(?:-|$)/.test(installed)) {
        throw new Error(`Blot requires Zig 0.17.0 (installed: ${installed})`);
      }
    }
    if (smoke) {
      if (preflightFiles.length) {
        await guests(
          "preflight-regressions",
          preflightFiles,
          "zig-native/zig-out-dev/bin/blotc",
        );
      }
      await guests("smoke", smokeFiles, "zig-native/zig-out-dev/bin/blotc");
    }
    if (values.dev) {
      if (requestedNative) {
        await phase(
          "native-run",
          ["zig", "build", "test", ...nativeOptions],
          native,
        );
      }
      if (requestedGuests) {
        await guests(
          "focused-guests",
          developmentFiles,
          "zig-native/zig-out-dev/bin/blotc",
          values.filter,
        );
      }
    } else {
      let files = positionals;
      if (!files.length) {
        files = ["zig-native/tests"];
        for await (const entry of Deno.readDir(resolve(root, "compiler"))) {
          if (entry.isFile && entry.name.endsWith(".test.ts")) {
            files.push(`compiler/${entry.name}`);
          }
        }
        files.sort();
      }
      if (!values.guest) {
        await phase("harness", [
          Deno.execPath(),
          "test",
          "--allow-read",
          "--allow-write",
          "--allow-run",
          "--allow-env",
          "--fail-fast",
          "scripts/test_compiler.test.ts",
          "scripts/compiler_gate_state.test.ts",
          "scripts/compiler_fingerprint.test.ts",
          "scripts/compiler_fixtures.test.ts",
          "scripts/build_compiler.test.ts",
          "scripts/native_test_runner.test.ts",
          "scripts/lint_zig.test.ts",
        ]);
        const compile = () =>
          phase("native-compile", [
            "zig",
            "build",
            "test-compile",
            ...nativeOptions,
          ], native);
        const release = () => phase("release-build", build(false, files));
        const laws = () =>
          phase(
            "native-run",
            ["zig", "build", "test", ...nativeOptions],
            native,
          );
        if (values.serial) {
          await compile();
          await release();
          await laws();
        } else {
          await together([
            release,
            async () => {
              await compile();
              await laws();
            },
          ], controller);
        }
      }
      await phase("pack", [
        Deno.execPath(),
        "run",
        "--allow-read",
        "--allow-write=generated/compiler",
        "scripts/pack_native.ts",
      ]);
      await guests(
        "guests",
        files,
        "zig-native/zig-out/bin/blotc",
        values.filter,
      );
    }
    report.success = true;
  } finally {
    clearTimeout(deadline);
    Deno.removeSignalListener("SIGINT", abort);
    if (Deno.build.os !== "windows") {
      Deno.removeSignalListener("SIGTERM", abort);
    }
    await flush();
    console.log(`Timing record: ${resolve(directory, "timings.json")}`);
    for (const sweep of report.slowest_oom_sweeps) {
      let label = sweep.scenario;
      if (sweep.scenario_source) {
        label =
          `${sweep.scenario_source.file_name}:${sweep.scenario_source.line} ${label}`;
      }
      console.log(
        `OOM ${
          (sweep.duration_ns / 1e9).toFixed(3)
        }s, ${sweep.allocations} allocations, ${sweep.runs} runs: ${label}`,
      );
    }
  }
}

if (import.meta.main) await main();
