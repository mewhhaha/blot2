import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const universal = "const identity: forall [a] => a -> a = fn value => value\n";
const entries = `entry const whole = fn (value: U32) => identity value
entry const fraction = fn (value: F32) => identity value
`;

const universalNumericSource =
    `const witness: forall [a] => (values: Array a) -> (index: U32) -> @proof.Index values index = fn values => fn index => @proof.index values index
const at: forall [a] => (values: Array a) -> (index: U32) -> (@proof.Index values index) -> a = fn values => fn index => fn proof => @array.get values index
entry const whole = fn (index: U32) => do:
  let values = #[8, 13]
  let proof = witness values index
  return at values index proof
entry const fraction = fn (index: U32) => do:
  let values = #[1.25, 3.5]
  let proof = witness values index
  return at values index proof
`;

Deno.test("closed universal numeric contracts preserve erased proof slots across element layouts", async () => {
  const source = universalNumericSource;
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0] ??
          new URL("../zig-out/bin/blotc", import.meta.url),
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes);
        try {
          assert.equal(guest.call("whole", 1), 13);
          assert.equal(guest.call("fraction", 1), 3.5);
          assert.throws(() => guest.call("whole", 2));
          assert.throws(() => guest.call("fraction", 4294967295));
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("closed universal numeric contracts reject forged slots and recover retained revisions", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url),
        entry, prelude: null, codegenTier, cacheDirectory: false,
      });
      try {
        const original = await compiler.build({ sources: { [entry]: universalNumericSource } });
        assert(original.success, JSON.stringify(original));
        for (const [source, code] of [
          [universalNumericSource.replaceAll("return at values index proof", "return at values index ()"), "proof_mismatch"],
          [universalNumericSource.replaceAll("return at values index proof", "let stored = #[proof]\n  return at values index proof"), "proof_runtime_use"],
          [universalNumericSource.replace("fn index => @proof.index values index", "fn index => @proof.index values (@u32.add index 1)"), "proof_mismatch"],
        ]) {
          const failed = await compiler.build({ sources: { [entry]: source } });
          assert(!failed.success, JSON.stringify(failed));
          assert(failed.diagnostics.some((diagnostic) => diagnostic.code === code), JSON.stringify(failed));
          const restored = await compiler.build({ sources: { [entry]: universalNumericSource } });
          assert(restored.success, JSON.stringify(restored));
          assert.deepEqual(restored.bytes, original.bytes);
          const guest = await instantiateGuest(restored.bytes);
          try {
            assert.equal(guest.call("whole", 1), 13);
            assert.equal(guest.call("fraction", 1), 3.5);
          } finally { guest.dispose(); }
        }
      } finally { await compiler.dispose(); }
    }
  } finally { await Deno.remove(directory, { recursive: true }); }
});

Deno.test("closed universal numeric contracts survive source and compiled dependency boundaries", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/proof.blot`;
  const archive = `${directory}/proof.blotdep`;
  const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const boundary = universalNumericSource.indexOf("entry const whole");
  const library = universalNumericSource.slice(0, boundary);
  const main = 'import {witness, at} from "./proof"\n' + universalNumericSource.slice(boundary);
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped", stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stderr) + new TextDecoder().decode(packed.stdout));
    for (const dependencies of [undefined, archive]) {
      for (const codegenTier of ["optimized", "development"] as const) {
        const compiler = await createZigProjectCompiler({ executable, entry, prelude: null, dependencies, codegenTier, cacheDirectory: false });
        try {
          const built = await compiler.build({ sources: { [entry]: main, [dependency]: library } });
          assert(built.success, JSON.stringify(built));
          const guest = await instantiateGuest(built.bytes);
          try {
            assert.equal(guest.call("whole", 1), 13);
            assert.equal(guest.call("fraction", 1), 3.5);
            assert.throws(() => guest.call("whole", 2));
            assert.throws(() => guest.call("fraction", 4294967295));
          } finally { guest.dispose(); }
        } finally { await compiler.dispose(); }
      }
    }
  } finally { await Deno.remove(directory, { recursive: true }); }
});

Deno.test("closed explicit universal functions execute independent U32 and F32 instances", async () => {
  let expected: Uint8Array | undefined;
  await compileAndRun(
    "const identity = fn value => value\n" + entries,
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
    "const identity: forall [a] => a -> a = fn value => 42\n" + entries,
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
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const retained = await createZigProjectCompiler(options);
  const revisions = [
    universal + entries,
    universal + entries.replace("identity value", "identity 43"),
    universal.replace("fn value => value", "fn value => 42") + entries,
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
