import { deepStrictEqual as same } from "node:assert/strict";
import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// Issue #11 and its follow-up: rebinding an enclosing local inside the do: arms
// of a statement case carries out of the case, as it does out of if branches.
Deno.test("rebinding inside statement case arms carries out of the case", async () => {
  await compileAndRun(`
type Beat is data = #Up | #Down
entry const main = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  case beat of
    #Up => do:
      count := 7
    #Down => do:
      count := 3
  break count
entry const one = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 1
  case beat of
    #Up => do:
      count := 7
    #Down => do:
      let unused = 2
  break count
entry const lone = func (n: U32) : U32 => return do:
  let count = 3
  case (n, n + 1) of
    (low, high) => do:
      count := low + high
  break count
`, (guest) => {
    equal(guest.call("main", 1), 7);
    equal(guest.call("main", 0), 3);
    equal(guest.call("one", 1), 7);
    equal(guest.call("one", 0), 1);
    equal(guest.call("lone", 4), 9);
  });
});

Deno.test("case arms carry field, self, nested if and three-arm rebinding, and scalar arms keep the incoming value", async () => {
  await compileAndRun(`
type Beat is data = #Up | #Down
type Tri is data = #Rise | #Fall | #Still
entry const fielded = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let held = { node: 5, other: 9 }
  case beat of
    #Up => do:
      held.node := 0
    #Down => do:
      held.node := self + 1
  break held.node + held.other
entry const selfish = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 10
  case beat of
    #Up => do:
      count := self + 1
      count := self * 2
    #Down => do:
      count := self - 1
  break count
entry const nested = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  case beat of
    #Up => do:
      if n > 5:
        count := 50
      else:
        count := 5
    #Down => do:
      count := 1
  break count
entry const three = func (n: U32) : U32 => return do:
  let beat = if n == 0 then #Fall else if n == 1 then #Rise else #Still
  let count = 0
  let other = 100
  case beat of
    #Rise => do:
      count := 7
    #Fall => do:
      count := 3
      other := 200
    #Still => do:
      count := 11
  break count + other
entry const scalar = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 4
  case beat of
    #Up => ()
    #Down => do:
      count := 9
  break count
entry const guarded = func (n: U32) : U32 => return do:
  let count = 0
  case n of
    0 => do:
      count := 100
    m if m > 5 => do:
      count := m * 2
    _ => do:
      count := 1
  break count
entry const retyped = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let ready = 1
  case beat of
    #Up => do:
      ready := n == 3
    #Down => do:
      ready := false
  break if ready then 1 else 0
`, (guest) => {
    equal(guest.call("fielded", 1), 9);
    equal(guest.call("fielded", 0), 15);
    equal(guest.call("selfish", 1), 22);
    equal(guest.call("selfish", 0), 9);
    equal(guest.call("nested", 9), 50);
    equal(guest.call("nested", 2), 5);
    equal(guest.call("nested", 0), 1);
    equal(guest.call("three", 0), 203);
    equal(guest.call("three", 1), 107);
    equal(guest.call("three", 2), 111);
    equal(guest.call("scalar", 1), 4);
    equal(guest.call("scalar", 0), 9);
    equal(guest.call("guarded", 0), 100);
    equal(guest.call("guarded", 9), 18);
    equal(guest.call("guarded", 3), 1);
    equal(guest.call("retyped", 3), 1);
    equal(guest.call("retyped", 2), 0);
    equal(guest.call("retyped", 0), 0);
  });
});

Deno.test("a direct return ends a case arm with its rebinding, and loops carry arm rebinding and breaks", async () => {
  await compileAndRun(`
type Beat is data = #Up | #Down
entry const direct = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 2
  case beat of
    #Up => do:
      count := self + 5
      break ()
    #Down => do:
      count := self + 1
  break count
entry const looped = func (n: U32) : U32 => return do:
  let total = 0
  for index in 0..n:
    let beat = if index % 2 == 0 then #Up else #Down
    case beat of
      #Up => do:
        total := self + 10
      #Down => do:
        total := self + 1
  break total
entry const breaking = func (n: U32) : U32 => return do:
  let total = 0
  for index in 0..10:
    let beat = if index < n then #Up else #Down
    case beat of
      #Up => do:
        total := self + 2
      #Down => do:
        total := self + 100
        break
  break total
`, (guest) => {
    equal(guest.call("direct", 1), 7);
    equal(guest.call("direct", 0), 3);
    equal(guest.call("looped", 5), 32);
    equal(guest.call("looped", 0), 0);
    equal(guest.call("breaking", 3), 106);
    equal(guest.call("breaking", 20), 20);
  });
});

