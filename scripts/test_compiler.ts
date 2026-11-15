// The compiler gate.
//   test_compiler.ts          the full gate: the tooling's own tests, the
//                             optimized compiler, its recorded references, the
//                             package and every guest and host test
//   test_compiler.ts --guest  the guest and host tests against the optimized
//                             compiler as it is
//   test_compiler.ts --dev    the debug compiler and the named test files
//                             (three smoke files when none is named)
import { fileURLToPath } from "node:url";
import { relative, resolve } from "node:path";
import { parseArgs } from "node:util";
import { type Phase, runPhase } from "./compiler_phase.ts";
import { failedGuestFiles, recentFailures } from "./compiler_gate_state.ts";
import { compilerLease } from "./compiler_lease.ts";
import {
  buildCommand,
  developmentCompiler,
  releaseCompiler,
} from "./build_compiler.ts";
export { runPhase } from "./compiler_phase.ts";

const root = fileURLToPath(new URL("../", import.meta.url));
export const smokeFiles = [
  "tests/guest/zig_project_protocol.test.ts",
  "tests/guest/zig_project_client.test.ts",
  "tests/guest/stage_chain_budget.test.ts",
];
/** The tests of these scripts, run first by the full gate. */
export const harnessFiles = [
  "tests/tooling/test_compiler.test.ts",
  "tests/tooling/bench_compile.test.ts",
  "tests/tooling/compiler_gate_state.test.ts",
  "tests/tooling/build_compiler.test.ts",
];
/** The compiler's recorded references: what the Zig compiler produced. */
export const referenceChecks = [
  ["reference-direct", "compiler-goose/tools/test_direct.py"],
  ["reference-uniqueness", "compiler-goose/tools/test_uniqueness.py"],
  ["reference-fixtures", "compiler-goose/tools/test_fixtures.py"],
];

