import {
  deepStrictEqual as equal,
  match,
  rejects,
  throws,
} from "node:assert/strict";
import { basename, dirname, join } from "node:path";
import { runCli } from "../../host/cli.ts";
import {
  decodeTestReport,
  discoverTestModules,
  encodeText,
  formatTestRunReport,
  readTestMetadata,
  resolveProject,
  runBlotTests,
  TEST_REPORT_MAGIC,
  TEST_REPORT_VERSION,
  type TestFailure,
  type TestRunReport,
} from "../../mod.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);

function packet(passed: number, failures: TestFailure[]) {
  return [
    TEST_REPORT_MAGIC,
    TEST_REPORT_VERSION,
    passed,
    failures.length,
    ...failures.flatMap(({ group, label, message, expected, actual }) =>
      [group, label, message, expected, actual].flatMap((field) => {
        const scalars = encodeText(field);
        return [scalars.length, ...scalars];
      })
    ),
  ];
}

const asciiFailure = {
  group: "arithmetic / addition",
  label: "integer sum",
  message: "values differ",
  expected: "42",
  actual: "41",
};

Deno.test("BTST v1 decodes multiple failures with Unicode scalar text", () => {
  const failures = [
    asciiFailure,
    {
      group: "λ",
      label: "誕生日🎂",
      message: "Zażółć",
      expected: "😀🪷",
      actual: "",
    },
  ];
  equal(TEST_REPORT_MAGIC, 1112822612);
  equal(decodeTestReport(Uint32Array.from(packet(12, failures))), {
    passed: 12,
    failed: 2,
    failures,
  });
});

Deno.test("BTST rejects malformed headers, records, scalars, and trailing data", () => {
  const words = packet(0, [asciiFailure]);
  throws(() => decodeTestReport(words.slice(0, 3)), /Truncated/);
  throws(() => decodeTestReport(words.slice(0, -1)), /Truncated/);
  throws(() => decodeTestReport([0, ...words.slice(1)]), /magic/);
  throws(() => decodeTestReport([words[0], 2, ...words.slice(2)]), /version/);
  throws(() => decodeTestReport([...words, 0]), /Trailing/);
  throws(() => decodeTestReport([words[0], 1, -1, 0]), /U32/);
  for (const scalar of [0xD800, 0x11_0000]) {
    throws(
      () => decodeTestReport([words[0], 1, 0, 1, 1, scalar, 0, 0, 0, 0]),
      /Unicode scalar/,
    );
  }
});

function leb(value: number): number[] {
  const bytes: number[] = [];
  while (value >= 128) {
    bytes.push((value % 128) | 128);
    value = Math.floor(value / 128);
  }
  return [...bytes, value];
}

function utf8(value: string): number[] {
  const bytes = new TextEncoder().encode(value);
  return [...leb(bytes.length), ...bytes];
}

function wasmWithTests(...payloads: number[][]): Uint8Array<ArrayBuffer> {
  return Uint8Array.of(
    0,
    97,
    115,
    109,
    1,
    0,
    0,
    0,
    ...payloads.flatMap((payload) => {
      const data = [...utf8("blot:tests"), ...payload];
      return [0, ...leb(data.length), ...data];
    }),
  );
}

Deno.test("blot:tests metadata keeps wire order, kinds, UTF-8 and u32 lines", () => {
  const name = "check 🌱".repeat(24);
  const bytes = wasmWithTests([
    1,
    2,
    0,
    ...utf8("generated_check"),
    ...utf8(name),
    ...utf8("prüfung.blot"),
    ...leb(128),
    1,
    ...utf8("generated_trap"),
    ...utf8("trap"),
    ...utf8("é.blot"),
    ...leb(0xFFFF_FFFF),
  ]);
  equal(readTestMetadata(new WebAssembly.Module(bytes)), [
    {
      kind: "check",
      exportName: "generated_check",
      displayName: name,
      filename: "prüfung.blot",
      line: 128,
    },
    {
      kind: "trap",
      exportName: "generated_trap",
      displayName: "trap",
      filename: "é.blot",
      line: 0xFFFF_FFFF,
    },
  ]);
  equal(readTestMetadata(wasmWithTests()), undefined);
  equal(readTestMetadata(wasmWithTests([1, 0])), []);
});

