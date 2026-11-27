import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const flags = (checks: readonly string[]) =>
  `#[${checks.map((check) => `if ${check} then 1 else 0`).join(", ")}]`;

function checkFlags(actual: unknown, checks: readonly string[]) {
  assert.deepEqual(
    Array.from(
      actual as Uint32Array,
      (value, index) => value === 1 ? null : checks[index],
    ).filter((value) => value !== null),
    [],
  );
  assert.equal((actual as Uint32Array).length, checks.length);
}

for (
  const [type, signed, width] of [
    ["U8", false, 8],
    ["I32", true, 32],
    ["U64", false, 64],
    ["I64", true, 64],
  ] as const
) {
  Deno.test(`Wave 3 ${type} arithmetic, comparison, shifts and traps`, async () => {
    const a = signed ? "-14" : "14";
    const checks = [
      `(a + 3) == ${signed ? "-11" : "17"}`,
      `(3 + a) == ${signed ? "-11" : "17"}`,
      `(a - b) == ${signed ? "-17" : "11"}`,
      `(a * b) == ${signed ? "-42" : "42"}`,
      `(a / b) == ${signed ? "-4" : "4"}`,
      `(a % b) == ${signed ? "-2" : "2"}`,
      "(a & b) == 2",
      `(a | b) == ${signed ? "-13" : "15"}`,
      `(a ^ b) == ${signed ? "-15" : "13"}`,
      `(~a) == ${signed ? "13" : width === 8 ? "241" : "0xfffffffffffffff1"}`,
      `(a << ${width + 1}) == ${signed ? "-28" : "28"}`,
      `(a >> ${width + 1}) == ${signed ? "-7" : "7"}`,
      `a == ${a}`,
      "a != b",
      signed ? "a < b" : "b < a",
      signed ? "a <= b" : "b <= a",
      signed ? "b > a" : "a > b",
      signed ? "b >= a" : "a >= b",
      `${type}.abs a == 14`,
    ];
    let extra = "";
    if (signed) {
      const min = -(1n << BigInt(width - 1));
      const max = -min - 1n;
      extra = `
io overflow (): U32 => (${type}.div (${min}) (-1)).to_u32
`;
      checks.push(
        "(-a) == 14",
        `(${type}.neg (${min})) == ${min}`,
        `(${type}.abs (${min})) == ${min}`,
        `((${type}.add ${max} 1) == ${min})`,
        `((${type}.rem (${min}) (-1)) == 0)`,
      );
    } else {
      const max = (1n << BigInt(width)) - 1n;
      checks.push(
        `(${type}.add ${max} 1) == 0`,
        `(${type}.sub 0 1) == ${max}`,
        `(${type}.mul ${max} 2) == ${max - 1n}`,
        `(${type}.div ${max} 2) == ${max / 2n}`,
        `a < ${max}`,
      );
    }
    await compileAndRun(
      `
io arithmetic (): #[U32] =>
  let a: ${type} = ${a}
  let b: ${type} = 3
  return ${flags(checks)}
io divide (divisor: U32): U32 => (${type}.div 14 divisor.to_${type.toLowerCase()}).to_u32
io remainder (divisor: U32): U32 => (${type}.rem 14 divisor.to_${type.toLowerCase()}).to_u32
${extra}
`,
      (guest) => {
        checkFlags(guest.call("arithmetic", null), checks);
        assert.equal(guest.call("divide", 3), 4);
        assert.equal(guest.call("remainder", 3), 2);
        assert.throws(
          () => guest.call("divide", 0),
          WebAssembly.RuntimeError,
        );
        assert.throws(
          () => guest.call("remainder", 0),
          WebAssembly.RuntimeError,
        );
        if (signed) {
          assert.throws(
            () => guest.call("overflow", null),
            WebAssembly.RuntimeError,
          );
        }
      },
    );
  });
}

