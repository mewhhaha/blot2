import { strict as assert } from "node:assert";
import {
  createZigProjectCompiler,
  type ZigProjectBuildOptions,
} from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

Deno.test("project revisions recheck edited data, keep callers and recover from failed edits", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const leaf = dir + "/settings.blot";
  const base = "type Look is data = $Look { sun: Bool }\n" +
    "const look = $Look { sun: true }\n";
  const options = { executable: Deno.args[0], entry, prelude: null };
  const edited = base.replace("sun: true", "sun: false");
  await Deno.writeTextFile(leaf, base);
  await Deno.writeTextFile(
    dir + "/middle.blot",
    'import * as s from "./settings"\nfunc lit () => return s.look.sun\n',
  );
  await Deno.writeTextFile(
    entry,
    'import { lit } from "./middle"\nentry func answer () => return if lit () then 41 else 17\n',
  );
  const compiler = await createZigProjectCompiler(options);
  async function compare(request: ZigProjectBuildOptions) {
    const fresh = await createZigProjectCompiler(options);
    try {
      const actual = await compiler.build(request);
      const expected = await fresh.build(request);
      assert.equal(actual.success, expected.success);
      if (actual.success && expected.success) assert.deepEqual(actual.bytes, expected.bytes);
      if (!actual.success && !expected.success) assert.deepEqual(actual.diagnostics, expected.diagnostics);
      return actual;
    } finally {
      await fresh.dispose();
    }
  }
  try {
    const initial = await compare({});
    assert(initial.success, JSON.stringify(initial));
    assert.equal(initial.stats.freshModules, 3);
    const change = await compare({ sources: { [leaf]: edited } });
    assert(change.success, JSON.stringify(change));
    assert.equal(change.stats.freshModules, 1);
    assert.equal(change.stats.cachedModules, 2);
    const guest = await instantiateGuest(change.bytes);
    try {
      assert.equal(guest.call("answer", null), 17);
    } finally {
      guest.dispose();
    }
    const fail = await compare({ sources: { [leaf]: edited.replace("false", "unknown") } });
    assert(!fail.success);
    assert.equal(fail.revision, change.revision);
    const recovered = await compare({ sources: { [leaf]: edited } });
    assert(recovered.success);
    assert.equal(recovered.revision, change.revision + 1);
    const revert = await compare({});
    assert(revert.success);
    assert.equal(revert.stats.freshModules, 0);
    assert.deepEqual(revert.bytes, initial.bytes);
    const branch = "func lit () => return if true then s.look.sun else false";
    const middle = dir + "/middle.blot";
    await Deno.writeTextFile(middle, 'import * as s from "./settings"\n' + branch + "\n");
    const withBranch = await compare({});
    assert(withBranch.success);
    const body = await compare({ sources: { [middle]: 'import * as s from "./settings"\n' +
      branch.replace("if true", "if false") + "\n" } });
    assert(body.success);
    assert.equal(body.stats.freshModules, 2);
    assert.equal(body.stats.cachedModules, 1);
    // Move declaration slots and change the type observed by a caller.
    await Deno.writeTextFile(leaf, "const first = 9\n" + base.replace("sun: Bool", "sun: U32").replace("sun: true", "sun: 9"));
    const diskFailure = await compare({});
    assert(!diskFailure.success);
    assert.equal(diskFailure.revision, body.revision);
    await Deno.writeTextFile(leaf, "const first = 9\n" + edited);
    const moved = await compare({});
    assert(moved.success);
    assert.equal(moved.revision, body.revision + 1);
  } finally {
    await compiler.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});
