import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("vNext 3A: nominal traits, output types, const Type.Trait, dot-calls, operators, *T and array lift", async () => {
  await compileAndRun(
    `
type Eq a is trait = { eq: a -> a -> Bool }
type Boxer a is trait = { wrap: a -> #[a] }
type Mul left { right, out } is trait = { mul: left -> right -> out }
type Collection c { item } is trait = {
  len: c -> U32,
  get: c -> U32 -> item,
}

type Vec2 is data = $Vec2 { x: U32, y: U32 }

func Vec2.scale (v: Vec2) -> (k: U32): Vec2 => $Vec2 { x: v.x * k, y: v.y * k }

const U32.Eq: Eq U32 = { eq: U32.eq }
const U32.Boxer: Boxer U32 = { wrap: func v => #[v] }
const U32.Mul: Mul U32 { right: U32, out: U32 } = { mul: U32.mul }
const Vec2.Eq: Eq Vec2 = { eq: func a -> b => a.x == b.x and a.y == b.y }
const Vec2.Mul: Mul Vec2 { right: U32, out: Vec2 } = { mul: Vec2.scale }

const Array.Collection: Collection #[a] { item: a } = {
  len: func xs => @array.length xs,
  get: func xs -> i => @array.get xs i,
}

const Array.Eq: Eq #[a] where { Eq a } = {
  eq: func xs -> ys =>
    if xs.length != ys.length:
      return false
    for i in 0..xs.length:
      if not (xs[i].eq ys[i]):
        return false
    return true
}

func square (x: a): a where { Mul a { right: a, out: a } } => x * x

func first_plus_len (xs: c): U32 where { Collection c { item: U32 } } =>
  xs.get 0 + xs.len

func first_item (xs: c): c.item where { Collection c } => xs.get 0

func same_generic (x: a) -> (y: a): Bool where { Eq a } => x.eq y

func use_explicit_dict (d: Eq a) -> (x: a) -> (y: a): Bool => d.eq x y

io main (): U32 =>
  let a = square 7
  let v = $Vec2 { x: 3, y: 4 }
  let v2 = v * 5
  let eq_vec = if v.eq ($Vec2 { x: 3, y: 4 }) then 1 else 0
  let eq_gen = if same_generic v ($Vec2 { x: 3, y: 4 }) then 1 else 0
  let eq_dict = if use_explicit_dict Vec2.Eq v2 ($Vec2 { x: 15, y: 20 }) then 1 else 0
  let xs: #[U32] = #[10, 20, 30]
  let fl = first_plus_len xs
  let fi = first_item xs
  // Read-only lift to *T
  let fv: *Vec2 = freeze ($Vec2 { x: 3, y: 4 })
  let fv2: *Vec2 = freeze ($Vec2 { x: 3, y: 4 })
  let eq_shared = if fv.eq fv2 then 1 else 0
  // Array trait lift: #[U32] and *#[U32] covered by Array.Eq and Array.Collection
  let grow: #[U32] = #[10, 20, 30]
  let eq_grow = if grow.eq grow then 1 else 0
  let fl_grow = first_plus_len grow
  let frozen_arr: *#[U32] = freeze grow
  let eq_frozen_arr = if frozen_arr.eq frozen_arr then 1 else 0
  let boxed: #[U32] = Boxer.wrap 9
  return a + v2.x + v2.y + eq_vec + eq_gen + eq_dict + fl + fi + eq_shared + eq_grow + fl_grow + eq_frozen_arr + boxed[0]
`,
    (guest) => {
      // 49 + 15 + 20 + 1 + 1 + 1 + 13 + 10 + 1 + 1 + 13 + 1 + 9 = 135
      equal(guest.call("main", null), 135);
    },
  );
});

Deno.test("vNext 3A: missing trait impl is rejected", async () => {
  await compileExpectedFailure(
    `
type Eq a is trait = { eq: a -> a -> Bool }
type Foo is data = $Foo U32
func same (x: a) -> (y: a): Bool where { Eq a } => x.eq y
io main (): U32 =>
  return if same ($Foo 1) ($Foo 1) then 1 else 0
`,
    "missing_implementation",
  );
});

