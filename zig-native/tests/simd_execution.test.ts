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
