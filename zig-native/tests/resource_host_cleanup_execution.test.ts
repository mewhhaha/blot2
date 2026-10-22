import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source =
  `entry const float = fn (drop: cleanup ((unique F32) -> Unit ! {Foreign})) => @resource.scope (fn () => 1.5) drop (fn loan => @usage.read loan)
entry const array = fn (drop: cleanup ((unique (Array U32)) -> Unit ! {Foreign})) => @resource.scope (fn () => #[1, 2]) drop (fn loan => @usage.length loan)
entry const run = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 42) drop (fn loan => @usage.read loan)
entry const wrapped = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 42) (fn owner => do:
  for index in 0..3:
    let value = index
  break drop owner) (fn loan => @usage.read loan)
entry const acquired = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 42) drop
  break @usage.borrow owner (fn loan => @usage.read loan)
entry const nested = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 7) drop (fn outer => @resource.scope (fn () => 9) drop (fn inner => @u32.add (@usage.read outer) (@usage.read inner)))
entry const trapped = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 11) drop (fn loan => @u32.div (@usage.read loan) 0)
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`host cleanup descriptors remain synchronous and drain every attempt (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-host-cleanup-" });
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, source);
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
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(first.bytes, { asynchronous });
        try {
          const trace: number[] = [];
          const capability = guest.cleanupCapability({
            parameter: "U32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 16,
            call: (value) => {
              trace.push(value);
              return null;
            },
          });
          const invoke = async (
            name: string,
            argument: unknown = capability,
          ) => {
            if (asynchronous) return await guest.callAsync(name, argument);
            return guest.call(name, argument);
          };
          assert.equal(
            (guest.abi.functions[0].parameter as { kind: string }).kind,
            "cleanup",
          );
          const floats: number[] = [];
          const float = guest.cleanupCapability({
            parameter: "F32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 1,
            call: (value) => {
              floats.push(value);
              return null;
            },
          });
          assert.equal(await invoke("float", float), 1.5);
          assert.deepEqual(floats, [1.5]);
          const arrays: Uint32Array[] = [];
          const array = guest.cleanupCapability({
            parameter: "Array U32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 1,
            call: (value) => {
              arrays.push(value);
              return null;
            },
          });
          assert.equal(await invoke("array", array), 2);
          assert.deepEqual(arrays, [new Uint32Array([1, 2])]);
          arrays[0][0] = 999;
          assert.equal(await invoke("array", array), 2);
          assert.deepEqual(arrays[1], new Uint32Array([1, 2]));
          assert.equal(await invoke("run"), 42);
          assert.equal(await invoke("acquired"), 42);
          assert.equal(await invoke("wrapped"), 42);
          assert.equal(await invoke("nested"), 16);
          assert.deepEqual(trace, [42, 42, 42, 9, 7]);
          trace.length = 0;
          await assert.rejects(() => invoke("trapped"));
          assert.deepEqual(trace, [11]);
          const ordinary = guest.capability({
            parameter: "U32",
            result: "Unit",
            call: () => null,
          });
          await assert.rejects(
            () => invoke("run", ordinary),
            (err: unknown) =>
              err instanceof GuestError && err.code === "capability_signature",
          );
          if (asynchronous) {
            const asyncDescriptor = guest.capabilityAsync({
              parameter: "U32",
              result: "Unit",
              call: () => Promise.resolve(null),
            });
            await assert.rejects(
              () => invoke("run", asyncDescriptor),
              (err: unknown) =>
                err instanceof GuestError &&
                err.code === "capability_signature",
            );
          }
          for (
            const metadata of [
              { maxSteps: 0, maxCalls: 1 },
              { maxSteps: 1, maxCalls: 0 },
              { maxSteps: Infinity, maxCalls: 1 },
              { maxSteps: 1, maxCalls: 65537 },
            ]
          ) {
            assert.throws(
              () =>
                guest.cleanupCapability({
                  parameter: "U32",
                  result: "Unit",
                  call: () => null,
                  ...metadata,
                }),
              GuestError,
            );
          }
          const thrown: number[] = [];
          const failing = guest.cleanupCapability({
            parameter: "U32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 16,
            call: (value) => {
              thrown.push(value);
              throw new Error(`drop${value}`);
            },
          });
          await assert.rejects(
            () => invoke("nested", failing),
            (err: unknown) =>
              err instanceof GuestError && err.code === "host_exception" &&
              String(err.cause) === "Error: drop9",
          );
          assert.deepEqual(thrown, [9, 7]);
          const limited: number[] = [];
          const limit = guest.cleanupCapability({
            parameter: "U32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 1,
            call: (value) => {
              limited.push(value);
              return null;
            },
          });
          await assert.rejects(() => invoke("nested", limit));
          assert.deepEqual(limited, [9]);
          const promise = guest.cleanupCapability({
            parameter: "U32",
            result: "Unit",
            maxSteps: 32,
            maxCalls: 16,
            call: (() => Promise.resolve(null)) as unknown as () => null,
          });
          await assert.rejects(
            () => invoke("run", promise),
            (err: unknown) =>
              err instanceof GuestError && err.code === "async_host_call",
          );
          trace.length = 0;
          assert.equal(await invoke("run"), 42);
          const warmed = guest.memoryBytes();
          for (let i = 0; i < 128; i++) {
            assert.equal(await invoke("nested"), 16);
          }
          assert.equal(guest.memoryBytes(), warmed);
        } finally {
          guest.dispose();
        }
      }
      const checkpoint = await compiler.exportCheckpoint();
      const failed = await compiler.build({
        sources: {
          [entry]: source.replaceAll(
            "cleanup ((unique U32) -> Unit ! {Foreign})",
            "((unique U32) -> Unit ! {Foreign})",
          ),
        },
      });
      assert(!failed.success);
      const recovered = await compiler.build({ sources: { [entry]: source } });
      assert(recovered.success);
      assert.deepEqual(recovered.bytes, first.bytes);
      assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
    } finally {
      await compiler.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("host cleanup imports preserve exact roles through archives and restarts", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-host-cleanup-import-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/cleanup.blot`;
  const archive = `${directory}/cleanup.blotdep`;
  const library = source.replaceAll("entry const", "const");
  const main = `import {run, acquired, wrapped} from "./cleanup"
entry const answer = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => run drop
entry const owned = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => acquired drop
entry const finite = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => wrapped drop
`;
  await Deno.writeTextFile(entry, main);
  await Deno.writeTextFile(dependency, library);
  try {
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stderr));
    for (const codegenTier of ["development", "optimized"] as const) {
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
        try {
          const first = await compiler.build({
            sources: { [entry]: main, [dependency]: library },
          });
          assert(first.success, JSON.stringify(first));
          if (original) assert.deepEqual(first.bytes, original);
          else original = first.bytes;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(first.bytes, { asynchronous });
            try {
              const trace: number[] = [];
              const drop = guest.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 16,
                call: (value) => {
                  trace.push(value);
                  return null;
                },
              });
              for (const name of ["answer", "owned", "finite"]) {
                let value;
                if (asynchronous) value = await guest.callAsync(name, drop);
                else value = guest.call(name, drop);
                assert.equal(value, 42);
              }
              assert.deepEqual(trace, [42, 42, 42]);
            } finally {
              guest.dispose();
            }
          }
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const fresh = await restored.build({
              sources: { [entry]: main, [dependency]: library },
            });
            assert(fresh.success, JSON.stringify(fresh));
            assert.deepEqual(fresh.bytes, first.bytes);
          } finally {
            await restored.close();
          }
        } finally {
          await compiler.close();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
