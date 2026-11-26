import { ok, strictEqual, throws } from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;

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
        guest.dispose?.();
      }
    } finally {
      await compiler.close();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

function hasSubOpcode(bytes: Uint8Array, prefix: number, sub: number): boolean {
  for (let i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] === prefix && bytes[i + 1] === sub) return true;
  }
  return false;
}

Deno.test("Tier 7A: 4-wide branchless v128 SIMD reduction on Maybe Vec3 pools", async () => {
  const source = `
type Pos is data = $Pos { z: F32, x: F32, y: F32 }

func make_pool (n: U32) -> (mode: U32): #[Maybe Pos] =>
  let out: #[Maybe Pos] = #[]
  for i in 0 .. n:
    let present = if mode == 0 then true
      else if mode == 1 then (i % 3 != 1)
      else if mode == 2 then false
      else (i % 4 == 0 or i % 4 == 3)
    if present:
      let f = U32.to_f32 (i + 1)
      let x = if mode == 3 and i == 4 then 0.0 / 0.0 else f * 0.25
      let y = if mode == 3 and i == 8 then -100.0 else f * 0.5
      let z = f * 0.125
      @storage.push out ($Some ($Pos { z, x, y }))
    else:
      @storage.push out $Nothing
  return out

func sum_simd (pos: #[Maybe Pos]) -> (scale: F32): U32 =>
  let sum: U32 = 0
  for i in 0 .. pos.length:
    if let $Some ($Pos { x, y, z }) = pos[i]:
      sum := self + F32.to_u32 ((x + y + z) * scale)
  return sum

func xor_simd (pos: #[Maybe Pos]): U32 =>
  let acc: U32 = 0
  for i in 0 .. pos.length:
    if let $Some ($Pos { x, y, z }) = pos[i]:
      acc := self ^ F32.to_u32 ((x + y - z) * 8.0)
  return acc

func sum_scalar_ref (pos: #[Maybe Pos]) -> (scale: F32): U32 =>
  let sum: U32 = 0
  let i: U32 = 0
  for ever:
    if i >= pos.length:
      break
    if let $Some ($Pos { x, y, z }) = pos[i]:
      sum := self + F32.to_u32 ((x + y + z) * scale)
    i := self + 1
  return sum

func xor_scalar_ref (pos: #[Maybe Pos]): U32 =>
  let acc: U32 = 0
  let i: U32 = 0
  for ever:
    if i >= pos.length:
      break
    if let $Some ($Pos { x, y, z }) = pos[i]:
      acc := self ^ F32.to_u32 ((x + y - z) * 8.0)
    i := self + 1
  return acc

io check_all (packed: U32): U32 =>
  let n = packed >> 4
  let mode = packed & 15
  let pool = make_pool n mode
  let s1 = sum_simd pool 16.0
  let s2 = sum_scalar_ref pool 16.0
  let x1 = xor_simd pool
  let x2 = xor_scalar_ref pool
  return if s1 == s2 and x1 == x2 then s1 ^ x1 else 0xdeadbeef

io oob_sum (n: U32): U32 =>
  let pool = make_pool n 0
  let sum: U32 = 0
  for i in 0 .. (n + 1):
    if let $Some ($Pos { x, y, z }) = pool[i]:
      sum := self + F32.to_u32 ((x + y + z) * 16.0)
  return sum
`;
  await withModule("blot_tier7a_", source, (guest, bytes) => {
    ok(
      hasSubOpcode(bytes, 0xfd, 13),
      "expected i8x16.shuffle (0xfd 0x0d) in Maybe Vec3 SIMD reduction",
    );
    for (const n of [0, 1, 3, 4, 5, 7, 16, 17, 65]) {
      for (const mode of [0, 1, 2, 3]) {
        const res = guest.call("check_all", (n << 4) | mode) as number;
        ok(res !== 0xdeadbeef, `Tier 7A mismatch for n=${n}, mode=${mode}`);
      }
    }
    throws(() => guest.call("oob_sum", 12));
  });
});

