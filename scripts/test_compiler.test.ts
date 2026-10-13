import { strict as assert } from "node:assert";
import { cacheStatus, runPhase, sweepTimings } from "./test_compiler.ts";

Deno.test("full compiler gates reject partial native suites before building", async () => {
  for (
    const args of [
      ["--native-suite", "syntax"],
      ["--native-filter", "canonical"],
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