Deno.test("vNext 3B: composable @handle, handler bindings, linear shadowing, Layer bundling, outer effects", async () => {
  await compileAndRun(
    `
type Log is effect = { write: U32 -> Unit }
type State s is effect = {
  get: Unit -> s,
  put: s -> Unit,
}
type Outer is effect = { emit: U32 -> Unit }
type Ask is effect = { get: Unit -> U32 }

const quiet: Log = { write: func _ => () }
const fixed_ask: Ask = { get: func () => 7 }
const quiet_outer: Outer = { emit: func _ => () }
const quiet_env = layer quiet fixed_ask
const triple_env = layer quiet fixed_ask
  .layer quiet_outer

func emit_pair (a: U32) -> (b: U32): Unit !{ Log } =>
  use Log.write a
  use Log.write b
  return ()

func run_with_log (h: Log) -> (x: U32): U32 =>
  h.run (func () => use Log.write x)
  return x + 1

func run_with_env (env: Layer [Log, Ask]) -> (x: U32): U32 =>
  return (func v =>
    use Log.write v
    use k <- Ask.get ()
    return v + k
  ).handle env
    .run x

func bump_state (delta: U32): U32 !{ State U32, Log } =>
  use cur <- State.get ()
  let next = cur + delta
  use State.put next
  use Log.write next
  return next

func push_grow (a: own #[U32]) -> (x: U32): #[U32] =>
  @storage.push a x
  return a

io main (): U32 =>
  // 1. Pre-built effect record, passing Log/Layer as parameter, 3-layer Layer.layer, and 'with' usable as an identifier
  let with = 9
  let r1 = run_with_log quiet with
  let r_env = run_with_env quiet_env 3
  let r_triple = triple_env.run (func () =>
    use Log.write 1
    use Outer.emit 2
    use k <- Ask.get ()
    return k
  )

  // 2. Local handlers linearly shadowing outer U32 and dynamic array, chained via .handle ... .run
  let log: #[U32] = #[]
  let n = 10
  handler h_log: Log =>
    write x => log := push_grow self x
  handler h_state: State U32 =>
    get () => n
    put v => n := v
  let total = (func () =>
    use a <- bump_state 5
    use b <- bump_state 7
    return a + b
  ).handle h_log
    .handle h_state
    .run ()

  // 3. Handler performing an outer effect composed via .handle chain
  let outer_sum = 0
  handler h_outer: Outer =>
    emit x => outer_sum := outer_sum + x
  handler h_log2: Log =>
    write x => use Outer.emit (x * 2)
  (func () => use emit_pair 3 4).handle h_log2
    .handle h_outer
    .run ()

  // 4. handler + @handle inside for loop with early break
  let acc = 0
  for i in 0..10:
    handler h_acc: Log =>
      write x => acc := acc + x
    @handle h_acc (func () => use Log.write i)
    if i == 4:
      break

  // 5. Direct argument passing to .run value + local stateful layer bundling
  let log2: #[U32] = #[]
  let m = 20
  handler h_log3: Log =>
    write x => log2 := push_grow self x
  handler h_state2: State U32 =>
    get () => m
    put v => m := v
  let local_env = layer h_log3 h_state2
  let bumped = bump_state.handle local_env
    .run 4

  // r1=10, r_env=10, r_triple=7, total=37, n=22, log.length=2, log[0]+log[1]=37, outer_sum=14, acc=10, bumped=24, m=24, log2[0]=24
  return r1 + r_env + r_triple + total + n + log.length + log[0] + log[1] + outer_sum + acc + bumped + m + log2[0]
`,
    (guest) => {
      // 10 + 10 + 7 + 37 + 22 + 2 + 15 + 22 + 14 + 10 + 24 + 24 + 24 = 221
      equal(guest.call("main", null), 221);
    },
  );
});

Deno.test("vNext 3B: fork rolls back mutations to handler-shadowed outer cell", async () => {
  await compileAndRun(
    `
type State s is effect = {
  get: Unit -> s,
  put: s -> Unit,
}

io main (): U32 =>
  let n = 10
  let dummy = #[1]
  handler h_state: State U32 =>
    get () => n
    put v => n := v
  let (preview, after) = (func (own d) =>
    use p <- fork d:
      use State.put 99
      use g <- State.get ()
      return g
    use g2 <- State.get ()
    return (p, g2)
  ).handle h_state
    .run dummy
  // preview == 99, after == 10, n == 10
  return preview * 1000 + after * 10 + n
`,
    (guest) => {
      equal(guest.call("main", null), 99000 + 100 + 10);
    },
  );
});

