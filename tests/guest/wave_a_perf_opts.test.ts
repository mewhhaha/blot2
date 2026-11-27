import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

async function compileAndRun(
  source: string,
  run: (guest: Awaited<ReturnType<typeof instantiateGuest>>) => void | Promise<void>,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "blot-wave-a-" });
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
      await run(guest);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Wave A Pillar 1: direct rodata constant tables, literal appends, bounds & immutability traps", async () => {
  await compileAndRun(
    `
const U8_TBL: #[U8] = #[1u8, 2u8, 3u8, 250u8, 255u8]
const U32_TBL: #[U32] = #[10u32, 0xDEADBEEF, 42u32, 999999u32]
const I32_TBL: #[I32] = #[-1i32, -123456i32, 0i32, 777i32]
const U64_TBL: #[U64] = #[1u64, 0x0123456789ABCDEFu64, 99u64]
const F64_TBL: #[F64] = #[1.5f64, -2.25f64, 0.125f64]
const BYTES_1: #[U8] = b"A"
const BYTES_3: #[U8] = b"XYZ"
const BYTES_7: #[U8] = b"0123456"
const BYTES_8: #[U8] = b"ABCDEFGH"
const BYTES_11: #[U8] = b"hello world"
const BYTES_16: #[U8] = b"0123456789abcdef"
const BYTES_25: #[U8] = b"HTTP/1.1 200 OK\\r\\nServer:!"

io read_tables (i: U32): #[U32] =>
  let a = U8_TBL[i].to_u32
  let b = U32_TBL[i & 3]
  let c = (I32_TBL[i & 3] + 200000i32).to_u32
  let d = (U64_TBL[i % 3] & 0xFFFFFFFFu64).to_u32
  let e = ((F64_TBL[i % 3] + 10.0f64) * 8.0f64).to_u32
  return #[a, b, c, d, e, U8_TBL.length, BYTES_25.length]

io read_oob (i: U32): U32 =>
  return U8_TBL[i].to_u32

io extend_all (init_cap: U32): #[U8] =>
  let out: #[U8] = Array.with_capacity init_cap
  out := Array.extend self BYTES_1
  out := Array.extend self BYTES_3
  out := Array.extend self BYTES_7
  out := Array.extend self BYTES_8
  out := Array.extend self BYTES_11
  out := Array.extend self BYTES_16
  out := Array.extend self BYTES_25
  return out

func read_escaped (a: #[U8]) -> (i: U32): U32 =>
  return a[i].to_u32 + a.length

io read_escaped_const (i: U32): U32 =>
  return read_escaped U8_TBL i
`,
    (guest) => {
      const r1 = Array.from(guest.call("read_tables", 1) as Uint32Array);
      assert.deepEqual(r1, [2, 0xdeadbeef, 200000 - 123456, 0x89abcdef, 62, 5, 25]);
      const r4 = Array.from(guest.call("read_tables", 4) as Uint32Array);
      assert.deepEqual(r4, [255, 10, 199999, 0x89abcdef, 62, 5, 25]);

      assert.throws(() => guest.call("read_oob", 5), /unreachable/i);

      const expected = Array.from(
        new TextEncoder().encode(
          "AXYZ0123456ABCDEFGHhello world0123456789abcdefHTTP/1.1 200 OK\r\nServer:!",
        ),
      );
      for (const cap of [0, 1, 8, 128]) {
        const bytes = Array.from(guest.call("extend_all", cap) as Uint8Array);
        assert.deepEqual(bytes, expected);
      }

      // Escaping a constant table into a non-inlined function still works via static pool.
      assert.equal(guest.call("read_escaped_const", 3), 255);
    },
  );
});

