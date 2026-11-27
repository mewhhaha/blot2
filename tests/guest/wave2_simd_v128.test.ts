import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
const opts = { stdRoot };
const importSimd = 'import * as simd from "std/simd"';
const canonicalNaN = 0x7fc00000;
const float = new Float32Array(1);
const word = new Uint32Array(float.buffer);
function fromBits(bits: number): number {
  word[0] = bits;
  return float[0];
}
function toBits(value: number): number {
  if (Number.isNaN(value)) return canonicalNaN;
  float[0] = value;
  return word[0];
}
function words(value: unknown): number[] {
  assert.ok(value instanceof Uint32Array || value instanceof Float32Array);
  return Array.from(
    new Uint32Array(value.buffer, value.byteOffset, value.length),
  );
}

type Inputs = { a: number[]; b: number[]; c: number[] };
type Law = [
  name: string,
  expression: string,
  expected: (input: Inputs) => number[],
];
type LaneOp = (a: number, b: number, c: number) => number;
function each(op: LaneOp): Law[2] {
  return ({ a, b, c }) => a.map((v, i) => op(v, b[i], c[i]) >>> 0);
}
function eachFloat(op: LaneOp): Law[2] {
  return each((a, b, c) => toBits(op(fromBits(a), fromBits(b), fromBits(c))));
}
const mask = (isTrue: boolean) => isTrue ? 0xffffffff : 0;
const bits = (expr: string) => `simd.f32_bits (${expr})`;
const broadcast = (a: number) => [a, a, a, a];
const clamp = (x: number, min: number, max: number) =>
  Number.isNaN(x) ? 0 : Math.min(max, Math.max(min, Math.trunc(x)));

