import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

async function compileAndRun(
  source: string,
  run: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array,
  ) => void | Promise<void>,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "squid-packed-" });
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
  const dir = await Deno.makeTempDir({ prefix: "squid-packed-reject-" });
  const entry = `${dir}/main.sq`;
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

Deno.test("Packed %[]: literals, comprehensions, spreads, contextual typing, and % modulo coexistence", async () => {
  await compileAndRun(
    `
func (%%) (a: U32) -> (b: U32): U32 => a * 10 + b

func sum_packed (xs: %[U32]): U32 =>
  let acc: U32 = 0
  for x in xs:
    acc := self + x
  return acc

func push_and_sum (xs: own %[U32]) -> (extra: U32): U32 =>
  let out = xs.push extra
  return sum_packed out

io test_syntax_and_ops (): #[U32] =>
  let empty: %[U32] = %[]
  let tight=%[1,2,3]
  let bytes: %[U8] = %[10, 20, 30]
  let bsum: U32 = 0
  for b in bytes:
    bsum := self + b.to_u32
  let arr = #[2, 4, 6, 8]
  let comp1 = %[y | x <- arr, x > 2, let y = x * 3]
  let comp2 = %[x + 1 | x <- tight]
  let comp3 = %[i * i | i <- #[0, 1, 2, 3, 4]]
  let sp1 = %[100, ...tight, 200]
  let sp2 = %[5, ...arr, 6]
  let rem1 = 17 % 5
  let rem2 = (%) 17 5
  let custom = 4 %% 2
  let app1 = sum_packed %[10, 20, 30]
  let app2 = push_and_sum %[1, 2] 9
  let empty_flag = if empty.is_empty then 1 else 0
  let tight_flag = if tight.is_empty then 1 else 0
  return #[
    empty.length,
    empty_flag,
    tight_flag,
    bsum,
    sum_packed comp1,
    sum_packed comp2,
    sum_packed comp3,
    sum_packed sp1,
    sum_packed sp2,
    rem1,
    rem2,
    custom,
    app1,
    app2,
  ]
`,
    (guest) => {
      const res = Array.from(guest.call("test_syntax_and_ops", null) as Uint32Array);
      assert.deepEqual(res, [
        0, // empty.length
        1, // empty.is_empty
        0, // tight.is_empty
        60, // 10+20+30
        54, // (4+6+8)*3
        9, // 2+3+4
        30, // 0+1+4+9+16
        306, // 100+1+2+3+200
        31, // 5+2+4+6+8+6
        2, // 17 % 5
        2, // (%) 17 5
        42, // 4 %% 2
        60, // sum_packed %[10, 20, 30]
        12, // push_and_sum %[1, 2] 9
      ]);
    },
  );
});

Deno.test("Packed %[]: flat scalars, enums, recursive nominals, and Array/Packed conversions", async () => {
  await compileAndRun(
    `
type Color is data = $Red | $Green | $Blue
type Chain is data = $End | $Link { v: U32, next: Chain }

func chain_sum (c: Chain): U32 =>
  let cur = c
  let acc: U32 = 0
  for ever:
    case cur of
      $End =>
        break
      $Link { v, next } =>
        acc := self + v
        cur := next
  return acc

io test_flat_ops (): #[U32] =>
  let u: %[U32] = Packed.with_capacity 4
  u := self.push 10
  u := self.push 20
  u := self.reserve 16
  let extra_p = %[30, 40]
  u := self.extend extra_p
  let arr = #[50, 60, 70]
  u := self.extend_array arr
  u := self.extend_view (&arr[1..3])
  // u = [10, 20, 30, 40, 50, 60, 70, 60, 70] -> sum = 410, len = 9
  let snap = u.copy
  let (u2, pval) = u.pop
  u := u2
  // snap still has 9 items; u has 8 items
  let joined = Packed.concat snap %[1, 2]
  let as_arr = joined.to_array
  let round = as_arr.to_packed
  let back = Array.from_packed round
  let dst_arr: #[U32] = #[9]
  dst_arr := self.extend_packed %[8, 7]

  // Packed Bool & U64 & F64 & Color & recursive Chain
  let flags: %[Bool] = %[true, false, true, true]
  let tcount: U32 = 0
  for f in flags:
    if f:
      tcount := self + 1
  let wide: %[U64] = %[100u64, 200u64, 300u64]
  let wsum: U64 = 0u64
  for w in wide:
    wsum := self + w
  let cols: %[Color] = %[$Red, $Green, $Blue, $Green]
  let cscore: U32 = 0
  for col in cols:
    case col of
      $Red =>
        cscore := self + 1
      $Green =>
        cscore := self + 10
      $Blue =>
        cscore := self + 100
  let c1 = $Link { v: 3, next: $Link { v: 4, next: $End } }
  let c2 = $Link { v: 10, next: $End }
  let chains: %[Chain] = %[c1, $End, c2]
  let chsum: U32 = 0
  for ch in chains:
    chsum := self + chain_sum ch

  let sum_back: U32 = 0
  for x in back:
    sum_back := self + x
  return #[
    u.length,
    snap.length,
    pval,
    joined.length,
    back.length,
    sum_back,
    dst_arr[0] + dst_arr[1] + dst_arr[2],
    tcount,
    wsum.to_u32,
    cscore,
    chsum,
  ]
`,
    (guest) => {
      const res = Array.from(guest.call("test_flat_ops", null) as Uint32Array);
      assert.deepEqual(res, [
        8, // u.length after pop
        9, // snap.length isolated
        70, // popped last element
        11, // joined.length
        11, // back.length
        413, // 410 + 1 + 2
        24, // 9 + 8 + 7
        3, // tcount
        600, // wsum
        121, // 1 + 10 + 100 + 10
        17, // 3 + 4 + 10
      ]);
    },
  );
});

