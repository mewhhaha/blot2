import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const maxU32 = 0xffffffff;
const divisors = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  9,
  10,
  11,
  13,
  19,
  40,
  60,
  100,
  139968,
  0x7fffffff,
  0x80000000,
  0x80000001,
  0xfffffffe,
  maxU32,
];
const factors = [0, 1, 2, 4, 32, 0x80000000];

function dividends(d: number): number[] {
  const k = Math.floor(maxU32 / d);
  return [
    ...new Set([
      0,
      1,
      d - 1,
      d,
      d + 1,
      2 * d - 1,
      2 * d,
      0x7fffffff,
      0x80000000,
      maxU32 - 1,
      maxU32,
      k * d - 1,
      k * d,
      (k - 1) * d - 1,
      (k - 1) * d,
    ].filter((x) => x >= 0 && x <= maxU32)),
  ];
}

Deno.test("Wave 1 U32 constant arithmetic covers both reciprocal paths and unsigned boundaries", async () => {
  const cases = [0, ...divisors].map((d, i) => `
io divide_${i} (x: U32): U32 => return x / ${d}
io remainder_${i} (x: U32): U32 => return x % ${d}`);
  const multiply = factors.map((c, i) => `
io multiply_${i} (x: U32): U32 => return x * ${c}
io multiply_left_${i} (x: U32): U32 => return ${c} * x`);
  const boundConstant = `
const DIVISOR: U32 = 19
io global_constant (x: U32): U32 => return x / DIVISOR
io staged_constant (x: U32): U32 => return x / (#run (10 + 9))
io bound_constant (x: U32): U32 =>
  let d = 19
  let alias = d
  return x / alias
io discarded_dividend (values: #[U32]): U32 => return values[0] * 0
io discarded_remainder (values: #[U32]): U32 => return values[0] % 1
`;
  await compileAndRun(
    [...cases, ...multiply, boundConstant].join("\n"),
    (guest) => {
      for (const [i, d] of divisors.entries()) {
        for (const x of dividends(d)) {
          assert.equal(
            guest.call(`divide_${i + 1}`, x),
            Math.floor(x / d),
            `${x} / ${d}`,
          );
          assert.equal(
            guest.call(`remainder_${i + 1}`, x),
            x % d,
            `${x} % ${d}`,
          );
        }
      }
      for (const [i, factor] of factors.entries()) {
        for (const x of dividends(factor || 1)) {
          const expected = Math.imul(x, factor) >>> 0;
          assert.equal(guest.call(`multiply_${i}`, x), expected);
          assert.equal(guest.call(`multiply_left_${i}`, x), expected);
        }
      }
      assert.equal(
        guest.call("bound_constant", maxU32),
        Math.floor(maxU32 / 19),
      );
      for (const x of [0, 1, maxU32]) {
        assert.throws(
          () => guest.call("divide_0", x),
          WebAssembly.RuntimeError,
        );
        assert.throws(
          () => guest.call("remainder_0", x),
          WebAssembly.RuntimeError,
        );
      }
      for (const name of ["discarded_dividend", "discarded_remainder"]) {
        assert.throws(
          () => guest.call(name, Uint32Array.of()),
          WebAssembly.RuntimeError,
        );
      }
    },
  );
});

Deno.test("Wave 1 invariant reciprocals preserve empty loops, conditional traps, and changing carries", async () => {
  await compileAndRun(
    `
io range (args: #[U32]): #[U32] =>
  let x = args[0]
  let d = args[1]
  let count = args[2]
  let q: U32 = 99
  let r: U32 = 99
  for i in 0 .. count:
    q := (x + i) / d
    r := (x + i) % d
  return #[q, r]
io guarded (args: #[U32]): U32 =>
  let x = args[0]
  let d = args[1]
  let enabled = args[2]
  let r: U32 = 99
  for i in 0 .. 2:
    if i == enabled:
      r := x % d
  return r
io infinite (args: #[U32]): U32 =>
  let x = args[0]
  let d = args[1]
  let out: U32 = 99
  for ever:
    out := x / d
    break
  return out
io early_break (args: #[U32]): U32 =>
  let d = args[0]
  let stop = args[1]
  let out: U32 = 99
  for ever:
    if stop == 1:
      break
    out := 12 / d
    break
  return out
io changing (count: U32): U32 =>
  let d: U32 = 2
  let out: U32 = 0
  for i in 0 .. count:
    out := self + ((17 + i) / d)
    d := self - 1
  return out
`,
    (guest) => {
      for (const d of divisors) {
        for (const x of dividends(d)) {
          assert.deepEqual(
            guest.call("range", Uint32Array.of((x - 1) >>> 0, d, 2)),
            Uint32Array.of(Math.floor(x / d), x % d),
          );
          assert.equal(
            guest.call("infinite", Uint32Array.of(x, d)),
            Math.floor(x / d),
          );
        }
      }
      assert.deepEqual(
        guest.call("range", Uint32Array.of(12, 0, 0)),
        Uint32Array.of(99, 99),
      );
      assert.throws(
        () => guest.call("range", Uint32Array.of(12, 0, 1)),
        WebAssembly.RuntimeError,
      );
      assert.equal(guest.call("guarded", Uint32Array.of(12, 0, 2)), 99);
      assert.throws(
        () => guest.call("guarded", Uint32Array.of(12, 0, 1)),
        WebAssembly.RuntimeError,
      );
      assert.throws(
        () => guest.call("infinite", Uint32Array.of(12, 0)),
        WebAssembly.RuntimeError,
      );
      assert.equal(guest.call("early_break", Uint32Array.of(0, 1)), 99);
      assert.throws(
        () => guest.call("early_break", Uint32Array.of(0, 0)),
        WebAssembly.RuntimeError,
      );
      assert.equal(guest.call("changing", 2), 26);
      assert.throws(() => guest.call("changing", 3), WebAssembly.RuntimeError);
    },
  );
});

