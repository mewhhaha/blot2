// Run before JS reference modules exist: source syntax must reach the Zig backend.
import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeCompiler } from "../compiler/native.ts";
import { createNativeIncrementalCompiler } from "../compiler/native_incremental.ts";
import { formatSource } from "../compiler/format.ts";
import { SourceError } from "../compiler/syntax.ts";

const executable = new URL("./zig-out/bin/blotc-zig", import.meta.url);
async function exportsOf(bytes: Uint8Array<ArrayBuffer>) {
  return (await WebAssembly.instantiate(bytes)).instance.exports;
}
function call(exports: WebAssembly.Exports, name: string, ...args: number[]) {
  const fn = exports[name];
  ok(typeof fn === "function", name);
  return fn(...args);
}

Deno.test("Zig current syntax: constructors, alternatives, guards and formatter", async () => {
  const compiler = await createNativeCompiler({ executable, threads: 4 });
  const source = `
// Keep this comment when formatting.
type Choice is data = #First U32 | #Second U32 | #Empty
const inspect = fn value => case value of
  #First amount | #Second amount if amount > 40 => amount
  #First amount | #Second amount => amount + 2
  #Empty => 0
entry const answer=fn value=>inspect (#Second value)
entry const selected = if :1 == :2.0 then 0 else 42
`;
  try {
    const formatted = await formatSource(source);
    equal(await formatSource(formatted), formatted);
    ok(formatted.includes("// Keep this comment"));
    const original = await compiler.compile(source);
    const artifact = await compiler.compile(formatted);
    const exports = await exportsOf(artifact.bytes);
    equal(call(exports, "answer", 40), 42);
    equal(call(exports, "answer", 42), 42);
    equal((exports.selected as WebAssembly.Global).value, 42);
    equal(call(await exportsOf(original.bytes), "answer", 40), 42);
    await rejects(
      () => compiler.compile("type Bad is data = Unmarked U32"),
      SourceError,
    );
    // A failed revision must not poison the following request.
    equal(
      call(
        await exportsOf((await compiler.compile(formatted)).bytes),
        "answer",
        42,
      ),
      42,
    );
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Zig current syntax: demand memoization, skipped effects and retained edits", async () => {
  const compiler = await createNativeIncrementalCompiler({
    executable,
    threads: 4,
  });
  try {
    for (const value of [20, 21]) {
      const source = `
effect Counter.read: Unit -> U32
effect Counter.write: U32 -> Unit
const increment = fn () => do:
  use previous <- Counter.read ()
  use Counter.write (previous + 1)
  return previous
const twice = fn ~value => @force value + @force value
const ignore = fn ~value => 42
entry const skipped = ignore (@panic "unused demand")
entry const run = fn () => do:
  let (count, result) = do (@effect.state Counter.read Counter.write ${value}):
    return twice (increment ())
  return count + result
`;
      const result = await compiler.compile(source);
      const exports = await exportsOf(result.artifact.bytes);
      equal((exports.skipped as WebAssembly.Global).value, 42);
      equal(call(exports, "run"), value * 3 + 1);
      equal(call(exports, "run"), value * 3 + 1);
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Zig current syntax: loop forms, immutable successors and vector dispatch", async () => {
  const compiler = await createNativeCompiler({ executable, threads: 4 });
  try {
    const artifact = await compiler.compile(`
type Vector is data = #Vector { x: F32 }
const Vector.add = fn (a: Vector) => fn (b: Vector) => #Vector { x: a.x + b.x }
entry const vector = fn () => (#Vector { x: 40.0 } + #Vector { x: 2.0 }).x
entry const loops = fn () => do:
  let total = 0
  for 0..5:
    total := self + 1
  for let value in [2, 3]:
    total := self + value
  for ever:
    total := self + 1
    if total == 42:
      return total
`);
    const exports = await exportsOf(artifact.bytes);
    equal(call(exports, "loops"), 42);
    equal(call(exports, "vector"), 42);
  } finally {
    await compiler.dispose();
  }
});
