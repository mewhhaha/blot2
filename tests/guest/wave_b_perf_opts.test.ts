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
  const dir = await Deno.makeTempDir({ prefix: "squid-wave-b-" });
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

Deno.test("Wave B Pillar 1: unobservable-NaN elision preserves semantics and keeps canonical NaN when bits/floats are observed", async () => {
  // Module with no float exports and no .bits: NaN comparisons & trunc_sat stay exact.
  await compileAndRun(
    `
io check_nan (z: U32): #[U32] =>
  let a: F32 = U32.to_f32 z
  let b: F32 = a / a
  let c: F32 = b * 2.0 + 1.0
  let eq_self: U32 = if c == c then 1 else 0
  let ne_self: U32 = if c != c then 1 else 0
  let lt_one: U32 = if c < 1.0 then 1 else 0
  let sat: U32 = c.to_i64.to_u32
  let d: F64 = U32.to_f64 z
  let e: F64 = d / d
  let d_eq: U32 = if e == e then 1 else 0
  let d_sat: U32 = e.to_i64.to_u32
  return #[eq_self, ne_self, lt_one, sat, d_eq, d_sat]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("check_nan", 0) as Uint32Array),
        [0, 1, 0, 0, 0, 0],
      );
      assert.deepEqual(
        Array.from(guest.call("check_nan", 5) as Uint32Array),
        [1, 0, 0, 3, 1, 1],
      );
    },
  );

  // Module observing F32.to_bits / F64.to_bits MUST keep canonical NaN bits.
  await compileAndRun(
    `
io nan_bits (z: U32): #[U32] =>
  let a: F32 = U32.to_f32 z
  let q32: F32 = (0.0 - a) / a
  let b32: U32 = F32.to_bits q32
  let d: F64 = U32.to_f64 z
  let q64: F64 = (0.0f64 - d) / d
  let b64: U64 = F64.to_bits q64
  return #[b32, (b64 & 0xFFFFFFFFu64).to_u32, (b64 >> 32u64).to_u32]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("nan_bits", 0) as Uint32Array),
        [0x7fc00000, 0x00000000, 0x7ff80000],
      );
    },
  );
});

Deno.test("Wave B Pillar 2: wide all-F32 v128 worker packing and storeAtPack preserve transform values and OOB traps", async () => {
  await compileAndRun(
    `
type Xf is data = $Xf { m0: F32, m1: F32, m2: F32, m3: F32, m4: F32, m5: F32, m6: F32, m7: F32, m8: F32, tx: F32, ty: F32, tz: F32 }
type Node is data = $Node { local: Xf, world: Xf, l: U32, r: U32 }

func ident (): Xf => $Xf { m0: 1.0, m1: 0.0, m2: 0.0, m3: 0.0, m4: 1.0, m5: 0.0, m6: 0.0, m7: 0.0, m8: 1.0, tx: 0.0, ty: 0.0, tz: 0.0 }

func compose (p: Xf) -> (l: Xf): Xf => $Xf {
  m0: p.m0 * l.m0 + p.m1 * l.m3 + p.m2 * l.m6,
  m1: p.m0 * l.m1 + p.m1 * l.m4 + p.m2 * l.m7,
  m2: p.m0 * l.m2 + p.m1 * l.m5 + p.m2 * l.m8,
  m3: p.m3 * l.m0 + p.m4 * l.m3 + p.m5 * l.m6,
  m4: p.m3 * l.m1 + p.m4 * l.m4 + p.m5 * l.m7,
  m5: p.m3 * l.m2 + p.m4 * l.m5 + p.m5 * l.m8,
  m6: p.m6 * l.m0 + p.m7 * l.m3 + p.m8 * l.m6,
  m7: p.m6 * l.m1 + p.m7 * l.m4 + p.m8 * l.m7,
  m8: p.m6 * l.m2 + p.m7 * l.m5 + p.m8 * l.m8,
  tx: p.m0 * l.tx + p.m1 * l.ty + p.m2 * l.tz + p.tx,
  ty: p.m3 * l.tx + p.m4 * l.ty + p.m5 * l.tz + p.ty,
  tz: p.m6 * l.tx + p.m7 * l.ty + p.m8 * l.tz + p.tz,
}

func update (pool: own #[Node]) -> (idx: U32) -> (parent: Xf): #[Node] =>
  let w = compose parent pool[idx].local
  pool[idx].world := w
  let lc = pool[idx].l
  let rc = pool[idx].r
  if lc != 0:
    pool := update self lc w
  if rc != 0:
    pool := update self rc w
  return pool

io run_scene (root: U32): I64 =>
  let id = ident ()
  let a = $Xf { m0: 0.0, m1: -1.0, m2: 0.0, m3: 1.0, m4: 0.0, m5: 0.0, m6: 0.0, m7: 0.0, m8: 1.0, tx: 2.0, ty: 3.0, tz: 4.0 }
  let b = $Xf { m0: 1.0, m1: 0.0, m2: 0.0, m3: 0.0, m4: 1.0, m5: 0.0, m6: 0.0, m7: 0.0, m8: 1.0, tx: 5.0, ty: 7.0, tz: 11.0 }
  let c = $Xf { m0: 1.0, m1: 0.0, m2: 0.0, m3: 0.0, m4: 1.0, m5: 0.0, m6: 0.0, m7: 0.0, m8: 1.0, tx: 13.0, ty: 17.0, tz: 19.0 }
  let pool: #[Node] = #[
    $Node { local: a, world: id, l: 1, r: 2 },
    $Node { local: b, world: id, l: 0, r: 0 },
    $Node { local: c, world: id, l: 0, r: 0 },
  ]
  pool := update self root id
  let sum: I64 = 0i64
  for i in 0 .. pool.length:
    let w = pool[i].world
    sum := self + (w.tx + w.ty + w.tz).to_i64
  return sum
`,
    (guest) => {
      // Node 0 world: (2, 3, 4) -> sum 9
      // Node 1 world: rot90(5,7,11) + (2,3,4) = (-7+2, 5+3, 11+4) = (-5, 8, 15) -> sum 18
      // Node 2 world: rot90(13,17,19) + (2,3,4) = (-17+2, 13+3, 19+4) = (-15, 16, 23) -> sum 24
      assert.equal(guest.call("run_scene", 0), 51n);
      assert.throws(() => guest.call("run_scene", 9), /unreachable/i);
    },
  );
});