const arithmetic: Law[] = [
  ["f32_add", bits("simd.f32_add af bf"), eachFloat((a, b) => a + b)],
  ["f32_sub", bits("simd.f32_sub af bf"), eachFloat((a, b) => a - b)],
  ["f32_mul", bits("simd.f32_mul af bf"), eachFloat((a, b) => a * b)],
  ["f32_div", bits("simd.f32_div af bf"), eachFloat((a, b) => a / b)],
  ["f32_abs", bits("simd.f32_abs af"), each((a) => a & 0x7fffffff)],
  ["f32_neg", bits("simd.f32_neg af"), each((a) => a ^ 0x80000000)],
  ["f32_sqrt", bits("simd.f32_sqrt af"), eachFloat(Math.sqrt)],
  ["f32_ceil", bits("simd.f32_ceil af"), eachFloat(Math.ceil)],
  ["f32_floor", bits("simd.f32_floor af"), eachFloat(Math.floor)],
  ["f32_trunc", bits("simd.f32_trunc af"), eachFloat(Math.trunc)],
  [
    "f32_min",
    bits("simd.f32_min af bf"),
    each((a, b) => fromBits(a) < fromBits(b) ? a : b),
  ],
  [
    "f32_max",
    bits("simd.f32_max af bf"),
    each((a, b) => fromBits(a) > fromBits(b) ? a : b),
  ],
  [
    "f32_relaxed_madd",
    bits("simd.f32_relaxed_madd af bf cf"),
    eachFloat((a, b, c) => Math.fround(a * b) + c),
  ],
  [
    "f32_relaxed_nmadd",
    bits("simd.f32_relaxed_nmadd af bf cf"),
    eachFloat((a, b, c) => c - Math.fround(a * b)),
  ],
  ["to_u32", "simd.to_u32 af", each((a) => clamp(fromBits(a), 0, 0xffffffff))],
  [
    "to_u32_signed",
    "simd.to_u32_signed af",
    each((a) => clamp(fromBits(a), -0x80000000, 0x7fffffff)),
  ],
  ["to_f32", bits("simd.to_f32 a"), each(toBits)],
  ["to_f32_signed", bits("simd.to_f32_signed a"), each((a) => toBits(a | 0))],
  ["f32_bits", "simd.f32_bits af", ({ a }) => a],
  ["f32_from_bits", "@simd.f32x4.bits (simd.f32_from_bits a)", ({ a }) => a],
  ["f32_splat", bits("simd.f32_splat lane_f"), ({ a }) => broadcast(a[0])],
  ["u32_splat", "simd.u32_splat lane_u", ({ a }) => broadcast(a[0])],
  ["u32_add", "simd.u32_add a b", each((a, b) => a + b)],
  ["u32_sub", "simd.u32_sub a b", each((a, b) => a - b)],
  ["u32_mul", "simd.u32_mul a b", each(Math.imul)],
  ["u32_and", "simd.u32_and a b", each((a, b) => a & b)],
  ["u32_or", "simd.u32_or a b", each((a, b) => a | b)],
  ["u32_xor", "simd.u32_xor a b", each((a, b) => a ^ b)],
  ["u32_not", "simd.u32_not a", each((a) => ~a)],
  ["u32_andnot", "simd.u32_andnot a b", each((a, b) => a & ~b)],
  ["u32_min", "simd.u32_min a b", each((a, b) => Math.min(a, b))],
  ["u32_max", "simd.u32_max a b", each((a, b) => Math.max(a, b))],
  [
    "u32_min_signed",
    "simd.u32_min_signed a b",
    each((a, b) => Math.min(a | 0, b | 0)),
  ],
  [
    "u32_max_signed",
    "simd.u32_max_signed a b",
    each((a, b) => Math.max(a | 0, b | 0)),
  ],
  [
    "u32_div",
    "simd.u32_div a (simd.u32_or b (simd.u32_splat 1))",
    each((a, b) => Math.floor(a / ((b | 1) >>> 0))),
  ],
  [
    "u32_shl",
    "simd.u32_shl lane_u b",
    ({ a, b }) => b.map((v) => (v << a[0]) >>> 0),
  ],
  ["u32_shr", "simd.u32_shr lane_u b", ({ a, b }) => b.map((v) => v >>> a[0])],
  [
    "u32_sar",
    "simd.u32_sar lane_u b",
    ({ a, b }) => b.map((v) => (v >> a[0]) >>> 0),
  ],
  [
    "f32_select",
    bits("simd.f32_select c af bf"),
    each((a, b, c) => (a & c) | (b & ~c)),
  ],
  [
    "u32_select",
    "simd.u32_select c a b",
    each((a, b, c) => (a & c) | (b & ~c)),
  ],
  [
    "f32_shuffle",
    bits("simd.f32_shuffle (7, 0, 5, 2) af bf"),
    ({ a, b }) => [b[3], a[0], b[1], a[2]],
  ],
  [
    "u32_shuffle",
    "simd.u32_shuffle (7, 0, 5, 2) a b",
    ({ a, b }) => [b[3], a[0], b[1], a[2]],
  ],
  [
    "f32_swizzle",
    bits("simd.f32_swizzle (3, 0, 0, 1) af"),
    ({ a }) => [a[3], a[0], a[0], a[1]],
  ],
  [
    "u32_swizzle",
    "simd.u32_swizzle (3, 0, 0, 1) a",
    ({ a }) => [a[3], a[0], a[0], a[1]],
  ],
  [
    "f32_broadcast",
    bits("simd.f32_broadcast 2 af"),
    ({ a }) => broadcast(a[2]),
  ],
  ["u32_broadcast", "simd.u32_broadcast 2 a", ({ a }) => broadcast(a[2])],
  [
    "dynamic_broadcast",
    "@simd.u32x4.broadcast b lane_u",
    ({ a, b }) => broadcast(b[a[0]] ?? b[0]),
  ],
  [
    "chain_nan",
    bits("simd.f32_add (simd.f32_mul af bf) cf"),
    eachFloat((a, b, c) => Math.fround(a * b) + c),
  ],
];

