import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `const drop: cleanup ((unique U32) -> Unit) = fn owner => do:
  for index in 0..3:
    let value = index
  break ()
const consume = fn (owner: unique U32) => drop owner
`;
const source = `import {consume} from "./cleanup"
entry const answer = fn () => do:
  let adapter: cleanup ((unique U32) -> Unit) = fn owner => ()
  use owner <- @resource.acquire (fn () => 9) (fn value => ())
  let ignored = adapter owner
  use other <- @resource.acquire (fn () => 11) (fn value => ())
  let result = consume other
  break 42
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`standalone pure cleanup literals retain source and portable receipts (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-pure-cleanup-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/cleanup.blot`;
    const archive = `${directory}/cleanup.blotdep`;
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
        try {
          const first = await compiler.build({
            sources: { [entry]: source, [dependency]: library },
          });
          assert(first.success, JSON.stringify(first));
          if (original) assert.deepEqual(first.bytes, original);
          else original = first.bytes;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(first.bytes, { asynchronous });
            try {
              const invoke = async () => {
                if (asynchronous) return await guest.callAsync("answer", null);
                return guest.call("answer", null);
              };
              assert.equal(await invoke(), 42);
              const warmed = guest.memoryBytes();
              for (let i = 0; i < 128; i++) assert.equal(await invoke(), 42);
              assert.equal(guest.memoryBytes(), warmed);
            } finally {
              guest.dispose();
            }
          }
          const checkpoint = await compiler.exportCheckpoint();
          const failed = await compiler.build({
            sources: {
              [entry]: source,
              [dependency]: library.replace("for index in 0..3:", "for ever:"),
            },
          });
          assert(!failed.success);
          const recovered = await compiler.build({
            sources: { [entry]: source, [dependency]: library },
          });
          assert(recovered.success);
          assert.deepEqual(recovered.bytes, first.bytes);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const fresh = await restored.build({
              sources: { [entry]: source, [dependency]: library },
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
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
