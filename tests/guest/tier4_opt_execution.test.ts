import { deepStrictEqual, ok, strictEqual, throws } from "node:assert/strict";
import { compileAndRun } from "./compile_helpers.ts";
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

Deno.test("Tier 4A: deferred NaN canonicalization on spark and Maybe Vec3 loops preserves 0x7fc00000 and tags", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-tier4a-nan-" });
  const entry = `${dir}/main.blot`;
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

type Vec3 is data = $Vec3 { x: F32, y: F32, z: F32 }

// 1. SoA spark loop with deferred NaN canonicalization (steps = 0, 1, 2, 10)
io soa_deferred_nan (packed: U32): #[F32] =>
  let n = packed & 65535
  let steps = packed >> 16
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    px[i] := U32.to_f32 (i + 1) * 0.5
    vx[i] := U32.to_f32 ((i & 3) + 1) * 0.25
  if n > 0:
    px[0] := inf
    vx[0] := 0.0 - inf
  if n > 5:
    px[5] := 0.0 - inf
    vx[5] := inf
  for _ in 0 .. steps:
    px := spark #[px[i] + vx[i] | i <- 0 .. n]
  return px

// 2. Maybe Vec3 if-let loop with deferred NaN canonicalization (preserves $Nothing and exact 0x7fc00000)
io maybe_vec3_deferred_nan (packed: U32): #[U32] =>
  let n = packed & 65535
  let steps = packed >> 16
  let pos: #[Maybe Vec3] = @array.fill n $Nothing
  let vel: #[Maybe Vec3] = @array.fill n $Nothing
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    if (i % 2) == 0:
      let f = U32.to_f32 (i + 1)
      let x0 = if i == 2 then inf else f * 0.5
      let vx0 = if i == 2 then 0.0 - inf else 0.25
      pos[i] := $Some ($Vec3 { x: x0, y: f, z: f * 0.25 })
      vel[i] := $Some ($Vec3 { x: vx0, y: 0.5, z: 0.125 })
  for _ in 0 .. steps:
    for i in 0 .. n:
      if let $Some ($Vec3 { x, y, z }) = pos[i]:
        if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = vel[i]:
          pos[i] := $Some ($Vec3 { x: x + vx, y: y + vy, z: z + vz })
  let out = @array.fill (n * 4) 0
  for i in 0 .. n:
    let base = i * 4
    case pos[i] of
      $Some ($Vec3 { x, y, z }) =>
        out[base] := 1
        out[base + 1] := f32_bits x
        out[base + 2] := f32_bits y
        out[base + 3] := f32_bits z
      $Nothing =>
        out[base] := 0
  return out

// 3. Conditional write depending on F32 comparison must NOT skip canonicalization
io conditional_write_nan (n: U32): #[F32] =>
  let arr = @array.fill n 0.0
  let zero = U32.to_f32 (n & 0)
  let inf = 1.0 / zero
  if n > 0:
    arr[0] := inf
  for _ in 0 .. 4:
    for i in 0 .. n:
      if arr[i] == arr[i]:
        arr[i] := arr[i] - arr[i]
  return arr
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
      ok(built.bytes.includes(0xfd), "Expected SIMD opcodes in Tier 4A module");
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const steps of [0, 1, 2, 10]) {
          for (const n of [0, 1, 4, 16, 19]) {
            const packed = ((steps << 16) | n) >>> 0;
            const words = asWords(guest.call("soa_deferred_nan", packed));
            strictEqual(words.length, n);
            const f32 = new Float32Array(new Uint32Array(words).buffer);
            for (let i = 0; i < n; i++) {
              if ((i === 0 || i === 5) && steps > 0) {
                strictEqual(
                  words[i],
                  0x7fc00000,
                  `soa_deferred_nan NaN canon n=${n} steps=${steps} i=${i}`,
                );
              } else if (i === 0 && steps === 0) {
                strictEqual(words[i], 0x7f800000);
              } else if (i === 5 && steps === 0) {
                strictEqual(words[i], 0xff800000);
              } else {
                let p = Math.fround((i + 1) * 0.5);
                const v = Math.fround(((i & 3) + 1) * 0.25);
                for (let s = 0; s < steps; s++) p = Math.fround(p + v);
                strictEqual(f32[i], p, `soa_deferred_nan finite n=${n} steps=${steps} i=${i}`);
              }
            }
          }

          const packedV = ((steps << 16) | 8) >>> 0;
          const outV = asWords(guest.call("maybe_vec3_deferred_nan", packedV));
          for (let i = 0; i < 8; i++) {
            const b = i * 4;
            if (i % 2 === 1) {
              strictEqual(outV[b], 0, `slot ${i} must stay $Nothing`);
            } else {
              strictEqual(outV[b], 1, `slot ${i} must stay $Some`);
              if (i === 2 && steps > 0) {
                strictEqual(outV[b + 1], 0x7fc00000, `slot 2 x NaN steps=${steps}`);
              } else if (i !== 2) {
                const f = Math.fround(i + 1);
                let x = Math.fround(f * 0.5);
                let y = f;
                let z = Math.fround(f * 0.25);
                for (let s = 0; s < steps; s++) {
                  x = Math.fround(x + 0.25);
                  y = Math.fround(y + 0.5);
                  z = Math.fround(z + 0.125);
                }
                const fbuf = new Float32Array(new Uint32Array([outV[b + 1], outV[b + 2], outV[b + 3]]).buffer);
                strictEqual(fbuf[0], x);
                strictEqual(fbuf[1], y);
                strictEqual(fbuf[2], z);
              }
            }
          }
        }

        const cw = asWords(guest.call("conditional_write_nan", 4));
        strictEqual(cw[0], 0x7fc00000, "conditional write NaN must canonicalize");
        strictEqual(cw[1], 0);
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