const comparisons: [string, (a: number, b: number) => boolean][] = [
  ["eq", (a, b) => a === b],
  ["ne", (a, b) => a !== b],
  ["lt", (a, b) => a < b],
  ["le", (a, b) => a <= b],
  ["gt", (a, b) => a > b],
  ["ge", (a, b) => a >= b],
];
for (const [op, compare] of comparisons) {
  arithmetic.push(
    [
      `f32_${op}`,
      `simd.f32_${op} af bf`,
      each((a, b) => mask(compare(fromBits(a), fromBits(b)))),
    ],
    [`u32_${op}`, `simd.u32_${op} a b`, each((a, b) => mask(compare(a, b)))],
  );
  if (op !== "eq" && op !== "ne") {
    arithmetic.push([
      `u32_${op}_signed`,
      `simd.u32_${op}_signed a b`,
      each((a, b) => mask(compare(a | 0, b | 0))),
    ]);
  }
}

Deno.test("Wave 2 SIMD arithmetic, masks, conversions and permutations preserve lane bits", async () => {
  const prologue = `
  let a = simd.load 0 input
  let b = simd.load 4 input
  let c = simd.load 8 input
  let af = simd.f32_from_bits a
  let bf = simd.f32_from_bits b
  let cf = simd.f32_from_bits c
  let (lane_u, _, _, _) = a
  let (lane_f, _, _, _) = af`;
  const vectorExports = arithmetic.map(([name, expr]) => `
io check_${name} (input: #[U32]): #[U32] =>${prologue}
  return simd.store 0 (${expr}) (@array.fill 4 0)
`).join("");
  const reductionExports = `
io reductions (input: #[U32]): #[U32] =>${prologue}
  let any = if simd.any_true a then 1 else 0
  let all = if simd.all_true a then 1 else 0
  let (sum, pair, dot, dot3) = simd.f32_bits (simd.f32_sum af, simd.f32_sum_pairwise af, simd.f32_dot af bf, simd.f32_dot3 af bf)
  return #[any, all, sum, pair, dot, dot3, simd.u32_sum a]
`;
  const datasets: Inputs[] = [
    {
      a: [0, 0x80000000, 0x7fc12345, 0x40f00000],
      b: [0x80000000, 0, 0x40000000, 0xffc54321],
      c: [0xaaaaaaaa, 0x55555555, 0xffffffff, 0],
    },
    {
      a: [0xff800000, 0x7f800000, 0xc0600000, 0xff812345],
      b: [0x7f800000, 0x7f800000, 0, 0x80000000],
      c: [0, 0x7fc0beef, 0x40800000, 0x80000000],
    },
    {
      a: [0x4f800000, 0xcf000001, 0x4f7fffff, 0xbf000000],
      b: [0x3f800000, 0x40000000, 0xc0000000, 0x3e800000],
      c: [7, 0x80330011, 0xffffffff, 0x10000000],
    },
    {
      a: [35, 1, 0x80000000, 0xffffffff],
      b: [0x80000001, 1, 0xffffffff, 0x7fffffff],
      c: [1, 2, 3, 4],
    },
    { a: [2, 0, 0, 0], b: [1, 2, 3, 4], c: [0, 0, 0, 0] },
    { a: [0, 0, 0, 0], b: [1, 2, 3, 4], c: [0, 0, 0, 0] },
  ];
  await compileAndRun(
    importSimd + vectorExports + reductionExports,
    (guest) => {
      for (const [i, input] of datasets.entries()) {
        const { a, b, c } = input;
        const packet = Uint32Array.of(...a, ...b, ...c);
        for (const [name, , expected] of arithmetic) {
          assert.deepEqual(
            words(guest.call(`check_${name}`, packet)),
            expected(input),
            `${name}, dataset ${i}`,
          );
        }
        const [x, y, z, w] = a.map(fromBits);
        const [p, q, r, s] = a.map((v, lane) =>
          Math.fround(fromBits(v) * fromBits(b[lane]))
        );
        const f = Math.fround;
        assert.deepEqual(words(guest.call("reductions", packet)), [
          Number(a.some(Boolean)),
          Number(a.every(Boolean)),
          toBits(f(f(x + y) + z) + w),
          toBits(f(x + y) + f(z + w)),
          toBits(f(f(p + q) + r) + s),
          toBits(f(p + q) + r),
          a.reduce((sum, v) => (sum + v) >>> 0, 0),
        ]);
      }
    },
    opts,
  );
});

