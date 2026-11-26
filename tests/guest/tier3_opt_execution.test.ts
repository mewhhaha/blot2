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

Deno.test("Tier 3A: 4x unrolled 16-element v128 SIMD across tails, offsets, Bool masks, and overlaps", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-tier3a-simd-" });
  const entry = `${dir}/main.blot`;
  const src = `// 1. 4x unrolled spark F32 with in-place reuse and duplicate stream
io spark_f32_unroll (n: U32): #[F32] =>
  let px = @array.fill n 0.0
  let vx = @array.fill n 0.0
  for i in 0 .. n:
    px[i] := U32.to_f32 (i + 1) * 0.5
    vx[i] := U32.to_f32 ((i & 7) + 1) * 0.25
  for _ in 0 .. 3:
    px := spark #[px[i] + vx[i] * 2.0 + px[i] * 0.0 | i <- 0 .. n]
  return px

// 2. 4x unrolled spark Bool mask load/store across arbitrary counts
io spark_bool_unroll (n: U32): #[U32] =>
  let a = @array.fill n 0
  let b = @array.fill n 0
  for i in 0 .. n:
    a[i] := i % 5
    b[i] := (i * 3) % 5
  let mask = spark #[a[i] >= b[i] | i <- 0 .. n]
  let out = @array.fill n 0
  for i in 0 .. n:
    if mask[i]:
      out[i] := 1
  return out

// 3. 4x unrolled in-place for-loop SAXPY with affine offsets
io for_saxpy_unroll (n: U32): #[F32] =>
  let total = n * 2
  let c = @array.fill total 2.0
  let b = @array.fill total 0.0
  for i in 0 .. total:
    b[i] := U32.to_f32 (i + 1) * 0.5
  let row_off = n
  let k_off: U32 = 0
  for col in 0 .. n:
    let dst = row_off + col
    c[dst] := c[dst] + 3.0 * b[k_off + col]
  return c

// 4. Loop-carried forward overlap across >16 elements must still fall back to scalar
io overlap_large_fallback (n: U32): #[U32] =>
  let a = @array.fill n 0
  if n > 0:
    a[0] := 7
  for i in 0 .. (if n > 0 then n - 1 else 0):
    a[i + 1] := a[i] + 3
  return a
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
      ok(
        built.bytes.includes(0xfd),
        "Expected Wasm SIMD 0xfd opcodes in Tier 3A module",
      );
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const n of [0, 1, 3, 4, 15, 16, 17, 31, 32, 35, 64]) {
          const gotF = Array.from(
            guest.call("spark_f32_unroll", n) as Float32Array,
          );
          const expF: number[] = [];
          for (let i = 0; i < n; i++) {
            let p = Math.fround((i + 1) * 0.5);
            const v = Math.fround(((i & 7) + 1) * 0.25);
            for (let s = 0; s < 3; s++) {
              p = Math.fround(
                Math.fround(p + Math.fround(v * 2.0)) + Math.fround(p * 0.0),
              );
            }
            expF.push(p);
          }
          deepStrictEqual(gotF, expF, `spark_f32_unroll n=${n}`);

          const gotB = asWords(guest.call("spark_bool_unroll", n));
          const expB = Array.from({ length: n }, (_, i) =>
            (i % 5) >= ((i * 3) % 5) ? 1 : 0
          );
          deepStrictEqual(gotB, expB, `spark_bool_unroll n=${n}`);

          const gotS = Array.from(
            guest.call("for_saxpy_unroll", n) as Float32Array,
          );
          const expS: number[] = [];
          for (let i = 0; i < n; i++) expS.push(2.0);
          for (let col = 0; col < n; col++) {
            expS.push(Math.fround(2.0 + Math.fround(3.0 * Math.fround((col + 1) * 0.5))));
          }
          deepStrictEqual(gotS, expS, `for_saxpy_unroll n=${n}`);

          const gotO = asWords(guest.call("overlap_large_fallback", n));
          const expO = Array.from({ length: n }, (_, i) => (7 + i * 3) >>> 0);
          deepStrictEqual(gotO, expO, `overlap_large_fallback n=${n}`);
        }
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

Deno.test("Tier 3B & 3C: if-to-select, branch/short-circuit bounds, selective invalidation, value reuse, and expanded inlining", async () => {
  await compileAndRun(
    `type Counter is data = $Counter { rev: U32, count: U32 }

func bump_counter (c: Counter): Counter =>
  let $Counter { rev, count } = c
  return $Counter { rev: rev + 1, count: count + 1 }

func small_sum_loop (arr: #[U32]) -> (n: U32): U32 =>
  let acc: U32 = 0
  for i in 0 .. n:
    acc := self + arr[i]
  return acc

// 3B: branchless if-to-select carry updates (U32, F32, Bool) + cross-loop CheckedArray
io branchless_carries (n: U32): U32 =>
  let flags = @array.fill n false
  for i in 0 .. n:
    flags[i] := (i % 3) != 0
  let count: U32 = 0
  let sum: U32 = 0
  let fsum = 0.0
  let parity = false
  for i in 0 .. n:
    if flags[i]:
      count := self + 1
      sum := self + i
      fsum := self + 0.5
      parity := Bool.not self
  let pbit: U32 = if parity then 1 else 0
  return (sum ^ (count * 31) ^ F32.to_u32 (fsum * 10.0)) + pbit

// 3B: if-branch bounds (idx < len, idx >= len else, logical and/or, compound or early exit)
io branch_bounds_checks (n: U32): U32 =>
  let xs = @array.fill n 0
  for i in 0 .. n:
    xs[i] := i * 7 + 3
  let acc: U32 = 0
  for i in 0 .. (n + 4):
    if i < xs.length and xs[i] > 10:
      acc := self + xs[i]
    if i >= xs.length:
      acc := self + 1
    else:
      acc := self + xs[i]
  // Compound 'or' early exit guard
  let a: U32 = 0
  let b: U32 = 0
  let lim = xs.length
  for ever:
    if a >= lim or b >= lim:
      break
    if xs[a] <= xs[b]:
      acc := self + xs[a]
      a := self + 1
    else:
      acc := self + xs[b]
      b := self + 1
  return acc

// 3C: selective invalidation on push/pop/truncate while reading another array,
// plus OOB trap preservation after pop/truncate!
io selective_invalidation (n: U32): U32 =>
  let src = @array.fill n 0
  for i in 0 .. n:
    src[i] := i + 10
  let dst: #[U32] = #[]
  let meta = $Counter { rev: 0, count: 0 }
  for i in 0 .. n:
    @storage.push dst (src[i] * 2)
    meta := bump_counter self
  if dst.length > 2:
    let _ = @storage.pop dst
    @storage.truncate dst (dst.length - 1)
  let $Counter { rev, count } = meta
  return small_sum_loop dst dst.length + rev + count

io truncated_oob_trap (n: U32): U32 =>
  let arr = @array.fill n 5
  let last = arr.length - 1
  let _ = arr[last]
  @storage.truncate arr (n - 2)
  // Must NOT reuse stale CheckedArray length or CheckedElem!
  return arr[last]

// 3C: CheckedElem value cache MUST be invalidated by indexedUpdate and by calls
func mutate_slot (xs: own #[U32]) -> (idx: U32) -> (v: U32): #[U32] =>
  xs[idx] := v
  return xs

io elem_cache_invalidation (n: U32): U32 =>
  let xs = @array.fill n 10
  let before = xs[2]
  xs[2] := 99
  let after_write = xs[2]
  // Reuse across both then & else branches of an if condition
  let pick: U32 = 0
  if xs[1] <= xs[2]:
    pick := xs[1] + xs[2]
  else:
    pick := xs[2] + xs[1]
  // Ensure else-branch reuse also works when condition is false
  let pick2: U32 = 0
  if xs[2] <= xs[1]:
    pick2 := xs[2]
  else:
    pick2 := xs[1] + 500
  xs := mutate_slot self 2 777
  let after_call = xs[2]
  return before + after_write + pick + pick2 + after_call

// 3C regression (GOAP shape): pre-loop array updated in-place AND pushed inside nested loop/if
io nested_update_and_push (max_steps: U32): U32 =>
  let vals: #[U32] = #[10]
  let closed: #[Bool] = #[false]
  let stop = false
  for _ in 0 .. max_steps:
    if not stop:
      let pick: U32 = 999999
      for i in 0 .. vals.length:
        if not closed[i] and pick == 999999:
          pick := i
      if pick == 999999:
        stop := true
      else:
        closed[pick] := true
        for k in 0 .. 2:
          if vals.length < max_steps:
            @storage.push vals (vals[pick] + k + 1)
            @storage.push closed false
  let sum: U32 = 0
  for i in 0 .. vals.length:
    if closed[i]:
      sum := self + vals[i]
  return sum * 100 + vals.length
`,
    (guest) => {
      // 3B branchless_carries: n = 10 -> flags true for 1,2,4,5,7,8 (6 items)
      // count=6, sum=27, fsum=3.0 (*10=30), parity=false (6 flips)
      const expB = ((27 ^ (6 * 31) ^ 30) >>> 0) + 0;
      equal(guest.call("branchless_carries", 10), expB);
      equal(guest.call("branchless_carries", 0), 0);

      // 3B branch_bounds_checks: n = 5 -> xs = [3, 10, 17, 24, 31]
      // loop i=0..8:
      //   i<5 and xs[i]>10: 17+24+31 = 72
      //   else (i<5): 3+10+17+24+31 = 85; i>=5 (4 iters): +4
      // compound or loop: a=0..4, b=0 -> xs[a]<=xs[0] only at a=0 (3), then a=1..4 > xs[0]=3 -> b increments 0->1->2->3->4->5
      // trace: (a=0,b=0): 3<=3 -> +3, a=1; (1,0): 10>3 -> +3, b=1; (1,1): 10<=10 -> +10, a=2; (2,1): 17>10 -> +10, b=2;
      //        (2,2): +17, a=3; (3,2): +17, b=3; (3,3): +24, a=4; (4,3): +24, b=4; (4,4): +31, a=5 -> break!
      //        compound sum = 3+3+10+10+17+17+24+24+31 = 139
      // total = 72 + 85 + 4 + 139 = 300
      equal(guest.call("branch_bounds_checks", 5), 300);

      // 3C selective_invalidation: n=6 -> dst pushed [20,22,24,26,28,30], pop+truncate -> [20,22,24,26] (sum 92) + rev 6 + count 6 = 104
      equal(guest.call("selective_invalidation", 6), 104);
      throws(() => guest.call("truncated_oob_trap", 5));

      // 3C elem_cache_invalidation: before=10, after_write=99, pick=10+99=109, pick2=10+500=510, after_call=777 => 1505
      equal(guest.call("elem_cache_invalidation", 5), 1505);

      // 3C GOAP-shape nested update + push: max_steps=5 -> vals=[10, 11, 12, 12, 13], all 5 closed (sum 58), len 5 => 5805
      equal(guest.call("nested_update_and_push", 5), 5805);
    },
    { stdRoot },
  );
});

Deno.test("Tier 3D: 4x algebraic parallel-power affine LCG unrolling exactness across counts and non-zero starts", async () => {
  await compileAndRun(
    `io lcg_n (n: U32): U32 =>
  let state: U32 = 43
  let acc: U32 = 0
  for _ in 0 .. n:
    state := self * 1664525 + 1013904223
    acc := self ^ (state >> 16)
  return acc

io lcg_range (packed: U32): U32 =>
  let start = packed >> 16
  let end = packed & 65535
  let state: U32 = 99
  let acc: U32 = 0
  for i in start .. end:
    state := self * 1664525 + 1013904223
    acc := (self + (state >> 16)) ^ i
  return acc
`,
    (guest) => {
      const refLcg = (n: number): number => {
        let state = 43 >>> 0;
        let acc = 0 >>> 0;
        for (let i = 0; i < n; i++) {
          state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
          acc = (acc ^ (state >>> 16)) >>> 0;
        }
        return acc >>> 0;
      };
      for (const n of [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 100, 10003]) {
        equal(guest.call("lcg_n", n), refLcg(n));
      }

      const refRange = (start: number, end: number): number => {
        let state = 99 >>> 0;
        let acc = 0 >>> 0;
        for (let i = start; i < end; i++) {
          state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
          acc = (((acc + (state >>> 16)) >>> 0) ^ i) >>> 0;
        }
        return acc >>> 0;
      };
      for (
        const [s, e] of [[0, 0], [5, 3], [5, 5], [2, 3], [2, 6], [2, 9], [
          7,
          25,
        ]]
      ) {
        equal(guest.call("lcg_range", ((s << 16) | e) >>> 0), refRange(s, e));
      }
    },
    { stdRoot },
  );
});

Deno.test("Tier 3E: bounded finite F32 NaN canon elision preserves 0x7fc00000 on adversarial NaNs + lazy variant payload load", async () => {
  await compileAndRun(
    `type Vec3 is data = $Vec3 { x: F32, y: F32, z: F32 }

io finite_f32_math (n: U32): #[F32] =>
  let f = U32.to_f32 (n & 1023)
  let a = f * 0.25
  let b = f * 0.5 + 1.0
  let c = b - a
  // Adversarial values that CAN produce NaN MUST STILL canonicalize to 0x7fc00000!
  let zero = U32.to_f32 (n & 0)
  let inf = 1.0 / zero
  let nan_sub = inf - inf
  let nan_mul = zero * inf
  let big = 1.0e25 * 1.0e25
  let nan_big = big - big
  let nan_div = zero / zero
  return #[a, b, c, nan_sub, nan_mul, nan_big, nan_div]

// Lazy variant payload load: tag checked before loading payload words; wildcard skips payload; OOB still traps
io lazy_variant_scan (n: U32): U32 =>
  let pool: #[Maybe Vec3] = @array.fill n $Nothing
  for i in 0 .. n:
    if (i % 4) == 0:
      let f = U32.to_f32 (i + 1)
      pool[i] := $Some ($Vec3 { x: f, y: f * 2.0, z: f * 3.0 })
  let sum = 0.0
  let present: U32 = 0
  for i in 0 .. n:
    if let $Some ($Vec3 { x, y, z }) = pool[i]:
      sum := self + x + y + z
    present := self + (case pool[i] of
      $Some _ => 1
      $Nothing => 0)
  return F32.to_u32 sum * 100 + present

io lazy_variant_oob (n: U32): U32 =>
  let pool: #[Maybe Vec3] = @array.fill n $Nothing
  if let $Some ($Vec3 { x, y, z }) = pool[n]:
    return F32.to_u32 (x + y + z)
  return 0
`,
    (guest) => {
      const words = asWords(guest.call("finite_f32_math", 12));
      const f32 = new Float32Array(new Uint32Array(words).buffer);
      equal(f32[0], 3.0);
      equal(f32[1], 7.0);
      equal(f32[2], 4.0);
      equal(words[3], 0x7fc00000);
      equal(words[4], 0x7fc00000);
      equal(words[5], 0x7fc00000);
      equal(words[6], 0x7fc00000);

      // n=10: present at i=0,4,8 -> f=1,5,9 -> sum(6*f) = 6*(1+5+9)=90, present=3 => 9003
      equal(guest.call("lazy_variant_scan", 10), 9003);
      equal(guest.call("lazy_variant_scan", 0), 0);
      throws(() => guest.call("lazy_variant_oob", 4));
    },
    { stdRoot },
  );
});

Deno.test("Tier 3F: zero-allocation fast-path commit for boxed and unboxed persistent processes + slow-path fallback", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-tier3f-persist-" });
  const entry = `${dir}/main.blot`;
  const src = `// 1. Unboxed persistent process (register-carried plain-element arrays + scalar field)
type UnboxedState is data = $UnboxedState { xs: #[U32], ys: #[U32], ticks: U32 }

func init_unboxed (n: U32): UnboxedState =>
  let xs = @array.fill n 1
  let ys = @array.fill n 2
  return $UnboxedState { xs, ys, ticks: 0 }

func step_unboxed (st: own UnboxedState) -> (cmd: U32): (UnboxedState, U32) =>
  let $UnboxedState { xs, ys, ticks } = st
  if cmd == 1:
    // Fast-path: in-place mutation + scalar field update (same array handles)
    for i in 0 .. xs.length:
      xs[i] := self + ys[i]
    ticks := self + 1
  if cmd == 2:
    // Fast-path with in-place growth via @storage.push (same handle slot/gen)
    @storage.push xs 100
    ticks := self + 1
  if cmd == 3:
    // Slow-path fallback: replace xs with a brand-new temporary array!
    let fresh = @array.fill (xs.length + 1) 7
    xs := fresh
    ticks := self + 10
  let sum: U32 = 0
  for i in 0 .. xs.length:
    sum := self + xs[i]
  return ($UnboxedState { xs, ys, ticks }, sum * 100 + ticks)

#process const unboxed_proc: Process [U32, U32, U32] = { init: init_unboxed, step: step_unboxed }

// 2. Boxed persistent process (>register limit, many fields + arrays + scalar rev)
type BoxedState is data = $BoxedState {
  a: #[U32], b: #[U32], c: #[U32], d: #[U32],
  e: #[U32], f: #[U32], g: #[U32], h: #[U32],
  rev: U32,
  extra: U32,
}

func init_boxed (n: U32): BoxedState =>
  return $BoxedState {
    a: @array.fill n 1, b: @array.fill n 2, c: @array.fill n 3, d: @array.fill n 4,
    e: @array.fill n 5, f: @array.fill n 6, g: @array.fill n 7, h: @array.fill n 8,
    rev: 0, extra: 10,
  }

func step_boxed (st: own BoxedState) -> (cmd: U32): (BoxedState, U32) =>
  let $BoxedState { a, b, c, d, e, f, g, h, rev, extra } = st
  if cmd == 1:
    // Fast-path: mutate a in-place + bump scalar rev/extra
    for i in 0 .. a.length:
      a[i] := self + b[i]
    rev := self + 1
    extra := self + 5
  if cmd == 2:
    // Fast-path with temporary snapshot allocation (released by releaseEntry)
    let tmp = @storage.copy a
    let tsum: U32 = 0
    for i in 0 .. tmp.length:
      tsum := self + tmp[i]
    rev := self + tsum
  if cmd == 3:
    // Slow-path fallback: replace array handle a with freshly allocated array
    a := @array.fill (a.length + 2) 9
    rev := self + 100
  let sum: U32 = 0
  for i in 0 .. a.length:
    sum := self + a[i]
  return ($BoxedState { a, b, c, d, e, f, g, h, rev, extra }, sum * 1000 + rev + extra)

#process const boxed_proc: Process [U32, U32, U32] = { init: init_boxed, step: step_boxed }
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
      const { instance } = await WebAssembly.instantiate(built.bytes, {});
      const exports = instance.exports as Record<
        string,
        (...args: number[]) => number
      >;

      // Exercise UnboxedState: init(4) -> xs=[1,1,1,1], ys=[2,2,2,2], ticks=0
      equal(exports["blot:proc_init:unboxed_proc"](4), 0);
      // cmd=1 (fast-path): xs=[3,3,3,3] (sum=12), ticks=1 => 1201
      equal(exports["blot:proc_step:unboxed_proc"](1), 1201);
      // cmd=1 again (fast-path persists scalar+array): xs=[5,5,5,5] (sum=20), ticks=2 => 2002
      equal(exports["blot:proc_step:unboxed_proc"](1), 2002);
      // cmd=2 (fast-path with persistent push growth): xs=[5,5,5,5,100] (sum=120), ticks=3 => 12003
      equal(exports["blot:proc_step:unboxed_proc"](2), 12003);
      // cmd=3 (slow-path fallback replaces xs): xs=[7,7,7,7,7,7] (sum=42), ticks=13 => 4213
      equal(exports["blot:proc_step:unboxed_proc"](3), 4213);
      // cmd=1 after slow-path (fast-path resumes on new committed handle!): xs=[9,9,9,9,7,7] wait ys.len=4 -> OOB? No, loop 0..xs.length reads ys[i]!
      // Test cmd=2 (push on new committed handle): xs=[7,7,7,7,7,7,100] (sum=142), ticks=14 => 14214
      equal(exports["blot:proc_step:unboxed_proc"](2), 14214);

      // Exercise BoxedState: init(3) -> a=[1,1,1], b=[2,2,2], rev=0, extra=10
      equal(exports["blot:proc_init:boxed_proc"](3), 0);
      // cmd=1 (fast-path boxed): a=[3,3,3] (sum=9), rev=1, extra=15 => 9016
      equal(exports["blot:proc_step:boxed_proc"](1), 9016);
      // cmd=2 (fast-path boxed with temp snapshot copy): sum=9, rev=10, extra=15 => 9025
      equal(exports["blot:proc_step:boxed_proc"](2), 9025);
      // cmd=3 (slow-path boxed replaces a): a=[9,9,9,9,9] (sum=45), rev=110, extra=15 => 45125
      equal(exports["blot:proc_step:boxed_proc"](3), 45125);
      // cmd=2 again after slow-path (fast-path boxed resumes on new committed handle!): sum=45, rev=155, extra=15 => 45170
      equal(exports["blot:proc_step:boxed_proc"](2), 45170);
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
