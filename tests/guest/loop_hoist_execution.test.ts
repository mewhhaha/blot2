import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("loop check hoisting, element address reuse, and zero-alloc loop elision preserve semantics across edge cases", async () => {
  await compileAndRun(`
type Cell is data = $Cell { x: F32, y: F32 }

// 1. Nested loop + if-let in-place updates (hoisted array checks + CheckedElem read-then-write)
io nested_match_update (n: U32): U32 =>
  let xs: #[Maybe Cell] = @array.fill n ($Some ($Cell { x: 1.0, y: 2.0 }))
  let ys: #[Maybe Cell] = @array.fill n ($Some ($Cell { x: 0.5, y: 0.25 }))
  for _ in 0 .. 4:
    for i in 0 .. n:
      if let $Some ($Cell { x, y }) = xs[i]:
        if let $Some ($Cell { x: dx, y: dy }) = ys[i]:
          xs[i] := $Some ($Cell { x: x + dx, y: y + dy })
  let sum = 0.0
  for i in 0 .. n:
    if let $Some ($Cell { x, y }) = xs[i]:
      sum := self + x + y
  return F32.to_u32 (sum * 10.0)

// 2. Non-in-place array carry swapping between two arrays in a noStorageResize loop
//    (must NOT hoist the carried handle across the swap!)
io swap_array_carry (steps: U32): U32 =>
  let a = #[10, 20, 30]
  let b = #[100, 200, 300]
  let cur = a
  let other = b
  let sum: U32 = 0
  for i in 0 .. steps:
    sum := self + cur[i % 3]
    let next_cur = other
    let next_other = cur
    cur := next_cur
    other := next_other
  return sum

// 3. Resizing loop inside a nested match/loop (must invalidate cached base/len on push!)
io nested_resize_growth (n: U32): U32 =>
  let out: #[U32] = #[1]
  for outer in 0 .. 2:
    for i in 0 .. n:
      if let $Some v = $Some (outer * 100 + i):
        @storage.push out v
  return out.length * 1000 + out[out.length - 1]

// 4. Zero-alloc inner \`for ever:\` with \`break\` nested inside an allocating outer loop
//    (outer loop must still reclaim its per-iteration scratch allocations safely)
io zero_alloc_inner_forever (rounds: U32): U32 =>
  let total: U32 = 0
  for r in 0 .. rounds:
    let scratch = @array.fill 2048 r
    let idx: U32 = 0
    for ever:
      if idx >= 8:
        break
      total := self + scratch[idx * 255]
      idx := self + 1
  return total

// 5. Same-index read-then-write and array spread in one function
io spread_and_reuse (seed: U32): U32 =>
  let base = #[seed, seed + 1, seed + 2]
  let expanded = #[99, ...base, 77]
  let dst = expanded.copy
  for i in 0 .. dst.length:
    dst[i] := dst[i] + expanded[i]
  return dst[0] + dst[1] + dst[2] + dst[3] + dst[4]
`, guest => {
    // 1. Each element starts (1.0, 2.0), +4*(0.5, 0.25) = (3.0, 3.0) => sum 6.0 each => 16 * 60 = 960
    equal(guest.call("nested_match_update", 16), 960);
    // 2. steps=6: cur[0]=a[0]=10, b[1]=200, a[2]=30, b[0]=100, a[1]=20, b[2]=300 => 660
    equal(guest.call("swap_array_carry", 6), 660);
    // 3. 1 initial + 2*64 pushes = 129 elements, last = 100 + 63 = 163 => 129163
    equal(guest.call("nested_resize_growth", 64), 129163);
    // 4. rounds=200 (would blow scratch if outer failed to reclaim!), sum of r*8 for r=0..199 = 8 * 19900 = 159200
    equal(guest.call("zero_alloc_inner_forever", 200), 159200);
    // 5. expanded=[99, 5, 6, 7, 77], doubled sum = 2*(99+5+6+7+77) = 388
    equal(guest.call("spread_and_reuse", 5), 388);
  });
});
