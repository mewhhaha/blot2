import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const universal = "const identity: forall [a] => a -> a = func value => return value\n";
const entries = `entry const whole = func (value: U32) => return identity value
entry const fraction = func (value: F32) => return identity value
`;


Deno.test("closed explicit universal functions execute independent U32 and F32 instances", async () => {
  let expected: Uint8Array | undefined;
  await compileAndRun(
    "const identity = func value => return value\n" + entries,
    (_guest, bytes) => {
      expected = bytes.slice();
    },
    { prelude: "none" },
  );
  await compileAndRun(universal + entries, (guest, bytes) => {
    assert.equal(guest.call("whole", 42), 42);
    assert.equal(guest.call("fraction", 3.25), 3.25);
    assert.deepEqual(bytes, expected);
  }, { prelude: "none" });
  await compileExpectedFailure(
    "const identity: forall [a] => a -> a = func value => return 42\n" + entries,
    "rank_mismatch",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("closed universal retained edits and failed revisions match fresh output", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
    entry,
    prelude: null,
  };
  const retained = await createZigProjectCompiler(options);
  const revisions = [
    universal + entries,
    universal + entries.replace("identity value", "identity 43"),
    universal.replace("func value => return value", "func value => return 42") + entries,
    universal + entries,
  ];
  try {
    for (const [index, source] of revisions.entries()) {
      const sources = { [entry]: source };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success && !expected.success) {
          assert.equal(index, 2, JSON.stringify(result));
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success);
        assert.notEqual(index, 2);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          let whole = 42;
          if (index === 1) whole = 43;
          assert.equal(guest.call("whole", 42), whole);
          assert.equal(guest.call("fraction", 3.25), 3.25);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