Deno.test("Wave 2 SIMD store bounds, immutable pools, byte-packed Bool, and fork rollback", async () => {
  await compileAndRun(
    `${importSimd}
const table: #[U32] = #[10, 20, 30, 40, 50]
io load (index: U32): #[U32] =>
  let lanes = @simd.load table index
  return simd.store 0 lanes (@array.fill 4 0)
io store (index: U32): #[U32] =>
  let owned = @storage.copy table
  return @simd.store owned index (91, 92, 93, 94)
io short (length: U32): #[F32] =>
  let input = @array.fill length 1.5
  let lanes = simd.load 0 input
  return simd.store 0 lanes input
io store_short (length: U32): #[F32] =>
  let input = @array.fill length 1.5
  return simd.store 0 (simd.f32_splat 2.5) input
io speculate (x: U32): #[U32] =>
  let dst = @storage.copy table
  let seen = fork dst:
    dst := @simd.store dst 1 (simd.u32_splat x)
    return dst[4]
  return #[seen, dst[0], dst[1], dst[2], dst[3], dst[4]]
io bool_fallback (_: Unit): #[U32] =>
  let src = #[false, true, false, true, true, false]
  let a = @simd.load src 1
  src := @simd.store src 2 a
  return #[if src[0] then 1 else 0, if src[1] then 1 else 0,
    if src[2] then 1 else 0, if src[3] then 1 else 0,
    if src[4] then 1 else 0, if src[5] then 1 else 0]
`,
    (guest) => {
      for (const index of [2, 0xfffffffc, 0xfffffffd, 0xfffffffe, 0xffffffff]) {
        for (const name of ["load", "store"]) {
          assert.throws(
            () => guest.call(name, index),
            WebAssembly.RuntimeError,
          );
        }
      }
      for (const length of [0, 1, 2, 3]) {
        assert.throws(
          () => guest.call("short", length),
          WebAssembly.RuntimeError,
        );
        assert.throws(
          () => guest.call("store_short", length),
          WebAssembly.RuntimeError,
        );
      }
      assert.deepEqual(words(guest.call("load", 1)), [20, 30, 40, 50]);
      assert.deepEqual(words(guest.call("store", 1)), [10, 91, 92, 93, 94]);
      assert.deepEqual(words(guest.call("short", 4)), broadcast(toBits(1.5)));
      assert.deepEqual(
        words(guest.call("store_short", 4)),
        broadcast(toBits(2.5)),
      );
      assert.deepEqual(words(guest.call("speculate", 99)), [
        99,
        10,
        20,
        30,
        40,
        50,
      ]);
      assert.deepEqual(words(guest.call("bool_fallback", null)), [
        0,
        1,
        1,
        0,
        1,
        1,
      ]);
    },
    opts,
  );
  await compileExpectedFailure(
    `
const table: #[U32] = #[10, 20, 30, 40]
io write (_: Unit): #[U32] => @simd.store table 0 (9, 8, 7, 6)
`,
    "aliased_update",
    undefined,
    opts,
  );
});

