import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  GuestError,
  type GuestOwner,
  instantiateGuest,
} from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Box a is data = #Box a
opaque type Secret = {left: U32, right: Array U32}
type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)
const closed = fn () => @resource.acquire (fn () => #Secret {right: #[8, 9], left: 7}) (fn owner => ())
const tree = fn () => @resource.acquire (fn () => #Branch (#Leaf 7, #Leaf 9)) (fn owner => ())
const box = fn () => @resource.acquire (fn () => #Box #[7, 9]) (fn owner => ())
const release_secret = fn (owner: unique Secret) => @resource.release owner
const release_tree = fn (owner: unique (Tree U32)) => @resource.release owner
const release_box = fn (owner: unique (Box (Array U32))) => @resource.release owner
`;
const source =
  `import {closed, tree, box, release_secret, release_tree, release_box} from "./owners"
entry const make = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.acquire (fn () => 42) drop
entry const float = fn (drop: cleanup ((unique F32) -> Unit ! {Foreign})) => @resource.acquire (fn () => 1.5) drop
entry const array = fn (drop: cleanup ((unique (Array U32)) -> Unit ! {Foreign})) => @resource.acquire (fn () => #[1, 2]) drop
entry const pure = fn () -> unique U32 => 9
entry const consume = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)
entry const pass = fn (owner: unique U32) => owner
entry const share = fn (owner: unique U32) => @usage.share owner
entry const read = fn (owner: shared U32) => @usage.borrow owner (fn loan => @usage.read loan)
entry const alias = fn (owner: shared U32) => owner
entry const length = fn (owner: unique (Array U32)) => @usage.borrow owner (fn loan => @usage.length loan)
entry const tuple = fn () => @resource.acquire (fn () => (#[7, 9], {items: #[#[1, 2]]})) (fn owner => ())
entry const finish_tuple = fn (owner: unique (Array U32, {items: Array (Array U32)})) => @resource.release owner
entry const secret = fn () => closed ()
entry const finish_secret = fn owner => release_secret owner
entry const tree_owner = fn () => tree ()
entry const finish_tree = fn owner => release_tree owner
entry const box_owner = fn () => box ()
entry const finish_box = fn owner => release_box owner
entry const waiting = fn (host: U32 -> U32 ! {Foreign}) => host 7
`;
const ownerError = (code: string) => (error: unknown) =>
  error instanceof GuestError && error.code === code;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`public owners retain exact native lifetimes and synchronous cleanup bindings (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-public-owner-" });
    const entry = `${directory}/main.blot`,
      dependency = `${directory}/owners.blot`,
      archive = `${directory}/owners.blotdep`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(dependency, library);
    try {
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      let original: Uint8Array<ArrayBuffer> | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
          dependencies,
        };
        const compiler = await createZigProjectCompiler(options);
        let restarted: typeof compiler | undefined;
        try {
          const first = await compiler.build({
            sources: { [entry]: source, [dependency]: library },
          });
          assert(first.success, JSON.stringify(first));
          if (original) assert.deepEqual(first.bytes, original);
          else original = first.bytes;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(first.bytes, { asynchronous });
            const invoke = async (name: string, value: unknown = null) => {
              if (asynchronous) return await guest.callAsync(name, value);
              return guest.call(name, value);
            };
            const trace: number[] = [];
            const drop = guest.cleanupCapability({
              parameter: "U32",
              result: "Unit",
              maxSteps: 32,
              maxCalls: 2,
              call(value) {
                trace.push(value);
                return null;
              },
            });
            try {
              let owner = await invoke("make", drop) as GuestOwner;
              assert.deepEqual(trace, []);
              const moved = await invoke("pass", owner) as GuestOwner;
              await assert.rejects(
                () => invoke("consume", owner),
                ownerError("use_after_move"),
              );
              assert.equal(await invoke("consume", moved), 42);
              assert.deepEqual(trace, [42]);
              await assert.rejects(
                () => invoke("consume", moved),
                ownerError("use_after_move"),
              );
              owner = await invoke("make", drop) as GuestOwner;
              const shared = await invoke("share", owner) as GuestOwner;
              const alias = await invoke("alias", shared) as GuestOwner;
              assert.equal(await invoke("read", shared), 42);
              assert.equal(await invoke("read", alias), 42);
              guest.releaseOwner(shared);
              assert.deepEqual(trace, [42]);
              assert.equal(await invoke("read", alias), 42);
              guest.releaseOwner(alias);
              assert.deepEqual(trace, [42, 42]);
              owner = await invoke("make", drop) as GuestOwner;
              await assert.rejects(
                () => invoke("length", owner),
                ownerError("owner_type"),
              );
              assert.equal(await invoke("consume", owner), 42);
              await assert.rejects(
                () => invoke("pass", { usage: "unique" }),
                ownerError("invalid_argument"),
              );
              const foreign = await instantiateGuest(first.bytes, {
                asynchronous,
              });
              const foreignDrop = foreign.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call: () => null,
              });
              const foreignOwner = asynchronous
                ? await foreign.callAsync("make", foreignDrop)
                : foreign.call("make", foreignDrop);
              await assert.rejects(
                () => invoke("consume", foreignOwner),
                ownerError("foreign_owner"),
              );
              foreign.dispose();
              assert.equal(await invoke("consume", await invoke("pure")), 9);
              assert.equal(await invoke("consume", 11), 11);
              for (
                const [make, finish] of [
                  ["tuple", "finish_tuple"],
                  ["secret", "finish_secret"],
                  ["tree_owner", "finish_tree"],
                  ["box_owner", "finish_box"],
                ]
              ) assert.equal(await invoke(finish, await invoke(make)), null);
              const floats: number[] = [];
              const float = guest.cleanupCapability({
                parameter: "F32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call(v) {
                  floats.push(v);
                  return null;
                },
              });
              guest.releaseOwner(await invoke("float", float) as GuestOwner);
              assert.deepEqual(floats, [1.5]);
              const arrays: Uint32Array[] = [];
              const array = guest.cleanupCapability({
                parameter: "Array U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call(v) {
                  arrays.push(v);
                  return null;
                },
              });
              assert.equal(
                await invoke("length", await invoke("array", array)),
                2,
              );
              assert.deepEqual(arrays, [new Uint32Array([1, 2])]);
              arrays[0][0] = 99;
              if (asynchronous) {
                let settle!: (value: number) => void;
                const host = guest.capabilityAsync({
                  parameter: "U32",
                  result: "U32",
                  call: () =>
                    new Promise<number>((resolve) => settle = resolve),
                });
                const pending = guest.callAsync("waiting", host);
                assert.throws(
                  () => guest.dispose(),
                  ownerError("reentrant_call"),
                );
                settle(8);
                assert.equal(await pending, 8);
              }
              await invoke("consume", await invoke("make", drop));
              const warmed = guest.memoryBytes();
              for (let index = 0; index < 128; index++) {
                const retained = await invoke("make", drop) as GuestOwner;
                const transient = await invoke("make", drop) as GuestOwner;
                guest.releaseOwner(retained);
                assert.equal(await invoke("consume", transient), 42);
              }
              assert.equal(guest.memoryBytes(), warmed);
              const failingTrace: number[] = [];
              const failed = guest.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call(value) {
                  failingTrace.push(value);
                  throw new Error("late cleanup");
                },
              });
              const doomed = await invoke("make", failed) as GuestOwner;
              assert.throws(
                () => guest.releaseOwner(doomed),
                ownerError("host_exception"),
              );
              assert.throws(
                () => guest.releaseOwner(doomed),
                ownerError("use_after_move"),
              );
              assert.deepEqual(failingTrace, [42]);
              const promises = guest.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call: (() => Promise.resolve(null)) as unknown as () => null,
              });
              const promised = await invoke("make", promises) as GuestOwner;
              assert.throws(
                () => guest.releaseOwner(promised),
                ownerError("async_host_call"),
              );
              const freeze = Object.freeze;
              const failedPublication = trace.length;
              Object.freeze = ((value: object) => {
                if (
                  Reflect.ownKeys(value).some((key) =>
                    typeof key === "symbol" && key.description === "GuestOwner"
                  )
                ) throw new Error("owner publication failure");
                return freeze(value);
              }) as typeof Object.freeze;
              try {
                await assert.rejects(
                  () => invoke("make", drop),
                  /owner publication failure/,
                );
              } finally {
                Object.freeze = freeze;
              }
              assert.equal(trace.length, failedPublication + 1);
              const before = trace.length;
              await invoke("make", drop);
              await invoke("make", drop);
              guest.dispose();
              assert.equal(trace.length, before + 2);
              assert.throws(
                () => guest.releaseOwner(owner),
                ownerError("disposed_guest"),
              );
            } finally {
              guest.dispose();
            }
          }
          const checkpoint = await compiler.exportCheckpoint();
          const invalid = await compiler.build({
            sources: {
              [entry]: source.replace(
                "@usage.borrow owner (fn loan => @usage.read loan)",
                "(owner, owner)",
              ),
            },
          });
          assert(!invalid.success);
          const recovered = await compiler.build({
            sources: { [entry]: source },
          });
          assert(recovered.success);
          assert.deepEqual(recovered.bytes, first.bytes);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          restarted = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          const restored = await restarted.build({
            sources: { [entry]: source, [dependency]: library },
          });
          assert(restored.success);
          assert.deepEqual(restored.bytes, first.bytes);
        } finally {
          await compiler.dispose();
          await restarted?.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`raw Wasm owner bridges reject forged and reused leases and share once authority (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const source = `entry const make = fn () -> unique U32 => 42
entry const consume = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)
entry const once: once ((unique U32) -> U32) = fn owner => @usage.borrow owner (fn loan => @usage.read loan)
entry const many = fn (owner: shared U32) => @usage.read owner
entry const share = fn (owner: unique U32) => @usage.share owner
`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const module = await WebAssembly.compile(first.bytes);
      assert.equal(WebAssembly.Module.imports(module).length, 0);
      // Forge a fresh F32 claim on the actual i32 owner entry. The guest linker
      // rejects the signature without invoking any owner or initializer body.
      const forged = first.bytes.slice();
      const encoded = new TextEncoder().encode("consume");
      let metadata = -1;
      for (
        let offset = 0;
        offset + encoded.length + 3 < forged.length;
        offset++
      ) {
        if (
          forged[offset] !== encoded.length ||
          !encoded.every((byte, index) => forged[offset + index + 1] === byte)
        ) continue;
        const tag = offset + encoded.length + 1;
        if (forged[tag] !== 8) continue;
        let cursor = tag + 1;
        while (forged[cursor++] >= 128) { /* canonical schema ULEB */ }
        if (forged[cursor] !== 1) continue;
        metadata = cursor;
        break;
      }
      assert(metadata >= 0);
      forged[metadata] = 3;
      await assert.rejects(
        () => instantiateGuest(forged),
        ownerError("invalid_abi"),
      );
      const raw = await WebAssembly.instantiate(module, {});
      const call = (name: string, ...args: number[]) =>
        (raw.exports[name] as CallableFunction)(...args);
      const invoke = (name: string, value: number) => {
        call("blot:ownership_enter");
        try {
          return call(name, value);
        } finally {
          call("blot:ownership_leave", 0);
        }
      };
      const lease = invoke("make", 0);
      for (const forged of [0, lease + 1, 0xFFFFFFFF]) {
        assert.throws(
          () => invoke("blot:owner_call/consume", forged),
          WebAssembly.RuntimeError,
        );
      }
      assert.equal(invoke("blot:owner_call/consume", lease), 42);
      assert.throws(
        () => invoke("blot:owner_call/consume", lease),
        WebAssembly.RuntimeError,
      );
      const another = invoke("make", 0);
      assert.equal(invoke("once", 9), 9);
      assert.throws(
        () => invoke("blot:owner_call/once", another),
        WebAssembly.RuntimeError,
      );
      assert.equal(invoke("blot:owner_call/consume", another), 42);
      const shared = invoke("blot:owner_call/share", invoke("make", 0));
      assert.equal(invoke("blot:owner_call/many", shared), 42);
      assert.equal(invoke("blot:owner_call/many", shared), 42);
      invoke("blot:owner_release", shared);
      assert.throws(
        () => invoke("blot:owner_call/many", shared),
        WebAssembly.RuntimeError,
      );
      const leases: number[] = [];
      for (let index = 0; index < 4096; index++) leases.push(invoke("make", 0));
      assert.throws(() => invoke("make", 0), WebAssembly.RuntimeError);
      invoke("blot:owner_release", leases[0]);
      const replacement = invoke("make", 0);
      assert(replacement > leases[4095]);
      assert.throws(
        () => invoke("blot:owner_call/consume", leases[0]),
        WebAssembly.RuntimeError,
      );
      invoke("blot:owner_release", replacement);
      for (const lease of leases.slice(1)) invoke("blot:owner_release", lease);
      call("blot:ownership_leave", 2);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
