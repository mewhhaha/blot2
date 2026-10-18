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
    state := simd.u32_xor state (simd.u32_shl 13 state)
    state := simd.u32_xor state (simd.u32_shr 17 state)
    let floats = simd.f32_mul (simd.to_f32 (simd.u32_shr 8 state)) (simd.f32_splat 0.0000000596)
    let chosen = simd.f32_select (simd.f32_lt floats (simd.f32_splat 0.5)) floats (simd.f32_neg floats)
    let mixed = simd.f32_shuffle (0, 5, 2, 7) chosen (simd.f32_swizzle (3, 2, 1, 0) chosen)
    acc := simd.f32_add (simd.f32_min acc (simd.f32_splat 100.0)) (simd.f32_max mixed (simd.f32_broadcast 1 mixed))
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
  return simd.f32_sum kept + sum 1.0 + simd.f32_dot rows[0] rows[1]
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

Deno.test("three-operand SIMD wrappers stay in v128 locals outside loops", async () => {
  await compileAndRun(`
import * as simd from "std/simd"
const pick = fn (h: U32) => fn (x: F32) -> F32 => do:
  let r = simd.f32_select (simd.u32_lt (simd.u32_splat h) (simd.u32_splat 8)) (simd.f32_splat x) (1.0, 2.0, 3.0, 4.0)
  let (a, b, c, d) = r
  return ((a + b) + c) + d
const bits = fn (h: U32) -> U32 => do:
  let r = simd.u32_select (simd.u32_splat h) (5, 6, 7, 8) (9, 10, 11, 12)
  let (a, b, c, d) = r
  return a + b + c + d
const fused = fn (x: F32) -> F32 => do:
  let r = simd.f32_relaxed_madd (simd.f32_splat x) (2.0, 2.0, 2.0, 2.0) (1.0, 1.0, 1.0, 1.0)
  let (a, b, c, d) = r
  return ((a + b) + c) + d
entry const run = fn (n: U32) -> F32 => do:
  let total = 0.0
  for i in 0..n:
    total := total + pick (i % 16) 0.5 + @u32.to_f32 (bits (if i % 2 == 0 then 0 else 0xFFFFFFFF)) + fused 0.25
  return total
`, (_, bytes) => {
    const guest = counters(bytes);
    const short = guest.run("run", 2);
    const long = guest.run("run", 1000);
    deepStrictEqual(short.traffic, [0, 0, 0]);
    deepStrictEqual(long.traffic, [0, 0, 0]);
    // h < 8 takes x in every lane; mask 0 picks 9..12, all ones 5..8.
    equal(short.result, 2 * 2 + (42 + 26) + 2 * 6);
  }, { stdRoot });
});