Deno.test("Wave 3 F64 uses binary64 arithmetic and canonical NaNs", async () => {
  const checks = [
    "(x + y) == -0.5",
    "(x - y) == -2.5",
    "(x * y) == -1.5",
    "(x / y) == -1.5",
    "(-x) == 1.5",
    "F64.abs x == 1.5",
    "F64.sqrt 2.25 == 1.5",
    "F64.floor x == -2.0",
    "F64.ceil x == -1.0",
    "F64.trunc x == -1.0",
    "x == -1.5",
    "x != y",
    "x < y",
    "x <= x",
    "y > x",
    "y >= y",
    "F64.min x y == x",
    "F64.max x y == y",
    "(y + 1e-15) != y",
    "F64.to_bits 1.00000000000000011102230246251565404236316680908203125 == 0x3ff0000000000000",
    "F64.to_bits (-0.0) == 0x8000000000000000",
    "F64.to_bits 5e-324 == 1",
    "F64.to_bits 1.7976931348623157e308 == 0x7fefffffffffffff",
    "F64.to_bits nan == 0xfff8000000000099",
    "F64.to_bits (0.0 / zero) == canonical",
    "F64.to_bits (F64.sqrt (-1.0)) == canonical",
    "F64.to_bits (inf - inf) == canonical",
    "F64.to_bits (nan + y) == canonical",
    "F64.to_bits (nan * y) == canonical",
    "F64.to_bits (F64.floor nan) == canonical",
    "F64.to_bits (F64.ceil nan) == canonical",
    "F64.to_bits (F64.trunc nan) == canonical",
    "F64.to_bits f32_nan.to_f64 == canonical",
    "F32.to_bits nan.to_f32 == 0x7fc00000",
    "F32.to_bits f32_nan == 0xffc00099",
    "F32.to_bits 1.00000005960464477539062500000001 == 0x3f800001",
  ];
  await compileAndRun(
    `
io floats (): #[U32] =>
  let x: F64 = -1.5
  let y: F64 = 1.0
  let zero: F64 = 0.0
  let inf = F64.from_bits 0x7ff0000000000000
  let nan = F64.from_bits 0xfff8000000000099
  let f32_nan = F32.from_bits 0xffc00099
  let canonical: U64 = 0x7ff8000000000000
  return ${flags(checks)}
`,
    (guest) => checkFlags(guest.call("floats", null), checks),
  );
});

Deno.test("Wave 3 literals take the type of their use", async () => {
  await compileAndRun(
    `
type Row = { a: U8, b: U64, c: F64, d: I32 }
const key: U64 = 0x9e3779b97f4a7c15
func one (): I64 => return -9223372036854775808
func byte (b: U8): U32 => return b.to_u32
func classify (x: U64): U8 => case x of
  0xffffffffffffffff => 255
  4294967296 => 123
  _ => 0
func signed (x: I64): U32 => case x of
  -9223372036854775808 => 1
  _ => 0
io contexts (input: U32): #[U32] =>
  let row: Row = { a: 255, b: 0xffffffffffffffff, c: 3.141592653589793, d: -2147483648 }
  let pair: (I64, F64) = (-42, -1.0)
  let nested: U8 = (254 + 1) + 2
  let a: U8 = if input == 0 then 255 else 127
  a := 0
  let buf: #[U8] = #[1, 2, 3]
  buf[1] := 255
  let chosen: U8 = case buf[1] of
    0 => 42
    255 => 23
    _ => 100
  let (n, f) = pair
  return #[row.a.to_u32, (row.b >> 60).to_u32, (F64.to_bits row.c).to_u32,
    row.d.to_u32, byte 42, byte a, byte chosen, byte (classify row.b),
    byte (classify 4294967296), signed (one ()), n.to_u32, (F64.to_bits f >> 32).to_u32,
    key.to_u32, nested.to_u32]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("contexts", 0),
        Uint32Array.of(
          255,
          15,
          0x54442d18,
          0x80000000,
          42,
          0,
          23,
          255,
          123,
          1,
          0xffffffd6,
          0xbff00000,
          0x7f4a7c15,
          1,
        ),
      );
    },
  );
});

Deno.test("Wave 3 rejects literals outside their type's range", async () => {
  for (
    const [binding, code] of [
      ["const bad: U8 = 256", "integer_range"],
      ["const bad: I32 = 2147483648", "integer_range"],
      ["const bad: I32 = -2147483649", "integer_range"],
      ["const bad: I64 = 9223372036854775808", "integer_range"],
      ["const bad: I64 = -9223372036854775809", "integer_range"],
      ["const bad: U64 = 0x10000000000000000", "integer_range"],
      ["const bad = 4294967296", "integer_range"],
      ["const bad = 1e39", "float_range"],
      ["const bad: F64 = 1e309", "float_range"],
      ["const bad: F64 = -1e309", "float_range"],
    ]
  ) {
    await compileExpectedFailure(binding + "\n", code);
  }
});

Deno.test("Wave 3 packed U8 storage spans fewer than 11 pages", async () => {
  await compileAndRun(
    `
io packed (count: U32): #[U32] =>
  let initial: U8 = 77
  let bytes = Array.create count initial
  bytes[0] := 255
  bytes[count - 1] := 123
  return #[bytes[0].to_u32, bytes[count / 2].to_u32, bytes[count - 1].to_u32]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("packed", 400_000),
        Uint32Array.of(255, 77, 123),
      );
      assert(
        guest.memoryBytes() <= 10 * 65_536,
        `${guest.memoryBytes()} bytes`,
      );
    },
  );
});

