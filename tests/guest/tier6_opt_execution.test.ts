import { deepStrictEqual, ok, strictEqual, throws } from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;

function asWords(value: unknown): number[] {
  const view = value as Float32Array | Uint32Array;
  return Array.from(
    new Uint32Array(view.buffer, view.byteOffset, view.length),
  );
}

function f32Bits(x: number): number {
  const f = new Float32Array([Math.fround(x)]);
  return new Uint32Array(f.buffer)[0];
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
  const entry = `${dir}/main.sq`;
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

Deno.test("Tier 6A: 4x coalesced Maybe Vec3 SIMD (contiguous, contiguous-ID, sparse-ID, duplicate-ID, NaN, alias & OOB)", async () => {
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

type Vec3 is data = $Vec3 { x: F32, y: F32, z: F32 }

io contig_step (packed: U32): #[U32] =>
  let n = packed & 255
  let steps = (packed >> 8) & 255
  let mode = (packed >> 16) & 255
  let pos: #[Maybe Vec3] = @array.fill n $Nothing
  let vlen = if mode == 3 and n > 0 then n - 1 else n
  let vel: #[Maybe Vec3] = @array.fill vlen $Nothing
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    let f = U32.to_f32 (i + 1)
    let present = if mode == 1 then ((i % 5) != 2 and (i % 7) != 0) else true
    if present:
      let y0 = if i == 5 and mode != 2 then inf else f * 2.0
      pos[i] := $Some ($Vec3 { x: f, y: y0, z: f * 0.25 })
      if i < vlen:
        let vy0 = if i == 5 and mode != 2 then (if mode == 1 then inf else 0.0 - inf) else 0.5
        vel[i] := $Some ($Vec3 { x: 0.25, y: vy0, z: 0.125 })
  if mode == 1:
    for _ in 0 .. steps:
      for i in 0 .. n:
        if let $Some ($Vec3 { x, y, z }) = pos[i]:
          if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = vel[i]:
            pos[i] := $Some ($Vec3 { x: x - vx, y: y - vy, z: z - vz })
  else:
    if mode == 2:
      for _ in 0 .. steps:
        for i in 0 .. n:
          if let $Some ($Vec3 { x, y, z }) = pos[i]:
            if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = pos[i]:
              pos[i] := $Some ($Vec3 { x: x + vx, y: y + vy, z: z + vz })
    else:
      for _ in 0 .. steps:
        for i in 0 .. n:
          if let $Some ($Vec3 { x, y, z }) = pos[i]:
            if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = vel[i]:
              pos[i] := $Some ($Vec3 { x: x + vx, y: y + vy, z: z + vz })
  let out = @array.fill (n * 4) 0
  for i in 0 .. n:
    let b = i * 4
    case pos[i] of
      $Some ($Vec3 { x, y, z }) =>
        out[b] := 1
        out[b + 1] := f32_bits x
        out[b + 2] := f32_bits y
        out[b + 3] := f32_bits z
      $Nothing =>
        out[b] := 0
  return out

io indirect_step (packed: U32): #[U32] =>
  let n = packed & 255
  let m = (packed >> 8) & 255
  let steps = (packed >> 16) & 15
  let mode = (packed >> 20) & 15
  let pos: #[Maybe Vec3] = @array.fill n $Nothing
  let vel: #[Maybe Vec3] = @array.fill n $Nothing
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    let f = U32.to_f32 (i + 1)
    if (i % 9) != 4:
      let y0 = if i == 6 and mode < 4 then inf else f * 2.0
      let vy0 = if i == 6 and mode < 4 then 0.0 - inf else 0.5
      pos[i] := $Some ($Vec3 { x: f, y: y0, z: f * 0.25 })
      vel[i] := $Some ($Vec3 { x: 0.25, y: vy0, z: 0.125 })
  let ids = @array.fill m 0
  for k in 0 .. m:
    let id_v = if mode == 0 or mode == 4 then (3 + k)
      else if mode == 1 or mode == 5 then (k * 2)
      else if mode == 2 then (if k < 4 then 2 else if k < 6 then 0 else if k < 8 then 1 else (k % n))
      else if mode == 3 then (m - 1 - k)
      else (if k + 1 == m then n else k)
    ids[k] := id_v
  if mode == 4 or mode == 5:
    for _ in 0 .. steps:
      for k in 0 .. m:
        let id = ids[k]
        if let $Some ($Vec3 { x, y, z }) = pos[id]:
          if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = pos[id]:
            pos[id] := $Some ($Vec3 { x: x + vx, y: y + vy, z: z + vz })
  else:
    for _ in 0 .. steps:
      for k in 0 .. m:
        let id = ids[k]
        if let $Some ($Vec3 { x, y, z }) = pos[id]:
          if let $Some ($Vec3 { x: vx, y: vy, z: vz }) = vel[id]:
            pos[id] := $Some ($Vec3 { x: x + vx, y: y + vy, z: z + vz })
  let out = @array.fill (n * 4) 0
  for i in 0 .. n:
    let b = i * 4
    case pos[i] of
      $Some ($Vec3 { x, y, z }) =>
        out[b] := 1
        out[b + 1] := f32_bits x
        out[b + 2] := f32_bits y
        out[b + 3] := f32_bits z
      $Nothing =>
        out[b] := 0
  return out
`;
  await withModule("squid-tier6a-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 6A");

    // 1. Shape 1 contiguous across boundary sizes & step counts
    for (const mode of [0, 1, 2]) {
      for (const steps of [1, 2, 5]) {
        for (const n of [0, 1, 3, 4, 5, 8, 9, 16, 19]) {
          const got = asWords(
            guest.call("contig_step", ((mode << 16) | (steps << 8) | n) >>> 0),
          );
          strictEqual(got.length, n * 4);
          for (let i = 0; i < n; i++) {
            const b = i * 4;
            const present = mode === 1 ? (i % 5 !== 2 && i % 7 !== 0) : true;
            if (!present) {
              strictEqual(got[b], 0);
              continue;
            }
            strictEqual(got[b], 1);
            const f = Math.fround(i + 1);
            let x = f;
            let y = i === 5 && mode !== 2 ? Infinity : Math.fround(f * 2.0);
            let z = Math.fround(f * 0.25);
            const vx = 0.25;
            const vy = i === 5 && mode !== 2
              ? (mode === 1 ? Infinity : -Infinity)
              : 0.5;
            const vz = 0.125;
            for (let s = 0; s < steps; s++) {
              if (mode === 1) {
                x = Math.fround(x - vx);
                y = Math.fround(y - vy);
                z = Math.fround(z - vz);
              } else if (mode === 2) {
                x = Math.fround(x + x);
                y = Math.fround(y + y);
                z = Math.fround(z + z);
              } else {
                x = Math.fround(x + vx);
                y = Math.fround(y + vy);
                z = Math.fround(z + vz);
              }
            }
            strictEqual(got[b + 1], f32Bits(x));
            if (Number.isNaN(y)) {
              strictEqual(
                got[b + 2],
                0x7fc00000,
                `contig NaN canon mode=${mode} n=${n} steps=${steps}`,
              );
            } else {
              strictEqual(got[b + 2], f32Bits(y));
            }
            strictEqual(got[b + 3], f32Bits(z));
          }
        }
      }
    }
    // Contiguous OOB trap when vel is shorter than pos
    throws(() => guest.call("contig_step", ((3 << 16) | (2 << 8) | 9) >>> 0));

    // 2. Shape 2 indirect across all 6 valid modes & multiple sizes
    const cases: Array<[number, number, number, number]> = [
      [20, 13, 4, 0], // State 2 contiguous offset span (ids = 3..15)
      [20, 4, 2, 0],
      [20, 1, 3, 0],
      [20, 10, 4, 1], // State 1 sparse strictly increasing (ids = 0,2,4..18)
      [20, 9, 3, 1],
      [12, 11, 4, 2], // State 0 duplicate IDs [2,2,2,2,0,0,1,1,8,9,10]
      [12, 9, 3, 3], // State 0 reverse unsorted unique IDs
      [20, 12, 3, 4], // State 2 contiguous self-alias pos == vel
      [20, 9, 3, 5], // State 1 sparse self-alias pos == vel
    ];
    for (const [n, m, steps, mode] of cases) {
      const packed = ((mode << 20) | (steps << 16) | (m << 8) | n) >>> 0;
      const got = asWords(guest.call("indirect_step", packed));
      // Build exact reference
      const pos: Array<[number, number, number] | null> = [];
      const vel: Array<[number, number, number] | null> = [];
      for (let i = 0; i < n; i++) {
        if (i % 9 === 4) {
          pos.push(null);
          vel.push(null);
        } else {
          const f = Math.fround(i + 1);
          const y0 = i === 6 && mode < 4 ? Infinity : Math.fround(f * 2.0);
          const vy0 = i === 6 && mode < 4 ? -Infinity : 0.5;
          pos.push([f, y0, Math.fround(f * 0.25)]);
          vel.push([0.25, vy0, 0.125]);
        }
      }
      const ids: number[] = [];
      for (let k = 0; k < m; k++) {
        if (mode === 0 || mode === 4) ids.push(3 + k);
        else if (mode === 1 || mode === 5) ids.push(k * 2);
        else if (mode === 2) {
          ids.push(k < 4 ? 2 : k < 6 ? 0 : k < 8 ? 1 : k % n);
        } else ids.push(m - 1 - k);
      }
      for (let s = 0; s < steps; s++) {
        for (const id of ids) {
          const p = pos[id];
          const v = mode === 4 || mode === 5 ? pos[id] : vel[id];
          if (p && v) {
            pos[id] = [
              Math.fround(p[0] + v[0]),
              Math.fround(p[1] + v[1]),
              Math.fround(p[2] + v[2]),
            ];
          }
        }
      }
      for (let i = 0; i < n; i++) {
        const b = i * 4;
        const p = pos[i];
        if (!p) {
          strictEqual(got[b], 0, `mode=${mode} i=${i} expected $Nothing`);
        } else {
          strictEqual(got[b], 1, `mode=${mode} i=${i} expected $Some`);
          strictEqual(got[b + 1], f32Bits(p[0]), `mode=${mode} i=${i} x`);
          if (Number.isNaN(p[1])) {
            strictEqual(
              got[b + 2],
              0x7fc00000,
              `mode=${mode} i=${i} y NaN canon`,
            );
          } else {
            strictEqual(got[b + 2], f32Bits(p[1]), `mode=${mode} i=${i} y`);
          }
          strictEqual(got[b + 3], f32Bits(p[2]), `mode=${mode} i=${i} z`);
        }
      }
    }
    // Indirect OOB trap
    throws(() =>
      guest.call(
        "indirect_step",
        ((6 << 20) | (2 << 16) | (9 << 8) | 12) >>> 0,
      )
    );
  });
});

Deno.test("Tier 6B-1: 4x8 2x-k-unrolled matmul across all row/k/col remainders, NaN canon, aliasing & OOB", async () => {
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

io matmul_rect (packed: U32): #[U32] =>
  let rows = packed & 63
  let inner = (packed >> 6) & 63
  let cols = (packed >> 12) & 63
  let mode = (packed >> 18) & 15
  let a = @array.fill (rows * inner) 0.0
  let b = @array.fill (inner * cols) 0.0
  let c_len = if mode == 3 and rows > 0 and cols > 0 then rows * cols - 1 else rows * cols
  let c = @array.fill c_len 0.0
  let zero = U32.to_f32 (packed & 0)
  let inf = 1.0 / zero
  for i in 0 .. (rows * inner):
    a[i] := U32.to_f32 ((i * 7 + 3) % 19) * 0.125
  for i in 0 .. (inner * cols):
    b[i] := U32.to_f32 ((i * 11 + 5) % 17) * 0.25
  if mode == 1 and rows >= 4 and inner >= 1 and cols >= 9:
    // Inject +Inf * 0.0 NaNs into all 4 rows in both SIMD col 2 and scalar tail col (cols - 1)
    a[0 * inner] := inf
    a[1 * inner] := inf
    a[2 * inner] := inf
    a[3 * inner] := inf
    b[2] := 0.0
    b[cols - 1] := 0.0
  if mode == 2:
    // Self-aliased c == b (square rows == inner == cols)
    for i in 0 .. rows:
      let row_a = i * inner
      let row_c = i * cols
      for k in 0 .. inner:
        let aik = a[row_a + k]
        let row_b = k * cols
        for j in 0 .. cols:
          b[row_c + j] := self + aik * b[row_b + j]
    let out = @array.fill (inner * cols) 0
    for i in 0 .. (inner * cols):
      out[i] := f32_bits b[i]
    return out
  for i in 0 .. rows:
    let row_a = i * inner
    let row_c = i * cols
    for k in 0 .. inner:
      let aik = a[row_a + k]
      let row_b = k * cols
      for j in 0 .. cols:
        c[row_c + j] := self + aik * b[row_b + j]
  let out = @array.fill (rows * cols) 0
  for i in 0 .. (rows * cols):
    out[i] := f32_bits c[i]
  return out
`;
  await withModule("squid-tier6b1-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 6B-1");

    const refMatmul = (
      rows: number,
      inner: number,
      cols: number,
      mode: number,
    ): number[] => {
      const a = new Float32Array(rows * inner);
      const b = new Float32Array(inner * cols);
      const c = new Float32Array(rows * cols);
      for (let i = 0; i < rows * inner; i++) {
        a[i] = Math.fround(((i * 7 + 3) % 19) * 0.125);
      }
      for (let i = 0; i < inner * cols; i++) {
        b[i] = Math.fround(((i * 11 + 5) % 17) * 0.25);
      }
      if (mode === 1 && rows >= 4 && inner >= 1 && cols >= 9) {
        a[0 * inner] = Infinity;
        a[1 * inner] = Infinity;
        a[2 * inner] = Infinity;
        a[3 * inner] = Infinity;
        b[2] = 0.0;
        b[cols - 1] = 0.0;
      }
      const dst = mode === 2 ? b : c;
      for (let i = 0; i < rows; i++) {
        const ra = i * inner;
        const rc = i * cols;
        for (let k = 0; k < inner; k++) {
          const aik = a[ra + k];
          const rb = k * cols;
          for (let j = 0; j < cols; j++) {
            dst[rc + j] = Math.fround(
              dst[rc + j] + Math.fround(aik * b[rb + j]),
            );
          }
        }
      }
      const out: number[] = [];
      for (let i = 0; i < dst.length; i++) {
        out.push(Number.isNaN(dst[i]) ? 0x7fc00000 : f32Bits(dst[i]));
      }
      return out;
    };

    const shapes: Array<[number, number, number]> = [
      [1, 1, 1],
      [2, 3, 8],
      [3, 4, 16],
      [4, 1, 8],
      [4, 2, 9],
      [4, 5, 17],
      [5, 3, 15],
      [6, 4, 16],
      [7, 5, 24],
      [8, 6, 27],
      [9, 7, 7],
      [12, 13, 19],
    ];
    for (const [r, k, c] of shapes) {
      const packed = ((c << 12) | (k << 6) | r) >>> 0;
      const got = asWords(guest.call("matmul_rect", packed));
      deepStrictEqual(
        got,
        refMatmul(r, k, c, 0),
        `matmul_rect ${r}x${k}x${c}`,
      );
    }

    // NaN canonicalization across all 4 rows in both SIMD col 2 and scalar tail col 10
    {
      const [r, k, c] = [6, 5, 11];
      const packed = ((1 << 18) | (c << 12) | (k << 6) | r) >>> 0;
      const got = asWords(guest.call("matmul_rect", packed));
      const exp = refMatmul(r, k, c, 1);
      deepStrictEqual(got, exp, "matmul_rect NaN canonicalization");
      for (let row = 0; row < 4; row++) {
        strictEqual(got[row * c + 2], 0x7fc00000, `row ${row} SIMD col 2 NaN`);
        strictEqual(
          got[row * c + (c - 1)],
          0x7fc00000,
          `row ${row} tail col NaN`,
        );
      }
    }

    // Aliased c == b fallback
    {
      const [r, k, c] = [8, 8, 8];
      const packed = ((2 << 18) | (c << 12) | (k << 6) | r) >>> 0;
      const got = asWords(guest.call("matmul_rect", packed));
      deepStrictEqual(got, refMatmul(r, k, c, 2), "matmul_rect aliased c == b");
    }

    // OOB trap when c is too short
    throws(() =>
      guest.call(
        "matmul_rect",
        ((3 << 18) | (16 << 12) | (4 << 6) | 8) >>> 0,
      )
    );
  });
});

