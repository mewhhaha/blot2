import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("aliases use the underlying layout, dispatch and independent type instantiations", async () => {
  await compileAndRun(
    `
type Number = U32
type Pair a = (a, a)
type Value = Box Number
type Box a is data = #Box { value: a }
const Box.read = func box => return func () => return box.value
const first = func (pair: Pair a) => return @product.get pair 0
const number: Value = #Box { value: 40 }
entry const answer = func () => return @u32.add (number.read ()) (first (2, 3))
entry const fraction = func () => return first (1.5, 2.5)
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("fraction", null), 1.5);
    },
  );
});

Deno.test("imported aliases survive retained revisions, type changes and fresh builds", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`,
    dependency = `${directory}/types.blot`;
  const compiler = await createZigProjectCompiler({ executable, entry });
  const original =
    "type Number = U32\ntype Pair a = (a, a)\nconst read = func (pair: Pair Number) => return @product.get pair 0\n";
  const sources = {
    [entry]:
      'import { Number, Pair, read } from "./types"\nconst pair: Pair Number = (42, 0)\nentry const answer = func () => return read pair\n',
    [dependency]: original,
  };
  try {
    const first = await compiler.build({ sources });
    ok(first.success, JSON.stringify(first));
    const noop = await compiler.build({ sources });
    ok(noop.success, JSON.stringify(noop));
    equal(noop.bytes, first.bytes);
    const changed = await compiler.build({
      sources: { ...sources, [dependency]: original.replace("= U32", "= F32") },
    });
    ok(!changed.success);
    equal(changed.diagnostics[0].code, "type_mismatch");
    equal(changed.revision, noop.revision);
    const fixed = await compiler.build({ sources });
    ok(fixed.success, JSON.stringify(fixed));
    equal(fixed.bytes, first.bytes);
    const fresh = await createZigProjectCompiler({ executable, entry });
    try {
      const rebuilt = await fresh.build({ sources });
      ok(rebuilt.success, JSON.stringify(rebuilt));
      equal(rebuilt.bytes, fixed.bytes);
    } finally {
      await fresh.dispose();
    }
    const guest = await instantiateGuest(fixed.bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("aliases freshen shaped parameters and latent effect rows independently", async () => {
  await compileAndRun(
    `
type Pair [a, b] = (a, b)
type Action a = Unit -> a ! {| e}
type Carry f is data = #Carry f
const first = func (pair: Pair [a, b]) => return @product.get pair 0
const invoke = func (action: Action a) => return action ()
const packed = func (carry: Carry (Action a)) => return case carry of
  #Carry action => action ()
entry const answer = func () => return invoke (func () => return first (42, true))
entry const effectful = func (send: U32 -> U32 ! {Foreign}) => return invoke (func () => return send 41)
entry const carried = func (send: U32 -> U32 ! {Foreign}) => return packed (#Carry (func () => return send 41))
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => value + 1,
      });
      equal(guest.call("effectful", send), 42);
      equal(guest.call("carried", send), 42);
    },
  );
  await compileExpectedFailure(
    "type Action a = Unit -> a ! {| e}\ntype Box is data = #Box (Action U32)\nentry const answer = 42\n",
    "unbound_alias_row",
  );
});

Deno.test("aliases preserve interfaces in serialized dependency bundles", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`,
    library = `${directory}/library.blot`,
    bundle = `${directory}/dependencies.blotdep`;
  try {
    await Deno.writeTextFile(
      library,
      "type Number = U32\ntype Pair a = (a, a)\nconst first = func (pair: Pair Number) => return @product.get pair 0\n",
    );
    await Deno.writeTextFile(
      entry,
      'import { first, Pair, Number } from "./library"\nconst input: Pair Number = (42, 0)\nentry const answer = func () => return first input\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      dependencies: bundle,
    });
    try {
      const built = await compiler.build();
      ok(built.success, JSON.stringify(built));
      ok(built.stats.cachedModules > 0);
      const guest = await instantiateGuest(built.bytes);
      try {
        equal(guest.call("answer", null), 42);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("aliases retain underlying effect identities in written rows and operation arguments", async () => {
  await compileAndRun(
    `
type Number = U32
type Identity a = a
type Signal a is effect = { get: Unit -> a }
type Read a is contract = { operation Signal.get a, type_rep a, effect_rep ! {} }
const read: Unit -> a ! {| e} where { Read a } = func () => return Signal.get a ()
const number: Unit -> Number ! {Signal.get Number} = func () => return Signal.get Number ()
entry const answer = func () : U32 => return do (@effect.provider (Signal.get (Identity Number)) (func () => return 21)):
  break @u32.add (read ()) (number ())
entry const fraction = func () : F32 => return do (@effect.provider (Signal.get (Identity F32)) (func () => return 1.5)):
  break read ()
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("fraction", null), 1.5);
    },
  );
});
