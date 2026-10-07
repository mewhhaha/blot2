import { deepStrictEqual, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("forked list cursors keep independent leaves across boundaries and collection", async () => {
  await compileAndRun(
    `
const skip = fn count => fn cursor => do:
  for index in 0..count:
    cursor := @cursor.advance self
  return cursor
const frozen = skip 247 (@list.generate 800 identity).iter
entry const run = fn count => do:
  let values = @list.generate 800 identity
  let original = values.iter
  let left = original
  let right = skip 300 original
  let total = 0
  for index in 0..count:
    total := self + @cursor.value left + @cursor.value right
    left := @cursor.advance self
    right := @cursor.advance self
  return total
entry const static_boundary = fn () => do:
  let next = @cursor.advance frozen
  return #[@cursor.value frozen, @cursor.value next, @cursor.value (@cursor.advance next)]
entry const collected = fn count => do:
  let left = (@list.generate 800 identity).iter
  let right = skip 300 left
  let total = 0
  let index = 0
  for ever:
    if index == count:
      break
    let garbage = @array.fill 8192 index
    total := self + @cursor.value left + @cursor.value right
    left := @cursor.advance self
    right := @cursor.advance self
    index := self + 1
  return total
entry const float_array = fn (seed: F32) => do:
  let first = #[seed, 0.0 - 0.0, 1.5].iter
  let second = @cursor.advance first
  return #[@cursor.value first, @cursor.value second, @cursor.value (@cursor.advance second)]
entry const past_value = fn count => @cursor.value (skip count [10, 20].iter)
entry const past_advance = fn count => @cursor.has (@cursor.advance (skip count [10, 20].iter))
entry const empty = fn (count: U32) => @cursor.has (@list.generate count identity).iter
`,
    (guest) => {
      for (const count of [0, 1, 247, 248, 249, 499, 500]) {
        equal(guest.call("run", count), count * (count - 1) + 300 * count);
      }
      deepStrictEqual(
        guest.call("static_boundary", null),
        Uint32Array.of(247, 248, 249),
      );
      equal(guest.call("collected", 500), 399500);
      deepStrictEqual(
        guest.call("float_array", -1.25),
        Float32Array.of(-1.25, 0, 1.5),
      );
      equal(guest.call("past_value", 1), 20);
      equal(guest.call("past_advance", 1), false);
      throws(() => guest.call("past_value", 2), WebAssembly.RuntimeError);
      throws(() => guest.call("past_advance", 2), WebAssembly.RuntimeError);
      equal(guest.call("empty", 0), false);
    },
  );
});