Deno.test("Wave 3 U8 arrays preserve byte strides through copies and fork", async () => {
  await compileAndRun(
    `
io storage (): #[U32] =>
  let buffer: #[U8] = #[1, 2, 3]
  let clone = buffer.clone
  let spec = fork buffer:
    buffer[0] := 200
    buffer := buffer.push 254
    return buffer[0].to_u32 + buffer[3].to_u32
  buffer := buffer.push 255
  let (remaining, last) = buffer.pop
  let slice = remaining.slice 1 2
  let joined = slice.concat clone
  joined := joined.truncate 4
  let sum = 0
  for value in joined:
    sum := sum + value.to_u32
  return #[spec, last.to_u32, remaining[0].to_u32, clone[0].to_u32, joined.length, sum]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("storage", null),
        Uint32Array.of(454, 255, 1, 1, 4, 8),
      );
    },
  );
});

Deno.test("Wave 3 64-bit arrays and mixed-width records survive fork rollback", async () => {
  await compileAndRun(
    `
type Row = { a: U8, b: U64, c: F64, d: I32 }
type Mixed is data = $Empty | $Row Row | $Box {
  a: U8, b: U64, c: F64, d: I32, e: U8, f: U64, g: F64, h: I64, i: U32,
  j: U8, k: U64, l: F64, m: I32, n: U8, o: U64, p: F64, q: I64
}
io storage (): #[U32] =>
  let us: #[U64] = #[0x100000001, 0x200000002]
  let ss: #[I64] = #[-4294967297, -4294967298]
  let fs: #[F64] = #[1.25, 2.5]
  let rows: #[Row] = #[{a: 7, b: 0x100000999, c: 3.25, d: -8}]
  let boxes: #[Mixed] = #[$Box {a: 1, b: 0x200000003, c: 0.5, d: -4, e: 5, f: 0x300000004, g: 5.5, h: -9, i: 17, j: 0, k: 0, l: 0.0, m: 0, n: 0, o: 0, p: 0.0, q: 0}]
  let spec = fork us, ss, fs, rows, boxes:
    us[0] := 0x500000006
    ss[0] := -11
    fs[1] := 7.0
    rows[0].c := 9.0
    boxes[0] := $Empty
    return (us[0] >> 32).to_u32 + ss[0].to_u32 + fs[1].to_u32 + rows[0].c.to_u32
  let row = rows[0]
  let boxed = case boxes[0] of
    $Box {b, g, i} => (b >> 32).to_u32 + g.to_u32 + i
    _ => 0
  let plus = func () => return us[1] + row.b
  return #[spec, (us[0] >> 32).to_u32, ss[1].to_u32, fs[1].to_u32, row.a.to_u32,
    (row.b >> 32).to_u32, row.c.to_u32, row.d.to_u32, boxed, (plus () >> 32).to_u32]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("storage", null),
        Uint32Array.of(10, 1, 0xfffffffe, 2, 7, 1, 3, 0xfffffff8, 24, 3),
      );
    },
  );
});

