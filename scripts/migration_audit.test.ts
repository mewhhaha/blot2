import { strict as assert } from "node:assert";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { auditProject, demoteEntries, selectPaths } from "./migration_audit.ts";

Deno.test("migration overlays demote exports without altering names or bodies", () => {
  const source =
    "// entry const ignored = 2\nentry const answer = func () => return 42\nentry let rows: ResizeArray U32 = #[]\n";
  assert.equal(
    demoteEntries(source),
    "// entry const ignored = 2\nconst answer = func () => return 42\nlet rows: ResizeArray U32 = #[]\n",
  );
  assert.equal(demoteEntries(demoteEntries(source)), demoteEntries(source));
});

Deno.test("migration path selection respects directory boundaries", () => {
  const files = [
    "tests/a.blot",
    "tests/negative/b.blot",
    "test_support/c.blot",
  ];
  assert.deepEqual(selectPaths(files, ["tests/"]), files.slice(0, 2));
  assert.deepEqual(selectPaths(files, ["tests/a.blot"]), [files[0]]);
  assert.deepEqual(selectPaths(files, ["test"]), []);
});

Deno.test("frontend audit checks unused declarations and exact rejection expectations", async () => {
  const compilerRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const project = await Deno.makeTempDir({ prefix: "blot-migration-audit-" });
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
      resolve(project, "valid.blot"),
      "entry const answer = func () : U32 => return 42\n",
    );
    const invalid = "const unused: U32 = true\n";
    await Deno.writeTextFile(resolve(project, "invalid.blot"), invalid);
    await Deno.writeTextFile(resolve(project, "rejected.blot"), invalid);
    const report = await auditProject({
      project,
      paths: [],
      report: resolve(project, "report.json"),
      expectations: {
        "rejected.blot": {
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
      [["invalid.blot", "failed"], ["rejected.blot", "expected-rejection"], [
        "valid.blot",
        "passed",
      ]],
    );
  } finally {
    await Deno.remove(project, { recursive: true });
  }
});
