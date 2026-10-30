import { strict as assert } from "node:assert";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const reader =
  `const read: forall [region r] => (borrow r U32) -> U32 = func loan => return @usage.read loan
`;
const consumer = `import {read} from "./reader"
const inspect = func (owner: unique U32) => return @usage.borrow owner (func loan => return read loan)
entry const answer = func () => return inspect 42
entry const another = func () => return inspect 7
entry const ordered = func (host: Unit -> U32 ! {Foreign}) => return (func (owner: unique U32) => return @usage.borrow owner (func loan => return do:
  use offset <- host ()
  break @u32.add (read loan) offset
)) 9
`;
async function observe(bytes: Uint8Array<ArrayBuffer>, delta = 0) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const invoke = async (
        name: string,
        value: Parameters<typeof guest.call>[1] = null,
      ) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      assert.equal(await invoke("answer"), 42 + delta);
      assert.equal(await invoke("another"), 7 + delta);
      let calls = 0;
      const callback = () => {
        calls++;
        return 7;
      };
      let host = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: callback,
      });
      if (asynchronous) {
        host = guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            return callback();
          },
        });
      }
      assert.equal(await invoke("ordered", host), 16 + delta);
      assert.equal(calls, 1);
      let failed = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: () => {
          throw new Error("region-forall-host-failure");
        },
      });
      if (asynchronous) {
        failed = guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            throw new Error("region-forall-host-failure");
          },
        });
      }
      await assert.rejects(
        () => invoke("ordered", failed),
        (error: unknown) =>
          error instanceof GuestError && error.code === "host_exception",
      );
      assert.equal(await invoke("answer"), 42 + delta);
      for (let index = 0; index < 32; index++) {
        assert.equal(await invoke("ordered", host), 16 + delta);
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        assert.equal(await invoke("ordered", host), 16 + delta);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`region forall readers preserve loan owners across imports edits archives and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/reader.blot`;
    const archive = `${directory}/reader.blotdep`;
    try {
      await Deno.writeTextFile(entry, consumer);
      await Deno.writeTextFile(dependency, reader);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      let expected: Uint8Array<ArrayBuffer> | undefined;
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
          const first = await compiler.build();
          assert(first.success, JSON.stringify(first));
          if (dependencies) assert(first.stats.cachedModules > 0);
          if (expected) assert.deepEqual(first.bytes, expected);
          else expected = first.bytes;
          await observe(first.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const bad = await compiler.build({
            sources: {
              [entry]: consumer +
                "const escaped = func (owner: unique U32) => return @usage.borrow owner (func loan => return func () => return read loan)\n",
            },
          });
          assert(!bad.success);
          assert(
            bad.diagnostics.some((diagnostic) =>
              diagnostic.code === "borrow_escape"
            ),
            JSON.stringify(bad),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({
            sources: { [entry]: consumer },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, first.bytes);
          const changed = reader.replace(
            "=> return @usage.read loan",
            "=> return @u32.add (@usage.read loan) 1",
          );
          const edited = await compiler.build({
            sources: { [dependency]: changed },
          });
          assert(edited.success, JSON.stringify(edited));
          await observe(edited.bytes, 1);
          const fresh = await createZigProjectCompiler(options);
          try {
            const independent = await fresh.build({
              sources: { [dependency]: changed },
            });
            assert(independent.success, JSON.stringify(independent));
            assert.deepEqual(independent.bytes, edited.bytes);
          } finally {
            await fresh.close();
          }
          const reverted = await compiler.build({
            sources: { [dependency]: reader },
          });
          assert(reverted.success, JSON.stringify(reverted));
          assert.deepEqual(reverted.bytes, first.bytes);
          const restarted = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restarted.build();
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, first.bytes);
            await observe(replayed.bytes);
          } finally {
            await restarted.close();
          }
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
