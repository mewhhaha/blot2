import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { formatSource } from "../../host/format.ts";
import {
  createZigProjectCompiler,
  decodeTestReport,
  instantiateGuest,
  readGuestAbi,
  readTestMetadata,
  runBlotTests,
} from "../../mod.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
const stdRoot = fileURLToPath(new URL("../../std/", import.meta.url));
const prelude = fileURLToPath(
  new URL("../../std/prelude.blot", import.meta.url),
);

Deno.test("first-class test blocks are stripped in normal builds and emitted with blot:tests in --test mode", async () => {
  const dir = await Deno.makeTempDir();
  try {
    const prodOnly = `${dir}/prod_only.blot`;
    const withTests = `${dir}/with_tests.blot`;
    const prodSource = [
      "private func helper (x: U32): U32 => x * 2",
      "entry func prod (x: U32): U32 => helper x + 1",
      "",
    ].join("\n");
    const fullSource = [
      'import * as test from "std/test"',
      "",
      "private func helper (x: U32): U32 => x * 2",
      "entry func prod (x: U32): U32 => helper x + 1",
      "",
      "@[test.suite]",
      'test "private helper suite":',
      '  use test.eq "doubled" 10 (helper 5)',
      "",
      'test "bool shortcut" => helper 21 == 42',
      "",
      'test "unit fallthrough":',
      "  let _ = helper 3",
      "",
      'test expect_trap "bare panic" => panic "boom"',
      "",
    ].join("\n");
    await Deno.writeTextFile(prodOnly, prodSource);
    await Deno.writeTextFile(withTests, fullSource);

    // Format idempotence check on first-class test syntax too.
    const formatted = await formatSource(fullSource);
    equal(await formatSource(formatted), formatted);

    const normalProd = await createZigProjectCompiler({
      executable,
      entry: prodOnly,
      prelude,
      stdRoot,
    });
    const normalWithTests = await createZigProjectCompiler({
      executable,
      entry: withTests,
      prelude,
      stdRoot,
    });
    const testSession = await createZigProjectCompiler({
      executable,
      entry: withTests,
      prelude,
      stdRoot,
      testMode: true,
    });
    try {
      const bare = await normalProd.build();
      ok(bare.success, JSON.stringify(bare));
      const stripped = await normalWithTests.build();
      ok(stripped.success, JSON.stringify(stripped));
      equal(stripped.bytes, bare.bytes);
      equal(readTestMetadata(stripped.bytes), undefined);
      equal(
        readGuestAbi(new WebAssembly.Module(stripped.bytes)).functions.map((f) =>
          f.name
        ),
        ["prod"],
      );

      const built = await testSession.build();
      ok(built.success, JSON.stringify(built));
      const meta = readTestMetadata(built.bytes);
      equal(meta, [
        {
          kind: "check",
          exportName: "__blot_test_0",
          displayName: "private helper suite",
          filename: "",
          line: 7,
        },
        {
          kind: "check",
          exportName: "__blot_test_1",
          displayName: "bool shortcut",
          filename: "",
          line: 10,
        },
        {
          kind: "check",
          exportName: "__blot_test_2",
          displayName: "unit fallthrough",
          filename: "",
          line: 12,
        },
        {
          kind: "trap",
          exportName: "__blot_test_3",
          displayName: "bare panic",
          filename: "",
          line: 15,
        },
      ]);

      const guest = await instantiateGuest(built.bytes);
      try {
        equal(guest.call("prod", 4), 9);
        const packet = guest.call("__blot_test_0", null);
        ok(packet instanceof Uint32Array);
        equal(decodeTestReport(packet), { passed: 1, failed: 0, failures: [] });
        equal(guest.call("__blot_test_1", null), true);
        equal(guest.call("__blot_test_2", null), null);
      } finally {
        guest.dispose();
      }

      // Retained session updates blot:tests metadata on edit.
      const edited = fullSource.replace(
        '"private helper suite"',
        '"renamed suite"',
      );
      const rebuilt = await testSession.build({
        sources: { [withTests]: edited },
      });
      ok(rebuilt.success, JSON.stringify(rebuilt));
      equal(readTestMetadata(rebuilt.bytes)?.[0]?.displayName, "renamed suite");
    } finally {
      await normalProd.dispose();
      await normalWithTests.dispose();
      await testSession.dispose();
    }

    // End-to-end execution through runBlotTests (blot test).
    const report = await runBlotTests({
      executable,
      paths: [withTests],
      prelude,
      stdRoot,
    });
    equal(report.success, true, JSON.stringify(report));
    equal(report.testsPassed, 4);
    equal(report.testsFailed, 0);
    equal(
      report.modules[0].tests.map((t) => t.displayName),
      [
        "private helper suite",
        "bool shortcut",
        "unit fallthrough",
        "bare panic",
      ],
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("imported modules keep first-class tests private and contextual test/expect_trap stay identifiers", async () => {
  const dir = await Deno.makeTempDir();
  try {
    const lib = `${dir}/lib.blot`;
    const main = `${dir}/main.blot`;
    await Deno.writeTextFile(
      lib,
      [
        "func answer (): U32 => 42",
        'test "library internal check" => answer () == 42',
        "",
      ].join("\n"),
    );
    await Deno.writeTextFile(
      main,
      [
        'import * as lib from "./lib"',
        "const test = 40",
        "const expect_trap = 2",
        "entry func main (): U32 => lib.answer () + test - 40 + expect_trap - 2",
        "",
      ].join("\n"),
    );
    const compiler = await createZigProjectCompiler({
      executable,
      entry: main,
      prelude,
      stdRoot,
      testMode: true,
    });
    try {
      const built = await compiler.build();
      ok(built.success, JSON.stringify(built));
      equal(readTestMetadata(built.bytes), undefined);
      equal(
        readGuestAbi(new WebAssembly.Module(built.bytes)).functions.map((f) =>
          f.name
        ),
        ["main"],
      );
      const guest = await instantiateGuest(built.bytes);
      try {
        equal(guest.call("main", null), 42);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