Deno.test("Wave 3 conversions cover every source and destination type", async () => {
  const types = ["U8", "U32", "I32", "U64", "I64", "F32", "F64"];
  const common = types.flatMap((src) =>
    types.map((dst) => {
      const literal = dst.startsWith("F") ? "237.0" : "237";
      return `${dst}.eq ${src.toLowerCase()}.to_${dst.toLowerCase()} ${literal}`;
    })
  );
  const checks = [
    ...common,
    "U8.from u64 == 237",
    "I32.from u8 == 237",
    "U64.from i32 == 237",
    "I64.from u32 == 237",
    "F64.from f32 == 237.0",
    "narrowed == 255",
    "negative.to_u64 == 0xffffffffffffffff",
    "negative.to_i64 == -1",
    "negative.to_u32 == 0xffffffff",
    "maximum.to_i32 == -1",
    "maximum.to_i64 == 4294967295",
    "wide.to_i64 == -1",
    "wide.to_u32 == 0xffffffff",
    "wide.to_i32 == -1",
    "wide.to_u8 == 255",
    "wide.to_f64 == 18446744073709551616.0",
    "negative64.to_f64 == -4294967297.0",
    "negative64.to_f32 == -4294967296.0",
    "big.to_u8 == 255",
    "f32big.to_u8 == 255",
    "f32low.to_u8 == 0",
    "neg.to_u8 == 0",
    "nan.to_u8 == 0",
    "f32nan.to_u8 == 0",
    "neg.to_i32 == -2147483648",
    "big.to_i32 == 2147483647",
    "neg.to_i64 == -9223372036854775808",
    "big.to_i64 == 9223372036854775807",
    "big.to_u64 == 0xffffffffffffffff",
    "neg.to_u64 == 0",
    "big.to_u32 == 0xffffffff",
    "nan.to_i64 == 0",
    "f32nan.to_i32 == 0",
  ];
  await compileAndRun(
    `
io conversions (): #[U32] =>
${
      types.map((type) =>
        `  let ${type.toLowerCase()}: ${type} = ${
          type.startsWith("F") ? "237.0" : "237"
        }`
      ).join("\n")
    }
  let negative: I32 = -1
  let negative64: I64 = -4294967297
  let maximum: U32 = 0xffffffff
  let wide: U64 = 0xffffffffffffffff
  let narrowed = maximum.to_u8
  let big: F64 = 1e40
  let neg: F64 = -1e40
  let f32big: F32 = 300.0
  let f32low: F32 = -5.0
  let nan = F64.from_bits 0x7ff8000000000001
  let f32nan = F32.from_bits 0x7fc00001
  return ${flags(checks)}
`,
    (guest) => checkFlags(guest.call("conversions", null), checks),
  );
});

Deno.test("Wave 3 SplitMix64 and base-2^30 multiply-add-div match BigInt", async () => {
  const state = 0x9e3779b97f4a7c15n;
  const mask = (1n << 64n) - 1n;
  const step = (x: bigint) => {
    let z = x;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & mask;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & mask;
    return z ^ (z >> 31n);
  };
  const base = 1n << 30n;
  const limbs = [0x3fffffffn, 0x31002345n, 0x2edcba98n, 321n];
  const multiply = 0x3fffffefn;
  const divisor = 0x3ffffffdn;
  let input = 0n;
  for (const limb of limbs.toReversed()) input = input * base + limb;
  const total = input * multiply + 17n;
  let quotient = total / divisor;
  const words = [Number(total % divisor)];
  for (let i = 0; i < limbs.length; ++i) {
    words.push(Number(quotient % base));
    quotient /= base;
  }
  words.push(Number(quotient));
  await compileAndRun(
    `
func mix (input: U64): U64 =>
  let a = (input ^ (input >> 30)) * 0xbf58476d1ce4e5b9
  let b = (a ^ (a >> 27)) * 0x94d049bb133111eb
  return b ^ (b >> 31)
io splitmix (seed: U32): #[U32] =>
  let state = seed.to_u64
  let output = @array.fill 16 0
  for i in 0..8:
    state := state + 0x9e3779b97f4a7c15
    let value = mix state
    output[2 * i] := value.to_u32
    output[2 * i + 1] := (value >> 32).to_u32
  return output
io limbs (): #[U32] =>
  let base: U64 = 1073741824
  let multiplier: U64 = 0x3fffffef
  let divisor: U64 = 0x3ffffffd
  let a: #[U64] = #[0x3fffffff, 0x31002345, 0x2edcba98, 321, 0]
  let carry: U64 = 17
  for i in 0..4:
    let v = a[i] * multiplier + carry
    a[i] := v % base
    carry := v / base
  a[4] := carry
  let rem: U64 = 0
  for i in 0..5:
    let index = 4 - i
    let v = rem * base + a[index]
    a[index] := v / divisor
    rem := v % divisor
  return #[rem.to_u32, a[0].to_u32, a[1].to_u32, a[2].to_u32, a[3].to_u32, a[4].to_u32]
`,
    (guest) => {
      const seed = 0xfedcba98;
      const expected = [];
      for (let i = 1n; i <= 8n; ++i) {
        const value = step((BigInt(seed) + i * state) & mask);
        expected.push(Number(value & 0xffffffffn), Number(value >> 32n));
      }
      assert.deepEqual(
        guest.call("splitmix", seed),
        Uint32Array.from(expected),
      );
      assert.deepEqual(guest.call("limbs", null), Uint32Array.from(words));
    },
  );
});

