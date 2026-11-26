import { deepStrictEqual, ok, strictEqual, throws } from "node:assert/strict";
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

async function withModule(
  prefix: string,
  src: string,
  fn: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array,
  ) => void,
) {
  const dir = await Deno.makeTempDir({ prefix });
  const entry = `${dir}/main.blot`;
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
      const guest = await instantiateGuest(built.bytes);
      try {
        fn(guest, built.bytes);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Tier 5A: branchless merge, memory.copy tails, k<dst_len hoisting, aliasing & OOB traps", async () => {
  const src =
    `func merge_range (src: #[U32]) -> (dst: own #[U32]) -> (lo: U32) -> (mid: U32) -> (hi: U32): #[U32] =>
  let i = lo
  let j = mid
  let k = lo
  for ever:
    if i >= mid or j >= hi:
      break
    if src[i] <= src[j]:
      dst[k] := src[i]
      i := self + 1
    else:
      dst[k] := src[j]
      j := self + 1
    k := self + 1
  for ever:
    if i >= mid:
      break
    dst[k] := src[i]
    i := self + 1
    k := self + 1
  for ever:
    if j >= hi:
      break
    dst[k] := src[j]
    j := self + 1
    k := self + 1
  return dst

func merge_pass (src: #[U32]) -> (dst: own #[U32]) -> (width: U32) -> (n: U32): #[U32] =>
  let lo: U32 = 0
  let step = width << 1
  for ever:
    if lo >= n:
      break
    let mid = lo + width
    if mid > n:
      mid := n
    let hi = lo + step
    if hi > n:
      hi := n
    dst := merge_range src self lo mid hi
    lo := self + step
  return dst

io sort_vec (n: U32): #[U32] =>
  let a = @array.fill n 0
  let b = @array.fill n 0
  let s: U32 = 98765
  for i in 0 .. n:
    s := self * 1664525 + 1013904223
    a[i] := s
  let width: U32 = 1
  let in_b = false
  for ever:
    if width >= n:
      break
    b := merge_pass a self width n
    width := self << 1
    if width >= n:
      in_b := true
      break
    a := merge_pass b self width n
    width := self << 1
  return if in_b then b else a

// Self-overlapping copy-tail (dst == src, k = i + 1) must fall back from memory.copy!
io aliased_copy_tail (n: U32): #[U32] =>
  let a = @array.fill n 0
  for idx in 0 .. n:
    a[idx] := idx + 1
  let i: U32 = 0
  let k: U32 = 1
  let lim = if n > 0 then n - 1 else 0
  for ever:
    if i >= lim:
      break
    a[k] := a[i]
    i := self + 1
    k := self + 1
  return a

// OOB dst in 2-way merge loop or copy-tail must trap!
io merge_dst_oob (packed: U32): #[U32] =>
  let n_src = packed & 255
  let n_dst = (packed >> 8) & 255
  let mid = (packed >> 16) & 255
  let hi = (packed >> 24) & 255
  let src = @array.fill n_src 0
  for idx in 0 .. n_src:
    src[idx] := idx * 2 + 1
  let dst = @array.fill n_dst 0
  return merge_range src dst 0 mid hi
`;
  await withModule("blot-tier5a-", src, (guest) => {
    for (const n of [0, 1, 2, 3, 7, 16, 17, 63, 100]) {
      const got = asWords(guest.call("sort_vec", n));
      const expected: number[] = [];
      let s = 98765 >>> 0;
      for (let i = 0; i < n; i++) {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        expected.push(s);
      }
      expected.sort((x, y) => x - y);
      deepStrictEqual(got, expected, `sort_vec(${n}) mismatch`);
    }

    // Sequential overlapping copy propagates a[0] = 1 across every index!
    deepStrictEqual(asWords(guest.call("aliased_copy_tail", 8)), [
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
    ]);

    // Valid merge into exact-size dst
    deepStrictEqual(
      asWords(
        guest.call(
          "merge_dst_oob",
          ((6 << 24) | (3 << 16) | (6 << 8) | 6) >>> 0,
        ),
      ),
      [1, 3, 5, 7, 9, 11],
    );
    // dst shorter than hi (n_dst=4, hi=6) MUST TRAP in merge/copy-tail!
    throws(() =>
      guest.call("merge_dst_oob", ((6 << 24) | (3 << 16) | (4 << 8) | 6) >>> 0)
    );
    // hi > n_src (n_src=5, hi=6) MUST TRAP!
    throws(() =>
      guest.call("merge_dst_oob", ((6 << 24) | (3 << 16) | (6 << 8) | 5) >>> 0)
    );
  });
});