Deno.test("owned arrays rebound across case arms keep guest memory stable", async () => {
  await compileAndRun(`
type Bag is data = #Many (Array U32) | #One U32 | #Empty
entry const owned = func (n: U32) : U32 => return do:
  let bag = if n % 3 == 0 then #Many (@array.generate (n % 40 + 8) (func index => return index + 1)) else if n % 3 == 1 then #One n else #Empty
  let values = @array.generate 12 (func index => return index)
  let total = 0
  case bag of
    #Empty => do:
      total := 5
    #One m => do:
      values := @array.generate (m % 9 + 3) (func index => return index * m)
      total := m
    #Many items => do:
      values := items
      if items.length > 20:
        total := items[1]
      else:
        values[0] := self + 77
  break values.length + values[0] + total
entry const escaping = func (n: U32) : Array U32 => return do:
  let beat = if n % 2 == 0 then #Up else #Down
  let values = @array.generate 4 (func index => return index)
  case beat of
    #Up => do:
      values[1] := 99
    #Down => do:
      values := #[n, n]
  break values
type Beat is data = #Up | #Down
`, (guest) => {
    equal(guest.call("owned", 0), 86);
    equal(guest.call("owned", 1), 5);
    equal(guest.call("owned", 2), 17);
    equal(guest.call("owned", 15), 26);
    equal(guest.call("owned", 4), 11);
    same(guest.call("escaping", 2), Uint32Array.of(0, 99, 2, 3));
    same(guest.call("escaping", 3), Uint32Array.of(3, 3));
    for (let index = 0; index < 64; index++) {
      guest.call("owned", index);
      guest.call("escaping", index);
    }
    const settled = guest.memoryBytes();
    equal(settled > 0, true);
    for (let index = 0; index < 4096; index++) {
      guest.call("owned", index);
      guest.call("escaping", index);
    }
    equal(guest.memoryBytes(), settled);
  });
});

Deno.test("constant evaluation of statement case arm rebinding agrees with runtime execution", async () => {
  await compileAndRun(`
type Tri is data = #Rise | #Fall | #Still
const pick = func (n: U32) : U32 => return do:
  let beat = if n == 0 then #Fall else if n == 1 then #Rise else #Still
  let count = 0
  let values = #[1, 2]
  case beat of
    #Rise => do:
      count := 7
      values := #[9, 9, 9]
    #Fall => do:
      count := 3
    #Still => do:
      if n > 5:
        count := 50
      else:
        count := 5
  break count + values.length
const folded_fall = pick 0
const folded_rise = pick 1
const folded_still = pick 9
entry const folded = func () : U32 => return folded_fall * 10000 + folded_rise * 100 + folded_still
entry const runtime = func (n: U32) : U32 => return pick n
`, (guest) => {
    equal(guest.call("folded", null), 51052);
    const [fall, rise, still] = [0, 1, 9].map((n) => guest.call("runtime", n) as number);
    equal(fall * 10000 + rise * 100 + still, 51052);
  });
});

Deno.test("a return nested inside a carrying case arm is rejected", async () => {
  await compileExpectedFailure(`
type Beat is data = #Up | #Down
entry const main = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  case beat of
    #Up => do:
      count := 7
      if n > 4:
        break ()
      count := 8
    #Down => do:
      count := 3
  break count
`, "case_arm_return");
});

Deno.test("an unread rebinding inside a statement do block is rejected", async () => {
  await compileExpectedFailure(`
entry const main = func (n: U32) : U32 => return do:
  let count = n
  do:
    count := self + 1
  break count
`, "dead_rebinding");
});

Deno.test("rebinding read in its block or its branches, or carried out by if, case values and loops, still compiles", async () => {
  await compileAndRun(`
type Beat is data = #Up | #Down
const step = func n => return n + 1
const build = func start => return do:
  start := step self
  start := step self
  break start
entry const arm = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 2
  let result = case beat of
    #Up => do:
      count := count + 5
      break count
    #Down => do:
      count := self + 1
      break count
  break result
entry const branch = func (n: U32) : U32 => return do:
  let count = 0
  if n > 0:
    count := 7
  else:
    count := 3
  break count
entry const chosen = func (n: U32) : U32 => return do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  count := case beat of
    #Up => 7
    #Down => 3
  break count
entry const guarded = func (n: U32) : U32 => return do:
  let held = n
  break case n of
    0 => do:
      let total = 1
      if held == 0:
        held := 9
        total := held + 1
      break total
    _ => 2
entry const looped = func (n: U32) : U32 => return do:
  let total = 0
  for 0 .. n:
    total := self + 2
  break total + build 0
`, (guest) => {
    equal(guest.call("arm", 1), 7);
    equal(guest.call("arm", 0), 3);
    equal(guest.call("branch", 1), 7);
    equal(guest.call("branch", 0), 3);
    equal(guest.call("chosen", 1), 7);
    equal(guest.call("chosen", 0), 3);
    equal(guest.call("guarded", 0), 10);
    equal(guest.call("guarded", 1), 2);
    equal(guest.call("looped", 3), 8);
  });
});
