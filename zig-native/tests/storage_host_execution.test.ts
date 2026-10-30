import { strict as assert } from "node:assert";
import { readGuestAbi } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("data-stack host arrays copy packets and preserve application owners after traps", async () => {
  await compileAndRun(
    `
const world: ResizeArray U32 = #[40]
entry const exchange = func (input: Array U32): Array U32 => return do:
  let previous = @storage.copy world
  let changed = @storage.write (&world[0]) input[0]
  return @storage.freeze previous
entry const read = func () => return world[0]
entry const floats = func (input: Array F32): Array F32 => return do:
  let scratch: GrowArray F32 = #[input[1], input[0]]
  return @storage.freeze scratch
`,
    (guest, bytes) => {
      const input = new Uint32Array([42]);
      const output = guest.call("exchange", input);
      assert.deepEqual(output, new Uint32Array([40]));
      input[0] = 99;
      assert.equal(guest.call("read", null), 42);
      assert.throws(() => guest.call("exchange", new Uint32Array()));
      assert.equal(guest.call("read", null), 42);
      assert.deepEqual(
        guest.call("exchange", new Uint32Array([7])),
        new Uint32Array([42]),
      );
      assert.deepEqual(output, new Uint32Array([40]));
      assert.deepEqual(
        guest.call("floats", new Float32Array([1.5, -2.25])),
        new Float32Array([-2.25, 1.5]),
      );
      assert.throws(() => guest.call("exchange", new Uint32Array(300000)));
      assert.equal(guest.call("read", null), 7);
      const module = new WebAssembly.Module(bytes);
      assert.equal(readGuestAbi(module).version, 8);
      assert.equal(
        WebAssembly.Module.customSections(module, "blot:ownership").length,
        0,
      );
      assert.deepEqual(WebAssembly.Module.imports(module), []);
      assert(
        !WebAssembly.Module.exports(module).some(({ name }) =>
          /retain|release|cycle|ownership/.test(name)
        ),
      );
      const exports = new WebAssembly.Instance(module).exports;
      assert.throws(
        () => (exports["blot:memory"] as WebAssembly.Memory).grow(1),
        RangeError,
      );
      assert.throws(
        () => (exports.exchange as CallableFunction)(0),
        WebAssembly.RuntimeError,
      );
      const allocate = exports["blot:allocate"] as CallableFunction;
      const reset = exports["blot:reset"] as CallableFunction;
      reset(0);
      const pointer = allocate(4);
      new DataView((exports["blot:memory"] as WebAssembly.Memory).buffer)
        .setUint32(pointer, 0xffffffff, true);
      assert.throws(
        () => (exports.exchange as CallableFunction)(pointer),
        WebAssembly.RuntimeError,
      );
    },
  );
});

Deno.test("data-stack callbacks exchange independent packets without retaining heap objects", async () => {
  await compileAndRun(
    `
const calls: ResizeArray U32 = #[0]
const invoke = func host -> packet => return host packet
entry const exchange = func (host: Array F32 -> Array F32 ! {Foreign}): Array F32 => return do:
  let request: GrowArray F32 = #[1.5, 2.5]
  let changed = @storage.write (&calls[0]) (@u32.add calls[0] 1)
  use first <- invoke host (@storage.freeze request)
  use second <- host first
  return #[first[0], second[0], request[0]]
entry const count = func () => return calls[0]
`,
    (guest) => {
      let count = 0;
      const host = guest.capability({
        parameter: "Array F32",
        result: "Array F32",
        call: (values) => {
          count++;
          assert.deepEqual(
            values,
            new Float32Array(count % 2 === 1 ? [1.5, 2.5] : [40]),
          );
          values[0] = 99;
          return new Float32Array([count % 2 === 1 ? 40 : 42]);
        },
      });
      for (let n = 0; n < 32; n++) {
        assert.deepEqual(
          guest.call("exchange", host),
          new Float32Array([40, 42, 1.5]),
        );
      }
      assert.equal(guest.call("count", null), 32);
      const failed = guest.capability({
        parameter: "Array F32",
        result: "Array F32",
        call: () => {
          throw new Error("host stopped");
        },
      });
      assert.throws(() => guest.call("exchange", failed));
      assert.equal(guest.call("count", null), 33);
      assert.deepEqual(
        guest.call("exchange", host),
        new Float32Array([40, 42, 1.5]),
      );
    },
  );
});

