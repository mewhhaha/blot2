import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Box is data = #Box (unique U32)
opaque type Secret = unique U32
opaque type Shared = shared U32
const make_box = fn (owner: unique U32) => #Box owner
const read_box = fn (#Box owner) => @usage.borrow owner (fn loan => @usage.read loan)
const make_secret = fn (owner: unique U32) => #Secret owner
const make_shared = fn (owner: unique U32) => #Shared (@usage.share owner)
const read_shared = fn (#Shared owner) => @usage.read owner
const repeat_shared = fn (owner: Shared) => @u32.add (read_shared owner) (read_shared owner)
const read_secret = fn (#Secret owner) => @usage.borrow owner (fn loan => @usage.read loan)
`;
const source =
  `import {Box, Secret, make_box, read_box, make_secret, read_secret, make_shared, repeat_shared} from "./owners"
entry const run = fn () => do:
  use owner <- @resource.acquire (fn () => 42) (fn value => ())
  let box = make_box owner
  return read_box box
entry const secret = fn () => do:
  use owner <- @resource.acquire (fn () => 42) (fn value => ())
  let box = make_secret owner
  return read_secret box
entry const shared = fn () => do:
  use owner <- @resource.acquire (fn () => 21) (fn value => ())
  let box = make_shared owner
  return repeat_shared box
entry const shared_cleanup = fn (release: cleanup ((unique U32) -> Unit ! {Foreign})) => do:
  use owner <- @resource.acquire (fn () => 21) release
  let box = make_shared owner
  return repeat_shared box
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`nominal and opaque affinity preserve source archive and restart owner flow (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-affine-nominal-",
    });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/owners.blot`;
    const archive = `${directory}/owners.blotdep`;
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
          const sources = { [entry]: source, [dependency]: library };
          const first = await compiler.build({ sources });
          assert(first.success, JSON.stringify(first));
          if (original) assert.deepEqual(first.bytes, original);
          else original = first.bytes;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(first.bytes, { asynchronous });
            try {
              const invoke = async (name: string) => {
                if (asynchronous) return await guest.callAsync(name, null);
                return guest.call(name, null);
              };
              assert.equal(await invoke("run"), 42);
              assert.equal(await invoke("secret"), 42);
              assert.equal(await invoke("shared"), 42);
              const trace: number[] = [];
              const release = guest.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 16,
                maxCalls: 1,
                call(value) {
                  trace.push(value);
                  return null;
                },
              });
              if (asynchronous) {
                assert.equal(
                  await guest.callAsync("shared_cleanup", release),
                  42,
                );
              } else assert.equal(guest.call("shared_cleanup", release), 42);
              assert.deepEqual(trace, [21]);
              const warmed = guest.memoryBytes();
              for (let iteration = 0; iteration < 128; iteration++) {
                assert.equal(await invoke("run"), 42);
                assert.equal(await invoke("secret"), 42);
                assert.equal(await invoke("shared"), 42);
              }
              if (asynchronous) {
                assert.equal(
                  await guest.callAsync("shared_cleanup", release),
                  42,
                );
              } else assert.equal(guest.call("shared_cleanup", release), 42);
              assert.deepEqual(trace, [21, 21]);
              assert.equal(guest.memoryBytes(), warmed);
            } finally {
              guest.dispose();
            }
          }
          for (const type of ["Box", "Secret"]) {
            const bad = await compiler.build({
              sources: {
                ...sources,
                [entry]: source +
                  `\nconst bad = fn (owner: ${type}) => (owner, owner)\n`,
              },
            });
            assert(!bad.success, JSON.stringify(bad));
            assert(
              bad.diagnostics.some((diagnostic) =>
                diagnostic.code === "use_after_move"
              ),
            );
          }
          const recovered = await compiler.build({ sources });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, first.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const restarted = await restored.build({ sources });
            assert(restarted.success, JSON.stringify(restarted));
            assert.deepEqual(restarted.bytes, first.bytes);
          } finally {
            await restored.dispose();
          }
        } finally {
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
