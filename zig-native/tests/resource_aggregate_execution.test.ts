import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library =
  `const inspect = fn (value: U32) => @resource.scope (fn () => {left: value, right: #[#[value, 7], #[9]]}) (fn owner => ()) (fn loan => 42)
const tuple = fn (value: U32) => do:
  use owner <- @resource.acquire (fn () => (value, #[value, 8])) (fn owned => ())
  let transfer: once (Unit -> Unit ! {Foreign}) = fn () => @resource.release owner
  use transfer ()
  return 42
const nested = fn (value: U32) => @resource.scope (fn () => #[#[value, 7], #[9]]) (fn owner => ()) (fn loan => @usage.length loan)
const failing = fn (value: U32) => @resource.scope (fn () => {left: value, right: #[#[value, 7], #[9]]}) (fn owner => do:
  let ignored = @u32.div 1 value
  return ()) (fn loan => 42)
`;
const source = `import {inspect, tuple, nested, failing} from "./cleanup"
entry const answer = fn (value: U32) => @u32.add (inspect value) (tuple value)
entry const length = fn (value: U32) => nested value
entry const failure = fn (value: U32) => failing value
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
                "(fn owner => ())",
                "(fn owner => do:\n    for ever:\n      let ignored = 7\n    return ())",
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
