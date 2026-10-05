import { deepStrictEqual, ok, rejects, throws } from "node:assert/strict";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

function errorCode(code: GuestError["code"], cause?: unknown) {
  return (error: unknown) => {
    ok(error instanceof GuestError, String(error));
    equal(error.code, code);
    if (cause !== undefined) equal(error.cause, cause);
    return true;
  };
}

Deno.test("source Foreign callbacks use named, captured, higher-order and provider applications", async () => {
  await compileAndRun(
    `
effect Advance: U32 -> U32
const invoke = fn action => fn value => action value
const retain = fn action => fn value => invoke action value
entry const direct = fn (host: U32 -> U32 ! {Foreign}) => host 41
entry const named = fn (host: U32 -> U32 ! {Foreign}) => invoke host 41
entry const captured = fn (host: U32 -> U32 ! {Foreign}) => do:
  let callback = retain host
  use next <- callback 41
  return next
entry const provided = fn (host: U32 -> U32 ! {Foreign}) => do (@effect.provider Advance host):
  use next <- Advance 41
  return next
entry const ignored = fn (host: U32 -> U32 ! {Foreign}) => 42
entry const pure = fn () => 7
`,
    async (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      deepStrictEqual(WebAssembly.Module.imports(module), [{ module: "blot:host/1", name: "call_u32_u32", kind: "function" }]);
      equal(WebAssembly.Module.exports(module).some(item => item.name === "blot:reset"), false);
      let calls = 0;
      const host = guest.capability({ parameter: "U32", result: "U32", call: value => { calls++; equal(value, 41); return value + 1; } });
      for (let iteration = 0; iteration < 100; iteration++) {
        for (const name of ["direct", "named", "captured", "provided", "ignored"]) equal(guest.call(name, host), 42);
      }
      equal(calls, 400);
      const replacement = await instantiateGuest(bytes);
      try {
        throws(() => replacement.call("direct", host), errorCode("foreign_capability"));
        for (const invalid of [null, 0, {}, { ...host }, (value: number) => value]) throws(() => guest.call("direct", invalid), errorCode("invalid_capability"));
        const wrong = guest.capability({ parameter: "F32", result: "U32", call: () => 42 });
        throws(() => guest.call("direct", wrong), errorCode("capability_signature"));
        const busy = guest.capability({ parameter: "U32", result: "U32", call: value => {
          throws(() => guest.call("pure", null), errorCode("reentrant_call"));
          throws(() => guest.dispose(), errorCode("reentrant_call"));
          return value + 1;
        } });
        equal(guest.call("captured", busy), 42);
        const stale = replacement.capability({ parameter: "U32", result: "U32", call: () => 42 });
        replacement.dispose();
        throws(() => guest.call("direct", stale), errorCode("stale_capability"));
        equal(guest.call("direct", host), 42);
      } finally { replacement.dispose(); }
    },
  );
});

Deno.test("source Foreign scalar entries recover after repeated host exceptions, bad results and Wasm panics", async () => {
  await compileAndRun(
    `
entry const main = fn (host: U32 -> U32 ! {Foreign}) => do:
  use next <- host 41
  if @u32.eq next 0:
    return @panic "host requested panic"
  return next
entry const pure = fn () => 7
`,
    (guest) => {
      const cause = new Error("host failed");
      const failing = guest.capability({ parameter: "U32", result: "U32", call: () => { throw cause; } });
      const bad = guest.capability({ parameter: "U32", result: "U32", call: () => -1 });
      const panic = guest.capability({ parameter: "U32", result: "U32", call: () => 0 });
      const good = guest.capability({ parameter: "U32", result: "U32", call: value => value + 1 });
      for (let iteration = 0; iteration < 100; iteration++) {
        throws(() => guest.call("main", failing), errorCode("host_exception", cause));
        throws(() => guest.call("main", bad), errorCode("host_result"));
        throws(() => guest.call("main", panic), WebAssembly.RuntimeError);
        equal(guest.call("pure", null), 7);
        equal(guest.call("main", good), 42);
      }
    },
  );
});