Deno.test("blot:tests rejects malformed sections", () => {
  for (
    const [payload, message] of [
      [[], /Truncated/],
      [[2, 0], /version/],
      [[1, 1], /Truncated/],
      [[1, 1, 2, 0, 0, 0, 0], /kind/],
      [[1, 1, 0, 8, 0, 0, 0], /Truncated UTF-8/],
      [[1, 1, 0, 1, 0xFF, 0, 0, 0], /Invalid UTF-8/],
      [[1, 0, 1], /Trailing/],
      [[1, 128, 128, 128, 128, 16], /LEB128/],
    ] as const
  ) {
    throws(() => readTestMetadata(wasmWithTests([...payload])), message);
  }
  throws(() => readTestMetadata(wasmWithTests([1, 0], [1, 0])), /Duplicate/);
});

async function temporary(test: (root: string) => Promise<void>) {
  const root = await Deno.makeTempDir();
  try {
    await test(root);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
}

async function write(
  root: string,
  file: string,
  text: string,
): Promise<string> {
  const path = join(root, file);
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, text);
  return path;
}

const unit = "entry func test_unit (): Unit => return ()\n";
const infiniteLoop = `entry func test_a_loop (): Unit =>
  for ever:
    continue
  return ()
`;

Deno.test("runner executes Unit, Bool and BTST checks and expected traps", () =>
  temporary(async (root) => {
    const path = await write(
      root,
      "checks.blot",
      `
${unit}
entry func test_true (): Bool => return true
entry func test_false (): Bool => return false
entry func test_report_ok (): #[U32] => return #[${packet(3, []).join(", ")}]
entry func test_report_bad (): #[U32] => return #[${
        packet(2, [asciiFailure]).join(", ")
      }]
entry func test_empty_report (): #[U32] => return #[]
entry func test_traps (): Unit => return @panic "check failed"
entry func test_argument (value: U32): U32 => return value
entry const test_scalar = 12
entry func test_return (): U32 => return 4
entry func trap_divide (): U32 => return @u32.div 1 0
entry func trap_returns (): U32 => return 42
`,
    );
    const report = await runBlotTests({
      executable,
      paths: [path],
      jobs: 2,
      release: true,
    });
    equal(report.success, false);
    equal(report.jobs, 2);
    equal(report.testsPassed, 4, JSON.stringify(report));
    equal(report.testsFailed, 8);
    equal([report.assertionsPassed, report.assertionsFailed], [8, 4]);
    const byName = Object.fromEntries(
      report.modules[0].tests.map((test) => [test.exportName, test]),
    );
    equal(byName.test_report_bad.failures, [asciiFailure]);
    match(byName.test_empty_report.message!, /Truncated BTST/);
    match(byName.test_argument.message!, /parameter must be Unit.*U32/);
    match(byName.test_return.message!, /Unsupported test return type U32/);
    match(byName.test_scalar.message!, /Expected a function export/);
    match(
      byName.trap_returns.message!,
      /Expected test to trap, but it returned normally/,
    );
    match(byName.test_traps.message!, /unreachable/);
    const text = await formatTestRunReport(report);
    match(text, /arithmetic \/ addition \/ integer sum: values differ/);
    match(text, /expected: 42\s+actual: 41/);
  }));