Deno.test("Tier 7B: Dead @array.fill elision preserves conditional, self-read, and zero-len semantics", async () => {
  const source = `
io full_overwrite (n: U32): U32 =>
  let a = @array.fill n 99
  let b = @array.fill n 77
  let c = @array.fill n 5
  for i in 0 .. n:
    a[i] := i * 3 + 1
    b[i] := i * 5 + 2
  let sum: U32 = 0
  for i in 0 .. n:
    sum := self + a[i] + b[i] + c[i]
  return sum

io conditional_must_keep_fill (n: U32): U32 =>
  let a = @array.fill n 7
  for i in 0 .. n:
    if i % 2 == 0:
      a[i] := i
  let sum: U32 = 0
  for i in 0 .. n:
    sum := self + a[i]
  return sum

io self_read_must_keep_fill (n: U32): U32 =>
  let a = @array.fill n 11
  for i in 0 .. n:
    a[i] := a[i] + i
  let sum: U32 = 0
  for i in 0 .. n:
    sum := self + a[i]
  return sum
`;
  await withModule("blot_tier7b_", source, (guest) => {
    for (const n of [0, 1, 4, 17]) {
      let expFull = 0;
      let expCond = 0;
      let expSelf = 0;
      for (let i = 0; i < n; i++) {
        expFull = (expFull + (i * 3 + 1) + (i * 5 + 2) + 5) >>> 0;
        expCond = (expCond + (i % 2 === 0 ? i : 7)) >>> 0;
        expSelf = (expSelf + 11 + i) >>> 0;
      }
      strictEqual(guest.call("full_overwrite", n), expFull);
      strictEqual(guest.call("conditional_must_keep_fill", n), expCond);
      strictEqual(guest.call("self_read_must_keep_fill", n), expSelf);
    }
  });
});

Deno.test("Tier 7C: Multi-array for auto-SIMD & 8x exact left-to-right F32 sum reduction", async () => {
  const source = `
import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

io multi_init (packed: U32): U32 =>
  let n = packed >> 4
  let seed = packed & 15
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  let ax = @array.fill n 0.0
  let base = U32.to_f32 (seed & 15)
  for i in 0 .. n:
    let fi = U32.to_f32 (i & 1023)
    px[i] := base + fi * 0.01
    vx[i] := fi * 0.02
    ax[i] := 0.5 - fi * 0.001
  let sp: F32 = 0.0
  for i in 0 .. n:
    sp := self + px[i]
  let sv: F32 = 0.0
  for i in 0 .. n:
    sv := self + vx[i]
  let sa: F32 = 0.0
  for i in 0 .. n:
    sa := self + ax[i]
  return f32_bits (sp + sv + sa)

io multi_init_ref (packed: U32): U32 =>
  let n = packed >> 4
  let seed = packed & 15
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  let ax = @array.fill n 0.0
  let base = U32.to_f32 (seed & 15)
  let i: U32 = 0
  for ever:
    if i >= n:
      break
    let fi = U32.to_f32 (i & 1023)
    px[i] := base + fi * 0.01
    vx[i] := fi * 0.02
    ax[i] := 0.5 - fi * 0.001
    i := self + 1
  let sp: F32 = 0.0
  let j: U32 = 0
  for ever:
    if j >= n:
      break
    sp := self + px[j]
    j := self + 1
  let sv: F32 = 0.0
  let k: U32 = 0
  for ever:
    if k >= n:
      break
    sv := self + vx[k]
    k := self + 1
  let sa: F32 = 0.0
  let l: U32 = 0
  for ever:
    if l >= n:
      break
    sa := self + ax[l]
    l := self + 1
  return f32_bits (sp + sv + sa)

io exact_f32_sum_order (n: U32): U32 =>
  let xs = @array.fill n 0.0
  for i in 0 .. n:
    xs[i] := if i == 0 then 16777216.0 else 0.75
  let s1: F32 = 0.0
  for i in 0 .. n:
    s1 := self + xs[i]
  let s2: F32 = 0.0
  let j: U32 = 0
  for ever:
    if j >= n:
      break
    s2 := self + xs[j]
    j := self + 1
  return if f32_bits s1 == f32_bits s2 then f32_bits s1 else 0xdeadbeef

io f32_sum_nan_canon (n: U32): U32 =>
  let xs = @array.fill n 1.0
  if n > 3:
    xs[3] := 0.0 / 0.0
  let s: F32 = 0.0
  for i in 0 .. n:
    s := self + xs[i]
  return f32_bits s

io f32_sum_oob (n: U32): U32 =>
  let xs = @array.fill n 1.0
  let s: F32 = 0.0
  for i in 0 .. (n + 1):
    s := self + xs[i]
  return f32_bits s
`;
  await withModule("blot_tier7c_", source, (guest) => {
    for (const n of [0, 1, 3, 4, 7, 8, 9, 15, 16, 17, 35, 65]) {
      strictEqual(
        guest.call("multi_init", (n << 4) | 9),
        guest.call("multi_init_ref", (n << 4) | 9),
        `multi_init bit-exact mismatch at n=${n}`,
      );
      const ordered = guest.call("exact_f32_sum_order", n) as number;
      ok(
        ordered !== 0xdeadbeef,
        `F32 left-to-right sum order diverged at n=${n}`,
      );
    }
    strictEqual(guest.call("f32_sum_nan_canon", 20), 0x7fc00000);
    throws(() => guest.call("f32_sum_oob", 16));
  });
});