// Every lane of a four-lane operation must have the bits of the scalar kernel
// it replaces, including NaN, signed zero, subnormals and shift counts >= 32.
const kernels = `
import * as simd from "std/simd"

const floats = #[0.0, -0.0, 1.0, -1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0, 0.5, -0.5, 1e-45, 3.0, -3.0]
const integers = #[0, 1, 2, 31, 32, 33, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFF, 12345, 64, 5]
const float_at = fn (index: U32) -> F32 => floats[index % floats.length]
const integer_at = fn (index: U32) -> U32 => integers[index % integers.length]
const float_quad = fn (start: U32) -> simd.F32x4 => (float_at start, float_at (start + 1), float_at (start + 2), float_at (start + 3))
const integer_quad = fn (start: U32) -> simd.U32x4 => (integer_at start, integer_at (start + 1), integer_at (start + 2), integer_at (start + 3))
const mask = fn (holds: Bool) -> U32 => if holds then 0xFFFFFFFF else 0

const float_vector = fn (op: U32) => fn (a: simd.F32x4) => fn (b: simd.F32x4) -> simd.F32x4 =>
  if op == 0 then simd.f32_min a b
  else if op == 1 then simd.f32_max a b
  else if op == 2 then simd.f32_add a b
  else if op == 3 then simd.f32_mul a b
  else if op == 4 then simd.f32_select (simd.f32_lt a b) a b
  else simd.f32_div a b
const float_scalar = fn (op: U32) => fn (x: F32) => fn (y: F32) -> F32 =>
  if op == 0 then F32.min x y
  else if op == 1 then F32.max x y
  else if op == 2 then x + y
  else if op == 3 then x * y
  else if op == 4 then (if x < y then x else y)
  else x / y
const float_compare = fn (op: U32) => fn (a: simd.F32x4) => fn (b: simd.F32x4) -> simd.U32x4 =>
  if op == 0 then simd.f32_eq a b
  else if op == 1 then simd.f32_ne a b
  else if op == 2 then simd.f32_lt a b
  else if op == 3 then simd.f32_le a b
  else if op == 4 then simd.f32_gt a b
  else simd.f32_ge a b
const float_holds = fn (op: U32) => fn (x: F32) => fn (y: F32) -> Bool =>
  if op == 0 then x == y
  else if op == 1 then x != y
  else if op == 2 then x < y
  else if op == 3 then x <= y
  else if op == 4 then x > y
  else x >= y
const integer_vector = fn (op: U32) => fn (a: simd.U32x4) => fn (b: simd.U32x4) -> simd.U32x4 =>
  if op == 0 then simd.u32_min a b
  else if op == 1 then simd.u32_max a b
  else if op == 2 then simd.u32_eq a b
  else if op == 3 then simd.u32_ne a b
  else if op == 4 then simd.u32_lt a b
  else if op == 5 then simd.u32_le a b
  else if op == 6 then simd.u32_gt a b
  else if op == 7 then simd.u32_ge a b
  else if op == 8 then simd.u32_andnot a b
  else if op == 9 then simd.u32_select a b (simd.u32_not b)
  else simd.u32_not a
const integer_scalar = fn (op: U32) => fn (x: U32) => fn (y: U32) -> U32 =>
  if op == 0 then min x y
  else if op == 1 then max x y
  else if op == 2 then mask (x == y)
  else if op == 3 then mask (x != y)
  else if op == 4 then mask (x < y)
  else if op == 5 then mask (x <= y)
  else if op == 6 then mask (x > y)
  else if op == 7 then mask (x >= y)
  else if op == 8 then x & (y ^ 0xFFFFFFFF)
  else if op == 9 then (y & x) | ((y ^ 0xFFFFFFFF) & (x ^ 0xFFFFFFFF))
  else x ^ 0xFFFFFFFF
const shifted = fn (op: U32) => fn (count: U32) => fn (a: simd.U32x4) -> simd.U32x4 =>
  if op == 0 then simd.u32_shl count a
  else if op == 1 then simd.u32_shr count a
  else simd.u32_sar count a

entry const vector_floats = fn (op: U32) -> Array F32 => do:
  let out: Array F32 = #[]
  for i in 0..floats.length:
    for j in 0..floats.length:
      let (a, b, c, d) = float_vector op (float_quad i) (float_quad j)
      out := #[...out, a, b, c, d]
  return out
entry const scalar_floats = fn (op: U32) -> Array F32 => do:
  let out: Array F32 = #[]
  for i in 0..floats.length:
    for j in 0..floats.length:
      for k in 0..4:
        out := #[...out, float_scalar op (float_at (i + k)) (float_at (j + k))]
  return out
entry const vector_float_masks = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..floats.length:
    for j in 0..floats.length:
      let (a, b, c, d) = float_compare op (float_quad i) (float_quad j)
      out := #[...out, a, b, c, d]
  return out
entry const scalar_float_masks = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..floats.length:
    for j in 0..floats.length:
      for k in 0..4:
        out := #[...out, mask (float_holds op (float_at (i + k)) (float_at (j + k)))]
  return out
entry const vector_integers = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..integers.length:
    for j in 0..integers.length:
      let (a, b, c, d) = integer_vector op (integer_quad i) (integer_quad j)
      out := #[...out, a, b, c, d]
  return out
entry const scalar_integers = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..integers.length:
    for j in 0..integers.length:
      for k in 0..4:
        out := #[...out, integer_scalar op (integer_at (i + k)) (integer_at (j + k))]
  return out
entry const vector_shifts = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..integers.length:
    for j in 0..integers.length:
      let (a, b, c, d) = shifted op (integer_at j) (integer_quad i)
      out := #[...out, a, b, c, d]
  return out
entry const scalar_shifts = fn (op: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..integers.length:
    for j in 0..integers.length:
      for k in 0..4:
        let x = integer_at (i + k)
        let count = integer_at j
        out := #[...out, if op == 0 then x << count else x >> count]
  return out
entry const float_table = fn (unused: U32) -> Array F32 => floats
entry const lane_bits = fn (unused: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..floats.length:
    let (a, b, c, d) = simd.f32_bits (float_quad i)
    out := #[...out, a, b, c, d]
  return out
entry const lane_floats = fn (unused: U32) -> Array F32 => do:
  let out: Array F32 = #[]
  for i in 0..integers.length:
    let (a, b, c, d) = simd.f32_from_bits (integer_quad i)
    out := #[...out, a, b, c, d]
  return out
entry const reductions = fn (unused: U32) -> Array U32 => do:
  let out: Array U32 = #[]
  for i in 0..integers.length:
    let lanes = integer_quad i
    out := #[...out, if simd.any_true lanes then 1 else 0, if simd.all_true lanes then 1 else 0]
  return out
const staged_float_table = vector_floats 0
const staged_mask_table = vector_float_masks 1
const staged_integer_table = vector_integers 9
const staged_shift_table = vector_shifts 2
entry const staged_floats = fn (unused: U32) -> Array F32 => staged_float_table
entry const staged_masks = fn (unused: U32) -> Array U32 => staged_mask_table
entry const staged_integers = fn (unused: U32) -> Array U32 => staged_integer_table
entry const staged_shifts = fn (unused: U32) -> Array U32 => staged_shift_table
`;