Deno.test("Wave 1 range and borrowed descriptors preserve bounds and invalidate on resize", async () => {
  await compileAndRun(
    `
io write_range (input: U32): U32 =>
  let count = 8
  let rows = @array.fill count 0
  for i in 0 .. 8:
    rows[i] := input + i
  return rows[7]
io long_range (input: U32): U32 =>
  let rows = @array.fill 8 0
  for i in 0 .. 9:
    rows[i] := input + i
  return rows[7]
func nested (words: #[U32]) -> (count: U32): U32 =>
  let sum = words[0]
  for i in 0 .. 2:
    for j in 0 .. count:
      if i == 0:
        sum := self + words[j]
      else:
        sum := self + words[j + 1]
  return sum
io borrowed (words: #[U32]): U32 => return nested words words[0]
io grown (value: U32): U32 =>
  let rows = #[10]
  let before = rows[0]
  rows := @storage.push self value
  return before + rows[1] + rows.length
io truncated (choose: U32): U32 =>
  let rows = #[10, 20]
  let before = rows[1]
  if choose == 0:
    @storage.truncate rows 1
  else:
    rows[0] := 30
  return before + rows[1]
io merged (choose: U32): U32 =>
  let rows = if choose == 0 then #[10] else #[20]
  rows[0] := self + 1
  return rows[0]
`,
    (guest) => {
      assert.equal(guest.call("write_range", 100), 107);
      assert.throws(
        () => guest.call("long_range", 100),
        WebAssembly.RuntimeError,
      );
      assert.equal(guest.call("borrowed", Uint32Array.of(2, 7, 9)), 27);
      assert.throws(
        () => guest.call("borrowed", Uint32Array.of(2, 7)),
        WebAssembly.RuntimeError,
      );
      assert.throws(
        () => guest.call("borrowed", Uint32Array.of()),
        WebAssembly.RuntimeError,
      );
      assert.equal(guest.call("grown", 99), 111);
      assert.equal(guest.call("truncated", 1), 40);
      assert.throws(() => guest.call("truncated", 0), WebAssembly.RuntimeError);
      assert.equal(guest.call("merged", 0), 11);
      assert.equal(guest.call("merged", 1), 21);
    },
  );
});

function readUleb(bytes: Uint8Array, cursor: { at: number }): number {
  let value = 0;
  let shift = 0;
  for (;;) {
    const part = bytes[cursor.at++];
    if (part === undefined || shift >= 35) throw new Error("Invalid Wasm u32");
    value |= (part & 0x7f) << shift;
    if (!(part & 0x80)) return value >>> 0;
    shift += 7;
  }
}

function uleb(value: number): number[] {
  const bytes = [];
  while (value >= 128) {
    bytes.push((value & 0x7f) | 0x80);
    value >>>= 7;
  }
  return [...bytes, value];
}