Deno.test("Packed %[]: split-stream sums (fused tag-only/selective/multi-arm case, general materialization, pop, extend, Wave C niche & outlined)", async () => {
  await compileAndRun(
    `
type Event is data =
  | $Tick
  | $Delta I32
  | $Spawn { id: U32, x: F32, y: F32, vx: F32, vy: F32, hp: U32, kind: U8 }
  | $Tag U8
  | $Reset

type BigBox is data = $BigBox { a: U32, b: U32, c: U32, d: U32, e: U32, f: U32 }

type Skewed is data =
  | $Small U32
  | $Huge { a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32 }

func score_event (ev: Event): U32 => case ev of
  $Tick => 1
  $Delta d => if d < 0i32 then 0 else d.to_u32
  $Spawn { id, hp, kind } => id + hp + kind.to_u32
  $Tag b => b.to_u32
  $Reset => 1000

func make_events (): %[Event] =>
  let evs: %[Event] = Packed.with_capacity 4
  evs := self.push $Tick
  evs := self.push ($Delta 15i32)
  evs := self.push ($Spawn { id: 7, x: 1.0, y: 2.0, vx: 3.0, vy: 4.0, hp: 50, kind: 3u8 })
  evs := self.push ($Tag 9u8)
  evs := self.push $Tick
  evs := self.push $Reset
  evs := self.push ($Delta (-5i32))
  return evs

io test_split_sum (): #[U32] =>
  let evs = make_events ()
  // 1. Fused tag-only scan (zero payload loads!)
  let ticks: U32 = 0
  let resets: U32 = 0
  for ev in evs:
    case ev of
      $Tick =>
        ticks := self + 1
      $Reset =>
        resets := self + 1
      _ =>
        ()

  // 2. Fused selective-variant scan (loads only $Delta and $Tag, skips $Spawn!)
  let delta_sum: I32 = 0i32
  let tag_sum: U32 = 0
  for ev in evs:
    case ev of
      $Delta d =>
        delta_sum := self + d
      $Tag b =>
        tag_sum := self + b.to_u32
      _ =>
        ()

  // 3. Fused full 5-variant case (tests caseLevel binary chain & rebinds)
  let full_score: U32 = 0
  let spawn_hp: U32 = 0
  for ev in evs:
    case ev of
      $Tick =>
        full_score := self + 1
      $Delta d =>
        if d > 0i32:
          full_score := self + d.to_u32
      $Spawn { id, hp, kind } =>
        full_score := self + id + hp + kind.to_u32
        spawn_hp := self + hp
      $Tag b =>
        full_score := self + b.to_u32
      $Reset =>
        full_score := self + 1000

  // 4. General materialization path (passes ev whole to helper)
  let general_score: U32 = 0
  for ev in evs:
    general_score := self + score_event ev

  // 5. Fused loop with continue & break (stops at $Reset)
  let before_reset: U32 = 0
  for ev in evs:
    case ev of
      $Reset =>
        break
      $Tick =>
        before_reset := self + 1
        continue
      $Delta d =>
        if d > 0i32:
          before_reset := self + d.to_u32
      _ =>
        ()

  // 6. Copy isolation, extend (packed-to-packed bulk copy), pop in lockstep, to_array/from_array
  let copy1 = evs.copy
  let extended = evs.extend copy1
  let (after_pop1, p1) = extended.pop
  let (after_pop2, p2) = after_pop1.pop
  let pop1_score = score_event p1
  let pop2_score = score_event p2

  let arr = copy1.to_array
  let rebuilt = Packed.from_array arr
  let rebuilt_score: U32 = 0
  for ev in rebuilt:
    rebuilt_score := self + score_event ev

  // 7. Wave C 2-variant nullable-pointer niche: %[Maybe BigBox]
  let boxes: %[Maybe BigBox] = %[
    $Nothing,
    $Some ($BigBox { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6 }),
    $Nothing,
    $Some ($BigBox { a: 10, b: 20, c: 30, d: 40, e: 50, f: 60 }),
  ]
  let box_sum: U32 = 0
  let nothing_count: U32 = 0
  for mb in boxes:
    case mb of
      $Nothing =>
        nothing_count := self + 1
      $Some ($BigBox { a, f }) =>
        box_sum := self + a + f

  // 8. Wave C skewed cold-outlined sum: %[Skewed]
  let skew: %[Skewed] = %[
    $Small 5,
    $Huge { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10 },
    $Small 7,
  ]
  let skew_sum: U32 = 0
  for sk in skew:
    case sk of
      $Small v =>
        skew_sum := self + v
      $Huge { a, j } =>
        skew_sum := self + a + j
  // Also materialize Skewed whole via pop!
  let (_, last_sk) = skew.pop
  let last_sk_val = case last_sk of
    $Small v => v
    _ => 0

  return #[
    ticks,
    resets,
    delta_sum.to_u32,
    tag_sum,
    full_score,
    spawn_hp,
    general_score,
    before_reset,
    after_pop2.length,
    pop1_score,
    pop2_score,
    rebuilt_score,
    box_sum,
    nothing_count,
    skew_sum,
    last_sk_val,
  ]
`,
    (guest) => {
      const res = Array.from(guest.call("test_split_sum", null) as Uint32Array);
      assert.deepEqual(res, [
        2, // ticks
        1, // resets
        10, // 15 + (-5)
        9, // tag_sum
        1086, // 1 + 15 + (7+50+3) + 9 + 1 + 1000 + 0
        50, // spawn_hp
        1086, // general_score matches fused full_score
        17, // $Tick(1) + $Delta(15) + $Tick(1) before $Reset
        12, // 14 - 2
        0, // popped $Delta(-5) -> score 0
        1000, // popped $Reset -> score 1000
        1086, // rebuilt via to_array/from_array
        77, // (1+6) + (10+60)
        2, // nothing_count
        23, // 5 + (1+10) + 7
        7, // popped $Small 7
      ]);
    },
  );
});

