import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("lists and arrays have different types and explicit conversions", async () => {
  await compileAndRun(`
entry const list = fn (x: U32) => (Array.from_list [x, 2])[0]
entry const array = fn (x: U32) -> Array U32 => #[x, 2]
entry const copy = fn (xs: Array U32) => Array.from_list (List.from_array xs)
entry const nested = fn (x: U32) => (Array.from_list ((Array.from_list [[x], [2]])[0]))[0]
entry const method = fn (x: U32) => [x, 2].length
entry const empty_length = [].length
entry const different_kinds = #Type [1] != #Type #[1]
entry const same_kind = #Type [1] == #Type [2]
const first = fn xs => xs[0]
const copied = fn xs => [x | x <- xs]
const replace_first = fn xs => fn value => do:
  let result = xs
  result[0] := value
  return result
entry const generic = fn (x: U32) =>
  #[first (Array.from_list [x]), first #[x + 1], first (Array.from_list (copied [x + 2])), first (Array.from_list (copied #[x + 3]))]
entry const generic_update = fn (x: F32) =>
  #[first (replace_first (Array.from_list [0.5]) x), first (replace_first #[1.5] x)]
`, guest => {
    equal(guest.call("list", 42), 42);
    equal([...(guest.call("array", 42) as Uint32Array)].join(","), "42,2");
    equal([...(guest.call("copy", new Uint32Array([1, 2])) as Uint32Array)].join(","), "1,2");
    equal(guest.call("nested", 42), 42);
    equal(guest.call("method", 42), 2);
    equal(guest.read("empty_length"), 0);
    equal(guest.read("different_kinds"), true);
    equal(guest.read("same_kind"), true);
    equal([...(guest.call("generic", 10) as Uint32Array)].join(","), "10,11,12,13");
    equal([...(guest.call("generic_update", 4.5) as Float32Array)].join(","), "4.5,4.5");
  });
  await compileExpectedFailure("entry const wrong = fn () -> Array U32 => [1]\n", "type_mismatch");
  await compileExpectedFailure("const wrong: List U32 = #[1]\nentry const run = 1\n", "type_mismatch");
  await compileExpectedFailure("const wrong = @array.length [1]\nentry const run = wrong\n", "type_mismatch");
  await compileExpectedFailure("const wrong = @list.length #[1]\nentry const run = wrong\n", "type_mismatch");
  await compileExpectedFailure("const first = fn xs => xs[0]\nentry const wrong = first 42\n", "type_mismatch");
  await compileExpectedFailure("entry const wrong = [...#[1]]\n", "type_mismatch");
  await compileExpectedFailure("entry const wrong = #[...[1]]\n", "type_mismatch");
});

Deno.test("comprehensions preserve nesting scope short circuiting and result order", async () => {
  await compileAndRun(`
entry const cartesian = fn (offset: U32) =>
  #[a * 10 + b + offset | a <- [1, 2], b <- #[3, 4]]
entry const dependent = fn (count: U32) =>
  #[b | a <- @array.generate count (fn i => i + 1), b <- @list.generate a (fn i => i)]
entry const guarded = fn (count: U32) =>
  #[squared | x <- @array.generate count (fn i => i), x > 1, let squared = x * x, squared < 20]
entry const empty = fn () -> Array U32 => #[b | a <- [], b <- [1 / 0]]
entry const skip = fn () -> Array U32 => #[y | x <- [1, 2], #False, let y = 1 / 0]
entry const shadow = fn (x: U32) => do:
  let ys = #[x | x <- [x, x + 1], let x = x + 10]
  return #[x, ys[0], ys[1]]
entry const captured = fn (xs: Array U32) =>
  #[xs[0] + x | x <- List.from_array xs]
`, guest => {
    equal([...(guest.call("cartesian", 100) as Uint32Array)].join(","), "113,114,123,124");
    equal([...(guest.call("dependent", 3) as Uint32Array)].join(","), "0,0,1,0,1,2");
    equal([...(guest.call("guarded", 10) as Uint32Array)].join(","), "4,9,16");
    equal((guest.call("empty", null) as Uint32Array).length, 0);
    equal((guest.call("skip", null) as Uint32Array).length, 0);
    equal([...(guest.call("shadow", 2) as Uint32Array)].join(","), "2,12,13");
    equal([...(guest.call("captured", new Uint32Array([1, 2, 3])) as Uint32Array)].join(","), "2,3,4");
  });
});

