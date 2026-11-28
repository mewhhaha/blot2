import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;

function asWords(value: unknown): number[] {
  const view = value as Float32Array | Uint32Array;
  return Array.from(new Uint32Array(view.buffer, view.byteOffset, view.length));
}

Deno.test("Phase 2: uniform 0x7fc00000 NaN canonicalization matches bit-for-bit across spark SIMD, scalar, std/simd, and #run", async () => {
  await compileAndRun(
    `import * as simd from "std/simd"

func make_f32 (bits: U32) : F32 => return do:
  let (x, _, _, _) = simd.f32_from_bits (bits, 0, 0, 0)
  break x

// Non-canonical negative NaN with payload 0x00012345 (0xffc12345).
const non_canon_nan: F32 = make_f32 0xffc12345
const inf: F32 = 1.0 / 0.0
const neg_inf: F32 = -1.0 / 0.0

func apply_f32_op (op: U32) -> (a: F32) -> (b: F32) : F32 => return
  if op == 0 then a + b
  else if op == 1 then a - b
  else if op == 2 then a * b
  else if op == 3 then a / b
  else if op == 4 then sqrt a
  else if op == 5 then floor a
  else if op == 6 then ceil a
  else if op == 7 then trunc a
  else if op == 8 then F32.neg (a / b)
  else if op == 9 then F32.abs a
  else if op == 10 then F32.min a b
  else if op == 11 then F32.max a b
  else if op == 12 then (if a == b then a + b else a)
  else sqrt (a * a + b * b)

// Spark SIMD path: range-affine contiguous streams over 2 inputs.
func spark_f32_op (op: U32) -> (xs: #[F32]) -> (ys: #[F32]) : #[F32] => return
  spark #[apply_f32_op op xs[i] ys[i] | i <- 0..xs.length]

// Scalar loop path for exact bit-for-bit comparison.
func scalar_f32_op (op: U32) -> (xs: #[F32]) -> (ys: #[F32]) : #[F32] => return
  @array.generate xs.length (func (i: U32) : F32 => return apply_f32_op op xs[i] ys[i])

const sample_a: #[F32] = #[
  0.0, -0.0, 1.5, -2.25,
  inf, neg_inf, 0.0, non_canon_nan,
  -1.0, 3.75, -3.75, 0.5,
  9.0
]
const sample_b: #[F32] = #[
  0.0, 0.0, 2.5, 4.0,
  inf, inf, inf, 1.0,
  2.0, 1.25, 2.0, -0.0,
  0.0
]

io run_spark_op (op: U32) : #[F32] => return spark_f32_op op sample_a sample_b
io run_scalar_op (op: U32) : #[F32] => return scalar_f32_op op sample_a sample_b

// Verify #run comptime staging matches runtime bit-for-bit on NaNs and non-canonicalizing ops.
const staged_nan_checks: #[F32] = #run #[
  0.0 / 0.0,
  (1.0 / 0.0) - (1.0 / 0.0),
  0.0 * (1.0 / 0.0),
  sqrt (-1.0),
  F32.neg (0.0 / 0.0),
  F32.abs (0.0 / 0.0),
  if false then (0.0 / 0.0) else -0.0,
  if true then (0.0 / 0.0) else -0.0,
  F32.min (0.0 / 0.0) 1.0,
  F32.min 1.0 (0.0 / 0.0),
]
io get_staged_nan_checks (unused: U32) : #[F32] => return staged_nan_checks

// Runtime spark SIMD over NaNs (including non-canonical 0xffc12345 from f32_from_bits).
io get_spark_nan_checks (unused: U32) : #[F32] => return do:
  let a = #[0.0, inf, 0.0, -1.0, non_canon_nan, non_canon_nan, non_canon_nan, non_canon_nan]
  let b = #[0.0, inf, inf, 1.0, 1.0, 1.0, 1.0, 1.0]
  let r0 = spark #[a[i] / b[i] | i <- 0..4]
  let r1 = spark #[a[i] - b[i] | i <- 0..4]
  let r2 = spark #[a[i] * b[i] | i <- 0..4]
  let r3 = spark #[sqrt a[i] | i <- 0..4]
  let r4 = spark #[floor a[i] | i <- 4..8]
  let r5 = spark #[ceil a[i] | i <- 4..8]
  let r6 = spark #[trunc a[i] | i <- 4..8]
  let r7 = spark #[a[i] + b[i] | i <- 4..8]
  let r8 = spark #[F32.neg (a[i] / b[i]) | i <- 0..4]
  let r9 = spark #[F32.abs a[i] | i <- 4..8]
  let r10 = spark #[a[i] | i <- 4..8]
  let conds = #[false, true, false, true]
  let r11 = spark #[if conds[i] then (0.0 / 0.0) else a[4 + i] | i <- 0..4]
  let r12 = spark #[F32.min a[4 + i] b[4 + i] | i <- 0..4]
  let r13 = spark #[F32.min b[4 + i] a[4 + i] | i <- 0..4]
  break #[
    r0[0], r1[1], r2[2], r3[3],
    r4[0], r5[0], r6[0], r7[0],
    r8[0], r9[0], r10[0], r11[0], r11[1], r12[0], r13[0]
  ]

// std/simd relaxed_madd / relaxed_nmadd canonicalize NaN to 0x7fc00000 while
// preserving separate rounding and leaving neg/abs/min/max uncanonicalized.
io get_std_simd_nan (unused: U32) : #[F32] => return do:
  let (m0, m1, m2, m3) = simd.f32_relaxed_madd (0.0, non_canon_nan, 1.5, inf) (inf, 1.0, 2.0, 0.0) (1.0, 2.0, 3.0, 0.0)
  let (n0, n1, n2, n3) = simd.f32_relaxed_nmadd (0.0, non_canon_nan, 1.5, 2.0) (inf, 1.0, 2.0, 3.0) (1.0, 2.0, 10.0, 5.0)
  let (g0, g1, g2, g3) = simd.f32_neg (0.0 / 0.0, non_canon_nan, 1.0, -0.0)
  let (a0, a1, a2, a3) = simd.f32_abs (non_canon_nan, 0.0 / 0.0, -2.0, -0.0)
  break #[m0, m1, m2, m3, n0, n1, n2, n3, g0, g1, a0, a1]

// #run comptime evaluation of spark expressions (both array and range sources).
const staged_spark_range: #[U32] = #run (spark #[i * 3 + 1 | i <- 0..6])
const staged_spark_arr: #[F32] = #run (spark #[x + 1.0 | x <- #[1.0, -0.0, 0.0 / 0.0, sqrt (-1.0), 2.5]])
io get_staged_spark_range (unused: U32) : #[U32] => return staged_spark_range
io get_staged_spark_arr (unused: U32) : #[F32] => return staged_spark_arr
io get_runtime_spark_arr (unused: U32) : #[F32] => return
  spark #[x + 1.0 | x <- #[1.0, -0.0, 0.0 / 0.0, sqrt (-1.0), 2.5]]
`,
    (guest) => {
      for (let op = 0; op <= 13; op++) {
        deepStrictEqual(
          asWords(guest.call("run_spark_op", op)),
          asWords(guest.call("run_scalar_op", op)),
          `op ${op} spark SIMD vs scalar bit mismatch`,
        );
      }
      deepStrictEqual(asWords(guest.call("get_staged_nan_checks", 0)), [
        0x7fc00000, // 0.0 / 0.0
        0x7fc00000, // inf - inf
        0x7fc00000, // 0.0 * inf
        0x7fc00000, // sqrt(-1.0)
        0xffc00000, // neg(0.0 / 0.0)
        0x7fc00000, // abs(0.0 / 0.0)
        0x80000000, // if false then (0.0/0.0) else -0.0
        0x7fc00000, // if true then (0.0/0.0) else -0.0
        0x3f800000, // min(NaN, 1.0) -> 1.0
        0x7fc00000, // min(1.0, NaN) -> NaN
      ]);

      deepStrictEqual(asWords(guest.call("get_spark_nan_checks", 0)), [
        0x7fc00000, // 0.0 / 0.0
        0x7fc00000, // inf - inf
        0x7fc00000, // 0.0 * inf
        0x7fc00000, // sqrt(-1.0)
        0x7fc00000, // floor(non_canon_nan)
        0x7fc00000, // ceil(non_canon_nan)
        0x7fc00000, // trunc(non_canon_nan)
        0x7fc00000, // non_canon_nan + 1.0
        0xffc00000, // neg(0.0 / 0.0)
        0x7fc12345, // abs(0xffc12345) preserved uncanonicalized
        0xffc12345, // non_canon_nan preserved uncanonicalized
        0xffc12345, // if false then (0.0/0.0) else non_canon_nan
        0x7fc00000, // if true then (0.0/0.0) else non_canon_nan
        0x3f800000, // min(non_canon_nan, 1.0) -> right operand 1.0
        0xffc12345, // min(1.0, non_canon_nan) -> right operand 0xffc12345
      ]);

      const stdSimd = asWords(guest.call("get_std_simd_nan", 0));
      deepStrictEqual(stdSimd, [
        0x7fc00000, // madd 0*inf + 1 -> canonical NaN
        0x7fc00000, // madd non_canon_nan*1 + 2 -> canonical NaN
        0x40c00000, // 1.5*2 + 3 = 6.0
        0x7fc00000, // inf*0 + 0 -> canonical NaN
        0x7fc00000, // nmadd 1 - 0*inf -> canonical NaN
        0x7fc00000, // nmadd 2 - non_canon_nan*1 -> canonical NaN
        0x40e00000, // 10 - 1.5*2 = 7.0
        0xbf800000, // 5 - 2*3 = -1.0
        0xffc00000, // neg(0.0/0.0) == 0xffc00000
        0x7fc12345, // neg(0xffc12345) == 0x7fc12345
        0x7fc12345, // abs(0xffc12345) == 0x7fc12345
        0x7fc00000, // abs(0x7fc00000) == 0x7fc00000
      ]);

      deepStrictEqual(asWords(guest.call("get_staged_spark_range", 0)), [1, 4, 7, 10, 13, 16]);
      deepStrictEqual(
        asWords(guest.call("get_staged_spark_arr", 0)),
        asWords(guest.call("get_runtime_spark_arr", 0)),
      );
    },
    { stdRoot },
  );
});

