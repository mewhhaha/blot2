import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("vNext syntax: not operator, bare => expr, => suite, return use, leading-dot chaining, panic", async () => {
  await compileAndRun(
    `
type Acc is data = $Acc {
  value: U32
}

func Acc.add (self: Acc) -> (n: U32): Acc => $Acc { value: self.value + n }
func Acc.mul (self: Acc) -> (n: U32): Acc => $Acc { value: self.value * n }
func Acc.get (self: Acc): U32 => self.value

func add (x: U32) -> (y: U32): U32 => x + y

func logic (a: Bool) -> (b: Bool) -> (x: U32) -> (y: U32): Bool =>
  not a and not x == y or not b

func sum_suite (xs: #[U32]): U32 =>
  let total = 0
  for x in xs:
    total := self + x
  return total

func choose_suite (n: U32): U32 =>
  case n of
    0 =>
      let base = 10
      return base + 5
    1 =>
      return 20
    _ =>
      return n * 2

func value_case_indented (n: U32): U32 =>
  let out = case n of
    0 =>
      100
    _ =>
      n + 1
  return out

func chain_ops (start: U32): U32 =>
  let result = ($Acc { value: start })
    .add 3
    .mul 4
    .add 2
    .get
  return result

func guard_nonzero (x: U32): U32 =>
  if x == 0:
    panic "must be nonzero"
  return x + 1

type Counter is effect = {
  next: U32 -> U32
}

func use_counter (x: U32): U32 ! {Counter.next} =>
  return use Counter.next x

func run_counter (x: U32): U32 =>
  let p = @effect.provider Counter.next (func n => n + 10)
  return do p:
    return use use_counter x

func count_to (limit: U32): U32 =>
  let i = 0
  for ever:
    if i >= limit:
      return i
    i := i + 1

#entry func test_add (x: U32): U32 => add x 7
#entry func test_logic (which: U32): Bool =>
  case which of
    0 => logic false true 1 2
    1 => logic true true 1 2
    2 => logic false true 2 2
    _ => logic true false 2 2
#entry func test_sum (): U32 => sum_suite #[1, 2, 3, 4]
#entry func test_choose (n: U32): U32 => choose_suite n
#entry func test_value_case (n: U32): U32 => value_case_indented n
#entry func test_chain (start: U32): U32 => chain_ops start
#entry func test_guard (x: U32): U32 => guard_nonzero x
#entry func test_return_use (x: U32): U32 => run_counter x
#entry func test_for_ever_return (n: U32): U32 => count_to n
`,
    (guest) => {
      equal(guest.call("test_add", 35), 42);
      // not false and not (1 == 2) or not true => (true and true) or false => true
      equal(guest.call("test_logic", 0), true);
      // not true and not (1 == 2) or not true => false or false => false
      equal(guest.call("test_logic", 1), false);
      // not false and not (2 == 2) or not true => (true and false) or false => false
      equal(guest.call("test_logic", 2), false);
      // not true and not (2 == 2) or not false => false or true => true
      equal(guest.call("test_logic", 3), true);
      equal(guest.call("test_sum", null), 10);
      equal(guest.call("test_choose", 0), 15);
      equal(guest.call("test_choose", 1), 20);
      equal(guest.call("test_choose", 7), 14);
      equal(guest.call("test_value_case", 0), 100);
      equal(guest.call("test_value_case", 5), 6);
      // ((5 + 3) * 4) + 2 = 34
      equal(guest.call("test_chain", 5), 34);
      equal(guest.call("test_guard", 41), 42);
      equal(guest.call("test_return_use", 5), 15);
      equal(guest.call("test_for_ever_return", 7), 7);
    },
  );
});