Deno.test("vNext 3B: body cannot read or rebind a local shadowed by an active handler", async () => {
  await compileExpectedFailure(
    `
type Log is effect = { write: U32 -> Unit }
io main (): U32 =>
  let count = 0
  handler h: Log =>
    write x => count := count + x
  (func () =>
    use Log.write 1
    let bad = count
    return ()
  ).handle h
    .run ()
  return count
`,
    "borrow_conflict",
  );
});

Deno.test("vNext 3B: stateful handler cannot escape its defining frame", async () => {
  await compileExpectedFailure(
    `
type Log is effect = { write: U32 -> Unit }
func leak (): Log =>
  let count = 0
  handler h: Log =>
    write x => count := count + x
  return h
io main (): U32 => return 0
`,
    "borrow_conflict",
  );
});

Deno.test("vNext 3B: handler Foreign is rejected as sealed_effect", async () => {
  await compileExpectedFailure(
    `
io main (): U32 =>
  handler h: Foreign =>
    x () => ()
  return 0
`,
    "sealed_effect",
  );
});

Deno.test("vNext 3B: contextual generic effect inference rejects mismatched result type", async () => {
  await compileExpectedFailure(
    `
type State s is effect = {
  get: Unit -> s,
  put: s -> Unit,
}
io main (): U32 =>
  let n: U32 = 10
  handler h_state: State U32 =>
    get () => n
    put v => n := v
  let g: Bool = (func () =>
    use x <- State.get ()
    return x
  ).handle h_state
    .run ()
  return if g then 1 else 0
`,
    "type_mismatch",
  );
});

Deno.test("vNext 3C: @[expr] tags, field defaults, #for #fields, #if/#else, val.(field), heterogeneous traits", async () => {
  await compileAndRun(
    `
type Skip is data = $Skip
type Meta is data = $Since U32 | $Weight U32

type Score a is trait = { score: a -> U32 }
const U32.Score: Score U32 = { score: func x => x }
const F32.Score: Score F32 = { score: func x => @f32.to_u32 x }

@[Skip]
type Player is data = $Player {
  @[$Skip]
  name: #[U32] = "anon",
  @[$Since 3]
  hp: U32 = 100,
  @[$Weight 7]
  ratio: F32 = 2.0,
  bonus: U32,
}

func sum_scored (val: t): U32 =>
  let acc = 0
  #for field in #fields t:
    #if not (field.has_tag Skip):
      acc := acc + Score.score val.(field)
  return acc

func sum_dot_scored (val: t): U32 =>
  let acc = 0
  #for field in #fields t:
    #if not (field.has_tag $Skip):
      acc := acc + val.(field).score
  return acc

func inspect_player_meta (): U32 =>
  let total = 0
  #for field in #fields Player:
    total := total + field.name.length
    #if field.has_default:
      total := total + 10
    #else:
      total := total + 1
    #if field.has_tag $Since:
      total := total + field.tag $Since
    #if field.has_tag ($Weight 7):
      total := total + 100
  return total

// Verify nominal #fields iterates in declared order (name, hp, ratio, bonus),
// NOT alphabetical order (bonus, hp, name, ratio).
func player_field_order_code (): U32 =>
  let code = 0
  #for field in #fields Player:
    code := code * 10 + field.name.length
  return code

func sum_structural (r: { a: U32, b: U32 }): U32 =>
  let s = 0
  #for f in #fields { a: U32, b: U32 }:
    s := s + r.(f)
  return s

io main (): U32 =>
  // Omit defaulted fields (name, hp, ratio), supply only required bonus
  let p1 = $Player { bonus: 5 }
  // Override defaulted hp while omitting name & ratio
  let p2 = $Player { hp: 40, bonus: 3 }
  // sum_scored p1 = 100 + 2 + 5 = 107
  let s1 = sum_scored p1
  // sum_dot_scored p2 = 40 + 2 + 3 = 45
  let s2 = sum_dot_scored p2
  // inspect_player_meta:
  //   name: len 4 + default 10 = 14
  //   hp: len 2 + default 10 + since 3 = 15
  //   ratio: len 5 + default 10 + weight7 100 = 115
  //   bonus: len 5 + non-default 1 = 6
  //   sum = 150
  let meta = inspect_player_meta ()
  // sum_structural = 11 + 22 = 33
  let sr = sum_structural { a: 11, b: 22 }
  // player_field_order_code: name(4), hp(2), ratio(5), bonus(5) = 4255
  return s1 + s2 + meta + sr + p1.name.length + player_field_order_code ()
`,
    (guest) => {
      // 107 + 45 + 150 + 33 + 4 + 4255 = 4594
      equal(guest.call("main", null), 4594);
    },
  );
});

