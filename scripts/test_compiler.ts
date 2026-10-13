import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

const root = fileURLToPath(new URL("../", import.meta.url));
const native = resolve(root, "zig-native");
const smokeFiles = [
  "zig-native/tests/zig_project_protocol.test.ts",
  "zig-native/tests/zig_project_client.test.ts",
  "zig-native/tests/stage_chain_budget.test.ts",
];

type Phase = {
  name: string;
  command: string[];
  wall_seconds: number;
  code: number;
  stdout: string;
  stderr: string;
  cache: string;
};
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

export function cacheStatus(name: string, stderr: string): string {
  let step = "";
  if (name === "native-compile") step = "compile test";
  if (name === "native-run") step = "run test";
  if (!step) return "not-applicable";
  for (const line of stderr.split("\n")) {
    if (!line.includes(step)) continue;
    if (/\bcached\b/.test(line)) return "hit";
    if (/\bsuccess\b|\bpass\b/.test(line)) return "miss";
  }
  return "unknown";
}

export async function runPhase(
  name: string,
  command: string[],
  directory: string,
  cwd = root,
  env: Record<string, string> = {},
): Promise<Phase> {
  await Deno.mkdir(directory, { recursive: true });
  const stdout = resolve(directory, `${name}.stdout.log`);
  const stderr = resolve(directory, `${name}.stderr.log`);
  const out = await Deno.open(stdout, {
    create: true,
    write: true,
    truncate: true,
  });
  const err = await Deno.open(stderr, {
    create: true,
    write: true,
    truncate: true,
  });
  console.log(`${name}: starting`);
  const started = performance.now();
  const child = new Deno.Command(command[0], {
    args: command.slice(1),
    cwd,
    env,
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const [status] = await Promise.all([
    child.status,
    child.stdout.pipeTo(out.writable),
    child.stderr.pipeTo(err.writable),
  ]);
  const phase = {
    name,
    command,
    wall_seconds: (performance.now() - started) / 1000,
    code: status.code,
    stdout,
    stderr,
    cache: cacheStatus(name, await Deno.readTextFile(stderr)),
  };
  console.log(
    `${name}: ${
      phase.wall_seconds.toFixed(2)
    }s, exit ${phase.code}, cache ${phase.cache}`,
  );
  return phase;
}

function testCommand(
  files: string[],
  compiler: string,
  jobs: number,
  filter?: string,
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
      filter: { type: "string" },
      "native-filter": { type: "string", multiple: true },
      "native-suite": { type: "string", default: "all" },
      "native-llvm": { type: "boolean", default: false },
      "oom-profile": { type: "boolean", default: false },
      "force-native": { type: "boolean", default: false },
      "timings-dir": { type: "string", default: "build/bench/iteration" },
      help: { type: "boolean", default: false },
    },
    allowPositionals: true,
  });
  if (values.help) {
    console.log(
      "test:compiler [--jobs 1..4] [--oom-profile] [--force-native] [--timings-dir PATH]\n" +
        "test:compiler:dev [--native-suite all|syntax|types|runtime] [--native-filter NAME] [--native-llvm] [--filter NAME] [FILES...]\n" +
        "test:guest [--jobs 1..4] [--filter NAME] [FILES...]",
    );
    return;
  }
  const jobs = Number(values.jobs);
  if (!Number.isInteger(jobs) || jobs < 1 || jobs > 4) {
    throw new Error("--jobs must be 1 through 4");
  }
  if (values.dev && values.guest) throw new Error("Choose --dev or --guest");
  if (values["native-llvm"] && !values.dev) {
    throw new Error("--native-llvm applies to development checks");
  }
  if (!["all", "syntax", "types", "runtime"].includes(values["native-suite"])) {
    throw new Error("--native-suite must be all, syntax, types or runtime");
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
  ) {
    throw new Error("Guest mode has no native tests");
  }
  for (const file of positionals) {
    if (!file.endsWith(".test.ts")) {
      throw new Error(`Expected a test file: ${file}`);
    }
  }
  const directory = resolve(root, values["timings-dir"]);
  const report = {
    mode: "full",
    native_suite: values["native-suite"],
    native_backend: "LLVM",
    jobs,
    started_at: new Date().toISOString(),
    wall_seconds: 0,
    success: false,
    phases: [] as Phase[],
    oom_profile: values["oom-profile"],
    oom_sweeps: 0,
    slowest_oom_sweeps: [] as Sweep[],
  };
  if (values.dev) report.mode = "development";
  if (values.guest) report.mode = "guest";
  const started = performance.now();
  const phase = async (
    name: string,
    command: string[],
    cwd = root,
    env: Record<string, string> = {},
  ) => {
    const result = await runPhase(name, command, directory, cwd, env);
    report.phases.push(result);
    if (name === "native-run" && values["oom-profile"]) {
      const stderr = await Deno.readTextFile(result.stderr);
      if (stderr.includes("BLOT_OOM_PROFILE_ERROR\t")) {
        throw new Error("Native laws ran, but OOM timing output is incomplete");
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
    if (result.code !== 0) {
      const text = (await Deno.readTextFile(result.stdout)) +
        (await Deno.readTextFile(result.stderr));
      console.error(text.split("\n").slice(-50).join("\n"));
      throw new Error(`${name} failed; logs: ${directory}`);
    }
  };
  const build = (dev: boolean) => {
    const args = [
      Deno.execPath(),
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-run=zig",
      "scripts/build_compiler.ts",
    ];
    if (dev) args.push("--dev");
    return args;
  };
  const nativeOptions = ["-Doptimize=safe", "--summary", "all"];
  if (values.dev && !values["native-llvm"]) {
    nativeOptions.push("-Dllvm=false", "-fincremental");
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
    if (!values.guest) {
      await phase("smoke-build", build(true));
      await phase(
        "smoke",
        testCommand(smokeFiles, "zig-native/zig-out-dev/bin/blotc", jobs),
        root,
        { DENO_JOBS: String(jobs) },
      );
    }
    if (values.dev) {
      if (values["native-filter"]?.length || values["native-suite"] !== "all") {
        await phase("native-compile", [
          "zig",
          "build",
          "test-compile",
          ...nativeOptions,
        ], native);
        await phase(
          "native-run",
          ["zig", "build", "test", ...nativeOptions],
          native,
        );
      }
      if (positionals.length || values.filter) {
        let files = positionals;
        if (!files.length) files = smokeFiles;
        await phase(
          "focused-guests",
          testCommand(
            files,
            "zig-native/zig-out-dev/bin/blotc",
            jobs,
            values.filter,
          ),
          root,
          { DENO_JOBS: String(jobs) },
        );
      }
    } else {
      if (!values.guest) {
        await phase("harness", [
          Deno.execPath(),
          "test",
          "--allow-read",
          "--allow-write",
          "--allow-run=zig,deno",
          "--allow-env=ZIG",
          "--fail-fast",
          "scripts/test_compiler.test.ts",
          "scripts/compiler_fingerprint.test.ts",
        ]);
        await phase("release-build", build(false));
        await phase("native-compile", [
          "zig",
          "build",
          "test-compile",
          ...nativeOptions,
        ], native);
        await phase(
          "native-run",
          ["zig", "build", "test", ...nativeOptions],
          native,
        );
      }
      await phase("pack", [
        Deno.execPath(),
        "run",
        "--allow-read",
        "--allow-write=generated/compiler",
        "scripts/pack_native.ts",
      ]);
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
      await phase(
        "guests",
        testCommand(files, "zig-native/zig-out/bin/blotc", jobs, values.filter),
        root,
        { DENO_JOBS: String(jobs) },
      );
    }
    report.success = true;
  } finally {
    report.wall_seconds = (performance.now() - started) / 1000;
    await Deno.mkdir(directory, { recursive: true });
    const destination = resolve(directory, "timings.json");
    await Deno.writeTextFile(
      destination,
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log(`Timing record: ${destination}`);
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