// Give the test access to the raw mutator and pool handles. Normal source
// ownership rules reject passing a static pool to the mutator's own parameter.
function exposeInternals(
  bytes: Uint8Array<ArrayBuffer>,
  names: string[],
): Uint8Array<ArrayBuffer> {
  const [section] = WebAssembly.Module.customSections(
    new WebAssembly.Module(bytes),
    "name",
  );
  const payload = new Uint8Array(section);
  const functions = new Map<string, number>();
  const cursor = { at: 0 };
  while (cursor.at < payload.length) {
    const subsection = payload[cursor.at++];
    const size = readUleb(payload, cursor);
    const end = cursor.at + size;
    if (subsection === 1) {
      const count = readUleb(payload, cursor);
      for (let i = 0; i < count; i++) {
        const index = readUleb(payload, cursor);
        const length = readUleb(payload, cursor);
        const name = new TextDecoder().decode(
          payload.subarray(cursor.at, cursor.at + length),
        );
        cursor.at += length;
        functions.set(name.split("#")[0], index);
      }
    }
    cursor.at = end;
  }

  cursor.at = 8;
  while (cursor.at < bytes.length) {
    const start = cursor.at;
    const sectionId = bytes[cursor.at++];
    const size = readUleb(bytes, cursor);
    const end = cursor.at + size;
    if (sectionId === 7) {
      const count = readUleb(bytes, cursor);
      const added = names.flatMap((name) => {
        const index = functions.get(name);
        assert.notEqual(index, undefined, name);
        const key = new TextEncoder().encode(name);
        return [...uleb(key.length), ...key, 0, ...uleb(index!)];
      });
      const exports = [
        ...uleb(count + names.length),
        ...bytes.subarray(cursor.at, end),
        ...added,
      ];
      return Uint8Array.from([
        ...bytes.subarray(0, start),
        7,
        ...uleb(exports.length),
        ...exports,
        ...bytes.subarray(end),
      ]);
    }
    cursor.at = end;
  }
  throw new Error("Missing Wasm export section");
}

Deno.test("Wave 1 freshly allocated arrays are writable but static pool handles still trap", async () => {
  await compileAndRun(
    `
const POOL: #[U32] = #[10, 20, 30, 40]
io get_pool (): #[U32] => return POOL
io read_pool (index: U32): U32 => return POOL[index]
io mutate (items: own #[U32]): U32 =>
  items[0] := 77
  return items[0]
`,
    async (guest, wasm) => {
      assert.equal(guest.call("mutate", Uint32Array.of(10)), 77);
      const raw = exposeInternals(wasm, ["pool.POOL", "named.mutate"]);
      const { instance: { exports } } = await WebAssembly.instantiate(raw);
      const pool = exports["pool.POOL"] as () => [number, number];
      const mutate = exports["named.mutate"] as (
        slot: number,
        generation: number,
      ) => number;
      const read = exports.read_pool as (index: number) => number;
      assert.equal(read(0), 10);
      const [slot, generation] = pool();
      assert.throws(() => mutate(slot, generation), WebAssembly.RuntimeError);
      assert.equal(read(0), 10);
    },
  );
});

Deno.test("Wave 1 associative U32 recursion agrees with the recursive definition", async () => {
  await compileAndRun(
    `
io fibonacci (n: U32): U32 =>
  if n < 2:
    return n
  return fibonacci (n - 1) + fibonacci (n - 2)
io branch_sum (n: U32): U32 =>
  if n == 0:
    return 4294967295
  if n == 1:
    return 4160749568
  if (n & 1) == 0:
    return branch_sum (n - 1) + branch_sum (n - 2)
  return 3900000001 + branch_sum (n - 1)
io branch_product (n: U32): U32 =>
  if n < 2:
    return n + 17
  if (n & 1) != 0:
    return 4294967295 * branch_product (n - 1)
  return branch_product (n - 1) * branch_product (n - 2)
io branch_xor (n: U32): U32 =>
  if n < 2:
    return n + 2400000000
  if (n & 1) == 0:
    return branch_xor (n - 1) ^ branch_xor (n - 2)
  return 3500000000 ^ branch_xor (n - 1)
io subtract (n: U32): U32 =>
  if n < 2:
    return n
  return subtract (n - 1) - subtract (n - 2)
`,
    (guest) => {
      const fib = [0, 1];
      const sum = [0xffffffff, 4160749568];
      const product = [17, 18];
      const xor = [2400000000, 2400000001];
      const sub = [0, 1];
      for (let n = 2; n <= 30; n++) {
        fib.push(fib[n - 1] + fib[n - 2]);
        sum.push((sum[n - 1] + (n % 2 ? 3900000001 : sum[n - 2])) >>> 0);
        product.push(
          Math.imul(product[n - 1], n % 2 ? 0xffffffff : product[n - 2]) >>> 0,
        );
        xor.push((xor[n - 1] ^ (n % 2 ? 3500000000 : xor[n - 2])) >>> 0);
        sub.push((sub[n - 1] - sub[n - 2]) >>> 0);
      }
      for (
        const [name, expected] of [
          ["fibonacci", fib],
          ["branch_sum", sum],
          ["branch_product", product],
          ["branch_xor", xor],
          ["subtract", sub],
        ] as const
      ) {
        for (const [n, result] of expected.entries()) {
          assert.equal(
            guest.call(name, n),
            result,
            `${name}(${n})`,
          );
        }
      }
    },
  );
});
