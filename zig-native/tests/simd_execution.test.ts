import { deepStrictEqual, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("explicit SIMD agrees with staging, preserves snapshots and supports partial application", async () => {
  await compileAndRun(`
import * as simd from "std/simd"
const plus = simd.u32_add (1, 2, 3, 4)
const operation = simd.u32_mul
const calculate = fn seed => simd.u32_sum (operation (plus (seed, seed, seed, seed)) (5, 6, 7, 8))
entry const runtime = fn seed => calculate seed
entry const staged = calculate 9
entry const flags = fn seed => simd.u32_sum (simd.u32_xor (simd.u32_and (seed, seed, seed, seed) (1, 2, 4, 8)) (1, 2, 4, 8))
entry const snapshot = fn seed => do:
  let before = #[seed, seed + 1, seed + 2, seed + 3, 99]
  let after = simd.store 1 (simd.u32_add (simd.load 0 before) (10, 20, 30, 40)) before
  return #[before[1], after[0], after[1], after[2], after[3], after[4]]
entry const invalid_load = fn index => simd.u32_sum (simd.load index #[1, 2, 3, 4])
entry const invalid_store = fn index => simd.store index (1, 2, 3, 4) #[1, 2, 3, 4]
entry const ordered = fn (value: F32) => simd.f32_sum (16777216.0, value, value, -16777216.0)
entry const regrouped = fn (value: F32) => simd.f32_sum_pairwise (16777216.0, value, value, -16777216.0)
entry const converted = fn (value: F32) => do:
  let (a, b, c, d) = simd.to_u32 (value, -1.0, 4294967296.0, 0.0 / 0.0)
  return #[a, b, c, d]
entry const floating = fn (value: F32) => do:
  let (a, b, c, d) = simd.f32_sqrt (simd.f32_mul (value, 2.0, 3.0, 4.0) (value, 2.0, 3.0, 4.0))
  return #[a, b, c, d]
`, guest => {
    equal(guest.call("runtime", 9), 304);
    equal(guest.read("staged"), 304);
    equal(guest.call("runtime", 0xffffffff), 44);
    equal(guest.call("flags", 5), 10);
    deepStrictEqual(Array.from(guest.call("snapshot", 5) as Uint32Array), [6, 5, 15, 26, 37, 48]);
    for (const index of [1, 4, 0xffffffff]) {
      throws(() => guest.call("invalid_load", index));
      throws(() => guest.call("invalid_store", index));
    }
    equal(guest.call("ordered", 1), 0);
    equal(guest.call("regrouped", 1), 1);
    deepStrictEqual(Array.from(guest.call("converted", 2.9) as Uint32Array), [2, 0, 0xffffffff, 0]);
    deepStrictEqual(Array.from(guest.call("floating", -5) as Float32Array), [5, 2, 3, 4]);
  }, { stdRoot });
});

Deno.test("automatic SIMD preserves scalar tails, wrapping arithmetic, rounding and trapping kernels", async () => {
  await compileAndRun(`
entry const integers = fn count => @array.generate count (fn index => index * 4294967295 + 17)
entry const floats = fn count => @array.generate count (fn index => (@u32.to_f32 index * 16777216.0 + 1.0) - @u32.to_f32 index * 16777216.0)
entry const division = fn count => @array.generate count (fn index => 12 / (4 - index))
entry const branching = fn count => @array.generate count (fn index => if index < 3 then index else 0)
entry const captured = fn count => do:
  let values = #[10, 20, 30, 40]
  return @array.generate count (fn index => values[index])
`, guest => {
    for (const count of [0, 1, 2, 3, 4, 5, 7, 8, 9, 31, 65, 4099]) {
      deepStrictEqual(Array.from(guest.call("integers", count) as Uint32Array), Array.from({ length: count }, (_, i) => (17 - i) >>> 0));
      deepStrictEqual(Array.from(guest.call("floats", count) as Float32Array), Array.from({ length: count }, (_, i) => Math.fround(Math.fround(Math.fround(i * 16777216) + 1) - Math.fround(i * 16777216))));
      deepStrictEqual(Array.from(guest.call("branching", count) as Uint32Array), Array.from({ length: count }, (_, i) => i < 3 ? i : 0));
    }
    deepStrictEqual(Array.from(guest.call("division", 4) as Uint32Array), [3, 4, 6, 12]);
    throws(() => guest.call("division", 5));
    deepStrictEqual(Array.from(guest.call("captured", 4) as Uint32Array), [10, 20, 30, 40]);
    throws(() => guest.call("captured", 5));
  });
});

Deno.test("four-element Array loads and stores check one range and keep snapshots", async () => {
  await compileAndRun(`
import * as simd from "std/simd"
entry const edited = fn (index: U32) -> Array F32 => do:
  let values = #[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let before = values
  values := simd.store index (simd.f32_mul (simd.load index values) (2.0, 2.0, 2.0, 2.0)) values
  return #[before[index], values[0], values[1], values[2], values[3], values[4], values[5]]
entry const flags = fn (index: U32) -> U32 => do:
  let values = #[#True, #False, #True, #True, #False]
  let (a, b, c, d) = simd.load index values
  let flipped = simd.store index (d, c, b, a) values
  return (if flipped[index] then 1 else 0) + (if flipped[index + 3] then 2 else 0) + (if values[index] then 4 else 0)
`, guest => {
    deepStrictEqual(Array.from(guest.call("edited", 0) as Float32Array), [1, 2, 4, 6, 8, 5, 6]);
    deepStrictEqual(Array.from(guest.call("edited", 2) as Float32Array), [3, 1, 2, 6, 8, 10, 12]);
    for (const index of [3, 4, 0xfffffffd, 0xffffffff]) throws(() => guest.call("edited", index));
    equal(guest.call("flags", 0), 1 + 2 + 4);
    equal(guest.call("flags", 1), 0);
    throws(() => guest.call("flags", 2));
  }, { stdRoot });
});

// Raw instances expose the runtime's ownership counters.
function counters(bytes: Uint8Array<ArrayBuffer>) {
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  const count = (name: string) => Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
  return {
    raw,
    run(name: string, argument: number) {
      const before = ["retains", "releases", "destroyed"].map(count);
      const result = (raw[name] as CallableFunction)(argument, 0);
      const after = ["retains", "releases", "destroyed"].map(count);
      equal(count("roots"), 0);
      equal(count("leases"), 0);
      return { result, traffic: after.map((value, index) => value - before[index]) };
    },
    // Repeated calls must reuse freed boxes rather than grow memory.
    steady(name: string, argument: number) {
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      for (let index = 0; index < 1000; index++) (raw[name] as CallableFunction)(argument, 0);
      const warmed = memory.buffer.byteLength;
      for (let index = 0; index < 20000; index++) (raw[name] as CallableFunction)(argument, 0);
      equal(memory.buffer.byteLength, warmed);
    },
  };
}

Deno.test("private SIMD values stay out of the heap and box once where they escape", async () => {
  await compileAndRun(`
import * as simd from "std/simd"
type Holder is data = #Holder { lanes: simd.F32x4, count: U32 }
// An Array result exports guest memory, whose size the test watches.
entry const exported = fn (n: U32) -> Array U32 => #[n]
entry const accumulate = fn (n: U32) -> F32 => do:
  let acc = simd.f32_splat 0.0
  let k = simd.f32_splat 0.5
  let step = (1.0, 2.0, 3.0, 4.0)
  for i in 0..n:
    acc := simd.f32_add (simd.f32_mul acc k) step
  let (a, b, c, d) = acc
  return ((a + b) + c) + d
entry const kernel = fn (reps: U32) -> F32 => do:
  let values = @array.generate 64 (fn i => @u32.to_f32 i)
  for r in 0..reps:
    for block in 0..16:
      let i = block * 4
      values := simd.store i (simd.f32_add (simd.f32_mul (simd.load i values) (0.5, 0.5, 0.5, 0.5)) (0.25, 0.25, 0.25, 0.25)) values
  return values[7]
entry const mixed = fn (n: U32) -> F32 => do:
  let state = (1, 2, 3, 4)
  let acc = simd.f32_splat 0.0
  for i in 0..n:
    state := simd.u32_xor (simd.u32_mul state (1664525, 1664525, 1664525, 1664525)) (1013904223, 1013904223, 1013904223, 1013904223)
    let floats = simd.f32_mul (simd.to_f32 state) (simd.f32_splat 0.0000000002)
    acc := simd.f32_add (simd.f32_mul acc (simd.f32_splat 0.5)) (simd.f32_sqrt (simd.f32_abs floats))
  return simd.f32_sum acc
const scaled = fn (lanes: simd.F32x4) => fn (n: U32) -> simd.F32x4 => do:
  let acc = lanes
  for i in 0..n:
    acc := simd.f32_mul acc (1.5, 1.5, 1.5, 1.5)
  return acc
entry const returned = fn (n: U32) -> F32 => simd.f32_sum (scaled (1.0, 2.0, 3.0, 4.0) n)
entry const held = fn (n: U32) -> F32 => do:
  let acc = simd.f32_splat 1.0
  for i in 0..n:
    acc := simd.f32_add acc acc
  let holder = #Holder { lanes: acc, count: n }
  let #Holder { lanes, count } = holder
  let maybe = if count > 0 then #Some lanes else #Nothing
  let sum = fn (offset: F32) => simd.f32_sum (simd.f32_add lanes (offset, offset, offset, offset))
  let rows = #[lanes, acc]
  let #Some kept = maybe else:
    return sum 0.0
  return simd.f32_sum kept + sum 1.0 + simd.f32_sum (simd.f32_mul rows[0] rows[1])
`, (_, bytes) => {
    const guest = counters(bytes);
    const short = guest.run("accumulate", 10);
    const long = guest.run("accumulate", 1000);
    deepStrictEqual(short.traffic, [0, 0, 0]);
    deepStrictEqual(long.traffic, [0, 0, 0]);
    equal(long.result, 20);
    // The Array is allocated once; every SIMD edit stays in place.
    deepStrictEqual(guest.run("kernel", 1).traffic, guest.run("kernel", 100).traffic);
    equal(guest.run("kernel", 2).result, 2.125);
    deepStrictEqual(guest.run("mixed", 10).traffic, guest.run("mixed", 1000).traffic);
    // The loop result boxes once when it is returned, however long it runs.
    deepStrictEqual(guest.run("returned", 1).traffic, guest.run("returned", 100).traffic);
    equal(guest.run("returned", 2).result, 22.5);
    equal(guest.run("held", 0).result, 4);
    equal(guest.run("held", 3).result, 32 + 36 + 256);
    for (const name of ["kernel", "mixed", "returned", "held"]) guest.steady(name, 3);
  }, { stdRoot });
});