Deno.test("ordinary suspended host calls keep data stacks alive and exclude reentry", async () => {
  await compileAndRun(
    `
const world: ResizeArray U32 = #[7]
entry const main = func (host: U32 -> U32 ! {Foreign}) => return do:
  let scratch: GrowArray U32 = #[40]
  let reference = &scratch[0]
  use next <- host (@storage.load reference)
  let changed = @storage.write reference next
  let published = @storage.write (&world[0]) next
  return @storage.load reference
entry const read = func () => return world[0]
`,
    async (guest) => {
      let resolve!: (value: number) => void;
      const host = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          assert.equal(value, 40);
          return new Promise<number>((ready) => {
            resolve = ready;
          });
        },
      });
      const pending = guest.callAsync("main", host);
      await assert.rejects(() => guest.callAsync("read", null), {
        code: "reentrant_call",
      });
      assert.throws(() => guest.dispose(), { code: "reentrant_call" });
      resolve(42);
      assert.equal(await pending, 42);
      assert.equal(await guest.callAsync("read", null), 42);
      const failed = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: () => Promise.reject(new Error("host stopped")),
      });
      await assert.rejects(() => guest.callAsync("main", failed), {
        code: "host_exception",
      });
      assert.equal(await guest.callAsync("read", null), 42);
    },
    { asynchronous: true },
  );
});

Deno.test("Foreign transport budgets both sides of a large copied packet", async () => {
  await compileAndRun(
    `
const calls: ResizeArray U32 = #[0]
entry const exchange = func (host: Array U32 -> Array U32 ! {Foreign}) => return do:
  let request: GrowArray U32 = #[]
  for 0 .. 153600:
    let item = @storage.push request 42
  use response <- host (@storage.freeze request)
  let count = @storage.write (&calls[0]) (calls[0] + 1)
  return response[153599] + request[0]
entry const count = func () => return calls[0]
`,
    (guest) => {
      const host = guest.capability({
        parameter: "Array U32",
        result: "Array U32",
        call: (values) => {
          assert.equal(values.length, 153600);
          assert.equal(values[0], 42);
          values[0] = 100;
          return new Uint32Array(153600).fill(7);
        },
      });
      assert.equal(guest.call("exchange", host), 49);
      assert.equal(guest.call("count", null), 1);
      const tooLarge = guest.capability({
        parameter: "Array U32",
        result: "Array U32",
        call: () => new Uint32Array(600000),
      });
      assert.throws(() => guest.call("exchange", tooLarge));
      assert.equal(guest.call("count", null), 1);
      assert.equal(guest.call("exchange", host), 49);
    },
  );
});

Deno.test("data-stack ABI identifies scalar-only exports without transport", async () => {
  await compileAndRun(
    `
const state: ResizeArray U32 = #[41]
entry const next = func () => return do:
  let pool = state
  pool[0] := @u32.add pool[0] 1
  return state[0]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.equal(readGuestAbi(module).version, 8);
      assert.equal(
        WebAssembly.Module.customSections(module, "blot:ownership").length,
        0,
      );
      assert.deepEqual(
        WebAssembly.Module.exports(module).map(({ name }) => name),
        ["next"],
      );
      assert.equal(guest.call("next", null), 42);
      assert.equal(guest.call("next", null), 43);
      // An ABI version cannot disguise either legacy runtime contract.
      for (
        const [name, payload] of [
          ["blot:ownership", [1, 0, 1]],
          ["blot:tasks", [2, 0]],
        ] as const
      ) {
        const title = new TextEncoder().encode(name);
        const section = [title.length, ...title, ...payload];
        const mixed = new WebAssembly.Module(
          new Uint8Array([...bytes, 0, section.length, ...section]),
        );
        assert.throws(() => readGuestAbi(mixed), /ownership/);
      }
    },
  );
});