Deno.test("Wave B Pillar 3: masked loop-carry BCE, mask==len-1 zero-len traps, and converging 2-pointer BCE", async () => {
  await compileAndRun(
    `
const NONE: U32 = 0xFFFFFFFF
type Slot is data = $Slot { key: U32, val: U32 }

func home (k: U32) -> (mask: U32): U32 =>
  return ((k * 0x9E3779B1) ^ (k >> 16)) & mask

func find_slot (slots: #[Slot]) -> (mask: U32) -> (key: U32): U32 =>
  let i = home key mask
  for ever:
    let $Slot { key: sk, val: sv } = slots[i]
    if sv == NONE or sk == key:
      break
    i := (self + 1) & mask
  return i

func map_remove (slots: own #[Slot]) -> (mask: U32) -> (at: U32): #[Slot] =>
  let i = at
  let j = i
  for ever:
    j := (self + 1) & mask
    let s = slots[j]
    if s.val == NONE:
      break
    let h = home s.key mask
    if (i < j and (h <= i or h > j)) or (i > j and h <= i and h > j):
      slots[i] := s
      i := j
  slots[i] := $Slot { key: 0, val: NONE }
  return slots

io hash_test (nslots: U32): U32 =>
  let mask = nslots - 1
  let slots = @array.fill nslots ($Slot { key: 0, val: NONE })
  for k in 1 .. 10:
    let at = find_slot slots mask k
    slots[at] := $Slot { key: k, val: k * 10 }
  for k in 1 .. 5:
    let at = find_slot slots mask k
    slots := map_remove self mask at
  let sum: U32 = 0
  for k in 1 .. 10:
    let at = find_slot slots mask k
    if slots[at].val != NONE:
      sum := self + slots[at].val
  return sum

io rev_prefix (k: U32): #[U32] =>
  let a = @array.fill 6 0
  for i in 0 .. 6:
    a[i] := i + 1
  let lo: U32 = 0
  let hi = k
  for ever:
    if lo >= hi:
      break
    let tmp = a[lo]
    a[lo] := a[hi]
    a[hi] := tmp
    lo := self + 1
    hi := self - 1
  return a

io rev_empty_high (lo_init: U32): U32 =>
  let a = @array.fill 4 0
  let lo = lo_init
  let hi: U32 = 10
  for ever:
    if lo >= hi:
      break
    a[lo] := a[hi]
    lo := self + 1
    hi := self - 1
  return a[0]
`,
    (guest) => {
      // Remaining keys 5..9 => (5+6+7+8+9)*10 = 350
      assert.equal(guest.call("hash_test", 16), 350);
      // nslots == 0 must still trap cleanly on first slots[i] access!
      assert.throws(() => guest.call("hash_test", 0), /unreachable/i);

      // Prefix reversals: valid k < 6, k == 0 no-op, k >= 6 traps!
      assert.deepEqual(
        Array.from(guest.call("rev_prefix", 4) as Uint32Array),
        [5, 4, 3, 2, 1, 6],
      );
      assert.deepEqual(
        Array.from(guest.call("rev_prefix", 0) as Uint32Array),
        [1, 2, 3, 4, 5, 6],
      );
      assert.throws(() => guest.call("rev_prefix", 6), /unreachable/i);
      // When lo_init >= hi (10 >= 10), loop exits immediately without indexing a[10] -> must NOT trap!
      assert.equal(guest.call("rev_empty_high", 10), 0);
      assert.throws(() => guest.call("rev_empty_high", 0), /unreachable/i);
    },
  );
});

