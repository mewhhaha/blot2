import { strict as assert } from "node:assert";
import { cacheStatus, runPhase, sweepTimings } from "./test_compiler.ts";

async function simulatedGate(
  args: string[],
  options: {
    version?: string;
    failBuild?: boolean;
    guest?: boolean;
    preflight?: number;
  } = {},
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-scope-" });
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";
  try {
    const calls = `${directory}/zig-calls`;
    await Deno.writeTextFile(calls, "");
    const shim = `${directory}/zig`;
    let script = "#!/bin/sh\n" +
      `printf '%s\\n' CALL "$@" >> ${quote(calls)}\n` +
      'if [ "$1" = version ]; then\n' +
      `  printf '%s\\n' ${quote(options.version ?? "0.17.0-dev.123")}\n` +
      "  exit 0\nfi\n";
    if (options.failBuild) script += "exit 19\n";
    await Deno.writeTextFile(shim, script);
    await Deno.chmod(shim, 0o755);
    if (options.guest) {
      const guest = `${directory}/selected.test.ts`;
      let source =
        'Deno.test("selected guest", () => { if (Deno.args[0] !== "zig-native/zig-out-dev/bin/blotc") throw new Error("wrong compiler"); });\n';
      if (args.includes("--filter")) {
        source +=
          'Deno.test("excluded guest", () => { throw new Error("guest filter was ignored"); });\n';
      }
      await Deno.writeTextFile(
        guest,
        source,
      );
      args = [...args, guest];
    }
    if (options.preflight) {
      for (let index = 1; index < options.preflight; index++) {
        const file = `${directory}/passing-${index}.test.ts`;
        await Deno.writeTextFile(
          file,
          `Deno.test("passing ${index}", () => {});\n`,
        );
        args = [...args, "--preflight", file];
      }
      const file = `${directory}/recent-failure.test.ts`;
      await Deno.writeTextFile(
        file,
        'Deno.test("recent regression", () => { throw new Error("reproduce before LLVM"); });\n',
      );
      args = [...args, "--preflight", file];
    }
    const result = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        "--allow-write",
        "--allow-run",
        "--allow-env",
        "scripts/test_compiler.ts",
        "--timings-dir",
        `${directory}/timings`,
        ...args,
      ],
      env: { PATH: directory },
      stdout: "piped",
      stderr: "piped",
    }).output();
    const report = JSON.parse(
      await Deno.readTextFile(`${directory}/timings/timings.json`),
    );
    const commands = (await Deno.readTextFile(calls)).split("CALL\n")
      .slice(1).map((call) => call.trimEnd().split("\n"));
    return {
      code: result.code,
      stdout: new TextDecoder().decode(result.stdout),
      stderr: new TextDecoder().decode(result.stderr),
      report,
      commands,
    };
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

Deno.test("selected development native laws skip compiler builds and guests", async () => {
  const result = await simulatedGate([
    "--dev",
    "--native-suite",
    "types",
    "--native-filter",
    "staging law",
    "--native-filter",
    "usage law",
  ], { version: "0.17.0" });
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.report.success, true);
  assert.equal(result.report.native_backend, "noLLVM");
  assert.deepEqual(
    result.report.phases.map((phase: { name: string }) => phase.name),
    ["zig-version", "native-run"],
  );
  const options = [
    "-Doptimize=safe",
    "--summary",
    "all",
    "-j2",
    "-Dtest-shards=2",
    "-Dllvm=false",
    "-fincremental",
    "--prefix",
    "zig-out-native-dev",
    "-Dtest-suite=types",
    "-Dtest-filter=staging law",
    "-Dtest-filter=usage law",
  ];
  assert.deepEqual(result.commands, [
    ["version"],
    ["build", "test", ...options],
  ]);
  assert(
    result.report.phases.every((phase: { command: string[] }) =>
      phase.command[0] === "zig"
    ),
  );
});

Deno.test("native development selections preserve LLVM and forced execution options", async () => {
  const result = await simulatedGate([
    "--dev",
    "--native-filter",
    "ownership",
    "--native-llvm",
    "--force-native",
  ]);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.report.native_backend, "LLVM");
  for (const command of result.commands.slice(1)) {
    assert(command.includes("-Dtest-filter=ownership"));
    assert(command.includes("-Dtest-force-run=true"));
    assert(!command.includes("-Dllvm=false"));
    assert(!command.includes("-fincremental"));
  }
});

Deno.test("native-only development rejects incompatible Zig before building", async () => {
  for (const version of ["0.16.0", "0.17.01", "0.17.0garbage"]) {
    const result = await simulatedGate([
      "--dev",
      "--native-suite",
      "runtime",
    ], { version });
    assert.notEqual(result.code, 0);
    assert.equal(result.report.success, false);
    assert.match(result.stderr, /requires Zig 0\.17\.0/);
    assert.deepEqual(result.commands, [["version"]]);
    assert.deepEqual(
      result.report.phases.map((phase: { name: string }) => phase.name),
      ["zig-version"],
    );
  }
});

