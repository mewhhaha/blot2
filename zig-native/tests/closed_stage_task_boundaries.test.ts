import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("staging splices reject a different callable usage shape before publication", async () => {
  const source = `const generated = @code.quote (fn (value: U32) => value)
const accepted = @code.quote ((fn (callback: U32 -> U32) => callback 42) (@code.splice generated))
entry const answer = fn () => @code.emit accepted
`;
  await compileAndRun(
    source,
    (guest) => assert.equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
  await compileExpectedFailure(
    source.replace("fn (value: U32)", "fn (value: unique U32)"),
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("staging lifts reject a live quantified type before code publication", async () => {
  await compileExpectedFailure(
    "const bad: forall [a] => a -> code [a, row {}] = fn value => @code.quote (@code.lift value)\n",
    "cross_stage_authority",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("task children cannot return group scoped callbacks or packages and recovery keeps accepted code", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-task-results-" });
  const entry = `${directory}/main.blot`;
  const accepted =
    "entry const answer = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => 42)))\n";
  const rejected = [
    {
      code: "task_escape",
      source: `const bad = fn () => @task.scope (fn group => do:
  let child = @task.spawn group (fn () => fn () => @task.join (@task.spawn group (fn () => 42)))
  break @task.join child)
`,
    },
    {
      code: "task_capture_transfer",
      source: `type Package = exists [a] => {value: a, apply: a -> U32}
const bad = fn () => @task.scope (fn group => do:
  let child = @task.spawn group (fn () => pack [U32] {value: 0, apply: fn (value: U32) => @task.join (@task.spawn group (fn () => value))} as Package)
  break @task.join child)
`,
    },
  ];
  await Deno.writeTextFile(entry, accepted);
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
    cacheDirectory: false,
  });
  try {
    const initial = await compiler.build();
    assert(initial.success, JSON.stringify(initial));
    const guest = await instantiateGuest(initial.bytes);
    try {
      for (const { source, code } of rejected) {
        const failed = await compiler.build({ sources: { [entry]: source } });
        assert(!failed.success);
        assert(
          failed.diagnostics.some((diagnostic) => diagnostic.code === code),
          JSON.stringify(failed),
        );
        assert.equal(guest.call("answer", null), 42);
        const corrected = await compiler.build({
          sources: { [entry]: accepted },
        });
        assert(corrected.success, JSON.stringify(corrected));
        assert.deepEqual(corrected.bytes, initial.bytes);
      }
    } finally {
      await guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
