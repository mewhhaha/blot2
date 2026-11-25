import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("Phase 2 unified #[T]: Array.push / Array.truncate / Array.pop, stack-to-heap promotion, and record field updates", async () => {
  await compileAndRun(
    `type Frame is data = $Frame { draws: #[U32], count: U32 }

func push_draw (frame: own Frame) -> (v: U32): Frame =>
  frame.draws := self.push v
  frame.count := self + 1
  return frame

#entry func grow_truncate_pop (n: U32): #[U32] =>
  let xs: #[U32] = #[]
  for i in 0..n:
    xs := self.push (i * 3)
  xs := self.truncate 2
  xs := self.push 77
  xs := self.push 88
  let (xs2, popped) = xs.pop
  return xs2.push popped

#entry func stack_to_heap_and_cache (): U32 =>
  let xs: #[U32] = #[10, 20]
  let first = xs[0]
  xs := self.push 30
  xs := self.push 40
  return first + xs[2] + xs[3]

#entry func record_field_push (n: U32): U32 =>
  let frame = $Frame { draws: #[], count: 0 }
  for i in 0..n:
    frame := push_draw self (i + 1)
  let total = 0
  for d in frame.draws:
    total := self + d
  return total + frame.count
`,
    (guest) => {
      equal(String(guest.call("grow_truncate_pop", 5)), "0,3,77,88");
      equal(guest.call("stack_to_heap_and_cache", null), 80);
      equal(guest.call("record_field_push", 10), 55 + 10);
    },
  );
});

Deno.test("Phase 2 strict ownedInPlace on #[T] and SizedArray #[N; T] immutability", async () => {
  // Borrowed #[T] parameter cannot be pushed/truncated/popped
  await compileExpectedFailure(
    `func bad (xs: #[U32]) =>
  @storage.push xs 1
  return ()
#entry func main (): U32 =>
  let a = #[1]
  let _ = bad a
  return a[0]
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `func bad (xs: #[U32]) =>
  @storage.truncate xs 0
  return ()
#entry func main (): U32 =>
  let a = #[1]
  let _ = bad a
  return a.length
`,
    "aliased_update",
  );
  // Module const global #[T] cannot be pushed
  await compileExpectedFailure(
    `const GLOBAL: #[U32] = #[1, 2]
#entry func main (): U32 =>
  @storage.push GLOBAL 3
  return GLOBAL.length
`,
    "aliased_update",
  );
  // Aliased local #[T] cannot be pushed
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2]
  let ys = xs
  @storage.push xs 3
  return ys[0]
`,
    "aliased_update",
  );
  // Active view borrows #[T] and rejects push
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2]
  let v = &xs[0..2]
  @storage.push xs 3
  return v[0]
`,
    "aliased_update",
  );
  // Outer #[T] captured in closure cannot be pushed
  await compileExpectedFailure(
    `func run (f: Unit -> Unit) => f ()
#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2]
  let _ = run (func () => @storage.push xs 3)
  return xs.length
`,
    "aliased_update",
  );
  // Compile-time fixed-length SizedArray #[N; T] rejects push, pop, truncate (intrinsic & method)
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[4; U32] = #[1, 2, 3, 4]
  @storage.push xs 5
  return xs[0]
`,
    "type_mismatch",
  );
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[4; U32] = #[1, 2, 3, 4]
  @storage.truncate xs 2
  return xs[0]
`,
    "type_mismatch",
  );
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[4; U32] = #[1, 2, 3, 4]
  let _ = xs.push 5
  return 0
`,
    "missing_member",
  );
});

Deno.test("Phase 2 backend hardening (S4, S5, S6, S7): loop borrow, range hoisting, backedge cache invalidation, and RHS update lock", async () => {
  // S4: for x in xs borrows scalar #[U32] so pushing/mutating xs inside the loop is rejected
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2, 3]
  let total = 0
  for x in xs:
    @storage.push xs x
    total := self + x
  return total
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2, 3]
  for x in xs:
    xs := self.push x
  return xs.length