Deno.test("Wave B Pillar 4: inlined small-fill helpers, if_value-push SCC workers, and external direct worker calls", async () => {
  await compileAndRun(
    `
type Expr is data = $Num { v: U32 } | $Add { l: U32, r: U32 } | $Mul { l: U32, r: U32 }

func emit_uint (buf: own #[U8]) -> (v: U32): #[U8] =>
  if v == 0:
    return buf.push '0'
  let digits = @array.fill 10 0u8
  let n: U32 = 0
  let x = v
  for ever:
    if x == 0:
      break
    digits[n] := (48 + (x % 10)).to_u8
    n := self + 1
    x := self / 10
  for ever:
    if n == 0:
      break
    n := self - 1
    buf := self.push digits[n]
  return buf

func gen_list (buf: own #[U8]) -> (d: U32) -> (seed: U32): #[U8] =>
  if d == 0:
    buf := emit_uint self seed
    return buf.push ' '
  buf := self.push '('
  buf := gen_list self (d - 1) (seed * 3 + 1)
  buf := gen_list self (d - 1) (seed * 3 + 2)
  buf := self.push ')'
  return buf

func build_ast (pool: own #[Expr]) -> (d: U32) -> (seed: U32): (#[Expr], U32) =>
  if d == 0:
    let idx = pool.length
    pool := self.push ($Num { v: seed })
    return (pool, idx)
  let (p1, l) = build_ast pool (d - 1) (seed + 1)
  let (p2, r) = build_ast p1 (d - 1) (seed + 2)
  let idx = p2.length
  let p3 = if (seed & 1) == 0 then p2.push ($Add { l, r }) else p2.push ($Mul { l, r })
  return (p3, idx)

func eval_ast (pool: #[Expr]) -> (idx: U32): U32 =>
  case pool[idx] of
    $Num { v } => v
    $Add { l, r } => eval_ast pool l + eval_ast pool r
    $Mul { l, r } => eval_ast pool l * eval_ast pool r

io test_gen (d: U32): #[U8] =>
  let buf: #[U8] = Array.with_capacity 32
  for i in 0 .. 2:
    buf := gen_list self d (i + 1)
  return buf

io test_ast (d: U32): U32 =>
  let pool: #[Expr] = Array.with_capacity 16
  let (p, root) = build_ast pool d 2
  return eval_ast p root
`,
    (guest) => {
      const text = new TextDecoder().decode(guest.call("test_gen", 1) as Uint8Array);
      assert.equal(text, "(4 5 )(7 8 )");
      // d=2, seed=2 (even => Add):
      //   left(d=1, seed=3 odd => Mul): Num(4) * Num(5) = 20
      //   right(d=1, seed=4 even => Add): Num(5) + Num(6) = 11
      //   total = 20 + 11 = 31
      assert.equal(guest.call("test_ast", 2), 31);
    },
  );
  // Passing a static const array to an `own` external worker param must be rejected at compile time.
  const dir = await Deno.makeTempDir({ prefix: "squid-wave-b-frozen-" });
  const entry = `${dir}/main.sq`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    stdRoot,
  });
  try {
    const built = await compiler.build({
      sources: {
        [entry]: `
const FROZEN: #[U8] = b"x"
func gen_list (buf: own #[U8]) -> (d: U32): #[U8] =>
  if d == 0:
    return buf.push '!'
  buf := gen_list self (d - 1)
  return buf
io test_frozen (d: U32): #[U8] =>
  return gen_list FROZEN d
`,
      },
    });
    assert.equal(built.success, false, "Passing static const to own param must fail check/lower");
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
});
