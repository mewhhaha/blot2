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
    "  let rows: Array U32 = #[]\n" +
    "  for i in 0..n:\n" +
    "    rows := @array.append self (v.a + 3)\n" +
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

Deno.test("retained syntax follows disk bytes, parser symbols and prelude edits", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const prelude = dir + "/prelude.blot";
  const first = dir + "/first.blot";
  const last = dir + "/last.blot";
  const operator =
    "func combine a -> b => return @u32.sub a b\n";
  const original =
    "func left () => return do:\n  let first = 10\n  return first\n";
  const stamp = new Date("2024-01-02T03:04:05Z");
  await Deno.writeTextFile(prelude, operator);
  await Deno.writeTextFile(
    entry,
    'import { left } from "./first"\nimport { right } from "./last"\n' +
      "entry func answer (): U32 => return combine (left () - right ()) 1\n",
  );
  await Deno.writeTextFile(first, original);
  await Deno.writeTextFile(
    last,
    "func right () => return do:\n  let first = 3\n  return { other: 99, first: first }.first\n",
  );
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
    await expect(6, 3);
    await Deno.writeTextFile(prelude, operator.replace("@u32.sub", "@u32.add"));
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

Deno.test("entry names can change while dependency fields and imported bindings keep their meanings", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  // The persistent checker starts at sixteen modules. Every hop contributes
  // to the executed answer, including the dependency that owns the host field.
  await Deno.writeTextFile(
    dir + "/m0.blot",
    "type Pair is data = $Pair { pad: U32, host: U32 }\n" +
      "func read () => return ($Pair { host: 7, pad: 99 }).host\n",
  );
  for (let i = 1; i <= 14; i++) {
    await Deno.writeTextFile(
      dir + "/m" + i + ".blot",
      'import * as prev from "./m' + (i - 1) +
        '"\nfunc read () => return prev.read ()\n',
    );
  }
  const body = (arg: string, expr: string) =>
    'import { read } from "./m14"\n' +
    "entry func answer (" + arg + ": U32): U32 => return " + expr + "\n";
  await Deno.writeTextFile(entry, body("host", "@u32.add host (read ())"));
  const options = {
    entry,
    executable: Deno.args[0],
    frontendWorkers: 8,
    prelude: null,
  };
  const session = await createZigProjectCompiler(options);
  let revision = 0;
  async function check(
    source: string,
    result: number | null,
    freshModules?: number,
  ) {
    const request = { sources: { [entry]: source } };
    const oracle = await createZigProjectCompiler({
      ...options,
      frontendWorkers: 1,
    });
    try {
      const actual = await session.build(request),
        expected = await oracle.build(request);
      assert.equal(actual.success, expected.success);
      if (result === null) {
        assert(!actual.success && !expected.success);
        assert.deepEqual(actual.diagnostics, expected.diagnostics);
        assert.equal(actual.revision, revision);
        return;
      }
      assert(actual.success && expected.success, JSON.stringify(actual));
      assert.equal(actual.revision, ++revision);
      assert.deepEqual(actual.bytes, expected.bytes);
      if (freshModules !== undefined) {
        assert.equal(actual.stats.freshModules, freshModules);
      }
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", 5), result);
      } finally {
        guest.dispose();
      }
    } finally {
      await oracle.dispose();
    }
  }
  try {
    await check(body("host", "@u32.add host (read ())"), 12, 16);
    await check(body("fresh_param", "@u32.add fresh_param (read ())"), 12, 1);
    await check(body("pad", "@u32.sub (read ()) pad"), 2, 1);
    await check(body("read", "read"), 5, 1);
    const extra = body("value", "@u32.add (extra ()) value") +
      "func extra () => return read ()\n";
    await check(extra, 12, 1);
    await check(extra.replace("func extra ()", "func extra ("), null);
    await check(body("unbound", "fresh_param"), null);
    await check(body("host", "@u32.add host (read ())"), 12, 1);
    await Deno.writeTextFile(dir + "/m0.blot", "func read () => return 17\n");
    await check(body("other", "@u32.add other (read ())"), 22);
  } finally {
    await session.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("an imported name change preserves earlier checks and rechecks callers", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const bridge = dir + "/bridge.blot";
  const leaf = dir + "/v0.blot";
  const initialLeaf = "type Pair is data = $Pair { first: U32, next: U32 }\n" +
    "func v0 () => return ($Pair { next: 7, first: 99 }).next\n";
  const initialBridge =
    'import { v0 } from "./v0"\nfunc bridge value => return @u32.add value (v0 ())\n';
  await Deno.writeTextFile(bridge, initialBridge);
  await Deno.writeTextFile(leaf, initialLeaf);
  const imports = ['import { bridge } from "./bridge"'];
  for (let i = 1; i < 16; i++) {
    await Deno.writeTextFile(
      dir + "/v" + i + ".blot",
      "func v" + i + " () => return " + i + "\n",
    );
    imports.push("import { v" + i + ' } from "./v' + i + '"');
  }
  await Deno.writeTextFile(
    entry,
    imports.join("\n") +
      "\nentry func answer (n: U32): U32 => return @u32.add (bridge n) (v15 ())\n",
  );
  const options = {
    entry,
    prelude: null,
    executable: Deno.args[0],
    frontendWorkers: 8,
  };
  const session = await createZigProjectCompiler(options);
  let revision = 0;
  async function compare(
    sources: Record<string, string>,
    want: number | null,
    fresh?: number,
  ) {
    const oracle = await createZigProjectCompiler({
      ...options,
      frontendWorkers: 1,
    });
    try {
      const actual = await session.build({ sources });
      const reference = await oracle.build({ sources });
      if (want === null) {
        assert(!actual.success && !reference.success);
        assert.deepEqual(actual.diagnostics, reference.diagnostics);
        assert.equal(actual.revision, revision);
        return;
      }
      assert(actual.success && reference.success, JSON.stringify(actual));
      assert.deepEqual(actual.bytes, reference.bytes);
      assert.equal(actual.revision, ++revision);
      if (fresh !== undefined) assert.equal(actual.stats.freshModules, fresh);
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", 2), want);
      } finally {
        guest.dispose();
      }
    } finally {
      await oracle.dispose();
    }
  }
  try {
    await compare({}, 24, 18);
    // Changing executable code with the same interface only checks its owner.
    const bodyEdit = initialLeaf.replace("next: 7", "next: 9");
    await compare({ [leaf]: bodyEdit }, 26, 1);
    // Its callers must still see a changed result type and reject the build.
    await compare({
      [leaf]: bodyEdit.replace("func v0 () => return ", "func v0 () => return @u32.eq 7 "),
    }, null);
    await compare({}, 24, 1);
    const renamed = initialBridge.replaceAll("value", "new_binding");
    await compare({ [bridge]: renamed }, 24, 2);
    await compare(
      { [bridge]: renamed.replace("(v0 ())", "(missing ())") },
      null,
    );
    await compare(
      {
        [bridge]: initialBridge.replace(
          "value => return @u32.add value (v0 ())",
          "v0 => return v0",
        ),
      },
      17,
      2,
    );
    await compare({
      [bridge]: renamed,
      [leaf]: initialLeaf.replace("next: 7", "next: 11"),
    }, 28);
    await Deno.writeTextFile(
      dir + "/other.blot",
      initialLeaf.replace("next: 7", "next: 8"),
    );
    await compare({ [bridge]: initialBridge.replace("./v0", "./other") }, 25);
    const small =
      'import { bridge } from "./bridge"\nentry func answer (n: U32): U32 => return bridge n\n';
    await compare({ [entry]: small }, 9, 3);
    await compare({}, 24);
  } finally {
    await session.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("an integer call argument can reuse a checked body across edits and rejection", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const dep = dir + "/numbers.blot";
  const numbers = "func sum (a: U32) -> (b: U32): U32 => return @u32.add a b\n";
  const imports = ['import * as numbers from "./numbers"'];
  for (let i = 0; i < 14; i++) {
    await Deno.writeTextFile(dir + "/d" + i + ".blot", "const marker = 1\n");
    imports.push("import * as d" + i + ' from "./d' + i + '"');
  }
  const source = imports.join("\n") +
    "\nentry func answer (): U32 => return do:\n" +
    "  let a = numbers.sum 64 17\n" +
    "  let b = numbers.sum 64 17\n" +
    "  return @u32.add a b\n";
  await Deno.writeTextFile(entry, source);
  await Deno.writeTextFile(dep, numbers);
  const options = {
    entry,
    prelude: null,
    executable: Deno.args[0],
    frontendWorkers: 8,
  };
  const session = await createZigProjectCompiler(options);
  let revision = 0;
  async function compare(
    text: string,
    want: number | null,
    reuse = false,
    dependency = numbers,
  ) {
    const request = { sources: { [entry]: text, [dep]: dependency } };
    const oracle = await createZigProjectCompiler({
      ...options,
      frontendWorkers: 1,
    });
    try {
      const actual = await session.build(request),
        fresh = await oracle.build(request);
      if (want === null) {
        assert(!actual.success && !fresh.success);
        assert.deepEqual(actual.diagnostics, fresh.diagnostics);
        assert.equal(actual.revision, revision);
        return;
      }
      assert(actual.success && fresh.success);
      assert.equal(actual.revision, ++revision);
      assert.deepEqual(actual.bytes, fresh.bytes);
      if (reuse) assert.equal(actual.stats.frontend.body_elaborations, 0);
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", null), want);
      } finally {
        guest.dispose();
      }
    } finally {
      await oracle.dispose();
    }
  }
  try {
    await compare(source, 162);
    const edit = source.replace("a = numbers.sum 64", "a = numbers.sum 65");
    await compare(edit, 163, true);
    await compare(edit, null, false, "func sum (a: Bool) -> (b: U32): U32 => return b\n");
    const tail = edit.replace("b = numbers.sum 64 17", "b = numbers.sum 64 99");
    await compare(tail, 245, true);
    await compare(tail.replace("65 17", "15 17"), 195, true); // Changes signed LEB width.
    await compare(source.replaceAll("64 17", "400 23"), 846);
    await compare(source, 162);
    const store = source.replace(
      "return @u32.add a b",
      "let lanes: Array U32 = #[0]\n  lanes[0] := a\n  return @u32.add lanes[0] b",
    );
    await compare(store, 162);
    await compare(store.replace("a = numbers.sum 64", "a = numbers.sum 65"), 163, true);
    const staged = source.replace("entry func answer", "func total") +
      "entry func answer (): U32 => return #run (total ())\n";
    await compare(staged, 162);
    await compare(staged.replace("a = numbers.sum 64", "a = numbers.sum 65"), 163, true);
  } finally {
    await session.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("retained structural replay handles panic nodes and skips wire_schema off the kernel dep cone", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const worker = dir + "/worker.blot";
  const kernelDep = dir + "/kernel_dep.blot";
  const baseWorker = [
    "private func check_inner (n: U32): U32 => return do:",
    "  if n == 0:",
    '    return @panic "zero input"',
    "  let acc: U32 = 0",
    "  for i in 0..n:",
    "    acc := @u32.add acc i",
    "  return acc",
    "func checked (n: U32): U32 => return check_inner n",
    "private func step_bonus (n: U32): U32 => return do:",
    "  let total: U32 = 0",
    "  for i in 0..n:",
    "    total := @u32.add total (@u32.add i 1)",
    "  return total",
    "func bonus (n: U32): U32 => return step_bonus n",
    "",
  ].join("\n");
  const baseKernelDep =
    "func scale (x: U32): U32 => return @u32.mul x 3\n";
  const dummyImports: string[] = [];
  for (let i = 0; i < 14; i++) {
    await Deno.writeTextFile(dir + `/d${i}.blot`, "const marker: U32 = 1\n");
    dummyImports.push(`import * as d${i} from "./d${i}"`);
  }
  const mainSource = [
    ...dummyImports,
    'import * as w from "./worker"',
    'import * as k from "./kernel_dep"',
    "entry kernel func kstep (x: U32): U32 => return k.scale x",
    "entry func answer (n: U32): U32 => return @u32.add (w.checked n) (w.bonus n)",
    "entry func run_k (x: U32): U32 => return k.scale x",
    "",
  ].join("\n");
  await Deno.writeTextFile(worker, baseWorker);
  await Deno.writeTextFile(kernelDep, baseKernelDep);
  await Deno.writeTextFile(entry, mainSource);
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    stdRoot: new URL("../../std/", import.meta.url).pathname,
    frontendWorkers: 8,
    profileBackend: true,
    profileTrace: true,
  };
  const session = await createZigProjectCompiler(options);
  try {
    const runAndCheck = async (
      sources: Record<string, string>,
      wantAnswer: number,
      wantKernel: number,
      expectWireSkipped: boolean,
    ) => {
      const actual = await session.build({ sources });
      assert(actual.success, JSON.stringify(actual));
      const events = session.profileProgress?.events ?? [];
      const latestBuild = events.reduce((m, e) => Math.max(m, e.build), 0);
      const sawWire = events.some(
        (e) =>
          e.build === latestBuild &&
          e.kind === "end" &&
          e.stage === "direct.wire_schema",
      );
      assert.equal(sawWire, !expectWireSkipped);
      const fresh = await createZigProjectCompiler(options);
      try {
        const oracle = await fresh.build({ sources });
        assert(oracle.success, JSON.stringify(oracle));
        assert.deepEqual(actual.bytes, oracle.bytes);
      } finally {
        await fresh.dispose();
      }
      const guest = await instantiateGuest(actual.bytes);
      try {
        assert.equal(guest.call("answer", 4), wantAnswer);
        assert.equal(guest.call("run_k", 5), wantKernel);
      } finally {
        guest.dispose();
      }
    };
    // Initial cold build: checked(4) = 0+1+2+3 = 6, bonus(4) = 1+2+3+4 = 10 -> 16; scale(5) = 15.
    await runAndCheck({}, 16, 15, false);
    // Structural edit in a module containing @panic, outside the kernel dep cone.
    const editedWorker = baseWorker.replace(
      "@u32.add i 1",
      "@u32.add (@u32.mul i 2) 1",
    );
    // bonus(4) = 1+3+5+7 = 16 -> 6+16 = 22.
    await runAndCheck({ [worker]: editedWorker }, 22, 15, true);
    // Comment-only edit in the same @panic module.
    await runAndCheck(
      { [worker]: editedWorker + "// trailing comment\n" },
      22,
      15,
      true,
    );
    // Changing the @panic message adds a new symbol / data bytes; fallback must still match oracle.
    await runAndCheck(
      { [worker]: editedWorker.replace("zero input", "must be nonzero") },
      22,
      15,
      false,
    );
    // Editing a module INSIDE the kernel dep cone must update kernel output and match oracle.
    await runAndCheck(
      {
        [worker]: baseWorker,
        [kernelDep]: "func scale (x: U32): U32 => return @u32.mul x 7\n",
      },
      16,
      35,
      false,
    );
    // Restore original sources.
    await runAndCheck(
      { [worker]: baseWorker, [kernelDep]: baseKernelDep },
      16,
      15,
      false,
    );
  } finally {
    await session.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});
