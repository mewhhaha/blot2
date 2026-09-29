import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";

const source = `
const pair = fn (left: U32) => fn (right: U32) => left * 10 + right
const triple = fn (a: U32) => fn (b: U32) => fn (c: U32) => a * 100 + b * 10 + c
const count = fn (left: U32) => fn (right: U32) => case left == 0 of
  #True => right
  #False => count (left - 1) (right + 1)
const choose = fn (left: U32) => fn (right: U32) => do:
  if left > right:
    return left
  return right
const captured = fn (left: U32) => fn (right: U32) => do:
  let next = fn (value: U32) => left + right + value
  return next 7
entry const saturated = fn (right: U32) => pair 2 right
entry const recursive = fn (value: U32) => count value 0
entry const three = fn (value: U32) => triple value 2 3
entry const partial = fn (value: U32) => do:
  let saved = pair value
  return saved 3 + saved 4
entry const shadowed = fn (left: U32) => pair 2 left
entry const returned = fn (value: U32) => choose value 9 + 100
entry const captures = fn (value: U32) => captured value 3
entry const identity = fn (value: U32) => value
entry const wrapping = fn (value: U32) => value + 1
entry const floating = fn (value: F32) => value * 2.0 + 1.0
entry const signed_zero = fn (value: F32) => value * 2.0
entry const comparison = fn (value: F32) => case value < 1.0 of
  #True => 7
  #False => 9
entry const array_export = fn (value: U32) => [value]
`;

function call(
  exports: WebAssembly.Exports,
  name: string,
  value: number,
): number {
  const fn = exports[name];
  ok(typeof fn === "function", `missing export ${name}`);
  return fn(value) as number;
}

Deno.test("saturated calls preserve scope, partials and numeric semantics in both backends", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = reference.compile(source);
    const actual = await native.compile(source);
    equal(actual.bytes, expected.bytes);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    const exports = instance.exports;
    equal(call(exports, "saturated", 7), 27);
    equal(call(exports, "three", 4), 423);
    equal(call(exports, "recursive", 100), 100);
    equal(call(exports, "partial", 2), 47);
    equal(call(exports, "shadowed", 8), 28);
    equal(call(exports, "returned", 4), 109);
    equal(call(exports, "returned", 12), 112);
    equal(call(exports, "captures", 5), 15);
    equal(call(exports, "wrapping", 0xffff_ffff), 0);
    equal(call(exports, "floating", 1.25), 3.5);
    equal(call(exports, "signed_zero", -0), -0);
    ok(Number.isNaN(call(exports, "floating", NaN)));
    equal(call(exports, "comparison", NaN), 9);

    // Each scalar entry resets the arena. A zero-byte allocation observes its
    // final pointer, so compare with a primitive path that allocates nothing.
    const allocate = exports["blot:allocate"];
    ok(typeof allocate === "function");
    call(exports, "identity", 1);
    const base = allocate(0);
    for (
      const name of [
        "saturated",
        "three",
        "shadowed",
        "wrapping",
        "floating",
        "comparison",
      ]
    ) {
      call(exports, name, 2);
      equal(allocate(0), base, `${name} allocated an intermediate closure`);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("saturation preserves argument order and effects between curried stages", async () => {
  const compiler = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const program = `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
const tick = fn () => do:
  use old <- Counter.read ()
  use Counter.write (old + 1)
  return old
const pair = fn (left: U32) => fn (right: U32) => left * 10 + right
const staged = fn (left: U32) => do:
  use middle <- tick ()
  return fn (right: U32) => left * 100 + middle * 10 + right
entry const ordered = fn (initial: U32) => do:
  let (state, result) = do (@effect.state Counter.read Counter.write initial):
    return pair (tick ()) (tick ())
  return state * 1000 + result
entry const intervening = fn (initial: U32) => do:
  let (state, result) = do (@effect.state Counter.read Counter.write initial):
    return staged (tick ()) (tick ())
  return state * 1000 + result
`;
    const artifact = compiler.compile(program);
    equal((await native.compile(program)).bytes, artifact.bytes);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal(call(instance.exports, "ordered", 1), 3012);
    equal(call(instance.exports, "intervening", 1), 4123);
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});

Deno.test("repeated curried array-copy helpers retain linear allocation", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const program = `
const copy = fn (values: Array F32) => fn (start: U32) => fn (count: U32) => do:
  let copied = @array.fill count values[start]
  for index in 0..count:
    copied[index] := values[start + index]
  return copied
entry const run = fn (count: U32) => do:
  let original = @array.fill count 3.0
  let first = copy original 0 count
  let second = copy first 0 count
  return [first[0], second[count - 1]]
`;
    const expected = reference.compile(program);
    const actual = await native.compile(program);
    equal(actual.bytes, expected.bytes);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    const count = 128;
    const allocate = instance.exports["blot:allocate"];
    ok(typeof allocate === "function");
    // Dynamic allocations reserve the first page to avoid low-ID false roots.
    const allocationFloor = Math.max(allocate(0), 65536);
    const pointer = call(instance.exports, "run", count);
    const memory = instance.exports["blot:memory"];
    ok(memory instanceof WebAssembly.Memory);
    equal(
      new Float32Array(memory.buffer, pointer + 4, 2),
      new Float32Array([3, 3]),
    );
    ok(
      allocate(0) - allocationFloor < count * 64,
      "copy loops lost in-place reuse after call expansion",
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