Deno.test("vNext symbols: #[T], #[n; T], *T, freeze, copy, and borrowed array coercion", async () => {
  await compileAndRun(
    `
type World is data = $World {
  tick: U32,
  scores: #[U32]
}

type Pair n is data = $Pair {
  xs: #[n; U32],
  ys: #[n; U32]
}

func sum_borrowed (xs: #[U32]): U32 =>
  let acc = 0
  for x in xs:
    acc := self + x
  return acc

func dot_linked (a: #[n; U32]) -> (b: #[n; U32]): U32 =>
  let acc = 0
  for i in 0..a.length:
    acc := self + a[i] * b[i]
  return acc

func sum_pair (p: Pair n): U32 => dot_linked p.xs p.ys

func read_world_score (w: World): U32 => w.tick + sum_borrowed w.scores

func build_and_read (): U32 =>
  let buf: #[U32] = #[]
  @storage.push buf 10
  @storage.push buf 20
  let s1 = sum_borrowed buf
  let fixed: #[U32] = buf
  let s2 = sum_borrowed fixed
  return s1 + s2

func build_resize_and_freeze (): U32 =>
  let buf: #[U32] = #[5, 10, 15]
  let popped = @storage.pop buf
  let shared: *#[U32] = freeze buf
  // shared is freely aliasable!
  let a = shared
  let b = shared
  let s = sum_borrowed a + b[0] + b[1]
  // copy unfreezes into a fresh linear array we can mutate in place!
  let fresh: #[U32] = copy shared
  fresh[0] := 100
  return popped + s + fresh[0] + shared[0]

func freeze_and_copy_world (): U32 =>
  let w = $World { tick: 3, scores: #[1, 2, 3] }
  let sw: *World = freeze w
  // Auto-lifting field reads through *World, and passing *World to borrowed World
  let a = read_world_score sw
  let b = sw.tick + sw.scores[2]
  // Deep copy *World -> fresh linear World that can be mutated without touching *World!
  let w2: World = copy sw
  w2.scores[0] := 50
  w2.tick := 9
  return a + b + w2.scores[0] + sw.scores[0] + w2.tick

func linked_lengths (): U32 =>
  let a: #[3; U32] = #[1, 2, 3]
  let b: #[3; U32] = #[4, 5, 6]
  let p = $Pair { xs: a, ys: b }
  return sum_pair p

#entry func test_seal (): U32 => build_and_read ()
#entry func test_freeze_copy (): U32 => build_resize_and_freeze ()
#entry func test_world (): U32 => freeze_and_copy_world ()
#entry func test_linked (): U32 => linked_lengths ()
`,
    (guest) => {
      // s1 = 30, s2 = 30 => 60
      equal(guest.call("test_seal", null), 60);
      // popped = 15, s = (5+10) + 5 + 10 = 30, fresh[0] = 100, shared[0] = 5 => 150
      equal(guest.call("test_freeze_copy", null), 150);
      // a = 3+6 = 9, b = 3+3 = 6, w2.scores[0] = 50, sw.scores[0] = 1, w2.tick = 9 => 75
      equal(guest.call("test_world", null), 75);
      // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
      equal(guest.call("test_linked", null), 32);
    },
  );
});

Deno.test("vNext rejections: suite fallthrough, frozen mutation, spent after freeze, linked length mismatch, _ hole", async () => {
  await compileExpectedFailure(
    `
#entry func bad (x: U32): U32 =>
  let y = x + 1
  y
`,
    "function_return_required",
  );

  await compileExpectedFailure(
    `
#entry func bad (): U32 =>
  let xs: *#[U32] = freeze #[1, 2, 3]
  xs[0] := 9
  return xs[0]
`,
    "type_mismatch",
  );

  await compileExpectedFailure(
    `
#entry func bad (): U32 =>
  let xs = #[1, 2, 3]
  let shared = freeze xs
  return xs[0] + shared[0]
`,
    "spent_value",
  );

  await compileExpectedFailure(
    `
func dot (a: #[n; U32]) -> (b: #[n; U32]): U32 => a[0] + b[0]
#entry func bad (): U32 =>
  let a: #[2; U32] = #[1, 2]
  let b: #[3; U32] = #[1, 2, 3]
  return dot a b
`,
    "type_mismatch",
  );

  await compileExpectedFailure(
    `
#entry func bad (): U32 =>
  let a: #[3; U32] = #[1, 2]
  return a[0]
`,
    "type_mismatch",
  );

  await compileExpectedFailure(
    `
#entry func bad (x: U32): U32 => _
`,
    "typed_hole",
  );
});
