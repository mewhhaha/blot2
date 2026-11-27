import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

async function compileAndRun(
  source: string,
  run: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array,
  ) => void | Promise<void>,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "blot-seq-" });
  const entry = `${dir}/main.blot`;
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
      await run(guest, built.bytes);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

async function expectReject(source: string, label: string): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "blot-seq-reject-" });
  const entry = `${dir}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    stdRoot,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert.equal(
      built.success,
      false,
      `Expected rejection for ${label}, but compilation succeeded`,
    );
    assert(
      built.diagnostics.length > 0,
      `Expected diagnostic for ${label}, got none`,
    );
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Seq ~[]: literals, comprehensions, spreads, contextual typing, and ~ operator coexistence", async () => {
  await compileAndRun(
    `
func (~) (a: U32) -> (b: U32): U32 => a * 100 + b
func (~~) (a: U32) -> (b: U32): U32 => a * 10 + b

func sum_seq (xs: ~[U32]): U32 =>
  let acc: U32 = 0
  for x in xs:
    acc := self + x
  return acc

func push_and_sum (xs: own ~[U32]) -> (extra: U32): U32 =>
  let out = xs.push extra
  return sum_seq out

func frozen_head (xs: *~[U32]): U32 => xs[0]
func tight_arrow (): ~[U32] =>~[7, 8, 9]

io test_syntax_and_ops (): #[U32] =>
  let empty: ~[U32] = ~[]
  let tight=~[1,2,3]
  let bytes: ~[U8] = ~[10, 20, 30]
  let bsum: U32 = 0
  for b in bytes:
    bsum := self + b.to_u32
  let arr = #[2, 4, 6, 8]
  let packed = %[3, 5, 7]
  let comp1 = ~[y | x <- arr, x > 2, let y = x * 3]
  let comp2 = ~[x + 1 | x <- tight]
  let comp3 = ~[i * i | i <- #[0, 1, 2, 3, 4]]
  let sp1 = ~[100, ...tight, 200]
  let sp2 = ~[5, ...arr, 6]
  let sp3 = ~[1, ...packed, 2]
  let op1 = 17 ~ 5
  let op2 = (~) 17 5
  let op3 = 4 ~~ 2
  let app1 = sum_seq ~[10, 20, 30]
  let app2 = push_and_sum ~[1, 2] 9
  let frz: *~[U32] = freeze ~[44, 55]
  let fh = frozen_head frz
  let ta = sum_seq (tight_arrow ())
  let empty_flag = if empty.is_empty then 1 else 0
  let tight_flag = if tight.is_empty then 1 else 0
  return #[
    empty.length,
    empty_flag,
    tight_flag,
    bsum,
    sum_seq comp1,
    sum_seq comp2,
    sum_seq comp3,
    sum_seq sp1,
    sum_seq sp2 + sum_seq sp3,
    op1,
    op2,
    op3,
    app1,
    app2,
    fh,
    ta,
  ]
`,
    (guest) => {
      const res = Array.from(
        guest.call("test_syntax_and_ops", null) as Uint32Array,
      );
      assert.deepEqual(res, [
        0, // empty.length
        1, // empty.is_empty
        0, // tight.is_empty
        60, // bsum
        54, // comp1: 12 + 18 + 24
        9, // comp2: 2 + 3 + 4
        30, // comp3: 0 + 1 + 4 + 9 + 16
        306, // sp1: 100 + 1 + 2 + 3 + 200
        49, // sp2 (31) + sp3 (18)
        1705, // 17 ~ 5
        1705, // (~) 17 5
        42, // 4 ~~ 2
        60, // app1
        12, // app2
        44, // frozen_head
        24, // tight_arrow
      ]);
    },
  );
});

Deno.test("Seq ~[]: push, pop, push_front, pop_front, insert, remove, indexing, and multi-level tree", async () => {
  await compileAndRun(
    `
type Box2 is data = $Box2 { a: U32, b: U32 }

io test_deque_and_focus (): #[U32] =>
  let s: ~[U32] = ~[]
  s := s.push 10
  s := s.push 20
  s := s.push_front 5
  s := s.push_front 1
  // s = [1, 5, 10, 20]
  s := s.insert 2 7
  // s = [1, 5, 7, 10, 20]
  s := s.insert 0 0
  s := s.insert s.length 99
  // s = [0, 1, 5, 7, 10, 20, 99]
  let (s1, p_back) = s.pop
  let (s2, p_front) = s1.pop_front
  let (s3, p_mid) = s2.remove 2
  // s3 = [1, 5, 10, 20], p_back=99, p_front=0, p_mid=7
  s3[1] := 55
  let g0 = case s3.get 0 of
    $Some v => v
    $Nothing => 9999
  let g_oob = case s3.get 10 of
    $Some v => v
    $Nothing => 7777
  let out = s3.to_array
  out := out.push p_back
  out := out.push p_front
  out := out.push p_mid
  out := out.push g0
  out := out.push g_oob
  return out

