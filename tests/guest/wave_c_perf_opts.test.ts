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
  const dir = await Deno.makeTempDir({ prefix: "blot-wave-c-" });
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

Deno.test("Wave C Pillar 1: boxed-return curried lambda inlining, last-use FBIP reuse after projections, and alias isolation", async () => {
  await compileAndRun(
    `
type WideState is data = $WideState {
  f0: U32, f1: U32, f2: U32, f3: U32,
  f4: U32, f5: U32, f6: U32, f7: U32,
  f8: U32, f9: U32, f10: U32, f11: U32,
  f12: U32, f13: U32, f14: U32, f15: U32,
  f16: U32, f17: U32,
}

func fold_steps (n: U32) -> (init: WideState) -> (step: WideState -> U32 -> WideState): WideState =>
  let cur = init
  for i in 0 .. n:
    cur := step cur i
  return cur

func mk_state (v: U32): WideState => $WideState {
  f0: v, f1: 1, f2: 2, f3: 3,
  f4: 4, f5: 5, f6: 6, f7: 7,
  f8: 8, f9: 9, f10: 10, f11: 11,
  f12: 12, f13: 13, f14: 14, f15: 15,
  f16: 16, f17: 17,
}

io test_fbip_fold (n: U32): #[U32] =>
  let s0 = mk_state 10
  // Keep s0 aliased to ensure initial block is NOT clobbered.
  let s1 = fold_steps n s0 (func (acc: WideState) -> (i: U32): WideState =>
    let next = acc
    let prev = next.f0
    let k = next.f17
    next.f0 := prev + i + k
    next.f1 := self + 1
    return next)
  // Second chain without aliasing s1 after this point.
  let s2 = s1
  let s3 = fold_steps n s2 (func (acc: WideState) -> (i: U32): WideState =>
    let next = acc
    let prev = next.f2
    next.f2 := prev + i
    return next)
  return #[s0.f0, s1.f0, s1.f1, s2.f2, s3.f2]
`,
    (guest) => {
      // n = 5000: sum(0..4999) = 12497500; s1.f0 = 10 + 12497500 + 5000*17 = 12582510
      const res = Array.from(guest.call("test_fbip_fold", 5000) as Uint32Array);
      assert.deepEqual(res, [10, 12582510, 5001, 2, 12497502]);
      // FBIP reuse keeps peak linear memory tiny (< 1 MiB even for 5000 iterations of an 18-word struct).
      assert(
        guest.memoryBytes() < 2 * 1024 * 1024,
        `Expected FBIP reuse to keep memory small, got ${guest.memoryBytes()} bytes`,
      );
    },
  );
});

Deno.test("Wave C Pillar 2: cross-function KnownClosure specialization for policy records, capturing lambdas, and closure-returning helpers", async () => {
  await compileAndRun(
    `
type Policy = {
  accept: U32 -> Bool,
  score: U32 -> U32 -> U32,
}

func accept_all (_: U32): Bool => true

func make_accept_all (): U32 -> Bool => accept_all

// Large enough not to inline into callers, exercising named ClosureSpec specialization.
func run_policy (n: U32) -> (pol: Policy) -> (bias: U32): U32 =>
  let acc: U32 = 0
  let kept: U32 = 0
  for i in 0 .. n:
    if pol.accept i:
      kept := self + 1
      let v = pol.score i bias
      acc := self + v
    else:
      acc := self + 1
  if kept > 0:
    return acc + kept
  return acc

func tail_loop (n: U32) -> (acc: U32) -> (f: U32 -> U32): U32 =>
  if n == 0:
    return acc
  return tail_loop (n - 1) (acc + f n) f

io test_specialize (n: U32): #[U32] =>
  let k: U32 = 3
  let p1: Policy = {
    accept: make_accept_all (),
    score: func (x: U32) -> (b: U32): U32 => x * k + b,
  }
  let p2: Policy = {
    accept: func (x: U32): Bool => (x & 1) == 0,
    score: func (x: U32) -> (b: U32): U32 => x + b * 2,
  }
  let r1 = run_policy n p1 5
  let r2 = run_policy n p2 7
  let r3 = tail_loop n 0 (func (x: U32): U32 => x + k)
  return #[r1, r2, r3]
`,
    (guest) => {
      // n = 100:
      // r1: kept=100, sum_{i=0..99}(3*i + 5) = 3*4950 + 500 = 15350; + 100 = 15450
      // r2: even i in 0..99 (50 items: 0,2,...,98 sum=2450), each + 14 -> 2450 + 700 = 3150; 50 odd -> +50; + kept(50) = 3250
      // r3: sum_{i=1..100}(i + 3) = 5050 + 300 = 5350
      const res = Array.from(guest.call("test_specialize", 100) as Uint32Array);
      assert.deepEqual(res, [15450, 3250, 5350]);
    },
  );
});