Deno.test("Tier 4B: variant tag-store skip vs tag-change write and CheckedLe bounds hoisting with traps", async () => {
  await compileAndRun(
    `type Vec3 is data = $Vec3 { x: F32, y: F32, z: F32 }

// 4B-1: same-tag overwrite skips tag store; different-tag overwrite MUST still write tag
io tag_skip_and_change (n: U32): #[U32] =>
  let pool: #[Maybe Vec3] = @array.fill n $Nothing
  for i in 0 .. n:
    let f = U32.to_f32 (i + 1)
    pool[i] := $Some ($Vec3 { x: f, y: f * 2.0, z: f * 3.0 })
  for i in 0 .. n:
    if let $Some ($Vec3 { x, y, z }) = pool[i]:
      if (i % 2) == 0:
        pool[i] := $Some ($Vec3 { x: x + 10.0, y: y + 20.0, z: z + 30.0 })
      else:
        pool[i] := $Nothing
  let out = @array.fill n 0
  for i in 0 .. n:
    case pool[i] of
      $Some ($Vec3 { x, y, z }) =>
        out[i] := F32.to_u32 (x + y + z)
      $Nothing =>
        out[i] := 999999
  return out

// 4B-2: range loop CheckedLe (a.length <= b.length fast path + slow-path trap when b is shorter)
io range_pair_sum (packed: U32): U32 =>
  let na = packed & 65535
  let nb = packed >> 16
  let a = @array.fill na 0
  let b = @array.fill nb 0
  for i in 0 .. na:
    a[i] := i + 1
  for i in 0 .. nb:
    b[i] := (i + 1) * 10
  let sum: U32 = 0
  let lim = a.length
  for i in 0 .. lim:
    sum := self + a[i] + b[i]
  return sum

// 4B-2: for-ever early-exit CheckedLe (mid <= src.length && hi <= src.length fast path + trap when hi > src.length)
io merge_bounds_check (packed: U32): U32 =>
  let n = packed & 255
  let mid = (packed >> 8) & 255
  let hi = (packed >> 16) & 255
  let src = @array.fill n 0
  for idx in 0 .. n:
    src[idx] := idx * 3 + 1
  let i: U32 = 0
  let j = mid
  let sum: U32 = 0
  for ever:
    if i >= mid or j >= hi:
      break
    if src[i] <= src[j]:
      sum := self + src[i]
      i := self + 1
    else:
      sum := self + src[j]
      j := self + 1
  return sum
`,
    (guest) => {
      const gotTag = asWords(guest.call("tag_skip_and_change", 6));
      deepStrictEqual(gotTag, [66, 999999, 78, 999999, 90, 999999]);

      // na=5, nb=5 => sum(1..5)*11 = 15*11 = 165
      strictEqual(guest.call("range_pair_sum", ((5 << 16) | 5) >>> 0), 165);
      // na=5, nb=9 => fast path (na <= nb)
      strictEqual(guest.call("range_pair_sum", ((9 << 16) | 5) >>> 0), 165);
      // na=5, nb=4 => MUST TRAP!
      throws(() => guest.call("range_pair_sum", ((4 << 16) | 5) >>> 0));

      // n=8, mid=4, hi=8 => src=[1,4,7,10,13,16,19,22]; i walks 0..3 (1+4+7+10=22) since src[i] <= src[4]=13
      strictEqual(guest.call("merge_bounds_check", ((8 << 16) | (4 << 8) | 8) >>> 0), 22);
      // n=6, mid=6, hi=8 => j starts at 6 < hi=8, i=0 < mid=6 -> reads src[6] -> MUST TRAP!
      throws(() => guest.call("merge_bounds_check", ((8 << 16) | (6 << 8) | 6) >>> 0));
    },
    { stdRoot },
  );
});

