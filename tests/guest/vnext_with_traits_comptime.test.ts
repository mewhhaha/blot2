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

#entry func main (): U32 =>
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
#entry func main (): U32 =>
  return if same ($Foo 1) ($Foo 1) then 1 else 0
`,
    "missing_implementation",
  );
});

Deno.test("vNext 3B: scoped with handlers, linear shadowing, pre-built records, multi-entry, outer effects", async () => {
  await compileAndRun(
    `
type Log is effect = { write: U32 -> Unit }
type State s is effect = {
  get: Unit -> s,
  put: s -> Unit,
}
type Outer is effect = { emit: U32 -> Unit }

const quiet: Log = { write: func _ => () }

func emit_pair (a: U32) -> (b: U32): Unit !{ Log } =>
  use Log.write a
  use Log.write b
  return ()

func run_with_log (h: Log) -> (x: U32): U32 =>
  with h:
    use Log.write x
  return x + 1

func bump_state (delta: U32): U32 !{ State U32, Log } =>
  use cur <- State.get ()
  let next = cur + delta
  use State.put next
  use Log.write next
  return next

func push_grow (a: own #[U32]) -> (x: U32): #[U32] =>
  @storage.push a x
  return a

#entry func main (): U32 =>
  // 1. Pre-built effect record and passing Log as parameter
  let r1 = run_with_log quiet 9

  // 2. Inline handler linearly shadowing outer U32 and dynamic array, plus multi-entry with
  let total = 0
  let log: #[U32] = #[]
  let n = 10
  with Log = { write: func x => log := push_grow self x }, State U32 = { get: func () => n, put: func v => n := v }:
    use a <- bump_state 5
    use b <- bump_state 7
    total := a + b

  // 3. Handler performing an outer effect + nested with
  let outer_sum = 0
  with Outer = { emit: func x => outer_sum := outer_sum + x }:
    with Log = { write: func x => use Outer.emit (x * 2) }:
      use emit_pair 3 4

  // 4. with inside for loop with early break carrying shadowed cell out
  let acc = 0
  for i in 0..10:
    with Log = { write: func x => acc := acc + x }:
      use Log.write i
      if i == 4:
        break

  // r1=10, total=15+22=37, n=22, log.length=2, log[0]+log[1]=37, outer_sum=14, acc=0+1+2+3+4=10
  return r1 + total + n + log.length + log[0] + log[1] + outer_sum + acc
`,
    (guest) => {
      // 10 + 37 + 22 + 2 + 15 + 22 + 14 + 10 = 132
      equal(guest.call("main", null), 132);
    },
  );
});

Deno.test("vNext 3B: fork rolls back mutations to with-shadowed outer cell", async () => {
  await compileAndRun(
    `
type State s is effect = {
  get: Unit -> s,
  put: s -> Unit,
}

#entry func main (): U32 =>
  let n = 10
  let dummy = #[1]
  let preview = 0
  let after = 0
  with State U32 = { get: func () => n, put: func v => n := v }:
    use p <- fork dummy:
      use State.put 99
      use g <- State.get ()
      return g
    preview := p
    use g2 <- State.get ()
    after := g2
  // preview == 99, after == 10, n == 10
  return preview * 1000 + after * 10 + n
`,
    (guest) => {
      equal(guest.call("main", null), 99000 + 100 + 10);
    },
  );
});

Deno.test("vNext 3B: suite cannot read or rebind a local shadowed by an active with handler", async () => {
  await compileExpectedFailure(
    `
type Log is effect = { write: U32 -> Unit }
#entry func main (): U32 =>
  let count = 0
  with Log = { write: func x => count := count + x }:
    use Log.write 1
    let bad = count
  return count
`,
    "borrow_conflict",
  );
});

Deno.test("vNext 3B: with Foreign is rejected as sealed_effect", async () => {
  await compileExpectedFailure(
    `
#entry func main (): U32 =>
  with Foreign = { x: func () => () }:
    let a = 1
  return 0
`,
    "sealed_effect",
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

#entry func main (): U32 =>
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

#entry func main (): U32 =>
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
#entry func main (): U32 =>
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
#entry func main (): U32 =>
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

#entry func main (): U32 =>
  let total = 0
  let p = $Packet { id: 10, flag: true }
  with Emit U32 = func v => total := total + v:
    use encode_packet p
  return total
`,
    (guest) => {
      // 10 + 1 + 5 = 16
      equal(guest.call("main", null), 16);
    },
  );
});