Deno.test("Tier 5B: 16-byte Maybe Vec3 v128 add/sub, scrambled fields, NaNs, aliasing & indirect-index bounds", async () => {
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

type Pos is data = $Pos { x: F32, y: F32, z: F32 }
type Vel is data = $Vel { vx: F32, vy: F32, vz: F32 }

// 5B-1 + 5B-2: scrambled field construction, sub, $Nothing preservation, NaN canonicalization, indirect dense_ids!
io vec3_indirect_step (packed: U32): #[U32] =>
  let n = packed & 255
  let steps = (packed >> 8) & 255
  let mode = (packed >> 16) & 255
  let pos: #[Maybe Pos] = @array.fill n $Nothing
  let vel: #[Maybe Vel] = @array.fill n $Nothing
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    let f = U32.to_f32 (i + 1)
    if (i % 3) != 1:
      let y0 = if i == 3 then inf else f * 2.0
      let vy0 = if i == 3 then (if mode == 1 then inf else 0.0 - inf) else 0.5
      pos[i] := $Some ($Pos { x: f, y: y0, z: f * 0.25 })
      vel[i] := $Some ($Vel { vx: 0.25, vy: vy0, vz: 0.125 })
  let ids = @array.fill n 0
  for i in 0 .. n:
    ids[i] := if mode == 2 and i == (n - 1) then n else (n - 1 - i)
  if mode == 1:
    // Subtract with scrambled field ordering in record literal
    for _ in 0 .. steps:
      for k in 0 .. n:
        let id = ids[k]
        if let $Some ($Pos { z, x, y }) = pos[id]:
          if let $Some ($Vel { vz, vx, vy }) = vel[id]:
            pos[id] := $Some ($Pos { z: z - vz, y: y - vy, x: x - vx })
  else:
    // Add via indirect index scan (mode=0 valid, mode=2 traps on ids[n-1] == n)
    for _ in 0 .. steps:
      for k in 0 .. n:
        let id = ids[k]
        if let $Some ($Pos { x, y, z }) = pos[id]:
          if let $Some ($Vel { vx, vy, vz }) = vel[id]:
            pos[id] := $Some ($Pos { x: x + vx, y: y + vy, z: z + vz })
  let out = @array.fill (n * 4) 0
  for i in 0 .. n:
    let base = i * 4
    case pos[i] of
      $Some ($Pos { x, y, z }) =>
        out[base] := 1
        out[base + 1] := f32_bits x
        out[base + 2] := f32_bits y
        out[base + 3] := f32_bits z
      $Nothing =>
        out[base] := 0
  return out

// Self-aliased pos == vel (doubling every lane)
io vec3_self_alias (n: U32): #[U32] =>
  let pos: #[Maybe Pos] = @array.fill n $Nothing
  for i in 0 .. n:
    let f = U32.to_f32 (i + 1)
    pos[i] := $Some ($Pos { x: f, y: f * 2.0, z: f * 3.0 })
  for _ in 0 .. 3:
    for i in 0 .. n:
      if let $Some ($Pos { x, y, z }) = pos[i]:
        if let $Some ($Pos { x: vx, y: vy, z: vz }) = pos[i]:
          pos[i] := $Some ($Pos { x: x + vx, y: y + vy, z: z + vz })
  let out = @array.fill n 0
  for i in 0 .. n:
    case pos[i] of
      $Some ($Pos { x, y, z }) =>
        out[i] := F32.to_u32 (x + y + z)
      $Nothing =>
        out[i] := 0
  return out
`;
  await withModule("blot-tier5b-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 5B");
    for (const mode of [0, 1]) {
      for (const steps of [1, 2, 5]) {
        const n = 9;
        const got = asWords(
          guest.call(
            "vec3_indirect_step",
            ((mode << 16) | (steps << 8) | n) >>> 0,
          ),
        );
        for (let i = 0; i < n; i++) {
          const b = i * 4;
          if (i % 3 === 1) {
            strictEqual(got[b], 0, `slot ${i} should remain $Nothing`);
          } else {
            strictEqual(got[b], 1, `slot ${i} should remain $Some`);
            if (i === 3) {
              strictEqual(
                got[b + 2],
                0x7fc00000,
                `slot 3 y NaN must canonicalize (mode=${mode}, steps=${steps})`,
              );
            } else {
              const f = Math.fround(i + 1);
              let x = f;
              let y = Math.fround(f * 2.0);
              let z = Math.fround(f * 0.25);
              for (let s = 0; s < steps; s++) {
                x = Math.fround(mode === 1 ? x - 0.25 : x + 0.25);
                y = Math.fround(mode === 1 ? y - 0.5 : y + 0.5);
                z = Math.fround(mode === 1 ? z - 0.125 : z + 0.125);
              }
              const fb = new Float32Array(
                new Uint32Array([got[b + 1], got[b + 2], got[b + 3]]).buffer,
              );
              strictEqual(fb[0], x);
              strictEqual(fb[1], y);
              strictEqual(fb[2], z);
            }
          }
        }
      }
    }
    // mode=2 has ids[n-1] == n (out of bounds!) -> MUST TRAP!
    throws(() =>
      guest.call("vec3_indirect_step", ((2 << 16) | (3 << 8) | 8) >>> 0)
    );
    // Self-aliased doubling 3x => factor of 8: (1+2+3)*8*(i+1) = 48*(i+1)
    deepStrictEqual(asWords(guest.call("vec3_self_alias", 4)), [
      48,
      96,
      144,
      192,
    ]);
  });
});

Deno.test("Tier 5C: 2-row x 16-col matmul across even/odd rows, tails, NaNs, overlapping C-stride & OOB trap", async () => {
  const src = `io matmul_rect (packed: U32): #[F32] =>
  let rows = packed & 255
  let inner = (packed >> 8) & 255
  let cols = (packed >> 16) & 255
  let a = @array.fill (rows * inner) 0.0
  let b = @array.fill (inner * cols) 0.0
  let c = @array.fill (rows * cols) 0.5
  let s: U32 = 54321
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

// NaN canonicalization in BOTH row 0 and row 1 (SIMD tile col=5 AND scalar tail col=17)
io matmul_nan_2row (m: U32): #[F32] =>
  let a = @array.fill 6 1.0
  let b = @array.fill (2 * m) 1.0
  let c = @array.fill (3 * m) 0.0
  let zero = U32.to_f32 (m & 0)
  let inf = 1.0 / zero
  a[0] := inf
  a[2] := 0.0 - inf
  a[4] := inf
  if m > 5:
    b[5] := 0.0
  if m > 17:
    b[17] := 0.0
  for row in 0 .. 3:
    let row_off_a = row * 2
    let row_off_c = row * m
    for k in 0 .. 2:
      let aik = a[row_off_a + k]
      let k_off = k * m
      for col in 0 .. m:
        let dst = row_off_c + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c

// Overlapping c_stride < cols MUST fall back to sequential row order!
io matmul_overlap_c (m: U32): #[F32] =>
  let a = @array.fill 4 1.0
  let b = @array.fill (2 * m) 1.0
  let c = @array.fill (m + 8) 0.0
  let c_stride: U32 = 4
  for row in 0 .. 2:
    let row_off_a = row * 2
    let row_off_c = row * c_stride
    for k in 0 .. 2:
      let aik = a[row_off_a + k]
      let k_off = k * m
      for col in 0 .. m:
        let dst = row_off_c + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c

// OOB row access must fall back and trap!
io matmul_oob (m: U32): F32 =>
  let a = @array.fill 4 1.0
  let b = @array.fill (2 * m) 1.0
  let c = @array.fill (m + 4) 0.0
  for row in 0 .. 2:
    let row_off_a = row * 2
    let row_off_c = row * m
    for k in 0 .. 2:
      let aik = a[row_off_a + k]
      let k_off = k * m
      for col in 0 .. m:
        let dst = row_off_c + col
        c[dst] := c[dst] + aik * b[k_off + col]
  return c[0]
`;
  await withModule("blot-tier5c-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 5C");
    for (
      const [rows, inner, cols] of [
        [1, 3, 16],
        [2, 4, 16],
        [3, 5, 19],
        [4, 8, 35],
        [5, 7, 15],
        [16, 16, 32],
      ]
    ) {
      const got = new Float32Array(
        new Uint32Array(
          asWords(
            guest.call(
              "matmul_rect",
              ((cols << 16) | (inner << 8) | rows) >>> 0,
            ),
          ),
        ).buffer,
      );
      const a = new Float32Array(rows * inner);
      const b = new Float32Array(inner * cols);
      const c = new Float32Array(rows * cols).fill(0.5);
      let s = 54321 >>> 0;
      for (let i = 0; i < rows * inner; i++) {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        a[i] = Math.fround((s & 63) * 0.125);
      }
      for (let i = 0; i < inner * cols; i++) {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        b[i] = Math.fround((s & 63) * 0.125);
      }
      for (let r = 0; r < rows; r++) {
        for (let k = 0; k < inner; k++) {
          for (let col = 0; col < cols; col++) {
            c[r * cols + col] = Math.fround(
              c[r * cols + col] +
                Math.fround(a[r * inner + k] * b[k * cols + col]),
            );
          }
        }
      }
      deepStrictEqual(
        Array.from(new Uint32Array(got.buffer)),
        Array.from(new Uint32Array(c.buffer)),
        `matmul_rect(${rows}x${inner}x${cols}) mismatch`,
      );
    }

    // NaN canonicalization across rows 0, 1 (5C 2-row) AND row 2 (4C 1-row odd tail)
    const m = 19;
    const nanW = asWords(guest.call("matmul_nan_2row", m));
    for (const r of [0, 1, 2]) {
      strictEqual(nanW[r * m + 5], 0x7fc00000, `row ${r} col 5 NaN`);
      strictEqual(nanW[r * m + 17], 0x7fc00000, `row ${r} col 17 tail NaN`);
    }

    // Overlapping c_stride=4 < m=16: row 0 writes 2.0 to [0..16), row 1 adds 2.0 to [4..20)
    const ov = new Float32Array(
      new Uint32Array(asWords(guest.call("matmul_overlap_c", 16))).buffer,
    );
    for (let i = 0; i < 4; i++) strictEqual(ov[i], 2.0);
    for (let i = 4; i < 16; i++) strictEqual(ov[i], 4.0);
    for (let i = 16; i < 20; i++) strictEqual(ov[i], 2.0);

    throws(() => guest.call("matmul_oob", 16));
  });
});

Deno.test("Tier 5D: 16-wide SIMD masked Bool and unmasked U32 reductions with edges and OOB traps", async () => {
  const src = `io masked_reduce (packed: U32): #[U32] =>
  let start = packed & 255
  let end = (packed >> 8) & 255
  let len = (packed >> 16) & 255
  let mode = (packed >> 24) & 255
  let flags = @array.fill len false
  for i in 0 .. len:
    flags[i] := if mode == 0 then false
      else if mode == 1 then true
      else ((i % 3) == 0 or (i % 5) == 0)
  let count: U32 = 0
  let sum: U32 = 0
  for i in start .. end:
    if flags[i]:
      count := self + 1
      sum := self + i
  return #[count, sum]

io unmasked_reduce (packed: U32): #[U32] =>
  let start = packed & 255
  let end = (packed >> 8) & 255
  let len = (packed >> 16) & 255
  let arr = @array.fill len 0
  for i in 0 .. len:
    arr[i] := (i * 17 + 3) ^ (i << 5)
  let sum: U32 = 0
  let xr: U32 = 0
  for i in start .. end:
    sum := self + arr[i]
  for i in start .. end:
    xr := self ^ arr[i]
  return #[sum, xr]
`;
  await withModule("blot-tier5d-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 5D");
    for (const mode of [0, 1, 2]) {
      for (
        const [start, end, len] of [
          [0, 0, 0],
          [0, 1, 1],
          [2, 17, 20],
          [2, 18, 20],
          [0, 32, 32],
          [3, 36, 40],
          [5, 3, 20],
          [2, 100, 100],
        ]
      ) {
        const packed = ((mode << 24) | (len << 16) | (end << 8) | start) >>> 0;
        const got = asWords(guest.call("masked_reduce", packed));
        let count = 0;
        let sum = 0;
        for (let i = start; i < end; i++) {
          const fl = mode === 0
            ? false
            : mode === 1
            ? true
            : (i % 3 === 0 || i % 5 === 0);
          if (fl) {
            count = (count + 1) >>> 0;
            sum = (sum + i) >>> 0;
          }
        }
        deepStrictEqual(
          got,
          [count, sum],
          `masked_reduce(${mode},${start},${end},${len})`,
        );
      }
    }
    // OOB end > len MUST TRAP!
    throws(() =>
      guest.call(
        "masked_reduce",
        ((2 << 24) | (20 << 16) | (21 << 8) | 0) >>> 0,
      )
    );

    for (
      const [start, end, len] of [
        [0, 0, 0],
        [0, 15, 15],
        [0, 16, 16],
        [1, 35, 40],
        [5, 2, 10],
      ]
    ) {
      const packed = ((len << 16) | (end << 8) | start) >>> 0;
      const got = asWords(guest.call("unmasked_reduce", packed));
      let sum = 0;
      let xr = 0;
      for (let i = start; i < end; i++) {
        const v = (Math.imul(i, 17) + 3) ^ (i << 5);
        sum = (sum + (v >>> 0)) >>> 0;
        xr = (xr ^ (v >>> 0)) >>> 0;
      }
      deepStrictEqual(
        got,
        [sum, xr],
        `unmasked_reduce(${start},${end},${len})`,
      );
    }
    throws(() =>
      guest.call("unmasked_reduce", ((16 << 16) | (20 << 8) | 0) >>> 0)
    );
  });
});

Deno.test("Tier 5E: 4-wide v128 outer-loop escape-time SIMD with divergence, tails & non-dead carry fallback", async () => {
  const src = `io mandel_small (packed: U32): U32 =>
  let size = packed & 255
  let limit = (packed >> 8) & 255
  let inv = if size > 0 then 1.0 / U32.to_f32 size else 0.0
  let total: U32 = 0
  for py in 0 .. size:
    let ci = U32.to_f32 py * inv * 2.4 - 1.2
    for px in 0 .. size:
      let cr = U32.to_f32 px * inv * 3.0 - 2.0
      let zr = 0.0
      let zi = 0.0
      let it: U32 = 0
      for ever:
        if it >= limit:
          break
        let zr2 = zr * zr
        let zi2 = zi * zi
        if zr2 + zi2 > 4.0:
          break
        let next_zi = 2.0 * zr * zi + ci
        zr := zr2 - zi2 + cr
        zi := next_zi
        it := self + 1
      total := self + it
  return total

// When a non-it carry (zr) is ALSO used after the inner loop, 5E MUST fall back to scalar!
io non_dead_carry_fallback (n: U32): U32 =>
  let total: U32 = 0
  let acc = 0.0
  for px in 0 .. n:
    let cr = U32.to_f32 px * 0.1
    let zr = 0.0
    let it: U32 = 0
    for ever:
      if it >= 10:
        break
      if zr > 2.0:
        break
      zr := zr + cr + 0.5
      it := self + 1
    total := self + it
    acc := self + zr
  return total + F32.to_u32 (acc * 10.0)
`;
  await withModule("blot-tier5e-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 5E");
    for (
      const [size, limit] of [
        [0, 10],
        [1, 10],
        [3, 10],
        [4, 0],
        [4, 1],
        [4, 2],
        [5, 25],
        [15, 50],
        [16, 100],
        [17, 100],
        [32, 100],
      ]
    ) {
      const got = guest.call("mandel_small", ((limit << 8) | size) >>> 0);
      const inv = size > 0 ? Math.fround(1.0 / Math.fround(size)) : 0.0;
      const c24 = Math.fround(2.4);
      const c12 = Math.fround(1.2);
      let total = 0;
      for (let py = 0; py < size; py++) {
        const ci = Math.fround(
          Math.fround(Math.fround(Math.fround(py) * inv) * c24) - c12,
        );
        for (let px = 0; px < size; px++) {
          const cr = Math.fround(
            Math.fround(Math.fround(Math.fround(px) * inv) * 3.0) - 2.0,
          );
          let zr = 0.0;
          let zi = 0.0;
          let it = 0;
          while (it < limit) {
            const zr2 = Math.fround(zr * zr);
            const zi2 = Math.fround(zi * zi);
            if (Math.fround(zr2 + zi2) > 4.0) break;
            const next_zi = Math.fround(
              Math.fround(Math.fround(2.0 * zr) * zi) + ci,
            );
            zr = Math.fround(Math.fround(zr2 - zi2) + cr);
            zi = next_zi;
            it++;
          }
          total = (total + it) >>> 0;
        }
      }
      strictEqual(got, total, `mandel_small(size=${size}, limit=${limit})`);
    }

    // Verify non-dead carry fallback matches exact scalar math
    let expTot = 0;
    let expAcc = 0.0;
    for (let px = 0; px < 9; px++) {
      const cr = Math.fround(Math.fround(px) * Math.fround(0.1));
      let zr = 0.0;
      let it = 0;
      while (it < 10) {
        if (zr > 2.0) break;
        zr = Math.fround(Math.fround(zr + cr) + 0.5);
        it++;
      }
      expTot = (expTot + it) >>> 0;
      expAcc = Math.fround(expAcc + zr);
    }
    strictEqual(
      guest.call("non_dead_carry_fallback", 9),
      (expTot + Math.trunc(Math.fround(expAcc * 10.0))) >>> 0,
    );
  });
});

Deno.test("Tier 5F: 16-wide SIMD LCG recurrence & 8x scalar affine unroll across all remainders", async () => {
  const src = `io lcg_xor (packed: U32): U32 =>
  let seed = packed & 65535
  let n = packed >> 16
  let state = seed | 1
  let acc: U32 = 0
  for _ in 0 .. n:
    state := self * 1664525 + 1013904223
    acc := self ^ (state >> 16)
  return acc ^ state

io lcg_add_range (packed: U32): U32 =>
  let start = packed & 255
  let end = (packed >> 8) & 255
  let state: U32 = 77
  let acc: U32 = 5
  for _ in start .. end:
    state := self * 1664525 + 1013904223
    acc := self + (state & 65535)
  return acc ^ state

// Non-associative 2-op carry exercises the 8x scalar unroll fallback!
io lcg_scalar8 (n: U32): U32 =>
  let state: U32 = 1337
  let acc: U32 = 0
  for _ in 0 .. n:
    state := self * 1664525 + 1013904223
    acc := (self * 31) ^ (state >> 16)
  return acc ^ state
`;
  await withModule("blot-tier5f-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 5F");
    for (const n of [0, 1, 2, 7, 8, 9, 15, 16, 17, 31, 32, 33, 100, 1007]) {
      const seed = 42;
      let st = (seed | 1) >>> 0;
      let acc = 0;
      for (let i = 0; i < n; i++) {
        st = (Math.imul(st, 1664525) + 1013904223) >>> 0;
        acc = (acc ^ (st >>> 16)) >>> 0;
      }
      strictEqual(
        guest.call("lcg_xor", ((n << 16) | seed) >>> 0),
        (acc ^ st) >>> 0,
        `lcg_xor(n=${n})`,
      );

      let st2 = 1337 >>> 0;
      let acc2 = 0;
      for (let i = 0; i < n; i++) {
        st2 = (Math.imul(st2, 1664525) + 1013904223) >>> 0;
        acc2 = (Math.imul(acc2, 31) ^ (st2 >>> 16)) >>> 0;
      }
      strictEqual(
        guest.call("lcg_scalar8", n),
        (acc2 ^ st2) >>> 0,
        `lcg_scalar8(n=${n})`,
      );
    }

    for (const [start, end] of [[0, 0], [5, 3], [3, 20], [1, 33], [7, 55]]) {
      let st = 77 >>> 0;
      let acc = 5 >>> 0;
      for (let i = start; i < end; i++) {
        st = (Math.imul(st, 1664525) + 1013904223) >>> 0;
        acc = (acc + (st & 65535)) >>> 0;
      }
      strictEqual(
        guest.call("lcg_add_range", ((end << 8) | start) >>> 0),
        (acc ^ st) >>> 0,
        `lcg_add_range(${start}..${end})`,
      );
    }
  });
});
