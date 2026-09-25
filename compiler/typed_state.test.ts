import { reachedSource } from "./fixtures.ts";
import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { instantiateGuest } from "./guest.ts";

const stateProgram = `
data Count = Count U32
data Position = Position F32
const get = fn witness => @state.get witness
const set = fn value => @state.set value
const nested_get = fn witness => @state.get (fn () => witness)
const advance = fn () => do:
  use previous <- get Count
  let Count value = previous
  use set (Count (value + 1))
  use current <- get Count
  let Count answer = current
  return answer
entry const answer = fn () => do:
  let (Count next, result) = @state.run (Count 41) advance
  return next + result
entry const independent = fn () => do:
  let (Count next, (Position moved, result)) = @state.run (Count 41) (fn () =>
    @state.run (Position 1.0) (fn () => do:
      use count <- advance ()
      use position <- get Position
      let Position value = position
      use set (Position (value + U32.to_f32 count))
      return count))
  return [U32.to_f32 next, moved, U32.to_f32 result]
entry const custom = fn () => @state.reader Count (fn () => Count 7) (fn () => do:
  use count <- get Count
  let Count answer = count
  return answer)
entry const nested_witness = fn () => do:
  let (_, Count answer) = @state.run (Count 42) (fn () => nested_get Count)
  return answer
`;

Deno.test("typed state specializes nominal constructor witnesses and scoped storage", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(stateProgram);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", null), 84);
      equal(guest.call("independent", null), new Float32Array([42, 43, 42]));
      equal(guest.call("custom", null), 7);
      equal(guest.call("nested_witness", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("typed state rejects an unhandled operation in a pure binding", async () => {
  const compiler = await createSourceCompiler();
  try {
    throws(() =>
      compiler.compile(reachedSource(`data Count = Count U32
const run: Unit -> Count = fn () => @state.get Count`)), (error: unknown) => {
      ok(error instanceof Error);
      ok(/effect|unhandled/.test(error.message), error.message);
      return true;
    });
  } finally {
    compiler.dispose();
  }
});

const genericProgram = `
data Cell value = Cell value
const read = fn witness => @state.get witness
const advance = fn () => do:
  use integer <- read (fn () => Cell 0)
  let Cell count = integer
  use fraction <- read (fn () => Cell 0.0)
  let Cell amount = fraction
  use @state.set (Cell (count + 1))
  use @state.set (Cell (amount + 0.5))
  return count
entry const answer = fn () => do:
  let (Cell count, (Cell amount, previous)) = @state.run (Cell 40) (fn () =>
    @state.run (Cell 1.0) advance)
  return U32.to_f32 count + amount + U32.to_f32 previous
entry const run = fn () => answer ()
entry const expected = answer ()
entry const witness = fn () => do:
  let (_, result) = @state.run (Cell 42) (fn () => do:
    use cell <- @state.get (fn () -> Cell U32 => @panic "a type witness must never be called")
    let Cell answer = cell
    return answer)
  return result
`;

Deno.test("typed state separates generic instances and executes in const evaluation", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(genericProgram);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 82.5);
      equal(guest.call("witness", null), 42);
      equal(
        artifact.analysis.constants.find((constant) =>
          constant.name === "expected"
        )
          ?.value,
        { $: "F32Value", value: 82.5 },
      );
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("typed state has exact native and JavaScript parity", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (const source of [stateProgram, genericProgram]) {
      equal(await native.compile(source), reference.compile(source));
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
