import {
  deepStrictEqual as equal,
  match,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runCli } from "../../host/cli.ts";
import {
  createCompiler,
  decodeTestReport,
  discoverTestModules,
  encodeText,
  formatGuestTrap,
  formatTestRunReport,
  GuestError,
  guestTrapOf,
  instantiateGuest,
  readTestMetadata,
  readTrapMetadata,
  resolveProject,
  runSquidTests,
  TEST_REPORT_MAGIC,
  TEST_REPORT_VERSION,
  type TestFailure,
  type TestRunReport,
  TRAP_SITE_OFFSET,
} from "../../mod.ts";

const executable = Deno.args.at(0) ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url);

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
      const data = [...utf8("squid:tests"), ...payload];
      return [0, ...leb(data.length), ...data];
    }),
  );
}

Deno.test("squid:tests metadata keeps wire order, kinds, UTF-8 and u32 lines", () => {
  const name = "check 🌱".repeat(24);
  const bytes = wasmWithTests([
    1,
    2,
    0,
    ...utf8("generated_check"),
    ...utf8(name),
    ...utf8("prüfung.sq"),
    ...leb(128),
    1,
    ...utf8("generated_trap"),
    ...utf8("trap"),
    ...utf8("é.sq"),
    ...leb(0xFFFF_FFFF),
  ]);
  equal(readTestMetadata(new WebAssembly.Module(bytes)), [
    {
      kind: "check",
      exportName: "generated_check",
      displayName: name,
      filename: "prüfung.sq",
      line: 128,
    },
    {
      kind: "trap",
      exportName: "generated_trap",
      displayName: "trap",
      filename: "é.sq",
      line: 0xFFFF_FFFF,
    },
  ]);
  equal(readTestMetadata(wasmWithTests()), undefined);
  equal(readTestMetadata(wasmWithTests([1, 0])), []);
});

