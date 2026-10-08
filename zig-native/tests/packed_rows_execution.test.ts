import { deepStrictEqual, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("direct collection loops eliminate temporary packed rows during repeated reads", async () => {
  await compileAndRun(
    `
let arrays = @array.generate 1024 (fn i => {x: i, y: i * 2, z: i})
let lists = @list.from_array arrays
const total_array = fn () => do:
  let sum = 0
  for row in arrays:
    sum := self + row.x + row.y + row.z
  return sum
const total_list = fn () => do:
  let sum = 0
  for row in lists:
    sum := self + row.x + row.y + row.z
  return sum
entry const run = fn count => do:
  let sum = 0
  for i in 0..count:
    sum := self + total_array () + total_list ()
  return sum
entry const memory = fn () -> Array U32 => #[]
`,
    (guest) => {
      const total = 4 * 1024 * 1023;
      equal(guest.call("run", 1), total);
      const warmed = guest.memoryBytes();
      equal(guest.call("run", 64), (total * 64) >>> 0);
      equal(guest.memoryBytes() <= warmed + 65536, true);
    },
  );
});

Deno.test("packed list rows preserve logical lengths, leaf crossings and structural snapshots", async () => {
  await compileAndRun(
    `
const saved = [{z: 7, a: 3, b: 4}, {b: 5, z: 11, a: 2}]
const sum = fn values => do:
  let total = 0
  for row in values:
    total := self + row.a + row.b + row.z
  return total
const skip = fn count => fn cursor => do:
  for i in 0..count:
    cursor := @cursor.advance self
  return cursor
entry const run = fn count => do:
  let rows = @list.generate count (fn i => {z: i * 3, a: i, b: i + 1})
  let before = rows
  let origin = rows.iter
  rows := [...self, {a: 100, b: 200, z: 300}]
  rows := [{a: 10, b: 20, z: 30}, ...self]
  let middle = @list.slice rows 1 count
  let joined = @list.concat middle saved
  let copied = @array.from_list joined
  let distant = skip (count - 1) origin
  return #[sum rows, sum before, sum middle, sum joined, copied.length, rows.length, (@cursor.value origin).a, (@cursor.value distant).z]
entry const build = fn count => do:
  let rows = [{z: i * 3, b: i + 1, a: i} | i <- @array.generate count (fn i => i)]
  return #[sum rows, rows.length, (@array.from_list rows).length]
entry const rectangular = fn count => do:
  let rows = [{a: x, b: y, z: 1} | x <- #[1, 2], y <- @array.fill count 3]
  return #[sum rows, rows.length]
entry const empty = fn count => do:
  let rows = @list.fill count {a: 1, b: 2, z: 3}
  let empty = @list.slice rows count 0
  let joined = @list.concat empty saved
  return #[empty.length, sum joined, (@array.from_list empty).length]
entry const single = fn count => (@list.fill count {value: 7}).length
`,
    (guest) => {
      for (const n of [1, 2, 82, 83, 84, 249, 1000]) {
        const sum = 5 * n * (n - 1) / 2 + n;
        deepStrictEqual(
          guest.call("run", n),
          Uint32Array.of(
            sum + 660,
            sum,
            sum,
            sum + 32,
            n + 2,
            n + 2,
            0,
            (n - 1) * 3,
          ),
        );
        deepStrictEqual(guest.call("build", n), Uint32Array.of(sum, n, n));
        deepStrictEqual(
          guest.call("rectangular", n),
          Uint32Array.of(n * 11, n * 2),
        );
        deepStrictEqual(guest.call("empty", n), Uint32Array.of(0, 32, 0));
        equal(guest.call("single", n), n);
      }
      deepStrictEqual(guest.call("build", 0), Uint32Array.of(0, 0, 0));
      deepStrictEqual(guest.call("empty", 0), Uint32Array.of(0, 32, 0));
      equal(guest.call("single", 0), 0);
    },
  );
});

Deno.test("packed rows preserve construction, copies, snapshots and ordinary generic calls", async () => {
  await compileAndRun(
    `
const literal = #[{z: 7, a: 3}, {a: 5, z: 11}]
const identity = fn value => value
const second = fn values => values[1]
const rows = fn count => @array.generate count (fn i => {z: i + 7, a: i * 3})
const sum = fn values => do:
  let total = 0
  for row in values:
    total := self + row.a * 10 + row.z
  return total
entry const operations = fn count => do:
  let values = rows count
  let before = values
  let extracted = values[1]
  let read = fn () => values[1].a
  values[1].a := self + 100
  let after = @array.set values 0 {a: 20, z: 30}
  let copied = @array.slice after 0 count
  let joined = @array.concat copied literal
  let extended = #[{a: 2, z: 4}, ...joined, {z: 9, a: 8}]
  let roundtrip = @array.from_list (@list.from_array extended)
  return #[sum roundtrip, sum before, extracted.a, read (), (second (identity after)).a]
entry const generated = fn count => sum (#[{z: y + 1, a: x} | x <- #[1, 2], y <- @array.generate count (fn i => i)])
entry const filled = fn count => sum (@array.fill count {a: 4, z: 6})
entry const empty = fn count => sum (#[{a: i, z: i} | i <- @array.generate count (fn i => i), i > count])
entry const single_field = fn count => (@array.generate count (fn i => {value: i}))[count - 1].value
entry const reference_rows = fn count => do:
  let values = @array.generate count (fn i => {items: #[i, i + 1], value: i})
  let before = values
  values[0].items[0] := 99
  return #[before[0].items[0], values[0].items[0], values[count - 1].value]
`,
    (guest) => {
      for (const n of [2, 3, 17, 249, 1000]) {
        const old = 31 * n * (n - 1) / 2 + 7 * n;
        deepStrictEqual(
          guest.call("operations", n),
          Uint32Array.of(old + 1000 + 223 + 37 + 61 + 24 + 89, old, 3, 3, 103),
        );
        equal(guest.call("generated", n), n * 30 + n * (n + 1));
        equal(guest.call("filled", n), 46 * n);
        equal(guest.call("empty", n), 0);
        equal(guest.call("single_field", n), n - 1);
        deepStrictEqual(
          guest.call("reference_rows", n),
          Uint32Array.of(0, 99, n - 1),
        );
      }
      equal(guest.call("filled", 0), 0);
      equal(guest.call("generated", 0), 0);
      throws(() => guest.call("single_field", 0), WebAssembly.RuntimeError);
    },
  );
});

Deno.test("packed tuple cursors preserve independent positions, escaped values and float bits", async () => {
  await compileAndRun(
    `
const constant = #[(1, -0.0), (2, 3.5)]
const first_field = fn row => do:
  let (value, _, _) = row
  return value
entry const floating = fn (input: Array F32) => do:
  let rows = #[(i, value) | value <- input, let i = 9]
  let original = rows
  let selected = rows[0]
  rows[0] := (0, 42.0)
  let cursor = original.iter
  let fork = cursor
  let cursor = @cursor.advance cursor
  let (_, first) = @cursor.value fork
  let (_, second) = @cursor.value cursor
  let (_, saved) = selected
  let (_, zero) = constant[0]
  return #[first, second, saved, zero]
entry const conversions = fn (input: Array F32) => do:
  let rows = #[(value, #True, ()) | value <- input]
  let listed = @list.from_array rows
  let copied = @array.from_list listed
  return #[first_field row | row <- copied]
entry const fields = fn (input: Array F32) => do:
  let rows = #[{value: value, count: 9} | value <- input]
  return #[rows[i].value | i <- @array.generate input.length (fn i => i)]
entry const boundaries = fn count => do:
  let values = @array.generate count (fn i => (i, i + 1))
  let selected = @array.slice values count 0
  let cursor = selected.iter
  return @cursor.has cursor
`,
    (guest) => {
      deepStrictEqual(
        guest.call("floating", Float32Array.of(-0, 3.5)),
        Float32Array.of(-0, 3.5, -0, -0),
      );
      const words = Uint32Array.of(
        0,
        0x80000000,
        0x7fc01234,
        0xffc05678,
        0x7f800000,
        0xff800000,
        0x3f800000,
      );
      const converted = guest.call(
        "conversions",
        new Float32Array(words.buffer),
      ) as Float32Array;
      deepStrictEqual(
        new Uint32Array(
          converted.buffer,
          converted.byteOffset,
          converted.length,
        ),
        words,
      );
      const fields = guest.call(
        "fields",
        new Float32Array(words.buffer),
      ) as Float32Array;
      deepStrictEqual(
        new Uint32Array(fields.buffer, fields.byteOffset, fields.length),
        words,
      );
      for (const count of [0, 1, 249]) {
        equal(
          guest.call("boundaries", count),
          false,
        );
      }
    },
  );
});

Deno.test("packed rows keep eager failure order and effectful field order", async () => {
  await compileAndRun(
    `
entry const order = fn (visit: U32 -> U32 ! {Foreign}) => do:
  use first <- visit 1
  use last <- visit 2
  let rows = #[{z: first, a: last}]
  use result <- visit (rows[0].a * 10 + rows[0].z)
  return result
entry const eager = fn divisor => do:
  let rows = #[(i, 10 / divisor) | i <- #[1, 2]]
  return rows.length
entry const too_large = fn count => (@array.fill count (1, 2, 3)).length
`,
    (guest) => {
      const seen: number[] = [];
      const visit = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          seen.push(value);
          return value;
        },
      });
      equal(guest.call("order", visit), 21);
      deepStrictEqual(seen, [1, 2, 21]);
      equal(guest.call("eager", 1), 2);
      throws(() => guest.call("eager", 0), WebAssembly.RuntimeError);
      throws(
        () => guest.call("too_large", 0x20000000),
        WebAssembly.RuntimeError,
      );
    },
  );
});

Deno.test("extracted packed rows and cursors survive collection and later array edits", async () => {
  await compileAndRun(
    `
entry const run = fn count => do:
  let rows = @array.generate 257 (fn i => {x: i, y: 65552 + i})
  let extracted = rows[256]
  let read = fn () => extracted.x + extracted.y
  let cursor = rows.iter
  let saved_cursor = (@list.from_array rows).iter
  let index = 0
  for ever:
    if index == count:
      return read () + (@cursor.value saved_cursor).y + rows[1].x
    rows[1].x := self + 1
    let discarded = @array.fill 8192 index
    cursor := @cursor.advance rows.iter
    index := self + 1
entry const memory = fn () -> Array U32 => #[]
`,
    (guest) => {
      equal(guest.call("run", 256), 131617 + 256);
      const warmed = guest.memoryBytes();
      equal(guest.call("run", 2048), 131617 + 2048);
      equal(guest.memoryBytes() <= warmed + 65536, true);
    },
  );
});