io test_large_tree_and_cursor (): #[U32] =>
  // Build 4000 items (forces height >= 2, >125 leaves)
  let s: ~[U32] = ~[]
  for i in 0..2000:
    s := s.push (2000 + i)
  for i in 0..2000:
    s := s.push_front (1999 - i)
  // Now s should be [0, 1, ..., 3999]
  let mismatch: U32 = 0
  for i in 0..4000:
    if s[i] != i:
      mismatch := self + 1
  // Cursor-local middle streak: insert 200 items at index 2000..2200
  for k in 0..200:
    s := s.insert (2000 + k) (100000 + k)
  // Verify length and spot checks
  let len1 = s.length
  let mid_ok: U32 = 0
  for k in 0..200:
    if s[2000 + k] == 100000 + k:
      mid_ok := self + 1
  let after_mid = s[2200]
  // Remove the 200 inserted items back out from index 2000
  let rem_sum: U32 = 0
  for k in 0..200:
    let (next_s, v) = s.remove 2000
    s := next_s
    rem_sum := self + v
  let len2 = s.length
  // Verify exact restoration [0..3999]
  let restore_mismatch: U32 = 0
  for i in 0..4000:
    if s[i] != i:
      restore_mismatch := self + 1
  // Mutate scattered indices across leaves
  for i in 0..100:
    let idx = i * 37
    s[idx] := idx * 3
  let mut_mismatch: U32 = 0
  for i in 0..100:
    let idx = i * 37
    if s[idx] != idx * 3:
      mut_mismatch := self + 1
  return #[mismatch, len1, mid_ok, after_mid, rem_sum, len2, restore_mismatch, mut_mismatch]

io test_nested_index_update (): #[U32] =>
  let boxes: ~[Box2] = ~[$Box2 { a: 1, b: 2 }, $Box2 { a: 3, b: 4 }]
  boxes[1].b := 40
  let nested: ~[#[U32]] = ~[#[10, 20], #[30, 40]]
  nested[0][1] := 200
  return #[boxes[0].a, boxes[1].a, boxes[1].b, nested[0][0], nested[0][1], nested[1][0]]

io trap_oob_read (): U32 =>
  let s = ~[1, 2, 3]
  return s[3]

io trap_empty_pop (): U32 =>
  let s: ~[U32] = ~[]
  let (_, v) = s.pop
  return v

io trap_empty_pop_front (): U32 =>
  let s: ~[U32] = ~[]
  let (_, v) = s.pop_front
  return v

io trap_oob_insert (): U32 =>
  let s = ~[1, 2]
  let s2 = s.insert 3 9
  return s2.length

io trap_bad_slice (): U32 =>
  let s = ~[1, 2, 3, 4]
  let sub = s.slice 3 1
  return sub.length
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("test_deque_and_focus", null) as Uint32Array),
        [1, 55, 10, 20, 99, 0, 7, 1, 7777],
      );
      const expectedRemSum = 200 * 100000 + (199 * 200) / 2;
      assert.deepEqual(
        Array.from(
          guest.call("test_large_tree_and_cursor", null) as Uint32Array,
        ),
        [0, 4200, 200, 2000, expectedRemSum, 4000, 0, 0],
      );
      assert.deepEqual(
        Array.from(guest.call("test_nested_index_update", null) as Uint32Array),
        [1, 3, 40, 10, 200, 30],
      );
      assert.throws(() => guest.call("trap_oob_read", null));
      assert.throws(() => guest.call("trap_empty_pop", null));
      assert.throws(() => guest.call("trap_empty_pop_front", null));
      assert.throws(() => guest.call("trap_oob_insert", null));
      assert.throws(() => guest.call("trap_bad_slice", null));
    },
  );
});