Deno.test("Wave A Pillar 2: Mode-M/R workers, right-spine associative TCO, 1-level leaf peeling, mutual SCC & copiedBox", async () => {
  await compileAndRun(
    `
const NONE: U32 = 0xFFFFFFFF

type Node is data = $Node { left: U32, right: U32, val: U32 }

func build_tree (pool: own #[Node]) -> (d: U32) -> (seed: U32): (#[Node], U32) =>
  if d == 0:
    let idx = pool.length
    pool := self.push ($Node { left: NONE, right: NONE, val: seed })
    return (pool, idx)
  let (p1, l) = build_tree pool (d - 1) (seed * 3 + 1)
  let (p2, r) = build_tree p1 (d - 1) (seed * 3 + 2)
  let idx = p2.length
  p2 := self.push ($Node { left: l, right: r, val: seed })
  return (p2, idx)

func check_u32 (pool: #[Node]) -> (idx: U32): U32 =>
  let n = pool[idx]
  if n.left == NONE:
    return 1
  return (1 + check_u32 pool n.left) + check_u32 pool n.right

func sum_i64 (pool: #[Node]) -> (idx: U32): I64 =>
  if idx == NONE:
    return 0i64
  let n = pool[idx]
  return (n.val.to_i64 + sum_i64 pool n.left) + sum_i64 pool n.right

io run_trees (packed: U32): #[U32] =>
  let depth = packed & 0xFF
  let init_cap = packed >> 8
  let pool: #[Node] = Array.with_capacity init_cap
  let (p, root) = build_tree pool depth 1
  let c = check_u32 p root
  let s = sum_i64 p root
  return #[p.length, c, (s & 0xFFFFFFFFi64).to_u32]

io check_oob (): U32 =>
  let pool: #[Node] = Array.with_capacity 1
  let (p, _) = build_tree pool 1 1
  return check_u32 p 99

// Mutual SCC with Mode-R text + Mode-M AST pool + loop-carried pool + inlined helper.
type Expr is data = $Num { v: U32 } | $Add { l: U32, r: U32 } | $Mul { l: U32, r: U32 }

func skip_ws (text: #[U8]) -> (tlen: U32) -> (pos: U32): U32 =>
  let p = pos
  for ever:
    if p >= tlen:
      break
    if text[p] != ' ':
      break
    p := self + 1
  return p

func parse_atom (text: #[U8]) -> (tlen: U32) -> (pool: own #[Expr]) -> (pos: U32): (#[Expr], U32, U32, U32) =>
  let p = skip_ws text tlen pos
  if p >= tlen:
    return (pool, p, 0, 1)
  let c = text[p]
  if c >= '0' and c <= '9':
    let v: U32 = 0
    for ever:
      if p >= tlen:
        break
      let ch = text[p]
      if ch >= '0' and ch <= '9':
        v := self * 10 + (ch - '0').to_u32
        p := self + 1
      else:
        break
    let idx = pool.length
    pool := self.push ($Num { v })
    return (pool, p, idx, 0)
  if c == '(':
    let (p1, pos1, inner, err) = parse_add text tlen pool (p + 1)
    if err != 0:
      return (p1, pos1, 0, err)
    let pos2 = skip_ws text tlen pos1
    if pos2 >= tlen or text[pos2] != ')':
      return (p1, pos2, 0, 2)
    return (p1, pos2 + 1, inner, 0)
  return (pool, p, 0, 3)

func parse_mul (text: #[U8]) -> (tlen: U32) -> (pool: own #[Expr]) -> (pos: U32): (#[Expr], U32, U32, U32) =>
  let (p0, pos0, lhs0, err0) = parse_atom text tlen pool pos
  if err0 != 0:
    return (p0, pos0, 0, err0)
  pool := p0
  let cur = pos0
  let lhs = lhs0
  for ever:
    cur := skip_ws text tlen self
    if cur >= tlen or text[cur] != '*':
      break
    let (p1, pos1, rhs, err1) = parse_atom text tlen pool (cur + 1)
    if err1 != 0:
      return (p1, pos1, 0, err1)
    let idx = p1.length
    pool := p1.push ($Mul { l: lhs, r: rhs })
    lhs := idx
    cur := pos1
  return (pool, cur, lhs, 0)

func parse_add (text: #[U8]) -> (tlen: U32) -> (pool: own #[Expr]) -> (pos: U32): (#[Expr], U32, U32, U32) =>
  let (p0, pos0, lhs0, err0) = parse_mul text tlen pool pos
  if err0 != 0:
    return (p0, pos0, 0, err0)
  pool := p0
  let cur = pos0
  let lhs = lhs0
  for ever:
    cur := skip_ws text tlen self
    if cur >= tlen or text[cur] != '+':
      break
    let (p1, pos1, rhs, err1) = parse_mul text tlen pool (cur + 1)
    if err1 != 0:
      return (p1, pos1, 0, err1)
    let idx = p1.length
    pool := p1.push ($Add { l: lhs, r: rhs })
    lhs := idx
    cur := pos1
  return (pool, cur, lhs, 0)

func eval_expr (pool: #[Expr]) -> (idx: U32): U32 =>
  case pool[idx] of
    $Num { v } => v
    $Add { l, r } => eval_expr pool l + eval_expr pool r
    $Mul { l, r } => eval_expr pool l * eval_expr pool r

const EXPR_OK: #[U8] = b"(2 + 3) * (4 + 5 * 6) + 7"
const EXPR_BAD: #[U8] = b"(2 + 3"

io eval_case (mode: U32): #[U32] =>
  let init_cap = mode & 0xFF
  let is_bad = (mode >> 8) != 0
  let text = if is_bad then EXPR_BAD else EXPR_OK
  let pool: #[Expr] = Array.with_capacity init_cap
  let (p, end_pos, root, err) = parse_add text text.length pool 0
  if err != 0:
    return #[err, end_pos, 0]
  return #[0, end_pos, eval_expr p root]

// Mode-R mutable worker on >64-byte copiedBox record elements.
type BigNode is data = $BigNode {
  child: U32, sibling: U32,
  a0: F32, a1: F32, a2: F32, a3: F32, a4: F32, a5: F32, a6: F32, a7: F32,
  b0: F32, b1: F32, b2: F32, b3: F32, b4: F32, b5: F32, b6: F32, b7: F32
}

func update_big (nodes: own #[BigNode]) -> (idx: U32) -> (acc: F32): #[BigNode] =>
  let cur = nodes[idx].a0 + acc
  nodes[idx].b0 := cur
  let ch = nodes[idx].child
  for ever:
    if ch == NONE:
      break
    nodes := update_big self ch cur
    ch := nodes[ch].sibling
  return nodes

io run_big (): U32 =>
  let nodes: #[BigNode] = Array.with_capacity 4
  nodes := self.push ($BigNode { child: 1, sibling: NONE, a0: 10.0f32, a1: 0.0f32, a2: 0.0f32, a3: 0.0f32, a4: 0.0f32, a5: 0.0f32, a6: 0.0f32, a7: 0.0f32, b0: 0.0f32, b1: 0.0f32, b2: 0.0f32, b3: 0.0f32, b4: 0.0f32, b5: 0.0f32, b6: 0.0f32, b7: 0.0f32 })
  nodes := self.push ($BigNode { child: 2, sibling: 3, a0: 5.0f32, a1: 0.0f32, a2: 0.0f32, a3: 0.0f32, a4: 0.0f32, a5: 0.0f32, a6: 0.0f32, a7: 0.0f32, b0: 0.0f32, b1: 0.0f32, b2: 0.0f32, b3: 0.0f32, b4: 0.0f32, b5: 0.0f32, b6: 0.0f32, b7: 0.0f32 })
  nodes := self.push ($BigNode { child: NONE, sibling: NONE, a0: 2.0f32, a1: 0.0f32, a2: 0.0f32, a3: 0.0f32, a4: 0.0f32, a5: 0.0f32, a6: 0.0f32, a7: 0.0f32, b0: 0.0f32, b1: 0.0f32, b2: 0.0f32, b3: 0.0f32, b4: 0.0f32, b5: 0.0f32, b6: 0.0f32, b7: 0.0f32 })
  nodes := self.push ($BigNode { child: NONE, sibling: NONE, a0: 7.0f32, a1: 0.0f32, a2: 0.0f32, a3: 0.0f32, a4: 0.0f32, a5: 0.0f32, a6: 0.0f32, a7: 0.0f32, b0: 0.0f32, b1: 0.0f32, b2: 0.0f32, b3: 0.0f32, b4: 0.0f32, b5: 0.0f32, b6: 0.0f32, b7: 0.0f32 })
  nodes := update_big self 0 1.0f32
  return (nodes[0].b0 + nodes[1].b0 + nodes[2].b0 + nodes[3].b0).to_u32
`,
    (guest) => {
      // Test leaf peeling + Mode-M dynamic growth across d = 0, 1, 2, 5 and cap = 0, 1, 64.
      for (const depth of [0, 1, 2, 5]) {
        const expectedNodes = (1 << (depth + 1)) - 1;
        const r0 = Array.from(guest.call("run_trees", depth | (0 << 8)) as Uint32Array);
        const r1 = Array.from(guest.call("run_trees", depth | (1 << 8)) as Uint32Array);
        const r64 = Array.from(guest.call("run_trees", depth | (64 << 8)) as Uint32Array);
        assert.equal(r0[0], expectedNodes);
        assert.equal(r0[1], expectedNodes);
        assert.deepEqual(r0, r1);
        assert.deepEqual(r0, r64);
      }
      assert.throws(() => guest.call("check_oob", null), /unreachable/i);

      // Mutual SCC parser: "(2 + 3) * (4 + 5 * 6) + 7" = 5 * 34 + 7 = 177.
      assert.deepEqual(Array.from(guest.call("eval_case", 0) as Uint32Array), [0, 25, 177]);
      assert.deepEqual(Array.from(guest.call("eval_case", 1) as Uint32Array), [0, 25, 177]);
      assert.deepEqual(Array.from(guest.call("eval_case", (1 << 8) | 1) as Uint32Array), [2, 6, 0]);

      // copiedBox recursive Mode-R mutable worker: 11 + 16 + 18 + 18 = 63.
      assert.equal(guest.call("run_big", null), 63);
    },
  );
});

