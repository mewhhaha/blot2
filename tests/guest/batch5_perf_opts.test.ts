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
  _opts?: unknown,
): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "blot-batch5-" });
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

async function compileExpectedFailure(source: string, code: string): Promise<void> {
  const dir = await Deno.makeTempDir({ prefix: "blot-batch5-fail-" });
  const entry = `${dir}/main.blot`;
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
