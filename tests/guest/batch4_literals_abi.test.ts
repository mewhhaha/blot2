import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import { instantiateGuest, readMemoryShape } from "../../host/guest.ts";
import { formatSource } from "../../host/format.ts";

const compiler = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const preludePath =
  new URL("../../std/prelude.sq", import.meta.url).pathname;
const stdOpts = { stdRoot: new URL("../../std", import.meta.url).pathname };

async function buildWasm(
  source: string,
  extraArgs: string[] = [],
): Promise<Uint8Array<ArrayBuffer>> {
  const parent = new URL("../../build", import.meta.url).pathname;
  await Deno.mkdir(parent, { recursive: true });
  const dir = await Deno.makeTempDir({ dir: parent, prefix: "batch4-budget-" });
  try {
    const input = `${dir}/program.sq`;
    const output = `${dir}/program.wasm`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(compiler, {
      args: [
        "build",
        input,
        output,
        "--prelude",
        preludePath,
        "--std-root",
        stdOpts.stdRoot,
        ...extraArgs,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!result.success) {
      throw new Error(
        `${new TextDecoder().decode(result.stdout)}\n${
          new TextDecoder().decode(result.stderr)
        }`,
      );
    }
    return await Deno.readFile(output);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Batch 4: char literals, byte strings, and numeric suffixes", async () => {
  await compileAndRun(
    `
func classify (ch: U8): U32 => case ch of
  'a' => 1
  '\\n' => 2
  '\\0' => 3
  '\\x7f' => 4
  '\\'' => 5
  _ => 0

io check_literals (_: Unit): Array U32 =>
  let a = 'a'
  let nl = '\\n'
  let nul = '\\0'
  let hex_ch = '\\x7f'
  let sq = '\\''
  let dq = '\\"'
  let uni: U32 = 'é'
  let txt = "ab"
  let txt_eq: U32 = if txt[0] == 'a' and 'b' == txt[1] then 1 else 0
  let bs = b"Hi\\r\\n\\0\\xff"
  let empty = b""
  let u8v = 0xff_u8
  let u32v = 0x1f32
  let i32v = -42i32
  let u64v = 100_000_000_000u64
  let i64min = -9223372036854775808i64
  let f32v = 1f32 + 2.5_f32
  let f64v = 1f64 + 2.25_f64
  let ok_i32: U32 = if i32v == -42 then 1 else 0
  let ok_u64: U32 = if u64v == 100000000000u64 then 1 else 0
  let ok_i64: U32 = if i64min < 0i64 then 1 else 0
  let ok_f32: U32 = if f32v == 3.5f32 then 1 else 0
  let ok_f64: U32 = if f64v == 3.25f64 then 1 else 0
  let ok_dq: U32 = if dq == 34u8 then 1 else 0
  return #[
    classify a,
    classify nl,
    classify nul,
    classify hex_ch,
    classify sq,
    ok_dq,
    uni,
    txt_eq,
    bs.length,
    U8.to_u32 bs[0],
    U8.to_u32 bs[4],
    U8.to_u32 bs[5],
    empty.length,
    U8.to_u32 u8v,
    u32v,
    ok_i32,
    ok_u64,
    ok_i64,
    ok_f32,
    ok_f64,
  ]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("check_literals", null) as Uint32Array),
        [
          1,
          2,
          3,
          4,
          5,
          1,
          0xe9,
          1,
          6,
          72,
          0,
          255,
          0,
          255,
          0x1f32,
          1,
          1,
          1,
          1,
          1,
        ],
      );
    },
    stdOpts,
  );
});

Deno.test("Batch 4: literal suffix overflow and byte-string in @panic are rejected", async () => {
  await compileExpectedFailure(
    `
io bad (_: Unit): U8 => return 256u8
`,
    "integer_range",
  );
  await compileExpectedFailure(
    `
io bad (_: Unit): U32 =>
  @panic b"not text"
  return 0
`,
    "unsupported",
  );
});

Deno.test("Batch 4: ABI 8 extended scalar, array, constant, and Foreign callback tags 14..23", async () => {
  await compileAndRun(
    `
io const C_U8: U8 = 200u8
io const C_I32: I32 = -12345i32
io const C_U64: U64 = 0xfedc_ba98_7654_3210u64
io const C_I64: I64 = -9000000000000i64
io const C_F64: F64 = 3.141592653589793f64

io echo_u8 (x: U8): U8 => return x + 1u8
io echo_i32 (x: I32): I32 => return x - 10i32
io echo_u64 (x: U64): U64 => return x + 1u64
io echo_i64 (x: I64): I64 => return x * 2i64
io echo_f64 (x: F64): F64 => return x * 0.5f64

io xor_bytes (xs: #[U8]): #[U8] =>
  let out = xs.copy
  for i in 0..out.length:
    out[i] := out[i] ^ 0x55u8
  return out

io sum_i32 (xs: #[I32]): #[I32] =>
  let out = xs.copy
  for i in 0..out.length:
    out[i] := out[i] + 1i32
  return out

io inc_u64 (xs: #[U64]): #[U64] =>
  let out = xs.copy
  for i in 0..out.length:
    out[i] := out[i] + 10u64
  return out

io neg_i64 (xs: #[I64]): #[I64] =>
  let out = xs.copy
  for i in 0..out.length:
    out[i] := 0i64 - out[i]
  return out

io scale_f64 (xs: #[F64]): #[F64] =>
  let out = xs.copy
  for i in 0..out.length:
    out[i] := out[i] * 2.0f64
  return out

io stream_bytes (cb: #[U8] -> #[U8] ! {Foreign}): #[U8] =>
  use res <- cb b"abc"
  return res

io call_u64_f64 (cb: U64 -> F64 ! {Foreign}): F64 =>
  use v <- cb 1000000000000u64
  return v + 0.5f64
`,
    (guest) => {
      assert.equal(guest.abi.version, 8);
      assert.equal(guest.read("C_U8"), 200);
      assert.equal(guest.read("C_I32"), -12345);
      assert.equal(guest.read("C_U64"), 0xfedc_ba98_7654_3210n);
      assert.equal(guest.read("C_I64"), -9000000000000n);
      assert.equal(guest.read("C_F64"), 3.141592653589793);

      assert.equal(guest.call("echo_u8", 41), 42);
      assert.equal(guest.call("echo_i32", -5), -15);
      assert.equal(
        guest.call("echo_u64", 0xffff_ffff_ffff_fffen),
        0xffff_ffff_ffff_ffffn,
      );
      assert.equal(guest.call("echo_i64", -1234567890123n), -2469135780246n);
      assert.equal(guest.call("echo_f64", 7.5), 3.75);

      // Odd lengths test 4-byte packet padding for Array U8 (e.g. length 5 -> alloc 12)
      const bytesIn = new Uint8Array([0, 1, 2, 0x55, 0xff]);
      const bytesOut = guest.call("xor_bytes", bytesIn) as Uint8Array;
      assert.deepEqual(Array.from(bytesOut), [0x55, 0x54, 0x57, 0x00, 0xaa]);

      // Larger array (>32 elems) tests bulk fast path for Array U8 and Array F64
      const bigBytes = new Uint8Array(100);
      for (let i = 0; i < bigBytes.length; i++) bigBytes[i] = i;
      const bigBytesOut = guest.call("xor_bytes", bigBytes) as Uint8Array;
      assert.equal(bigBytesOut.length, 100);
      assert.equal(bigBytesOut[99], 99 ^ 0x55);

      const i32Out = guest.call(
        "sum_i32",
        new Int32Array([-2, 0, 2147483646]),
      ) as Int32Array;
      assert.deepEqual(Array.from(i32Out), [-1, 1, 2147483647]);

      const u64Out = guest.call(
        "inc_u64",
        new BigUint64Array([0n, 0xffff_ffff_ffff_fff0n]),
      ) as BigUint64Array;
      assert.deepEqual(Array.from(u64Out), [10n, 0xffff_ffff_ffff_fffan]);

      const i64Out = guest.call(
        "neg_i64",
        new BigInt64Array([5n, -9_000_000_000_000n]),
      ) as BigInt64Array;
      assert.deepEqual(Array.from(i64Out), [-5n, 9_000_000_000_000n]);

      const f64In = new Float64Array(24);
      for (let i = 0; i < f64In.length; i++) f64In[i] = i + 0.125;
      const f64Out = guest.call("scale_f64", f64In) as Float64Array;
      assert.equal(f64Out.length, 24);
      assert.equal(f64Out[0], 0.25);
      assert.equal(f64Out[23], 46.25);

      const byteCb = guest.capability({
        parameter: "Array U8",
        result: "Array U8",
        call: (arr) => new Uint8Array([...arr, 33]),
      });
      const streamed = guest.call("stream_bytes", byteCb) as Uint8Array;
      assert.deepEqual(Array.from(streamed), [97, 98, 99, 33]);

      const u64Cb = guest.capability({
        parameter: "U64",
        result: "F64",
        call: (n) => Number(n) / 1e12,
      });
      assert.equal(guest.call("call_u64_f64", u64Cb), 1.5);
    },
    stdOpts,
  );
});

Deno.test("Batch 4: configurable --stack-mb, --heap-mb, --transport-mb memory budgets", async () => {
  const source = `
io byte_len (xs: #[U8]): U32 => return xs.length
`;
  const defaultWasm = await buildWasm(source);
  const customWasm = await buildWasm(source, [
    "--stack-mb",
    "16",
    "--heap-mb",
    "16",
    "--transport-mb",
    "4",
  ]);

  const defaultShape = readMemoryShape(defaultWasm);
  const customShape = readMemoryShape(customWasm);
  assert.ok(
    (customShape.maximumPages ?? 0) < (defaultShape.maximumPages ?? 0),
    `Expected smaller maximumPages with 16/16/4 MiB (${customShape.maximumPages}) than default 128/128/2 MiB (${defaultShape.maximumPages})`,
  );

  // 3 MiB payload exceeds default 2 MiB transport, succeeds with --transport-mb 4.
  const payload = new Uint8Array(3 * 1024 * 1024);
  const customGuest = await instantiateGuest(customWasm);
  try {
    assert.equal(customGuest.call("byte_len", payload), payload.length);
  } finally {
    customGuest.dispose();
  }
  const defaultGuest = await instantiateGuest(defaultWasm);
  try {
    assert.throws(() => defaultGuest.call("byte_len", payload));
  } finally {
    defaultGuest.dispose();
  }
});

Deno.test("Batch 4: formatter round-trips char literals, byte strings, and numeric suffixes", async () => {
  const source = `io main (_: Unit): U32 =>
  let a = 'a'
  let b = b"hello\\n\\x00"
  let x = 0xff_u8
  let y = 1.5f64
  return case a of
    'a' => b.length + U8.to_u32 x
    _ => F64.to_u32 y
`;
  const formatted = await formatSource(source);
  assert.equal(formatted, source);
});
