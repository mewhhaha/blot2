import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

async function compileAndRun(
  source: string,
  run: (guest: Awaited<ReturnType<typeof instantiateGuest>>) => void | Promise<void>,
  _opts?: unknown,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "squid-batch5-" });
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
      await run(guest);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

async function compileExpectedFailure(source: string, code: string): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "squid-batch5-fail-" });
  const entry = `${dir}/main.sq`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    stdRoot,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(!built.success, "Expected compilation to fail");
    const hasCode = built.diagnostics.some((d) => d.code === code);
    assert(
      hasCode,
      `Expected diagnostic ${code}, got: ${JSON.stringify(built.diagnostics)}`,
    );
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

const opts = {};

Deno.test("Batch 5 Opt 1+3: hoisted CheckedGrow push/extend/reserve & own param mutation", async () => {
  await compileAndRun(
    `
func fill_and_bump (dst: own #[U32]) -> (n: U32): #[U32] =>
  let seed: U32 = 17
  for i in 0 .. n:
    seed := (self * 1103515245 + 12345) & 0xFFFF
    dst := self.push (seed ^ i)
  dst := Array.reserve self n
  let extra = #[10u32, 20u32, 30u32]
  for _ in 0 .. 5:
    dst := Array.extend self extra
  for i in 0 .. dst.length:
    dst[i] := self + 1
  return dst

io run_grow (n: U32): #[U32] =>
  // Start with tiny capacity so push grows past initial stack backing onto heap mid-loop.
  let buf: #[U32] = Array.with_capacity 4
  let filled = fill_and_bump buf n
  let sum: U32 = 0
  for i in 0 .. filled.length:
    sum := self + filled[i]
  return #[filled.length, sum]
`,
    (guest) => {
      const n = 500;
      let seed = 17 >>> 0;
      let expectedSum = 0 >>> 0;
      for (let i = 0; i < n; i++) {
        seed = (Math.imul(seed, 1103515245) + 12345) & 0xffff;
        expectedSum = (expectedSum + ((seed ^ i) + 1)) >>> 0;
      }
      for (let k = 0; k < 5; k++) {
        expectedSum = (expectedSum + 11 + 21 + 31) >>> 0;
      }
      assert.deepEqual(Array.from(guest.call("run_grow", n) as Uint32Array), [
        n + 15,
        expectedSum,
      ]);
    },
    opts,
  );
});
Deno.test("Batch 5 Opt 2: F64 and F64x2 NaN-canonicalization elision preserves canonical NaN at all boundaries", async () => {
  await compileAndRun(
    `
import * as simd from "std/simd"

func pair_mag (dx: simd.F64x2) -> (dy: simd.F64x2) -> (dz: simd.F64x2) -> (dt_v: simd.F64x2): simd.F64x2 =>
  let d2 = simd.f64_add (simd.f64_add (simd.f64_mul dx dx) (simd.f64_mul dy dy)) (simd.f64_mul dz dz)
  return simd.f64_div dt_v (simd.f64_mul d2 (simd.f64_sqrt d2))

func return_nan (x: F64): F64 =>
  let inf = 1.0f64 / x
  return inf - inf

io test_nan_boundaries (n: U32): #[U32] =>
  let z: F64 = n.to_f64
  // 1. Direct F64.to_bits of NaN-producing expression
  let b1 = F64.to_bits (z / z)
  // 2. Non-canonical NaN payload fed through F64 add must canonicalize before to_bits
  let dirty = F64.from_bits 0x7ff8_0000_0000_1234u64
  let b2 = F64.to_bits (dirty + 1.0f64)
  // 3. Returning NaN from helper must produce canonical NaN
  let b3 = F64.to_bits (return_nan z)
  // 4. Storing NaN into an array must store canonical NaN
  let arr = @array.fill 2 0.0f64
  arr[0] := (dirty * 2.0f64) + 3.0f64
  let b4 = F64.to_bits arr[0]
  // 5. F64x2 helper whose result is bit-observed must canonicalize both lanes
  let zv = simd.f64_splat z
  let dv = simd.f64_splat dirty
  let (lo5, hi5) = simd.f64_bits (pair_mag dv zv zv (simd.f64_splat 1.0f64))
  // 6. F64x2 helper destructured and consumed only by scalar multiply (elision path)
  let dx0 = 3.0f64 - z
  let dx1 = 0.0f64 - z
  let dy0 = 4.0f64 - z
  let dy1 = 1.0f64 - z
  let (m0, m1) = pair_mag (dx0, dx1) (dy0, dy1) (0.0f64, 0.0f64) (simd.f64_splat 125.0f64)
  // m0 = 125 / (25 * 5) = 1.0, m1 = 125 / (1 * 1) = 125.0
  let prod_ok: U32 = if F64.to_u32 (m0 * 10.0f64 + m1) == 135 then 1 else 0
  // 7. Counted scalar F64 loop with deferred NaN canonicalization must still
  // canonicalize dirty NaNs for steps = 1 and steps = 5, and preserve initial value for steps = 0.
  let a0 = dirty
  for _ in 0 .. 5:
    a0 := self + 1.0f64
  let b7 = F64.to_bits a0
  let a1 = dirty
  for _ in 0 .. 1:
    a1 := self * 2.0f64
  let b8 = F64.to_bits a1
  let a_zero = 42.0f64
  for _ in 0 .. n:
    a_zero := self + 1.0f64
  let zero_ok: U32 = if a_zero == 42.0f64 then 1 else 0
  let canon: U64 = 0x7ff8_0000_0000_0000u64
  return #[
    if b1 == canon then 1 else 0,
    if b2 == canon then 1 else 0,
    if b3 == canon then 1 else 0,
    if b4 == canon then 1 else 0,
    if lo5 == canon and hi5 == canon then 1 else 0,
    prod_ok,
    if b7 == canon then 1 else 0,
    if b8 == canon then 1 else 0,
    zero_ok,
  ]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("test_nan_boundaries", 0) as Uint32Array),
        [1, 1, 1, 1, 1, 1, 1, 1, 1],
      );
    },
    opts,
  );
});
Deno.test("Batch 5 Opt 4: recursive own storage (direct, growing, mutual, non-first param)", async () => {
  await compileAndRun(
    `
type TNode is data = $TNode { l: U32, r: U32 }
const NONE: U32 = 0xFFFFFFFF

func build_tree (pool: own #[TNode]) -> (d: U32): (#[TNode], U32) =>
  if d == 0:
    let idx = pool.length
    pool := self.push ($TNode { l: NONE, r: NONE })
    return (pool, idx)
  let (p1, l) = build_tree pool (d - 1)
  let (p2, r) = build_tree p1 (d - 1)
  let idx = p2.length
  let p3 = p2.push ($TNode { l, r })
  return (p3, idx)

func check_tree (pool: #[TNode]) -> (idx: U32): U32 =>
  let nd = pool[idx]
  if nd.l == NONE:
    return 1
  return 1 + check_tree pool nd.l + check_tree pool nd.r

func even_push (n: U32) -> (acc: own #[U32]): #[U32] =>
  if n == 0:
    return acc
  acc := self.push (n * 2)
  return odd_push (n - 1) acc

func odd_push (n: U32) -> (acc: own #[U32]): #[U32] =>
  if n == 0:
    return acc
  acc := self.push (n * 2 + 1)
  return even_push (n - 1) acc

io test_rec_own (depth: U32): #[U32] =>
  // Pre-sized pool
  let p_pre: #[TNode] = Array.with_capacity ((1 << (depth + 1)) - 1)
  let (tree1, root1) = build_tree p_pre depth
  let c1 = check_tree tree1 root1

  // Tiny initial capacity to force heap reallocation mid-recursion
  let p_grow: #[TNode] = Array.with_capacity 4
  let (tree2, root2) = build_tree p_grow depth
  let c2 = check_tree tree2 root2

  // Mutually recursive with own in parameter position 1 (non-first)
  let m0: #[U32] = Array.with_capacity 2
  let m1 = even_push 10 m0
  let msum: U32 = 0
  for i in 0 .. m1.length:
    msum := self + m1[i]

  return #[c1, c2, tree1.length, tree2.length, m1.length, msum]
`,
    (guest) => {
      const depth = 11;
      const nodes = (1 << (depth + 1)) - 1; // 4095
      // even_push 10 pushes: 20, 19, 16, 15, 12, 11, 8, 7, 4, 3 -> sum = 115
      assert.deepEqual(
        Array.from(guest.call("test_rec_own", depth) as Uint32Array),
        [nodes, nodes, nodes, nodes, 10, 115],
      );
    },
    opts,
  );
});
Deno.test("Batch 5 Opt 4 negative: aliased recursive own call is rejected by uniqueness", async () => {
  await compileExpectedFailure(
    `
func bad_rec (pool: own #[U32]) -> (d: U32): (#[U32], U32) =>
  if d == 0:
    return (pool, 0)
  let (p1, a) = bad_rec pool (d - 1)
  // Illegal: reuses consumed 'pool' instead of 'p1'
  let (p2, b) = bad_rec pool (d - 1)
  return (p2, a + b + p1.length)

io run (n: U32): U32 =>
  let p: #[U32] = Array.with_capacity 8
  let (_, c) = bad_rec p n
  return c
`,
    "spent_value",
  );
});

Deno.test("Batch 5 Opt 3 negative: static const array cannot be passed to own parameter", async () => {
  await compileExpectedFailure(
    `
const STATIC_ARR: #[U32] = #[1, 2, 3, 4]

func mutate_it (a: own #[U32]): #[U32] =>
  a[0] := 99
  return a

io run (n: U32): U32 =>
  let b = mutate_it STATIC_ARR
  return b[0] + n
`,
    "own_argument",
  );
});

Deno.test("Batch 5 Opt 5: stack-backed Array.with_capacity rewinds cleanly across 20,000 calls", async () => {
  await compileAndRun(
    `
func scratch_sum (n: U32) -> (seed: U32): U32 =>
  // 4096 * 4 = 16 KiB per call; 20,000 calls = 320 MiB cumulative (> 64 MiB stack!)
  let buf: #[U32] = Array.with_capacity 4096
  for i in 0 .. n:
    buf := self.push (i ^ seed)
  let s: U32 = 0
  for i in 0 .. buf.length:
    s := self + buf[i]
  return s

io run_rewind (iters: U32): U32 =>
  let total: U32 = 0
  for k in 0 .. iters:
    total := self + scratch_sum 128 k
  return total
`,
    (guest) => {
      let expected = 0 >>> 0;
      for (let k = 0; k < 20000; k++) {
        for (let i = 0; i < 128; i++) {
          expected = (expected + (i ^ k)) >>> 0;
        }
      }
      assert.equal(guest.call("run_rewind", 20000), expected);
    },
    opts,
  );
});
Deno.test("Regression: small array literals declared inside lambdas respect real-handle escape/growth/carry", async () => {
  await compileAndRun(
    `
func read_sum (xs: #[U32]): U32 =>
  let s: U32 = 0
  for i in 0 .. xs.length:
    s := self + xs[i]
  return s

func bump_first (m: own #[U32]): #[U32] =>
  m[0] := m[0] + 1
  return m

func with_val (n: U32) -> (f: U32 -> #[U32]): #[U32] => f n

io test_lambda_small_arrays (n: U32): #[U32] =>
  // Case 1: small literal inside lambda passed to callee (mirrors six-more-ecs_membership_edits)
  let r1 = with_val n (func (x: U32): #[U32] =>
    let ids = #[0, x / 2, x - 1]
    return #[read_sum ids])
  // Case 2: 1-element literal inside lambda mutated and loop-carried across calls (mirrors incremental-query_cached/uncached)
  let r2 = with_val n (func (x: U32): #[U32] =>
    let meta: #[U32] = #[0]
    let acc: U32 = 0
    for i in 0 .. 4:
      if i == 2:
        meta[0] := 0
      meta := bump_first self
      acc := self + meta[0]
    return #[acc, meta[0]])
  // Case 3: small literal inside lambda grown via bulk push loop (mirrors followup-six-publish_*)
  let r3 = with_val n (func (x: U32): #[U32] =>
    let out: #[U32] = #[1, 2, 3, x]
    for i in 0 .. 3:
      for w in #[i, i + 1, i + 2]:
        @storage.push out w
    return out)
  // Case 4: genuinely non-escaping small literal inside lambda (positive DirectArray path)
  let r4 = with_val n (func (x: U32): #[U32] =>
    let local_arr = #[x, x + 1, x + 2]
    local_arr[1] := local_arr[0] + local_arr[2]
    return #[local_arr[0] + local_arr[1] + local_arr[2]])
  return #[r1[0], r2[0], r2[1], r3.length, r3[r3.length - 1], r4[0]]
`,
    (guest) => {
      // n = 10:
      // r1 = [0 + 5 + 9] = [14]
      // r2: i=0 -> meta=[1], acc=1; i=1 -> meta=[2], acc=3; i=2 -> reset 0 -> meta=[1], acc=4; i=3 -> meta=[2], acc=6
      // r3: 4 + 3*3 = 13 elements, last element = 2 + 2 = 4
      // r4: local_arr = [10, 22, 12], sum = 44
      assert.deepEqual(
        Array.from(guest.call("test_lambda_small_arrays", 10) as Uint32Array),
        [14, 6, 2, 13, 4, 44],
      );
    },
    opts,
  );
});

Deno.test("Regression: non-inlined own-array call invalidates cached checked_arrays before inline tuple propagation", async () => {
  await compileAndRun(
    `
type Span is data = $Span { start: U32, count: U32 }

// Deliberately large enough to stay non-inlined while taking \`labels: own #[U32]\`
// and growing it via bulk push loop, mirroring ink/ui/tree.store_node + declare_owned.
func push_pair (a: &[U32]) -> (b: &[U32]) -> (c: &[U32]) -> (labels: own #[U32]): (Span, #[U32]) =>
  let s = labels.length
  for x in a:
    @storage.push labels x
  let d = labels.length
  for x in b:
    @storage.push labels x
  let e = labels.length
  for x in c:
    @storage.push labels x
  let total = a.length + b.length + c.length + (d - s) * 0 + (e - d) * 0
  return ($Span { start: s, count: total }, labels)

// Small wrapper that gets inlined and returns (labels, spans).
func declare_pair (a: &[U32]) -> (b: &[U32]) -> (c: &[U32]) -> (labels: own #[U32]) -> (spans: own #[Span]): (#[U32], #[Span]) =>
  let (sp, labels) = push_pair a b c labels
  @storage.push spans sp
  return (labels, spans)

func check_spans (labels: &[U32]) -> (spans: &[Span]): U32 =>
  let sum: U32 = 0
  for sp in spans:
    if sp.start > labels.length or sp.count > labels.length - sp.start:
      return panic "span outside labels"
    for i in sp.start .. sp.start + sp.count:
      sum := self + labels[i]
  return sum

io test_own_call_invalidation (n: U32): #[U32] =>
  let src = #[10, 20, 30]
  let empty: #[U32] = #[]
  let a = &src[0..1]
  let b = &src[1..2]
  let c = &empty[0..0]
  let labels: #[U32] = #[]
  let spans: #[Span] = #[]
  let (labels, spans) = declare_pair a b c labels spans
  let (labels, spans) = declare_pair a b c labels spans
  let (labels, spans) = declare_pair a b c labels spans
  // First check caches \`labels\` (base, length=6) in checked_arrays.
  let first = check_spans (&labels[0..labels.length]) (&spans[0..spans.length])
  // Subsequent declare_pair calls grow \`labels\` past initial capacity (6 -> 8 -> 10).
  let (labels, spans) = declare_pair a b c labels spans
  let (labels, spans) = declare_pair a b c labels spans
  // Must NOT reuse stale length=6 or stale pre-realloc base!
  let second = check_spans (&labels[0..labels.length]) (&spans[0..spans.length])
  return #[first, second, labels.length, spans.length + n * 0]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("test_own_call_invalidation", 0) as Uint32Array),
        [90, 150, 10, 5],
      );
    },
    opts,
  );
});

Deno.test("KnownClosure devirtualization: const policy records, multi-arg lambdas, and control-flow soundness", async () => {
  await compileAndRun(
    `
type Ops = { hash: U32 -> U32, equal: U32 -> U32 -> Bool }

func hash_u32 (x: U32): U32 => (x * 2654435761) ^ (x >> 16)
func eq_u32 (a: U32) -> (b: U32): Bool => a == b
const u32_ops: Ops = { hash: hash_u32, equal: eq_u32 }

func eq_target (target: U32) -> (value: U32): Bool => value == target

func fold_matching (ops: Ops) -> (pred: U32 -> Bool) -> (step: U32 -> U32 -> U32) -> (xs: #[U32]) -> (init: U32): U32 =>
  let acc = init
  for i in 0 .. xs.length:
    let v = xs[i]
    if pred v and ops.equal v v:
      acc := step self (ops.hash v & 0xFF)
  return acc

// Conditional branch returning two distinct closures (deliver_count == 2):
// must NOT mis-propagate either branch as statically known.
func pick_op (flag: Bool) -> (k: U32): (U32 -> U32) =>
  if flag:
    return func (x: U32): U32 => x + k
  return func (x: U32): U32 => x * k

// Helper creating an internal temporary closure before returning another closure,
// exercising known_closures stack compaction across > 16 sequential calls.
func wrap_adder (base: U32): (U32 -> U32) =>
  let tmp = func (z: U32): U32 => z + 999
  let bonus = tmp 0 - 999
  return func (x: U32): U32 => x + base + bonus

io test_known_closures (n: U32): #[U32] =>
  let xs: #[U32] = #[3, 7, 3, 11, 3, 7]
  let bias: U32 = n
  // 1. Const policy record + partial predicate + 2-arg capturing lambda
  let r1 = fold_matching u32_ops (eq_target 3) (func (a: U32) => func (b: U32): U32 => a + b + bias) xs 0
  // 2. Conditional closure return (both arms exercised)
  let f_add = pick_op true 5
  let f_mul = pick_op false 5
  let r2 = f_add 10
  let r3 = f_mul 10
  // 3. Loop-carried closure reassignment must not stick to initial closure
  let cur: U32 -> U32 = func (x: U32): U32 => x + 1
  let r4: U32 = 0
  for i in 0 .. 4:
    r4 := self + cur i
    if i == 1:
      cur := func (x: U32): U32 => x * 10
  // 4. >16 sequential inlined closure-returning calls (must not leak known_closures slots)
  let r5: U32 = 0
  for i in 0 .. 20:
    let g = wrap_adder i
    r5 := self + g 1
  return #[r1, r2, r3, r4, r5]
`,
    (guest) => {
      const h3 = (((Math.imul(3, 2654435761) >>> 0) ^ (3 >>> 16)) & 0xff) >>> 0;
      // r1: 3 matches of value 3, each adds h3 + bias(2)
      const expectedR1 = 3 * (h3 + 2);
      // r2 = 10 + 5 = 15, r3 = 10 * 5 = 50
      // r4: i=0 -> 0+1=1; i=1 -> 1+1=2 (then cur becomes *10); i=2 -> 20; i=3 -> 30 => 53
      // r5: sum_{i=0..19} (1 + i) = 20 + 190 = 210
      assert.deepEqual(
        Array.from(guest.call("test_known_closures", 2) as Uint32Array),
        [expectedR1, 15, 50, 53, 210],
      );
    },
    opts,
  );
});

Deno.test("Exact IEEE-754 left-to-right 4x unrolled F32/F64 for-in reductions across #[T], %[T], and ~[T]", async () => {
  await compileAndRun(
    `
type Pair32 is data = $Pair32 { x: F32, y: F32 }
type Pair64 is data = $Pair64 { x: F64, y: F64 }

func sum_arr_f32 (xs: #[F32]): F32 =>
  let acc: F32 = 0.0f32
  for x in xs:
    acc := self + x
  return acc

func sum_arr_f32_ref (xs: #[F32]): F32 =>
  let acc: F32 = 0.0f32
  for i in 0 .. xs.length:
    acc := self + xs[i]
  return acc

func sum_packed_f32 (xs: %[F32]): F32 =>
  let acc: F32 = 0.0f32
  for x in xs:
    acc := self + x
  return acc

func sum_seq_f32 (xs: ~[F32]): F32 =>
  let acc: F32 = 0.0f32
  for x in xs:
    acc := self + x
  return acc

func sum_arr_f64 (xs: #[F64]): F64 =>
  let acc: F64 = 0.0f64
  for x in xs:
    acc := self + x
  return acc

func sum_packed_f64 (xs: %[F64]): F64 =>
  let acc: F64 = 0.0f64
  for x in xs:
    acc := self + x
  return acc

func sum_seq_f64 (xs: ~[F64]): F64 =>
  let acc: F64 = 0.0f64
  for x in xs:
    acc := self + x
  return acc

func sum_arr_pair32_left (ps: #[Pair32]): F32 =>
  let acc: F32 = 0.0f32
  for p in ps:
    acc := self + p.x + p.y
  return acc

func sum_arr_pair32_grouped (ps: #[Pair32]): F32 =>
  let acc: F32 = 0.0f32
  for p in ps:
    acc := self + (p.x + p.y)
  return acc

func sum_packed_pair32 (ps: %[Pair32]): F32 =>
  let acc: F32 = 0.0f32
  for p in ps:
    acc := self + p.x + p.y
  return acc

func sum_seq_pair64 (ps: ~[Pair64]): F64 =>
  let acc: F64 = 0.0f64
  for p in ps:
    acc := self + p.x + p.y
  return acc

func sum_init_f32 (init: F32) -> (xs: #[F32]): F32 =>
  let acc = init
  for x in xs:
    acc := self + x
  return acc

func sum_init_f64 (init: F64) -> (xs: %[F64]): F64 =>
  let acc = init
  for x in xs:
    acc := self + x
  return acc

io run_float_reductions (): #[U32] =>
  // Non-associative values: 1e7 + 0.3 + ... + (-1e7) depends strictly on left-to-right rounding.
  let a32: #[F32] = #[16777216.0f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, -16777216.0f32]
  let p32: %[F32] = %[16777216.0f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, -16777216.0f32]
  let s32: ~[F32] = ~[16777216.0f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, 0.75f32, -16777216.0f32]
  let ref32 = F32.to_bits (sum_arr_f32_ref a32)
  let r_a32 = F32.to_bits (sum_arr_f32 a32)
  let r_p32 = F32.to_bits (sum_packed_f32 p32)
  let r_s32 = F32.to_bits (sum_seq_f32 s32)

  // Pair32: (acc + 16777216) + 0.75 vs acc + (0.75 + 0.75) differ in F32!
  let pa: #[Pair32] = #[
    $Pair32 { x: 16777216.0f32, y: 0.75f32 },
    $Pair32 { x: 0.75f32, y: 0.75f32 },
    $Pair32 { x: 0.75f32, y: 0.75f32 },
    $Pair32 { x: 0.75f32, y: 0.75f32 },
    $Pair32 { x: -16777216.0f32, y: 0.25f32 },
  ]
  let pp: %[Pair32] = pa.to_packed
  let pl_bits = F32.to_bits (sum_arr_pair32_left pa)
  let pp_bits = F32.to_bits (sum_packed_pair32 pp)
  let pg_bits = F32.to_bits (sum_arr_pair32_grouped pa)

  // F64 across #[F64], %[F64], ~[F64] and ~[Pair64] (> 64 elems to span multiple Seq leaves)
  let a64: #[F64] = #[9007199254740992.0f64, 0.75f64, 0.75f64, 0.75f64, 0.75f64, -9007199254740992.0f64]
  let p64: %[F64] = %[9007199254740992.0f64, 0.75f64, 0.75f64, 0.75f64, 0.75f64, -9007199254740992.0f64]
  let s64: ~[F64] = ~[9007199254740992.0f64, 0.75f64, 0.75f64, 0.75f64, 0.75f64, -9007199254740992.0f64]
  let eq64_p = if F64.to_bits (sum_arr_f64 a64) == F64.to_bits (sum_packed_f64 p64) then 1 else 0
  let eq64_s = if F64.to_bits (sum_arr_f64 a64) == F64.to_bits (sum_seq_f64 s64) then 1 else 0

  let sp64: ~[Pair64] = ~[]
  for i in 0 .. 70:
    @storage.push sp64 ($Pair64 { x: U32.to_f64 i * 0.25f64, y: 0.5f64 })
  let sp64_sum = sum_seq_pair64 sp64
  // sum_{i=0..69} (0.25*i + 0.5) = 0.25*(69*70/2) + 35 = 603.75 + 35 = 638.75 (exact binary!)
  let sp64_ok = if F64.to_bits sp64_sum == F64.to_bits 638.75f64 then 1 else 0

  // Non-canonical NaN: empty preserves payload, non-empty canonicalizes to 0x7fc00000 / 0x7ff8000000000000.
  let raw_nan32 = F32.from_bits 0x7fc01234
  let empty32: #[F32] = #[]
  let one32: #[F32] = #[1.0f32]
  let keep_nan32 = F32.to_bits (sum_init_f32 raw_nan32 empty32)
  let canon_nan32 = F32.to_bits (sum_init_f32 raw_nan32 one32)
  let raw_nan64 = F64.from_bits 0x7ff8000000001234u64
  let empty64: %[F64] = %[]
  let one64: %[F64] = %[1.0f64]
  let keep_nan64_ok = if F64.to_bits (sum_init_f64 raw_nan64 empty64) == 0x7ff8000000001234u64 then 1 else 0
  let canon_nan64_ok = if F64.to_bits (sum_init_f64 raw_nan64 one64) == 0x7ff8000000000000u64 then 1 else 0

  return #[
    if r_a32 == ref32 then 1 else 0,
    if r_p32 == ref32 then 1 else 0,
    if r_s32 == ref32 then 1 else 0,
    if pl_bits == pp_bits then 1 else 0,
    if pl_bits != pg_bits then 1 else 0,
    eq64_p,
    eq64_s,
    sp64_ok,
    keep_nan32,
    canon_nan32,
    keep_nan64_ok,
    canon_nan64_ok,
  ]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("run_float_reductions", null) as Uint32Array),
        [1, 1, 1, 1, 1, 1, 1, 1, 0x7fc01234, 0x7fc00000, 1, 1],
      );
    },
    opts,
  );
});

Deno.test("U64 constant-divisor Granlund-Montgomery div/rem matches runtime div/rem across edge cases", async () => {
  await compileAndRun(
    `
func rt_div (x: U64) -> (d: U64): U64 => x / d
func rt_rem (x: U64) -> (d: U64): U64 => x % d

func check_d (xs: #[U64]) -> (d: U64) -> (cq: U64 -> U64) -> (cr: U64 -> U64): U32 =>
  for x in xs:
    if cq x != rt_div x d:
      return 1
    if cr x != rt_rem x d:
      return 2
  return 0

io run_u64_div_checks (): #[U32] =>
  let xs: #[U64] = #[
    0u64, 1u64, 2u64, 3u64, 6u64, 7u64, 8u64, 9u64, 10u64, 11u64,
    20u64, 21u64, 22u64, 99u64, 100u64, 101u64,
    0xffffffffu64, 0x100000000u64, 0x100000001u64, 0x100000002u64,
    0x7fffffffffffffffu64, 0x8000000000000000u64, 0x8000000000000001u64,
    0xfffffffffffffffeu64, 0xffffffffffffffffu64,
  ]
  return #[
    check_d xs 3u64 (func x => x / 3u64) (func x => x % 3u64),
    check_d xs 5u64 (func x => x / 5u64) (func x => x % 5u64),
    check_d xs 7u64 (func x => x / 7u64) (func x => x % 7u64),
    check_d xs 10u64 (func x => x / 10u64) (func x => x % 10u64),
    check_d xs 14u64 (func x => x / 14u64) (func x => x % 14u64),
    check_d xs 21u64 (func x => x / 21u64) (func x => x % 21u64),
    check_d xs 100u64 (func x => x / 100u64) (func x => x % 100u64),
    check_d xs 1000000007u64 (func x => x / 1000000007u64) (func x => x % 1000000007u64),
    check_d xs 0x100000001u64 (func x => x / 0x100000001u64) (func x => x % 0x100000001u64),
    check_d xs 0x8000000000000001u64 (func x => x / 0x8000000000000001u64) (func x => x % 0x8000000000000001u64),
    check_d xs 0xffffffffffffffffu64 (func x => x / 0xffffffffffffffffu64) (func x => x % 0xffffffffffffffffu64),
  ]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("run_u64_div_checks", null) as Uint32Array),
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
    },
    opts,
  );
});