const words = (value: unknown) => {
  const view = value as Float32Array | Uint32Array;
  return Array.from(new Uint32Array(view.buffer, view.byteOffset, view.length));
};
const integerTable = [0, 1, 2, 31, 32, 33, 0x80000000, 0xffffffff, 0x7fffffff, 12345, 64, 5];
const floatBits = (value: number) => new Uint32Array(Float32Array.of(value).buffer)[0];

Deno.test("explicit SIMD lanes are bit-identical to their scalar kernels and to staging", async () => {
  await compileAndRun(kernels, guest => {
    for (let op = 0; op <= 5; op++) {
      deepStrictEqual(words(guest.call("vector_floats", op)), words(guest.call("scalar_floats", op)), `float operation ${op}`);
      deepStrictEqual(words(guest.call("vector_float_masks", op)), words(guest.call("scalar_float_masks", op)), `float comparison ${op}`);
    }
    for (let op = 0; op <= 10; op++) deepStrictEqual(words(guest.call("vector_integers", op)), words(guest.call("scalar_integers", op)), `integer operation ${op}`);
    for (let op = 0; op <= 1; op++) deepStrictEqual(words(guest.call("vector_shifts", op)), words(guest.call("scalar_shifts", op)), `shift ${op}`);
    // The prelude's min/max pick the right operand for NaN and equal zeros.
    const minimum = guest.call("vector_floats", 0) as Float32Array;
    deepStrictEqual(floatBits(minimum[4 * 13 + 0]), floatBits(-0)); // min(-0, -0) from i=1, j=1
    deepStrictEqual(floatBits(minimum[4 * (0 * 12 + 1)]), floatBits(-0)); // min(+0, -0) chooses -0
    deepStrictEqual(floatBits(minimum[4 * (1 * 12 + 0)]), floatBits(0)); // min(-0, +0) chooses +0
    // Arithmetic shifts copy the sign bit; counts wrap modulo 32.
    const arithmetic = words(guest.call("vector_shifts", 2));
    const expected: number[] = [];
    for (let i = 0; i < 12; i++) {
      for (let j = 0; j < 12; j++) {
        for (let k = 0; k < 4; k++) expected.push((integerTable[(i + k) % 12] | 0) >> (integerTable[j] & 31) >>> 0);
      }
    }
    deepStrictEqual(arithmetic, expected);
    // Compare with the guest's own table: a NaN constant's sign is the host's.
    const table = words(guest.call("float_table", 0));
    deepStrictEqual(table.slice(0, 4).concat(table.slice(5)), [0, -0, 1, -1, Infinity, -Infinity, 0.5, -0.5, 1e-45, 3, -3].map(floatBits));
    deepStrictEqual(words(guest.call("lane_bits", 0)), Array.from({ length: 48 }, (_, n) => table[(Math.floor(n / 4) + n % 4) % 12]));
    deepStrictEqual(words(guest.call("lane_floats", 0)), Array.from({ length: 48 }, (_, n) => integerTable[(Math.floor(n / 4) + n % 4) % 12] >>> 0));
    deepStrictEqual(Array.from(guest.call("reductions", 0) as Uint32Array), Array.from({ length: 12 }, (_, i) => {
      const lanes = [0, 1, 2, 3].map(k => integerTable[(i + k) % 12]);
      return [lanes.some(lane => lane !== 0) ? 1 : 0, lanes.every(lane => lane !== 0) ? 1 : 0];
    }).flat());
    deepStrictEqual(words(guest.call("staged_floats", 0)), words(guest.call("vector_floats", 0)));
    deepStrictEqual(words(guest.call("staged_masks", 0)), words(guest.call("vector_float_masks", 1)));
    deepStrictEqual(words(guest.call("staged_integers", 0)), words(guest.call("vector_integers", 9)));
    deepStrictEqual(words(guest.call("staged_shifts", 0)), words(guest.call("vector_shifts", 2)));
  }, { stdRoot });
});