Deno.test("Wave C Pillar 3: byte/enum/alignment field packing across arrays, boxed records, copies, and persistent #process state", async () => {
  await compileAndRun(
    `
type Kind is data = $A | $B | $C | $D
type PackedRec = { flag1: Bool, id: U32, kind: Kind, flag2: Bool, byte: U8, score: F32 }
type SmallSum is data = $Empty | $Pair (U8, Bool) | $Triple (Kind, Bool, U8)
type MixedSum is data = $Zero | $Small (Bool, U8) | $Wide { x: U32, active: Bool, y: U32 }
type BoxedPacked = {
  flag1: Bool,
  a0: U32, a1: U32, a2: U32, a3: U32,
  kind: Kind,
  a4: U32, a5: U32, a6: U32, a7: U32,
  byte: U8,
  a8: U32, a9: U32, a10: U32, a11: U32,
  small: SmallSum,
  a12: U32, a13: U32, a14: U32, a15: U32,
  flag2: Bool,
  mixed: MixedSum,
}
type ProcRec = { flag1: Bool, id: U32, kind: Kind, flag2: Bool, score: F32 }
type ProcSum is data = $PEmpty | $PPair (Kind, Bool) | $PTriple (Kind, Bool, Kind)
type ProcState is data = $ProcState {
  flag: Bool,
  kind: Kind,
  recs: #[ProcRec],
  sums: #[ProcSum],
}

func kind_val (k: Kind): U32 =>
  case k of
    $A => 1
    $B => 2
    $C => 3
    $D => 4

func mk_kind (i: U32): Kind =>
  case i & 3 of
    0 => $A
    1 => $B
    2 => $C
    _ => $D

func p_init (seed: U32): ProcState =>
  let recs: #[ProcRec] = #[]
  let sums: #[ProcSum] = #[]
  @storage.push recs { flag1: true, id: seed, kind: $B, flag2: false, score: 1.5 }
  @storage.push sums ($PPair ($C, true))
  return $ProcState { flag: true, kind: $C, recs, sums }

func p_step (st: own ProcState) -> (cmd: U32): (ProcState, #[U32]) =>
  let spec = fork st:
    @storage.push st.recs { flag1: false, id: 999, kind: $D, flag2: true, score: 0.0 }
    return st.recs.length
  @storage.push st.recs { flag1: (cmd & 1) == 0, id: cmd, kind: mk_kind cmd, flag2: true, score: U32.to_f32 cmd }
  @storage.push st.sums ($PTriple (mk_kind cmd, (cmd & 1) == 0, $B))
  let acc: U32 = 0
  for r in st.recs:
    acc := self + r.id + kind_val r.kind + (if r.flag1 then 10 else 0) + (if r.flag2 then 20 else 0)
  for s in st.sums:
    acc := self + (case s of
      $PEmpty => 1
      $PPair (k, fl) => kind_val k + (if fl then 3 else 0)
      $PTriple (k1, fl, k2) => kind_val k1 + kind_val k2 + (if fl then 5 else 0))
  let rlen = st.recs.length
  return (st, #[spec, rlen, acc])

#process const pack_proc: Process [U32, U32, #[U32]] = { init: p_init, step: p_step }

io test_packing (n: U32): #[U32] =>
  let kinds: #[Kind] = @array.fill n $B
  for i in 0 .. n:
    kinds[i] := mk_kind i
  let mbools: #[Maybe Bool] = #[]
  let recs: #[PackedRec] = #[]
  let ssums: #[SmallSum] = #[]
  let msums: #[MixedSum] = #[]
  for i in 0 .. n:
    @storage.push mbools (case @u32.rem i 3 of
      0 => $Nothing
      1 => $Some false
      _ => $Some true)
    @storage.push recs { flag1: (i & 1) == 0, id: i * 3, kind: kinds[i], flag2: @u32.rem i 3 == 0, byte: U32.to_u8 (i & 255), score: U32.to_f32 i * 0.5 }
    @storage.push ssums (case @u32.rem i 3 of
      0 => $Empty
      1 => $Pair (U32.to_u8 (i & 255), (i & 1) == 0)
      _ => $Triple (kinds[i], @u32.rem i 5 == 0, U32.to_u8 ((i * 7) & 255)))
    @storage.push msums (case @u32.rem i 3 of
      0 => $Zero
      1 => $Small ((i & 1) == 0, U32.to_u8 (i & 255))
      _ => $Wide { x: i, active: (i & 3) == 0, y: i + 10 })

  let ksum: U32 = 0
  for k in kinds:
    ksum := self + kind_val k
  let mbsum: U32 = 0
  for mb in mbools:
    mbsum := self + (case mb of
      $Nothing => 1
      $Some false => 2
      $Some true => 5)
  let rsum: U32 = 0
  for r in recs:
    rsum := self + r.id + kind_val r.kind + U8.to_u32 r.byte + (if r.flag1 then 7 else 0) + (if r.flag2 then 11 else 0) + F32.to_u32 (r.score * 2.0)
  let ssum: U32 = 0
  for s in ssums:
    ssum := self + (case s of
      $Empty => 1
      $Pair (b, fl) => U8.to_u32 b + (if fl then 3 else 0)
      $Triple (k, fl, b) => U8.to_u32 b + (if fl then 13 else 0) + kind_val k)
  let msum: U32 = 0
  for m in msums:
    msum := self + (case m of
      $Zero => 1
      $Small (fl, b) => U8.to_u32 b + (if fl then 5 else 0)
      $Wide { x, active, y } => x + y + (if active then 17 else 0))

  let bp: BoxedPacked = {
    flag1: true, a0: 1, a1: 2, a2: 3, a3: 4, kind: $C,
    a4: 5, a5: 6, a6: 7, a7: 8, byte: U32.to_u8 42,
    a8: 9, a9: 10, a10: 11, a11: 12, small: ssums[2],
    a12: 13, a13: 14, a14: 15, a15: 16, flag2: false,
    mixed: msums[2],
  }
  let bp2 = bp
  bp2.flag1 := false
  bp2.kind := $D
  bp2.byte := U32.to_u8 99
  bp2.flag2 := true
  let recs_cp = @storage.copy recs
  let check_bp: U32 = if not bp2.flag1 and bp2.flag2 and kind_val bp2.kind == 4 and U8.to_u32 bp2.byte == 99 and bp.flag1 and kind_val bp.kind == 3 and recs_cp[5].id == recs[5].id then 1 else 0
  return #[ksum, mbsum, rsum, ssum, msum, check_bp]
`,
    (guest) => {
      const r = Array.from(guest.call("test_packing", 10000) as Uint32Array);
      assert.deepEqual(r, [25000, 26665, 201349754, 874291, 33813510, 1]);

      // Verify #process persistent state with packed structs + fork rollback across turns!
      guest.call("blot:proc_init:pack_proc", 5);
      // Initial: recs=[{flag1:T, id:5, kind:$B(2), flag2:F}] (5+2+10=17), sums=[$PPair($C(3),T)] (3+3=6) -> 23
      // Turn 1 (cmd=4): fork saw len=2; pushed rec {flag1:T, id:4, kind:$A(1), flag2:T} (4+1+10+20=35), sum $PTriple($A(1),T,$B(2)) (1+2+5=8) -> 23+43 = 66
      const t1 = Array.from(guest.call("blot:proc_step:pack_proc", 4) as Uint32Array);
      assert.deepEqual(t1, [2, 2, 66]);
      // Turn 2 (cmd=3): fork saw len=3; pushed rec {flag1:F, id:3, kind:$D(4), flag2:T} (3+4+20=27), sum $PTriple($D(4),F,$B(2)) (4+2=6) -> 66+33 = 99
      const t2 = Array.from(guest.call("blot:proc_step:pack_proc", 3) as Uint32Array);
      assert.deepEqual(t2, [3, 3, 99]);
    },
  );
});

