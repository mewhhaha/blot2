import { strict as assert } from "node:assert";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";
import { ResourceJournal } from "../../compiler/resource_journal.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
const identity = fn value => do:
  return value
entry const ordinary = fn (value: U32) => identity value
const make = fn () -> unique U32 ! {Foreign} => @resource.acquire (fn () => 9) (fn owner => ())
const forward = fn (owner: unique U32) => owner
entry const run = fn () => do:
  use owner <- make ()
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use @resource.release (forward owner)
  return value
entry const generic = fn () => do:
  use owner <- make ()
  let shared = @usage.share owner
  let moved = identity shared
  return @usage.read moved
entry const shared = fn () => do:
  use owner <- make ()
  let value = @usage.share owner
  return @u32.add (@usage.read value) (@usage.read value)
entry const captured = fn () => do:
  use owner <- make ()
  let transfer: once (Unit -> unique U32) = fn () => owner
  let moved = transfer ()
  use value <- @usage.borrow moved (fn loan => @usage.read loan)
  use @resource.release moved
  return value
entry const array = fn () => do:
  use owner <- @resource.acquire (fn () => #[9, 10, 11]) (fn owner => ())
  use value <- @usage.borrow owner (fn loan => @usage.length loan)
  use @resource.release owner
  return value
entry const listed = fn () => do:
  use owner <- @resource.acquire (fn () => [1.5, 2.5, 3.5]) (fn owner => ())
  let shared = @usage.share owner
  return @usage.length shared
entry const unit = fn () => do:
  use owner <- @resource.acquire (fn () => ()) (fn owner => ())
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use @resource.release owner
  return value
entry const boolean = fn () => do:
  use owner <- @resource.acquire (fn () => #True) (fn owner => ())
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use @resource.release owner
  return value
entry const result = fn () => do:
  use owner <- @resource.acquire (fn () => #[9, 10, 11]) (fn owner => ())
  use value <- @usage.borrow owner (fn loan => #[@usage.length loan, 9])
  use @resource.release owner
  return value
entry const floating = fn () => do:
  use owner <- @resource.acquire (fn () => 1.5) (fn owner => ())
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use @resource.release owner
  return value
entry const failed = fn () => do:
  use owner <- @resource.acquire (fn () => 9) (fn owner => @panic "cleanup")
  use @resource.release owner
  return 9
entry const scalar_input = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)
entry const array_input = fn (owner: unique (Array U32)) => @usage.borrow owner (fn loan => @usage.length loan)
entry const float_input = fn (owner: shared F32) => @usage.read owner
entry const surviving = fn () => do:
  use owner <- do:
    use nested <- make ()
    return nested
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use @resource.release owner
  return value
entry const captured_obligation = fn () => do:
  use older <- make ()
  let shared = @usage.share older
  use owner <- @resource.acquire (fn () => 10) (fn owner => do:
    let observed = @usage.read shared
    return ())
  use @resource.release owner
  return 10
entry const host = fn (callback: Unit -> U32 ! {Foreign}) => do:
  use owner <- make ()
  use value <- @usage.borrow owner (fn loan => @usage.read loan)
  use answer <- callback ()
  use @resource.release owner
  return @u32.add value answer
entry const acquired_twice = fn () => do:
  use owner <- @resource.acquire (fn () => make ()) (fn owner => ())
  use @resource.release owner
  return 9
entry const acquisition_failed = fn () => do:
  use owner <- @resource.acquire (fn () -> unique U32 => @panic "acquire") (fn owner => @panic "should not clean")
  return 9
entry const looped = fn () => do:
  for index in 0..5000:
    use owner <- make ()
  return 5000
entry const broken = fn () => do:
  for ever:
    use owner <- make ()
    break
  return 9
entry const branched = fn (host: Unit -> U32 ! {Foreign}) => do:
  if #True:
    use owner <- @resource.acquire (fn () => 9) (fn owner => @panic "cleanup")
  return host ()
entry const merged = fn (choose: Bool) => do:
  let initial_left: unique (Array U32) = #[1]
  let initial_right: unique (Array U32) = #[1, 2]
  let left = @usage.share initial_left
  let right = @usage.share initial_right
  if choose:
    use first <- @resource.acquire (fn () => #[1, 2]) (fn owner => ())
    left := @usage.share first
    use second <- @resource.acquire (fn () => #[1, 2, 3]) (fn owner => ())
    right := @usage.share second
  return @u32.add (@usage.length left) (@usage.length right)
entry const unused = fn (host: Unit -> U32 ! {Foreign}) => do:
  use value <- do:
    use owner <- @resource.acquire (fn () => 9) (fn owner => @panic "cleanup")
    return 9
  return host ()
`;
Deno.test("resource transfer keeps acquired boxes through source moves sharing captures and explicit release", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-transfer-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      try {
        assert.equal(guest.abi.version, 5);
        const invoke = async (name: string) => {
          if (asynchronous) return await guest.callAsync(name, null);
          return guest.call(name, null);
        };
        assert.equal(await invoke("run"), 9);
        assert.equal(await invoke("generic"), 9);
        assert.equal(await invoke("shared"), 18);
        assert.equal(await invoke("captured"), 9);
        assert.equal(await invoke("surviving"), 9);
        assert.equal(await invoke("captured_obligation"), 10);
        const input = async (name: string, value: unknown) => {
          if (asynchronous) return await guest.callAsync(name, value);
          return guest.call(name, value);
        };
        assert.equal(await input("ordinary", 19), 19);
        assert.equal(await input("merged", true), 5);
        assert.equal(await input("merged", false), 3);
        assert.equal(await invoke("looped"), 5000);
        assert.equal(await invoke("broken"), 9);
        assert.equal(await input("scalar_input", 19), 19);
        assert.equal(await input("array_input", new Uint32Array([1, 2, 3])), 3);
        assert.equal(await input("float_input", 2.5), 2.5);
        assert.equal(await invoke("array"), 3);
        assert.equal(await invoke("listed"), 3);
        assert.equal(await invoke("unit"), null);
        assert.equal(await invoke("boolean"), true);
        assert.deepEqual(await invoke("result"), new Uint32Array([3, 9]));
        assert.equal(await invoke("floating"), 1.5);
        await assert.rejects(invoke("failed"), WebAssembly.RuntimeError);
        await assert.rejects(
          invoke("acquired_twice"),
          WebAssembly.RuntimeError,
        );
        assert.equal(await invoke("run"), 9);
        let calls = 0;
        const host = guest.capability({
          parameter: "Unit",
          result: "U32",
          call: () => ++calls,
        });
        if (asynchronous) {
          await assert.rejects(
            guest.callAsync("branched", host),
            WebAssembly.RuntimeError,
          );
        } else {assert.throws(() =>
            guest.call("branched", host), WebAssembly.RuntimeError);}
        assert.equal(calls, 0);
        if (asynchronous) {
          await assert.rejects(
            guest.callAsync("unused", host),
            WebAssembly.RuntimeError,
          );
        } else {assert.throws(() =>
            guest.call("unused", host), WebAssembly.RuntimeError);}
        assert.equal(calls, 0);
        assert.equal(await invoke("run"), 9);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    compiler.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("resource transfer retirement preserves roots through cancellation cleanup failures and warmed recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-transfer-raw-" });
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
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        bytes = result.bytes;
      } finally {
        await compiler.dispose();
      }
      const module = new WebAssembly.Module(bytes);
      assert.equal(readGuestAbi(module).version, 5);
      for (const asynchronous of [false, true]) {
        const jspi = WebAssembly as unknown as {
          Suspending: new (
            callback: () => Promise<number>,
          ) => WebAssembly.ImportValue;
          promising(
            callback: CallableFunction,
          ): (...args: unknown[]) => Promise<number>;
        };
        let failHost = false;
        let suspended = false;
        let settle: ((value: number) => void) | undefined;
        let cancel: ((cause: Error) => void) | undefined;
        const host = () => {
          if (failHost) throw new Error("host rejected");
          return 7;
        };
        let imported: WebAssembly.ImportValue = host;
        if (asynchronous) {
          imported = new jspi.Suspending(async () => {
            if (suspended) {
              return await new Promise<number>((resolve, reject) => {
                settle = resolve;
                cancel = reject;
              });
            }
            return host();
          });
        }
        const raw = new WebAssembly.Instance(module, {
          "blot:host/1": { call_unit_u32: imported },
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
          "blot:resource/2": {
            register_owned(
              token: number,
              adapter: number,
              payload: number,
              callable: number,
              provider: number,
              owner: number,
            ) {
              const words = new Uint32Array(memory.buffer);
              const slot = (owner >>> 0) / 4;
              assert.equal(words[slot + 1], 0);
              assert.equal(words[slot - 7], 8);
              journal.registerOwned(
                token >>> 0,
                adapter,
                payload >>> 0,
                callable >>> 0,
                provider >>> 0,
                owner >>> 0,
              );
              words[slot + 1] = token;
              words[slot - 6] |= 2048;
            },
            retire: (token: number) => journal.retire(token >>> 0),
            drain: () => journal.drain(),
          },
        }).exports;
        const memory = raw["blot:memory"] as WebAssembly.Memory;
        const trace: string[] = [];
        const journal = new ResourceJournal(
          Array.from({ length: 3 }, (_, index) => ({
            cleanup(payload: number, callable: number, provider: number) {
              trace.push(`cleanup:${index}`);
              (raw[`blot:resource_cleanup/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
            drop(payload: number, callable: number, provider: number) {
              trace.push(`drop:${index}`);
              (raw[`blot:resource_drop/${index}`] as CallableFunction)(
                payload,
                callable,
                provider,
              );
            },
          })),
          (owner, token) => {
            const words = new Uint32Array(memory.buffer);
            assert.equal(words[owner / 4 + 1], token);
            words[owner / 4 + 1] = 0;
          },
        );
        const count = (name: string) =>
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
        const begin = () => {
          trace.length = 0;
          (raw["blot:ownership_enter"] as CallableFunction)();
          journal.begin();
        };
        const finish = (outcome: number) => {
          try {
            journal.finish();
          } finally {
            (raw["blot:ownership_leave"] as CallableFunction)(outcome);
            (raw["blot:reset"] as CallableFunction)(0);
          }
          for (const name of ["roots", "leases", "host_refs"]) {
            assert.equal(count(name), 0, name);
          }
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
        assert.equal(await invoke("array"), 3);
        finish(0);
        const warmed = memory.buffer.byteLength;
        for (let index = 0; index < 128; index++) {
          for (
            const name of [
              "run",
              "shared",
              "captured",
              "surviving",
              "array",
              "host",
              "failed",
              "acquisition_failed",
              "captured_obligation",
            ]
          ) {
            begin();
            failHost = name === "host";
            let outcome = 0;
            try {
              const value = await invoke(name, {});
              let expected = 9;
              if (name === "array") expected = 3;
              if (name === "shared") expected = 18;
              if (name === "captured_obligation") expected = 10;
              assert.equal(value, expected);
            } catch (cause) {
              outcome = 1;
              if (
                name !== "host" && name !== "failed" &&
                name !== "acquisition_failed"
              ) throw cause;
            }
            if (
              name === "host" || name === "failed" ||
              name === "acquisition_failed"
            ) assert.equal(outcome, 1);
            finish(outcome);
            let expected = ["cleanup:0", "drop:0"];
            if (name === "array") expected = ["cleanup:2", "drop:2"];
            if (name === "acquisition_failed") expected = [];
            if (name === "captured_obligation") {
              expected = [...expected, ...expected];
            }
            assert.deepEqual(trace, expected, name);
            assert.equal(memory.buffer.byteLength, warmed);
          }
        }
        failHost = false;
        if (asynchronous) {
          suspended = true;
          for (const rejected of [false, true]) {
            begin();
            const pending = invoke("host", {});
            assert(count("roots") > 0);
            assert(count("leases") > 0);
            assert.equal(count("host_refs"), 1);
            assert.deepEqual(trace, []);
            if (rejected) {
              cancel!(new Error("cancelled"));
              await assert.rejects(pending, /cancelled/);
              finish(1);
            } else {
              settle!(7);
              assert.equal(await pending, 16);
              finish(0);
            }
            assert.deepEqual(trace, ["cleanup:0", "drop:0"]);
          }
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("resource transfer preserves source archive checkpoint restart and failed revisions", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-transfer-import-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/scope.blot`;
  const dependencies = `${directory}/scope.blotdep`;
  const producer =
    `const make = fn (value: U32) => @resource.acquire (fn () => #[value, @u32.add value 1]) (fn owner => ())\n`;
  const consumer =
    `import {make} from "./scope"\nentry const answer = fn (value: U32) => do:\n  use owner <- make value\n  use length <- @usage.borrow owner (fn loan => @usage.length loan)\n  use @resource.release owner\n  return length\n`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(dependency, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const compiler = await createZigProjectCompiler(options);
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      try {
        const first = await compiler.build();
        const archived = await imported.build();
        assert(first.success, JSON.stringify(first));
        assert(archived.success, JSON.stringify(archived));
        assert(archived.stats.cachedModules > 0);
        assert.deepEqual(archived.bytes, first.bytes);
        for (const bytes of [first.bytes, archived.bytes]) {
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(bytes, { asynchronous });
            try {
              if (asynchronous) {
                assert.equal(await guest.callAsync("answer", 42), 2);
              } else assert.equal(guest.call("answer", 42), 2);
            } finally {
              guest.dispose();
            }
          }
        }
        const checkpoint = await compiler.exportCheckpoint();
        const bad = await compiler.build({
          sources: {
            [entry]: consumer,
            [dependency]: producer.replace(
              "fn owner => ()",
              "fn owner => @resource.release owner",
            ),
          },
        });
        assert(!bad.success);
        assert(
          bad.diagnostics.some((diagnostic) =>
            diagnostic.code === "cleanup_not_safe" ||
            diagnostic.code === "effect_mismatch"
          ),
          JSON.stringify(bad),
        );
        const recovered = await compiler.build();
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, first.bytes);
        const resumed = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const restart = await resumed.build();
          assert(restart.success, JSON.stringify(restart));
          assert.deepEqual(restart.bytes, first.bytes);
        } finally {
          await resumed.dispose();
        }
      } finally {
        await compiler.dispose();
        await imported.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
