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
      if (actual.success && expected.success) {
        assert.deepEqual(actual.bytes, expected.bytes);
      }
      if (!actual.success && !expected.success) {
        assert.deepEqual(actual.diagnostics, expected.diagnostics);
      }
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
    assert.equal(change.stats.relocatedOperands, 1);
    assert.equal(change.stats.freshModules, 1);
    assert.equal(change.stats.cachedModules, 2);
    const guest = await instantiateGuest(change.bytes);
    try {
      assert.equal(guest.call("answer", null), 17);
    } finally {
      guest.dispose();
    }
    const fail = await compare({
      sources: { [leaf]: edited.replace("false", "unknown") },
    });
    assert(!fail.success);
    assert.equal(fail.revision, change.revision);
    const recovered = await compare({ sources: { [leaf]: edited } });
    assert(recovered.success);
    assert.equal(recovered.revision, change.revision + 1);
    assert.equal(recovered.stats.freshModules, 0);
    const revert = await compare({});
    assert(revert.success);
    assert.equal(revert.stats.freshModules, 1);
    assert.deepEqual(revert.bytes, initial.bytes);
    const branch = "func lit () => return if true then s.look.sun else false";
    const middle = dir + "/middle.blot";
    await Deno.writeTextFile(
      middle,
      'import * as s from "./settings"\n' + branch + "\n",
    );
    const withBranch = await compare({});
    assert(withBranch.success);
    const reapply = await compare({ sources: { [leaf]: edited } });
    assert(reapply.success);
    assert.equal(reapply.stats.freshModules, 1);
    const body = await compare({
      sources: {
        [leaf]: edited,
        [middle]: 'import * as s from "./settings"\n' +
          branch.replace("if true", "if false") + "\n",
      },
    });
    assert(body.success);
    assert.equal(body.stats.freshModules, 2);
    assert.equal(body.stats.cachedModules, 1);
    const repeatedRoute = await compare({
      sources: {
        [leaf]: edited,
        [middle]: 'import * as s from "./settings"\n' +
          branch.replace("if true", "if false") + "\n",
      },
    });
    assert(repeatedRoute.success);
    assert.equal(repeatedRoute.stats.freshModules, 0);
    // Move declaration slots and change the type observed by a caller.
    await Deno.writeTextFile(
      leaf,
      "const first = 9\n" +
        base.replace("sun: Bool", "sun: U32").replace("sun: true", "sun: 9"),
    );
    const diskFailure = await compare({});
    assert(!diskFailure.success);
    assert.equal(diskFailure.revision, repeatedRoute.revision);
    await Deno.writeTextFile(leaf, "const first = 9\n" + edited);
    const moved = await compare({});
    assert(moved.success);
    assert.equal(moved.revision, repeatedRoute.revision + 1);
  } finally {
    await compiler.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("a function edit only invalidates its own callers when an independent initializer also changes", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const settings = dir + "/settings.blot";
  const tuning = dir + "/tuning.blot";
  const options = { executable: Deno.args[0], entry, prelude: null };
  await Deno.writeTextFile(settings, "const flag = true\n");
  await Deno.writeTextFile(tuning, "func tune () => return 9\n");
  await Deno.writeTextFile(
    dir + "/reader.blot",
    'import { flag } from "./settings"\nfunc enabled () => return flag\n',
  );
  await Deno.writeTextFile(
    entry,
    'import { enabled } from "./reader"\nimport { tune } from "./tuning"\n' +
      "entry func answer () => return if enabled () then 0 else tune ()\n",
  );
  const compiler = await createZigProjectCompiler(options);
  const fresh = await createZigProjectCompiler(options);
  try {
    const initial = await compiler.build({});
    assert(initial.success, JSON.stringify(initial));
    assert.equal(initial.stats.freshModules, 4);
    const request = {
      sources: {
        [settings]: "const flag = false\n",
        [tuning]: "func tune () => return 29\n",
      },
    };
    const [actual, expected] = await Promise.all([
      compiler.build(request),
      fresh.build(request),
    ]);
    assert(actual.success, JSON.stringify(actual));
    assert(expected.success, JSON.stringify(expected));
    assert.deepEqual(actual.bytes, expected.bytes);
    assert.equal(actual.stats.freshModules, 3);
    assert.equal(actual.stats.cachedModules, 1);
    const guest = await instantiateGuest(actual.bytes);
    try {
      assert.equal(guest.call("answer", null), 29);
    } finally {
      guest.dispose();
    }
  } finally {
    await Promise.all([compiler.dispose(), fresh.dispose()]);
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("scalar relocations follow committed edits and decline staged and width changes", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const values = dir + "/values.blot";
  const base = "const flag: Bool = true\nconst a: U32 = 7\nconst b: U32 = 13\n";
  const main = 'import * as v from "./values"\n' +
    "entry func answer (n: U32): U32 => return do:\n" +
    "  let rows: List U32 = []\n" +
    "  for i in 0..n:\n" +
    "    rows := @list.append self (v.a + 3)\n" +
    "  return rows.length + (if (#run v.flag) then v.a else v.b)\n" +
    "entry func selected (): U32 => return (#run (if v.flag then v.a else v.b))\n" +
    "entry func scale (): F32 => return 0.25\n";
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    stdRoot: new URL("../../std/", import.meta.url).pathname,
  };
  await Deno.writeTextFile(entry, main);
  await Deno.writeTextFile(values, base);
  const client = await createZigProjectCompiler(options);
  try {
    const first = await client.build();
    assert(first.success);
    const withA = base.replace("= 7", "= 19");
    const withB = withA.replace("= 13", "= 24");
    const off = withB.replace("= true", "= false");
    const wide = off.replace("= 24", "= 4096");
    const final = wide.replace("= 19", "= 16000").replace("4096", "4097");
    const loopEdit = main.replace("(v.a + 3)", "(v.a + 4)");
    const floatEdit = loopEdit.replace("0.25", "0.125");
    const cases: [string, number, boolean, string?][] = [
      [withA, 23, false],
      [withB, 23, true],
      [off, 28, false],
      [wide, 4100, false],
      [wide.replace("4096", "4097"), 4101, false],
      [wide.replace("= 19", "= 20").replace("4096", "4097"), 4101, true],
      [final, 4101, false],
      [final, 4101, true, loopEdit],
      [final, 4101, true, floatEdit],
    ];
    for (const [source, result, relocated, entrySource = main] of cases) {
      const request = { sources: { [values]: source, [entry]: entrySource } };
      const actual = await client.build(request);
      assert(actual.success, JSON.stringify(actual));
      if (relocated) assert(Number(actual.stats.relocatedOperands) > 0);
      else assert.equal(actual.stats.relocatedOperands, undefined);
      const fresh = await createZigProjectCompiler(options);
      try {
        const oracle = await fresh.build(request);
        assert(oracle.success);
        assert.deepEqual(actual.bytes, oracle.bytes);
      } finally {
        await fresh.dispose();
      }
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", 4), result);
        assert.equal(guest.call("selected", null), result - 4);
        let scale = 0.25;
        if (entrySource === floatEdit) scale = 0.125;
        assert.equal(guest.call("scale", null), scale);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await client.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("retained syntax follows disk bytes, parser symbols and inherited fixity", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const prelude = dir + "/prelude.blot";
  const first = dir + "/first.blot";
  const last = dir + "/last.blot";
  const operator =
    "infixl 60 (-) = sub\nfunc sub a -> b => return @u32.sub a b\n";
  const original =
    "func left () => return do:\n  let first = 10\n  return first\n";
  const stamp = new Date("2024-01-02T03:04:05Z");
  await Deno.writeTextFile(prelude, operator);
  await Deno.writeTextFile(
    entry,
    'import { left } from "./first"\nimport { right } from "./last"\n' +
      "entry func answer (): U32 => return left () - right () - 1\n",
  );
  await Deno.writeTextFile(first, original);
  await Deno.writeTextFile(last, "func right () => return 3\n");
  await Deno.utime(first, stamp, stamp);
  const options = {
    executable: Deno.args[0],
    entry,
    prelude,
    frontendWorkers: 1,
  };
  const client = await createZigProjectCompiler(options);
  async function expect(value: number, reused: number) {
    const oracle = await createZigProjectCompiler(options);
    try {
      const actual = await client.build();
      const fresh = await oracle.build();
      assert(actual.success, JSON.stringify(actual));
      assert(fresh.success);
      assert.deepEqual(actual.bytes, fresh.bytes);
      assert.deepEqual(actual.stats.sourceLoad, {
        sourceReads: 4,
        reusedSyntaxModules: reused,
      });
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", null), value);
      } finally {
        guest.dispose();
      }
    } finally {
      await oracle.dispose();
    }
  }
  try {
    await expect(6, 0);
    await expect(6, 4);
    await Deno.writeTextFile(first, original.replace("10", "20"));
    await Deno.utime(first, stamp, stamp);
    await expect(16, 3);
    // The edited local preserves the symbol count but changes a spelling.
    await Deno.writeTextFile(first, original.replaceAll("first", "other"));
    await expect(6, 2);
    await Deno.writeTextFile(prelude, operator.replace("infixl", "infixr"));
    await expect(8, 0);
    if (Deno.build.os !== "windows") {
      await Deno.rename(last, dir + "/three.blot");
      await Deno.symlink(dir + "/three.blot", last);
      await expect(8, 3);
      await Deno.writeTextFile(
        dir + "/five.blot",
        "func right () => return 5\n",
      );
      await Deno.remove(last);
      await Deno.symlink(dir + "/five.blot", last);
      await expect(6, 3);
    }
  } finally {
    await client.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});