Deno.test("Wave 2 v128.store traps on a static owner descriptor", async () => {
  await compileAndRun(
    `${importSimd}
func init (seed: U32): #[U32] => #[seed, 123, 456, 789]
func step (state: own #[U32]) -> (x: U32): (#[U32], U32) =>
  state := simd.store 0 (simd.u32_splat x) state
  let result = state[3]
  return (state, result)
#process const vector_pool: Process [U32, U32, U32] = { init: init, step: step }
io expose_memory (_: Unit): #[U32] => #[0]
`,
    (guest, bytes) => {
      guest.call("squid:proc_init:vector_pool", 77);
      assert.equal(guest.call("squid:proc_step:vector_pool", 99), 99);

      // Squid's checker rejects stores to const pools. Exercise the runtime
      // guard by marking this persistent state owner static in the raw ABI.
      const { exports } = new WebAssembly.Instance(
        new WebAssembly.Module(bytes),
      );
      const init = exports["squid:proc_init:vector_pool"] as CallableFunction;
      const step = exports["squid:proc_step:vector_pool"] as CallableFunction;
      init(77);
      const memory = new DataView(
        (exports["squid:memory"] as WebAssembly.Memory).buffer,
      );
      const read = (at: number) => memory.getUint32(at, true);
      const initial = [77, 123, 456, 789];
      const directory = 1024;
      const persistentBlock = 192; // First persistent block with default budgets.
      const staticFlag = 0x20000000;
      const liveFlag = 0x10000000;
      let owner = 0;
      for (let block = persistentBlock; block < 256; block++) {
        const base = read(directory + block * 4);
        if (base === 0) continue;
        for (let i = 0; i < 256; i++) {
          const entry = base + i * 16;
          if (read(entry + 4) !== 4 || !(read(entry + 8) & liveFlag)) continue;
          if (
            initial.every((value, lane) =>
              value === read(read(entry) + lane * 4)
            )
          ) {
            owner = entry;
            break;
          }
        }
        if (owner !== 0) break;
      }
      assert.notEqual(owner, 0, "located the process's persistent state owner");
      memory.setUint32(owner + 8, read(owner + 8) | staticFlag, true);
      assert.throws(() => step(99), WebAssembly.RuntimeError);
      assert.deepEqual(
        initial.map((_, lane) => read(read(owner) + lane * 4)),
        initial,
      );
    },
    opts,
  );
});

Deno.test("Wave 2 SIMD shadows survive branches, match arms, loop backedges and closure environments", async () => {
  await compileAndRun(
    `${importSimd}
io flow (count: U32): #[U32] =>
  let base = simd.load 0 #[2, 3, 5, 7]
  let before: U32 = 0
  if count == 0:
    let (first, _, _, _) = base
    before := first
  else:
    let (_, second, _, _) = base
    before := second
  let (_, _, third, _) = base
  let carry = if count == 0 then simd.u32_mul base (simd.u32_splat 2) else simd.u32_add base (simd.u32_splat 11)
  for i in 0 .. count:
    let next = simd.u32_add carry (simd.u32_splat i)
    let (a, b, c, d) = next
    carry := if i % 2 == 0 then (d, c, b, a) else simd.u32_xor next (simd.u32_splat 3)
  let selected = case count of
    0 => simd.u32_sub carry base
    _ => simd.u32_mul carry base
  let closure = func (n: U32) => simd.u32_add selected (simd.u32_splat n)
  let (a, b, c, d) = closure third
  return #[before, third, a, b, c, d]
`,
    (guest) => {
      for (const count of [0, 1, 2, 7]) {
        const base = [2, 3, 5, 7];
        let carry = base.map((v) => count === 0 ? v * 2 : v + 11);
        for (let i = 0; i < count; i++) {
          const next = carry.map((v) => v + i);
          carry = i % 2 === 0 ? next.reverse() : next.map((v) => v ^ 3);
        }
        const selected = carry.map((v, i) =>
          count === 0 ? v - base[i] : v * base[i]
        );
        assert.deepEqual(
          words(guest.call("flow", count)),
          [count === 0 ? 2 : 3, 5, ...selected.map((v) => v + 5)],
        );
      }
    },
    opts,
  );
});

