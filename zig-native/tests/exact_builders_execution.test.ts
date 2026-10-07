import { deepStrictEqual } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("exact nested builders preserve arrays, lists, empty extents and element order", async () => {
  await compileAndRun(
    `
entry const rectangle = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    for y in 2..5:
      result := [...self, x * 10 + y]
  return @array.from_list result
entry const product = fn (values: Array U32) => #[x * 10 + y | x <- values, y <- values]
const lists = fn (values: Array U32) => [x * 10 + y | x <- values, y <- values]
entry const list_result = fn values => Array.from_list (lists values)
entry const reversed = fn count => do:
  let result: List U32 = []
  for x in count..2:
    result := [...self, x]
  return @array.from_list result
entry const ragged = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, x * 10 + y]
  return @array.from_list result
entry const observed = fn count => do:
  let result: List U32 = []
  for x in 0..count:
    result := [...self, result.length]
  return @array.from_list result
`,
    (guest) => {
      for (const count of [0, 1, 83, 249]) {
        deepStrictEqual(
          guest.call("rectangle", count),
          Uint32Array.from(
            { length: count * 3 },
            (_, i) => Math.floor(i / 3) * 10 + i % 3 + 2,
          ),
        );
      }
      for (const values of [[], [3], [1, 2, 3]]) {
        const expected = Uint32Array.from(
          values.flatMap((x) => values.map((y) => x * 10 + y)),
        );
        deepStrictEqual(
          guest.call("product", Uint32Array.from(values)),
          expected,
        );
        deepStrictEqual(
          guest.call("list_result", Uint32Array.from(values)),
          expected,
        );
      }
      deepStrictEqual(guest.call("reversed", 3), new Uint32Array());
      deepStrictEqual(guest.call("reversed", 0), Uint32Array.of(0, 1));
      deepStrictEqual(
        guest.call("ragged", 4),
        Uint32Array.of(10, 20, 21, 30, 31, 32),
      );
      deepStrictEqual(guest.call("observed", 4), Uint32Array.of(0, 1, 2, 3));
    },
  );
});

Deno.test("effectful builders retain the ordinary path and nested-loop order", async () => {
  await compileAndRun(
    `
entry const run = fn (send: U32 -> U32 ! {Foreign}) => do:
  let result: List U32 = []
  for x in 0..2:
    for y in 1..3:
      use value <- send (x * 10 + y)
      result := [...self, value]
  return @array.from_list result
`,
    (guest) => {
      const seen: number[] = [];
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value: number) => {
          seen.push(value);
          return value + 100;
        },
      });
      deepStrictEqual(
        guest.call("run", send),
        Uint32Array.of(101, 102, 111, 112),
      );
      deepStrictEqual(seen, [1, 2, 11, 12]);
      equal(seen.length, 4);
    },
  );
});