export function testCommand(
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

export type Step = { name: string; command: string[]; guests?: string[] };
export type Selection = {
  mode: "full" | "guest" | "development";
  files: string[];
  filter?: string;
  jobs: number;
  preflight: string[];
};

/** The phases of one run, in order. `junit` names a guest phase's report. */
export function plan(
  selection: Selection,
  junit: (name: string) => string,
): Step[] {
  const guests = (
    name: string,
    files: string[],
    compiler: string,
    filter?: string,
  ): Step => ({
    name,
    command: testCommand(files, compiler, selection.jobs, filter, junit(name)),
    guests: files,
  });
  if (selection.mode === "development") {
    let files = selection.files;
    if (!files.length) files = smokeFiles;
    return [
      { name: "development-build", command: buildCommand(true) },
      guests("focused-guests", files, developmentCompiler, selection.filter),
    ];
  }
  let files = selection.files;
  if (!files.length) files = ["tests/guest", "tests/host"];
  if (selection.mode === "guest") {
    return [guests("guests", files, releaseCompiler, selection.filter)];
  }
  const steps: Step[] = [{
    name: "harness",
    command: [
      Deno.execPath(),
      "test",
      "--allow-read",
      "--allow-write",
      "--allow-run",
      "--allow-env",
      "--fail-fast",
      ...harnessFiles,
    ],
  }, { name: "release-build", command: buildCommand(false) }];
  for (const [name, script] of referenceChecks) {
    steps.push({ name, command: ["python3", script] });
  }
  steps.push({
    name: "pack",
    command: [
      Deno.execPath(),
      "run",
      "--allow-read",
      "--allow-write=generated/compiler",
      "scripts/pack_native.ts",
    ],
  });
  // Files that failed last time run first, so a repeat failure is quick.
  if (selection.preflight.length) {
    steps.push(
      guests("preflight-regressions", selection.preflight, releaseCompiler),
    );
  }
  steps.push(guests("guests", files, releaseCompiler));
  return steps;
}

async function main() {
  const { values, positionals } = parseArgs({
    args: Deno.args,
    options: {
      dev: { type: "boolean", default: false },
      guest: { type: "boolean", default: false },
      jobs: { type: "string", default: "4" },
      filter: { type: "string" },
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
      "test:compiler [--jobs 1..4] [--preflight FILE]\n" +
        "test:compiler:dev [--filter NAME] [FILES...]\n" +
        "test:guest [--jobs 1..4] [--filter NAME] [FILES...]\n" +
        "All modes: [--budget-seconds N] [--phase-seconds N] [--heartbeat-seconds N] [--timings-dir PATH]\n" +
        "Development defaults to 600s in all; the full gate to 3600s in all and 1800s per phase.",
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
  if (!Number.isInteger(jobs) || jobs > 4) {
    throw new Error("--jobs must be 1 through 4");
  }
  // The optimized build alone takes seven minutes on a fast machine.
  let defaultBudget = 3600;
  let defaultPhase = 1800;
  if (values.dev) {
    defaultBudget = 600;
    defaultPhase = 600;
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
  if (!values.dev && !values.guest && (positionals.length || values.filter)) {
    throw new Error(
      "The full compiler gate cannot be filtered; use test:compiler:dev",
    );
  }
  for (const file of [...positionals, ...values.preflight ?? []]) {
    if (!file.endsWith(".test.ts")) {
      throw new Error(`Expected a test file: ${file}`);
    }
  }
  let mode: Selection["mode"] = "full";
  if (values.dev) mode = "development";
  if (values.guest) mode = "guest";
  const directory = resolve(root, values["timings-dir"]);
  await Deno.mkdir(directory, { recursive: true });
  const runDirectory = await Deno.makeTempDir({
    dir: directory,
    prefix: "run-",
  });
  const failurePath = resolve(directory, "recent-failures.json");
  const preflight = new Set<string>();
  if (mode === "full") {
    for (const file of await recentFailures(failurePath)) {
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
  }
  const report = {
    mode,
    jobs,
    budget_seconds: budget,
    phase_seconds: phaseBudget,
    started_at: new Date().toISOString(),
    wall_seconds: 0,
    success: false,
    active: [] as string[],
    phases: [] as Phase[],
  };
  const started = performance.now();
  const controller = new AbortController();
  const abort = () => controller.abort();
  Deno.addSignalListener("SIGINT", abort);
  if (Deno.build.os !== "windows") Deno.addSignalListener("SIGTERM", abort);
  const deadline = setTimeout(() => controller.abort("budget"), budget * 1000);
  const flush = async () => {
    report.wall_seconds = (performance.now() - started) / 1000;
    const temporary = resolve(directory, `timings.${Deno.pid}.tmp`);
    const contents = JSON.stringify(report, null, 2) + "\n";
    await Deno.writeTextFile(resolve(runDirectory, "timings.json"), contents);
    await Deno.writeTextFile(temporary, contents);
    await Deno.rename(temporary, resolve(directory, "timings.json"));
  };
  const junit = (name: string) => resolve(runDirectory, `${name}.junit.xml`);
  const steps = plan({
    mode,
    files: positionals,
    filter: values.filter,
    jobs,
    preflight: [...preflight],
  }, junit);
  // One build or gate at a time: they share the compiler's build directory.
  let lease: Awaited<ReturnType<typeof compilerLease>> | undefined;
  try {
    if (mode !== "guest") lease = await compilerLease(root);
    for (const step of steps) {
      if (controller.signal.aborted) {
        throw new Error("Compiler gate cancelled before " + step.name);
      }
      report.active.push(step.name);
      await flush();
      let result: Phase;
      try {
        result = await runPhase(
          step.name,
          step.command,
          runDirectory,
          root,
          { DENO_JOBS: String(jobs) },
          { seconds: phaseBudget, heartbeat, signal: controller.signal },
        );
        report.phases.push(result);
      } finally {
        report.active = report.active.filter((name) => name !== step.name);
        await flush();
      }
      if (step.guests) {
        let failed: string[] = [];
        try {
          failed = failedGuestFiles(
            await Deno.readTextFile(junit(step.name)),
            root,
          );
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) throw error;
        }
        if (failed.length || result.code === 0) {
          await Deno.writeTextFile(
            failurePath,
            JSON.stringify(failed, null, 2) + "\n",
          );
        }
      }
      if (result.code !== 0) {
        throw new Error(`${step.name} failed; logs: ${runDirectory}`);
      }
    }
    report.success = true;
  } finally {
    await lease?.[Symbol.asyncDispose]();
    clearTimeout(deadline);
    Deno.removeSignalListener("SIGINT", abort);
    if (Deno.build.os !== "windows") {
      Deno.removeSignalListener("SIGTERM", abort);
    }
    await flush();
    console.log(`Timing record: ${resolve(directory, "timings.json")}`);
  }
}

if (import.meta.main) await main();