Deno.test("Packed %[]: SoA records and tuples (boxed/unboxed, touched-column projection, destructuring, whole materialization)", async () => {
  await compileAndRun(
    `
type Particle is data = $Particle {
  x: F32,
  y: F32,
  vx: F32,
  vy: F32,
  hp: U32,
  alive: Bool,
  pad: Unit,
}

func particle_score (p: Particle): U32 =>
  if p.alive then p.hp + p.x.to_u32 + p.y.to_u32 else 0

func build_particles (): %[Particle] =>
  let ps: %[Particle] = Packed.with_capacity 4
  ps := self.push ($Particle { x: 10.0, y: 20.0, vx: 1.0, vy: 2.0, hp: 100, alive: true, pad: () })
  ps := self.push ($Particle { x: 30.0, y: 40.0, vx: 3.0, vy: 4.0, hp: 200, alive: false, pad: () })
  ps := self.push ($Particle { x: 50.0, y: 60.0, vx: 5.0, vy: 6.0, hp: 300, alive: true, pad: () })
  return ps

io test_soa (): #[U32] =>
  let ps = build_particles ()
  // 1. Touched-column virtual projection: reads ONLY hp and alive (never loads x, y, vx, vy!)
  let alive_hp: U32 = 0
  for p in ps:
    if p.alive:
      alive_hp := self + p.hp

  // 2. Destructuring pattern on nominal SoA record (reads only x and hp)
  let x_hp_sum: U32 = 0
  for $Particle { x, hp } in ps:
    x_hp_sum := self + x.to_u32 + hp

  // 3. Whole materialization (passes p to helper)
  let whole_sum: U32 = 0
  for p in ps:
    whole_sum := self + particle_score p

  // 4. Structural record SoA (mixed widths: U32, U8, F64, Bool)
  let recs: %[{ a: U32, b: U8, c: F64, d: Bool }] = %[
    { a: 10, b: 1u8, c: 2.0f64, d: true },
    { a: 20, b: 2u8, c: 3.0f64, d: false },
    { a: 30, b: 4u8, c: 5.0f64, d: true },
  ]
  let rec_partial: U32 = 0
  for r in recs:
    if r.d:
      rec_partial := self + r.a + r.b.to_u32
  let rec_destr: U32 = 0
  for { a, c } in recs:
    rec_destr := self + a + c.to_u32

  // 5. Tuple SoA
  let tups: %[(U32, F32, Bool)] = %[
    (11, 2.0, true),
    (22, 3.0, false),
    (33, 4.0, true),
  ]
  let tup_sum: U32 = 0
  for (n, _, ok) in tups:
    if ok:
      tup_sum := self + n

  // 6. Copy, extend, pop, to_array/from_array on SoA
  let ps2 = ps.copy
  let ps_ext = ps.extend ps2
  let (ps_popped, last_p) = ps_ext.pop
  let $Particle { hp: last_hp } = last_p
  let as_arr = ps2.to_array
  let rebuilt = as_arr.to_packed
  let reb_sum: U32 = 0
  for p in rebuilt:
    reb_sum := self + p.hp

  return #[
    alive_hp,
    x_hp_sum,
    whole_sum,
    rec_partial,
    rec_destr,
    tup_sum,
    ps_popped.length,
    last_hp,
    reb_sum,
  ]
`,
    (guest) => {
      const res = Array.from(guest.call("test_soa", null) as Uint32Array);
      assert.deepEqual(res, [
        400, // 100 + 300
        690, // (10+100) + (30+200) + (50+300)
        540, // (100+10+20) + 0 + (300+50+60)
        45, // (10+1) + (30+4)
        70, // (10+2) + (20+3) + (30+5)
        44, // 11 + 33
        5, // 6 - 1
        300, // popped last particle hp
        600, // 100 + 200 + 300
      ]);
    },
  );
});