Deno.test("vNext 3C: #for #variants with variant.name, variant.index, variant.has_tag, variant.tag", async () => {
  await compileAndRun(
    `
type Deprecated is data = $Deprecated
type Weight is data = $Weight U32

type Color is data =
  @[$Weight 10]
  $Red
  | @[Deprecated]
  @[$Weight 20]
  $Green
  | $Blue U32

func inspect_colors (): U32 =>
  let acc = 0
  #for v in #variants Color:
    acc := acc + v.index + v.name.length
    #if v.has_tag Deprecated:
      acc := acc + 1000
    #if v.has_tag $Weight:
      acc := acc + v.tag $Weight
  return acc

io main (): U32 =>
  // Red: index 0 + len 3 + weight 10 = 13
  // Green: index 1 + len 5 + deprecated 1000 + weight 20 = 1026
  // Blue: index 2 + len 4 = 6
  // Total = 1045
  return inspect_colors ()
`,
    (guest) => {
      equal(guest.call("main", null), 1045);
    },
  );
});

Deno.test("vNext 3C: omitting a required non-defaulted field is rejected", async () => {
  await compileExpectedFailure(
    `
type Boxed is data = $Boxed { a: U32 = 1, b: U32 }
io main (): U32 =>
  let x = $Boxed { a: 2 }
  return x.a
`,
    "missing_record_field",
  );
});

Deno.test("vNext 3C: field default type mismatch is rejected", async () => {
  await compileExpectedFailure(
    `
type Bad is data = $Bad { hp: U32 = true }
io main (): U32 =>
  let x = $Bad { hp: 1 }
  return x.hp
`,
    "type_mismatch",
  );
});

Deno.test("vNext 3A+3B+3C: effectful final-arrow trait with scoped with and #for #fields", async () => {
  await compileAndRun(
    `
type Emit a is effect = a -> Unit
type Encode a is trait = { encode: a -> Unit ! {Emit U32} }
const U32.Encode: Encode U32 = { encode: func x => use Emit x }
const Bool.Encode: Encode Bool = { encode: func b => use Emit (if b then 1 else 0) }
type Packet is data = $Packet { id: U32, flag: Bool, count: U32 = 5 }

func encode_packet (p: Packet): Unit ! {Emit U32} =>
  #for field in #fields Packet:
    use Encode.encode p.(field)
  return ()

io main (): U32 =>
  let total = 0
  let p = $Packet { id: 10, flag: true }
  handler h_emit: Emit U32 => v => total := total + v
  encode_packet.handle h_emit
    .run p
  return total
`,
    (guest) => {
      // 10 + 1 + 5 = 16
      equal(guest.call("main", null), 16);
    },
  );
});

