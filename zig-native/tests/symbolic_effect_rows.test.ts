import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

const library = `type State a is effect = { get: Unit -> a, set: a -> Unit }
const read: Unit -> a ! {State.get a} = fn () => State.get ()
const apply = fn (callback: Unit -> a ! {State.get a | e}) => callback ()
const capture = fn (callback: Unit -> a ! {State.get a}) => fn () => callback ()
`;

Deno.test("symbolic operation rows specialize generic callbacks and captured aliases", async () => {
  await compileAndRun(
    library +
      `entry const integer = fn () => @product.get (@effect.run State.get State.set 42 (fn () => apply (capture read))) 1
entry const floating = fn () => @product.get (@effect.run State.get State.set 1.5 (fn () => read ())) 1
`,
    (guest) => {
      assert.equal(guest.call("integer", null), 42);
      assert.equal(guest.call("floating", null), 1.5);
    },
    { prelude: "none" },
  );
});

Deno.test("symbolic written rows cannot become closed reflected descriptors", async () => {
  await compileExpectedFailure(
    library + "entry const answer = @effect.count (@effect.of read)\n",
    "open_effect_descriptor",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("symbolic operation rows survive compiled dependencies and retained specialization edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-symbolic-effect-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/state.blot`;
  const archive = `${directory}/state.blotdep`;
  const main = `import { State, read, apply, capture } from "./state"
entry const integer = fn () => @product.get (@effect.run State.get State.set 42 (fn () => apply (capture read))) 1
entry const floating = fn () => @product.get (@effect.run State.get State.set 1.5 (fn () => read ())) 1
`;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const dependencies of [undefined, archive]) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        dependencies,
        cacheDirectory: false,
      });
      try {
        for (const expected of [42, 43, null, 42]) {
          if (expected === null) {
            const before = await compiler.exportCheckpoint();
            const rejected = await compiler.build({
              sources: {
                [entry]: main.replace("capture read", "capture missing"),
              },
            });
            assert(!rejected.success);
            assert.equal(rejected.diagnostics[0].code, "unknown_value");
            assert.deepEqual(await compiler.exportCheckpoint(), before);
            continue;
          }
          const updated = main.replace("set 42", `set ${expected}`);
          const sources = { [entry]: updated };
          const result = await compiler.build({ sources });
          assert(result.success, JSON.stringify(result));
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            dependencies,
            checkpoint,
            cacheDirectory: false,
          });
          try {
            const rebuilt = await restored.build({ sources });
            assert(rebuilt.success, JSON.stringify(rebuilt));
            assert.deepEqual(rebuilt.bytes, result.bytes);
            for (const bytes of [result.bytes, rebuilt.bytes]) {
              const guest = await instantiateGuest(bytes);
              try {
                assert.equal(guest.call("integer", null), expected);
                assert.equal(guest.call("floating", null), 1.5);
              } finally {
                guest.dispose();
              }
            }
          } finally {
            await restored.dispose();
          }
        }
      } finally {
        await compiler.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("abstract operation contracts preserve symbolic aliases through source and compiled consumers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-symbolic-contract-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/read.blot`;
  const archive = `${directory}/read.blotdep`;
  const declarations = `
type Number = U32
type Identity a = a
type Signal a is effect = { get: Unit -> a }
type Read a is contract = { operation Signal.get a, type_rep a, effect_rep ! {} }
const read: Unit -> a ! {| e} where { Read a } = fn () => Signal.get a ()
const number: Unit -> Number ! {Signal.get Number} = fn () => Signal.get Number ()
`;
  const main = `
import {Number, Identity, Signal, Read, read, number} from "./read"
entry const answer = fn () -> U32 => do (@effect.provider (Signal.get (Identity Number)) (fn () => 21)):
  return @u32.add (read ()) (number ())
entry const fraction = fn () -> F32 => do (@effect.provider (Signal.get (Identity F32)) (fn () => 1.5)):
  return read ()
`;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, declarations);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const dependencies of [undefined, archive]) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        dependencies,
        cacheDirectory: false,
      });
      try {
        for (const value of [21, 22, 21]) {
          const sources = {
            [entry]: main.replace("fn () => 21", `fn () => ${value}`),
          };
          const built = await compiler.build({ sources });
          assert(built.success, JSON.stringify(built));
          const guest = await instantiateGuest(built.bytes);
          try {
            assert.equal(guest.call("answer", null), value * 2);
            assert.equal(guest.call("fraction", null), 1.5);
          } finally {
            guest.dispose();
          }
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            dependencies,
            cacheDirectory: false,
            checkpoint,
          });
          try {
            const rebuilt = await restored.build({ sources });
            assert(rebuilt.success, JSON.stringify(rebuilt));
            assert.deepEqual(rebuilt.bytes, built.bytes);
          } finally {
            await restored.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
