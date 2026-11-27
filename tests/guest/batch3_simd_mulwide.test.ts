import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const opts = { stdRoot: new URL("../../std", import.meta.url).pathname };

Deno.test("Batch 3: F64x2 SIMD arithmetic, load/store, comparisons, select and canonical NaN", async () => {
  await compileAndRun(
    `
import * as simd from "std/simd"

io test_f64x2 (n: U32): Array U32 =>
  let z: F64 = 0.0
  let a: #[F64] = @array.fill 4 z
  let b: #[F64] = @array.fill 4 z
  let out: #[F64] = @array.fill 4 z
  a[0] := 1.5
  a[1] := 4.0
  a[2] := 9.0
  a[3] := -2.25
  b[0] := 2.5
  b[1] := 2.0
  b[2] := 3.0
  b[3] := 0.75
  let v0 = simd.load_f64x2 0 a
  let v1 = simd.load_f64x2 0 b
  let sum = simd.f64_add v0 v1
  let prod = simd.f64_mul sum (simd.f64_splat 2.0)
  out := simd.store_f64x2 0 prod self
  let v2 = simd.load_f64x2 2 a
  let v3 = simd.load_f64x2 2 b
  let sq = simd.f64_sqrt (simd.f64_abs v2)
  let mask = simd.f64_gt v2 v3
  let sel = simd.f64_select mask sq v3
  out := simd.store_f64x2 2 sel self
  // Canonical NaN check on 0.0 / 0.0 via f64x2.div
  let nan_v = simd.f64_div (simd.f64_splat 0.0) (simd.f64_splat 0.0)
  let (nan_lo, nan_hi) = simd.f64_bits nan_v
  let nan_ok: U32 = if nan_lo == 0x7ff8000000000000 and nan_hi == 0x7ff8000000000000 then 1 else 0
  let r0 = F64.to_u32 (out[0] * 100.0)
  let r1 = F64.to_u32 (out[1] * 100.0)
  let r2 = F64.to_u32 (out[2] * 100.0)
  let r3 = F64.to_u32 (out[3] * 100.0)
  return #[r0, r1, r2, r3, nan_ok]
`,
    (guest) => {
      // out[0]=(1.5+2.5)*2=8.0 -> 800
      // out[1]=(4.0+2.0)*2=12.0 -> 1200
      // out[2]=sqrt(9.0)=3.0 (9>3 true) -> 300
      // out[3]=0.75 (-2.25>0.75 false) -> 75
      assert.deepEqual(Array.from(guest.call("test_f64x2", 0) as Uint32Array), [
        800,
        1200,
        300,
        75,
        1,
      ]);
    },
    opts,
  );
});

Deno.test("Batch 3: U8x16 and I16x8 SIMD load/store, widen/mul/shift/narrow, eq/bitmask", async () => {
  await compileAndRun(
    `
import * as simd from "std/simd"

io test_u8_i16 (n: U32): Array U32 =>
  let z8: U8 = 0
  let src: #[U8] = @array.fill 16 z8
  let dst: #[U8] = @array.fill 16 z8
  for i in 0..16:
    src[i] := U32.to_u8 (i * 10)
  let v = simd.load_u8x16 0 src
  // Check eq + bitmask on byte value 30 (lane 3)
  let mask = simd.u8_bitmask (simd.u8_eq v (simd.u8_splat 30))
  // Widen to I16x8, multiply by 2, add 10, shift right by 1 => (x * 2 + 10) >> 1 = x + 5
  let lo16 = simd.i16_extend_low_u v
  let hi16 = simd.i16_extend_high_u v
  let two = simd.i16_splat 2
  let ten = simd.i16_splat 10
  let lo_res = simd.i16_shr_u 1 (simd.i16_add (simd.i16_mul lo16 two) ten)
  let hi_res = simd.i16_shr_u 1 (simd.i16_add (simd.i16_mul hi16 two) ten)
  let packed = simd.u8_narrow lo_res hi_res
  dst := simd.store_u8x16 0 packed self
  // Also test u8_avgr: avgr(10, 21) = (10 + 21 + 1) >> 1 = 16
  let av = simd.u8_avgr (simd.u8_splat 10) (simd.u8_splat 21)
  let av_buf: #[U8] = @array.fill 16 z8
  av_buf := simd.store_u8x16 0 av self
  return #[mask, U8.to_u32 dst[0], U8.to_u32 dst[7], U8.to_u32 dst[15], U8.to_u32 av_buf[0]]
`,
    (guest) => {
      // mask = 1 << 3 = 8; dst[0]=5, dst[7]=75, dst[15]=155; av_buf[0]=16
      assert.deepEqual(Array.from(guest.call("test_u8_i16", 0) as Uint32Array), [
        8,
        5,
        75,
        155,
        16,
      ]);
    },
    opts,
  );
});

Deno.test("Batch 3: U64.mul_wide runtime and #run staging, plus F64 trig", async () => {
  await compileAndRun(
    `
const staged_hi: U32 = #do:
  let a: U64 = 0xffff_ffff_ffff_ffff
  let pair = U64.mul_wide a a
  let lo = @product.get pair 0
  let hi = @product.get pair 1
  // (2^64 - 1)^2 = 2^128 - 2^65 + 1 => hi = 2^64 - 2, lo = 1
  break U64.to_u32 (lo + (hi & 0xff))

io test_mul_wide_and_trig (n: U32): Array U32 =>
  let a: U64 = 0x1234_5678_9abc_def0
  let b: U64 = 0xfedc_ba98_7654_3210
  let (lo, hi) = U64.mul_wide a b
  // Exact 128-bit product:
  // 0x123456789abcdef0 * 0xfedcba9876543210 = 0x121fa00ad77d7422_236d88fe5618cf00
  let lo_ok: U32 = if lo == 0x236d88fe5618cf00 then 1 else 0
  let hi_ok: U32 = if hi == 0x121fa00ad77d7422 then 1 else 0
  let s = F64.sin 1.0
  let c = F64.cos 1.0
  // sin^2(1) + cos^2(1) == 1.0 within 1e-14
  let pyth = F64.abs (s * s + c * c - 1.0)
  let s_err = F64.abs (s - 0.8414709848078965)
  let c_err = F64.abs (c - 0.5403023058681398)
  let trig_ok: U32 = if pyth < 1e-14 and s_err < 1e-14 and c_err < 1e-14 then 1 else 0
  return #[staged_hi, lo_ok, hi_ok, trig_ok]
`,
    (guest) => {
      // staged_hi = 1 + 0xfe = 255
      assert.deepEqual(
        Array.from(guest.call("test_mul_wide_and_trig", 0) as Uint32Array),
        [255, 1, 1, 1],
      );
    },
  );
});
