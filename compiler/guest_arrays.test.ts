import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { GuestError, instantiateGuest } from "./guest.ts";
import { compile } from "./test_compile.ts";

const source = `
entry const integers = fn (values: Array U32) => values
entry const floats = fn (values: Array F32) => values
entry const change = fn (values: Array F32) => @array.set values 0 42.5
entry const first = fn (values: Array F32) => @array.get values 0
entry const filled = fn (count: U32) => @array.fill count 3.5
entry const empty = fn () => @array.fill 0 0
entry const constant = fn () => #[1, 4_294_967_295]
entry const callback = fn (io: U32 -> U32 ! {Foreign}) => do:
  use value <- io 40
  return value
`;

async function exercise(bytes: Uint8Array<ArrayBuffer>) {
  const guest = await instantiateGuest(bytes);
  try {
    equal(guest.abi.version, 2);
    equal(guest.abi.functions[0], {
      name: "integers",
      parameter: "Array U32",
      result: "Array U32",
    });
    const integers = new Uint32Array([0, 42, 0xffffffff]);
    const floats = new Float32Array([0, -0, 1.1, Infinity, -Infinity, NaN]);
    for (
      const [name, input] of [
        ["integers", integers],
        ["floats", floats],
        ["integers", new Uint32Array()],
        ["floats", new Float32Array()],
      ] as const
    ) {
      const output = guest.call(name, input);
      equal(output, input);
      ok(output !== input);
      ok(output instanceof Uint32Array || output instanceof Float32Array);
      ok(output.buffer !== input.buffer);
    }
    // Views may cover only a middle range of a larger backing buffer.
    for (
      const [name, input] of [
        [
          "integers",
          new Uint32Array([123, 0, 0x12345678, 0xffffffff, 456]).subarray(1, 4),
        ],
        [
          "floats",
          new Float32Array([123, -0, Infinity, 1.25, 456]).subarray(1, 4),
        ],
      ] as const
    ) {
      const output = guest.call(name, input);
      equal(output, input);
      ok(output instanceof Uint32Array || output instanceof Float32Array);
      equal(output.length, 3);
      ok(output.buffer !== input.buffer);
      input[0] = 99;
      ok(!Object.is(output[0], 99));
    }
    // No numeric conversion should quiet a signaling NaN or lose payload bits
    // during an otherwise identity round trip through the array ABI.
    const bits = new Uint32Array([
      0x7f800001,
      0x7fc12345,
      0xffc12345,
      0x80000000,
      0x3f800001,
    ]);
    const bitResult = guest.call("floats", new Float32Array(bits.buffer));
    ok(bitResult instanceof Float32Array);
    equal(new Uint32Array(bitResult.buffer), bits);
    // Exercise both sides of the bulk-copy threshold with ordinary and shared
    // offset views. Shared inputs use word reads, not independently racing bytes.
    for (const Buffer of [ArrayBuffer, SharedArrayBuffer]) {
      for (const length of [0, 1, 32, 33, 4096]) {
        const storage = new Buffer((length + 2) * 4);
        const words = new Uint32Array(storage, 4, length);
        for (let index = 0; index < length; index++) {
          words[index] = bits[index % bits.length];
        }
        const snapshot = new Uint32Array(words);
        const integerCopy = guest.call("integers", words);
        const floatCopy = guest.call(
          "floats",
          new Float32Array(storage, 4, length),
        );
        equal(integerCopy, snapshot);
        ok(floatCopy instanceof Float32Array);
        equal(new Uint32Array(floatCopy.buffer), snapshot);
        words.fill(0);
        equal(integerCopy, snapshot);
        equal(new Uint32Array(floatCopy.buffer), snapshot);
      }
    }
    const output = guest.call("change", floats);
    equal(floats[0], 0);
    ok(output instanceof Float32Array);
    equal(output[0], 42.5);
    output[0] = 999;
    equal(guest.call("first", floats), 0);
    equal(guest.call("empty", null), new Uint32Array());
    equal(guest.call("constant", null), new Uint32Array([1, 0xffffffff]));
    // Input allocation and the guest's copy each cross memory page boundaries.
    const large = new Float32Array(70_000).fill(2.25);
    const changed = guest.call("change", large);
    ok(changed instanceof Float32Array);
    equal(changed.length, large.length);
    equal(changed[0], 42.5);
    equal(changed[large.length - 1], 2.25);
    for (let index = 0; index < 70; index++) {
      equal(guest.call("filled", 70_000), new Float32Array(70_000).fill(3.5));
    }
    equal(changed[0], 42.5);
    equal(large[0], 2.25);
    for (
      const invalid of [[], new Uint32Array(1), new Float64Array(1), null, 0]
    ) {
      throws(() => guest.call("floats", invalid), (error) => {
        ok(error instanceof GuestError);
        equal(error.code, "invalid_argument");
        return true;
      });
    }
    throws(() => guest.call("integers", new Float32Array(1)), GuestError);
    throws(
      () => guest.call("first", new Float32Array()),
      WebAssembly.RuntimeError,
    );
    // Each input/copy crosses the old 16 MiB boundary; host and guest limits
    // must agree, and a later call must still reset and reuse the arena.
    const beyondBootstrap = new Float32Array(4_194_304).fill(2.25);
    const copied = guest.call("change", beyondBootstrap);
    ok(copied instanceof Float32Array);
    equal(copied.length, beyondBootstrap.length);
    equal(copied[0], 42.5);
    equal(copied[copied.length - 1], 2.25);
    equal(beyondBootstrap[0], 2.25);
    throws(() => guest.call("filled", 1_073_741_823), WebAssembly.RuntimeError);
    equal(guest.call("first", new Float32Array([7])), 7);
    equal(
      guest.call(
        "callback",
        guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => value + 2,
        }),
      ),
      42,
    );
  } finally {
    guest.dispose();
  }
}

Deno.test("numeric array ABI copies inputs/results and resets after growth and traps", async () => {
  await exercise((await compile(source)).bytes);
});