Deno.test("list spreads and array updates preserve aliases across chunk boundaries", async () => {
  await compileAndRun(`
type Item is data = #Item { value: U32 }
entry const grow = fn (count: U32) => do:
  let xs: List U32 = []
  for i in 0..count:
    xs := [i, ...self, i + count]
  return Array.from_list xs
entry const snapshot = fn (count: U32) => do:
  let original = @list.generate count (fn i => i)
  let changed = Array.from_list [9, ...original, 8]
  let before = Array.from_list original
  changed[count / 2] := 42
  return #[before[0], before[count / 2], before[count - 1], changed[0], changed[count / 2], changed[count + 1]]
entry const array_spread = fn (x: U32) => #[x, ...#[2, 3], 4]
entry const legacy_cons = fn (x: U32) => Array.from_list [x | [2, 3]]
entry const aggregate = fn (x: U32) => do:
  let xs = Array.from_list [#Item { value: x }, #Item { value: 2 }]
  xs[0].value := 42
  return xs[0].value
`, guest => {
    for (const count of [0, 1, 127, 128, 129, 255, 256, 257, 1025]) {
      const actual = guest.call("grow", count) as Uint32Array;
      equal(actual.length, count * 2);
      for (let i = 0; i < count; i++) {
        equal(actual[i], count - i - 1);
        equal(actual[count + i], count + i);
      }
    }
    for (const count of [3, 255, 256, 257, 1025]) {
      equal([...(guest.call("snapshot", count) as Uint32Array)].join(","), `0,${Math.floor(count / 2)},${count - 1},9,42,8`);
    }
    equal([...(guest.call("array_spread", 1) as Uint32Array)].join(","), "1,2,3,4");
    equal([...(guest.call("legacy_cons", 1) as Uint32Array)].join(","), "1,2,3");
    equal(guest.call("aggregate", 1), 42);
  });
});

Deno.test("list construction works during staging and preserves F32 values", async () => {
  await compileAndRun(`
const staged = [x + 1 | x <- [40, 41]]
const large = @list.generate 513 (fn i => i)
type Item is data = #Item { value: U32 }
const stored = @list.generate 8193 (fn i => #Item { value: i })
entry const frozen_item = fn (index: U32) => (Array.from_list stored)[index].value
entry const frozen_edit = fn (value: U32) => do:
  let xs = Array.from_list stored
  xs[8192].value := value
  return #[(Array.from_list stored)[8192].value, xs[8192].value]
entry const answer = (Array.from_list staged)[1]
entry const frozen_chunks = fn (index: U32) => (Array.from_list large)[index]
entry const floats = fn (count: U32) =>
  #[x | x <- @list.generate count (fn i => @f32.add (@u32.to_f32 i) 0.5)]
entry const float_update = fn (x: F32) => do:
  let xs = Array.from_list [x, 2.5]
  let before = xs
  xs[0] := 4.5
  return #[before[0], xs[0], #[3.5, ...xs, 5.5][3]]
@[fn value => value + 1]
entry const tagged = 41
`, guest => {
    equal(guest.read("answer"), 42);
    equal(guest.read("tagged"), 42);
    for (const index of [0, 255, 256, 511, 512]) equal(guest.call("frozen_chunks", index), index);
    for (const index of [0, 255, 256, 8191, 8192]) equal(guest.call("frozen_item", index), index);
    for (const value of [42, 99, 123]) equal([...(guest.call("frozen_edit", value) as Uint32Array)].join(","), `8192,${value}`);
    const floats = guest.call("floats", 513) as Float32Array;
    for (let i = 0; i < floats.length; i++) equal(floats[i], i + 0.5);
    equal([...(guest.call("float_update", 1.5) as Float32Array)].join(","), "1.5,4.5,5.5");
  });
});

