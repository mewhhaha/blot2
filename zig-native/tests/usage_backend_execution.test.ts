import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
const unit = fn (owner: unique Unit) => @usage.borrow owner (fn loan => @usage.read loan)
const float = fn (owner: unique F32) => @usage.borrow_mut owner (fn loan => @f32.add (@usage.read loan) (@usage.read loan))
const captured = fn (callback: once (Unit -> U32 ! {Foreign})) => do:
  let owner = (fn (value: unique U32) => value) 9
  return @usage.borrow owner (fn loan => @u32.add (@usage.read loan) (callback ()))
const payload = fn (owner: unique U32) => @usage.borrow owner (fn loan => @array.fill 1024 (@usage.read loan))
entry const buffer = fn () => payload 9
entry const empty = fn () => unit ()
entry const fraction = fn () => float 1.25
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => captured (fn () => host ())
entry const ordered = fn (host: Unit -> U32 ! {Foreign}) => do:
  let create = fn () => do:
    use ignored <- host ()
    return (fn (value: unique U32) => value) 9
  return @usage.borrow (create ()) (fn loan => @u32.add (@usage.read loan) (host ()))
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`borrow backend preserves scalar machines captured callbacks and owner order (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, first.bytes);
      const unresolved = await compiler.build({
        sources: {
          [entry]: source +
            "\nentry const unknown: forall [a] => a -> a = fn value => value\n",
        },
      });
      assert(!unresolved.success);
      assert(
        unresolved.diagnostics.some((diagnostic) =>
          diagnostic.code === "entry_type" ||
          diagnostic.code === "unresolved_type"
        ),
        JSON.stringify(unresolved),
      );
      const recovered = await compiler.build({ sources: { [entry]: source } });
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, first.bytes);
      const module = new WebAssembly.Module(first.bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(first.bytes, { asynchronous });
        try {
          const call = async (name: string, value: unknown) => {
            if (asynchronous) return await guest.callAsync(name, value);
            return guest.call(name, value);
          };
          assert.equal(await call("empty", null), null);
          assert.equal(await call("fraction", null), 2.5);
          let calls = 0;
          let host = guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => ++calls,
          });
          if (asynchronous) {
            host = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: async () => {
                await Promise.resolve();
                return ++calls;
              },
            });
          }
          assert.equal(await call("answer", host), 10);
          assert.equal(calls, 1);
          calls = 0;
          assert.equal(await call("ordered", host), 11);
          assert.equal(calls, 2);
          assert.deepEqual(
            await call("buffer", null),
            new Uint32Array(1024).fill(9),
          );
          let failed = guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => {
              throw new Error("borrow-host-failure");
            },
          });
          if (asynchronous) {
            failed = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: async () => {
                await Promise.resolve();
                throw new Error("borrow-host-failure");
              },
            });
          }
          await assert.rejects(
            call("answer", failed),
            (error: unknown) =>
              error instanceof GuestError && error.code === "host_exception",
          );
          calls = 0;
          assert.equal(await call("answer", host), 10);
          const warmBytes = guest.memoryBytes();
          for (let index = 0; index < 8; index++) {
            calls = 0;
            assert.equal(await call("answer", host), 10);
            assert.equal(calls, 1);
            assert.deepEqual(
              await call("buffer", null),
              new Uint32Array(1024).fill(9),
            );
          }
          assert.equal(guest.memoryBytes(), warmBytes);
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