Deno.test("squid:tests rejects malformed sections", () => {
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

const unit = "io test_unit (): Unit => return ()\n";
const infiniteLoop = `io test_a_loop (): Unit =>
  for ever:
    continue
  return ()
`;

Deno.test("directory discovery selects first-class tests and rejection fixtures", () =>
  temporary(async (root) => {
    const plain = await write(root, "src/plain.sq", 'test "check" => true\n');
    const trap = await write(
      root,
      "src/trap.sq",
      'test expect_trap "trap" => 1 / 0\n',
    );
    const tagged = await write(
      root,
      "src/tagged.sq",
      '@[test.suite]\ntest "tagged" => true\n',
    );
    const inline = await write(
      root,
      "src/inline.sq",
      '@[test.suite] test expect_trap "inline" => 1 / 0\n',
    );
    const rejected = await write(
      root,
      "src/reject.sq",
      "// rejects: unknown_value\nconst value = missing\n",
    );
    const helper = await write(
      root,
      "src/helper.sq",
      'const test = "helper"\n// test "comment" => true\n',
    );
    equal(await discoverTestModules({ root, paths: ["src"] }), [
      { path: inline, kind: "checks" },
      { path: plain, kind: "checks" },
      { path: rejected, kind: "rejected", expectedRejection: "unknown_value" },
      { path: tagged, kind: "checks" },
      { path: trap, kind: "checks" },
    ]);
    equal(await discoverTestModules({ root, paths: [helper] }), [
      { path: helper, kind: "checks" },
    ]);
  }));

Deno.test({
  name: "test mode follows compiler help for session and direct builds",
  ignore: Deno.build.os === "windows",
  fn: () =>
    temporary(async (root) => {
      const paths = await Promise.all([
        write(root, "first.sq", unit),
        write(root, "second.sq", unit),
      ]);
      const log = join(root, "calls");
      const native = executable instanceof URL
        ? fileURLToPath(executable)
        : executable;
      const quote = (value: string) =>
        "'" + value.replaceAll("'", "'\\''") + "'";
      for (const supported of [true, false]) {
        // Record the flag and delegate without it so the fixture also runs
        // against an older compiler. Exercise help emitted on stderr.
        const wrapper = await write(
          root,
          "compiler",
          `#!/bin/sh
if [ "$1" = --help ]; then
  printf '%s\\n' ${supported ? "--test" : "--testing"} >&2
  exit 0
fi
mode=off
for arg do
  shift
  if [ "$arg" = --test ]; then
    mode=on
  else
    set -- "$@" "$arg"
  fi
done
printf '%s %s\\n' "$1" "$mode" >> ${quote(log)}
exec ${quote(native)} "$@"
`,
        );
        await Deno.chmod(wrapper, 0o755);
        for (
          const [inputMode, command] of [
            ["project", "serve-project"],
            ["source", "build"],
          ] as const
        ) {
          await Deno.writeTextFile(log, "");
          const report = await runSquidTests({
            executable: wrapper,
            root,
            paths,
            inputMode,
            jobs: 1,
          });
          equal(
            [report.success, report.testsPassed],
            [true, 2],
            JSON.stringify(report),
          );
          equal(
            (await Deno.readTextFile(log)).trim().split("\n"),
            paths.map(() => `${command} ${supported ? "on" : "off"}`),
          );
        }
        if (supported) {
          await Deno.writeTextFile(log, "");
          equal(
            await runCli(wrapper, [
              "build",
              paths[0],
              join(root, "build.wasm"),
              "--test",
            ]),
            0,
          );
          equal(await Deno.readTextFile(log), "build on\n");
        }
      }
    }),
});

Deno.test("runner executes Unit, Bool and BTST checks and expected traps", () =>
  temporary(async (root) => {
    const path = await write(
      root,
      "checks.sq",
      `
${unit}
io test_true (): Bool => return true
io test_false (): Bool => return false
io test_report_ok (): #[U32] => return #[${packet(3, []).join(", ")}]
io test_report_bad (): #[U32] => return #[${
        packet(2, [asciiFailure]).join(", ")
      }]
io test_empty_report (): #[U32] => return #[]
io test_traps (): Unit => return @panic "check failed"
io test_argument (value: U32): U32 => return value
io const test_scalar = 12
io test_return (): U32 => return 4
io trap_divide (): U32 => return @u32.div 1 0
io trap_returns (): U32 => return 42
`,
    );
    const report = await runSquidTests({
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
    equal(byName.test_traps.message, 'panic: "check failed"');
    equal(byName.test_traps.trap?.kind, "panic");
    equal(byName.test_traps.trap?.message, "check failed");
    const text = await formatTestRunReport(report);
    match(text, /arithmetic \/ addition \/ integer sum: values differ/);
    match(text, /expected: 42\s+actual: 41/);
  }));

Deno.test("default discovery classifies traps and rejections and skips helpers", () =>
  temporary(async (root) => {
    await write(root, "tests/helper.sq", "const value = 1\n");
    await write(root, "node_modules/ignored.test.sq", unit);
    await write(root, "app/sibling.test.sq", unit);
    const nested = await write(
      root,
      "tests/nested/sample.sq",
      'test "future syntax"\n',
    );
    await write(
      root,
      "tests/traps/divide.sq",
      "io test_divide (): U32 => return @u32.div 1 0\n",
    );
    const bad = "io demo (): Bool => return missing_value\n";
    await write(
      root,
      "tests/rejected/a_code.sq",
      "// rejects: unknown_value\n" + bad,
    );
    await write(
      root,
      "tests/rejected/b_message.sq",
      "// first comment\n\n// rejects: missing_value\n" + bad,
    );
    await write(
      root,
      "tests/rejected/c_compiles.sq",
      "// rejects: unknown_value\n" + unit,
    );
    await write(
      root,
      "tests/rejected/d_wrong.sq",
      "// rejects: unknown_type\n" + bad,
    );
    await write(root, "tests/rejected/e_missing.sq", bad);
    await write(
      root,
      "tests/rejection_marker.sq",
      "// rejects: unknown_value\n" + bad,
    );
    const report = await runSquidTests({ executable, root, jobs: 2 });
    equal(
      report.modules.map((
        { path, kind, tests },
      ) => [basename(path), kind, tests[0].status]),
      [
        ["sibling.test.sq", "checks", "passed"],
        ["a_code.sq", "rejected", "passed"],
        ["b_message.sq", "rejected", "passed"],
        ["c_compiles.sq", "rejected", "failed"],
        ["d_wrong.sq", "rejected", "failed"],
        ["e_missing.sq", "rejected", "failed"],
        ["rejection_marker.sq", "rejected", "passed"],
        ["divide.sq", "traps", "passed"],
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
      paths: ["tests/helper.sq"],
    });
    equal(helper.map(({ path }) => basename(path)), ["helper.sq"]);
    equal(
      await discoverTestModules({ root, paths: ["tests/nested"] }),
      [{ path: nested, kind: "checks" }],
    );
    const fromTrapDirectory = await discoverTestModules({
      root: join(root, "tests/traps"),
      paths: ["divide.sq"],
    });
    equal(fromTrapDirectory[0].kind, "traps");
    const filtered = await runSquidTests({
      executable,
      root,
      filter: "a_code",
    });
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
      "tests/a.sq",
      `io test_a_fails (): Bool => return false
io test_b_target (): Bool => return true
`,
    );
    await write(
      root,
      "tests/b.sq",
      "io test_other (): Bool => return unknown\n",
    );
    await write(
      root,
      "tests/c.sq",
      `${unit}// mentions target but has no matching export\n`,
    );
    const filtered = await runSquidTests({
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
    const unmatched = await runSquidTests({
      executable,
      root,
      filter: "unmatched",
    });
    equal([unmatched.success, unmatched.message], [
      false,
      "No tests matched filter",
    ]);
    const bailed = await runSquidTests({
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
    const empty = await runSquidTests({ executable, root: emptyRoot });
    equal([empty.success, empty.message], [false, "No test modules found"]);
  }));

Deno.test({
  name: "deadline terminates a non-yielding Wasm test and replaces its worker",
  sanitizeOps: true,
  sanitizeResources: true,
  fn: () =>
    temporary(async (root) => {
      const path = await write(root, "deadline.sq", infiniteLoop + unit);
      const report = await runSquidTests({
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
    await write(root, "library/squid-workspace.yaml", "exports:\n  .: ./src\n");
    await write(root, "library/src/value.sq", "const shared = 40\n");
    const app = join(root, "app");
    const paths = ["a/check.sq", "b/check.sq"];
    const manifest = {
      tests: { files: paths },
      dependencies: { math: { path: "../library" } },
    };
    await write(app, "squid.json", JSON.stringify(manifest));
    await write(
      app,
      "tests/ignored.sq",
      "io test_ignored (): Bool => return false\n",
    );
    await write(app, "a/helper.sq", "const local = 2\n");
    await write(app, "b/helper.sq", "const local = 3\n");
    for (const [index, path] of paths.entries()) {
      await write(
        app,
        path,
        `import { local } from "./helper"
import { shared } from "math/value"
io test_imports () => return @u32.eq (@u32.add shared local) ${42 + index}
`,
      );
    }
    equal((await resolveProject(join(app, paths[0])))?.tests, { files: paths });
    const report = await runSquidTests({
      executable,
      root: join(app, "a"),
      jobs: 2,
    });
    equal(
      [report.success, report.testsPassed],
      [true, 2],
      JSON.stringify(report),
    );

    await write(root, "override/value.sq", "const shared = 41\n");
    const override = await runSquidTests({
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
        [{ files: "check.sq" }, /must be an array/],
        [{ files: [""] }, /nonempty string/],
        [{ files: [42] }, /nonempty string/],
        [{ files: ["../check.sq"] }, /relative path/],
        [{ files: [`../${basename(root)}/check.sq`] }, /relative path/],
        [{ files: ["/check.sq"] }, /relative path/],
        [{ files: ["C:/check.sq"] }, /relative path/],
        [{ files: ["test\\check.sq"] }, /relative path/],
      ] as const
    ) {
      await write(root, "squid.json", JSON.stringify({ tests }));
      await rejects(() => resolveProject(join(root, "test.sq")), error);
    }
  }));

Deno.test("CLI emits a single JSON report under the squid task permissions", () =>
  temporary(async (root) => {
    const path = await write(root, "checks.sq", unit);
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
        "--allow-env=HOME,XDG_CACHE_HOME,SPM_CACHE_DIR",
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

function u32le(value: number): number[] {
  return [
    value & 0xff,
    (value >>> 8) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 24) & 0xff,
  ];
}

function wasmWithTraps(...payloads: number[][]): Uint8Array<ArrayBuffer> {
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
      const data = [...utf8("squid:traps"), ...payload];
      return [0, ...leb(data.length), ...data];
    }),
  );
}

Deno.test("squid:traps v1 decodes panic, bounds, and unreachable metadata and rejects malformed sections", () => {
  equal(TRAP_SITE_OFFSET, 772);
  equal(readTrapMetadata(wasmWithTraps()), undefined);
  equal(readTrapMetadata(wasmWithTraps([1, ...u32le(0)])), []);
  const utf8Msg = new TextEncoder().encode("audit: lost receipt 🧾");
  const boundsMsg = new TextEncoder().encode("index out of bounds");
  const bytes = wasmWithTraps([
    1,
    ...u32le(3),
    1,
    ...u32le(1),
    ...u32le(10),
    ...u32le(42),
    ...u32le(utf8Msg.length),
    ...utf8Msg,
    2,
    ...u32le(2),
    ...u32le(50),
    ...u32le(55),
    ...u32le(boundsMsg.length),
    ...boundsMsg,
    3,
    ...u32le(3),
    ...u32le(0),
    ...u32le(0),
    ...u32le(0),
  ]);
  const entries = readTrapMetadata(new WebAssembly.Module(bytes));
  equal(entries, [
    {
      kind: "panic",
      unit: 1,
      start: 10,
      end: 42,
      message: "audit: lost receipt 🧾",
    },
    {
      kind: "bounds",
      unit: 2,
      start: 50,
      end: 55,
      message: "index out of bounds",
    },
    {
      kind: "unreachable",
      unit: 3,
      start: 0,
      end: 0,
      message: "",
    },
  ]);
  equal(formatGuestTrap(entries![0]), 'panic: "audit: lost receipt 🧾"');
  equal(
    formatGuestTrap({ kind: "panic", unit: 0, start: 0, end: 0, message: "" }),
    "panic",
  );
  equal(formatGuestTrap(entries![1]), "index out of bounds");
  equal(
    formatGuestTrap({ kind: "bounds", unit: 0, start: 0, end: 0, message: "" }),
    "index out of bounds",
  );
  equal(formatGuestTrap(entries![2]), "unreachable");
  equal(
    formatGuestTrap({
      kind: "unreachable",
      unit: 0,
      start: 0,
      end: 0,
      message: "impossible branch",
    }),
    "unreachable: impossible branch",
  );

  const expectInvalidAbi = (pattern: RegExp) => (error: unknown) => {
    ok(error instanceof GuestError, String(error));
    equal(error.code, "invalid_abi");
    match(error.message, pattern);
    return true;
  };
  for (
    const [payload, pattern] of [
      [[], /Truncated/],
      [[1, 0, 0], /Truncated/],
      [[2, ...u32le(0)], /version/],
      [[1, ...u32le(1)], /Truncated/],
      [[1, ...u32le(1), 1, ...u32le(1), ...u32le(0)], /Truncated/],
      [
        [1, ...u32le(1), 0, ...u32le(1), ...u32le(0), ...u32le(0), ...u32le(0)],
        /kind/,
      ],
      [
        [1, ...u32le(1), 4, ...u32le(1), ...u32le(0), ...u32le(0), ...u32le(0)],
        /kind/,
      ],
      [
        [
          1,
          ...u32le(1),
          1,
          ...u32le(1),
          ...u32le(0),
          ...u32le(0),
          ...u32le(4),
          65,
          66,
        ],
        /Truncated/,
      ],
      [
        [
          1,
          ...u32le(1),
          1,
          ...u32le(1),
          ...u32le(0),
          ...u32le(0),
          ...u32le(1),
          0xff,
        ],
        /Invalid UTF-8/,
      ],
      [[1, ...u32le(0), 0], /Trailing/],
    ] as const
  ) {
    throws(
      () => readTrapMetadata(wasmWithTraps([...payload])),
      expectInvalidAbi(pattern),
    );
  }
  throws(
    () => readTrapMetadata(wasmWithTraps([1, ...u32le(0)], [1, ...u32le(0)])),
    expectInvalidAbi(/Duplicate/),
  );
});

Deno.test("squid test reports decoded panic and bounds traps with source line/col and keeps expect_trap passing", () =>
  temporary(async (root) => {
    const scalarPanicPath = await write(
      root,
      "scalar_panic.sq",
      `test "panics":
  @panic "audit: lost receipt"
`,
    );
    const mixedPath = await write(
      root,
      "traps_provenance.sq",
      `import * as test from "std/test"

test "out of bounds":
  let xs = #[10, 20, 30]
  let _ = xs[5]

test expect_trap "expected panic" => @panic "expected"

@[test.suite]
test "btst assertion location":
  use test.eq "expected sum" 42 41
`,
    );
    const report = await runSquidTests({
      executable,
      paths: [scalarPanicPath, mixedPath],
      jobs: 1,
    });
    equal(report.success, false);
    equal(report.testsPassed, 1, JSON.stringify(report));
    equal(report.testsFailed, 3, JSON.stringify(report));
    const byPath = Object.fromEntries(
      report.modules.map((mod) => [mod.path, mod]),
    );
    const panicTest = byPath[scalarPanicPath].tests[0];
    equal(panicTest.displayName, "panics");
    equal(panicTest.status, "failed");
    equal(panicTest.message, 'panic: "audit: lost receipt"');
    equal(panicTest.trap?.kind, "panic");
    equal(panicTest.trap?.message, "audit: lost receipt");
    equal(panicTest.trap?.filename, scalarPanicPath);
    equal(panicTest.trap?.line, 2);
    equal(panicTest.trap?.col, 3);

    const byDisplay = Object.fromEntries(
      byPath[mixedPath].tests.map((test) => [test.displayName, test]),
    );
    equal(byDisplay["expected panic"].status, "passed");

    const boundsTest = byDisplay["out of bounds"];
    equal(boundsTest.status, "failed");
    equal(boundsTest.message, "index out of bounds");
    equal(boundsTest.trap?.kind, "bounds");
    equal(boundsTest.trap?.filename, mixedPath);
    equal(boundsTest.trap?.line, 5);
    equal(boundsTest.trap?.col, 11);

    const formatted = await formatTestRunReport(report);
    match(
      formatted,
      /panic: "audit: lost receipt"\n    at .*scalar_panic\.sq:2:3/,
    );
    match(
      formatted,
      /index out of bounds\n    at .*traps_provenance\.sq:5:11/,
    );
    match(
      formatted,
      /expected sum: expected equal values\n      at .*traps_provenance\.sq:11\n      expected: 42\n      actual: 41/,
    );
  }));

Deno.test("repeated calls on the same guest after a trap never leak a stale trap ID", () =>
  temporary(async (root) => {
    const entry = await write(
      root,
      "trap_reuse.sq",
      `io first_panic (): U32 => return @panic "first panic"
io second_panic (): U32 => return @panic "second panic"
io div_zero (): U32 => return @u32.div 1 0
io ok_value (): U32 => return 42
`,
    );
    const compiler = await createCompiler({ executable, entry });
    try {
      const built = await compiler.build();
      ok(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        throws(
          () => guest.call("first_panic", null),
          (error: unknown) => {
            ok(error instanceof WebAssembly.RuntimeError, String(error));
            match(error.message, /^panic: "first panic" \(/);
            const trap = guestTrapOf(error);
            ok(trap);
            equal(trap.kind, "panic");
            equal(trap.message, "first panic");
            equal(
              (error as WebAssembly.RuntimeError & { squidTrap?: unknown })
                .squidTrap,
              trap,
            );
            ok(error.cause instanceof WebAssembly.RuntimeError);
            return true;
          },
        );
        // Unrecorded trap immediately after a recorded panic must not inherit the prior trap ID.
        throws(
          () => guest.call("div_zero", null),
          (error: unknown) => {
            ok(error instanceof WebAssembly.RuntimeError, String(error));
            equal(guestTrapOf(error), undefined);
            ok(!error.message.includes("first panic"), error.message);
            return true;
          },
        );
        equal(guest.call("ok_value", null), 42);
        throws(
          () => guest.call("second_panic", null),
          (error: unknown) => {
            ok(error instanceof WebAssembly.RuntimeError, String(error));
            equal(guestTrapOf(error)?.message, "second panic");
            return true;
          },
        );
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  }));