Deno.test("Tier 6B-2: 4-wide v128 SIMD affine-LCG array-init (1-step U32, 2-step F32, final state, subranges & OOB)", async () => {
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

io init_u32_1step (packed: U32): #[U32] =>
  let start = packed & 255
  let end = (packed >> 8) & 255
  let cap = (packed >> 16) & 255
  let a = @array.fill cap 777
  let s: U32 = 98765
  for i in start .. end:
    s := self * 1664525 + 1013904223
    a[i] := s
  let out = @array.fill (cap + 1) 0
  for i in 0 .. cap:
    out[i] := a[i]
  out[cap] := s
  return out

io init_f32_2step (n: U32): #[U32] =>
  let a = @array.fill n 0.0
  let b = @array.fill n 0.0
  let s: U32 = 12345
  for i in 0 .. n:
    s := self * 1664525 + 1013904223
    a[i] := U32.to_f32 (s & 1023) * 0.0009765625
    s := self * 1664525 + 1013904223
    b[i] := U32.to_f32 (s & 1023) * 0.0009765625
  let out = @array.fill (n * 2 + 1) 0
  for i in 0 .. n:
    out[i] := f32_bits a[i]
    out[n + i] := f32_bits b[i]
  out[n * 2] := s
  return out
`;
  await withModule("squid-tier6b2-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 6B-2");

    // 1-step U32 across all mod-4 sizes, subranges, and empty/reversed ranges
    const ranges: Array<[number, number, number]> = [
      [0, 0, 0],
      [0, 1, 1],
      [0, 2, 2],
      [0, 3, 3],
      [0, 4, 4],
      [0, 5, 5],
      [0, 7, 7],
      [0, 8, 8],
      [0, 9, 9],
      [0, 16, 16],
      [0, 17, 17],
      [0, 65, 65],
      [3, 14, 18],
      [10, 4, 16], // end < start => empty
    ];
    for (const [start, end, cap] of ranges) {
      const packed = ((cap << 16) | (end << 8) | start) >>> 0;
      const got = asWords(guest.call("init_u32_1step", packed));
      const exp = new Array(cap + 1).fill(777);
      let s = 98765 >>> 0;
      for (let i = start; i < end; i++) {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        exp[i] = s;
      }
      exp[cap] = s;
      deepStrictEqual(got, exp, `init_u32_1step ${start}..${end} cap=${cap}`);
    }
    // OOB trap when end > cap
    throws(() =>
      guest.call("init_u32_1step", ((8 << 16) | (9 << 8) | 0) >>> 0)
    );

    // 2-step F32 across all mod-4 sizes
    for (const n of [0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 65]) {
      const got = asWords(guest.call("init_f32_2step", n));
      const exp = new Array(n * 2 + 1).fill(0);
      let s = 12345 >>> 0;
      for (let i = 0; i < n; i++) {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        exp[i] = f32Bits(Math.fround((s & 1023) * 0.0009765625));
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        exp[n + i] = f32Bits(Math.fround((s & 1023) * 0.0009765625));
      }
      exp[n * 2] = s;
      deepStrictEqual(got, exp, `init_f32_2step n=${n}`);
    }
  });
});

Deno.test("Tier 6C: dual-stream 8-pixel v128 escape SIMD across 8-pixel, 4-pixel tail & scalar tail", async () => {
  const src = `io mandel_check (packed: U32): U32 =>
  let size = packed & 255
  let limit = (packed >> 8) & 255
  let inv = 1.0 / U32.to_f32 size
  let total: U32 = 0
  for py in 0 .. size:
    let ci = U32.to_f32 py * inv * 2.4 - 1.2
    for px in 0 .. size:
      let cr = U32.to_f32 px * inv * 2.4 - 1.8
      let zr: F32 = 0.0
      let zi: F32 = 0.0
      let it: U32 = 0
      for ever:
        if it >= limit:
          break
        let zr2 = zr * zr
        let zi2 = zi * zi
        if zr2 + zi2 > 4.0:
          break
        let nzi = 2.0 * zr * zi + ci
        zr := zr2 - zi2 + cr
        zi := nzi
        it := self + 1
      total := self + it
  return total
`;
  await withModule("squid-tier6c-", src, (guest, bytes) => {
    ok(bytes.includes(0xfd), "Expected v128 SIMD ops in Tier 6C");

    const f24 = Math.fround(2.4);
    const f12 = Math.fround(1.2);
    const f18 = Math.fround(1.8);
    const refMandel = (size: number, limit: number): number => {
      if (size === 0) return 0;
      const inv = Math.fround(1.0 / Math.fround(size));
      let total = 0;
      for (let py = 0; py < size; py++) {
        const ci = Math.fround(
          Math.fround(Math.fround(Math.fround(py) * inv) * f24) - f12,
        );
        for (let px = 0; px < size; px++) {
          const cr = Math.fround(
            Math.fround(Math.fround(Math.fround(px) * inv) * f24) - f18,
          );
          let zr = 0;
          let zi = 0;
          let it = 0;
          while (it < limit) {
            const zr2 = Math.fround(zr * zr);
            const zi2 = Math.fround(zi * zi);
            if (Math.fround(zr2 + zi2) > 4.0) break;
            const nzi = Math.fround(
              Math.fround(Math.fround(2.0 * zr) * zi) + ci,
            );
            zr = Math.fround(Math.fround(zr2 - zi2) + cr);
            zi = nzi;
            it++;
          }
          total = (total + it) >>> 0;
        }
      }
      return total;
    };

    for (const limit of [0, 1, 2, 10, 64]) {
      for (const size of [1, 3, 4, 5, 7, 8, 9, 12, 15, 16, 17, 24, 32]) {
        const got = guest.call(
          "mandel_check",
          ((limit << 8) | size) >>> 0,
        ) as number;
        strictEqual(
          got,
          refMandel(size, limit),
          `mandel_check size=${size} limit=${limit}`,
        );
      }
    }
  });
});
