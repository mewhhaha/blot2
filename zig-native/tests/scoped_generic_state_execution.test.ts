import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = "const store = func setter => return func value => return setter value\n";
const source = `import {store} from "./library"
type State a is effect = {get: Unit -> a, set: a -> Unit}
type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
entry const answer = func (seed: U32) => return @effect.scope (func (s: State U32) => return do:
  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    use store Box.set (func () => return do:
      let (state, value) = do (@effect.state s.get s.set seed):
        break s.get ()
      break value
    )
    use callback <- Box.get ()
    break callback ()
  break result
)
`;
async function execute(bytes: Uint8Array) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      for (let index = 0; index < 32; index++) {
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", 42), 42);
        } else assert.equal(guest.call("answer", 42), 42);
      }
    } finally {
      guest.dispose();
    }
  }
}
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`generic State setter uses the actual local cell through archives and recovery (${codegenTier})`, async () => {
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
          const older = `import {store} from "./library"
type State a is effect = {get: Unit -> a, set: a -> Unit}
type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
entry const answer = func () => return do:
  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    break @effect.scope (func (s: State U32) => return do:
      use store Box.set (func () => return do:
        let (state, value) = do (@effect.state s.get s.set 42):
          break s.get ()
        break value
      )
      break 0
    )
  break result
`;
          const ordinary = source.replace(
            "@effect.state Box.get Box.set (func () => return 0)",
            "@effect.provider Box.set (func value => return ())",
          ).replace("let (stored, result) =", "let result =");
          for (const invalid of [older, ordinary]) {
            const rejected = await compiler.build({
              sources: { [entry]: invalid },
            });
            assert(!rejected.success);
            assert(
              JSON.stringify(rejected).includes("capability_escape"),
              JSON.stringify(rejected),
            );
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
