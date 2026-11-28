import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

async function compileAndRun(
  source: string,
  run: (guest: Awaited<ReturnType<typeof instantiateGuest>>) => void | Promise<void>,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "squid-batch6-" });
  const entry = `${dir}/main.sq`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    stdRoot,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    assert(WebAssembly.validate(built.bytes), "Invalid Wasm bytes");
    const guest = await instantiateGuest(built.bytes);
    try {
      await run(guest);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Batch 6 Opt 1: loop-invariant U64 reciprocal div/rem edge cases & zero trap", async () => {
  await compileAndRun(
    `
func div_rem_loop (vals: #[U64]) -> (d: U64): #[U64] =>
  let out: #[U64] = #[]
  for i in 0 .. vals.length:
    let x = vals[i]
    out := self.push (x / d)
    out := self.push (x % d)
  return out

func div_rem_u32_loop (vals: #[U64]) -> (d32: U32): #[U64] =>
  let d = d32.to_u64
  let out: #[U64] = #[]
  for i in 0 .. vals.length:
    let x = vals[i]
    out := self.push (x / d)
    out := self.push (x % d)
  return out

io run_u64 (args: #[U32]): #[U32] =>
  let d = args[0].to_u64 | (args[1].to_u64 << 32u64)
  let vals: #[U64] = #[
    0u64,
    1u64,
    2u64,
    3u64,
    0x7fff_ffff_ffff_ffffu64,
    0x8000_0000_0000_0000u64,
    0x8000_0000_0000_0001u64,
    0xffff_ffff_ffff_fffeu64,
    0xffff_ffff_ffff_ffffu64,
    0x1234_5678_9abc_def0u64,
  ]
  let res = div_rem_loop vals d
  let out: #[U32] = #[]
  for i in 0 .. res.length:
    let v = res[i]
    out := self.push v.to_u32
    out := self.push (v >> 32u64).to_u32
  return out

io run_u32 (d32: U32): #[U32] =>
  let vals: #[U64] = #[
    0u64,
    1u64,
    0x7fff_ffff_ffff_ffffu64,
    0x8000_0000_0000_0000u64,
    0xffff_ffff_ffff_ffffu64,
    0xfedc_ba98_7654_3210u64,
  ]
  let res = div_rem_u32_loop vals d32
  let out: #[U32] = #[]
  for i in 0 .. res.length:
    let v = res[i]
    out := self.push v.to_u32
    out := self.push (v >> 32u64).to_u32
  return out
`,
    (guest) => {
      const vals = [
        0n,
        1n,
        2n,
        3n,
        0x7fff_ffff_ffff_ffffn,
        0x8000_0000_0000_0000n,
        0x8000_0000_0000_0001n,
        0xffff_ffff_ffff_fffen,
        0xffff_ffff_ffff_ffffn,
        0x1234_5678_9abc_def0n,
      ];
      const divisors = [
        1n,
        2n,
        3n,
        4n,
        7n,
        10n,
        16n,
        1000003n,
        0x8000_0000n,
        0x8000_0001n,
        0x7fff_ffff_ffff_ffffn,
        0x8000_0000_0000_0000n,
        0x8000_0000_0000_0001n,
        0xffff_ffff_ffff_fffen,
        0xffff_ffff_ffff_ffffn,
      ];
      for (const d of divisors) {
        const lo = Number(d & 0xffff_ffffn);
        const hi = Number((d >> 32n) & 0xffff_ffffn);
        const words = guest.call("run_u64", new Uint32Array([lo, hi])) as Uint32Array;
        assert.equal(words.length, vals.length * 4);
        for (let i = 0; i < vals.length; i++) {
          const q = BigInt(words[i * 4]) | (BigInt(words[i * 4 + 1]) << 32n);
          const r = BigInt(words[i * 4 + 2]) | (BigInt(words[i * 4 + 3]) << 32n);
          assert.equal(q, vals[i] / d, `q mismatch for ${vals[i]} / ${d}`);
          assert.equal(r, vals[i] % d, `r mismatch for ${vals[i]} % ${d}`);
        }
      }
      // d == 0 MUST trap!
      assert.throws(() => guest.call("run_u64", new Uint32Array([0, 0])));

      const u32Vals = [
        0n,
        1n,
        0x7fff_ffff_ffff_ffffn,
        0x8000_0000_0000_0000n,
        0xffff_ffff_ffff_ffffn,
        0xfedc_ba98_7654_3210n,
      ];
      for (const d32 of [1, 2, 3, 13, 256, 200016, 0x80000000, 0xffffffff]) {
        const words = guest.call("run_u32", d32) as Uint32Array;
        const d = BigInt(d32 >>> 0);
        for (let i = 0; i < u32Vals.length; i++) {
          const q = BigInt(words[i * 4]) | (BigInt(words[i * 4 + 1]) << 32n);
          const r = BigInt(words[i * 4 + 2]) | (BigInt(words[i * 4 + 3]) << 32n);
          assert.equal(q, u32Vals[i] / d);
          assert.equal(r, u32Vals[i] % d);
        }
      }
      assert.throws(() => guest.call("run_u32", 0));
    },
  );
});

