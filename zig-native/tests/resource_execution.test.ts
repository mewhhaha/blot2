import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { ResourceJournal } from "../../compiler/resource_journal.ts";
import {
  GuestError,
  instantiateGuest,
  readGuestAbi,
} from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @u32.add (@usage.read loan) (host ()))
entry const float = fn () => @resource.scope (fn () => 1.5) (fn owner => ()) (fn loan => @usage.read loan)
entry const unit = fn () => @resource.scope (fn () => ()) (fn owner => ()) (fn loan => @usage.read loan)
entry const truth = fn () => @resource.scope (fn () => #True) (fn owner => ()) (fn loan => @usage.read loan)
entry const nested = fn (host: Unit -> U32 ! {Foreign}) => @resource.scope (fn () => 9) (fn owner => ()) (fn outer => @resource.scope (fn () => 7) (fn owner => ()) (fn inner => @u32.add (@usage.read outer) (@u32.add (@usage.read inner) (host ()))))
entry const failed_cleanup = fn (host: Unit -> U32 ! {Foreign}) => @resource.scope (fn () => 9) (fn owner => @panic "cleanup") (fn loan => host ())
entry const surviving = fn () => do:
  use values <- @resource.scope (fn () => 9) (fn owner => ()) (fn loan => #[@usage.read loan, @u32.add (@usage.read loan) 1, @u32.add (@usage.read loan) 2])
  for index in 0..128:
    use other <- @resource.scope (fn () => 7) (fn owner => ()) (fn loan => @usage.read loan)
  return values
entry const sequential = fn () => do:
  let count = 0
  for index in 0..10000:
    use value <- @resource.scope (fn () => 7) (fn owner => ()) (fn loan => @usage.read loan)
    count := @u32.add self value
  return count
entry const finite_cleanup = fn () => @resource.scope (fn () => 9) (fn owner => do:
  for index in 0..3:
    for inner in 1..4:
      let value = @u32.add index inner
  return ()) (fn loan => @usage.read loan)
entry const finite_cleanup_trap = fn () => @resource.scope (fn () => 9) (fn owner => do:
  for index in 0..3:
    if @u32.eq index 2:
      let value = @panic "finite cleanup"
  return ()) (fn loan => @usage.read loan)
entry const empty_cleanup = fn () => @resource.scope (fn () => 9) (fn owner => do:
  for index in 4..2:
    let value = @panic "empty cleanup must not run"
  return ()) (fn loan => @usage.read loan)
entry const memory = fn () -> Array U32 => #[]
`;
Deno.test("resource scalar scope executes finite cleanup across sync JSPI failures and retained restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-resource-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    const first = await compiler.build({ sources: { [entry]: source } });
    assert(first.success, JSON.stringify(first));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(first.bytes, { asynchronous });
      try {
        assert.equal(guest.abi.version, 4);
        assert.equal(guest.abi.resourceAdapterCount, 2);
        let calls = 0;
        let host = guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => {
            calls++;
            return 7;
          },
        });
        if (asynchronous) {
          host = guest.capabilityAsync({
            parameter: "Unit",
            result: "U32",
            call: async () => {
              calls++;
              await Promise.resolve();
              return 7;
            },
          });
        }
        const invoke = async (name: string, input: typeof host | null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        assert.equal(await invoke("answer", host), 16);
        assert.equal(await invoke("finite_cleanup", null), 9);
        assert.equal(await invoke("empty_cleanup", null), 9);
        await assert.rejects(
          () => invoke("finite_cleanup_trap", null),
          WebAssembly.RuntimeError,
        );
        assert.equal(await invoke("finite_cleanup", null), 9);
        assert.equal(await invoke("float", null), 1.5);
        assert.equal(await invoke("unit", null), null);
        assert.equal(await invoke("truth", null), true);
        const values = await invoke("surviving", null);
        assert(values instanceof Uint32Array);
        assert.deepEqual([...values], [9, 10, 11]);
        assert.equal(await invoke("sequential", null), 70000);
        assert.deepEqual([...values], [9, 10, 11]);
        const warmed = guest.memoryBytes();
        for (let index = 0; index < 100; index++) {
          assert.deepEqual(await invoke("surviving", null), values);
        }
        assert(guest.memoryBytes() <= warmed + 65536);
        assert.equal(await invoke("nested", host), 23);
        await assert.rejects(
          () => invoke("failed_cleanup", host),
          WebAssembly.RuntimeError,
        );
        assert.equal(await invoke("answer", host), 16);
        let failed = guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => {
            throw new Error("host failure");
          },
        });
        if (asynchronous) {
          failed = guest.capabilityAsync({
            parameter: "Unit",
            result: "U32",
            call: async () => {
              await Promise.resolve();
              throw new Error("host failure");
            },
          });
        }
        await assert.rejects(() => invoke("nested", failed));
        await assert.rejects(
          () => invoke("failed_cleanup", failed),
          (error) =>
            error instanceof GuestError && error.code === "host_exception" &&
            error.cause instanceof Error &&
            error.cause.message === "host failure",
        );
        assert.equal(await invoke("answer", host), 16);
        assert.equal(calls, 5);
      } finally {
        guest.dispose();
      }
    }
    const bad = await compiler.build({
      sources: {
        [entry]: source.replace(
          "(fn loan => @usage.read loan)",
          "(fn loan => loan)",
        ),
      },
    });
    assert(!bad.success);
    assert(
      bad.diagnostics.some((d) => d.code === "borrow_escape"),
      JSON.stringify(bad),
    );
    const recovered = await compiler.build({ sources: { [entry]: source } });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    const restarted = await createZigProjectCompiler(options);
    try {
      const resumed = await restarted.build({ sources: { [entry]: source } });
      assert(resumed.success, JSON.stringify(resumed));
      assert.deepEqual(resumed.bytes, first.bytes);
    } finally {
      await restarted.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

const recoverySource = `
entry const normal = fn (host: Unit -> U32 ! {Foreign}) => do:
  let captured = @array.fill 1024 41
  use value <- @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @u32.add (@usage.read loan) (@u32.add captured[0] (host ())))
  return value
entry const early = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => do:
  return @usage.read loan
)
entry const branch = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => if @u32.eq (@usage.read loan) 9 then @usage.read loan else 0)
entry const break_exit = fn () => do:
  let result = 0
  for ever:
    use value <- @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @usage.read loan)
    result := value
    break
  return result