Deno.test("SIMD lane movement, dot products and relaxed multiply-add", async () => {
  await compileAndRun(`
import * as simd from "std/simd"
import { Vec3 } from "std/vector"
entry const moved = fn (seed: F32) -> Array F32 => do:
  let left = (seed, 1.0, 2.0, 3.0)
  let right = (4.0, 5.0, 6.0, 7.0)
  let (a, b, c, d) = simd.f32_shuffle (1, 4, 3, 6) left right
  let (e, f, g, h) = simd.f32_swizzle (3, 2, 1, 0) left
  let (i, j, k, l) = simd.f32_broadcast 2 left
  let (m, n, o, p) = simd.f32_shuffle (7, 7, 0, 0) left right
  return #[a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]
entry const moved_words = fn (seed: U32) -> Array U32 => do:
  let (a, b, c, d) = simd.u32_shuffle (0, 5, 2, 7) (seed, 1, 2, 3) (4, 5, 6, 7)
  let (e, f, g, h) = simd.u32_swizzle (1, 1, 3, 0) (seed, 1, 2, 3)
  let (i, j, k, l) = simd.u32_broadcast 0 (seed, 1, 2, 3)
  return #[a, b, c, d, e, f, g, h, i, j, k, l]
entry const dots = fn (seed: F32) -> Array F32 => do:
  let left = (seed, 0.1, 1e30, -3.5)
  let right = (0.3, seed, -1e30, 2.25)
  let (ax, ay, az, aw) = left
  let (bx, by, bz, bw) = right
  let vector = #Vec3 { x: ax, y: ay, z: az }.dot(#Vec3 { x: bx, y: by, z: bz })
  return #[simd.f32_dot3 left right, vector, simd.f32_dot left right, ((ax * bx + ay * by) + az * bz) + aw * bw]
entry const madd = fn (seed: F32) -> Array F32 => do:
  let (a, b, c, d) = simd.f32_relaxed_madd (seed, 1.0, 2.0, 3.0) (3.0, 0.1, 0.5, 0.25) (1.0, 0.2, -1.0, 0.0)
  return #[a, b, c, d]
`, guest => {
    deepStrictEqual(Array.from(guest.call("moved", 9) as Float32Array), [1, 4, 3, 6, 3, 2, 1, 9, 2, 2, 2, 2, 7, 7, 9, 9]);
    deepStrictEqual(Array.from(guest.call("moved_words", 9) as Uint32Array), [9, 5, 2, 7, 1, 1, 3, 9, 9, 9, 9, 9]);
    for (const seed of [0.7, -0, 1e-30]) {
      const [dot3, vector, dot4, scalar] = words(guest.call("dots", seed));
      equal(dot3, vector);
      equal(dot4, scalar);
    }
    // Each lane is either fused or separately rounded, depending on the host.
    const lanes = Array.from(guest.call("madd", 1.5) as Float32Array);
    const inputs = [[1.5, 3, 1], [1, 0.1, 0.2], [2, 0.5, -1], [3, 0.25, 0]].map(lane => lane.map(Math.fround));
    inputs.forEach(([a, b, c], index) => {
      const fused = Math.fround(a * b + c);
      const separate = Math.fround(Math.fround(a * b) + c);
      if (lanes[index] !== fused && lanes[index] !== separate) throw new Error(`lane ${index}: ${lanes[index]}`);
    });
  }, { stdRoot });
});

Deno.test("SIMD lane selectors must be literals at a direct call", async () => {
  const { compileExpectedFailure } = await import("./compile_helpers.ts");
  for (const body of [
    "simd.f32_sum (simd.f32_swizzle (lane, 0, 0, 0) (1.0, 2.0, 3.0, 4.0))",
    "simd.f32_sum (simd.f32_broadcast lane (1.0, 2.0, 3.0, 4.0))",
    "simd.f32_sum (simd.f32_shuffle (8, 0, 1, 2) (1.0, 2.0, 3.0, 4.0) (5.0, 6.0, 7.0, 8.0))",
    "simd.u32_sum (simd.u32_swizzle (0, 4, 1, 2) (1, 2, 3, 4)) + lane",
    "simd.f32_sum (@simd.f32x4.swizzle (lane, 1, 2, 3) (1.0, 2.0, 3.0, 4.0))",
  ]) {
    await compileExpectedFailure(`
import * as simd from "std/simd"
entry const run = fn (lane: U32) => ${body}
`, "simd_lane_literal", undefined, { stdRoot });
  }
});
