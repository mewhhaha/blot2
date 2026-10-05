import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("generated arrays call captured scalar and aggregate callbacks in index order", async () => {
  await compileAndRun(`
type Item is data = #Item { value: U32 }
const indices = @array.generate 3 (fn index => @u32.add index 40)
entry const staged: U32 = @array.get indices 2
entry const generated = fn (offset: U32) -> Array U32 => @array.generate 4 (fn index => @u32.add index offset)
entry const floating = fn (offset: F32) -> Array F32 => @array.generate 3 (fn index => @f32.add (@u32.to_f32 index) offset)
entry const nested = fn (offset: U32) -> U32 => do:
  let items = @array.generate 3 (fn index => #Item { value: @u32.add index offset })
  return (@array.get items 2).value
entry const empty = fn () -> Array U32 => @array.generate 0 (fn (index: U32) -> U32 => @panic "uncalled generator")
`, guest => {
    equal(guest.read("staged"), 42);
    equal([...(guest.call("generated", 40) as Uint32Array)].join(","), "40,41,42,43");
    equal([...(guest.call("floating", 1.5) as Float32Array)].join(","), "1.5,2.5,3.5");
    equal(guest.call("nested", 40), 42);
    equal((guest.call("empty", null) as Uint32Array).length, 0);
  });
});

Deno.test("staged array generation preserves argument and callback failure order", async () => {
  await compileExpectedFailure(`entry const value: U32 = @array.length (@array.generate 0 (@panic "generator argument"))\n`, "const_panic", "generator argument");
  await compileExpectedFailure(`entry const value: U32 = @array.get (@array.generate 1 (fn (index: U32) -> U32 => @panic "first index")) 0\n`, "const_panic", "first index");
});

Deno.test("native arrays preserve snapshots through the existing array guest ABI", async () => {
  await compileAndRun(`
entry const fill = fn (count: U32) -> Array U32 => @array.fill count 7
entry const empty = fn () -> Array U32 => #[]
entry const replace = fn (values: Array U32) -> Array U32 => @array.set values 0 42
entry const first = fn (values: Array F32) -> F32 => @array.get values 0
entry const length = fn (values: Array F32) -> U32 => @array.length values
entry const alias = fn (value: U32) -> U32 => do:
  let before = #[value, 2]
  let after = @array.set before 0 40
  return @u32.add (@array.get before 0) (@array.get after 0)
`, guest => {
    for (const count of [0, 1, 32, 16384, 32769, 1]) {
      const filled = guest.call("fill", count) as Uint32Array;
      equal(filled.length, count);
      for (const value of filled) equal(value, 7);
      if (count) {
        const changed = guest.call("replace", filled) as Uint32Array;
        equal(changed[0], 42);
        equal(filled[0], 7);
        equal(changed.length, count);
      }
      equal((guest.call("empty", null) as Uint32Array).length, 0);
    }
    equal(guest.call("first", new Float32Array([-0, 1.5])), -0);
    equal(guest.call("first", new Float32Array([1.23456789])), Math.fround(1.23456789));
    equal(guest.call("length", new Float32Array()), 0);
    equal(guest.call("alias", 2), 42);
    let trapped = false;
    try { guest.call("replace", new Uint32Array()); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    equal(trapped, true);
    equal(guest.call("alias", 3), 43);
  });
});

Deno.test("selected F32 locals survive generated products and captured arrays without merging generic functions", async () => {
  await compileAndRun(`
const scaled = fn (value: U32) => from value / 65536.0
const place = fn index => do:
  let x = scaled index + 0.5
  return (x, x, index)
const generate = fn count => fn make => @array.generate count make
entry const run = fn (count: U32) -> Bool => do:
  let positions = generate count place
  let flags = generate count (fn index => do:
    let (x, y, _) = positions[index]
    return @f32.eq (@f32.add x y) 1.0)
  return flags[0]
entry const independent = fn () => do:
  let identity = fn value => value
  return @f32.add (@u32.to_f32 (identity 41)) (identity 1.5)
`, guest => {
    for (const count of [1, 2, 4, 32]) equal(guest.call("run", count), true);
    for (let index = 0; index < 100; index++) equal(guest.call("independent", null), 42.5);
  }, { prelude: "std/prelude.blot" });
});

Deno.test("a selected F32 local cannot acquire a U32 type from a later use", async () => {
  await compileExpectedFailure(`
const scaled = fn (value: U32) => from value / 65536.0
entry const wrong = fn (index: U32) -> U32 => do:
  let x = scaled index + 0.5
  return @u32.add x 1
`, "type_mismatch", undefined, { prelude: "std/prelude.blot" });
});

Deno.test("selected F32 data remains typed beside a callable in a destructured product", async () => {
  await compileAndRun(`
const scaled = fn (value: U32) => from value / 65536.0
entry const run = fn (index: U32) => do:
  let pair = (scaled index + 0.5, fn value => value)
  let (x, identity) = pair
  let first = identity 41
  return @f32.add x (@u32.to_f32 first)
`, guest => {
    for (const index of [0, 1, 65536]) equal(guest.call("run", index), Math.fround(index / 65536 + 41.5));
  }, { prelude: "std/prelude.blot" });
  await compileExpectedFailure(`
const scaled = fn (value: U32) => from value / 65536.0
entry const wrong = fn (index: U32) -> U32 => do:
  let pair = (scaled index + 0.5, fn value => value)
  let (value, identity) = pair
  return @u32.add value (identity 41)
`, "type_mismatch", undefined, { prelude: "std/prelude.blot" });
});
