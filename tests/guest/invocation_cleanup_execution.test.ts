import { deepEqual, equal, ok, rejects, throws } from "node:assert/strict";
import { GuestError } from "../../host/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

const source = `
io run (host: U32 -> U32 ! {Foreign}) : U32 ! {Foreign} => return do:
  let values: Array U32 = #[7, 11]
  use at <- host values[0]
  if at >= values.length:
    return @panic "outside the invocation"
  use result <- host values[at]
  return values[at] + result
`;

Deno.test("ABI 8 scalar invocations release scoped owners on normal return and trap", async () => {
  await compileAndRun(source, (guest, bytes) => {
    equal(guest.abi.version, 8);
    equal(guest.abi.invocationFinish, true);
    const exports = WebAssembly.Module.exports(new WebAssembly.Module(bytes));
    ok(!exports.some((entry) => entry.name === "blot:reset"));
    const trace: number[] = [];
    const capability = guest.capability({
      parameter: "U32",
      result: "U32",
      call: (value) => {
        trace.push(value);
        if (value === 7) return 1;
        return 13;
      },
    });
    equal(guest.call("run", capability), 24);
    deepEqual(trace, [7, 11]);
    equal(guest.lastReclaimedOwners(), 0);

    trace.length = 0;
    const trap = guest.capability({
      parameter: "U32",
      result: "U32",
      call: (value) => {
        trace.push(value);
        return 2;
      },
    });
    throws(() => guest.call("run", trap), WebAssembly.RuntimeError);
    deepEqual(trace, [7]);
    ok(guest.lastReclaimedOwners()! > 0);
  });
});

const jspi = WebAssembly as typeof WebAssembly & {
  Suspending?: unknown;
  promising?: unknown;
};
Deno.test({
  name:
    "ABI 8 preserves owners across JSPI suspension and releases them after rejection",
  ignore: typeof jspi.Suspending !== "function" ||
    typeof jspi.promising !== "function",
  async fn() {
    await compileAndRun(source, async (guest) => {
      const first = Promise.withResolvers<number>();
      const entered = Promise.withResolvers<void>();
      const trace: number[] = [];
      const capability = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          trace.push(value);
          if (value !== 7) return Promise.resolve(13);
          entered.resolve();
          return first.promise;
        },
      });
      const running = guest.callAsync("run", capability);
      try {
        await entered.promise;
        deepEqual(trace, [7]);
        equal(guest.lastReclaimedOwners(), undefined);
        await rejects(
          () => guest.callAsync("run", capability),
          (error) =>
            error instanceof GuestError && error.code === "reentrant_call",
        );
      } finally {
        first.resolve(1);
        equal(await running, 24);
      }
      deepEqual(trace, [7, 11]);
      equal(guest.lastReclaimedOwners(), 0);

      trace.length = 0;
      const failure = new Error("callback rejected");
      const failing = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          trace.push(value);
          if (value === 7) return Promise.resolve(1);
          return Promise.reject(failure);
        },
      });
      await rejects(
        () => guest.callAsync("run", failing),
        (error) =>
          error instanceof GuestError && error.code === "host_exception" &&
          error.cause === failure,
      );
      deepEqual(trace, [7, 11]);
      ok(guest.lastReclaimedOwners()! > 0);
    }, { asynchronous: true });
  },
});