Deno.test("owned comprehension and append loops allocate proportional to their output", async () => {
  await compileAndRun(`
entry const build = fn (count: U32) => do:
  let xs: List U32 = []
  for index in 0..count:
    xs := [...self, index]
  return Array.from_list xs
entry const compact = fn (count: U32) =>
  #[i + 1 | i <- @array.generate count (fn i => i), i % 2 == 0]
`, guest => {
    const count = 4097;
    const built = guest.call("build", count) as Uint32Array;
    equal(built.length, count);
    for (let i = 0; i < count; i++) equal(built[i], i);
    const compact = guest.call("compact", count) as Uint32Array;
    equal(compact.length, 2049);
    for (let i = 0; i < compact.length; i++) equal(compact[i], i * 2 + 1);
    if (guest.memoryBytes() > 2 * 1024 * 1024) {
      throw new Error(`Collection construction copied growing outputs: ${guest.memoryBytes()} bytes`);
    }
  });
});

Deno.test("ordinary list library functions compose with prelude methods", async () => {
  await compileAndRun(`
import * as list from "../../std/list"
entry const run = fn (value: U32) => do:
  let values = list.map (fn x => x + 1) (list.prepend value [1, 2, 3])
  let selected = list.filter (fn x => x > 2) values
  let total = list.fold_left U32.add 0 selected
  return #[total, (Array.from_list values)[0], values.length]
`, guest => {
    equal([...(guest.call("run", 40) as Uint32Array)].join(","), "48,41,4");
  });
});

Deno.test("lists reject indexed reads updates and public indexing intrinsics", async () => {
  const rejected = [
    "entry const run = [1, 2][0]",
    "const first = fn xs => xs[0]\nentry const run = first [1, 2]",
    "entry const run = fn () => do:\n  let xs = [1, 2]\n  xs[0] := 3\n  return xs.length",
    "type Item is data = #Item { value: U32 }\nentry const run = fn () => do:\n  let xs = [#Item { value: 1 }]\n  xs[0].value := 3\n  return xs.length",
  ];
  for (const source of rejected) await compileExpectedFailure(source + "\n", "type_mismatch");
  for (const source of ["@list.get [1] 0", "@list.set [1] 0 2"]) {
    await compileExpectedFailure(`entry const run = ${source}\n`, "unknown_intrinsic");
  }
  for (const source of ["[1].get 0", "[1].set 0 2"]) {
    await compileExpectedFailure(`entry const run = ${source}\n`, "missing_member");
  }
});

Deno.test("collector traces chunk links snapshots and aggregate elements with bounded storage", async () => {
  await compileAndRun(`
type Item is data = #Item { value: U32 }
const sum = fn (values: List Item) => do:
  let result = 0
  for item in values:
    result := self + item.value
  return result
entry const run = fn (limit: U32) => do:
  let older = @list.generate 513 (fn i => #Item { value: i })
  let read = fn () => sum older
  let values = older
  let index = 0
  for ever:
    if index == limit:
      return #[read (), sum values, values.length]
    let discarded = @list.fill 8192 index
    values := [#Item { value: index }, ...older, #Item { value: index + 1 }]
    index := self + 1
`, guest => {
    const original = 512 * 513 / 2;
    equal([...(guest.call("run", 1000) as Uint32Array)].join(","), `${original},${original + 1999},515`);
    const warmed = guest.memoryBytes();
    equal([...(guest.call("run", 5000) as Uint32Array)].join(","), `${original},${original + 9999},515`);
    if (guest.memoryBytes() > warmed + 131072) {
      throw new Error(`Chunk revisions retained dead chains: ${warmed} -> ${guest.memoryBytes()}`);
    }
  });
});
