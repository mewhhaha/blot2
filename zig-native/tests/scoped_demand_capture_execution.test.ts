import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = "const delay = func ~value => return value\n";
const source = `import {delay} from "./library"
type State a is effect = {get: Unit -> a, set: a -> Unit}
entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
  let ignored = s
  let pending = delay (do:
    let local = 42
    break local
  )
  use finished <- @demand pending
  break finished
)
`;
async function execute(bytes: Uint8Array) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      for (let index = 0; index < 32; index++) {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", null), 42);
        } else assert.equal(guest.call("answer", null), 42);
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped demand construction capture proof survives archives and recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/library.blot`;
    const archive = `${directory}/library.blotdep`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(dependency, library);
    try {
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      let bytes: Uint8Array | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          cacheDirectory: false as const,
          dependencies,
        };
        const compiler = await createZigProjectCompiler(options);
        try {
          const built = await compiler.build();
          assert(built.success, JSON.stringify(built));
          if (bytes) assert.deepEqual(built.bytes, bytes);
          else bytes = built.bytes;
          await execute(built.bytes);
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          try {
            const replayed = await restored.build();
            assert(replayed.success, JSON.stringify(replayed));
            assert.deepEqual(replayed.bytes, built.bytes);
            await execute(replayed.bytes);
          } finally {
            await restored.close();
          }
          for (const capture of ["s", "s.get"]) {
            const invalid = source.replace(
              "let local = 42",
              `let captured = ${capture}\n    let local = 42`,
            );
            const rejected = await compiler.build({
              sources: { [entry]: invalid },
            });
            assert(!rejected.success);
            assert(JSON.stringify(rejected).includes("capability_escape"));
          }
          const recovered = await compiler.build({
            sources: { [entry]: source },
          });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
          await execute(recovered.bytes);
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