Deno.test("Packed %[]: split-stream memory density beats wide flat sum storage", async () => {
  await compileAndRun(
    `
type BigEvent is data =
  | $Tick
  | $Big { a: U64, b: U64, c: U64, d: U64, e: U64, f: U64, g: U64, h: U64 }

io test_density (n: U32): #[U32] =>
  let evs: %[BigEvent] = Packed.with_capacity 64
  for i in 0..n:
    if i % 100 == 0:
      let v = i.to_u64
      evs := self.push ($Big { a: v, b: v + 1u64, c: 0u64, d: 0u64, e: 0u64, f: 0u64, g: 0u64, h: 1u64 })
    else:
      evs := self.push $Tick
  let ticks: U32 = 0
  let bigs: U32 = 0
  let sum_h: U32 = 0
  for ev in evs:
    case ev of
      $Tick =>
        ticks := self + 1
      $Big { h } =>
        bigs := self + 1
        sum_h := self + h.to_u32
  return #[evs.length, ticks, bigs, sum_h]
`,
    (guest) => {
      // 50,000 events: 49,500 $Tick (1B each = 49.5 KB) + 500 $Big (64B each = 32 KB)
      // Total live split-stream payload ~82 KB (vs ~3.6+ MB for flat #[BigEvent]!).
      const res = Array.from(guest.call("test_density", 50000) as Uint32Array);
      assert.deepEqual(res, [50000, 49500, 500, 500]);
      assert(
        guest.memoryBytes() < 1024 * 1024,
        `Expected split-stream %[BigEvent] to stay under 1 MiB, got ${guest.memoryBytes()} bytes`,
      );
    },
  );
});

