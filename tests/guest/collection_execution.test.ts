import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("comprehensions preserve nesting scope short circuiting and result order", async () => {
  await compileAndRun(`
entry const cartesian = func (offset: U32) => return
  #[a * 10 + b + offset | a <- [1, 2], b <- #[3, 4]]
entry const dependent = func (count: U32) => return
  #[b | a <- @array.generate count (func i => return i + 1), b <- @list.generate a (func i => return i)]
entry const guarded = func (count: U32) => return
  #[squared | x <- @array.generate count (func i => return i), x > 1, let squared = x * x, squared < 20]
entry const empty = func () : Array U32 => return #[b | a <- [], b <- [1 / 0]]
entry const skip = func () : Array U32 => return #[y | x <- [1, 2], false, let y = 1 / 0]
entry const shadow = func (x: U32) => return do:
  let ys = #[x | x <- [x, x + 1], let x = x + 10]
  break #[x, ys[0], ys[1]]
entry const captured = func (xs: Array U32) => return
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

Deno.test("array spreads and aggregate element updates", async () => {
  await compileAndRun(`
type Item is data = $Item { value: U32 }
entry const array_spread = func (x: U32) => return #[x, ...#[2, 3], 4]
entry const aggregate = func (x: U32) => return do:
  let xs = #[$Item { value: x }, $Item { value: 2 }]
  xs[0].value := 42
  break xs[0].value
`, guest => {
    equal([...(guest.call("array_spread", 1) as Uint32Array)].join(","), "1,2,3,4");
    equal(guest.call("aggregate", 1), 42);
  });
});

Deno.test("list construction works during staging and preserves F32 values", async () => {
  await compileAndRun(`
const staged = [x + 1 | x <- [40, 41]]
const large = @list.generate 513 (func i => return i)
type Item is data = $Item { value: U32 }
const stored = @list.generate 8193 (func i => return $Item { value: i })
entry const frozen_item = func (index: U32) => return (Array.from_list stored)[index].value
entry const frozen_edit = func (value: U32) => return do:
  let xs = Array.from_list stored
  xs[8192].value := value
  break #[(Array.from_list stored)[8192].value, xs[8192].value]
entry const answer = (Array.from_list staged)[1]
entry const frozen_chunks = func (index: U32) => return (Array.from_list large)[index]
entry const floats = func (count: U32) => return
  #[x | x <- @list.generate count (func i => return @f32.add (@u32.to_f32 i) 0.5)]
entry const float_update = func (x: F32) => return do:
  let xs = Array.from_list [x, 2.5]
  let before = xs
  xs[0] := 4.5
  break #[before[0], xs[0], #[3.5, ...xs, 5.5][3]]
@[func value => return value + 1]
entry const tagged = 41
`, guest => {
    equal(guest.read("answer"), 42);
    equal(guest.read("tagged"), 42);
    for (const index of [0, 255, 256, 511, 512]) equal(guest.call("frozen_chunks", index), index);
    for (const index of [0, 255, 256, 8191, 8192]) equal(guest.call("frozen_item", index), index);
    for (const value of [42, 99, 123]) equal([...(guest.call("frozen_edit", value) as Uint32Array)].join(","), `8192,${value}`);
    const floats = guest.call("floats", 513) as Float32Array;
    for (let i = 0; i < floats.length; i++) equal(floats[i], i + 0.5);
    // `before` aliases `xs`, so it sees the write (tasks/LANGUAGE_COHERENCE.md A7).
    equal([...(guest.call("float_update", 1.5) as Float32Array)].join(","), "4.5,4.5,5.5");
  });
});

Deno.test("owned comprehensions keep the selected elements in order", async () => {
  await compileAndRun(`
entry const compact = func (count: U32) => return
  #[i + 1 | i <- @array.generate count (func i => return i), i % 2 == 0]
`, guest => {
    const count = 4097;
    const compact = guest.call("compact", count) as Uint32Array;
    equal(compact.length, 2049);
    for (let i = 0; i < compact.length; i++) equal(compact[i], i * 2 + 1);
  });
});

Deno.test("ordinary list library functions compose with prelude methods", async () => {
  await compileAndRun(`
import * as list from "../../std/list"
entry const run = func (value: U32) => return do:
  let values = list.map (func x => return x + 1) (list.prepend value [1, 2, 3])
  let selected = list.filter (func x => return x > 2) values
  let total = list.fold_left U32.add 0 selected
  break #[total, (Array.from_list values)[0], values.length]
`, guest => {
    equal([...(guest.call("run", 40) as Uint32Array)].join(","), "48,41,4");
  });
});

Deno.test("lists reject indexed reads updates and public indexing intrinsics", async () => {
  const rejected = [
    "entry const run = [1, 2][0]",
    "const first = func xs => return xs[0]\nentry const run = first [1, 2]",
    "entry const run = func () => return do:\n  let xs = [1, 2]\n  xs[0] := 3\n  break xs.length",
    "type Item is data = $Item { value: U32 }\nentry const run = func () => return do:\n  let xs = [$Item { value: 1 }]\n  xs[0].value := 3\n  break xs.length",
  ];
  for (const source of rejected) await compileExpectedFailure(source + "\n", "type_mismatch");
  for (const source of ["@list.get [1] 0", "@list.set [1] 0 2"]) {
    await compileExpectedFailure(`entry const run = ${source}\n`, "unknown_intrinsic");
  }
  for (const source of ["[1].get 0", "[1].set 0 2"]) {
    await compileExpectedFailure(`entry const run = ${source}\n`, "missing_member");
  }
});
