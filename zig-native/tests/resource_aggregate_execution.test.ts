import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library =
  `const inspect = func (value: U32) => return @resource.scope (func () => return {left: value, right: #[#[value, 7], #[9]]}) (func owner => return ()) (func loan => return 42)
const tuple = func (value: U32) => return do:
  use owner <- @resource.acquire (func () => return (value, #[value, 8])) (func owned => return ())
  let transfer: once (Unit -> Unit ! {Foreign}) = func () => return @resource.release owner
  use transfer ()
  break 42
const nested = func (value: U32) => return @resource.scope (func () => return #[#[value, 7], #[9]]) (func owner => return ()) (func loan => return @usage.length loan)
const failing = func (value: U32) => return @resource.scope (func () => return {left: value, right: #[#[value, 7], #[9]]}) (func owner => return do:
  let ignored = @u32.div 1 value
  break ()) (func loan => return 42)
`;
const source = `import {inspect, tuple, nested, failing} from "./cleanup"
entry const answer = func (value: U32) => return @u32.add (inspect value) (tuple value)
entry const length = func (value: U32) => return nested value
entry const failure = func (value: U32) => return failing value
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`closed aggregate resources retain exact children and portable cleanup (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-aggregate-resource-",
    });
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
      assert(
        packed.success,
        new TextDecoder().decode(packed.stderr) +
          new TextDecoder().decode(packed.stdout),
      );
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
                if (asynchronous) return await guest.callAsync("answer", 5);
                return guest.call("answer", 5);
              };
              assert.equal(await invoke(), 84);
              const warmed = guest.memoryBytes();
              for (let i = 0; i < 128; i++) assert.equal(await invoke(), 84);
              assert.equal(guest.memoryBytes(), warmed);
              if (asynchronous) {
                assert.equal(await guest.callAsync("length", 7), 2);
                await assert.rejects(guest.callAsync("failure", 0));
              } else {
                assert.equal(guest.call("length", 7), 2);
                assert.throws(() => guest.call("failure", 0));
              }
              assert.equal(await invoke(), 84);
              assert.equal(guest.memoryBytes(), warmed);
            } finally {
              guest.dispose();
            }
          }
          const checkpoint = await compiler.exportCheckpoint();
          const failed = await compiler.build({
            sources: {
              [entry]: source,
              [dependency]: library.replace(
                "(func owner => return ())",
                "(func owner => return do:\n    for ever:\n      let ignored = 7\n    break ())",
              ),
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