Deno.test("Wave 3 #run preserves wide bits, signedness and NaNs", async () => {
  await compileAndRun(
    `
func calculate (): (U64, I64, F64) =>
  let nan = F64.from_bits 0xfff8000000000001
  let result: U64 = (U64.mul 0xffffffff 0xffffffff) >> 32
  let negative: I64 = -4294967297
  return (result, negative >> 32, F64.ceil nan)
const staged = #run (calculate ())
io values (): #[U32] =>
  let (a, b, c) = staged
  let d = (F64.to_bits c) >> 32
  return #[a.to_u32, b.to_u32, d.to_u32]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("values", null),
        Uint32Array.of(0xfffffffe, 0xfffffffe, 0x7ff80000),
      );
    },
  );
});

Deno.test("Wave 3 wide literals survive dependency bundles and retained edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-wave3-bundle-" });
  const entry = directory + "/main.sq";
  const library = directory + "/wide.sq";
  const dependencies = directory + "/wide.sqdep";
  const executable = Deno.args[0] ??
    new URL("../../compiler-goose/build/squidc-goose", import.meta.url)
      .pathname;
  const prelude = new URL("../../std/prelude.sq", import.meta.url).pathname;
  const source = `func mix (x: U64): U64 => x ^ 0x100000001
func offset (x: F64): F64 => x + 1e-15
`;
  try {
    await Deno.writeTextFile(library, source);
    await Deno.writeTextFile(
      entry,
      `import {mix, offset} from "./wide"
io evaluate (x: U32): #[U32] =>
  let bits = F64.to_bits (offset 1.0)
  let out = mix x.to_u64
  return #[out.to_u32, (out >> 32).to_u32, bits.to_u32, (bits >> 32).to_u32]
`,
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const options = { executable, prelude, entry };
    const session = await createZigProjectCompiler({
      ...options,
      dependencies,
    });
    const cold = await createZigProjectCompiler(options);
    try {
      const initial = await session.build();
      assert(initial.success, JSON.stringify(initial));
      assert(initial.stats.cachedModules > 0);
      const original = await cold.build();
      assert(original.success, JSON.stringify(original));
      assert.deepEqual(original.bytes, initial.bytes);
      const overlay = {
        sources: { [library]: source.replace("0x100000001", "0x200000001") },
      };
      const edited = await session.build(overlay);
      const reference = await cold.build(overlay);
      assert(edited.success, JSON.stringify(edited));
      assert(reference.success, JSON.stringify(reference));
      assert.deepEqual(edited.bytes, reference.bytes);
      for (const [build, high] of [[initial, 1], [edited, 2]] as const) {
        const guest = await instantiateGuest(build.bytes);
        try {
          assert.deepEqual(
            guest.call("evaluate", 7),
            Uint32Array.of(6, high, 5, 0x3ff00000),
          );
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await cold.dispose();
      await session.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
