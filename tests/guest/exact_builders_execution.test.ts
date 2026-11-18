import { deepStrictEqual } from "node:assert/strict";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("exact nested builders preserve arrays, lists, empty extents and element order", async () => {
  await compileAndRun(
    `
entry const rectangle = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    for y in 2..5:
      result := [...self, x * 10 + y]
  break @array.from_list result
entry const product = func (values: Array U32) => return #[x * 10 + y | x <- values, y <- values]
const lists = func (values: Array U32) => return [x * 10 + y | x <- values, y <- values]
entry const list_result = func values => return Array.from_list (lists values)
entry const reversed = func count => return do:
  let result: List U32 = []
  for x in count..2:
    result := [...self, x]
  break @array.from_list result
entry const ragged = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, x * 10 + y]
  break @array.from_list result
entry const observed = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    result := [...self, result.length]
  break @array.from_list result
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
entry const run = func (send: U32 -> U32 ! {Foreign}) => return do:
  let result: List U32 = []
  for x in 0..2:
    for y in 1..3:
      use value <- send (x * 10 + y)
      result := [...self, value]
  break @array.from_list result
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

Deno.test("exclusive append arms grow a private loop carry and preserve the result of every arm", async () => {
  const fixture = new URL(
    "../../compiler-goose/tests/fixtures/direct/branch_appends.blot",
    import.meta.url,
  );
  await compileAndRun(await Deno.readTextFile(fixture), (guest) => {
    for (const count of [0, 1, 17, 8192]) {
      const expected: number[] = [];
      for (let i = 0; i < count; i++) {
        switch (i % 5) {
          case 0:
            expected.push(i);
            break;
          case 1:
            if (i === 1) expected.push(99);
            else expected.push(2 * i);
            break;
          case 3:
            if (i % 2 === 0) expected.push(3 * i);
            else expected.push(4 * i);
            break;
        }
      }
      deepStrictEqual(guest.call("collect", count), Uint32Array.from(expected));
    }
  });
});

Deno.test("branch appends preserve a saved prefix, independent branches and the order of item effects", async () => {
  await compileAndRun(
    `
entry func build (send: U32 -> U32): Array U32 => return do:
  let prefix: List U32 = [11]
  let rows = @list.slice prefix 0 1
  for i in 0..9:
    if (i & 1) == 0:
      use word <- send i
      rows := @list.append self word
    else:
      use word <- send (100 + i)
      rows := @list.append self word
  let left = @list.concat rows [71]
  let right = @list.concat rows [72]
  return @array.from_list (@list.concat prefix (@list.concat rows (@list.concat left right)))
`,
    (guest) => {
      const calls: number[] = [];
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value: number) {
          calls.push(value);
          return value + 10;
        },
      });
      const values = [0, 101, 2, 103, 4, 105, 6, 107, 8];
      const rows = [11, ...values.map((value) => value + 10)];
      deepStrictEqual(
        guest.call("build", send),
        Uint32Array.of(11, ...rows, ...rows, 71, ...rows, 72),
      );
      deepStrictEqual(calls, values);
    },
  );
});

Deno.test("a branch cannot grow a list observed by a live alias", async () => {
  await compileExpectedFailure(
    `
entry func build (count: U32): U32 => return do:
  let rows: List U32 = [11]
  let snapshot = rows
  for i in 0..count:
    case i % 3 of
      0 => do:
        rows := @list.append self i
      1 => do:
        rows := @list.append self (i + 1)
      _ => ()
  return snapshot.length + rows.length
`,
    "aliased_update",
  );
});