Deno.test("Tier 4C: 4x v128 register-blocked matmul k-loop across tails, NaNs, aliasing fallback, and OOB trap", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-tier4c-matmul-" });
  const entry = `${dir}/main.blot`;
  const src = `io matmul_rect (packed: U32): #[F32] =>
  let rows = packed & 255
  let inner = (packed >> 8) & 255
  let cols = (packed >> 16) & 255
  let a = @array.fill (rows * inner) 0.0
  let b = @array.fill (inner * cols) 0.0
  let c = @array.fill (rows * cols) 1.5
  let s: U32 = 12345
  for i in 0 .. (rows * inner):
    s := self * 1664525 + 1013904223
    a[i] := U32.to_f32 (s & 63) * 0.125
  for i in 0 .. (inner * cols):
    s := self * 1664525 + 1013904223
    b[i] := U32.to_f32 (s & 63) * 0.125
  for row in 0 .. rows:
    let row_off_a = row * inner
    let row_off_c = row * cols
    for k in 0 .. inner:
      let aik = a[row_off_a + k]
      let k_off = k * cols
      for col in 0 .. cols:
        let dst = row_off_c + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c

// NaN canonicalization at both SIMD tile column (col=5) and scalar tail column (col=17)
io matmul_nan (m: U32): #[F32] =>
  let a = @array.fill (2 * 2) 1.0
  let b = @array.fill (2 * m) 1.0
  let c = @array.fill (2 * m) 0.0
  let zero = U32.to_f32 (m & 0)
  let inf = 1.0 / zero
  a[0] := inf
  if m > 5:
    b[5] := 0.0
  if m > 17:
    b[17] := 0.0
  for row in 0 .. 2:
    let row_off_a = row * 2
    let row_off_c = row * m
    for k in 0 .. 2:
      let aik = a[row_off_a + k]
      let k_off = k * m
      for col in 0 .. m:
        let dst = row_off_c + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c

// Aliased c == b MUST fall back to exact sequential semantics
io matmul_aliased (n: U32): #[F32] =>
  let a = @array.fill (n * n) 0.5
  let c = @array.fill (n * n) 0.0
  for i in 0 .. (n * n):
    c[i] := U32.to_f32 (i + 1) * 0.25
  for row in 0 .. n:
    let row_off = row * n
    for k in 0 .. n:
      let aik = a[row_off + k]
      let k_off = k * n
      for col in 0 .. n:
        let dst = row_off + col
        c[dst] := c[dst] + aik * c[k_off + col]
  return c

// OOB b MUST fall back and trap cleanly
io matmul_oob (m: U32): F32 =>
  let a = @array.fill 4 1.0
  let b = @array.fill (m + 1) 1.0
  let c = @array.fill (2 * m) 0.0
  for row in 0 .. 2:
    let row_off = row * m
    for k in 0 .. 2:
      let aik = a[row * 2 + k]
      let k_off = k * m
      for col in 0 .. m:
        let dst = row_off + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c[0]
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
      ok(built.bytes.includes(0xfd), "Expected SIMD opcodes in Tier 4C module");
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const [rows, inner, cols] of [[2, 3, 1], [2, 4, 15], [3, 5, 16], [2, 6, 17], [3, 4, 31], [2, 8, 32], [2, 5, 35]]) {
          const packed = ((cols << 16) | (inner << 8) | rows) >>> 0;
          const got = asWords(guest.call("matmul_rect", packed));
          // Exact k-order JS Math.fround reference
          const a = new Float32Array(rows * inner);
          const b = new Float32Array(inner * cols);
          const c = new Float32Array(rows * cols).fill(1.5);
          let s = 12345 >>> 0;
          for (let i = 0; i < rows * inner; i++) {
            s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
            a[i] = Math.fround((s & 63) * 0.125);
          }
          for (let i = 0; i < inner * cols; i++) {
            s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
            b[i] = Math.fround((s & 63) * 0.125);
          }
          for (let row = 0; row < rows; row++) {
            for (let k = 0; k < inner; k++) {
              const aik = a[row * inner + k];
              for (let col = 0; col < cols; col++) {
                const dst = row * cols + col;
                c[dst] = Math.fround(c[dst] + Math.fround(aik * b[k * cols + col]));
              }
            }
          }
          const exp = Array.from(new Uint32Array(c.buffer));
          deepStrictEqual(got, exp, `matmul_rect ${rows}x${inner}x${cols}`);
        }

        const nanWords = asWords(guest.call("matmul_nan", 19));
        strictEqual(nanWords[5], 0x7fc00000, "matmul SIMD tile NaN must be 0x7fc00000");
        strictEqual(nanWords[17], 0x7fc00000, "matmul scalar tail NaN must be 0x7fc00000");

        const aliasGot = asWords(guest.call("matmul_aliased", 16));
        const ac = new Float32Array(16 * 16);
        for (let i = 0; i < 256; i++) ac[i] = Math.fround((i + 1) * 0.25);
        for (let row = 0; row < 16; row++) {
          for (let k = 0; k < 16; k++) {
            for (let col = 0; col < 16; col++) {
              const dst = row * 16 + col;
              ac[dst] = Math.fround(ac[dst] + Math.fround(0.5 * ac[k * 16 + col]));
            }
          }
        }
        deepStrictEqual(aliasGot, Array.from(new Uint32Array(ac.buffer)), "matmul_aliased exact sequential");

        throws(() => guest.call("matmul_oob", 16));
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

Deno.test("Tier 4D: CheckedGrow reuse, depth-3/spark inlining, and unique_owned reuse vs alias safety", async () => {
  await compileAndRun(
    `func leaf_push (arr: own #[U32]) -> (v: U32): (#[U32], U32) =>
  @storage.push arr v
  let n = arr.length
  return (arr, n)

func mid_push (arr: own #[U32]) -> (v: U32): (#[U32], U32) =>
  let (arr2, n) = leaf_push arr v
  let val = arr2[n - 1] + n
  return (arr2, val)

func top_push (arr: own #[U32]) -> (v: U32): (#[U32], U32) =>
  return mid_push arr (v * 2)

io nested_grow_ops (n: U32): U32 =>
  let arr: #[U32] = #[]
  let acc: U32 = 0
  for i in 0 .. n:
    let (next_arr, delta) = top_push arr (i + 1)
    arr := next_arr
    acc := self + delta
    arr[i] := arr[i] + 1
  if arr.length >= 2:
    let last = @storage.pop arr
    acc := self + last
    @storage.truncate arr (arr.length - 1)
  for i in 0 .. arr.length:
    acc := self + arr[i]
  return acc

io nested_grow_oob (n: U32): U32 =>
  let arr: #[U32] = #[]
  for i in 0 .. n:
    @storage.push arr i
  @storage.truncate arr (n - 1)
  return arr[n - 1]

func step_spark (px: #[F32]) -> (vx: #[F32]): #[F32] =>
  return spark #[px[i] + vx[i] | i <- 0 .. px.length]

// Uniquely-owned array forwarded into inlined spark helper (in-place reuse!)
io spark_inline_unique (n: U32): #[F32] =>
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  for i in 0 .. n:
    px[i] := U32.to_f32 (i + 1)
    vx[i] := 0.5
  let out = px
  for _ in 0 .. 8:
    out := step_spark out vx
  return out

// Aliased array passed to inlined spark helper MUST NOT corrupt alias 'saved'!
io spark_inline_aliased (n: U32): #[F32] =>
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  for i in 0 .. n:
    px[i] := U32.to_f32 (i + 1)
    vx[i] := 10.0
  let saved = px
  let out = px
  for _ in 0 .. 4:
    out := step_spark out vx
  let res = @array.fill (n * 2) 0.0
  for i in 0 .. n:
    res[i] := saved[i]
    res[n + i] := out[i]
  return res

// Direct spark inside loop referencing outer loop-invariant array MUST NOT overwrite outer array!
io spark_direct_invariant_safe (n: U32): #[F32] =>
  let vx = @array.fill n 10.0
  let out = @array.fill n 1.0
  for _ in 0 .. 4:
    out := spark #[out[i] + vx[i] | i <- 0 .. n]
  return out
`,
    (guest) => {
      // n=4: push 2,4,6,8; mid_push returns (2+1)+(4+2)+(6+3)+(8+4)=30; arr becomes [3,5,7,9];
      // pop 9 -> acc=39, arr=[3,5,7]; truncate -> [3,5] -> sum +8 => 47
      strictEqual(guest.call("nested_grow_ops", 4), 47);
      throws(() => guest.call("nested_grow_oob", 4));

      const uniq = Array.from(guest.call("spark_inline_unique", 19) as Float32Array);
      deepStrictEqual(
        uniq,
        Array.from({ length: 19 }, (_, i) => Math.fround(i + 1 + 4.0)),
      );

      const aliased = Array.from(guest.call("spark_inline_aliased", 18) as Float32Array);
      const expSaved = Array.from({ length: 18 }, (_, i) => Math.fround(i + 1));
      const expOut = Array.from({ length: 18 }, (_, i) => Math.fround(i + 1 + 40.0));
      deepStrictEqual(aliased.slice(0, 18), expSaved, "alias saved MUST NOT be mutated");
      deepStrictEqual(aliased.slice(18, 36), expOut, "out must be updated");

      const inv = Array.from(guest.call("spark_direct_invariant_safe", 17) as Float32Array);
      deepStrictEqual(
        inv,
        Array.from({ length: 17 }, () => 41.0),
        "loop-invariant vx MUST NOT be overwritten by direct spark",
      );
    },
    { stdRoot },
  );
});

Deno.test("Tier 4E: exact 2.0*x->x+x, 2x unroll pure-scalar for-ever, and 4x unrolled strided fill across types/strides", async () => {
  await compileAndRun(
    `import * as simd from "std/simd"

// 4E-1: 2.0 * x and x * 2.0 bit-identical across signed zero, subnormal, Inf, NaN
io mul_two_bits (bits: U32): #[U32] =>
  let (x, _, _, _) = simd.f32_from_bits (bits, 0, 0, 0)
  let a = 2.0 * x
  let b = x * 2.0
  let (ab, bb, _, _) = simd.f32_bits (a, b, 0.0, 0.0)
  return #[ab, bb]

// 4E-2: 2x unrolled pure-scalar for-ever loop across odd/even limits and early exit
io forever_unroll2 (limit: U32): U32 =>
  let zr = 0.25
  let zi = 0.125
  let it: U32 = 0
  for ever:
    if it >= limit:
      break
    let zr2 = zr * zr
    let zi2 = zi * zi
    if zr2 + zi2 > 4.0:
      break
    let next_zi = 2.0 * zr * zi + 0.3
    zr := zr2 - zi2 + 0.2
    zi := next_zi
    it := self + 1
  return it * 1000 + F32.to_u32 ((zr + zi + 10.0) * 100.0)

// 4E-3: 4x unrolled strided fill on Bool, U32, and F32 across strides and limits
io strided_fill_bool (packed: U32): #[U32] =>
  let n = packed & 255
  let start = (packed >> 8) & 255
  let stride = (packed >> 16) & 255
  let flags = @array.fill n true
  let m = start
  for ever:
    if m >= n:
      break
    flags[m] := false
    m := self + stride
  let out = @array.fill n 0
  for i in 0 .. n:
    if flags[i]:
      out[i] := 1
  return out

io strided_fill_u32 (packed: U32): #[U32] =>
  let n = packed & 255
  let start = (packed >> 8) & 255
  let stride = (packed >> 16) & 255
  let xs = @array.fill n 7
  let m = start
  for ever:
    if m >= n:
      break
    xs[m] := 42
    m := self + stride
  return xs

io strided_fill_oob (n: U32): U32 =>
  let flags = @array.fill n true
  let limit = n + 3
  let m: U32 = 0
  for ever:
    if m >= limit:
      break
    flags[m] := false
    m := self + 2
  return 0
`,
    (guest) => {
      // Test exact IEEE-754 bits for 2.0 * x
      const testBits: [number, number][] = [
        [0x00000000, 0x00000000], // +0.0 -> +0.0
        [0x80000000, 0x80000000], // -0.0 -> -0.0
        [0x00000001, 0x00000002], // +min_subnormal -> 2*min_subnormal
        [0x80000001, 0x80000002], // -min_subnormal -> -2*min_subnormal
        [0x3fc00000, 0x40400000], // 1.5 -> 3.0
        [0xc0500000, 0xc0d00000], // -3.25 -> -6.5
        [0x7f800000, 0x7f800000], // +Inf -> +Inf
        [0xff800000, 0xff800000], // -Inf -> -Inf
        [0x7fc00000, 0x7fc00000], // qNaN -> 0x7fc00000
      ];
      for (const [inp, exp] of testBits) {
        const [a, b] = asWords(guest.call("mul_two_bits", inp));
        strictEqual(a, exp, `2.0 * 0x${inp.toString(16)}`);
        strictEqual(b, exp, `0x${inp.toString(16)} * 2.0`);
      }

      // Test 2x unrolled for-ever across odd and even iteration counts
      for (const limit of [0, 1, 2, 3, 4, 5, 16, 17, 100]) {
        let zr = Math.fround(0.25);
        let zi = Math.fround(0.125);
        let it = 0;
        while (it < limit) {
          const zr2 = Math.fround(zr * zr);
          const zi2 = Math.fround(zi * zi);
          if (Math.fround(zr2 + zi2) > 4.0) break;
          const nextZi = Math.fround(Math.fround(Math.fround(2.0 * zr) * zi) + 0.3);
          zr = Math.fround(Math.fround(zr2 - zi2) + 0.2);
          zi = nextZi;
          it++;
        }
        const exp = (it * 1000 + Math.trunc(Math.fround(Math.fround(Math.fround(zr + zi) + 10.0) * 100.0))) >>> 0;
        strictEqual(guest.call("forever_unroll2", limit), exp, `forever_unroll2 limit=${limit}`);
      }

      // Test 4x strided fill across strides, starts, and lengths
      for (const [n, start, stride] of [[0, 0, 1], [1, 0, 1], [4, 0, 1], [5, 0, 1], [17, 2, 3], [25, 4, 2], [30, 0, 7], [15, 3, 50]]) {
        const packed = ((stride << 16) | (start << 8) | n) >>> 0;
        const gotB = asWords(guest.call("strided_fill_bool", packed));
        const expB = Array.from({ length: n }, () => 1);
        for (let m = start; m < n; m += stride) expB[m] = 0;
        deepStrictEqual(gotB, expB, `strided_fill_bool n=${n} start=${start} stride=${stride}`);

        const gotU = asWords(guest.call("strided_fill_u32", packed));
        const expU = Array.from({ length: n }, () => 7);
        for (let m = start; m < n; m += stride) expU[m] = 42;
        deepStrictEqual(gotU, expU, `strided_fill_u32 n=${n} start=${start} stride=${stride}`);
      }

      throws(() => guest.call("strided_fill_oob", 10));
    },
    { stdRoot },
  );
});
