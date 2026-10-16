import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const run = fn () => @effect.scope (fn (older: State U32) => do:
  use escaped <- @effect.scope (fn (younger: State F32) => @resource.scope (fn () => 9) (fn owner => do:
    let cleanup_capture = younger
    return ()
  ) (fn loan => do:
    let observed = @usage.read loan
    return fn () => do:
      let retained = older
      return 42
  ))
  return escaped ()
)
const fail = fn () => @effect.scope (fn (state: State U32) => @resource.scope (fn () => 9) (fn owner => @panic "cleanup") (fn loan => @usage.read loan))
`;
const source = `import {run, fail} from "./library"
entry const answer = fn () => run ()
entry const failed = fn () => fail ()
`;
async function execute(bytes: Uint8Array, expected: number) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const invoke = async (name: string) => {
        if (asynchronous) return await guest.callAsync(name, null);
        return guest.call(name, null);
      };
      assert.equal(await invoke("answer"), expected);
      await assert.rejects(() => invoke("failed"), WebAssembly.RuntimeError);
      for (let index = 0; index < 32; index++) {
        assert.equal(await invoke("answer"), expected);
      }
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        assert.equal(await invoke("answer"), expected);
      }
      assert(guest.memoryBytes() <= warmed + 65536);
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped resource result footprints survive cleanup archives and recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/library.blot`;
    const archive = `${directory}/library.blotdep`;
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(dependency, library);
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
      let bytes: Uint8Array | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          dependencies,
          cacheDirectory: false as const,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          const built = await compiler.build();
          assert(built.success, JSON.stringify(built));
          if (bytes) assert.deepEqual(built.bytes, bytes);
          else bytes = built.bytes;
          await execute(built.bytes, 42);
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restored.build();
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            await execute(replayed.bytes, 42);
          } finally {
            await restored.close();
          }
          const edited = await compiler.build({
            sources: {
              [dependency]: library.replace("return 42", "return 43"),
            },
          });
          assert(edited.success, JSON.stringify(edited));
          await execute(edited.bytes, 43);
          const invalid = await compiler.build({
            sources: {
              [dependency]: library.replace(
                "let retained = older",
                "let retained = younger",
              ),
            },
          });
          assert(!invalid.success);
          assert(
            invalid.diagnostics.some((diagnostic) =>
              diagnostic.code === "capability_escape"
            ),
          );
          const recovered = await compiler.build({
            sources: { [dependency]: library },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