Deno.test("Seq ~[]: O(1) reverse, reverse_range, split, concat, slice, and reversed for loops", async () => {
  await compileAndRun(
    `
io test_reverse_split_concat_slice (): #[U32] =>
  let base: ~[U32] = ~[]
  for i in 0..100:
    base := base.push i
  // Keep focus dirty by inserting/removing before reverse!
  let dirty = base.copy
  dirty := dirty.insert 50 999
  let rev_dirty = dirty.reverse
  // dirty[50] == 999, len == 101 => rev_dirty[50] == 999, rev_dirty[0] == 99, rev_dirty[100] == 0
  let r_first = rev_dirty[0]
  let r_mid = rev_dirty[50]
  let r_last = rev_dirty[100]
  let rr = rev_dirty.reverse
  let rr_mid = rr[50]
  let rr_first = rr[0]

  // Mutate reversed sequence directly
  let rev_edit = base.reverse
  rev_edit[0] := 777
  rev_edit[99] := 888
  // base must be untouched (CoW!)
  let base_0 = base[0]
  let base_99 = base[99]
  let re_0 = rev_edit[0]
  let re_99 = rev_edit[99]

  // reverse_range on [0..10): reverse [2..7) -> [0, 1, 6, 5, 4, 3, 2, 7, 8, 9]
  let small: ~[U32] = ~[]
  for i in 0..10:
    small := small.push i
  let rr_small = small.reverse_range 2 7

  // split + concat + slice on multi-level tree (N = 1000)
  let big: ~[U32] = ~[]
  for i in 0..1000:
    big := big.push i
  let (left, right) = big.split 333
  let joined = right.concat left
  // joined = [333..999, 0..332]
  let j0 = joined[0]
  let j666 = joined[666]
  let j667 = joined[667]
  let j999 = joined[999]

  // Split a REVERSED sequence!
  let rev_big = big.reverse
  let (rl, rr2) = rev_big.split 400
  // rev_big = [999..0]; rl = [999..600] (len 400), rr2 = [599..0] (len 600)
  let rl_0 = rl[0]
  let rl_last = rl[399]
  let rr2_0 = rr2[0]
  let rr2_last = rr2[599]

  // Slice a reversed sequence and iterate with break/continue
  let sub = rev_big.slice 100 110
  // sub = [899, 898, ..., 890]
  let loop_sum: U32 = 0
  let loop_count: U32 = 0
  for x in sub:
    if x == 895:
      continue
    if x == 892:
      break
    loop_sum := self + x
    loop_count := self + 1
  // visited: 899, 898, 897, 896, (skip 895), 894, 893, (break 892) => count=6, sum=5377

  // For loop over dirty-focus reversed sequence
  let dirty_rev_sum: U32 = 0
  for x in rev_dirty:
    dirty_rev_sum := self + x
  // sum(0..99) + 999 = 4950 + 999 = 5949

  let out = #[
    r_first, r_mid, r_last, rr_mid, rr_first,
    base_0, base_99, re_0, re_99,
    j0, j666, j667, j999,
    rl.length, rl_0, rl_last, rr2.length, rr2_0, rr2_last,
    loop_count, loop_sum, dirty_rev_sum,
  ]
  for x in rr_small:
    out := out.push x
  return out
`,
    (guest) => {
      const res = Array.from(
        guest.call("test_reverse_split_concat_slice", null) as Uint32Array,
      );
      assert.deepEqual(res, [
        99, 999, 0, 999, 0,
        0, 99, 777, 888,
        333, 999, 0, 332,
        400, 999, 600, 600, 599, 0,
        6, 5377, 5949,
        0, 1, 6, 5, 4, 3, 2, 7, 8, 9,
      ]);
    },
  );
});

Deno.test("Seq ~[]: O(1) generative repeat, ramp, and zero-copy from_frozen_array", async () => {
  await compileAndRun(
    `
io test_generative_and_span (): #[U32] =>
  let rep = Seq.repeat 1_000_000 42
  let r0 = rep[0]
  let r_mid = rep[500_000]
  let r_last = rep[999_999]
  let rep_sub = rep.slice 100 110
  let rep_sub_sum: U32 = 0
  for x in rep_sub:
    rep_sub_sum := self + x
  // Edit middle of 1M repeat without materializing whole 1M!
  let rep_ed = rep.copy
  rep_ed[500_000] := 99
  let rep_orig_mid = rep[500_000]
  let rep_ed_mid = rep_ed[500_000]
  let rep_ed_neigh = rep_ed[500_001]

  let rmp = Seq.ramp 10 3 1_000_000
  let m0 = rmp[0]
  let m_mid = rmp[500_000]
  let m_last = rmp[999_999]
  let rmp_rev = rmp.reverse
  let mr0 = rmp_rev[0]
  let mr_last = rmp_rev[999_999]
  let rmp_sub = rmp.slice 100 105
  // 10 + 3*100 = 310, 313, 316, 319, 322
  let rmp_sub_rev = rmp_sub.reverse
  let small_ramp = Seq.ramp 1 1 1000
  let sum_fwd: U32 = 0
  for x in small_ramp:
    sum_fwd := self + x
  let sum_rev: U32 = 0
  for x in small_ramp.reverse:
    sum_rev := self + x
  // Edit middle of small_ramp
  let sr_ed = small_ramp.copy
  sr_ed[500] := 99999
  let sr_orig = small_ramp[500]
  let sr_new = sr_ed[500]
  let sr_next = sr_ed[501]

  // Zero-copy from_frozen_array
  let arr: #[U32] = Array.with_capacity 10_000
  for i in 0..10_000:
    arr := arr.push (i * 7 + 1)
  let frz = freeze arr
  let sp = Seq.from_frozen_array frz
  let sp0 = sp[0]
  let sp5000 = sp[5000]
  let sp_rev0 = sp.reverse[0]
  let sp_slice = sp.slice 10 15
  let sp_slice_sum: U32 = 0
  for x in sp_slice:
    sp_slice_sum := self + x
  // Mutate sp copy -> frz stays untouched
  let sp_ed = sp.copy
  sp_ed[5000] := 123456
  let frz_still = frz[5000]
  let sp_ed_val = sp_ed[5000]
  let sp_ed_prev = sp_ed[4999]

  return #[
    rep.length, r0, r_mid, r_last, rep_sub_sum, rep_orig_mid, rep_ed_mid, rep_ed_neigh,
    rmp.length, m0, m_mid, m_last, mr0, mr_last,
    rmp_sub[0], rmp_sub[4], rmp_sub_rev[0], rmp_sub_rev[4],
    sum_fwd, sum_rev, sr_orig, sr_new, sr_next,
    sp.length, sp0, sp5000, sp_rev0, sp_slice_sum, frz_still, sp_ed_val, sp_ed_prev,
  ]
`,
    (guest) => {
      const res = Array.from(
        guest.call("test_generative_and_span", null) as Uint32Array,
      );
      assert.deepEqual(res, [
        1_000_000, 42, 42, 42, 420, 42, 99, 42,
        1_000_000, 10, 1_500_010, 3_000_007, 3_000_007, 10,
        310, 322, 322, 310,
        500_500, 500_500, 501, 99999, 502,
        10_000, 1, 35001, 69994, 71 + 78 + 85 + 92 + 99, 35001, 123456, 34994,
      ]);
      // Repeat(1M) + Ramp(1M) + Span(10K) should use tiny memory (far below 8 MB!)
      const memBytes = guest.memoryBytes();
      assert(
        memBytes < 2 * 1024 * 1024,
        `Expected compact generative+span memory (< 2 MiB), got ${memBytes} bytes`,
      );
    },
  );
});

