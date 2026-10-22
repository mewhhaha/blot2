import { strict as assert } from "node:assert";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const producer =
  `const forward: forall [a] => unique a -> unique a = fn owner => owner
`;
const consumer = `import {forward} from "./forward"
entry const answer = fn () => do:
  use owner <- @resource.acquire (fn () => 9) (fn owner => ())
  let moved = forward owner
  use value <- @usage.borrow moved (fn loan => @usage.read loan)
  use @resource.release moved
  break value
entry const ordered = fn (host: Unit -> U32 ! {Foreign}) => do:
  use owner <- @resource.acquire (fn () => 9) (fn owner => ())
  let moved = forward owner
  use offset <- host ()
  use value <- @usage.borrow moved (fn loan => @usage.read loan)
  use @resource.release moved
  break @u32.add value offset
`;
async function observe(bytes: Uint8Array<ArrayBuffer>, expected: number) {
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
      assert.equal(await invoke("answer"), expected);
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
      let failed = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: () => {
          throw new Error("affine-forall-host-failure");
        },
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
        failed = guest.capabilityAsync({
          parameter: "Unit",
          result: "U32",
          call: async () => {
            await Promise.resolve();
            throw new Error("affine-forall-host-failure");
          },
        });
      }
      assert.equal(await invoke("ordered", host), expected + 7);
      assert.equal(calls, 1);
      await assert.rejects(
        () => invoke("ordered", failed),
        (error: unknown) =>
          error instanceof GuestError && error.code === "host_exception",
      );
      assert.equal(await invoke("answer"), expected);
      for (let index = 0; index < 32; index++) {
        assert.equal(await invoke("ordered", host), expected + 7);
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        assert.equal(await invoke("ordered", host), expected + 7);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`explicit affine forall preserves resource moves through imports archives and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/forward.blot`;
    const archive = `${directory}/forward.blotdep`;
    try {
      await Deno.writeTextFile(entry, consumer);
      await Deno.writeTextFile(dependency, producer);
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
          await observe(first.bytes, 9);
          const checkpoint = await compiler.exportCheckpoint();
          const invalid = await compiler.build({
            sources: {
              [entry]: consumer.replaceAll(
                "let moved = forward owner",
                "let moved = forward owner\n  use @resource.release owner",
              ),
            },
          });
          assert(!invalid.success);
          assert(
            invalid.diagnostics.some((diagnostic) =>
              diagnostic.code === "use_after_move"
            ),
            JSON.stringify(invalid),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({
            sources: { [entry]: consumer },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, first.bytes);
          const changed = consumer.replaceAll("fn () => 9", "fn () => 11");
          const edited = await compiler.build({
            sources: { [entry]: changed },
          });
          assert(edited.success, JSON.stringify(edited));
          await observe(edited.bytes, 11);
          const fresh = await createZigProjectCompiler(options);
          try {
            const independent = await fresh.build({
              sources: { [entry]: changed },
            });
            assert(independent.success, JSON.stringify(independent));
            assert.deepEqual(independent.bytes, edited.bytes);
          } finally {
            await fresh.close();
          }
          const reverted = await compiler.build({
            sources: { [entry]: consumer },
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
            await observe(replayed.bytes, 9);
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