Deno.test("default discovery classifies traps and rejections and skips helpers", () =>
  temporary(async (root) => {
    await write(root, "tests/helper.blot", "const value = 1\n");
    await write(root, "node_modules/ignored.test.blot", unit);
    await write(root, "app/sibling.test.blot", unit);
    const nested = await write(
      root,
      "tests/nested/sample.blot",
      'test "future syntax"\n',
    );
    await write(
      root,
      "tests/traps/divide.blot",
      "entry func test_divide (): U32 => return @u32.div 1 0\n",
    );
    const bad = "entry func demo (): Bool => return missing_value\n";
    await write(
      root,
      "tests/rejected/a_code.blot",
      "// rejects: unknown_value\n" + bad,
    );
    await write(
      root,
      "tests/rejected/b_message.blot",
      "// first comment\n\n// rejects: missing_value\n" + bad,
    );
    await write(
      root,
      "tests/rejected/c_compiles.blot",
      "// rejects: unknown_value\n" + unit,
    );
    await write(
      root,
      "tests/rejected/d_wrong.blot",
      "// rejects: unknown_type\n" + bad,
    );
    await write(root, "tests/rejected/e_missing.blot", bad);
    await write(
      root,
      "tests/rejection_marker.blot",
      "// rejects: unknown_value\n" + bad,
    );
    const report = await runBlotTests({ executable, root, jobs: 2 });
    equal(
      report.modules.map((
        { path, kind, tests },
      ) => [basename(path), kind, tests[0].status]),
      [
        ["sibling.test.blot", "checks", "passed"],
        ["a_code.blot", "rejected", "passed"],
        ["b_message.blot", "rejected", "passed"],
        ["c_compiles.blot", "rejected", "failed"],
        ["d_wrong.blot", "rejected", "failed"],
        ["e_missing.blot", "rejected", "failed"],
        ["rejection_marker.blot", "rejected", "passed"],
        ["divide.blot", "traps", "passed"],
      ],
    );
    equal(
      report.modules[5].tests[0].message,
      "Missing leading // rejects: expectation",
    );
    equal(report.modules[4].tests[0].diagnostics?.[0].code, "unknown_value");
    match(await formatTestRunReport(report), /missing_value/);
    const helper = await discoverTestModules({
      root,
      paths: ["tests/helper.blot"],
    });
    equal(helper.map(({ path }) => basename(path)), ["helper.blot"]);
    equal(
      await discoverTestModules({ root, paths: ["tests/nested"] }),
      [{ path: nested, kind: "checks" }],
    );
    const fromTrapDirectory = await discoverTestModules({
      root: join(root, "tests/traps"),
      paths: ["divide.blot"],
    });
    equal(fromTrapDirectory[0].kind, "traps");
    const filtered = await runBlotTests({ executable, root, filter: "a_code" });
    equal([filtered.success, filtered.testsPassed, filtered.modules.length], [
      true,
      1,
      1,
    ]);
  }));

Deno.test("filter skips unrelated compilation and bail stops queued tests and modules", () =>
  temporary(async (root) => {
    await write(
      root,
      "tests/a.blot",
      `entry func test_a_fails (): Bool => return false
entry func test_b_target (): Bool => return true
`,
    );
    await write(
      root,
      "tests/b.blot",
      "entry func test_other (): Bool => return unknown\n",
    );
    await write(
      root,
      "tests/c.blot",
      `${unit}// mentions target but has no matching export\n`,
    );
    const filtered = await runBlotTests({
      executable,
      root,
      filter: "target",
      jobs: 2,
    });
    equal([filtered.success, filtered.testsPassed, filtered.modules.length], [
      true,
      1,
      1,
    ]);
    equal(filtered.modules[0].tests[0].exportName, "test_b_target");
    const unmatched = await runBlotTests({
      executable,
      root,
      filter: "unmatched",
    });
    equal([unmatched.success, unmatched.message], [
      false,
      "No tests matched filter",
    ]);
    const bailed = await runBlotTests({
      executable,
      root,
      bail: true,
      jobs: 1,
    });
    equal([bailed.testsPassed, bailed.testsFailed, bailed.modules.length], [
      0,
      1,
      1,
    ]);
    equal(bailed.modules[0].tests[0].exportName, "test_a_fails");
    const emptyRoot = join(root, "empty");
    await Deno.mkdir(emptyRoot);
    const empty = await runBlotTests({ executable, root: emptyRoot });
    equal([empty.success, empty.message], [false, "No test modules found"]);
  }));

Deno.test({
  name: "deadline terminates a non-yielding Wasm test and replaces its worker",
  sanitizeOps: true,
  sanitizeResources: true,
  fn: () =>
    temporary(async (root) => {
      const path = await write(root, "deadline.blot", infiniteLoop + unit);
      const report = await runBlotTests({
        executable,
        paths: [path],
        deadline: 0.15,
        jobs: 1,
      });
      equal(report.modules[0].tests.map(({ status }) => status), [
        "timeout",
        "passed",
      ]);
      match(report.modules[0].tests[0].message!, /Timeout after 0.15s/);
      match(await formatTestRunReport(report), /timeout test_a_loop/);
    }),
});

