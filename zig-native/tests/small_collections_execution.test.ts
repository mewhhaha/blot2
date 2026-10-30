import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("small scalar lists disappear through ordinary producer and traversal helpers", async () => {
  await compileAndRun(
    `
const pair = func value => return [value, value + 1]
const sum = func (values: List U32) => return do:
  let result = 0
  for value in values:
    result := self + value
  break result
entry const run = func count => return do:
  let result = 0
  for index in 0..count:
    result := self + sum (pair index)
  break result
entry const local = func count => return do:
  let result = 0
  for index in 0..count:
    let values = pair index
    for value in values:
      result := self + value
  break result
entry const floats = func seed => return do:
  let total = seed
  for value in [1.0e20, 0.0 - 1.0e20, 1.0]:
    total := self + value
  break total
entry const escape = func value => return Array.from_list (pair value)
entry const alias = func seed => return do:
  let values = pair seed
  let old = values
  values := [...self, 90]
  break #[sum old, sum values]
const changed = func (values: List U32) => return func flag => return do:
  if flag == 0:
    values := [9]
  let result = 0
  for value in values:
    result := self + value
  break result
entry const merged = func seed => return changed [seed, seed + 1] seed
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
const mark = func number => return do:
  use previous <- @state.get #Trace
  let #Trace before = previous
  use @state.set (#Trace (before * 10 + number))
  break number
const first = func (values: List U32) => return do:
  for value in values:
    break value
  break 0
entry const ordered = func () => return do:
  let (#Trace trace, answer) = @state.run (#Trace 0) (func () => return first [mark 1, mark 2, mark 3])
  break trace * 10 + answer
entry const trapped = func denominator => return first [7, @u32.div 1 denominator]
entry const empty = func (seed: U32) => return do:
  let result = seed
  let values: List U32 = []
  for value in values:
    result := self + value
  break result
`,
    (guest) => {
      equal(guest.call("ordered", null), 1231);
      equal(guest.call("trapped", 1), 7);
      throws(() => guest.call("trapped", 0), WebAssembly.RuntimeError);
      equal(guest.call("empty", 42), 42);
    },
  );
});