Deno.test("Batch 6 Opt 2+4a: CheckedSimdWindow & Mode-2 SIMD store worker exactness + OOB/wrap traps", async () => {
  await compileAndRun(
    `
import * as simd from "std/simd"

func stencil_pass (src: #[U8]) -> (dst: own #[U8]) -> (w: U32): #[U8] =>
  let wm1 = w - 1
  for y in 1 .. wm1:
    let row = y * w
    let up = row - w
    let dn = row + w
    let x: U32 = 1
    for ever:
      if x + 17 > w:
        break
      let u0 = simd.load_u8x16 (up + x - 1) src
      let m1 = simd.load_u8x16 (row + x) src
      let d2 = simd.load_u8x16 (dn + x + 1) src
      let s = simd.u8_add (simd.u8_add u0 m1) d2
      dst := simd.store_u8x16 (row + x) s self
      x := self + 16
    for tx in x .. wm1:
      dst[row + tx] := ((src[up + tx - 1].to_u32 + src[row + tx].to_u32 + src[dn + tx + 1].to_u32) & 255).to_u8
  return dst

io run_stencil (args: #[U32]): U32 =>
  let w = args[0]
  let src_len = args[1]
  let dst_len = args[2]
  let src = @array.fill src_len 0u8
  for i in 0 .. src_len:
    src[i] := ((i * 37 + 11) & 63).to_u8
  let dst = @array.fill dst_len 0u8
  let out = stencil_pass src dst w
  let acc: U32 = 0
  for i in 0 .. out.length:
    acc := self * 31 + out[i].to_u32
  return acc
`,
    (guest) => {
      const refStencil = (w: number): number => {
        const n = w * w;
        const src = new Uint8Array(n);
        for (let i = 0; i < n; i++) src[i] = (i * 37 + 11) & 63;
        const dst = new Uint8Array(n);
        for (let y = 1; y < w - 1; y++) {
          const row = y * w;
          const up = row - w;
          const dn = row + w;
          for (let x = 1; x < w - 1; x++) {
            dst[row + x] = (src[up + x - 1] + src[row + x] + src[dn + x + 1]) & 255;
          }
        }
        let acc = 0;
        for (let i = 0; i < n; i++) acc = (Math.imul(acc, 31) + dst[i]) >>> 0;
        return acc;
      };
      // 0-iter SIMD (w=4, w=17), exact-fit (w=18, w=34), non-multiple (w=37, w=64)
      for (const w of [4, 17, 18, 34, 37, 64]) {
        assert.equal(guest.call("run_stencil", new Uint32Array([w, w * w, w * w])), refStencil(w));
      }
      // OOB src (last read at row 33 * 34 + 33 = 1155) and OOB dst (last write at row 32 * 34 + 32 = 1120) MUST trap!
      assert.throws(() => guest.call("run_stencil", new Uint32Array([34, 34 * 34 - 1, 34 * 34])));
      assert.throws(() => guest.call("run_stencil", new Uint32Array([34, 34 * 34, 32 * 34 + 32])));
    },
  );
});