Deno.test("Phase 2: U32 ops, unsigned min/max, Bool mask normalization, range-affine streams & wrapping fallback", async () => {
  await compileAndRun(
    `func mix_u32 (x: U32) -> (k: U32) : U32 => return do:
  let a = (x * 0x9e3779b9) ^ (x >> k)
  let b = U32.bit_not (a & 0x0f0f0f0f) | (a << 3)
  let c = min a b
  let d = max a b
  break c + (d - x)

io spark_u32 (n: U32) : #[U32] => return do:
  let shift: U32 = 5
  break spark #[mix_u32 (i + 0xfffffffd) shift | i <- 0..n]

io scalar_u32 (n: U32) : #[U32] => return do:
  let shift: U32 = 5
  break @array.generate n (func (i: U32) : U32 => return mix_u32 (i + 0xfffffffd) shift)

// Strict Bool mask normalization: #[Bool] load -> not/and/or/eq/ne/if -> #[Bool] store.
// Verify stored words in linear memory are STRICTLY 0 or 1 (never 0xffffffff) by
// testing exact scalar equality against true (1) and false (0); 0xffffffff returns 99!
io spark_bool_strict (n: U32) : #[U32] => return do:
  let a = spark #[(i & 1) == 0 | i <- 0..n]
  let b = spark #[(i & 2) != 0 | i <- 0..n]
  let flag: Bool = (n & 1) == 1
  let c = spark #[if flag then ((Bool.not a[i]) and b[i]) or (a[i] == b[i]) else (a[i] != b[i]) | i <- 0..n]
  break @array.generate n (func (i: U32) : U32 => return
    if c[i] == true then 1 else if c[i] == false then 0 else 99)

// Range-affine stream with offset + wrapping-safe fallback!
const table: #[U32] = #[10, 20, 30, 40, 50, 60, 70, 80, 90]

io affine_normal (offset: U32) : #[U32] => return
  spark #[table[offset + i] + table[i + 1] | i <- 0..6]

// Unsigned wrap: offset = 0xfffffffe, start = 2 -> offset + start wraps to 0!
// Pre-loop proof detects wrap (base_idx < offset) and falls back to scalar loop.
io affine_wrap_ok (unused: U32) : #[U32] => return do:
  let off: U32 = 0xfffffffe
  break spark #[table[off + i] | i <- 2..7]

// Conditional short-array guard: arr.len == 3 < 8 -> pre-loop proof fails,
// falls back cleanly to scalar loop so out-of-bounds lane NEVER executes!
io affine_short_guarded (unused: U32) : #[U32] => return do:
  let short = #[11, 22, 33]
  break spark #[if i < short.length then short[i] else 99 | i <- 0..8]

// Array-generator gather falls back to scalar cleanly.
io gather_fallback (unused: U32) : #[U32] => return do:
  let idxs = #[4, 1, 7, 0, 2]
  break spark #[table[x] | x <- idxs]

// Integer division and trapping logical RHS fall back to scalar preserving exact trap order.
io guarded_div (xs: #[U32]) : #[U32] => return
  spark #[if x != 0 then 100 / x else 0 | x <- xs]

io guarded_and_div (xs: #[U32]) : #[U32] => return do:
  let flags = spark #[x != 0 and (100 / x > 10) | x <- xs]
  break spark #[if f then 1 else 0 | f <- flags]

io trap_div (xs: #[U32]) : #[U32] => return
  spark #[100 / x | x <- xs]

// Nested spark: outer scalar fallback, inner vectorized, escape-safe.
io nested_spark (unused: U32) : #[U32] => return do:
  let rows = spark #[spark #[r * 10 + c | c <- 0..5] | r <- 0..3]
  break #[rows[0][0], rows[0][4], rows[1][2], rows[2][4]]
`,
    (guest) => {
      for (const n of [0, 1, 2, 3, 4, 5, 7, 8, 9, 17, 33]) {
        deepStrictEqual(asWords(guest.call("spark_u32", n)), asWords(guest.call("scalar_u32", n)), `u32 len ${n}`);
        const boolWords = Array.from(guest.call("spark_bool_strict", n) as Uint32Array);
        const flag = (n & 1) === 1;
        const expected = Array.from({ length: n }, (_, i) => {
          const a = (i & 1) === 0;
          const b = (i & 2) !== 0;
          const res = flag ? ((!a && b) || (a === b)) : (a !== b);
          return res ? 1 : 0;
        });
        deepStrictEqual(boolWords, expected, `bool len ${n}`);
      }
      deepStrictEqual(asWords(guest.call("affine_normal", 2)), [50, 70, 90, 110, 130, 150]);
      deepStrictEqual(asWords(guest.call("affine_wrap_ok", 0)), [10, 20, 30, 40, 50]);
      deepStrictEqual(asWords(guest.call("affine_short_guarded", 0)), [11, 22, 33, 99, 99, 99, 99, 99]);
      deepStrictEqual(asWords(guest.call("gather_fallback", 0)), [50, 20, 80, 10, 30]);
      deepStrictEqual(asWords(guest.call("guarded_div", Uint32Array.of(0, 2, 0, 5, 4))), [0, 50, 0, 20, 25]);
      deepStrictEqual(asWords(guest.call("guarded_and_div", Uint32Array.of(0, 2, 0, 20, 5))), [0, 1, 0, 0, 1]);
      throws(() => guest.call("trap_div", Uint32Array.of(2, 5, 0, 4)));
      deepStrictEqual(asWords(guest.call("nested_spark", 0)), [0, 4, 12, 24]);
    },
  );
});