`,
    "own_argument",
  );

  // S7: @simd.store locks target container during RHS evaluation
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2, 3, 4]
  let _ = @simd.store xs 0 (always (10, 20, 30, 40) (@storage.push xs 99))
  return xs[0]
`,
    "aliased_update",
  );
  // Early return of aliasing element alongside outer container is still rejected
  await compileExpectedFailure(
    `func bad (rows: own #[#[U32]]): (#[U32], #[#[U32]]) =>
  for row in rows:
    return (row, rows)
  return (#[], rows)
#entry func main (): U32 =>
  let (a, _) = bad #[#[1]]
  return a.length
`,
    "result_not_owned",
  );
  // 1-arg own method xs.pop consumes xs; partial 2-arg xs.push is rejected
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2]
  let (xs2, _) = xs.pop
  return xs[0] + xs2.length
`,
    "spent_value",
  );
  await compileExpectedFailure(
    `#entry func main (): U32 =>
  let xs: #[U32] = #[1, 2]
  let f = xs.push
  return (f 3).length
`,
    "own_function_value",
  );

  // S4 sibling field positive + S5 OOB trap after truncate + S6 loop-backedge cache invalidation
  await compileAndRun(
    `type Pair is data = $Pair { src: #[U32], dst: #[U32] }

func early_return_from_scalar_loop (xs: own #[U32]) -> (target: U32): (Bool, #[U32]) =>
  for x in xs:
    if x == target:
      return (true, xs)
  xs := self.push target
  return (false, xs)

#entry func early_return_scalar_loop_test (): U32 =>
  let (found1, xs1) = early_return_from_scalar_loop #[10, 20] 20
  let (found2, xs2) = early_return_from_scalar_loop xs1 30
  return (if found1 then 100 else 0) + (if found2 then 10 else 0) + xs2.length

#entry func sibling_field_loop (): U32 =>
  let p = $Pair { src: #[10, 20, 30], dst: #[] }
  for x in p.src:
    p.dst := self.push (x + 1)
  return p.dst[0] + p.dst[1] + p.dst[2]

#entry func loop_backedge_reloads_base_and_len (): U32 =>
  let xs: #[U32] = #[1, 2, 3]
  let before = xs[0]
  let sum = before
  for i in 0..4:
    xs := self.push (i + 10)
    sum := self + xs[xs.length - 1]
  return sum + xs.length

#entry func range_truncate_must_trap (): U32 =>
  let xs: #[U32] = #[10, 20, 30]
  let acc = 0
  for i in 0..xs.length:
    xs := self.truncate 0
    acc := self + xs[i]
  return acc

#entry func indexed_update_rhs_promotes_to_heap (): U32 =>
  let xs: #[U32] = #[10]
  xs[0] := do:
    for i in 0..64:
      @storage.push xs i
    break self + 32
  return xs[0] + xs.length + xs[64]

#entry func indexed_update_rhs_pop_must_trap (): U32 =>
  let xs: #[U32] = #[10]
  xs[0] := do:
    let _ = @storage.pop xs
    break 42
  return xs[0]
`,
    (guest) => {
      equal(guest.call("early_return_scalar_loop_test", null), 103);
      equal(guest.call("sibling_field_loop", null), 11 + 21 + 31);
      // before=1, pushes 10,11,12,13 -> sum = 1 + 10+11+12+13 = 47, final len = 7 -> 54
      equal(guest.call("loop_backedge_reloads_base_and_len", null), 54);
      // xs[0] = 42, xs.length = 65, xs[64] = 63 -> 170
      equal(guest.call("indexed_update_rhs_promotes_to_heap", null), 170);
      let trapped = false;
      try {
        guest.call("range_truncate_must_trap", null);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      let popTrapped = false;
      try {
        guest.call("indexed_update_rhs_pop_must_trap", null);
      } catch {
        popTrapped = true;
      }
      equal(popTrapped, true);
    },
  );
});

Deno.test("Phase 2 fork rewind across stack-to-heap promotion on #[T]", async () => {
  await compileAndRun(
    `#entry func fork_promotes_and_rewinds (): U32 =>
  let xs: #[U32] = #[10, 20]
  let spec = fork xs:
    xs := self.push 30
    xs := self.push 40
    xs[0] := 999
    return xs.length * 1000 + xs[0] + xs[3]
  return spec * 100 + xs.length * 10 + xs[0] + xs[1]
`,
    (guest) => {
      // spec = 4*1000 + 999 + 40 = 5039; after rollback xs = #[10, 20] -> 2*10 + 10 + 20 = 50 -> 503950
      equal(guest.call("fork_promotes_and_rewinds", null), 503950);
    },
  );
});