Deno.test("Wave A Pillar 3+4: wide aggregate leaf inline, non-resizing own helper, scalar-packed DirectArray & extend_view", async () => {
  await compileAndRun(
    `
type Mat12 is data = $Mat12 {
  m0: F32, m1: F32, m2: F32, m3: F32,
  m4: F32, m5: F32, m6: F32, m7: F32,
  m8: F32, m9: F32, m10: F32, m11: F32
}

func compose12 (a: Mat12) -> (b: Mat12): Mat12 =>
  return $Mat12 {
    m0: a.m0 * b.m0 + a.m1 * b.m4 + a.m2 * b.m8,
    m1: a.m0 * b.m1 + a.m1 * b.m5 + a.m2 * b.m9,
    m2: a.m0 * b.m2 + a.m1 * b.m6 + a.m2 * b.m10,
    m3: a.m0 * b.m3 + a.m1 * b.m7 + a.m2 * b.m11 + a.m3,
    m4: a.m4 * b.m0 + a.m5 * b.m4 + a.m6 * b.m8,
    m5: a.m4 * b.m1 + a.m5 * b.m5 + a.m6 * b.m9,
    m6: a.m4 * b.m2 + a.m5 * b.m6 + a.m6 * b.m10,
    m7: a.m4 * b.m3 + a.m5 * b.m7 + a.m6 * b.m11 + a.m7,
    m8: a.m8 * b.m0 + a.m9 * b.m4 + a.m10 * b.m8,
    m9: a.m8 * b.m1 + a.m9 * b.m5 + a.m10 * b.m9,
    m10: a.m8 * b.m2 + a.m9 * b.m6 + a.m10 * b.m10,
    m11: a.m8 * b.m3 + a.m9 * b.m7 + a.m10 * b.m11 + a.m11
  }

io run_compose (n: U32): U32 =>
  let cur = $Mat12 { m0: 1.0f32, m1: 0.0f32, m2: 0.0f32, m3: 0.0f32, m4: 0.0f32, m5: 1.0f32, m6: 0.0f32, m7: 0.0f32, m8: 0.0f32, m9: 0.0f32, m10: 1.0f32, m11: 0.0f32 }
  let step = $Mat12 { m0: 1.0f32, m1: 0.0f32, m2: 0.0f32, m3: 1.0f32, m4: 0.0f32, m5: 1.0f32, m6: 0.0f32, m7: 2.0f32, m8: 0.0f32, m9: 0.0f32, m10: 1.0f32, m11: 3.0f32 }
  for _ in 0 .. n:
    cur := compose12 self step
  return (cur.m3 + cur.m7 + cur.m11).to_u32

// Non-resizing own helper preserving hoisted array descriptors across loops and if merges.
func shift_clear (slots: own #[U32]) -> (mask: U32) -> (at: U32): #[U32] =>
  let i = at
  let j = i
  for ever:
    j := (self + 1) & mask
    let v = slots[j]
    if v == 0:
      break
    if (v & 1) == 1:
      slots[i] := v
      i := j
  slots[i] := 0
  return slots

io run_shift (): U32 =>
  let slots = @array.fill 16 0
  for i in 0 .. 12:
    slots[i] := (i * 2) + 1
  for step in 0 .. 8:
    if (step & 1) == 0:
      slots := shift_clear self 15 (step & 7)
    slots[(step + 4) & 15] := self + 2
  let sum: U32 = 0
  for i in 0 .. 16:
    sum := self + slots[i]
  return sum

// Tiny <= 16-byte scalar-packed DirectArray (U8 & Bool, zero & non-zero fill, literal, RMW, loop carry, OOB trap).
io run_scalar_packed (v: U32): #[U32] =>
  // 10-byte U8 buffer (crosses low/high 64-bit lanes: indices 0..7 and 8..9)
  let digs = @array.fill 10 0u8
  let n: U32 = 0
  let x = v
  for ever:
    digs[n] := (48 + (x % 10)).to_u8
    n := self + 1
    x := self / 10
    if x == 0:
      break
  // 16-byte non-zero fill + RMW update across both lanes
  let buf16 = @array.fill 16 0x5au8
  for i in 0 .. 16:
    buf16[i] := (self + i.to_u8) & 0xFFu8
  // Literal small U8 array + Bool packed array
  let lit: #[U8] = #[3u8, 7u8, 11u8, 13u8, 17u8]
  let flags = @array.fill 12 true
  flags[3] := false
  flags[10] := false
  let fcount: U32 = 0
  for i in 0 .. 12:
    if flags[i]:
      fcount := self + 1
  let dsum: U32 = 0
  for i in 0 .. n:
    dsum := self + digs[i].to_u32
  let bsum: U32 = 0
  for i in 0 .. 16:
    bsum := self + buf16[i].to_u32
  return #[n, dsum, bsum, lit[0].to_u32 + lit[4].to_u32, fcount]

io scalar_packed_oob_read (idx: U32): U32 =>
  let buf = @array.fill 10 0u8
  return buf[idx].to_u32

io scalar_packed_oob_write (idx: U32): U32 =>
  let buf = @array.fill 16 1u8
  buf[idx] := 2u8
  return buf[0].to_u32

// Selective resize with Array.with_capacity + Array.extend_view + non-resized read array.
io run_extend_view (reps: U32): #[U32] =>
  let dict: #[U8] = b"alpha beta gamma delta"
  let spans: #[U32] = #[5u32, 100u32, 181u32, 277u32]
  let out: #[U8] = Array.with_capacity 2
  for i in 0 .. reps:
    let sp = spans[i & 3]
    let ds = sp >> 4
    let dl = sp & 15
    out := Array.extend_view self dict[ds .. ds + dl]
    out := self.push ' '
  let h: U32 = 0
  for i in 0 .. out.length:
    h := self * 31 + out[i].to_u32
  return #[out.length, h]
`,
    (guest) => {
      assert.equal(guest.call("run_compose", 10), 60);

      // Compute expected sum for run_shift in JS.
      const s = new Uint32Array(16);
      for (let i = 0; i < 12; i++) s[i] = i * 2 + 1;
      for (let step = 0; step < 8; step++) {
        if ((step & 1) === 0) {
          let i = step & 7;
          let j = i;
          while (true) {
            j = (j + 1) & 15;
            const v = s[j];
            if (v === 0) break;
            if ((v & 1) === 1) {
              s[i] = v;
              i = j;
            }
          }
          s[i] = 0;
        }
        s[(step + 4) & 15] = (s[(step + 4) & 15] + 2) >>> 0;
      }
      const expectedShift = Array.from(s).reduce((a, b) => (a + b) >>> 0, 0);
      assert.equal(guest.call("run_shift", null), expectedShift);

      // v = 123456789 -> 9 digits '1'..'9', sum of ASCII 49..57 = 477
      // buf16: sum_{i=0}^{15} (0x5a + i) = 16*90 + 120 = 1560
      // lit[0] + lit[4] = 3 + 17 = 20; flags: 10 true
      assert.deepEqual(
        Array.from(guest.call("run_scalar_packed", 123456789) as Uint32Array),
        [9, 477, 1560, 20, 10],
      );
      assert.throws(() => guest.call("scalar_packed_oob_read", 10), /unreachable/i);
      assert.throws(() => guest.call("scalar_packed_oob_write", 16), /unreachable/i);

      // 8 reps = 2 full cycles of ("alpha " + "beta " + "gamma " + "delta ") = 2 * 23 = 46 bytes
      const ev = Array.from(guest.call("run_extend_view", 8) as Uint32Array);
      assert.equal(ev[0], 46);
      const expectedStr = "alpha beta gamma delta alpha beta gamma delta ";
      let h = 0;
      for (const b of new TextEncoder().encode(expectedStr)) {
        h = (Math.imul(h, 31) + b) >>> 0;
      }
      assert.equal(ev[1], h);
    },
  );
});