Deno.test("Seq ~[]: packed leaves (LEAF_PACKED_SUM and LEAF_PACKED_SOA)", async () => {
  await compileAndRun(
    `
type Event is data =
  | $Tick
  | $Big { a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32 }

type Particle is data = $Particle {
  id: U32,
  x: F32,
  y: F32,
  z: F32,
  vx: F32,
  vy: F32,
  hp: U32,
}

io test_packed_sum_seq (): #[U32] =>
  let evs: ~[Event] = ~[]
  for i in 0..2000:
    if i % 100 == 0:
      evs := evs.push ($Big { a: i, b: i + 1, c: i + 2, d: i + 3, e: i + 4, f: i + 5, g: i + 6, h: i + 7 })
    else:
      evs := evs.push $Tick
  // Forward fused for+case scan
  let tick_fwd: U32 = 0
  let big_fwd: U32 = 0
  for ev in evs:
    case ev of
      $Tick =>
        tick_fwd := self + 1
      $Big { a, h } =>
        big_fwd := self + a + h
  // Reversed fused for+case scan
  let tick_rev: U32 = 0
  let big_rev: U32 = 0
  for ev in evs.reverse:
    case ev of
      $Tick =>
        tick_rev := self + 1
      $Big { a, h } =>
        big_rev := self + a + h
  // Random index on Tick and Big (forward & reversed)
  let idx_0 = case evs[0] of
    $Tick => 9999
    $Big { h } => h
  let idx_1 = case evs[1] of
    $Tick => 111
    $Big _ => 9999
  let idx_1900 = case evs[1900] of
    $Tick => 9999
    $Big { a } => a
  let rev_idx_99 = case evs.reverse[99] of
    $Tick => 9999
    $Big { a } => a
  // Mutate same-variant ($Big -> $Big) and cross-variant ($Tick -> $Big, $Big -> $Tick)
  evs[0] := $Tick
  evs[1] := $Big { a: 500, b: 1, c: 2, d: 3, e: 4, f: 5, g: 6, h: 700 }
  evs[100] := $Big { a: 800, b: 0, c: 0, d: 0, e: 0, f: 0, g: 0, h: 900 }
  let after_0 = case evs[0] of
    $Tick => 1
    $Big _ => 0
  let after_1 = case evs[1] of
    $Tick => 0
    $Big { a, h } => a + h
  let after_100 = case evs[100] of
    $Tick => 0
    $Big { a, h } => a + h
  // Split & concat
  let (l, r) = evs.split 500
  let joined = r.concat l
  let joined_ticks: U32 = 0
  let joined_big_sum: U32 = 0
  for ev in joined:
    case ev of
      $Tick =>
        joined_ticks := self + 1
      $Big { a, h } =>
        joined_big_sum := self + a + h
  return #[
    tick_fwd, big_fwd, tick_rev, big_rev,
    idx_0, idx_1, idx_1900, rev_idx_99,
    after_0, after_1, after_100,
    joined_ticks, joined_big_sum,
  ]

io test_packed_soa_seq (): #[U32] =>
  let ps: ~[Particle] = ~[]
  for i in 0..1500:
    ps := ps.push ($Particle {
      id: i,
      x: i.to_f32,
      y: (i * 2).to_f32,
      z: 1.0,
      vx: 0.5,
      vy: 0.25,
      hp: i * 10 + 5,
    })
  // Touched-column forward scan (only id & hp!)
  let sum_id_fwd: U32 = 0
  let sum_hp_fwd: U32 = 0
  for p in ps:
    sum_id_fwd := self + p.id
    sum_hp_fwd := self + p.hp
  // Touched-column reversed scan
  let sum_id_rev: U32 = 0
  let sum_hp_rev: U32 = 0
  for p in ps.reverse:
    sum_id_rev := self + p.id
    sum_hp_rev := self + p.hp
  // Direct field update + random index
  ps[750].hp := 99999
  let p750_id = ps[750].id
  let p750_hp = ps[750].hp
  let p750_y = ps[750].y.to_u32
  // Split + concat preserves all columns
  let (a, b) = ps.split 750
  let c = b.concat a
  let c0_id = c[0].id
  let c0_hp = c[0].hp
  let c0_y = c[0].y.to_u32
  return #[
    sum_id_fwd, sum_hp_fwd, sum_id_rev, sum_hp_rev,
    p750_id, p750_hp, p750_y,
    c0_id, c0_hp, c0_y,
  ]
`,
    (guest) => {
      // Big indices: 0, 100, 200, ..., 1900 (20 items). sum(a) = 19000, sum(a+h) = 2*19000 + 20*7 = 38140
      const bigSumOrig = 2 * 19000 + 20 * 7;
      // After edits: remove i=0 (a+h=7), add i=1 (500+700=1200), replace i=100 (207 -> 1700)
      const bigSumAfter = bigSumOrig - 7 + 1200 - 207 + 1700;
      assert.deepEqual(
        Array.from(guest.call("test_packed_sum_seq", null) as Uint32Array),
        [
          1980, bigSumOrig, 1980, bigSumOrig,
          7, 111, 1900, 1900,
          1, 1200, 1700,
          1980, bigSumAfter,
        ],
      );
      const sumId = (1499 * 1500) / 2;
      const sumHp = sumId * 10 + 1500 * 5;
      assert.deepEqual(
        Array.from(guest.call("test_packed_soa_seq", null) as Uint32Array),
        [
          sumId, sumHp, sumId, sumHp,
          750, 99999, 1500,
          750, 99999, 1500,
        ],
      );
    },
  );
});