Deno.test("comptime writes specialize self and preserve nested owned paths", async () => {
  await compileAndRun(
    `
type Bump a is trait = { bump: a -> a }
const U32.Bump: Bump U32 = { bump: func x => x + 1 }
const F32.Bump: Bump F32 = { bump: func x => x + 0.5 }
const Bool.Bump: Bump Bool = { bump: func x => not x }

type Small is data = $Small { ratio: F32, flag: Bool, count: U32 }
type Large is data = $Large {
  a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32,
  i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32,
  ratio: F32, flag: Bool,
}
type Vec is data = $Vec { x: U32, y: U32 }
type Pair = { right: Vec, left: Vec }

func bump (value: t): t =>
  let r = value
  #for field in #fields t:
    r.(field) := Bump.bump self
  return r

io main (): Bool =>
  let r: { n: U32, m: U32 } = { n: 3, m: 5 }
  #for field in #fields { n: U32, m: U32 }:
    r.(field) := self + 1
  let tiny = bump ($Small { ratio: 1.5, flag: true, count: 7 })
  let big = bump ($Large {
    a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9,
    j: 10, k: 11, l: 12, m: 13, n: 14, o: 15, p: 16, ratio: 2.0, flag: false,
  })
  let large_rows = #[big]
  #for field in #fields Large:
    large_rows[0].(field) := Bump.bump self
  let outer = { inner: tiny }
  let rows = #[tiny, tiny]
  let pair: Pair = { right: $Vec { x: 8, y: 9 }, left: $Vec { x: 6, y: 7 } }
  #for field in #fields Small:
    rows[1].(field) := Bump.bump self
    outer.inner.(field) := Bump.bump self
  #for field in #fields Pair:
    pair.(field).x := self + 3
  return r.n == 4 and r.m == 6 and
    tiny.ratio == 2.0 and not tiny.flag and tiny.count == 8 and
    big.a == 2 and big.p == 17 and big.ratio == 2.5 and big.flag and
    large_rows[0].a == 3 and large_rows[0].p == 18 and not large_rows[0].flag and
    rows[0].count == 8 and rows[1].count == 9 and rows[1].flag and
    outer.inner.count == 9 and outer.inner.ratio == 2.5 and
    pair.right.x == 11 and pair.left.x == 9 and pair.left.y == 7
`,
    (guest) => equal(guest.call("main", null), true),
  );
});

