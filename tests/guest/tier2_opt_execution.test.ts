import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;

function asWords(value: unknown): number[] {
  const view = value as Float32Array | Uint32Array;
  return Array.from(
    new Uint32Array(view.buffer, view.byteOffset, view.length),
  );
}

Deno.test("Tier 2A-2D: inline array.generate closures, F32 NaN elision, spark in-place reuse, and loop/guard bounds", async () => {
  await compileAndRun(
    `import * as array from "std/array"

type Vec2 is data = $Vec2 { x: F32, y: F32 }
type SoaPair is data = $SoaPair { px: #[F32], vx: #[F32] }

// 2A: inline array.generate with captures, aggregates, and early return inside closure
entry func gen_inline_early_return (n: U32): U32 =>
  let bias: U32 = 2
  let pts = array.generate n (func i =>
    if i == 0:
      return $Vec2 { x: 100.0, y: 200.0 }
    let v = U32.to_f32 (i + bias)
    return $Vec2 { x: v, y: v * 2.0 })
  let acc = 0.0
  for i in 0 .. pts.length:
    let $Vec2 { x, y } = pts[i]
    acc := self + x + y
  return F32.to_u32 acc

// 2A fallback: allocating generator closure (nested array inside generator)
entry func gen_allocating_fallback (n: U32): U32 =>
  let rows = array.generate n (func i => @array.fill 3 (i + 1))
  let total: U32 = 0
  for i in 0 .. rows.length:
    total := self + rows[i][0] + rows[i][2]
  return total

// 2B: register-only F32 loop vs observable canonical NaN bit boundaries
entry func f32_nan_boundaries (seed: U32): #[F32] =>
  let zero = U32.to_f32 (seed & 0)
  let raw_nan = zero / zero
  let neg_nan = F32.neg (zero / zero)
  let abs_nan = F32.abs (zero / zero)
  let stored = #[zero / zero, (1.0 / zero) - (1.0 / zero)]
  // Register-only loop (Mandelbrot shape): NaN elided internally, exact count out
  let zr = 0.0
  let zi = 0.0
  let it: U32 = 0
  for ever:
    if it >= 20:
      break
    let zr2 = zr * zr
    let zi2 = zi * zi
    if zr2 + zi2 > 4.0:
      break
    let next_zi = 2.0 * zr * zi + 0.25
    zr := zr2 - zi2 + 0.5
    zi := next_zi
    it := self + 1
  return #[raw_nan, neg_nan, abs_nan, stored[0], stored[1], U32.to_f32 it]

// 2C: uniquely-owned destructured own struct + in-place spark reuse over non-multiple-of-4 length
func step_owned_pair (st: own SoaPair) -> (steps: U32): (SoaPair, U32) =>
  let $SoaPair { px, vx } = st
  let n = px.length
  for _ in 0 .. steps:
    px := spark #[px[i] + vx[i] | i <- 0 .. n]
  let sum = 0.0
  for i in 0 .. n:
    sum := self + px[i]
  return ($SoaPair { px, vx }, F32.to_u32 (sum * 10.0))

entry func spark_reuse_owned (n: U32): U32 =>
  let px = array.generate n (func i => U32.to_f32 i)
  let vx = @array.fill n 0.5
  let (_, out) = step_owned_pair ($SoaPair { px, vx }) 6
  return out

// 2C: aliased array MUST NOT be mutated by spark
entry func spark_aliased_no_corrupt (n: U32): U32 =>
  let px = array.generate n (func i => U32.to_f32 (i + 1))
  let saved = px
  px := spark #[px[i] * 2.0 + 1.0 | i <- 0 .. n]
  let s_old = 0.0
  let s_new = 0.0
  for i in 0 .. n:
    s_old := self + saved[i]
    s_new := self + px[i]
  return F32.to_u32 s_old * 10000 + F32.to_u32 s_new

// 2C: non-zero start / mismatched length / shifted offset fall back cleanly
entry func spark_reuse_guards (n: U32): U32 =>
  let px = array.generate n (func i => U32.to_f32 (i + 1))
  let shifted = spark #[px[i + 1] + 10.0 | i <- 0 .. (n - 1)]
  let sub = spark #[px[i] * 2.0 | i <- 1 .. n]
  let acc = 0.0
  for i in 0 .. shifted.length:
    acc := self + shifted[i] + sub[i]
  return F32.to_u32 acc

// 2D: length alias + if-merge CheckedArray + guard CheckedBound + OOB trap preservation
entry func guard_bounds_ok (n: U32): U32 =>
  let flags = @array.fill n true
  if n > 0:
    flags[0] := false
  if n > 1:
    flags[1] := false
  let m: U32 = 2
  for ever:
    if m >= n:
      break
    flags[m] := false
    m := self + 2
  let count: U32 = 0
  for i in 0 .. n:
    if flags[i]:
      count := self + 1
  return count

entry func guard_bounds_trap (n: U32): U32 =>
  let arr = @array.fill n 7
  let bad = n + 1
  let acc: U32 = 0
  for i in 0 .. bad:
    acc := self + arr[i]
  return acc
`,
    (guest) => {
      // 2A: i=0 -> 300; i=1..4 with bias=2 -> 3*(3+4+5+6) = 54 => 354
      equal(guest.call("gen_inline_early_return", 5), 354);
      // 2A fallback: sum_{i=0..3} 2*(i+1) = 2*(1+2+3+4) = 20
      equal(guest.call("gen_allocating_fallback", 4), 20);
      // 2B: exact canonical quiet NaN bits preserved at every observable boundary
      const nanRes = asWords(guest.call("f32_nan_boundaries", 0));
      equal(nanRes[0], 0x7fc00000);
      equal(nanRes[1], 0xffc00000);
      equal(nanRes[2], 0x7fc00000);
      equal(nanRes[3], 0x7fc00000);
      equal(nanRes[4], 0x7fc00000);
      equal(nanRes[5], 0x40a00000); // 5.0f32 (c = 0.5 + 0.25i escapes at iter 5)
      // 2C: n=13, steps=6 -> sum_{i=0..12} (i + 3) = 78 + 39 = 117 -> *10 = 1170
      equal(guest.call("spark_reuse_owned", 13), 1170);
      // 2C aliased: n=8 -> old=1+..+8=36, new=2*36+8=80 -> 360080
      equal(guest.call("spark_aliased_no_corrupt", 8), 360080);
      // 2C guards: n=6 -> px=[1..6], shifted=[12,13,14,15,16] (sum 70), sub=[4,6,8,10,12] (sum 40) => 110
      equal(guest.call("spark_reuse_guards", 6), 110);
      // 2D: n=10 -> flags[0]=F, [1]=F, evens=F, odds 3,5,7,9=T => 4
      equal(guest.call("guard_bounds_ok", 10), 4);
      equal(guest.call("guard_bounds_ok", 0), 0);
      throws(() => guest.call("guard_bounds_trap", 5));
    },
    { stdRoot },
  );
});