Deno.test("Batch 6 Opt 4b: overlapping v128 range-copy, ForeverEqBoundLoop, 0<len BCE & RMW", async () => {
  await compileAndRun(
    `
io test_copy (args: #[U32]): U32 =>
  let n = args[0]
  let dst_len = args[1]
  let src_len = args[2]
  let src = @array.fill src_len 0
  let dst = @array.fill dst_len 0
  for i in 0 .. src_len:
    src[i] := i * 17 + 3
  for i in 0 .. n:
    dst[i] := src[i]
  // Self-copy must also work identically.
  for i in 0 .. n:
    dst[i] := dst[i]
  let h: U32 = 0
  for i in 0 .. dst.length:
    h := self * 131 + dst[i]
  return h

io test_eq_bound (args: #[U32]): #[U32] =>
  let n = args[0]
  let r0 = args[1]
  let arr_len = args[2]
  let perm = @array.fill arr_len 0
  let cnt = @array.fill arr_len 2
  for i in 0 .. arr_len:
    perm[i] := i + 10
  let r = r0
  let done = false
  for ever:
    if r == n:
      done := true
      break
    let p0 = perm[0]
    let i: U32 = 0
    for ever:
      if i >= r:
        break
      perm[i] := perm[i + 1]
      i := self + 1
    perm[r] := p0
    cnt[r] := self - 1
    if cnt[r] > 0:
      break
    r := self + 1
  let sum: U32 = if done then 1000 else 0
  for i in 0 .. perm.length:
    sum := self + perm[i] * (i + 1) + cnt[i]
  return #[r, sum]
`,
    (guest) => {
      // Test every copy length boundary: 0..17, 31, 32, 65
      for (const n of [0, 1, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15, 16, 17, 31, 32, 65]) {
        const len = n + 3;
        let expected = 0;
        for (let i = 0; i < len; i++) {
          const v = i < n ? ((i * 17 + 3) >>> 0) : 0;
          expected = (Math.imul(expected, 131) + v) >>> 0;
        }
        assert.equal(guest.call("test_copy", new Uint32Array([n, len, len])), expected, `copy failed for n=${n}`);
      }
      // OOB copy MUST trap!
      assert.throws(() => guest.call("test_copy", new Uint32Array([11, 10, 11])));
      assert.throws(() => guest.call("test_copy", new Uint32Array([11, 11, 10])));

      // ForeverEqBoundLoop: normal r0=1, n=5 -> perm rotates [10,11,12,13,14] -> [11,10,12,13,14], cnt[1]=1 > 0 -> breaks at r=1!
      const ok1 = guest.call("test_eq_bound", new Uint32Array([5, 1, 5])) as Uint32Array;
      assert.equal(ok1[0], 1);
      // Expected perm=[11,10,12,13,14], cnt=[2,1,2,2,2]
      const expSum = 11 * 1 + 2 + 10 * 2 + 1 + 12 * 3 + 2 + 13 * 4 + 2 + 14 * 5 + 2;
      assert.equal(ok1[1], expSum);

      // OOB when n > arr_len and r0 == 4 (reaches perm[4] on arr_len=4) MUST trap cleanly!
      assert.throws(() => guest.call("test_eq_bound", new Uint32Array([6, 4, 4])));
      // Fallback when r0 > n (e.g. r0=4, n=3, arr_len=4): r != n -> tries perm[4] -> traps!
      assert.throws(() => guest.call("test_eq_bound", new Uint32Array([3, 4, 4])));
    },
  );
});

Deno.test("Batch 6 Opt 3: ~[U32] SIMD reverse bulk push_front, zero-alloc pop_front, and CoW isolation", async () => {
  await compileAndRun(
    `
io test_seq_front (n: U32): #[U32] =>
  let s: ~[U32] = ~[]
  for i in 0 .. n:
    s := self.push_front (i * 3 + 7)
  // Take CoW snapshot before draining!
  let snap = s.copy
  let drain_sum: U32 = 0
  for k in 0 .. n:
    let (s2, v) = s.pop_front
    s := s2
    // Expected LIFO order: (n - 1 - k) * 3 + 7
    let exp = (n - 1 - k) * 3 + 7
    if v != exp:
      return #[999999, k, v, exp]
    drain_sum := self + v
  // Also test pushing onto a non-empty CoW snapshot!
  let snap2 = snap.copy
  for i in 0 .. 300:
    snap2 := self.push_front (100000 + i)
  let orig_first: U32 = if snap.length > 0 then snap[0] else 0
  let orig_last: U32 = if snap.length > 0 then snap[snap.length - 1] else 0
  return #[s.length, snap.length, snap2.length, orig_first, orig_last, drain_sum]
`,
    (guest) => {
      for (const n of [0, 1, 7, 255, 256, 257, 512, 1000, 5000]) {
        const res = guest.call("test_seq_front", n) as Uint32Array;
        assert.equal(res[0], 0, `drained len for n=${n}`);
        assert.equal(res[1], n, `snapshot len for n=${n}`);
        assert.equal(res[2], n + 300, `snap2 len for n=${n}`);
        const expFirst = n > 0 ? ((n - 1) * 3 + 7) >>> 0 : 0;
        const expLast = n > 0 ? 7 : 0;
        assert.equal(res[3], expFirst, `orig_first for n=${n}`);
        assert.equal(res[4], expLast, `orig_last for n=${n}`);
        let expSum = 0;
        for (let i = 0; i < n; i++) expSum = (expSum + i * 3 + 7) >>> 0;
        assert.equal(res[5], expSum, `drain_sum for n=${n}`);
      }
    },
  );
});