Deno.test("comptime builders decode heterogeneous lanes in declaration order", async () => {
  await compileAndRun(
    `
type Skip is data = $Skip
type Vec2 is data = $Vec2 { x: F32, y: F32 }
type Packet is data = $Packet {
  ratio: F32, flag: Bool, id: U32, position: Vec2,
  @[$Skip]
  revision: U32 = 42,
}

type LaneDecode a is trait = { from_lanes: #[F32] -> U32 -> Maybe (a, U32) }
type LaneEncode a is trait = { to_lanes: a -> #[F32] }
type Default a is trait = { default: Unit -> a }

const U32.Default: Default U32 = { default: func () => 77 }
const U32.LaneEncode: LaneEncode U32 = { to_lanes: func x => #[@u32.to_f32 x] }
const F32.LaneEncode: LaneEncode F32 = { to_lanes: func x => #[x] }
const Bool.LaneEncode: LaneEncode Bool = { to_lanes: func x => #[if x then 1.0 else 0.0] }
const Vec2.LaneEncode: LaneEncode Vec2 = { to_lanes: func x => #[x.x, x.y] }

func read_f32 (xs: #[F32]) -> (at: U32): Maybe (F32, U32) =>
  if at >= xs.length:
    return $Nothing
  return $Some (xs[at], at + 1)

func read_u32 (xs: #[F32]) -> (at: U32): Maybe (U32, U32) =>
  let $Some (lane, next) = read_f32 xs at else:
    return $Nothing
  return $Some (@f32.to_u32 lane, next)

func read_bool (xs: #[F32]) -> (at: U32): Maybe (Bool, U32) =>
  let $Some (lane, next) = read_f32 xs at else:
    return $Nothing
  if lane != 0.0 and lane != 1.0:
    return $Nothing
  return $Some (lane == 1.0, next)

func read_vec2 (xs: #[F32]) -> (at: U32): Maybe (Vec2, U32) =>
  let $Some (x, next) = read_f32 xs at else:
    return $Nothing
  let $Some (y, end) = read_f32 xs next else:
    return $Nothing
  return $Some ($Vec2 { x, y }, end)

const F32.LaneDecode: LaneDecode F32 = { from_lanes: read_f32 }
const U32.LaneDecode: LaneDecode U32 = { from_lanes: read_u32 }
const Bool.LaneDecode: LaneDecode Bool = { from_lanes: read_bool }
const Vec2.LaneDecode: LaneDecode Vec2 = { from_lanes: read_vec2 }

func encode (value: t): #[F32] =>
  let lanes: #[F32] = #[]
  #for field in #fields t:
    #if not (field.has_tag $Skip):
      let values = LaneEncode.to_lanes value.(field)
      for i in 0..values.length:
        @storage.push lanes values[i]
  return lanes

func decode (values: #[F32]): Maybe t =>
  let at: U32 = 0
  let built: t = #for field in #fields t:
    #if field.has_tag $Skip:
      #if field.has_default:
        break field.default
      #else:
        break Default.default ()
    #else:
      let $Some (v, next) = LaneDecode.from_lanes values at else:
        return $Nothing
      at := next
      break v
  if at != values.length:
    return $Nothing
  return $Some built

type WithFallback is data = $WithFallback { @[$Skip] cached: U32 }
type Wrapped a is data = $Wrapped { item: a }
type Row = { alpha: U32, beta: F32, flag: Bool }

io main (): Bool =>
  let p = $Packet { ratio: 2.5, flag: true, id: 9, position: $Vec2 { x: 7.0, y: 8.0 }, revision: 1 }
  let lanes = encode p
  let result: Maybe Packet = decode lanes
  let $Some restored = result else:
    return false
  let raw: Row = { alpha: 12, beta: 4.0, flag: false }
  let decoded: Maybe Row = decode (encode raw)
  let $Some structural = decoded else:
    return false
  let short: Maybe Packet = decode #[2.5, 1.0, 9.0, 7.0]
  let invalid: Maybe Packet = decode #[2.5, 2.0, 9.0, 7.0, 8.0]
  let extra: Maybe Packet = decode #[2.5, 1.0, 9.0, 7.0, 8.0, 0.0]
  let generic: Maybe (Wrapped U32) = decode #[18.0]
  let $Some wrapped = generic else:
    return false
  let fallback: Maybe WithFallback = decode #[]
  let $Some cached = fallback else:
    return false
  let $Nothing = short else:
    return false
  let $Nothing = invalid else:
    return false
  let $Nothing = extra else:
    return false
  return lanes.length == 5 and lanes[0] == 2.5 and lanes[2] == 9.0 and
    restored.flag and restored.id == p.id and restored.ratio == p.ratio and
    restored.position.x == p.position.x and restored.position.y == p.position.y and
    restored.revision == 42 and structural.alpha == 12 and structural.beta == 4.0 and
    not structural.flag and cached.cached == 77 and wrapped.item == 18
`,
    (guest) => equal(guest.call("main", null), true),
  );
});

Deno.test("comptime builders pack boxed and empty records and merge runtime break carries", async () => {
  const fields = Array.from({ length: 20 }, (_, index) => `f${19 - index}: U32`)
    .join(", ");
  await compileAndRun(
    `
type Large is data = $Large { ${fields} }
type FlatLarge = { ${fields} }
type Empty is data = $Empty
type Blank = {}
type Pair = { a: U32, b: U32 }

func indexed (): Large =>
  return #for field in #fields Large:
    #if field.index == 0:
      break 100
    #else:
      break field.index

func count_flat (): FlatLarge =>
  return #for field in #fields FlatLarge:
    break field.index

func empty (): Empty =>
  return #for field in #fields Empty:
    break field.index

func blank (): Blank =>
  return #for field in #fields Blank:
    break field.index

func pair (start: U32): U32 =>
  let at = start
  let built = #for field in #fields Pair:
    if at == 0:
      at := 7
      break field.index + 1
    else:
      at := at + 5
      break field.index + 2
  return 100 * built.a + 10 * built.b + at

func unit_field (): U32 =>
  let count = 0
  let _ = #for field in #fields { empty: Unit }:
    count := count + 1
  return count

func nested_loop (): U32 =>
  let count = 0
  for i in 0..3:
    let _ = #for field in #fields Pair:
      count := count + i + field.index
      break count
  return count

io main (): Bool =>
  let large = indexed ()
  let flat = count_flat ()
  let $Empty = empty ()
  let owned = #for field in #fields { left: #[U32], right: #[U32] }:
    break #[field.index]
  owned.left[0] := self + 6
  let _ = blank ()
  return owned.left[0] == 6 and owned.right[0] == 1 and
    large.f19 == 100 and large.f18 == 1 and large.f0 == 19 and
    flat.f0 == 0 and flat.f19 == 11 and pair 0 == 142 and pair 1 == 241 and unit_field () == 1 and nested_loop () == 9
`,
    (guest) => equal(guest.call("main", null), true),
  );
});