Deno.test("Packed %[]: freeze (*%[T]), fork rollback, module const, returns, and nested containers", async () => {
  await compileAndRun(
    `
type Event is data = $Tick | $Val U32 | $Pair { a: U32, b: U32 }
type Vec2 is data = $Vec2 { x: U32, y: U32 }

const CONST_FLAT: %[U32] = %[3, 6, 9]
const CONST_EVENTS: %[Event] = %[$Tick, $Val 10, $Pair { a: 4, b: 5 }]
const CONST_SOA: %[Vec2] = %[$Vec2 { x: 1, y: 2 }, $Vec2 { x: 3, y: 4 }]
const CONST_NESTED: %[#[U32]] = %[#[1, 2], #[3, 4, 5]]

func sum_frozen_events (f: *%[Event]): U32 =>
  let total: U32 = 0
  for ev in f:
    case ev of
      $Tick =>
        total := self + 1
      $Val v =>
        total := self + v
      $Pair { a, b } =>
        total := self + a + b
  return total + f.length

func sum_frozen_soa (f: *%[Vec2]): U32 =>
  let total: U32 = 0
  for v in f:
    total := self + v.x + v.y
  return total

io test_freeze_fork_const_nested (): #[U32] =>
  // 1. Freeze split-stream & SoA & flat
  let fe: *%[Event] = freeze (%[$Tick, $Val 20, $Pair { a: 2, b: 3 }])
  let fs: *%[Vec2] = freeze (%[$Vec2 { x: 7, y: 8 }, $Vec2 { x: 9, y: 10 }])
  let f_ev_sum = sum_frozen_events fe
  let f_ev_copy = fe.copy
  let f_ev_copy_grown = f_ev_copy.push ($Val 100)
  let f_soa_sum = sum_frozen_soa fs

  // 2. Fork rollback across growth on split-stream, SoA, and flat
  let evs: %[Event] = %[$Tick, $Val 5]
  let spec_ev_len = fork evs:
    for i in 0..20:
      evs := self.push ($Pair { a: i, b: i + 1 })
    return evs.length
  let evs_after_fork: U32 = 0
  for ev in evs:
    case ev of
      $Tick =>
        evs_after_fork := self + 1
      $Val v =>
        evs_after_fork := self + v
      $Pair { a, b } =>
        evs_after_fork := self + a + b

  let pts: %[Vec2] = %[$Vec2 { x: 2, y: 3 }]
  let spec_pt_len = fork pts:
    for i in 0..16:
      pts := self.push ($Vec2 { x: i, y: i })
    return pts.length
  let pts_after_fork: U32 = 0
  for p in pts:
    pts_after_fork := self + p.x + p.y

  // 3. Module const reads & copy isolation
  let cf_sum: U32 = 0
  for x in CONST_FLAT:
    cf_sum := self + x
  let cf_mut = CONST_FLAT.copy
  cf_mut := self.push 100
  let ce_sum: U32 = 0
  for ev in CONST_EVENTS:
    case ev of
      $Tick =>
        ce_sum := self + 1
      $Val v =>
        ce_sum := self + v
      $Pair { a, b } =>
        ce_sum := self + a + b
  let cs_sum: U32 = 0
  for v in CONST_SOA:
    cs_sum := self + v.x + v.y
  let cn_sum: U32 = 0
  for row in CONST_NESTED:
    for x in row:
      cn_sum := self + x

  // 4. Nested %[#[U32]] and %[%[U32]] with copy isolation
  let inner_a: #[U32] = #[10, 20]
  let inner_b: #[U32] = #[30]
  let nest1: %[#[U32]] = %[inner_a, inner_b]
  let nest1_copy = nest1.copy
  let nest1_sum: U32 = 0
  for row in nest1_copy:
    for x in row:
      nest1_sum := self + x
  let nest2: %[%[U32]] = %[%[1, 2], %[3, 4, 5]]
  let nest2_sum: U32 = 0
  for sub in nest2:
    for x in sub:
      nest2_sum := self + x

  return #[
    f_ev_sum,
    fe.length,
    f_ev_copy_grown.length,
    f_soa_sum,
    spec_ev_len,
    evs.length,
    evs_after_fork,
    spec_pt_len,
    pts.length,
    pts_after_fork,
    cf_sum,
    CONST_FLAT.length,
    cf_mut.length,
    ce_sum,
    cs_sum,
    cn_sum,
    nest1_sum,
    nest2_sum,
  ]
`,
    (guest) => {
      const expected = [
        29, // (1 + 20 + 5) + 3
        3, // fe.length unchanged after copy grown
        4, // f_ev_copy_grown.length
        34, // 7+8+9+10
        22, // spec_ev_len inside fork
        2, // evs.length rolled back
        6, // $Tick(1) + $Val(5) rolled back
        17, // spec_pt_len inside fork
        1, // pts.length rolled back
        5, // 2 + 3 rolled back
        18, // 3+6+9
        3, // CONST_FLAT.length unchanged
        4, // cf_mut.length
        20, // 1 + 10 + 4 + 5
        10, // 1+2+3+4
        15, // 1+2+3+4+5
        60, // 10+20+30
        15, // 1+2+3+4+5
      ];
      // Call twice to verify module const persistence survives invocation teardown!
      assert.deepEqual(
        Array.from(guest.call("test_freeze_fork_const_nested", null) as Uint32Array),
        expected,
      );
      assert.deepEqual(
        Array.from(guest.call("test_freeze_fork_const_nested", null) as Uint32Array),
        expected,
      );
    },
  );
});

