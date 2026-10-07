import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("small scalar lists disappear through ordinary producer and traversal helpers", async () => {
  await compileAndRun(
    `
const pair = fn value => [value, value + 1]
const sum = fn (values: List U32) => do:
  let result = 0
  for value in values:
    result := self + value
  return result
entry const run = fn count => do:
  let result = 0
  for index in 0..count:
    result := self + sum (pair index)
  return result
entry const local = fn count => do:
  let result = 0
  for index in 0..count:
    let values = pair index
    for value in values:
      result := self + value
  return result
entry const floats = fn seed => do:
  let total = seed
  for value in [1.0e20, 0.0 - 1.0e20, 1.0]:
    total := self + value
  return total
entry const escape = fn value => Array.from_list (pair value)
entry const alias = fn seed => do:
  let values = pair seed
  let old = values
  values := [...self, 90]
  return #[sum old, sum values]
const changed = fn (values: List U32) => fn flag => do:
  if flag == 0:
    values := [9]
  let result = 0
  for value in values:
    result := self + value
  return result
entry const merged = fn seed => changed [seed, seed + 1] seed
`,
    (guest) => {
      equal(guest.call("run", 20000), 400000000);
      equal(guest.call("local", 20000), 400000000);
      ok(
        guest.memoryBytes() <= 192 * 1024,
        `Temporary lists still allocate: ${guest.memoryBytes()}`,
      );
      equal(guest.call("floats", 0), 1);
      deepStrictEqual(guest.call("escape", 20), Uint32Array.of(20, 21));
      deepStrictEqual(guest.call("alias", 20), Uint32Array.of(41, 131));
      equal(guest.call("merged", 0), 9);
      equal(guest.call("merged", 20), 41);
    },
  );
});

Deno.test("small collection elimination preserves eager order, unused elements, traps and early exits", async () => {
  await compileAndRun(
    `
type Trace is data = #Trace U32
const mark = fn number => do:
  use previous <- @state.get #Trace
  let #Trace before = previous
  use @state.set (#Trace (before * 10 + number))
  return number
const first = fn (values: List U32) => do:
  for value in values:
    return value
  return 0
entry const ordered = fn () => do:
  let (#Trace trace, answer) = @state.run (#Trace 0) (fn () => first [mark 1, mark 2, mark 3])
  return trace * 10 + answer
entry const trapped = fn denominator => first [7, @u32.div 1 denominator]
entry const empty = fn (seed: U32) => do:
  let result = seed
  let values: List U32 = []
  for value in values:
    result := self + value
  return result
`,
    (guest) => {
      equal(guest.call("ordered", null), 1231);
      equal(guest.call("trapped", 1), 7);
      throws(() => guest.call("trapped", 0), WebAssembly.RuntimeError);
      equal(guest.call("empty", 42), 42);
    },
  );
});
