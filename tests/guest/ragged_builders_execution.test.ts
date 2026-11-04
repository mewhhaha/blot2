import { deepStrictEqual, throws } from "node:assert/strict";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("ragged builders preserve dependent bounds filters and empty source order", async () => {
  await compileAndRun(
    `
entry const triangle = func count => return do:
  let result: List U32 = []
  for x in 0..count:
    for y in 0..x:
      result := [...self, x * 10 + y]
  break @array.from_list result
entry const selected = func (values: Array U32) => return
  #[square | x <- values, x > 1, let square = x * x, square < 10]
const lists = func (values: List U32) => return [y | x <- values, x > 1, y <- values, y < x]
entry const selected_list = func (values: Array U32) => return @array.from_list (lists (@list.from_array values))
entry const all_filtered = func (values: Array U32) => return #[x | x <- values, false]
entry const exhausted = func (count: U32) => return do:
  let result: List U32 = []
  for x in 0..count:
    if false:
      result := [...self, x]
  break @array.from_list result
entry const reversed = func (first: U32) => return do:
  let result: List U32 = []
  for x in first..2:
    for y in 0..x:
      result := [...self, y]
  break @array.from_list result
entry const skip = func () => return do:
  let result: List U32 = []
  for x in 0..0:
    for y in 0..4_294_967_295:
      result := [...self, x + y]
  break @array.from_list result
`,
    (guest) => {
      for (const count of [0, 1, 8, 32, 128, 256]) {
        const expected: number[] = [];
        for (let x = 0; x < count; x++) {
          for (let y = 0; y < x; y++) expected.push(x * 10 + y);
        }
        deepStrictEqual(
          guest.call("triangle", count),
          Uint32Array.from(expected),
        );
      }
      for (const values of [[], [0, 1, 2, 3, 4], [3, 2, 0, 4]]) {
        const input = Uint32Array.from(values);
        deepStrictEqual(
          guest.call("selected", input),
          Uint32Array.from(
            values.filter((x) => x > 1).map((x) => x * x).filter((x) => x < 10),
          ),
        );
        deepStrictEqual(
          guest.call("selected_list", input),
          Uint32Array.from(
            values.filter((x) => x > 1).flatMap((x) =>
              values.filter((y) => y < x)
            ),
          ),
        );
        deepStrictEqual(guest.call("all_filtered", input), new Uint32Array());
      }
      deepStrictEqual(guest.call("reversed", 3), new Uint32Array());
      deepStrictEqual(guest.call("exhausted", 1_048_577), new Uint32Array());
      deepStrictEqual(guest.call("reversed", 0), Uint32Array.of(0));
      deepStrictEqual(guest.call("skip", null), new Uint32Array());
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

Deno.test("ragged packed row copies retain List leaf crossings snapshots and four dependent dimensions", async () => {
  await compileAndRun(
    `
const arrays = func rows => return #[row | row <- rows, row.a < 249]
const lists = func rows => return [row | row <- rows, row.a < 249]
const sum = func rows => return do:
  let total = 0
  for row in rows:
    total := self + row.a + row.b + row.z
  break total
entry const packed = func count => return do:
  let input = @array.generate count (func i => return {a: i, b: i + 1, z: i * 3})
  let from_array = arrays input
  let list_input = @list.from_array input
  let from_list = lists list_input
  let snapshot = input
  input[0].a := 42
  break #[sum from_array, sum from_list, from_array.length, from_list.length, snapshot[0].a, input[0].a]
entry const four = func count => return do:
  let values: List U32 = []
  for a in 0..count:
    for b in 0..a:
      for c in 0..b:
        for d in 0..c:
          values := @list.append self d
  break @array.from_list values
`,
    (guest) => {
      for (const count of [1, 82, 83, 84, 249, 1000]) {
        const selected = Math.min(count, 249);
        const sum = 5 * selected * (selected - 1) / 2 + selected;
        deepStrictEqual(
          guest.call("packed", count),
          Uint32Array.of(sum, sum, selected, selected, 0, 42),
        );
      }
      for (const count of [0, 1, 4, 5, 8]) {
        const expected: number[] = [];
        for (let a = 0; a < count; a++) {
          for (let b = 0; b < a; b++) {
            for (let c = 0; c < b; c++) {
              for (let d = 0; d < c; d++) expected.push(d);
            }
          }
        }
        deepStrictEqual(guest.call("four", count), Uint32Array.from(expected));
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

Deno.test("ragged inert reference copies preserve closures and shared callback captures", async () => {
  await compileAndRun(
    `
const delay = func value => return func () => return value
entry const captured = func (seed: U32) : U32 => return do:
  let pending = delay (@array.fill 3 seed)
  let first = pending ()
  let values = #[pending, pending]
  let copied = #[value | value <- values, true]
  break (copied[0] ())[0] + (copied[1] ())[2] + first[1]
entry const closures = func (seed: U32) : U32 => return do:
  let callback = func value => return value + seed
  let values = #[callback, callback]
  let copied = @array.from_list [value | value <- values, true]
  break copied[0] 1 + copied[1] 2
`,
    (guest) => {
      equal(guest.call("captured", 14), 42);
      equal(guest.call("closures", 20), 43);
      equal(guest.call("captured", 7), 21);
    },
  );
});

Deno.test("ragged guest allocation failure preserves established immutable input", async () => {
  await compileAndRun(
    `
let original = #[11,22,33]
entry const saved = func () => return original[1]
entry const triangle = func (count: U32) => return do:
  let values: List U32 = []
  for x in 0..count:
    for y in 0..x:
      values := [...self, x]
  break @array.from_list values
`,
    (guest, bytes) => {
      equal(guest.call("saved", null), 22);
      // Constrain the guest's resource limit; executable instructions and
      // allocation behavior stay unchanged. The exact output exceeds four pages.
      let cursor = 8;
      const read = () => {
        let value = 0, shift = 0, byte: number;
        do {
          byte = bytes[cursor++];
          value |= (byte & 127) << shift;
          shift += 7;
        } while ((byte & 128) !== 0);
        return value;
      };
      const parts = [...bytes.slice(0, 8)];
      while (cursor < bytes.length) {
        const start = cursor, section = bytes[cursor++], length = read();
        const end = cursor + length;
        if (section === 5) {
          equal(read(), 1);
          equal(read(), 1);
          equal(read(), 1);
          parts.push(5, 4, 1, 1, 1, 4);
        } else parts.push(...bytes.slice(start, end));
        cursor = end;
      }
      const constrained = new WebAssembly.Instance(
        new WebAssembly.Module(Uint8Array.from(parts)),
      );
      const triangle = constrained.exports.triangle as CallableFunction;
      const saved = constrained.exports.saved as CallableFunction;
      equal(saved(), 22);
      throws(() => triangle(400), WebAssembly.RuntimeError);
      equal(saved(), 22);
      equal(triangle(4) > 0, true);
      equal(saved(), 22);
    },
  );
});
