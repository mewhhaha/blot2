import { strictEqual as equal, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { instantiateGuest } from "./guest.ts";
import { SourceError } from "./syntax.ts";

Deno.test("selected callback rows specialize independently for pure and handled uses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
effect Tick: Unit -> U32
const provider = @effect.provider Tick (fn () => 10)
const apply = fn transform => fn value => @type.call "map" transform (#Some value)
const unused = fn transform => fn value => @type.call "map" transform (#Some value)
const tick = fn value => do:
  use amount <- Tick ()
  return value + amount
entry const pure = fn () => Maybe.unwrap_or 0 (apply (fn x => x + 1) 41)
entry const effectful = fn () => do provider:
  return Maybe.unwrap_or 0 (apply tick 32)
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.pure as CallableFunction)(), 42);
    equal((instance.exports.effectful as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("ordinary selected operators prove concrete curried rows before relinking invocation", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
type Box a is data = #Box a
const Box.add = fn left => fn right => case left, right of
  #Box a, #Box b => #Box (a + b)
const twice = fn value => value + value
entry const answer = fn (value: F32) => case twice (#Box value) of
  #Box result => result
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", 21), 42);
    } finally {
      guest.dispose();
    }
    throws(
      () =>
        compiler.compile(`
effect Tick: Unit -> Unit
type Box a is data = #Box a
const Box.add = fn left => fn right => do:
  use Tick ()
  return case left, right of
    #Box a, #Box b => #Box (a + b)
const twice = fn value => value + value
entry const answer: F32 -> F32 ! {} = fn value => case twice (#Box value) of
  #Box result => result
`),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});