entry const trapped = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @u32.div (@usage.read loan) 0)
entry const acquire_failed = fn () => @resource.scope (fn () -> unique U32 => @panic "acquire") (fn owner => ()) (fn loan => @usage.read loan)
entry const cleanup_failed = fn (host: Unit -> U32 ! {Foreign}) => @resource.scope (fn () => 9) (fn owner => ()) (fn outer => @resource.scope (fn () => 7) (fn owner => @panic "cleanup") (fn inner => host ()))
entry const memory = fn () -> Array U32 => #[]
`;
Deno.test("resource typed journal drains compiled traps and suspended failures with flat roots and memory in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-resource-recovery-",
  });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      let bytes: Uint8Array<ArrayBuffer>;
      try {
        const built = await compiler.build({
          sources: { [entry]: recoverySource },
        });
        assert(built.success, JSON.stringify(built));
        bytes = built.bytes;
      } finally {
        await compiler.dispose();
      }
      const module = new WebAssembly.Module(bytes);
      const abi = readGuestAbi(module);
      assert.equal(abi.version, 4);
      for (const asynchronous of [false, true]) {
        const jspi = WebAssembly as unknown as {
          Suspending: new (
            fn: (reference: unknown, unit: number) => Promise<number>,
          ) => WebAssembly.ImportValue;
          promising(
            fn: CallableFunction,
          ): (...args: unknown[]) => Promise<number>;
        };
        let failure = false;
        let settle: ((value: number) => void) | undefined;
        let reject: ((error: Error) => void) | undefined;
        let suspended = false;
        const host = () => {
          if (failure) throw new Error("host failure");
          return 7;
        };
        let hostImport: WebAssembly.ImportValue = host;
        if (asynchronous) {
          hostImport = new jspi.Suspending(async () => {
            if (suspended) {
              return await new Promise<number>((resolve, decline) => {
                settle = resolve;
                reject = decline;
              });
            }
            await Promise.resolve();
            return host();
          });
        }
        const raw = new WebAssembly.Instance(module, {
          "blot:host/1": { call_unit_u32: hostImport },
          "blot:resource/1": {
            reserve: () => journal.reserve(),
            register: (
              token: number,
              adapter: number,
              payload: number,
              callable: number,
              provider: number,
            ) =>
              journal.register(
                token >>> 0,
                adapter,
                payload >>> 0,
                callable >>> 0,
                provider >>> 0,
              ),
            release: (token: number) => journal.release(token >>> 0),
          },
        }).exports;
        const trace: string[] = [];
        const journal = new ResourceJournal(
          Array.from({ length: abi.resourceAdapterCount! }, (_, index) => ({
            cleanup(payload, callable, provider) {
              trace.push(`cleanup:${payload}`);
              (raw[`blot:resource_cleanup/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
            drop(payload, callable, provider) {
              trace.push(`drop:${payload}`);
              (raw[`blot:resource_drop/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
          })),
        );
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        const memory = raw["blot:memory"] as WebAssembly.Memory;
        const begin = () => {
          (raw["blot:ownership_enter"] as CallableFunction)();
          journal.begin();
          trace.length = 0;
        };
        const finish = (outcome: number) => {
          let cleanupError: unknown;
          try {
            journal.finish();
          } catch (cause) {
            cleanupError = cause;
          }
          (raw["blot:ownership_leave"] as CallableFunction)(outcome);
          (raw["blot:reset"] as CallableFunction)(0);
          assert.equal(count("roots"), 0);
          assert.equal(count("leases"), 0);
          assert.equal(count("host_refs"), 0);
          return cleanupError;
        };
        const invoke = (name: string, ...args: unknown[]) => {
          if (asynchronous) {
            return jspi.promising(raw[name] as CallableFunction)(...args);
          }
          return Promise.resolve().then(() =>
            (raw[name] as CallableFunction)(...args)
          );
        };
        begin();
        assert.equal(await invoke("normal", {}), 57);
        assert.equal(finish(0), undefined);
        assert.deepEqual(trace, ["cleanup:9", "drop:9"]);
        const warmed = memory.buffer.byteLength;
        for (const name of ["early", "branch", "break_exit"]) {
          begin();
          assert.equal(await invoke(name), 9);
          assert.equal(finish(0), undefined);
          assert.deepEqual(trace, ["cleanup:9", "drop:9"]);
        }
        for (let index = 0; index < 128; index++) {
          for (
            const name of [
              "trapped",
              "acquire_failed",
              "cleanup_failed",
              "normal",
            ]
          ) {
            begin();
            failure = name === "normal";
            await assert.rejects(() => invoke(name, {}));
            const cleanupError = finish(1);
            if (name === "acquire_failed") assert.deepEqual(trace, []);
            else if (name === "cleanup_failed") {
              assert.deepEqual(trace, [
                "cleanup:7",
                "drop:7",
                "cleanup:9",
                "drop:9",
              ]);
              assert.equal(
                cleanupError,
                undefined,
                "the failed cleanup is never retried",
              );
            } else assert.deepEqual(trace, ["cleanup:9", "drop:9"]);
            failure = false;
            begin();
            assert.equal(await invoke("normal", {}), 57);
            assert.equal(finish(0), undefined);
            assert.equal(memory.buffer.byteLength, warmed);
          }
        }
        if (asynchronous) {
          suspended = true;
          for (const rejectHost of [false, true]) {
            begin();
            const pending = invoke("normal", {});
            assert(count("roots") > 0);
            assert(count("leases") > 0);
            assert.equal(count("host_refs"), 1);
            assert.deepEqual(trace, [], "cleanup waits for host settlement");
            if (rejectHost) {
              reject!(new Error("suspended host failure"));
              await assert.rejects(pending, /suspended host failure/);
              assert.equal(finish(1), undefined);
            } else {
              settle!(7);
              assert.equal(await pending, 57);
              assert.equal(finish(0), undefined);
            }
            assert.deepEqual(trace, ["cleanup:9", "drop:9"]);
          }
        }
        (raw["blot:ownership_leave"] as CallableFunction)(2);
      }
      const guest = await instantiateGuest(module, { asynchronous: true });
      try {
        let resolve: ((value: number) => void) | undefined;
        const host = guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: () =>
            new Promise<number>((settle) => {
              resolve = settle;
            }),
        });
        const pending = guest.callAsync("normal", host);
        assert.throws(
          () => guest.dispose(),
          (error) =>
            error instanceof GuestError && error.code === "reentrant_call",
        );
        await assert.rejects(
          () => guest.callAsync("normal", host),
          (error) =>
            error instanceof GuestError && error.code === "reentrant_call",
        );
        resolve!(7);
        assert.equal(await pending, 57);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("resource owned cleanup contracts survive imported bodies portable checkpoint and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-resource-import-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/scope.blot`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  const sources = {
    [entry]:
      `import {run} from "./scope"\nentry const answer = fn () => run ()\n`,
    [dependency]:
      `const run = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @usage.read loan)\n`,
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    const first = await compiler.build({ sources });
    assert(first.success, JSON.stringify(first));
    const checkpoint = await compiler.exportCheckpoint();
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(first.bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", null), 9);
        } else assert.equal(guest.call("answer", null), 9);
      } finally {
        guest.dispose();
      }
    }
    const failed = await compiler.build({
      sources: {
        ...sources,
        [dependency]: sources[dependency].replace(
          "(fn owner => ())",
          "(fn owner => (fn () => ()) ())",
        ),
      },
    });
    assert(!failed.success);
    assert(
      failed.diagnostics.some((d) => d.code === "cleanup_not_safe"),
      JSON.stringify(failed),
    );
    const recovered = await compiler.build({ sources });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    for (const useCheckpoint of [false, true]) {
      const replayOptions = {
        ...options,
        checkpoint: undefined as Uint8Array<ArrayBuffer> | undefined,
      };
      if (useCheckpoint) replayOptions.checkpoint = checkpoint;
      const replay = await createZigProjectCompiler(replayOptions);
      try {
        const resumed = await replay.build({ sources });
        assert(resumed.success, JSON.stringify(resumed));
        assert.deepEqual(resumed.bytes, first.bytes);
      } finally {
        await replay.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