Deno.test("comptime defaults use the defining module and update after retained edits", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.sq";
  const model = dir + "/model.sq";
  const definition = `
private func answer (): U32 => 37
type Item is data = $Item { ready: Bool = true, amount: U32 = answer () }
func amount (item: Item): U32 => if item.ready then item.amount else 0
`;
  try {
    await Deno.writeTextFile(model, definition);
    await Deno.writeTextFile(
      dir + "/builder.sq",
      `
func build (): t =>
  return #for field in #fields t:
    break field.default
`,
    );
    await Deno.writeTextFile(
      entry,
      `
import * as model from "./model"
import { build } from "./builder"
io main (): U32 =>
  let item: model.Item = build ()
  return model.amount item
`,
    );
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
    });
    try {
      async function verify(
        expected: number,
        sources?: Record<string, string>,
      ) {
        const output = await compiler.build({ sources });
        if (!output.success) {
          throw new Error(JSON.stringify(output.diagnostics));
        }
        const guest = await instantiateGuest(output.bytes);
        try {
          equal(guest.call("main", null), expected);
        } finally {
          guest.dispose();
        }
      }
      await verify(37);
      await verify(49, { [model]: definition.replace("37", "49") });
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("comptime writes reject read-only receivers and unknown selectors", async () => {
  for (const parameter of ["*Row", "&Row", "&[Row]"]) {
    const receiver = parameter === "&[Row]" ? "r[0]" : "r";
    await compileExpectedFailure(
      `
type Row = { count: U32 }
func bad (r: ${parameter}): U32 =>
  #for field in #fields Row:
    ${receiver}.(field) := 3
  return 0
io main (): U32 => 0
`,
      "type_mismatch",
    );
  }
  await compileExpectedFailure(
    `
type Choice is data = $First { x: U32 } | $Second { x: U32 }
io main (): U32 =>
  let value = $First { x: 1 }
  #for variant in #variants Choice:
    value.(variant) := 2
  return value.x
`,
    "unknown_name",
  );
  await compileExpectedFailure(
    `
io main (): U32 =>
  let value = { x: 1 }
  value.(field) := 2
  return value.x
`,
    "unknown_value",
  );
});

Deno.test("comptime writes preserve aliased_update and spent_value", async () => {
  await compileExpectedFailure(
    `
type Row = { items: #[U32] }
io main (): U32 =>
  let row: Row = { items: #[1] }
  let alias = row
  #for field in #fields Row:
    row.(field) := #[2]
  return row.items.length + alias.items.length
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
type Row = { x: U32 }
io main (): U32 =>
  let rows: #[Row] = #[{ x: 1 }]
  let alias = rows
  #for field in #fields Row:
    rows[0].(field) := self + 1
  return rows[0].x + alias[0].x
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
type Row = { items: #[U32] }
func consume (row: own Row): U32 => row.items.length
io main (): U32 =>
  let items: #[U32] = #[1, 2]
  let row: Row = { items }
  let size = consume (own row)
  #for field in #fields Row:
    row.(field) := self
  return row.items.length + size
`,
    "spent_value",
  );
});

Deno.test("comptime builders reject variants, missing defaults, and non-Unit fallthrough", async () => {
  await compileExpectedFailure(
    `
type Choice is data = $First | $Second
io main (): U32 =>
  let _ = #for variant in #variants Choice:
    break variant.index
  return 0
`,
    "GPU_FRONTEND_SYNTAX_ERROR",
  );
  await compileExpectedFailure(
    `
type Row is data = $Row { x: U32 }
io main (): U32 =>
  let row = #for field in #fields Row:
    break field.default
  return row.x
`,
    "storage_unsupported",
  );
  await compileExpectedFailure(
    `
io main (): U32 =>
  let row = #for field in #fields { x: U32 }:
    let _ = field.index
  return row.x
`,
    "storage_unsupported",
  );
});