Deno.test("Seq ~[]: freeze, CoW copy, deep nested copy, fork rollback, module const, and conversions", async () => {
  await compileAndRun(
    `
const FIXED_SEQ: ~[U32] = ~[10, 20, 30, 40, 50]

io test_const_and_freeze (): #[U32] =>
  let sum_c: U32 = 0
  for x in FIXED_SEQ:
    sum_c := self + x
  let rev_c0 = FIXED_SEQ.reverse[0]
  let copy_c = FIXED_SEQ.copy
  copy_c[0] := 999
  // Freeze with active dirty focus!
  let s: ~[U32] = ~[]
  for i in 0..200:
    s := s.push i
  s := s.insert 100 7777
  let frz: *~[U32] = freeze s
  let f100 = frz[100]
  let f_rev0 = frz.reverse[0]
  let f_copy = frz.copy
  f_copy[100] := 8888
  let f_still = frz[100]
  return #[sum_c, FIXED_SEQ[0], copy_c[0], rev_c0, f100, f_rev0, f_copy[100], f_still]

io test_deep_copy_and_fork (): #[U32] =>
  // Shallow container copy + explicit inner copy preserves outer isolation
  let nested: ~[#[U32]] = ~[#[1, 2], #[3, 4]]
  let nested_copy = nested.copy
  let inner_copy = nested_copy[0].copy
  inner_copy[0] := 999
  nested_copy[0] := inner_copy
  let orig_n = nested[0][0]
  let copy_n = nested_copy[0][0]

  // Fork rollback on multi-level tree + focus + returning copy out of fork
  let s: ~[U32] = ~[]
  for i in 0..300:
    s := s.push i
  let escaped = fork s:
    s[0] := 1111
    s[150] := 2222
    s := s.insert 50 3333
    s := s.push 4444
    s := s.push_front 5555
    return s.copy
  // Outer s must be completely rolled back!
  let s_len = s.length
  let s_0 = s[0]
  let s_50 = s[50]
  let s_150 = s[150]
  // Escaped copy must preserve forked mutations!
  let e_len = escaped.length
  let e_0 = escaped[0]
  let e_1 = escaped[1]
  let e_51 = escaped[51]
  let e_last = escaped[escaped.length - 1]
  // Subsequent mutation on outer s must not affect escaped!
  s[0] := 6666
  let e_1_after = escaped[1]
  return #[orig_n, copy_n, s_len, s_0, s_50, s_150, e_len, e_0, e_1, e_51, e_last, e_1_after]

io test_conversions (): #[U32] =>
  let a = #[1, 2, 3]
  let p = %[4, 5, 6]
  let s1 = a.to_seq
  s1 := s1.extend_packed p
  s1 := s1.extend_view (&a[1..3])
  let p2 = s1.to_packed
  let s2 = p2.to_seq
  let a2 = s2.to_array
  a2 := a2.extend_seq ~[99]
  let p3 = %[10]
  p3 := p3.extend_seq ~[20, 30]
  let p3_sum: U32 = 0
  for x in p3:
    p3_sum := self + x
  a2 := a2.push p3_sum
  return a2
`,
    (guest) => {
      // Call twice to prove module const persists across invocations
      assert.deepEqual(
        Array.from(guest.call("test_const_and_freeze", null) as Uint32Array),
        [150, 10, 999, 50, 7777, 199, 8888, 7777],
      );
      assert.deepEqual(
        Array.from(guest.call("test_const_and_freeze", null) as Uint32Array),
        [150, 10, 999, 50, 7777, 199, 8888, 7777],
      );
      assert.deepEqual(
        Array.from(guest.call("test_deep_copy_and_fork", null) as Uint32Array),
        [1, 999, 300, 0, 50, 150, 303, 5555, 1111, 3333, 4444, 1111],
      );
      assert.deepEqual(
        Array.from(guest.call("test_conversions", null) as Uint32Array),
        [1, 2, 3, 4, 5, 6, 2, 3, 99, 60],
      );
    },
  );
});

