import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { GuestError, instantiateGuest } from "./guest.ts";
import { compile as compileArtifact } from "./test_compile.ts";

function errorCode(code: GuestError["code"]) {
  return (error: unknown) => {
    ok(error instanceof GuestError, String(error));
    equal(error.code, code);
    return true;
  };
}

async function compile(source: string) {
  return (await compileArtifact(source)).bytes;
}

Deno.test("async capabilities suspend main while retaining locals and exclusive invocation ownership", async () => {
  const bytes = await compile(`
entry const main = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- host 40
  use second <- host first
  return @u32.add first second
entry const pure = fn () => 7
`);
  const guest = await instantiateGuest(bytes, { asynchronous: true });
  let resume!: (value: number) => void;
  let calls = 0;
  const host = guest.capabilityAsync({
    parameter: "U32",
    result: "U32",
    call: (value) => {
      calls++;
      if (calls === 1) {
        equal(value, 40);
        return new Promise<number>((resolve) => {
          resume = resolve;
        });
      }
      equal(value, 41);
      return Promise.resolve(42);
    },
  });
  try {
    throws(() => guest.call("main", host), errorCode("async_host_call"));
    const result = guest.callAsync("main", host);
    equal(calls, 1);
    await rejects(
      () => guest.callAsync("pure", null),
      errorCode("reentrant_call"),
    );
    throws(() => guest.dispose(), errorCode("reentrant_call"));
    resume(41);
    equal(await result, 83);
    equal(calls, 2);
    equal(await guest.callAsync("pure", null), 7);
    const cause = new Error("stopped");
    await rejects(() =>
      guest.callAsync(
        "main",
        guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: () => Promise.reject(cause),
        }),
      ), (error: unknown) => {
      ok(error instanceof GuestError);
      equal(error.code, "host_exception");
      equal(error.cause, cause);
      return true;
    });
    equal(await guest.callAsync("pure", null), 7);
  } finally {
    guest.dispose();
  }
});

Deno.test("numeric array capabilities copy packets and preserve guest allocations through suspension and growth", async () => {
  const bytes = await compile(`
entry const main = fn (host: Array F32 -> Array F32 ! {Foreign}) => do:
  let retained = @array.fill 70000 9.5
  use first <- host #[1.5, 2.5]
  use second <- host first
  return #[@array.get retained 69999, @array.get first 0, @array.get second 69999]
`);
  equal(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), [{
    module: "blot:host/1",
    name: "call_array_f32_array_f32",
    kind: "function",
  }]);
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      let calls = 0;
      const response = new Float32Array(70000).fill(6.25);
      const call = (packet: Float32Array) => {
        calls++;
        if (calls === 1) equal(packet, new Float32Array([1.5, 2.5]));
        else {
          equal(packet, response);
          packet[0] = 99; // Incoming arrays do not alias retained guest locals.
        }
        return response;
      };
      const host = asynchronous
        ? guest.capabilityAsync({
          parameter: "Array F32",
          result: "Array F32",
          call: async (packet) => {
            await Promise.resolve();
            return call(packet);
          },
        })
        : guest.capability({
          parameter: "Array F32",
          result: "Array F32",
          call,
        });
      const result = asynchronous
        ? await guest.callAsync("main", host)
        : guest.call("main", host);
      equal(result, new Float32Array([9.5, 6.25, 6.25]));
      equal(calls, 2);
      equal(response[0], 6.25);
      const bad = guest.capability({
        parameter: "Array F32",
        result: "Array F32",
        call: () => new Uint32Array(1) as unknown as Float32Array,
      });
      if (asynchronous) {
        await rejects(
          () => guest.callAsync("main", bad),
          errorCode("host_result"),
        );
      } else throws(() => guest.call("main", bad), errorCode("host_result"));
    } finally {
      guest.dispose();
    }
  }
});

Deno.test("array callback signatures support unsigned arrays and mixed scalar results", async () => {
  const bytes = await compile(`
entry const arrays = fn (host: Array U32 -> Array U32 ! {Foreign}) => do:
  use result <- host #[4_294_967_295]
  return result
entry const input = fn (host: Array U32 -> U32 ! {Foreign}) => do:
  use result <- host #[4_294_967_295]
  return result
entry const output = fn (host: U32 -> Array U32 ! {Foreign}) => do:
  use result <- host 4_294_967_295
  return result
`);
  const guest = await instantiateGuest(bytes, { asynchronous: true });
  try {
    const values = new Uint32Array([0xffffffff]);
    equal(
      await guest.callAsync(
        "arrays",
        guest.capabilityAsync({
          parameter: "Array U32",
          result: "Array U32",
          call: async (packet) => {
            equal(packet, values);
            return packet;
          },
        }),
      ),
      values,
    );
    equal(
      await guest.callAsync(
        "input",
        guest.capabilityAsync({
          parameter: "Array U32",
          result: "U32",
          call: async (packet) => packet[0],
        }),
      ),
      0xffffffff,
    );
    equal(
      await guest.callAsync(
        "output",
        guest.capabilityAsync({
          parameter: "U32",
          result: "Array U32",
          call: async (value) => new Uint32Array([value]),
        }),
      ),
      values,
    );
  } finally {
    guest.dispose();
  }
});
