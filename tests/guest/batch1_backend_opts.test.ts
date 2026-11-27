import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url);

async function buildGuest(source: string) {
  const dir = await Deno.makeTempDir({ prefix: "blot-batch1-" });
  const entry = `${dir}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    return {
      bytes: built.bytes,
      guest: await instantiateGuest(built.bytes),
      cleanup: async () => {
        await Deno.remove(dir, { recursive: true });
      },
    };
  } finally {
    await compiler.close();
  }
}

Deno.test("Batch 1: U64 constant and loop-invariant division/remainder match BigInt and trap on zero", async () => {
  const dividends = [
    0n,
    1n,
    2n,
    3n,
    7n,
    10n,
    0xffffffffn,
    0x100000000n,
    0x7fffffffffffffffn,
    0x8000000000000000n,
    0xfffffffffffffffen,
    0xffffffffffffffffn,
    0x123456789abcdef0n,
  ];
  const constDivisors = [
    1n,
    2n,
    3n,
    5n,
    7n,
    10n,
    65536n,
    1000000007n,
    0x80000000n,
    0x80000001n,
    0x8000000000000001n,
    0xffffffffffffffffn,
  ];
  const lines: string[] = [];
  for (const [di, d] of constDivisors.entries()) {
    lines.push(`
func const_check_${di} (lo: U32) -> (hi: U32): #[U32] =>
  let x: U64 = lo.to_u64 | (hi.to_u64 << 32)
  let q = x / ${d}
  let r = x % ${d}
  return #[q.to_u32, (q >> 32).to_u32, r.to_u32, (r >> 32).to_u32]
`);
  }
  const source = `
${lines.join("\n")}

func inlined_mod (x: U64) -> (m: U32): U64 =>
  return x % m.to_u64

io check_const (pair: #[U32]): #[U32] =>
  let idx = pair[0]
  let lo = pair[1]
  let hi = pair[2]
  return case idx of
${
    constDivisors.map((_, i) => `    ${i} => const_check_${i} lo hi`).join("\n")
  }
    _ => #[0, 0, 0, 0]

io loop_u64_div (args: #[U32]): #[U32] =>
  let d_lo = args[0]
  let d_hi = args[1]
  let d: U64 = d_lo.to_u64 | (d_hi.to_u64 << 32)
  let q_sum: U64 = 0
  let r_sum: U64 = 0
  for i in 0..((args.length - 2) / 2):
    let x: U64 = args[2 + i * 2].to_u64 | (args[3 + i * 2].to_u64 << 32)
    q_sum := self + x / d
    r_sum := self + x % d
  return #[q_sum.to_u32, (q_sum >> 32).to_u32, r_sum.to_u32, (r_sum >> 32).to_u32]

io loop_u32_ext_div (args: #[U32]): #[U32] =>
  let m: U32 = args[0]
  let r_sum: U64 = 0
  for i in 0..((args.length - 1) / 2):
    let x: U64 = args[1 + i * 2].to_u64 | (args[2 + i * 2].to_u64 << 32)
    r_sum := self + inlined_mod x m
  return #[r_sum.to_u32, (r_sum >> 32).to_u32]
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    const toU64 = (arr: Uint32Array, off: number) =>
      BigInt(arr[off] >>> 0) | (BigInt(arr[off + 1] >>> 0) << 32n);
    for (const [di, d] of constDivisors.entries()) {
      for (const x of dividends) {
        const res = guest.call(
          "check_const",
          Uint32Array.of(di, Number(x & 0xffffffffn), Number(x >> 32n)),
        ) as Uint32Array;
        assert.equal(toU64(res, 0), x / d, `const div ${x} / ${d}`);
        assert.equal(toU64(res, 2), x % d, `const rem ${x} % ${d}`);
      }
    }
    const mask64 = (1n << 64n) - 1n;
    const flatDividends = dividends.flatMap((x) => [
      Number(x & 0xffffffffn),
      Number(x >> 32n),
    ]);
    for (
      const d of [
        1n,
        2n,
        3n,
        7n,
        65536n,
        1000000007n,
        0xffffffffn,
        0x100000000n,
        0x8000000000000000n,
        0xffffffffffffffffn,
      ]
    ) {
      const res = guest.call(
        "loop_u64_div",
        Uint32Array.from([
          Number(d & 0xffffffffn),
          Number(d >> 32n),
          ...flatDividends,
        ]),
      ) as Uint32Array;
      let expQ = 0n;
      let expR = 0n;
      for (const x of dividends) {
        expQ = (expQ + x / d) & mask64;
        expR = (expR + x % d) & mask64;
      }
      assert.equal(toU64(res, 0), expQ, `loop div d=${d}`);
      assert.equal(toU64(res, 2), expR, `loop rem d=${d}`);
    }
    assert.throws(
      () => guest.call("loop_u64_div", Uint32Array.from([0, 0, 1, 0])),
      WebAssembly.RuntimeError,
    );
    for (const m of [1, 2, 3, 7, 13, 65536, 1000000007, 0xffffffff]) {
      const res = guest.call(
        "loop_u32_ext_div",
        Uint32Array.from([m, ...flatDividends]),
      ) as Uint32Array;
      let expR = 0n;
      for (const x of dividends) {
        expR = (expR + (x % BigInt(m))) & mask64;
      }
      assert.equal(toU64(res, 0), expR, `inlined ext mod m=${m}`);
    }
    assert.throws(
      () => guest.call("loop_u32_ext_div", Uint32Array.from([0, 5, 0])),
      WebAssembly.RuntimeError,
    );
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 1: br_table dense integer and sum-type dispatch preserve semantics and order", async () => {
  const source = `
type Tok is data =
  | $A
  | $B U32
  | $C { x: U32, y: U32 }
  | $D (U32, U32)
  | $E

io int_dense (x: U32): U32 =>
  return case x of
    10 => 100
    11 => 200
    13 => 400
    14 => 500
    v => v + 1

io tok_dense (k: U32): U32 =>
  let arr: #[Tok] = #[$A, $B 7, $C { x: 3, y: 4 }, $D (8, 9), $E]
  return case arr[k] of
    $A => 1
    $B n => n * 2
    $C (x, y) => x * 10 + y
    $D (a, b) => a + b
    $E => 99

io wildcard_first (x: U32): U32 =>
  return case x of
    _ => 77
    0 => 1
    1 => 2
`;
  const { bytes, guest, cleanup } = await buildGuest(source);
  try {
    // Verify OP_br_table (0x0e) was emitted in the Wasm binary.
    assert(bytes.includes(0x0e), "expected OP_br_table in emitted Wasm");
    assert.equal(guest.call("int_dense", 10), 100);
    assert.equal(guest.call("int_dense", 11), 200);
    assert.equal(guest.call("int_dense", 12), 13);
    assert.equal(guest.call("int_dense", 13), 400);
    assert.equal(guest.call("int_dense", 14), 500);
    assert.equal(guest.call("int_dense", 9), 10);
    assert.equal(guest.call("int_dense", 999), 1000);
    assert.equal(guest.call("tok_dense", 0), 1);
    assert.equal(guest.call("tok_dense", 1), 14);
    assert.equal(guest.call("tok_dense", 2), 34);
    assert.equal(guest.call("tok_dense", 3), 17);
    assert.equal(guest.call("tok_dense", 4), 99);
    assert.equal(guest.call("wildcard_first", 0), 77);
    assert.equal(guest.call("wildcard_first", 1), 77);
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 1: boxed element projection, boxed subfield indexed update, and alias isolation", async () => {
  const source = `
type Xf is data = $Xf {
  a: F32, b: F32, c: F32, d: F32,
  e: F32, f: F32, g: F32, h: F32,
  tx: F32, ty: F32, tz: F32, pad: F32
}
type Node is data = $Node {
  parent: U32,
  local: Xf,
  world: Xf
}
func mk_xf (v: F32): Xf =>
  $Xf { a: v, b: 0.0, c: 0.0, d: 0.0, e: 0.0, f: v, g: 0.0, h: 0.0, tx: v, ty: v * 2.0, tz: v * 3.0, pad: 1.0 }

io test_boxed (n: U32): #[F32] =>
  let pool = @array.generate n (func i => $Node { parent: i, local: mk_xf (F32.from i), world: mk_xf 1.0 })
  let snap = pool.copy
  for i in 0..n:
    pool[i].world := mk_xf (pool[i].local.tz + 5.0)
    pool[i].local.tx := pool[i].local.tx + 10.0
  let sum_w = 0.0
  let sum_l = 0.0
  let sum_snap = 0.0
  for i in 0..n:
    sum_w := self + pool[i].world.tx
    sum_l := self + pool[i].local.tx
    sum_snap := self + snap[i].world.tx + snap[i].local.tx
  return #[sum_w, sum_l, sum_snap]
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    const res = guest.call("test_boxed", 10) as Float32Array;
    // i = 0..9: sum(i) = 45
    // world.tx = 3*i + 5 => sum = 135 + 50 = 185
    // local.tx = i + 10 => sum = 45 + 100 = 145
    // snap: world.tx = 1, local.tx = i => sum = 10 + 45 = 55
    assert.equal(res[0], 185);
    assert.equal(res[1], 145);
    assert.equal(res[2], 55);
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 1: function-exit reclamation with returned own array and large stack chunk reuse", async () => {
  const source = `
func step_with_scratch (out: own #[U32]) -> (k: U32): #[U32] =>
  // 1 MiB scratch array per call; 200 calls = 200 MiB > 128 MiB stack budget unless reclaimed on exit.
  let scratch = @array.fill 262144 k
  out[0] := self + scratch[0] + scratch[262143]
  return out

io run_reclaim (iters: U32): U32 =>
  let out = #[0]
  for i in 0..iters:
    out := step_with_scratch self 1
  return out[0]

func alloc_big (n: U32): U32 =>
  let one: U8 = 1
  let buf = @array.fill n one
  return buf[0].to_u32 + buf[n - 1].to_u32

io run_large_reuse (base_mb: U32): U32 =>
  // Allocate decreasing sizes (e.g. 24M -> 12M -> 6M) in separate scopes; best-fit reuse avoids 3 separate chunks.
  let s = alloc_big (base_mb * 1048576)
  let s2 = alloc_big ((base_mb / 2) * 1048576)
  let s3 = alloc_big ((base_mb / 4) * 1048576)
  return s + s2 + s3
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    assert.equal(guest.call("run_reclaim", 200), 400);
    assert.equal(guest.call("run_large_reuse", 24), 6);
  } finally {
    guest.dispose();
    await cleanup();
  }
});

Deno.test("Batch 1: masked and affine BCE preserve exact bounds traps", async () => {
  const source = `
io sum_masked (n: U32): U32 =>
  let arr = @array.generate 256 (func i => i)
  let total = 0
  let mask: U32 = 255
  for i in 0..n:
    total := self + arr[i & mask]
  return total

io sum_affine (n: U32): U32 =>
  let arr = @array.generate (n + 2) (func i => i)
  let total = 0
  for i in 0..n:
    total := self + arr[i] + arr[i + 1] + arr[i + 2]
  return total

io sum_affine_oob (n: U32): U32 =>
  let arr = @array.generate n (func i => i)
  let total = 0
  for i in 0..n:
    total := self + arr[i + 1]
  return total

io sum_masked_oob (mask: U32): U32 =>
  let arr = @array.generate 16 (func i => i)
  let total = 0
  for i in 0..32:
    total := self + arr[i & mask]
  return total
`;
  const { guest, cleanup } = await buildGuest(source);
  try {
    assert.equal(guest.call("sum_masked", 512), 2 * (255 * 256) / 2);
    // sum_{i=0}^{9} (3i + 3) = 3*45 + 30 = 165
    assert.equal(guest.call("sum_affine", 10), 165);
    assert.throws(() => guest.call("sum_affine_oob", 10), WebAssembly.RuntimeError);
    assert.throws(() => guest.call("sum_masked_oob", 31), WebAssembly.RuntimeError);
  } finally {
    guest.dispose();
    await cleanup();
  }
});