Deno.test("Seq ~[]: anti-fragmentation mixed operations stress test", async () => {
  await compileAndRun(
    `
io test_mixed_stress (): #[U32] =>
  let s: ~[U32] = ~[]
  for i in 0..128:
    s := s.push i
  // 200 rounds of deterministic mixed operations
  let seed: U32 = 1234567
  for step in 0..200:
    seed := self * 1664525 + 1013904223
    let op = seed % 6
    let n = s.length
    if op == 0:
      s := s.push (1000 + step)
    else:
      if op == 1:
        s := s.push_front (2000 + step)
      else:
        if op == 2:
          let idx = (seed / 7) % (n + 1)
          s := s.insert idx (3000 + step)
        else:
          if op == 3:
            if n > 16:
              let idx = (seed / 11) % n
              let (ns, _) = s.remove idx
              s := ns
          else:
            if op == 4:
              let cut = (seed / 13) % (n + 1)
              let (l, r) = s.split cut
              s := r.concat l
            else:
              let a = (seed / 17) % n
              let b = (seed / 19) % n
              if a < b:
                s := s.reverse_range a b
              else:
                s := s.reverse
  return s.to_array
`,
    (guest) => {
      // Replicate exact deterministic operations in JS
      let ref: number[] = Array.from({ length: 128 }, (_, i) => i);
      let seed = 1234567 >>> 0;
      for (let step = 0; step < 200; step++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        const op = seed % 6;
        const n = ref.length;
        if (op === 0) {
          ref.push(1000 + step);
        } else if (op === 1) {
          ref.unshift(2000 + step);
        } else if (op === 2) {
          const idx = Math.floor(seed / 7) % (n + 1);
          ref.splice(idx, 0, 3000 + step);
        } else if (op === 3) {
          if (n > 16) {
            const idx = Math.floor(seed / 11) % n;
            ref.splice(idx, 1);
          }
        } else if (op === 4) {
          const cut = Math.floor(seed / 13) % (n + 1);
          ref = [...ref.slice(cut), ...ref.slice(0, cut)];
        } else {
          const a = Math.floor(seed / 17) % n;
          const b = Math.floor(seed / 19) % n;
          if (a < b) {
            const mid = ref.slice(a, b).reverse();
            ref = [...ref.slice(0, a), ...mid, ...ref.slice(b)];
          } else {
            ref.reverse();
          }
        }
      }
      const actual = Array.from(
        guest.call("test_mixed_stress", null) as Uint32Array,
      );
      assert.deepEqual(actual, ref);
    },
  );
});

