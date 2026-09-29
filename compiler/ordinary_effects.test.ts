import { reachedSource } from "./fixtures.ts";
import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("ordinary generic operations infer composite and curried families from arguments and results", async () => {
  const source = `
type Convert [input, output] is effect = input -> output
type Curried input => type output is effect = input -> output
type Named { input, output } is effect = input -> output
const convert = fn value => Convert value
const explicit = fn (value: a) -> b => Named { input: a, output: b } value
const curried = Curried
const invoke = fn operation => operation 10
entry const answer = fn () => do (@effect.provider (Convert [U32, F32]) (fn value => @u32.to_f32 value)):
  return do (@effect.provider ((Curried U32) F32) (fn value => @u32.to_f32 value)):
    return do (@effect.provider (Named { input: U32, output: F32 }) (fn value => @u32.to_f32 value)):
      use first <- convert 20
      use second <- explicit 12
      let operation = curried
      use third <- invoke operation
      return @f32.add first (@f32.add second third)
`;
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(0), 42);
    ok(
      artifact.analysis.functions.some((fn) =>
        fn.effect_row.operations.some((operation) =>
          operation.declaration === "Convert<1:i1:f>"
        )
      ),
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("ordinary generic operation identities remain distinct under nested providers", async () => {
  const source = `
type Left a is effect = Unit -> a
type Right a is effect = Unit -> a
const read_left = fn (witness: p -> a) -> a => Left ()
const read_right = fn () -> U32 => Right ()
type Box is data = #Box U32
entry const answer = fn () => do (@effect.provider (Left Box) (fn () => #Box 40)):
  return do (@effect.provider (Right U32) (fn () => 2)):
    use boxed <- read_left #Box
    let #Box left = boxed
    use right <- read_right ()
    return @u32.add left right
`;
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("an explicit Unit type argument remains distinct from a unit value argument", async () => {
  const source = `
type Identity a is effect = a -> a
entry const answer = fn () => do (@effect.provider (Identity Unit) (fn value => value)):
  use Identity ()
  return 42
`;
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("free operation arguments share annotations while value bindings keep their meaning", async () => {
  const source = `
type Cell a is effect = { get: Unit -> a, set: a -> Unit }
type Inspect a is effect = Array a -> a
const read = fn (witness: p -> a) -> a => Cell.get a ()
const write = fn (a: a) => Cell.set a
const write_array = fn (a: a) => Cell.set [a]
entry const answer = fn () => do:
  let (next, result) = @effect.run Cell.get Cell.set 0 (fn () => do:
    use write 42
    return read (fn () => 0))
  let (values, ignored) = @effect.run Cell.get Cell.set [0] (fn () => write_array result)
  return do (@effect.provider (Inspect U32) (fn values => @array.length values)):
    use length <- Inspect []
    return @u32.add (@array.get values 0) length
`;
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("removed selectors are rejected and ordinary effects respect pure annotations", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        ["const answer = fn () => @effect.get Cell.get 0", "unknown_intrinsic"],
        ["const answer = fn () => @effect.set Cell.set 0", "unknown_intrinsic"],
        [
          "type Read a is effect = Unit -> a\nconst answer: Unit -> U32 = fn () => Read ()",
          "effect_mismatch",
        ],
        [
          "type Phantom a is effect = Unit -> Unit\nconst answer = fn () => Phantom ()",
          "ambiguous_effect",
        ],
      ] as const
    ) {
      throws(
        () => reference.compile(reachedSource(source)),
        (error) => error instanceof SourceError && error.code === code,
      );
      await rejects(
        () => native.compile(reachedSource(source)),
        (error) => error instanceof SourceError && error.code === code,
      );
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