Deno.test("Packed %[]: compile-time rejections for indexing, slicing, linking, truncate, read, implicit conversion, and uniqueness", async () => {
  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  return p[0]
`,
    "index read p[0]",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  p[0] := 9
  return p.length
`,
    "index write p[0] := 9",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  let v = &p[0..2]
  return v.length
`,
    "slice view &p[0..2]",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  let r = &p[0]
  return @storage.read p 0
`,
    "element ref &p[0]",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  let l = ^p[0]
  return p.length
`,
    "element link ^p[0]",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  p := @storage.truncate self 1
  return p.length
`,
    "@storage.truncate on packed",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2, 3]
  return @storage.read p 0
`,
    "@storage.read on packed",
  );

  await expectReject(
    `func need_arr (xs: #[U32]): U32 => xs.length
io main (): U32 =>
  let p = %[1, 2, 3]
  return need_arr p
`,
    "implicit %[U32] -> #[U32]",
  );

  await expectReject(
    `func need_packed (xs: %[U32]): U32 => xs.length
io main (): U32 =>
  let a = #[1, 2, 3]
  return need_packed a
`,
    "implicit #[U32] -> %[U32]",
  );

  await expectReject(
    `func bad_borrow (xs: %[U32]): %[U32] => xs.push 1
io main (): U32 =>
  let p = %[1, 2]
  return (bad_borrow p).length
`,
    "mutating borrowed %[U32] parameter",
  );

  await expectReject(
    `io main (): U32 =>
  let p = %[1, 2]
  let alias = p
  p := self.push 3
  return alias.length + p.length
`,
    "mutating aliased %[U32]",
  );

  await expectReject(
    `io main (): U32 =>
  let f: *%[U32] = freeze %[1, 2]
  let g = f.push 3
  return g.length
`,
    "mutating frozen *%[U32]",
  );

  await expectReject(
    `const P: %[U32] = %[1, 2]
io main (): U32 =>
  let q = P.push 3
  return q.length
`,
    "mutating module const %[U32]",
  );
});

Deno.test("Packed %[]: SoA header-cached growth, pop/refill, reserve, extend, copy, nested containers, and fork rollback", async () => {
  await compileAndRun(
    `
type WideRec = {
  id: U32,
  hp: U32,
  x: F64,
  y: F64,
  z: F64,
  flags: U32,
}

type BagRec = {
  id: U32,
  items: #[U32],
}

const CONST_WIDE: %[WideRec] = %[
  { id: 1, hp: 10, x: 1.0f64, y: 2.0f64, z: 3.0f64, flags: 7 },
  { id: 2, hp: 20, x: 4.0f64, y: 5.0f64, z: 6.0f64, flags: 9 },
]

io test_soa_cached_lifecycle (): #[U32] =>
  // Start completely empty (%[]), grow across multiple doublings (0 -> 4 -> 8 -> ... -> 512)
  let xs: %[WideRec] = %[]
  for i in 0..300:
    xs := xs.push { id: i, hp: i * 3 + 1, x: i.to_f64, y: 2.0f64, z: 3.0f64, flags: i % 5 }

  // Pop 50 elements, push 20 back, reserve +200, push 30 more (total = 300)
  let pop_sum: U32 = 0
  for _ in 0..50:
    let (next_xs, v) = xs.pop
    xs := next_xs
    pop_sum := self + v.id
  for i in 0..20:
    xs := xs.push { id: 1000 + i, hp: 5, x: 0.0f64, y: 0.0f64, z: 0.0f64, flags: 1 }
  xs := xs.reserve 200
  for i in 0..30:
    xs := xs.push { id: 2000 + i, hp: 7, x: 0.0f64, y: 0.0f64, z: 0.0f64, flags: 2 }

  // Copy isolation + extend + pop on copy must not disturb original
  let cp = xs.copy
  cp := cp.extend CONST_WIDE
  let (cp2, last_v) = cp.pop
  let xs_sum: U32 = 0
  for { id, hp, flags } in xs:
    xs_sum := self + id + hp + flags
  let cp2_sum: U32 = 0
  for { id, hp } in cp2:
    cp2_sum := self + id + hp

  // Fork rollback across BOTH growth and pop on SoA
  let pre_len = xs.length
  let fork_len = fork xs:
    for i in 0..400:
      xs := xs.push { id: 9000 + i, hp: 1, x: 0.0f64, y: 0.0f64, z: 0.0f64, flags: 0 }
    let (xs_p, _) = xs.pop
    xs := xs_p
    return xs.length
  let post_sum: U32 = 0
  for { id, hp, flags } in xs:
    post_sum := self + id + hp + flags

  // Nested container field inside SoA record (tests holdsContainer noteStore + deep copy!)
  let bags: %[BagRec] = %[]
  for i in 0..40:
    bags := bags.push { id: i, items: #[i, i + 1] }
  let bags_cp = bags.copy
  let bags_sum: U32 = 0
  for b in bags_cp:
    let sub: U32 = 0
    for v in b.items:
      sub := self + v
    bags_sum := self + b.id + sub

  return #[
    pre_len,
    fork_len,
    xs.length,
    pop_sum,
    last_v.id,
    last_v.hp,
    xs_sum,
    post_sum,
    cp2.length,
    cp2_sum,
    bags_sum,
  ]
`,
    (guest) => {
      // Popped ids: 250..299 => sum = 50*(250+299)/2 = 13725
      let popSum = 0;
      for (let i = 250; i < 300; i++) popSum += i;
      // xs contains: 0..249 (id=i, hp=3i+1, flags=i%5), 1000..1019 (hp=5, flags=1), 2000..2029 (hp=7, flags=2)
      let xsSum = 0;
      let xsIdHp = 0;
      for (let i = 0; i < 250; i++) {
        xsSum += i + (i * 3 + 1) + (i % 5);
        xsIdHp += i + (i * 3 + 1);
      }
      for (let i = 0; i < 20; i++) {
        xsSum += (1000 + i) + 5 + 1;
        xsIdHp += (1000 + i) + 5;
      }
      for (let i = 0; i < 30; i++) {
        xsSum += (2000 + i) + 7 + 2;
        xsIdHp += (2000 + i) + 7;
      }
      // cp2 = xs + CONST_WIDE[0] (id=1, hp=10)
      const cp2Sum = xsIdHp + 1 + 10;
      // bags: i + i + (i + 1) = 3i + 1 for i=0..39 => 3*(39*40/2) + 40 = 2380
      let bagsSum = 0;
      for (let i = 0; i < 40; i++) bagsSum += i + i + (i + 1);
      const expected = [
        300, // pre_len
        699, // fork_len (300 + 400 - 1)
        300, // xs.length rolled back
        popSum,
        2, // last_v.id (CONST_WIDE[1])
        20, // last_v.hp
        xsSum,
        xsSum, // post_sum unchanged after fork rollback
        301, // cp2.length
        cp2Sum,
        bagsSum,
      ];
      assert.deepEqual(
        Array.from(guest.call("test_soa_cached_lifecycle", null) as Uint32Array),
        expected,
      );
      // Run twice to ensure CONST_WIDE persists across invocations
      assert.deepEqual(
        Array.from(guest.call("test_soa_cached_lifecycle", null) as Uint32Array),
        expected,
      );
    },
  );
});
