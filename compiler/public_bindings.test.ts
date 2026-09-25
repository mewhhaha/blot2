import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler, type SourceCompilerOptions } from "./source.ts";
import { loadSourceProject, type SourceInput } from "./source_project.ts";

async function compileBoth(
  source: SourceInput,
  options: SourceCompilerOptions = { prelude: "none" },
): Promise<WebAssembly.Exports> {
  const reference = await createSourceCompiler(options);
  const native = await createNativeCompiler(options);
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    ok(WebAssembly.validate(artifact.bytes));
    return new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes))
      .exports;
  } finally {
    reference.dispose();
    await native.dispose();
  }
}

Deno.test("top-level const, let, type, constructor and effect bindings are importable by default", async () => {
  const sources: Record<string, string> = {
    "/public/main.blot": `
import { offset, started, Box, unwrap, Read } from "./library"
entry const answer = fn () => do (@effect.provider Read (fn () => started)):
  use value <- Read ()
  return unwrap (Box (@u32.add offset value))
`,
    "/public/library.blot": `
type Box is data = Box U32
type Read is effect = Unit -> U32
const offset = 1
let started = @u32.add 40 1
const unwrap = fn (value: Box) => case value of
  Box number => number
`,
  };
  const project = await loadSourceProject(new URL("file:///public/main.blot"), {
    readSource: (url) => Promise.resolve(sources[url.pathname]),
  });
  const exports = await compileBoth(project);
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("public generic, curried and structural helpers do not become invalid Wasm roots", async () => {
  const exports = await compileBoth(`
type Box is data = Box U32
const identity = fn value => value
const add = fn left => fn right => @u32.add left right
const boxed = Box 40
const unwrap = fn (value: Box) => case value of
  Box number => number
entry const answer = fn () => add (identity (unwrap boxed)) 2
`);
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("public grouped, aliased and partially applied function values preserve their callable exports", async () => {
  const exports = await compileBoth(`
entry const grouped = (fn (value: U32) => @u32.add value 1)
entry const alias = grouped
const make = fn offset => fn (value: U32) => @u32.add offset value
entry const chosen = make 40
entry const answer = fn () => alias (chosen 1)
`);
  equal(Object.keys(exports).sort(), ["alias", "answer", "chosen", "grouped"]);
  equal((exports.grouped as CallableFunction)(41), 42);
  equal((exports.alias as CallableFunction)(41), 42);
  equal((exports.chosen as CallableFunction)(2), 42);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("a generic public effect helper resolves its family at a concrete handled caller", async () => {
  const exports = await compileBoth(`
type State a is effect = { get: Unit -> a, set: a -> Unit }
const read = fn () => State.get ()
const again = fn () => read ()
entry const answer = fn () => do (@effect.provider (State.get U32) (fn () => 41)):
  use value <- again ()
  return @u32.add value 1
`);
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("public input types constrained by associated equality retain their callable entry", async () => {
  const exports = await compileBoth(
    `
entry const boolean = fn (value: Bool) => case value of
  True => 42
  False => 0
entry const flag = fn actual => boolean (actual == 7)
`,
    { prelude: "default" },
  );
  ok(typeof exports.flag === "function");
  equal(exports.flag(7), 42);
  equal(exports.flag(8), 0);
});

Deno.test("concrete effect requirements propagate through public helper interfaces", async () => {
  const exports = await compileBoth(`
type Read a is effect = Unit -> a
const get = fn () -> U32 => Read ()
const update = fn () => get ()
entry const answer = fn () => do (@effect.provider (Read U32) (fn () => 42)):
  return update ()
`);
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("generic associated helpers defer dispatch until their nominal caller is known", async () => {
  const exports = await compileBoth(
    `
type Box is data = Box U32
const Box.offset = fn (box: Box) => fn amount => case box of
  Box value => @u32.add value amount
const offset = fn value => @type.call "offset" value 1
entry const answer = fn () => offset (Box 41)
`,
    { prelude: "default" },
  );
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});

Deno.test("exported runtime factory closures retain captured startup allocations across host calls", async () => {
  const exports = await compileBoth(`
const make = fn values => fn (increment: U32) => @u32.add (@array.get values 0) increment
entry let chosen = make [40]
entry const churn = fn () => @array.get [7, 8, 9, 10] 0
`);
  equal(Object.keys(exports).sort(), ["chosen", "churn"]);
  equal((exports.chosen as CallableFunction)(2), 42);
  equal((exports.churn as CallableFunction)(), 7);
  equal((exports.chosen as CallableFunction)(2), 42);
});

Deno.test("associated callback dispatch preserves ordinary effects in public helper interfaces", async () => {
  const exports = await compileBoth(
    `
type State a is effect = { get: Unit -> a, set: a -> Unit }
const get = fn (witness: p -> a) -> a => State.get ()
const set = fn value => State.set value
type Input is data = Input F32
const edit = fn transform => do:
  use input <- get Input
  let Input x = input
  return set (Input (transform x))
const first = fn () => edit (fn x => x + 4.0)
entry const answer = fn () => do:
  let (Input value, _) = do (@effect.state (State.get Input) (State.set Input) (Input 38.0)):
    return first ()
  return value
`,
    { prelude: "default" },
  );
  equal(Object.keys(exports), ["answer"]);
  equal((exports.answer as CallableFunction)(), 42);
});