Deno.test("Tier 7D: 2x byte-pointer branchless merge handles odd tails and sort parity", async () => {
  const source = `
func merge_u32 (src: #[U32]) -> (dst: own #[U32]) -> (lo: U32) -> (mid: U32) -> (hi: U32): #[U32] =>
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

io sort_u32_hash (packed: U32): U32 =>
  let n = packed >> 8
  let seed = packed & 255
  let a = @array.fill n 0
  let b = @array.fill n 0
  let s = seed | 1
  for i in 0 .. n:
    s := self * 1664525 + 1013904223
    a[i] := s
  let width: U32 = 1
  let in_b = false
  for ever:
    if width >= n:
      break
    let lo: U32 = 0
    let step = width << 1
    for ever:
      if lo >= n:
        break
      let mid = if lo + width > n then n else lo + width
      let hi = if lo + step > n then n else lo + step
      b := merge_u32 a self lo mid hi
      lo := self + step
    width := self << 1
    if width >= n:
      in_b := true
      break
    let lo2: U32 = 0
    let step2 = width << 1
    for ever:
      if lo2 >= n:
        break
      let mid2 = if lo2 + width > n then n else lo2 + width
      let hi2 = if lo2 + step2 > n then n else lo2 + step2
      a := merge_u32 b self lo2 mid2 hi2
      lo2 := self + step2
    width := self << 1
  let sorted = if in_b then b else a
  let hash: U32 = 0
  for i in 0 .. n:
    if i > 0 and sorted[i] < sorted[i - 1]:
      return 0xdeadbeef
    hash := (self * 31) ^ sorted[i]
  return hash
`;
  await withModule("blot_tier7d_", source, (guest) => {
    for (const n of [0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 63, 64, 129]) {
      const res = guest.call("sort_u32_hash", (n << 8) | 42) as number;
      ok(res !== 0xdeadbeef, `Tier 7D merge sort unsorted for n=${n}`);
    }
  });
});

Deno.test("Tier 7E: Zero-spill 4x-k matmul with v128.load32_splat matches scalar reference", async () => {
  const source = `
import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

io check_matmul (packed: U32): U32 =>
  let rows = (packed >> 16) & 255
  let n = (packed >> 8) & 255
  let m = packed & 255
  let a = @array.fill (rows * n) 0.0
  let b = @array.fill (n * m) 0.0
  let c1 = @array.fill (rows * m) 0.0
  let c2 = @array.fill (rows * m) 0.0
  let s: U32 = 12345
  for i in 0 .. (rows * n):
    s := self * 1664525 + 1013904223
    a[i] := U32.to_f32 (s & 127) * 0.0625
  for i in 0 .. (n * m):
    s := self * 1664525 + 1013904223
    b[i] := U32.to_f32 (s & 127) * 0.0625
  for row in 0 .. rows:
    let ro = row * n
    let co = row * m
    for k in 0 .. n:
      let aik = a[ro + k]
      let ko = k * m
      for col in 0 .. m:
        let dst = co + col
        c1[dst] := c1[dst] + aik * b[ko + col]
  let r: U32 = 0
  for ever:
    if r >= rows:
      break
    let k: U32 = 0
    for ever:
      if k >= n:
        break
      let aik = a[r * n + k]
      let col: U32 = 0
      for ever:
        if col >= m:
          break
        let dst = r * m + col
        c2[dst] := c2[dst] + aik * b[k * m + col]
        col := self + 1
      k := self + 1
    r := self + 1
  for i in 0 .. (rows * m):
    if f32_bits c1[i] != f32_bits c2[i]:
      return 0xdeadbeef
  return 1
`;
  await withModule("blot_tier7e_", source, (guest, bytes) => {
    ok(
      hasSubOpcode(bytes, 0xfd, 9),
      "expected v128.load32_splat (0xfd 0x09) in 4x-k matmul",
    );
    for (
      const [rows, n, m] of [
        [4, 1, 8],
        [4, 2, 8],
        [4, 3, 8],
        [4, 4, 8],
        [4, 5, 11],
        [6, 7, 16],
        [8, 16, 16],
      ]
    ) {
      strictEqual(
        guest.call("check_matmul", (rows << 16) | (n << 8) | m),
        1,
        `Tier 7E matmul mismatch for ${rows}x${n}x${m}`,
      );
    }
  });
});
