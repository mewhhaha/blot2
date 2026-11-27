import { strict as assert } from "node:assert";
import {
  developmentCompiler,
  releaseCompiler,
} from "../../scripts/build_compiler.ts";
import {
  harnessFiles,
  plan,
  referenceChecks,
  type Selection,
  smokeFiles,
  testCommand,
} from "../../scripts/test_compiler.ts";

const junit = (name: string) => `/logs/${name}.junit.xml`;
const selection = (overrides: Partial<Selection>): Selection => ({
  mode: "full",
  files: [],
  jobs: 4,
  preflight: [],
  ...overrides,
});
const script = new URL("../../scripts/test_compiler.ts", import.meta.url)
  .pathname;
async function rejected(...args: string[]) {
  const result = await new Deno.Command(Deno.execPath(), {
    args: ["run", "-A", script, ...args],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert.notEqual(result.code, 0);
  return new TextDecoder().decode(result.stderr);
}

Deno.test("the full gate tests its tooling, builds, checks the references, packs and runs every guest", () => {
  const steps = plan(selection({}), junit);
  assert.deepEqual(steps.map((step) => step.name), [
    "harness",
    "release-build",
    ...referenceChecks.map(([name]) => name),
    "pack",
    "guests",
  ]);
  const harness = steps[0].command;
  for (const file of harnessFiles) assert(harness.includes(file), file);
  assert.deepEqual(steps[1].command.slice(-1), ["--release"]);
  const guests = steps[steps.length - 1];
  assert.deepEqual(guests.guests, ["tests/guest", "tests/host"]);
  assert.deepEqual(guests.command.slice(-2), ["--", releaseCompiler]);
  assert(guests.command.includes("--parallel"));
  assert(guests.command.includes(junit("guests")));
});

Deno.test("every harness file and reference check of the gate exists", async () => {
  const root = new URL("../../", import.meta.url);
  for (const file of harnessFiles) await Deno.stat(new URL(file, root));
  for (const [, tool] of referenceChecks) await Deno.stat(new URL(tool, root));
  for (const file of smokeFiles) await Deno.stat(new URL(file, root));
});

Deno.test("recent failures run before the whole guest suite", () => {
  const steps = plan(
    selection({ preflight: ["tests/guest/a.test.ts"] }),
    junit,
  );
  const names = steps.map((step) => step.name);
  assert.equal(
    names.indexOf("preflight-regressions"),
    names.indexOf("guests") - 1,
  );
  assert.deepEqual(steps[names.indexOf("preflight-regressions")].guests, [
    "tests/guest/a.test.ts",
  ]);
});

Deno.test("guest mode runs only the guests, against the optimized compiler as it is", () => {
  const steps = plan(
    selection({
      mode: "guest",
      files: ["tests/guest/a.test.ts"],
      filter: "name",
      jobs: 1,
    }),
    junit,
  );
  assert.equal(steps.length, 1);
  assert.deepEqual(steps[0].guests, ["tests/guest/a.test.ts"]);
  assert(!steps[0].command.includes("--parallel"));
  assert.deepEqual(steps[0].command.slice(-5), [
    "--filter",
    "name",
    "tests/guest/a.test.ts",
    "--",
    releaseCompiler,
  ]);
});

Deno.test("development mode builds the debug compiler and runs the named files or the smoke files", () => {
  const smoke = plan(selection({ mode: "development" }), junit);
  assert.deepEqual(smoke.map((step) => step.name), [
    "development-build",
    "focused-guests",
  ]);
  assert.deepEqual(smoke[0].command.slice(-2), [
    "--output",
    developmentCompiler,
  ]);
  assert.deepEqual(smoke[1].guests, smokeFiles);
  assert.deepEqual(smoke[1].command.slice(-2), ["--", developmentCompiler]);
  const named = plan(
    selection({ mode: "development", files: ["tests/host/lsp.test.ts"] }),
    junit,
  );
  assert.deepEqual(named[1].guests, ["tests/host/lsp.test.ts"]);
});

Deno.test("the test command passes the compiler after the files", () => {
  assert.deepEqual(
    testCommand(["a.test.ts"], "squidc", 2, undefined, undefined).slice(-4),
    ["--parallel", "a.test.ts", "--", "squidc"],
  );
});

Deno.test("the full gate cannot be filtered, and modes do not combine", async () => {
  assert.match(await rejected("--filter", "name"), /cannot be filtered/);
  assert.match(
    await rejected("tests/guest/a.test.ts"),
    /cannot be filtered/,
  );
  assert.match(await rejected("--dev", "--guest"), /Choose --dev or --guest/);
  assert.match(await rejected("--guest", "notes.md"), /Expected a test file/);
  assert.match(await rejected("--jobs", "9"), /--jobs must be 1 through 4/);
});
