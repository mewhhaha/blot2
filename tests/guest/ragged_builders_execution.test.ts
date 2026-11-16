import { deepStrictEqual, throws } from "node:assert/strict";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("ragged array builders preserve filters and empty sources", async () => {
  await compileAndRun(
    `
entry const selected = func (values: Array U32) => return
  #[square | x <- values, x > 1, let square = x * x, square < 10]
entry const all_filtered = func (values: Array U32) => return #[x | x <- values, false]
`,
    (guest) => {
      for (const values of [[], [0, 1, 2, 3, 4], [3, 2, 0, 4]]) {
        const input = Uint32Array.from(values);
        deepStrictEqual(
          guest.call("selected", input),
          Uint32Array.from(
            values.filter((x) => x > 1).map((x) => x * x).filter((x) => x < 10),
          ),
        );
        deepStrictEqual(guest.call("all_filtered", input), new Uint32Array());
      }
    },
  );
});

Deno.test("ragged rejected bodies retain trapping and callback order", async () => {
  await compileAndRun(
    `
entry const trapping_guard = func (values: Array U32) => return #[10 / x | x <- values, 1 / (x - 1) == 0]
entry const effectful = func (send: U32 -> U32 ! {Foreign}) => return do:
  let result: List U32 = []
  for x in 0..3:
    use value <- send x
    result := [...self, value]
  break @array.from_list result
entry const observed = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, result.length]
  break @array.from_list result
`,
    (guest) => {
      throws(
        () => guest.call("trapping_guard", Uint32Array.of(0, 1)),
        WebAssembly.RuntimeError,
      );
      const seen: number[] = [];
      const callback = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value: number) => {
          seen.push(value);
          return value + 100;
        },
      });
      deepStrictEqual(
        guest.call("effectful", callback),
        Uint32Array.of(100, 101, 102),
      );
      deepStrictEqual(seen, [0, 1, 2]);
      deepStrictEqual(
        guest.call("observed", 4),
        Uint32Array.of(0, 1, 2, 3, 4, 5),
      );
      equal(seen.length, 3);
    },
  );
});

Deno.test("ragged packed row copies keep copied rows and writes through the input alias", async () => {
  await compileAndRun(
    `
const arrays = func rows => return #[row | row <- rows, row.a < 249]
const sum = func rows => return do:
  let total = 0
  for row in rows:
    total := self + row.a + row.b + row.z
  break total
entry const packed = func count => return do:
  let input = @array.generate count (func i => return {a: i, b: i + 1, z: i * 3})
  let from_array = arrays input
  let snapshot = input
  input[0].a = 42
  break #[sum from_array, from_array.length, snapshot[0].a, input[0].a]
`,
    (guest) => {
      for (const count of [1, 82, 83, 84, 249, 1000]) {
        const selected = Math.min(count, 249);
        const sum = 5 * selected * (selected - 1) / 2 + selected;
        // The comprehension copied its rows before the write; `snapshot`
        // aliases `input` and reads it (tasks/LANGUAGE_COHERENCE.md A7).
        deepStrictEqual(
          guest.call("packed", count),
          Uint32Array.of(sum, selected, 42, 42),
        );
      }
    },
  );
});

Deno.test("ragged staged controls publish correct immutable selections and dependent rows", async () => {
  await compileAndRun(
    `
const selected = func (values: Array U32) => return #[square | x <- values, x > 1, let square = x * x, square < 10]
const selected_values = selected #[0,1,2,3,4]
const triangle = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, x * 10 + y]
  break @array.from_list result
const saved = triangle 4
entry const staged = func () => return #[selected_values[0], selected_values[1], saved.length, saved[0], saved[5]]
`,
    (guest) =>
      deepStrictEqual(
        guest.call("staged", null),
        Uint32Array.of(4, 9, 6, 10, 32),
      ),
  );
});

Deno.test("ragged empty and rejected branches retain complete payload checking", async () => {
  await compileExpectedFailure(
    "entry const run = func (values: Array U32) => return #[absent | x <- values, false]\n",
    "unknown_value",
  );
  await compileExpectedFailure(
    "entry const run = func count => return do:\n  let result: List U32 = []\n  for x in 0..0:\n    for y in 0..count:\n      result := [...self, absent]\n  break @array.from_list result\n",
    "unknown_value",
  );
});

Deno.test("ragged inert reference copies preserve shared callback captures", async () => {
  await compileAndRun(
    `
const delay = func (value: Array U32) => return func () => return value.copy
entry const captured = func (seed: U32) : U32 => return do:
  let pending = delay (@array.fill 3 seed)
  let first = pending ()
  let values = #[pending, pending]
  let copied = #[value | value <- values, true]
  break (copied[0] ())[0] + (copied[1] ())[2] + first[1]
`,
    (guest) => {
      equal(guest.call("captured", 14), 42);
      equal(guest.call("captured", 7), 21);
    },
  );
});
