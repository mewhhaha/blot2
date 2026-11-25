import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

// Wide boxed multi-constructor sum (> inline word threshold forces heap boxing).
const fbipProgram = `
type State is data =
  | $Active { a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32, q: U32, r: U32 }
  | $Paused { a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32, q: U32, r: U32 }

func make_active (a: U32) -> (b: U32) -> (c: U32) -> (d: U32): State =>
  return $Active { a, b, c, d, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10, k: 11, l: 12, m: 13, n: 14, o: 15, p: 16, q: 17, r: 18 }

func sum_state (s: State): U32 => return case s of
  $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + q + r
  $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + q + r

func step_branch (s: State) -> (flag: U32): State =>
  let cur = case s of
    $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
    $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
  case cur of
    $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } =>
      if flag == 0:
        return $Active { a: a + 1, b: b + 2, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
      else:
        return $Paused { a: a + 3, b, c: c + 1, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
    $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } =>
      return $Active { a: a + 5, b, c, d: d + 1, e, f, g, h, i, j, k, l, m, n, o, p, q, r }

// Statement-match FBIP inside a loop on a copiedBox carry initialized from a
// shared value: must leave the original untouched AND stay zero-allocation.
#entry func loop_stmt_fbip (iters: U32): U32 =>
  let initial = make_active 10 20 30 40
  let cur = initial
  for idx in 0..iters:
    case cur of
      $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } =>
        if (idx & 1) == 0:
          cur := $Active { a: a + 1, b: b + 2, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
        else:
          cur := $Paused { a: a + 3, b, c: c + 1, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
      $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } =>
        cur := $Active { a: a + 5, b, c, d: d + 1, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
  let init_sum = sum_state initial
  let cur_sum = sum_state cur
  return init_sum * 1000000 + cur_sum

// Expression-match with do: return and branching if/else tails.
#entry func branch_return_fbip (iters: U32): U32 =>
  let cur = make_active 1 2 3 4
  for idx in 0..iters:
    cur := step_branch cur (idx & 1)
  return sum_state cur

// Expression-match with do: break (Tag.block_ -> Tag.return_) on a boxed value.
#entry func block_break_fbip (iters: U32): U32 =>
  let cur = do:
    let init = make_active 2 4 6 8
    break init
  for idx in 0..iters:
    cur := case cur of
      $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => do:
        let next_a = a + 1
        break $Active { a: next_a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
      $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => do:
        break $Paused { a: a + 2, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
  return sum_state cur

// Aliasing soundness: when cur is referenced twice, FBIP must NOT fire.
#entry func alias_soundness (n: U32): U32 =>
  let cur = make_active n 2 3 4
  let saved = cur
  let next = case cur of
    $Active { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => $Active { a: a + 100, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
    $Paused { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r } => $Paused { a: a + 200, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r }
  let sa = sum_state saved
  let na = sum_state next
  return sa * 1000 + na
`;

const tailConstSum = 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16 + 17 + 18;

function expectedLoopSum(iters: number): number {
  let tag = 0;
  let a = 10, b = 20, c = 30, d = 40;
  for (let i = 0; i < iters; i++) {
    if (tag === 0) {
      if ((i & 1) === 0) {
        a += 1;
        b += 2;
      } else {
        tag = 1;
        a += 3;
        c += 1;
      }
    } else {
      tag = 0;
      a += 5;
      d += 1;
    }
  }
  const initSum = 10 + 20 + 30 + 40 + tailConstSum;
  const curSum = a + b + c + d + tailConstSum;
  return initSum * 1_000_000 + curSum;
}

function expectedBranchSum(iters: number): number {
  let tag = 0;
  let a = 1, b = 2, c = 3, d = 4;
  for (let i = 0; i < iters; i++) {
    if (tag === 0) {
      if ((i & 1) === 0) {
        a += 1;
        b += 2;
      } else {
        tag = 1;
        a += 3;
        c += 1;
      }
    } else {
      tag = 0;
      a += 5;
      d += 1;
    }
  }
  return a + b + c + d + tailConstSum;
}

Deno.test("FBIP reuses boxed blocks across statement matches, return tails, and branching if/else without corrupting aliases", async () => {
  await compileAndRun(fbipProgram, (guest) => {
    assert.equal(guest.call("loop_stmt_fbip", 0), expectedLoopSum(0));
    assert.equal(guest.call("loop_stmt_fbip", 100), expectedLoopSum(100));
    assert.equal(guest.call("loop_stmt_fbip", 50_000), expectedLoopSum(50_000));
    assert.equal(guest.call("branch_return_fbip", 100), expectedBranchSum(100));
    assert.equal(guest.call("block_break_fbip", 100), 2 + 4 + 6 + 8 + 100 + tailConstSum);
    const sa = 7 + 2 + 3 + 4 + tailConstSum;
    assert.equal(guest.call("alias_soundness", 7), sa * 1000 + (sa + 100));
    // Warm steady-state: repeated 50k-iteration statement-match FBIP loops must not grow linear memory.
    const raw = (guest as unknown as { exports?: Record<string, unknown> }).exports;
    const mem = raw?.["blot:memory"] as WebAssembly.Memory | undefined;
    if (mem) {
      const before = mem.buffer.byteLength;
      for (let r = 0; r < 5; r++) {
        assert.equal(guest.call("loop_stmt_fbip", 50_000), expectedLoopSum(50_000));
      }
      assert.equal(mem.buffer.byteLength, before);
    }
  });
});