Deno.test("Phase 2: work counters, unpatchableOperand (-2) & recordInlined replay soundness", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-spark-replay-" });
  const entry = `${dir}/main.sq`;
  const v1 = `func scale_helper (x: F32) : F32 => return x * 2.0 + 3.0
func unrelated (n: U32) : U32 => return n + 10
io simd_map (xs: #[F32]) : #[F32] => return spark #[scale_helper x + 1.0 | x <- xs]
io fallback_map (xs: #[U32]) : #[U32] => return spark #[100 / x | x <- xs]
io call_unrelated (n: U32) : U32 => return unrelated n
`;
  try {
    await Deno.writeTextFile(entry, v1);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      stdRoot,
    });
    try {
      const b1 = await compiler.build();
      ok(b1.success, JSON.stringify(b1));
      equal(b1.stats.sparksVectorized, 1);
      equal(b1.stats.sparksScalarFallback, 1);
      // Verify the emitted Wasm actually contains 0xfd SIMD instructions.
      ok(b1.bytes.includes(0xfd), "Expected Wasm SIMD 0xfd prefix in compiled module");
      {
        const g = await instantiateGuest(b1.bytes);
        try {
          deepStrictEqual(Array.from(g.call("simd_map", Float32Array.of(1, 2, 3, 4, 5)) as Float32Array), [6, 8, 10, 12, 14]);
          equal(g.call("call_unrelated", 5), 15);
        } finally {
          g.dispose();
        }
      }

      // 1. Edit constant inside vectorized spark body: relocate MUST reject (-2 sentinel) and fall through cleanly!
      const v2 = v1.replace("scale_helper x + 1.0", "scale_helper x + 5.0");
      const b2 = await compiler.build({ sources: { [entry]: v2 } });
      ok(b2.success, JSON.stringify(b2));
      equal(b2.stats.relocatedOperands, undefined);
      {
        const g = await instantiateGuest(b2.bytes);
        try {
          deepStrictEqual(Array.from(g.call("simd_map", Float32Array.of(1, 2, 3, 4, 5)) as Float32Array), [10, 12, 14, 16, 18]);
        } finally {
          g.dispose();
        }
      }

      // 2. Edit constant inside inlined helper `scale_helper`: recordInlined + unpatchableOperand MUST re-emit cleanly!
      const v3 = v2.replace("x * 2.0 + 3.0", "x * 4.0 + 7.0");
      const b3 = await compiler.build({ sources: { [entry]: v3 } });
      ok(b3.success, JSON.stringify(b3));
      equal(b3.stats.relocatedOperands, undefined);
      {
        const g = await instantiateGuest(b3.bytes);
        try {
          deepStrictEqual(Array.from(g.call("simd_map", Float32Array.of(1, 2, 3, 4, 5)) as Float32Array), [16, 20, 24, 28, 32]);
        } finally {
          g.dispose();
        }
      }

      // 3. Edit constant in `unrelated` function in the same unit: scalar relocate STILL works because -2 is body-scoped!
      const v4 = v3.replace("return n + 10", "return n + 20");
      const b4 = await compiler.build({ sources: { [entry]: v4 } });
      ok(b4.success, JSON.stringify(b4));
      equal(b4.stats.relocatedOperands, 1);
      {
        const g = await instantiateGuest(b4.bytes);
        try {
          equal(g.call("call_unrelated", 5), 25);
          deepStrictEqual(Array.from(g.call("simd_map", Float32Array.of(1, 2, 3, 4, 5)) as Float32Array), [16, 20, 24, 28, 32]);
        } finally {
          g.dispose();
        }
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("Phase 2: k==3 cross-nominal AoS SIMD, Shape 2 indirect ids[k] AoS SIMD, #[T] SIMD reductions & fast range-push", async () => {
  await compileAndRun(
    `
type Pos is data = $Pos { x: F32, y: F32, z: F32 }
type Vel is data = $Vel { vx: F32, vy: F32, vz: F32 }
type PairU32 = { a: U32, b: U32 }

func make_pos (n: U32): #[Pos] =>
  let ps: #[Pos] = #[]
  for i in 0..n:
    let f = U32.to_f32 (i + 1)
    ps := self.push ($Pos { x: f * 0.5, y: f * 1.25, z: f * 2.0 })
  return ps

func make_vel (n: U32): #[Vel] =>
  let vs: #[Vel] = #[]
  for i in 0..n:
    let f = U32.to_f32 ((i & 7) + 1)
    vs := self.push ($Vel { vx: f * 0.25, vy: f * 0.5, vz: f * 0.75 })
  return vs

// 1. Contiguous k==3 cross-nominal AoS SIMD (Pos += Vel and Pos += Vel * dt)
io aos3_add (n: U32): #[F32] =>
  let ps = make_pos n
  let vs = make_vel n
  let len = min ps.length vs.length
  for _ in 0..4:
    for i in 0..len:
      let $Pos { x, y, z } = ps[i]
      let $Vel { vx, vy, vz } = vs[i]
      ps[i] := $Pos { x: x + vx, y: y + vy, z: z + vz }
  let out: #[F32] = #[]
  for i in 0..len:
    let $Pos { x, y, z } = ps[i]
    out := self.push x
    out := self.push y
    out := self.push z
  return out

io aos3_fma (n: U32): #[F32] =>
  let ps = make_pos n
  let vs = make_vel n
  let dt: F32 = 0.5
  let len = min ps.length vs.length
  for i in 0..len:
    let $Pos { x, y, z } = ps[i]
    let $Vel { vx, vy, vz } = vs[i]
    ps[i] := $Pos { x: x + vx * dt, y: y + vy * dt, z: z + vz * dt }
  let out: #[F32] = #[]
  for i in 0..len:
    let $Pos { x, y, z } = ps[i]
    out := self.push x
    out := self.push y
    out := self.push z
  return out

// 2. Shape 2 indirect ids[k] AoS SIMD: contiguous, non-zero offset contiguous, sparse increasing, unsorted+duplicates
io aos3_indirect (ids: #[U32]): #[F32] =>
  let n: U32 = 24
  let ps = make_pos n
  let vs = make_vel n
  let m = ids.length
  for _ in 0..5:
    for k in 0..m:
      let id = ids[k]
      let $Pos { x, y, z } = ps[id]
      let $Vel { vx, vy, vz } = vs[id]
      ps[id] := $Pos { x: x + vx, y: y + vy, z: z + vz }
  let out: #[F32] = #[]
  for i in 0..n:
    let $Pos { x, y, z } = ps[i]
    out := self.push x
    out := self.push y
    out := self.push z
  return out

// Self-aliasing indirect update (ps[id] += ps[id])
io aos3_indirect_self_alias (ids: #[U32]): #[F32] =>
  let ps = make_pos 12
  let m = ids.length
  for _ in 0..3:
    for k in 0..m:
      let id = ids[k]
      let $Pos { x, y, z } = ps[id]
      ps[id] := $Pos { x: x + x, y: y + y, z: z + z }
  let out: #[F32] = #[]
  for i in 0..12:
    let $Pos { x, y, z } = ps[i]
    out := self.push x
    out := self.push y
    out := self.push z
  return out

// Canonical NaN check through k==3 AoS SIMD + outer deferred-NaN loop
io aos3_nan_canon (_: U32): #[F32] =>
  let inf: F32 = 1.0 / 0.0
  let ps: #[Pos] = #[]
  let vs: #[Vel] = #[]
  for _ in 0..8:
    ps := self.push ($Pos { x: inf, y: 1.0, z: 0.0 })
    vs := self.push ($Vel { vx: -inf, vy: 2.0, vz: 3.0 })
  for _ in 0..3:
    for i in 0..8:
      let $Pos { x, y, z } = ps[i]
      let $Vel { vx, vy, vz } = vs[i]
      ps[i] := $Pos { x: x + vx, y: y + vy, z: z + vz }
  let $Pos { x, y, z } = ps[7]
  return #[x, y, z]

// 3. #[T] SIMD reductions (+ and ^, U32/U64/record) & fast range-push (auto-grow, non-empty, const, AoS record)
io arr_simd_red_and_fast_push (n: U32): #[U32] =>
  let a: #[U32] = #[]
  for i in 0..n:
    a := self.push (i * 7 + 3)
  let b: #[U32] = #[100, 200]
  for i in 0..n:
    b := self.push 9
  let pairs: #[PairU32] = #[]
  for i in 0..n:
    pairs := self.push { a: i + 1, b: i * 2 + 3 }
  let u64s: #[U64] = #[]
  for i in 0..n:
    u64s := self.push (i.to_u64 * 3u64 + 2u64)

  let sum_a: U32 = 0
  for x in a:
    sum_a := self + x
  let xor_a: U32 = 0
  for x in a:
    xor_a := self ^ x
  let sum_b: U32 = 0
  for x in b:
    sum_b := self + x
  let sum_p: U32 = 0
  for { a: pa, b: pb } in pairs:
    sum_p := self + pa + pb
  let sum_64: U64 = 0u64
  for x in u64s:
    sum_64 := self + x
  let xor_64: U64 = 0u64
  for x in u64s:
    xor_64 := self ^ x

  return #[a.length, sum_a, xor_a, sum_b, sum_p, sum_64.to_u32, xor_64.to_u32]
`,
    (guest) => {
      const f32 = Math.fround;
      for (const n of [0, 1, 3, 4, 5, 7, 8, 9, 12, 16, 33]) {
        const expAdd: number[] = [];
        const expFma: number[] = [];
        for (let i = 0; i < n; i++) {
          const fp = f32(i + 1);
          const fv = f32((i & 7) + 1);
          let x = f32(fp * 0.5), y = f32(fp * 1.25), z = f32(fp * 2.0);
          const vx = f32(fv * 0.25), vy = f32(fv * 0.5), vz = f32(fv * 0.75);
          expFma.push(f32(x + f32(vx * 0.5)), f32(y + f32(vy * 0.5)), f32(z + f32(vz * 0.5)));
          for (let t = 0; t < 4; t++) {
            x = f32(x + vx); y = f32(y + vy); z = f32(z + vz);
          }
          expAdd.push(x, y, z);
        }
        deepStrictEqual(Array.from(guest.call("aos3_add", n) as Float32Array), expAdd, `aos3_add n=${n}`);
        deepStrictEqual(Array.from(guest.call("aos3_fma", n) as Float32Array), expFma, `aos3_fma n=${n}`);
      }

      const idCases: number[][] = [
        [],
        [0, 1, 2],
        Array.from({ length: 24 }, (_, i) => i), // contiguous from 0 (all_distinct == 2)
        Array.from({ length: 12 }, (_, i) => i + 5), // contiguous from 5 (all_distinct == 2)
        [1, 4, 7, 10, 13, 16, 19, 22], // strictly increasing sparse (all_distinct == 1)
        [3, 1, 3, 0, 3, 2, 1, 3, 11], // unsorted + duplicate IDs (all_distinct == 0)
      ];
      for (const ids of idCases) {
        const ps = Array.from({ length: 24 }, (_, i) => {
          const fp = f32(i + 1);
          return [f32(fp * 0.5), f32(fp * 1.25), f32(fp * 2.0)];
        });
        const vs = Array.from({ length: 24 }, (_, i) => {
          const fv = f32((i & 7) + 1);
          return [f32(fv * 0.25), f32(fv * 0.5), f32(fv * 0.75)];
        });
        for (let t = 0; t < 5; t++) {
          for (const id of ids) {
            ps[id][0] = f32(ps[id][0] + vs[id][0]);
            ps[id][1] = f32(ps[id][1] + vs[id][1]);
            ps[id][2] = f32(ps[id][2] + vs[id][2]);
          }
        }
        deepStrictEqual(
          Array.from(guest.call("aos3_indirect", Uint32Array.from(ids)) as Float32Array),
          ps.flat(),
          `aos3_indirect ids=${JSON.stringify(ids)}`,
        );
      }
      // Out-of-bounds indirect ID must trap!
      throws(() => guest.call("aos3_indirect", Uint32Array.of(0, 1, 24)));

      // Self-aliasing indirect update (contiguous + duplicates)
      for (const ids of [[0, 1, 2, 3, 4, 5, 6, 7], [2, 2, 5, 2]]) {
        const ps = Array.from({ length: 12 }, (_, i) => {
          const fp = f32(i + 1);
          return [f32(fp * 0.5), f32(fp * 1.25), f32(fp * 2.0)];
        });
        for (let t = 0; t < 3; t++) {
          for (const id of ids) {
            ps[id][0] = f32(ps[id][0] + ps[id][0]);
            ps[id][1] = f32(ps[id][1] + ps[id][1]);
            ps[id][2] = f32(ps[id][2] + ps[id][2]);
          }
        }
        deepStrictEqual(
          Array.from(guest.call("aos3_indirect_self_alias", Uint32Array.from(ids)) as Float32Array),
          ps.flat(),
        );
      }

      // Canonical NaN through k==3 AoS SIMD + outer deferred-NaN loop
      const nanRes = asWords(guest.call("aos3_nan_canon", 0));
      deepStrictEqual(nanRes, [0x7fc00000, 0x40e00000, 0x41100000]);

      // #[T] SIMD reductions & fast range-push
      for (const n of [0, 1, 3, 15, 16, 17, 33, 65]) {
        let sumA = 0, xorA = 0, sumB = 300, sumP = 0;
        let sum64 = 0n, xor64 = 0n;
        for (let i = 0; i < n; i++) {
          const v = (i * 7 + 3) >>> 0;
          sumA = (sumA + v) >>> 0;
          xorA = (xorA ^ v) >>> 0;
          sumB = (sumB + 9) >>> 0;
          sumP = (sumP + (i + 1) + (i * 2 + 3)) >>> 0;
          const v64 = BigInt(i) * 3n + 2n;
          sum64 = (sum64 + v64) & 0xffffffffffffffffn;
          xor64 ^= v64;
        }
        deepStrictEqual(
          Array.from(guest.call("arr_simd_red_and_fast_push", n) as Uint32Array),
          [n, sumA, xorA, sumB, sumP, Number(sum64 & 0xffffffffn), Number(xor64 & 0xffffffffn)],
          `arr_simd_red_and_fast_push n=${n}`,
        );
      }
    },
  );
});