Deno.test("selected guests and combined development checks omit smoke", async () => {
  for (
    const [native, filtered] of [[false, false], [false, true], [true, true]]
  ) {
    const args = ["--dev", "--jobs", "1"];
    if (filtered) args.push("--filter", "selected guest");
    const phases = ["development-build"];
    if (native) {
      args.push("--native-suite", "syntax");
      phases.push("native-run");
    }
    phases.push("focused-guests");
    const result = await simulatedGate(args, { guest: true });
    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.report.success, true);
    assert.deepEqual(
      result.report.phases.map((phase: { name: string }) => phase.name),
      phases,
    );
    assert.deepEqual(result.commands[0], ["version"]);
    assert(result.commands[1].includes("install"));
    let commandCount = 2;
    if (native) commandCount = 3;
    assert.equal(result.commands.length, commandCount);
  }
});

Deno.test("guest filters build directly while default development and full gates retain smoke", async () => {
  for (
    const [args, name] of [
      [["--dev", "--filter", "selected"], "development-build"],
      [["--dev"], "smoke-build"],
      [[], "smoke-build"],
    ] as [string[], string][]
  ) {
    const result = await simulatedGate(args, { failBuild: true });
    assert.notEqual(result.code, 0);
    assert.equal(result.report.success, false);
    assert.deepEqual(
      result.report.phases.map((phase: { name: string }) => phase.name),
      [name],
    );
    assert.equal(result.report.phases[0].code, 19);
    assert.deepEqual(result.commands[0], ["version"]);
    assert(result.commands[1].includes("install"));
    assert.equal(result.commands.length, 2);
  }
});

Deno.test("full compiler gates reject all partial selections before building", async () => {
  for (
    const args of [
      ["--native-suite", "syntax"],
      ["--native-filter", "canonical"],
      ["--filter", "selected guest"],
      ["compiler/native.test.ts"],
    ]
  ) {
    const result = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        "scripts/test_compiler.ts",
        ...args,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.notEqual(result.code, 0);
    assert.match(
      new TextDecoder().decode(result.stderr),
      /full compiler gate cannot be filtered/,
    );
    assert.equal(result.stdout.length, 0);
  }
});

Deno.test("explicit preflight regressions are never truncated before release/native compilation", async () => {
  const result = await simulatedGate([], { preflight: 9 });
  assert.notEqual(result.code, 0);
  assert.equal(result.report.success, false);
  assert.deepEqual(
    result.report.phases.map((phase: { name: string }) => phase.name),
    ["smoke-build", "preflight-regressions"],
  );
  assert.match(result.stderr, /reproduce before LLVM/);
  assert.equal(result.commands.length, 2);
  assert(
    !result.commands.some((args: string[]) =>
      args.includes("-Doptimize=fast") || args.includes("test-compile")
    ),
  );
});

Deno.test("gate timings drain both pipes and preserve the command exit code", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-gate-timing-" });
  try {
    const result = await runPhase("failure", [
      Deno.execPath(),
      "eval",
      "const bytes = new Uint8Array(131072).fill(65); await Promise.all([Deno.stdout.write(bytes), Deno.stderr.write(bytes)]); Deno.exit(7);",
    ], directory);
    assert.equal(result.code, 7);
    assert.equal((await Deno.stat(result.stdout)).size, 131072);
    assert.equal((await Deno.stat(result.stderr)).size, 131072);
    assert(result.wall_seconds > 0);
    const success = await runPhase("warning", [
      Deno.execPath(),
      "eval",
      'console.error("failed command: warning from a successful test");',
    ], directory);
    assert.equal(success.code, 0);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("OOM timing records preserve failed sweeps and rank by elapsed time", () => {
  const rows = [
    {
      kind: "deterministic",
      duration_ns: 20,
      allocations: 4,
      runs: 5,
      completed: true,
      scenario: "small",
    },
    {
      kind: "concurrent",
      duration_ns: 80,
      allocations: 8,
      runs: 12,
      completed: false,
      scenario: "failed",
    },
  ];
  const log = "normal test output\n" +
    rows.map((row) => "BLOT_OOM_PROFILE\t" + JSON.stringify(row)).join("\n");
  const result = sweepTimings(log);
  assert.deepEqual(result.map((row) => row.scenario), ["failed", "small"]);
  assert.equal(result[0].completed, false);
  assert.throws(() => sweepTimings('BLOT_OOM_PROFILE\t{"duration_ns":-1}'));
});

Deno.test("native timing distinguishes cached compilation from executed tests", () => {
  const summary =
    "test success\n+- run test 1507 pass (1507 total) success 6m\n   +- compile test safe native-native cached 20ms MaxRSS:38M\n";
  assert.equal(cacheStatus("native-compile", summary), "hit");
  assert.equal(cacheStatus("native-run", summary), "miss");
  assert.equal(
    cacheStatus("native-run", "+- run test 3 pass (3 total) 1ms"),
    "miss",
  );
  assert.equal(
    cacheStatus("native-run", "test cached\n+- run test cached"),
    "hit",
  );
});
