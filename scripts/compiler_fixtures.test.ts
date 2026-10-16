import { strict as assert } from "node:assert";
import {
  compilerFixtures,
  fixturesForGuestFiles,
  parseCompilerFixtures,
} from "./compiler_fixtures.ts";

Deno.test("fixture selection is explicit and rejects unknown names", () => {
  assert.deepEqual(parseCompilerFixtures(""), []);
  assert.deepEqual(parseCompilerFixtures("arena-fixture,arena-fixture"), [
    "arena-fixture",
  ]);
  assert.throws(
    () => parseCompilerFixtures("budget-fixture"),
    /Unknown compiler fixture/,
  );
});

Deno.test("guest dependencies select every runtime fixture and directories retain full coverage", () => {
  assert.deepEqual(fixturesForGuestFiles(["zig-native/tests/arena.test.ts"]), [
    "arena-fixture",
  ]);
  assert.deepEqual(
    fixturesForGuestFiles([
      "zig-native/tests/scoped_authority_runtime.test.ts",
    ]),
    ["shared-rc-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles(["zig-native/tests/list_runtime.test.ts"]),
    ["list-runtime-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles([
      "zig-native/tests/resource_retire_execution.test.ts",
    ]),
    ["resource-retire-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles([
      "zig-native/tests/cohort_runtime_execution.test.ts",
    ]),
    ["cohort-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles([
      "zig-native/tests/region_owner_publication_execution.test.ts",
    ]),
    ["region-owner-publication-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles(["zig-native/tests/task_context_execution.test.ts"]),
    ["task-context-fixture"],
  );
  assert.deepEqual(
    fixturesForGuestFiles(["zig-native/tests/primitive_execution.test.ts"]),
    [],
  );
  assert.deepEqual(
    fixturesForGuestFiles(["zig-native/tests/"]),
    compilerFixtures,
  );
});