async function disassemble(bytes: Uint8Array): Promise<string> {
  const file = await Deno.makeTempFile({ suffix: ".wasm" });
  try {
    await Deno.writeFile(file, bytes);
    const result = await new Deno.Command("wasm2wat", {
      args: ["--enable-all", file],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(result.success, new TextDecoder().decode(result.stderr));
    return new TextDecoder().decode(result.stdout);
  } finally {
    await Deno.remove(file);
  }
}

Deno.test("Wave 2 std/simd load–multiply–add–store loop stays in v128 locals", async () => {
  await compileAndRun(
    `${importSimd}
io chain (input: #[F32]): #[F32] =>
  let dst = @array.fill input.length 0.0
  let scale = simd.f32_splat 0.5
  let offset = simd.f32_splat 2.25
  for block in 0 .. input.length / 4:
    let i = block * 4
    let product = simd.load i input
    dst := simd.store i (simd.f32_add (simd.f32_mul product scale) offset) dst
  return dst
`,
    async (guest, bytes) => {
      const input = Float32Array.of(1, 2, -3, 4, -0, 6, Infinity, -Infinity);
      assert.deepEqual(
        words(guest.call("chain", input)),
        Array.from(input, (x) => toBits(x * 0.5 + 2.25)),
      );
      const wat = await disassemble(bytes);
      const kernel = wat.split("\n  (func ").find((body) =>
        body.includes("f32x4.mul")
      );
      assert.ok(kernel);
      assert.match(
        kernel,
        /\bloop\b[\s\S]*v128\.load[\s\S]*f32x4\.mul[\s\S]*f32x4\.add[\s\S]*v128\.store/,
      );
      assert.doesNotMatch(kernel, /(?:extract|replace)_lane|call_indirect/);
      const hot = kernel.slice(
        kernel.indexOf("loop"),
        kernel.indexOf("v128.store"),
      );
      assert.doesNotMatch(hot, /\bcall\b/);
      assert.equal(
        kernel.match(/v128\.bitselect/g)?.length,
        1,
        "canonicalize add, elide multiply",
      );
    },
    opts,
  );
});

Deno.test("Wave 2 emits byte shuffles for literal selectors after the scalar fact table fills", async () => {
  const padding = Array.from({ length: 40 }, (_, i) => i).join(", ");
  await compileAndRun(
    `${importSimd}
io permute (input: #[U32]): #[U32] =>
  let pad = #[${padding}]
  let value = simd.load 0 input
  let reversed = simd.u32_swizzle (3, 2, 1, 0) value
  let mixed = @simd.u32x4.shuffle (7, 0, 6, 1) (value, reversed)
  return simd.store pad[0] mixed (@array.fill 4 0)
`,
    async (guest, bytes) => {
      assert.deepEqual(
        words(guest.call("permute", Uint32Array.of(11, 22, 33, 44))),
        [11, 11, 22, 22],
      );
      const wat = await disassemble(bytes);
      assert.equal(wat.match(/i8x16\.shuffle/g)?.length, 2);
    },
    opts,
  );
});

Deno.test("Wave 2 uses the opt-in relaxed SIMD opcodes and canonicalizes their NaNs", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-wave2-relaxed-" });
  const entry = `${dir}/main.sq`;
  try {
    await Deno.writeTextFile(
      entry,
      `${importSimd}
io relaxed (input: #[U32]): #[U32] =>
  let a = simd.f32_from_bits (simd.load 0 input)
  let b = simd.f32_from_bits (simd.load 4 input)
  let c = simd.f32_from_bits (simd.load 8 input)
  let out = @array.fill 8 0
  out := simd.store 0 (simd.f32_bits (simd.f32_relaxed_madd a b c)) out
  return simd.store 4 (simd.f32_bits (simd.f32_relaxed_nmadd a b c)) out
`,
    );
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0] ??
        new URL("../../compiler-goose/build/squidc-goose", import.meta.url)
          .pathname,
      entry,
      prelude: new URL("../../std/prelude.sq", import.meta.url).pathname,
      stdRoot,
      relaxedSimd: true,
    });
    try {
      const built = await compiler.build();
      assert.ok(built.success, JSON.stringify(built));
      const wat = await disassemble(built.bytes);
      assert.match(wat, /f32x4\.relaxed_madd/);
      assert.match(wat, /f32x4\.relaxed_nmadd/);
      const guest = await instantiateGuest(built.bytes);
      try {
        const input = Uint32Array.of(
          canonicalNaN | 7,
          toBits(Infinity),
          toBits(2),
          toBits(-4),
          toBits(2),
          toBits(0),
          toBits(-3),
          toBits(0.5),
          toBits(1),
          toBits(8),
          toBits(10),
          toBits(0.5),
        );
        assert.deepEqual(words(guest.call("relaxed", input)), [
          canonicalNaN,
          canonicalNaN,
          toBits(4),
          toBits(-1.5),
          canonicalNaN,
          canonicalNaN,
          toBits(16),
          toBits(2.5),
        ]);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