Deno.test("source Foreign trampolines preserve F32, mixed scalar, Bool and Unit signatures", async () => {
  await compileAndRun(
    `
entry const floating = fn (host: F32 -> F32 ! {Foreign}) => host 1.25
entry const mixed = fn (host: U32 -> F32 ! {Foreign}) => host 41
entry const boolean = fn (host: Bool -> Bool ! {Foreign}) => host #True
entry const unit = fn (host: Unit -> Unit ! {Foreign}) => host ()
`,
    (guest) => {
      const floating = guest.capability({ parameter: "F32", result: "F32", call: value => { equal(value, 1.25); return value + 3.5; } });
      const mixed = guest.capability({ parameter: "U32", result: "F32", call: value => { equal(value, 41); return 4.75; } });
      const boolean = guest.capability({ parameter: "Bool", result: "Bool", call: value => { equal(value, true); return false; } });
      const unit = guest.capability({ parameter: "Unit", result: "Unit", call: value => { equal(value, null); return null; } });
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("floating", floating), 4.75);
        equal(guest.call("mixed", mixed), 4.75);
        equal(guest.call("boolean", boolean), false);
        equal(guest.call("unit", unit), null);
      }
    },
  );
});

Deno.test("source Foreign numeric-array callbacks copy retained inputs and returned packets across growth and failure", async () => {
  await compileAndRun(
    `
const invoke = fn action => fn value => action value
entry const main = fn (host: Array F32 -> Array F32 ! {Foreign}) => do:
  let retained = @array.fill 70000 9.5
  use first <- invoke host #[1.5, 2.5]
  use second <- invoke host first
  return #[@array.get retained 69999, @array.get first 0, @array.get second 69999]
`,
    (guest, bytes) => {
      deepStrictEqual(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), [{ module: "blot:host/1", name: "call_array_f32_array_f32", kind: "function" }]);
      let calls = 0;
      const response = new Float32Array(70000).fill(6.25);
      const packets: Float32Array[] = [];
      const host = guest.capability({ parameter: "Array F32", result: "Array F32", call: packet => {
        if (calls++ % 2 === 0) deepStrictEqual(packet, Float32Array.of(1.5, 2.5));
        else deepStrictEqual(packet, response);
        packets.push(packet);
        packet[0] = 99;
        return response;
      } });
      for (let iteration = 0; iteration < 10; iteration++) {
        const result = guest.call("main", host) as Float32Array;
        deepStrictEqual(result, Float32Array.of(9.5, 6.25, 6.25));
        result[0] = 100;
        equal(response[0], 6.25);
      }
      equal(calls, 20);
      equal(packets[0][0], 99);
      const cause = new Error("array host failed");
      const failing = guest.capability({ parameter: "Array F32", result: "Array F32", call: () => { throw cause; } });
      for (let iteration = 0; iteration < 10; iteration++) {
        throws(() => guest.call("main", failing), errorCode("host_exception", cause));
        deepStrictEqual(guest.call("main", host), Float32Array.of(9.5, 6.25, 6.25));
      }
      equal(response[0], 6.25);
    },
  );
});

const jspi = WebAssembly as unknown as { Suspending?: unknown; promising?: unknown };
Deno.test({
  name: "source Foreign async callbacks preserve suspended locals and recover after rejection",
  ignore: typeof jspi.Suspending !== "function" || typeof jspi.promising !== "function",
  fn: async () => {
    await compileAndRun(
      `
entry const main = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- host 40
  use second <- host first
  return @u32.add first second
entry const pure = fn () => 7
`,
      async (guest) => {
        let resume!: (value: number) => void;
        let calls = 0;
        const host = guest.capabilityAsync({ parameter: "U32", result: "U32", call: value => {
          calls++;
          if (calls === 1) {
            equal(value, 40);
            return new Promise<number>(resolve => { resume = resolve; });
          }
          equal(value, 41);
          return Promise.resolve(42);
        } });
        const pending = guest.callAsync("main", host);
        equal(calls, 1);
        await rejects(() => guest.callAsync("pure", null), errorCode("reentrant_call"));
        throws(() => guest.dispose(), errorCode("reentrant_call"));
        resume(41);
        equal(await pending, 83);
        equal(calls, 2);
        const cause = new Error("async host failed");
        const failing = guest.capabilityAsync({ parameter: "U32", result: "U32", call: () => Promise.reject(cause) });
        await rejects(() => guest.callAsync("main", failing), errorCode("host_exception", cause));
        equal(await guest.callAsync("pure", null), 7);
        const good = guest.capabilityAsync({ parameter: "U32", result: "U32", call: value => Promise.resolve(value + 1) });
        equal(await guest.callAsync("main", good), 83);
      },
      { asynchronous: true },
    );
  },
});