Deno.test("manifest discovery compiles each test with its own relative imports and package aliases", () =>
  temporary(async (root) => {
    await write(root, "library/blot-workspace.yaml", "exports:\n  .: ./src\n");
    await write(root, "library/src/value.blot", "const shared = 40\n");
    const app = join(root, "app");
    const paths = ["a/check.blot", "b/check.blot"];
    const manifest = {
      tests: { files: paths },
      dependencies: { math: { path: "../library" } },
    };
    await write(app, "blot.json", JSON.stringify(manifest));
    await write(
      app,
      "tests/ignored.blot",
      "entry func test_ignored (): Bool => return false\n",
    );
    await write(app, "a/helper.blot", "const local = 2\n");
    await write(app, "b/helper.blot", "const local = 3\n");
    for (const [index, path] of paths.entries()) {
      await write(
        app,
        path,
        `import { local } from "./helper"
import { shared } from "math/value"
entry const test_imports = func () => return shared + local == ${42 + index}
`,
      );
    }
    equal((await resolveProject(join(app, paths[0])))?.tests, { files: paths });
    const report = await runBlotTests({
      executable,
      root: join(app, "a"),
      jobs: 2,
    });
    equal(
      [report.success, report.testsPassed],
      [true, 2],
      JSON.stringify(report),
    );

    await write(root, "override/value.blot", "const shared = 41\n");
    const override = await runBlotTests({
      executable,
      root: app,
      paths: [paths[0]],
      imports: { "math/": join(root, "override") },
    });
    equal([override.success, override.testsFailed], [false, 1]);
  }));

Deno.test("manifest validates the tests object and confines its paths to the project", () =>
  temporary(async (root) => {
    for (
      const [tests, error] of [
        [null, /must be an object/],
        [{ extra: true }, /unknown field extra/],
        [{ files: "check.blot" }, /must be an array/],
        [{ files: [""] }, /nonempty string/],
        [{ files: [42] }, /nonempty string/],
        [{ files: ["../check.blot"] }, /relative path/],
        [{ files: [`../${basename(root)}/check.blot`] }, /relative path/],
        [{ files: ["/check.blot"] }, /relative path/],
        [{ files: ["C:/check.blot"] }, /relative path/],
        [{ files: ["test\\check.blot"] }, /relative path/],
      ] as const
    ) {
      await write(root, "blot.json", JSON.stringify({ tests }));
      await rejects(() => resolveProject(join(root, "test.blot")), error);
    }
  }));

Deno.test("CLI emits a single JSON report under the blot task permissions", () =>
  temporary(async (root) => {
    const path = await write(root, "checks.blot", unit);
    const cli = await write(
      root,
      "cli.ts",
      `
import { runCli } from ${
        JSON.stringify(new URL("../../host/cli.ts", import.meta.url).href)
      };
const [compiler, ...args] = Deno.args;
Deno.exitCode = await runCli(compiler.startsWith("file:") ? new URL(compiler) : compiler, args);
`,
    );
    const result = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        "--allow-write",
        "--allow-run",
        "--allow-env=HOME,XDG_CACHE_HOME,BPM_CACHE_DIR",
        cli,
        String(executable),
        "test",
        path,
        "--filter",
        "test_unit",
        "--json",
        "--release",
        "--jobs",
        "2",
        "--deadline",
        "2",
        "--prelude",
        "none",
        "--wasm3",
      ],
      cwd: new URL("../../", import.meta.url),
      stdout: "piped",
      stderr: "piped",
    }).output();
    const decoder = new TextDecoder();
    equal(result.code, 0, decoder.decode(result.stderr));
    const report: TestRunReport = JSON.parse(decoder.decode(result.stdout));
    equal([report.success, report.testsPassed, report.jobs], [true, 1, 2]);
    equal(await runCli(executable, ["test", path, "--filter", "missing"]), 1);
  }));

Deno.test("CLI rejects invalid test flags", async () => {
  for (
    const flags of [
      ["--unknown"],
      ["--jobs", "0"],
      ["--jobs", "1.5"],
      ["--deadline", "NaN"],
      ["--deadline", "-1"],
      ["--alias", "prefix"],
      ["--filter"],
      ["--input-mode", "bad"],
    ]
  ) {
    equal(await runCli(executable, ["test", ...flags]), 2);
  }
});
