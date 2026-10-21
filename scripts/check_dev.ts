import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { type Phase, runPhase } from "./compiler_phase.ts";
import {
  fileDigest,
  inputDigest,
  nativeInputs,
} from "./compiler_gate_state.ts";
import { compilerLease } from "./compiler_lease.ts";
import { fixturesForGuestFiles } from "./compiler_fixtures.ts";
import {
  devCheckAreas,
  type NativeTestRecord,
  nativeTestRecords,
  verifyGuestResults,
  verifyNativeSelection,
} from "./dev_check_areas.ts";

const root = fileURLToPath(new URL("../", import.meta.url));

async function scriptInputs(directory: string): Promise<string[]> {
  const paths: string[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory) paths.push(...await scriptInputs(path));
    else if (entry.name.endsWith(".ts") || entry.name.endsWith(".json")) {
      paths.push(path);
    }
  }
  return paths;
}

async function main() {
  const started = performance.now();
  const { values } = parseArgs({
    args: Deno.args,
    options: {
      area: { type: "string", default: "static-sharing" },
      "budget-seconds": { type: "string", default: "300" },
      "timings-dir": { type: "string", default: "build/bench/check-dev" },
      help: { type: "boolean", default: false },
      "list-areas": { type: "boolean", default: false },
    },
  });
  if (values.help || values["list-areas"]) {
    console.log(
      "check:dev [--area NAME] [--list-areas] [--budget-seconds 300] [--timings-dir PATH]\nZig builds, complete native compilation, selected tests with sampled allocation faults, guests and local static checks. Full qualification stays pending.",
    );
    for (const [name, area] of Object.entries(devCheckAreas)) {
      console.log(
        `${name}: ${area.description} (${area.native.length} native laws, ${area.guests.length} guest files)`,
      );
    }
    return;
  }
  const area = Object.hasOwn(devCheckAreas, values.area)
    ? devCheckAreas[values.area as keyof typeof devCheckAreas]
    : undefined;
  if (!area) throw new Error(`Unknown development area: ${values.area}`);
  const budget = Number(values["budget-seconds"]);
  if (!Number.isFinite(budget) || budget <= 0 || budget > 300) {
    throw new Error("Development budget must be between 0 and 300 seconds");
  }
  const directory = resolve(root, values["timings-dir"]!);
  await Deno.mkdir(directory, { recursive: true });
  const runDirectory = await Deno.makeTempDir({
    dir: directory,
    prefix: "run-",
  });
  const report = {
    started_at: new Date().toISOString(),
    area: values.area,
    area_description: area.description,
    backend: "noLLVM",
    deno_runtime: Deno.version,
    allocation_failures: "sampled",
    budget_seconds: budget,
    wall_seconds: 0,
    success: false,
    outcome: "incomplete",
    error: null as string | null,
    qualifies_release: false,
    pending: [
      "Full native execution with exhaustive allocation failures",
      "Full guest/client suite and CI analyzers",
      "LLVM release and performance qualification",
    ],
    input_digest: "",
    compiler_sha256: "",
    native_binary_sha256: "",
    compiled_native_tests: 0,
    selected_native_tests: [...area.native] as string[],
    guest_files: [...area.guests],
    guest_filters: area.guestFilters,
    guest_tests: [] as { name: string; file: string }[],
    native_tests: [] as NativeTestRecord[],
    phases: [] as Phase[],
    identity_timings: [] as { name: string; wall_seconds: number }[],
    overhead_seconds: 0,
  };
  const identify = async <T>(name: string, action: () => Promise<T>) => {
    const start = performance.now();
    try {
      return await action();
    } finally {
      report.identity_timings.push({
        name,
        wall_seconds: (performance.now() - start) / 1000,
      });
    }
  };
  const controller = new AbortController();
  const abort = () => controller.abort("cancelled");
  Deno.addSignalListener("SIGINT", abort);
  if (Deno.build.os !== "windows") Deno.addSignalListener("SIGTERM", abort);
  const deadline = setTimeout(() => controller.abort("budget"), budget * 1000);
  const phase = async (
    name: string,
    args: string[],
    seconds: number,
    cwd = root,
  ) => {
    if (controller.signal.aborted) {
      throw new Error(
        "Development check incomplete: time budget or cancellation",
      );
    }
    const remaining = budget - (performance.now() - started) / 1000;
    if (remaining <= 0 || seconds <= 0) {
      throw new Error("Development check exceeded its time budget");
    }
    const result = await runPhase(name, args, runDirectory, cwd, {}, {
      seconds: Math.min(seconds, remaining),
      heartbeat: 15,
      signal: controller.signal,
    });
    report.phases.push(result);
    if (result.code !== 0) {
      if (result.stopped) report.outcome = "incomplete";
      else report.outcome = "failed";
      console.error(
        (await Deno.readTextFile(result.stderr)).split("\n").slice(-25).join(
          "\n",
        ),
      );
      throw new Error(`${name}: exit ${result.code}; logs: ${runDirectory}`);
    }
    return result;
  };
  try {
    await using lease = await compilerLease(root);
    const inputs = async () => [
      ...await nativeInputs(root),
      ...await scriptInputs(resolve(root, "compiler")),
      ...await scriptInputs(resolve(root, "scripts")),
      ...await scriptInputs(resolve(root, "zig-native/tests")),
      ...area.guests.map((path) => resolve(root, path)),
      ...[
        "scripts/check_dev.ts",
        "scripts/dev_check_areas.ts",
        "scripts/build_compiler.ts",
        "deno.json",
        "deno.lock",
      ].map((path) => resolve(root, path)),
    ];
    report.input_digest = await identify(
      "initial-inputs",
      async () => inputDigest(await inputs()),
    );
    const version = await phase("zig-version", ["zig", "version"], 5);
    if ((await Deno.readTextFile(version.stdout)).trim() !== "0.17.0") {
      throw new Error("Development checks require Zig 0.17.0");
    }
    // The 90-second build target is advisory; cold builds may use spare test
    // time. The end-to-end deadline still enforces the complete 300s budget.
    const buildDeadline = performance.now() + 150_000;
    await phase("development-build", [
      Deno.execPath(),
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-run=zig",
      "scripts/build_compiler.ts",
      "--dev",
      `--fixtures=${fixturesForGuestFiles(area.guests).join(",")}`,
      "--jobs=2",
    ], (buildDeadline - performance.now()) / 1000);
    await phase(
      "native-compile",
      [
        "zig",
        "build",
        "test-compile",
        "-Doptimize=safe",
        "-Dllvm=false",
        "--prefix",
        "zig-out-native-dev",
        "-j2",
        "--summary",
        "all",
      ],
      (buildDeadline - performance.now()) / 1000,
      resolve(root, "zig-native"),
    );
    const binary = resolve(
      root,
      "zig-native/zig-out-native-dev/bin/blot-tests",
    );
    const inventory = await phase("native-inventory", [binary, "--list"], 5);
    const names = (await Deno.readTextFile(inventory.stdout)).trim().split(
      "\n",
    );
    if (
      names.length === 0 || new Set(names).size !== names.length ||
      area.native.some((name) => !names.includes(name))
    ) {
      throw new Error(
        "Compiled inventory is empty, duplicated or missing an area regression",
      );
    }
    report.compiled_native_tests = names.length;
    await identify("initial-executables", async () => {
      report.native_binary_sha256 = await fileDigest(binary);
      report.compiler_sha256 = await fileDigest(
        resolve(root, "zig-native/zig-out-dev/bin/blotc"),
      );
    });
    const native = await phase("native-run", [
      binary,
      "--allocation-failures=sampled",
      ...area.native.map((name) => `--test=${name}`),
    ], 90);
    report.native_tests = nativeTestRecords(
      await Deno.readTextFile(native.stderr),
    );
    verifyNativeSelection(report.native_tests, area.native, "sampled");
    const guestDeadline = performance.now() + 60_000;
    const guestCommand = [
      Deno.execPath(),
      "test",
      "--allow-read",
      "--allow-write",
      "--allow-run",
      "--allow-env=BLOT_CLIENT_TEST_AMBIENT",
      "--fail-fast",
    ];
    const guestPhase = async (
      name: string,
      files: string[],
      filter?: string,
    ) => {
      const junit = resolve(runDirectory, name + ".junit.xml");
      await phase(name, [
        ...guestCommand,
        "--junit-path",
        junit,
        ...(filter ? ["--filter", filter] : []),
        ...files,
        "--",
        "zig-native/zig-out-dev/bin/blotc",
      ], (guestDeadline - performance.now()) / 1000);
      report.guest_tests.push(
        ...verifyGuestResults(
          await Deno.readTextFile(junit),
          files,
          filter ? [filter] : undefined,
        ),
      );
    };
    const unfilteredGuests = area.guests.filter((file) =>
      !area.guestFilters[file]
    );
    if (unfilteredGuests.length) {
      await guestPhase("guest-smoke", unfilteredGuests);
    }
    for (
      const [index, [file, filter]] of Object.entries(area.guestFilters)
        .entries()
    ) {
      await guestPhase(`guest-selected-${index}`, [file], filter);
    }
    // Cold analyzer caches may use time saved by focused native/guest checks.
    const analysisDeadline = started + budget * 1000;
    const remainingAnalysis = () =>
      (analysisDeadline - performance.now()) / 1000;
    await phase("format", [
      Deno.execPath(),
      "fmt",
      "--check",
      "mod.ts",
      "deno.json",
      "compiler",
      "scripts",
      ".github",
    ], remainingAnalysis());
    await phase("types", [
      Deno.execPath(),
      "check",
      "mod.ts",
      "scripts/check_dev.ts",
      "scripts/test_compiler.ts",
      "compiler/zig_project_client.ts",
    ], remainingAnalysis());
    await phase(
      "zig-lint",
      [Deno.execPath(), "task", "lint:zig:dev"],
      remainingAnalysis(),
    );
    await identify("final-inputs-and-executables", async () => {
      if (
        report.input_digest !== await inputDigest(await inputs()) ||
        report.native_binary_sha256 !== await fileDigest(binary) ||
        report.compiler_sha256 !==
          await fileDigest(resolve(root, "zig-native/zig-out-dev/bin/blotc"))
      ) {
        throw new Error(
          "Inputs or executable changed during the check; results are stale",
        );
      }
    });
    if (
      controller.signal.aborted || performance.now() - started > budget * 1000
    ) {
      throw new Error(
        "Development check incomplete: end-to-end budget exceeded or cancelled",
      );
    }
    report.success = true;
    report.outcome = "passed";
  } catch (error) {
    report.error = String(error);
    throw error;
  } finally {
    clearTimeout(deadline);
    Deno.removeSignalListener("SIGINT", abort);
    if (Deno.build.os !== "windows") {
      Deno.removeSignalListener("SIGTERM", abort);
    }
    report.wall_seconds = (performance.now() - started) / 1000;
    report.overhead_seconds = report.wall_seconds -
      report.phases.reduce((total, phase) => total + phase.wall_seconds, 0) -
      report.identity_timings.reduce(
        (total, timing) => total + timing.wall_seconds,
        0,
      );
    if (!report.native_tests.length) {
      try {
        report.native_tests = nativeTestRecords(
          await Deno.readTextFile(
            resolve(runDirectory, "native-run.stderr.log"),
          ),
        );
      } catch { /* Unstarted or interrupted output. */ }
    }
    const text = JSON.stringify(report, null, 2) + "\n";
    await Deno.writeTextFile(resolve(runDirectory, "results.json"), text);
    await Deno.writeTextFile(resolve(directory, "results.json"), text);
    for (
      const record of [...report.native_tests].sort((a, b) =>
        b.duration_ns - a.duration_ns
      ).slice(0, 5)
    ) {
      console.log(`${(record.duration_ns / 1e9).toFixed(3)}s ${record.name}`);
    }
    console.log(
      `Development ${report.outcome}: ${
        report.wall_seconds.toFixed(2)
      }s. Report: ${
        resolve(runDirectory, "results.json")
      }\nFull qualification remains pending.`,
    );
  }
}

if (import.meta.main) await main();