Deno.test("Seq ~[]: deep edge cases (height-3 trees, empty ops, heterogeneous leaves, packed edits, pop-to-empty, multi-branch CoW)", async () => {
  await compileAndRun(
    `
type BigEvent is data =
  | $Tick
  | $Big { a: U64, b: U64, c: U64, d: U64, e: U64, f: U64, g: U64, h: U64 }

type Particle is data = $Particle {
  id: U32,
  x: F32,
  y: F32,
  z: F32,
  vx: F32,
  vy: F32,
  hp: U32,
}

io test_empty_and_drain (): #[U32] =>
  let e: ~[U32] = ~[]
  let e_rev = e.reverse
  let (el, er) = e.split 0
  let ec1 = e.concat e
  let ec2 = e.concat ~[7, 8]
  let ec3 = ~[9, 10].concat e
  let esl = e.slice 0 0
  let err = e.reverse_range 0 0
  let rep0 = Seq.repeat 0 42
  let rmp0 = Seq.ramp 10 3 0
  let empty_arr: #[U32] = #[]
  let sp0 = Seq.from_frozen_array (freeze empty_arr)
  let e_sum: U32 = 0
  for x in e:
    e_sum := self + x
  // Build 100 items, pop_front 50 and pop 50 down to empty, then refill!
  let d: ~[U32] = ~[]
  for i in 0..100:
    d := d.push i
  let front_sum: U32 = 0
  for _ in 0..50:
    let (nd, v) = d.pop_front
    d := nd
    front_sum := self + v
  let back_sum: U32 = 0
  for _ in 0..50:
    let (nd, v) = d.pop
    d := nd
    back_sum := self + v
  let drained_len = d.length
  d := d.push_front 111
  d := d.push 222
  return #[
    e_rev.length, el.length, er.length, ec1.length, ec2.length, ec3.length,
    esl.length, err.length, rep0.length, rmp0.length, sp0.length, e_sum,
    front_sum, back_sum, drained_len, d[0], d[1],
  ]

io test_heterogeneous_and_height3 (): #[U32] =>
  // Height-3 tree: 20,000 items (> 16*16*64 = 16,384 leaves-per-height-2)
  let h3: ~[U32] = ~[]
  for i in 0..20_000:
    h3 := h3.push i
  let (hl, hr) = h3.split 4000
  let h3_rot = hr.concat hl
  let h3_rev = h3_rot.reverse
  let h3_sum: U32 = 0
  for x in h3_rev:
    h3_sum := self + x

  // Heterogeneous tree: RAMP + FROZEN_SPAN + REPEAT + FLAT literal!
  let arr: #[U32] = Array.with_capacity 50
  for i in 0..50:
    arr := arr.push (1000 + i)
  let s_ramp = Seq.ramp 0 2 50
  let s_span = Seq.from_frozen_array (freeze arr)
  let s_rep = Seq.repeat 50 777
  let s_flat = ~[9001, 9002, 9003]
  let combo = ((s_ramp.concat s_span).concat s_rep).concat s_flat
  // Length = 153: [0..98 even] + [1000..1049] + [777 x 50] + [9001, 9002, 9003]
  let c0 = combo[0]
  let c49 = combo[49]
  let c50 = combo[50]
  let c100 = combo[100]
  let c152 = combo[152]
  // Reverse & mutate across leaf boundaries
  let combo_rev = combo.reverse
  let cr0 = combo_rev[0]
  let cr152 = combo_rev[152]
  let combo_ed = combo.copy
  combo_ed[25] := 5555
  combo_ed[75] := 6666
  combo_ed[125] := 7777
  let combo_sum: U32 = 0
  for x in combo_ed:
    combo_sum := self + x

  // Multi-version CoW branching from a shared base
  let base = ~[i | i <- #[10, 20, 30, 40, 50]]
  let v1 = base.copy
  v1 := v1.push_front 1
  let v2 = base.copy
  v2 := v2.insert 2 99
  let v3 = base.reverse
  v3[0] := 500
  return #[
    h3_rot.length, h3_rot[0], h3_rot[16000], h3_rev[0], h3_sum,
    combo.length, c0, c49, c50, c100, c152, cr0, cr152, combo_sum,
    base[0], base[4], v1[0], v2[2], v3[0],
  ]

io test_packed_sum_lazy_upgrade_and_soa_edits (): #[U32] =>
  // 10,000 events: 99% $Tick, 1% 64B $Big, PLUS upgrading an all-$Tick leaf!
  let evs: ~[BigEvent] = ~[]
  for i in 0..10_000:
    if i >= 500 and i % 100 == 0:
      let v = i.to_u64
      evs := evs.push ($Big { a: v, b: 1u64, c: 2u64, d: 3u64, e: 4u64, f: 5u64, g: 6u64, h: 7u64 })
    else:
      evs := evs.push $Tick
  // Indices 0..499 are purely $Tick leaves (zero $Big sub-buffers allocated!).
  // Now upgrade index 100 in-place to $Big!
  evs[100] := $Big { a: 4242u64, b: 0u64, c: 0u64, d: 0u64, e: 0u64, f: 0u64, g: 0u64, h: 8u64 }
  let upgraded = case evs[100] of
    $Tick => 0
    $Big { a, h } => a.to_u32 + h.to_u32
  let still_tick = case evs[101] of
    $Tick => 1
    $Big _ => 0

  // SoA insert / remove / push_front / pop_front / full replace
  let ps: ~[Particle] = ~[]
  for i in 0..80:
    ps := ps.push ($Particle { id: i, x: 1.0, y: 2.0, z: 3.0, vx: 4.0, vy: 5.0, hp: i * 2 })
  ps := ps.push_front ($Particle { id: 900, x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, hp: 9000 })
  ps := ps.insert 40 ($Particle { id: 800, x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, hp: 8000 })
  let (ps1, pf) = ps.pop_front
  let (ps2, rm) = ps1.remove 39
  return #[upgraded, still_tick, pf.id, pf.hp, rm.id, rm.hp, ps2.length, ps2[39].id]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("test_empty_and_drain", null) as Uint32Array),
        [
          0, 0, 0, 0, 2, 2,
          0, 0, 0, 0, 0, 0,
          (49 * 50) / 2, (50 + 99) * 50 / 2, 0, 111, 222,
        ],
      );
      const h3Sum = (19999 * 20000) / 2;
      // combo sum before edits:
      // ramp(0,2,50): sum(0,2,..,98) = 2450
      // span(1000..1049): 50*1000 + 49*50/2 = 51225
      // rep(50, 777): 38850
      // flat: 9001+9002+9003 = 27006
      // edits: idx 25 was 50 -> 5555 (+5505); idx 75 was 1025 -> 6666 (+5641); idx 125 was 777 -> 7777 (+7000)
      const comboSum = 2450 + 51225 + 38850 + 27006 + (5555 - 50) +
        (6666 - 1025) + (7777 - 777);
      assert.deepEqual(
        Array.from(
          guest.call("test_heterogeneous_and_height3", null) as Uint32Array,
        ),
        [
          20_000, 4000, 0, 3999, h3Sum,
          153, 0, 98, 1000, 777, 9003, 9003, 0, comboSum,
          10, 50, 1, 99, 500,
        ],
      );
      assert.deepEqual(
        Array.from(
          guest.call(
            "test_packed_sum_lazy_upgrade_and_soa_edits",
            null,
          ) as Uint32Array,
        ),
        [4250, 1, 900, 9000, 800, 8000, 80, 39],
      );
    },
  );
});

Deno.test("Seq ~[]: compile-time rejections (views, refs, links, truncate, implicit coercions, mutations)", async () => {
  await expectReject(
    `io main (): U32 =>
  let s = ~[1, 2, 3]
  let v = &s[0..2]
  return v.length
`,
    "slice view &s[0..2] on Seq",
  );

  await expectReject(
    `io main (): U32 =>
  let s = ~[1, 2, 3]
  let r = &s[0]
  return r.load
`,
    "element ref &s[0] on Seq",
  );

  await expectReject(
    `io main (): U32 =>
  let s = ~[1, 2, 3]
  let l = ^s[0]
  return l.load
`,
    "element link ^s[0] on Seq",
  );

  await expectReject(
    `io main (): U32 =>
  let s = ~[1, 2, 3]
  @storage.truncate s 1
  return s.length
`,
    "truncate on Seq",
  );

  await expectReject(
    `func take_arr (xs: #[U32]): U32 => xs.length
io main (): U32 =>
  return take_arr ~[1, 2, 3]
`,
    "implicit Seq -> Array coercion",
  );

  await expectReject(
    `func take_packed (xs: %[U32]): U32 => xs.length
io main (): U32 =>
  return take_packed ~[1, 2, 3]
`,
    "implicit Seq -> Packed coercion",
  );

  await expectReject(
    `func take_seq (xs: ~[U32]): U32 => xs.length
io main (): U32 =>
  return take_seq #[1, 2, 3]
`,
    "implicit Array -> Seq coercion",
  );

  await expectReject(
    `io main (): U32 =>
  let s = freeze ~[1, 2, 3]
  let s2 = s.push 4
  return s2.length
`,
    "mutating frozen *~[U32]",
  );

  await expectReject(
    `func bad (xs: ~[U32]): U32 =>
  let ys = xs.push 4
  return ys.length
io main (): U32 => bad ~[1, 2]
`,
    "pushing to borrowed ~[U32]",
  );

  await expectReject(
    `func bad (xs: ~[U32]): U32 =>
  xs[0] := 9
  return xs[0]
io main (): U32 => bad ~[1, 2]
`,
    "indexed write on borrowed ~[U32]",
  );

  await expectReject(
    `const C: ~[U32] = ~[1, 2, 3]
io main (): U32 =>
  let c2 = C.push 4
  return c2.length
`,
    "mutating module const ~[U32]",
  );

  await expectReject(
    `io main (): U32 =>
  let nested: ~[#[U32]] = ~[#[1, 2], #[3, 4]]
  let shallow = nested.copy
  shallow[0][0] := 999
  return nested[0][0]
`,
    "mutating aliased inner array through shallow Seq.copy",
  );
});