Deno.test("Tier 2E: byte-packed #[Bool] arrays across fill, update, spread, ABI packets, records, and fork rollback", async () => {
  await compileAndRun(
    `import * as flat from "std/flat"

type Flagged is data = $Flagged { flag: Bool, val: U32 }

// Byte-packed #[Bool] roundtrip + flat.encode/flat.decode on #[4; Bool]
entry func bool_roundtrip (xs: #[U32]): #[U32] =>
  let bs = @array.generate xs.length (func i => xs[i] != 0)
  for i in 0 .. bs.length:
    bs[i] := Bool.not self
  return @array.generate bs.length (func i => if bs[i] then 1 else 0)

entry func bool_flat_roundtrip (mask: U32): U32 =>
  let arr: #[4; Bool] = #[
    (mask & 1) != 0,
    (mask & 2) != 0,
    (mask & 4) != 0,
    (mask & 8) != 0,
  ]
  let words = flat.encode arr
  let dec: Maybe #[4; Bool] = flat.decode words
  if let $Some out = dec:
    let res: U32 = 0
    for i in 0 .. 4:
      if out[i]:
        res := self | (1 << i)
    return res
  return 999

// Fill, slice, spread, linearAppend, self-update on odd/even/large sizes
entry func bool_ops_checksum (n: U32): U32 =>
  let a = @array.fill n true
  let b = @array.fill n false
  for i in 0 .. n:
    if (i % 3) == 0:
      a[i] := false
      b[i] := true
  let s = @array.slice a 1 (if n > 2 then n - 2 else 0)
  let c = #[true, ...s, false]
  let grown = c.copy
  grown := @array.append grown true
  grown := @array.append grown false
  let acc: U32 = 0
  for i in 0 .. grown.length:
    if grown[i]:
      acc := self + (i + 1)
  for i in 0 .. b.length:
    if b[i]:
      acc := self + 1000
  return acc

// Record elements containing Bool MUST keep 4-byte flat field layout (not 1-byte!)
entry func record_bool_field (n: U32): U32 =>
  let xs = @array.fill n ($Flagged { flag: true, val: 0x12345678 })
  for i in 0 .. n:
    if (i & 1) == 0:
      xs[i].flag := Bool.not self
      xs[i].val := i + 10
  let sum: U32 = 0
  for i in 0 .. n:
    let $Flagged { flag, val } = xs[i]
    if flag:
      sum := self + (val & 255)
    else:
      sum := self + val
  return sum

// Fork rollback on 1-byte #[Bool] must restore target byte without corrupting neighbors
entry func bool_fork_rollback (unused: U32): U32 =>
  let flags = #[true, false, true, false, true]
  let _ = fork flags:
    flags[1] := true
    flags[2] := false
    flags[3] := true
    return 99
  let mask: U32 = 0
  for i in 0 .. flags.length:
    if flags[i]:
      mask := self | (1 << i)
  return mask
`,
    (guest) => {
      for (const n of [0, 1, 3, 4, 5, 17]) {
        const input = Uint32Array.from(
          { length: n },
          (_, i) => (i % 3 === 0 ? 1 : 0),
        );
        const expected = Array.from(input, (v) => (v === 1 ? 0 : 1));
        deepStrictEqual(asWords(guest.call("bool_roundtrip", input)), expected);
      }
      for (let mask = 0; mask < 16; mask++) {
        equal(guest.call("bool_flat_roundtrip", mask), mask);
      }
      // n=7: a=[F,T,T,F,T,T,F], b=[T,F,F,T,F,F,T] (3 trues -> 3000)
      // s = a[1..6] = [T,T,F,T,T], c=[T,T,T,F,T,T,F], grown=[T,T,T,F,T,T,F,T,F]
      // true 1-based indices in grown: 1+2+3+5+6+8 = 25 => 3025
      equal(guest.call("bool_ops_checksum", 7), 3025);
      // Record-of-Bool: n=4 -> i=0: (F,10), i=1: (T,0x78=120), i=2: (F,12), i=3: (T,120) => 262
      equal(guest.call("record_bool_field", 4), 262);
      // Fork rollback: original [T,F,T,F,T] => bits 0,2,4 => 1+4+16 = 21
      equal(guest.call("bool_fork_rollback", 0), 21);
    },
    { stdRoot },
  );
});