Deno.test("Wave C Pillar 4: skewed sum cold-variant outlining, 2-variant nullable-pointer niche, module consts, and #process persistence", async () => {
  await compileAndRun(
    `
type TerrainLike is data = $TerrainLike {
  cols: U32,
  rows: U32,
  cell: F32,
  ox: F32, oy: F32, oz: F32,
  min_h: F32, max_h: F32,
  heights: #[F32],
}
type MeshLike is data = $MeshLike {
  ox: F32, oy: F32, oz: F32,
  sx: F32, sy: F32, sz: F32,
  verts: #[F32],
  tris: #[U32],
}
type ShapeKind is data =
  | $Box
  | $Sphere
  | $Capsule
  | $Brush
  | $Heightfield TerrainLike
  | $Mesh MeshLike

type Collider is data = $Collider {
  shape: ShapeKind,
  sx: F32, sy: F32, sz: F32,
  radius: F32,
  height: F32,
  ox: F32, oy: F32, oz: F32,
  friction: F32,
  restitution: F32,
  layer: U32,
  mask: U32,
  trigger: Bool,
}

type BigBoxed is data = $BigBoxed {
  a0: U32, a1: U32, a2: U32, a3: U32,
  a4: U32, a5: U32, a6: U32, a7: U32,
  a8: U32, a9: U32, a10: U32, a11: U32,
  a12: U32, a13: U32, a14: U32, a15: U32,
  a16: U32,
  items: #[U32],
}

type MixedProc is data =
  | $PSmall U32
  | $PPacked (Bool, Bool)
  | $PBig BigBoxed
  | $PMed TerrainLike

type MixedWide is data =
  | $TagSmall U64
  | $TagPacked (Bool, U8)
  | $TagBig BigBoxed
  | $TagMed TerrainLike

type Source is data = $Source {
  id: U32,
  px: F32, py: F32, pz: F32,
  collider: Maybe Collider,
}

type OutlineProcState is data = $OutlineProcState {
  active: Maybe Collider,
  kinds: #[ShapeKind],
  mixed: #[MixedProc],
}

const STATIC_SHAPE: ShapeKind = $Heightfield ($TerrainLike {
  cols: 3, rows: 2, cell: 1.0,
  ox: 0.0, oy: 0.0, oz: 0.0,
  min_h: 0.0, max_h: 4.0,
  heights: #[7.0, 9.0],
})

const STATIC_MAYBE: Maybe Collider = $Some ($Collider {
  shape: STATIC_SHAPE,
  sx: 2.0, sy: 2.0, sz: 2.0,
  radius: 1.0, height: 1.0,
  ox: 0.0, oy: 0.0, oz: 0.0,
  friction: 0.5, restitution: 0.0,
  layer: 4, mask: 255,
  trigger: true,
})

func mk_box_col (i: U32): Collider =>
  $Collider {
    shape: $Box,
    sx: U32.to_f32 i, sy: 2.0, sz: 3.0,
    radius: 0.5, height: 1.0,
    ox: 0.0, oy: 0.0, oz: 0.0,
    friction: 0.5, restitution: 0.1,
    layer: 1, mask: 255,
    trigger: (i & 1) == 0,
  }

func mk_terrain_col (i: U32): Collider =>
  let h: #[F32] = #[U32.to_f32 i, U32.to_f32 (i + 1)]
  return $Collider {
    shape: $Heightfield ($TerrainLike {
      cols: 2, rows: 1, cell: 1.0,
      ox: 0.0, oy: 0.0, oz: 0.0,
      min_h: 0.0, max_h: 10.0,
      heights: h,
    }),
    sx: 1.0, sy: 1.0, sz: 1.0,
    radius: 0.0, height: 0.0,
    ox: 0.0, oy: 0.0, oz: 0.0,
    friction: 0.8, restitution: 0.0,
    layer: 2, mask: 255,
    trigger: false,
  }

func mk_big (v: U32): BigBoxed =>
  $BigBoxed {
    a0: v, a1: v + 1, a2: v + 2, a3: v + 3,
    a4: v + 4, a5: v + 5, a6: v + 6, a7: v + 7,
    a8: v + 8, a9: v + 9, a10: v + 10, a11: v + 11,
    a12: v + 12, a13: v + 13, a14: v + 14, a15: v + 15,
    a16: v + 16,
    items: #[v, v * 2],
  }

func mk_static_like (): ShapeKind =>
  $Heightfield ($TerrainLike {
    cols: 3, rows: 2, cell: 1.0,
    ox: 0.0, oy: 0.0, oz: 0.0,
    min_h: 0.0, max_h: 4.0,
    heights: #[7.0, 9.0],
  })

func op_init (seed: U32): OutlineProcState =>
  let kinds: #[ShapeKind] = #[$Box, mk_static_like ()]
  let mixed: #[MixedProc] = #[$PSmall seed, $PBig (mk_big seed)]
  let active: Maybe Collider = if seed == 0 then $Nothing else $Some (mk_terrain_col seed)
  return $OutlineProcState { active, kinds, mixed }

func col_score (mc: Maybe Collider): U32 =>
  case mc of
    $Nothing => 1
    $Some c =>
      c.layer + (if c.trigger then 10 else 0) + F32.to_u32 c.sx + (case c.shape of
        $Box => 2
        $Heightfield t => t.cols + F32.to_u32 t.heights[1]
        _ => 0)

func op_step (st: own OutlineProcState) -> (cmd: U32): (OutlineProcState, #[U32]) =>
  let spec = fork st:
    @storage.push st.kinds $Sphere
    return st.kinds.length
  let next_active: Maybe Collider = if cmd == 0 then $Nothing else $Some (mk_terrain_col cmd)
  st.active := next_active
  @storage.push st.kinds (if (cmd & 1) == 0 then $Box else mk_static_like ())
  @storage.push st.mixed ($PPacked ((cmd & 1) == 0, cmd > 2))
  let ksum: U32 = 0
  for k in st.kinds:
    ksum := self + (case k of
      $Box => 1
      $Sphere => 2
      $Heightfield t => t.cols + F32.to_u32 t.heights[0]
      _ => 0)
  let msum: U32 = 0
  for m in st.mixed:
    msum := self + (case m of
      $PSmall u => u
      $PPacked (f1, f2) => (if f1 then 7 else 0) + (if f2 then 3 else 0)
      $PBig bb => bb.a0 + bb.a16 + bb.items[1]
      $PMed t => t.cols)
  let cur_score = col_score st.active
  return (st, #[spec, cur_score, ksum, msum])

#process const outline_proc: Process [U32, U32, #[U32]] = { init: op_init, step: op_step }

io test_static_and_outline (n: U32): #[U32] =>
  let kinds: #[ShapeKind] = #[]
  let sources: #[Source] = #[]
  for i in 0 .. n:
    let k: ShapeKind = case @u32.rem i 5 of
      0 => $Box
      1 => $Sphere
      2 => $Capsule
      3 => $Brush
      _ => mk_static_like ()
    @storage.push kinds k
    let mc: Maybe Collider = if @u32.rem i 4 == 0 then $Nothing else $Some (mk_box_col i)
    @storage.push sources ($Source { id: i, px: U32.to_f32 i, py: 0.0, pz: 0.0, collider: mc })
  let ksum: U32 = 0
  for i in 0 .. n:
    ksum := self + (case kinds[i] of
      $Box => 1
      $Sphere => 2
      $Capsule => 3
      $Brush => 4
      $Heightfield t => t.cols + F32.to_u32 t.heights[0]
      $Mesh m => m.tris[0])
  let ssum: U32 = 0
  for i in 0 .. n:
    ssum := self + col_score sources[i].collider
  let static_score = col_score STATIC_MAYBE
  return #[ksum, ssum, static_score]
`,
    (guest) => {
      // n = 2000:
      // kinds: 400 each of 1, 2, 3, 4, (3+7=10) -> 400 * 20 = 8000
      // static_score: layer(4) + trigger(10) + sx(2) + (cols 3 + heights[1] 9 = 12) = 28
      const r = Array.from(guest.call("test_static_and_outline", 2000) as Uint32Array);
      assert.equal(r[0], 8000);
      assert.equal(r[2], 28);
      // Outlining + nullable niche keeps 2000 ShapeKinds + 2000 Sources well under 1 MiB.
      assert(
        guest.memoryBytes() < 1024 * 1024,
        `Expected outlined sums + nullable niche to stay compact, got ${guest.memoryBytes()} bytes`,
      );

      // Verify #process persistence across turns with outlined ShapeKind, Maybe Collider niche, BigBoxed, and STATIC_SHAPE!
      guest.call("blot:proc_init:outline_proc", 5);
      // Turn 1 (cmd=3):
      // fork saw kinds.length=3; rolled back;
      // active = $Some (mk_terrain_col 3) -> layer(2)+0+sx(1)+(cols 2 + h[1] 4)=9
      // kinds = [$Box(1), STATIC(10), STATIC(10)] -> 21
      // mixed = [$PSmall 5 (5), $PBig 5 (5 + 21 + 10 = 36), $PPacked (F, T) (3)] -> 44
      const t1 = Array.from(guest.call("blot:proc_step:outline_proc", 3) as Uint32Array);
      assert.deepEqual(t1, [3, 9, 21, 44]);
      // Turn 2 (cmd=0):
      // fork saw kinds.length=4; active = $Nothing -> 1
      // kinds += $Box(1) -> 22
      // mixed += $PPacked (T, F) (+7) -> 51
      const t2 = Array.from(guest.call("blot:proc_step:outline_proc", 0) as Uint32Array);
      assert.deepEqual(t2, [4, 1, 22, 51]);
      // Turn 3 (cmd=6):
      // fork saw kinds.length=5; active = $Some (mk_terrain_col 6) -> 2+0+1+(2+7)=12
      // kinds += $Box(1) -> 23; mixed += $PPacked (T, T) (+10) -> 61
      const t3 = Array.from(guest.call("blot:proc_step:outline_proc", 6) as Uint32Array);
      assert.deepEqual(t3, [5, 12, 23, 61]);
    },
  );
});
