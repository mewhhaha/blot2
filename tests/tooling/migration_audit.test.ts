import { strict as assert } from "node:assert";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  auditBatches,
  auditProject,
  demoteEntries,
  selectPaths,
} from "../../scripts/integration/migration_audit.ts";

Deno.test("migration overlays demote exports without altering names or bodies", () => {
  const source =
    "// io const ignored = 2\nio const answer = func () => return 42\nio let rows: Array U32 = #[]\n  io answer_named () => return 42\n";
  assert.equal(
    demoteEntries(source),
    "// io const ignored = 2\nconst answer = func () => return 42\nlet rows: Array U32 = #[]\n  func answer_named () => return 42\n",
  );
  assert.equal(demoteEntries(demoteEntries(source)), demoteEntries(source));
});

Deno.test("batched frontend coverage isolates rejections and never passes a failed or unscheduled file", async () => {
  const calls: string[][] = [];
  const outcomes = new Map<string, boolean>();
  const batches: { files: string[]; split: boolean }[] = [];
  const selected = [
    "a.sq",
    "bad.sq",
    "c.sq",
    "d.sq",
    "expected.sq",
    "unreached.sq",
  ];
  await assert.rejects(() =>
    auditBatches({
      selected,
      batchSize: 4,
      expectedFiles: new Set(["expected.sq"]),
      build: async (files) => {
        calls.push([...files]);
        if (files.includes("unreached.sq")) {
          throw new Error("transport stopped");
        }
        // c and d each pass but cannot share an import graph; bad never passes.
        const success = !files.includes("bad.sq") &&
          !files.includes("expected.sq") &&
          !(files.includes("c.sq") && files.includes("d.sq"));
        return { success, diagnostics: [] };
      },
      batch: async (batch) => {
        batches.push(batch);
      },
      result: async (files, result) => {
        for (const file of files) {
          assert.equal(
            outcomes.has(file),
            false,
            "A file has exactly one final outcome",
          );
          outcomes.set(file, result.success);
        }
      },
    }), /transport stopped/);
  assert.deepEqual([...outcomes], [
    ["a.sq", true],
    ["bad.sq", false],
    ["c.sq", true],
    ["d.sq", true],
    ["expected.sq", false],
  ]);
  assert.equal(outcomes.has("unreached.sq"), false);
  assert.ok(calls.some((files) => files.length === 4));
  assert.ok(batches.some((batch) => batch.split));
  assert.ok(
    calls.filter((files) => files.includes("expected.sq")).every((files) =>
      files.length === 1
    ),
  );
});

Deno.test("migration path selection respects directory boundaries", () => {
  const files = [
    "tests/a.sq",
    "tests/negative/b.sq",
    "test_support/c.sq",
  ];
  assert.deepEqual(selectPaths(files, ["tests/"]), files.slice(0, 2));
  assert.deepEqual(selectPaths(files, ["tests/a.sq"]), [files[0]]);
  assert.deepEqual(selectPaths(files, ["test"]), []);
});

Deno.test("frontend audit checks unused declarations and exact rejection expectations", async () => {
  const compilerRoot = resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../..",
  );
  const project = await Deno.makeTempDir({ prefix: "squid-migration-audit-" });
  try {
    const initialized = await new Deno.Command("git", {
      args: ["init", "--quiet", project],
    }).output();
    assert.equal(initialized.success, true);
    await Deno.writeTextFile(
      resolve(project, "pen.json"),
      JSON.stringify({
        compiler: { settings: { std: resolve(compilerRoot, "std") } },
      }),
    );
    await Deno.writeTextFile(
      resolve(project, "valid.sq"),
      "io answer () : U32 => return 42\n",
    );
    const invalid = "const unused: U32 = true\n";
    await Deno.writeTextFile(resolve(project, "invalid.sq"), invalid);
    await Deno.writeTextFile(resolve(project, "rejected.sq"), invalid);
    const report = await auditProject({
      project,
      paths: [],
      report: resolve(project, "report.json"),
      expectations: {
        "rejected.sq": {
          code: "type_mismatch",
          reason: "A Bool cannot initialize a U32.",
        },
      },
    });
    assert.equal(report.complete, true);
    assert.equal(report.passed, 1);
    assert.equal(report.expectedRejections, 1);
    assert.equal(report.unexpectedFailures, 1);
    assert.deepEqual(
      report.results.map(({ file, status }) => [file, status]),
      [["invalid.sq", "failed"], ["rejected.sq", "expected-rejection"], [
        "valid.sq",
        "passed",
      ]],
    );
  } finally {
    await Deno.remove(project, { recursive: true });
  }
});