Deno.test("Batch 6 Opt 6: gated >= 8 MiB in-place tail extend via r.push and Mode-3 push_entry", async () => {
  await compileAndRun(
    `
func push_worker (dst: own #[U32]) -> (count: U32): #[U32] =>
  for i in 0 .. count:
    dst := self.push (i ^ 0x55aa)
  return dst

io test_large_tail_extend (_: Unit): #[U32] =>
  // Initial 2,097,152 * 4B = 8 MiB block at arena_top -> grows 8 MiB -> 16 MiB in place!
  let a: #[U32] = Array.with_capacity 2097152
  a := push_worker self 2200000
  return #[a.length, a[0], a[2097151], a[2097152], a[2199999]]
`,
    (guest) => {
      const res = guest.call("test_large_tail_extend", null) as Uint32Array;
      assert.deepEqual(Array.from(res), [
        2200000,
        0 ^ 0x55aa,
        2097151 ^ 0x55aa,
        2097152 ^ 0x55aa,
        2199999 ^ 0x55aa,
      ]);
    },
  );
});

Deno.test("Batch 6 Opt 5 soundness: boxed tuple return, polymorphic helper call, and closure-specialized worker guard", async () => {
  await compileAndRun(
    `
data WideBox = $WideBox {
  a: U32, b: U32, c: U32, d: U32,
  e: U32, f: U32, g: U32, h: U32,
  i: U32, j: U32, k: U32, l: U32,
  m: U32, n: U32, o: U32, p: U32,
}

func make_wide (x: U32): WideBox =>
  return $WideBox {
    a: x, b: x + 1, c: x + 2, d: x + 3,
    e: x + 4, f: x + 5, g: x + 6, h: x + 7,
    i: x + 8, j: x + 9, k: x + 10, l: x + 11,
    m: x + 12, n: x + 13, o: x + 14, p: x + 15,
  }

// 1. Boxed tuple return (> 16 words) containing an own #[U32] mutated in a loop.
func commit_wide (idx: U32) -> (box: WideBox) -> (xs: own #[U32]): (WideBox, #[U32], Bool) =>
  if idx >= xs.length:
    return (box, xs, false)
  for k in 0 .. xs.length:
    if k == idx:
      xs[k] := xs[k] + 100
  return (make_wide (box.a + 1), xs, true)

// 2. Polymorphic small helper called from a looping helper over #[U32].
func valid_span (n: U32) -> xs => n <= xs.length

func check_spans (xs: #[U32]) -> (n: U32): U32 =>
  let acc: U32 = 0
  for i in 0 .. n:
    if valid_span (i + 1) xs:
      acc := self + xs[i]
  return acc

// 3. Closure-specialized helper taking a #[U32] and a function argument.
func fold_with (f: U32 -> U32) -> (xs: #[U32]): U32 =>
  let acc: U32 = 0
  for i in 0 .. xs.length:
    acc := self + f xs[i]
  return acc

io test_worker_soundness (idx: U32): #[U32] =>
  let xs: #[U32] = #[10, 20, 30, 40]
  let (wb, xs2, ok) = commit_wide idx (make_wide 5) xs
  let span_sum = check_spans xs2 6
  let folded1 = fold_with (func v => v * 2) xs2
  let folded2 = fold_with (func v => v + 3) xs2
  return #[wb.a, wb.p, xs2[0], xs2[2], if ok then 1 else 0, span_sum, folded1, folded2]
`,
    (guest) => {
      const res = guest.call("test_worker_soundness", 2) as Uint32Array;
      // xs2 = [10, 20, 130, 40], sum = 200, folded1 = 400, folded2 = 212
      assert.deepEqual(Array.from(res), [6, 21, 10, 130, 1, 200, 400, 212]);
      const oob = guest.call("test_worker_soundness", 9) as Uint32Array;
      // xs unchanged = [10, 20, 30, 40], sum = 100, folded1 = 200, folded2 = 112
      assert.deepEqual(Array.from(oob), [5, 20, 10, 30, 0, 100, 200, 112]);
    },
  );
});
