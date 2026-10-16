import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  GuestError,
  instantiateGuest,
  readGuestAbi,
} from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `entry const answer: once (U32 -> U32) = fn value => value
entry const failure: once (U32 -> U32) = fn value => @panic "once failure"
entry const host: once ((U32 -> U32 ! {Foreign}) -> U32 ! {Foreign}) = fn callback => callback 7
entry const ordinary = fn (value: U32) => value
`;
const onceError = (error: unknown) =>
  error instanceof GuestError && error.code === "once_reused";
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`public once exports consume native and guest invocation authority (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-once-entry-" });
    const entry = `${directory}/main.blot`;
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const compiler = await createZigProjectCompiler(options);
    let restarted: typeof compiler | undefined;
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const module = new WebAssembly.Module(first.bytes);
      const abi = readGuestAbi(module);
      for (const fn of abi.functions) {
        if (fn.name === "ordinary") assert.equal(fn.multiplicity, undefined);
        else assert.equal(fn.multiplicity, "once");
      }
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(module, { asynchronous });
        const invoke = async (name: string, value: unknown) => {
          if (asynchronous) return await guest.callAsync(name, value);
          return guest.call(name, value);
        };
        try {
          await assert.rejects(
            () => invoke("answer", -1),
            (error: unknown) =>
              error instanceof GuestError && error.code === "invalid_argument",
          );
          assert.equal(await invoke("answer", 42), 42);
          await assert.rejects(() => invoke("answer", 9), onceError);
          await assert.rejects(() => invoke("failure", 0));
          await assert.rejects(() => invoke("failure", 0), onceError);
          const capability = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => value + 1,
          });
          assert.equal(await invoke("host", capability), 8);
          await assert.rejects(() => invoke("host", capability), onceError);
          assert.equal(await invoke("ordinary", 1), 1);
          assert.equal(await invoke("ordinary", 2), 2);
        } finally {
          guest.dispose();
        }
        const failed = await instantiateGuest(module, { asynchronous });
        try {
          const rejected = failed.capability({
            parameter: "U32",
            result: "U32",
            call: () => {
              throw new Error("host failure");
            },
          });
          if (asynchronous) {
            await assert.rejects(failed.callAsync("host", rejected));
            await assert.rejects(failed.callAsync("host", rejected), onceError);
          } else {
            assert.throws(() => failed.call("host", rejected));
            assert.throws(() => failed.call("host", rejected), onceError);
          }
        } finally {
          failed.dispose();
        }
      }
      const pendingGuest = await instantiateGuest(module, {
        asynchronous: true,
      });
      try {
        let resumeGuest!: (value: number) => void;
        const host = pendingGuest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: () =>
            new Promise<number>((resolve) => {
              resumeGuest = resolve;
            }),
        });
        const pending = pendingGuest.callAsync("host", host);
        await assert.rejects(
          pendingGuest.callAsync("host", host),
          (error: unknown) =>
            error instanceof GuestError && error.code === "reentrant_call",
        );
        resumeGuest(8);
        assert.equal(await pending, 8);
        await assert.rejects(pendingGuest.callAsync("host", host), onceError);
      } finally {
        pendingGuest.dispose();
      }
      const rejectedGuest = await instantiateGuest(module, {
        asynchronous: true,
      });
      try {
        const host = rejectedGuest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: () => Promise.reject(new Error("settlement failure")),
        });
        await assert.rejects(rejectedGuest.callAsync("host", host));
        await assert.rejects(rejectedGuest.callAsync("host", host), onceError);
      } finally {
        rejectedGuest.dispose();
      }
      const raw = new WebAssembly.Instance(module, {
        "blot:host/1": {
          "call_u32_u32": (_reference: unknown, value: number) => value + 1,
        },
      });
      const run = raw.exports.answer as (value: number) => number;
      const failure = raw.exports.failure as (value: number) => number;
      const host = raw.exports.host as (value: object) => number;
      const ordinary = raw.exports.ordinary as (value: number) => number;
      assert.equal(run(42), 42);
      assert.throws(() => run(9), WebAssembly.RuntimeError);
      assert.throws(() => failure(0), WebAssembly.RuntimeError);
      assert.throws(() => failure(0), WebAssembly.RuntimeError);
      assert.equal(host({}), 8);
      assert.throws(() => host({}), WebAssembly.RuntimeError);
      assert.equal(ordinary(1), 1);
      assert.equal(ordinary(2), 2);
      type Jspi = {
        Suspending: new (
          fn: (reference: unknown, value: number) => Promise<number>,
        ) => WebAssembly.ImportValue;
        promising: (fn: CallableFunction) => (value: object) => Promise<number>;
      };
      const integration = WebAssembly as unknown as Jspi;
      let resume!: (value: number) => void;
      const suspended = new WebAssembly.Instance(module, {
        "blot:host/1": {
          "call_u32_u32": new integration.Suspending((_reference, value) =>
            new Promise<number>((resolve) => {
              assert.equal(value, 7);
              resume = resolve;
            })
          ),
        },
      });
      const pending = integration.promising(
        suspended.exports.host as CallableFunction,
      )({});
      assert.throws(
        () => (suspended.exports.host as (value: object) => number)({}),
        WebAssembly.RuntimeError,
      );
      resume(8);
      assert.equal(await pending, 8);
      assert.throws(
        () => (suspended.exports.host as (value: object) => number)({}),
        WebAssembly.RuntimeError,
      );
      const rejectedAliases = await compiler.build({
        sources: {
          [entry]:
            "const value: once (U32 -> U32) = fn input => input\nentry const first = value\nentry const second = value\n",
        },
      });
      assert(!rejectedAliases.success);
      assert(
        rejectedAliases.diagnostics.some((diagnostic) =>
          diagnostic.code === "duplicate_owner"
        ),
      );
      const restored = await compiler.build({ sources: { [entry]: source } });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, first.bytes);
      const checkpoint = await compiler.exportCheckpoint();
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, first.bytes);
      restarted = await createZigProjectCompiler({ ...options, checkpoint });
      const recovered = await restarted.build({ sources: { [entry]: source } });
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, first.bytes);
    } finally {
      await restarted?.close();
      await compiler.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