Deno.test("Tier 2F: in-place for-loop auto-SIMD matches scalar across tails, offsets, and overlapping dependencies", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-tier2f-simd-" });
  const entry = `${dir}/main.blot`;
  const src = `// 1. SAXPY with affine local offset alias (matmul_64 inner-loop shape)
entry func saxpy_offset (n: U32): #[F32] =>
  let row: U32 = 1
  let total = n * 2
  let c = @array.fill total 1.0
  let b = @array.fill total 0.0
  for i in 0 .. total:
    b[i] := U32.to_f32 (i + 1) * 0.5
  let row_off = row * n
  let k_off = (1 - row) * n
  let scale = 2.5
  for col in 0 .. n:
    let dst = row_off + col
    c[dst] := c[dst] + scale * b[k_off + col]
  return c

// 2. U32 in-place elementwise for loop with non-zero start
entry func u32_subrange (n: U32): #[U32] =>
  let dst = @array.fill n 10
  let src = @array.fill n 0
  for i in 0 .. n:
    src[i] := i * 3 + 1
  for i in 2 .. n:
    dst[i] := dst[i] + src[i] * 2
  return dst

// 3. Loop-carried forward overlap dependency a[i + 1] := a[i] + 1
//    MUST NOT mis-vectorize; runtime overlap guard must fall back to sequential scalar!
entry func overlap_forward (n: U32): #[U32] =>
  let a = @array.fill n 0
  if n > 0:
    a[0] := 1
  for i in 0 .. (if n > 0 then n - 1 else 0):
    a[i + 1] := a[i] + 1
  return a

// 4. Loop-carried stride-2 overlap dependency a[i + 2] := a[i] + 10
entry func overlap_stride2 (n: U32): #[U32] =>
  let a = @array.fill n 0
  if n > 0:
    a[0] := 1
  if n > 1:
    a[1] := 2
  for i in 0 .. (if n > 2 then n - 2 else 0):
    a[i + 2] := a[i] + 10
  return a

// 5. Out-of-bounds stream inside vectorizable for loop must trap cleanly
entry func oob_for_simd (n: U32): #[F32] =>
  let dst = @array.fill n 0.0
  let short = @array.fill (if n > 2 then n - 2 else 0) 1.0
  for i in 0 .. n:
    dst[i] := dst[i] + short[i]
  return dst
`;
  try {
    await Deno.writeTextFile(entry, src);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      stdRoot,
    });
    try {
      const built = await compiler.build();
      ok(built.success, JSON.stringify(built));
      // Verify 2F actually emitted Wasm SIMD (0xfd prefix) even with zero spark expressions!
      ok(
        built.bytes.includes(0xfd),
        "Expected 2F auto-SIMD 0xfd instructions in compiled module",
      );
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const n of [0, 1, 3, 4, 5, 7, 8, 13, 16]) {
          const out = Array.from(
            guest.call("saxpy_offset", n) as Float32Array,
          );
          const expected: number[] = [];
          for (let i = 0; i < n; i++) expected.push(1.0);
          for (let col = 0; col < n; col++) {
            expected.push(1.0 + 2.5 * ((col + 1) * 0.5));
          }
          deepStrictEqual(out, expected, `saxpy_offset n=${n}`);

          const uout = asWords(guest.call("u32_subrange", n));
          const uexp = Array.from({ length: n }, (_, i) =>
            i < 2 ? 10 : 10 + (i * 3 + 1) * 2
          );
          deepStrictEqual(uout, uexp, `u32_subrange n=${n}`);

          const fwd = asWords(guest.call("overlap_forward", n));
          const fwdExp = Array.from({ length: n }, (_, i) => i + 1);
          deepStrictEqual(fwd, fwdExp, `overlap_forward n=${n}`);

          const s2 = asWords(guest.call("overlap_stride2", n));
          const s2Exp: number[] = [];
          for (let i = 0; i < n; i++) {
            s2Exp.push(i < 2 ? i + 1 : s2Exp[i - 2] + 10);
          }
          deepStrictEqual(s2, s2Exp, `overlap_stride2 n=${n}`);
        }
        throws(() => guest.call("oob_for_simd", 12));
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
