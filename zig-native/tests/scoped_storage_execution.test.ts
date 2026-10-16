import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
const identity = fn value => value
`;
const main = `import {State, Box, identity} from "./state"
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => @effect.scope (fn (s: State U32) => do:
  use boxed <- do (@effect.state Box.get Box.set (fn () => 0)):
    let original = fn () => do:
      let (state, value) = do (@effect.state s.get s.set 7):
        return s.get ()
      return value
    let version = identity original
    let bundle = {callback: version, nested: #[version]}
    use Box.set bundle.callback
    use adjust <- host ()
    use callback <- Box.get ()
    return @u32.add (callback ()) adjust
  let (stored, result) = boxed
  return result
)
`;
const older = `import {State, Box, identity} from "./state"
entry const invalid = fn () => do:
  let (stored, result) = do (@effect.state Box.get Box.set (fn () => 0)):
    return @effect.scope (fn (s: State U32) => do:
      use Box.set (fn () => do:
        let (state, value) = do (@effect.state s.get s.set 7):
          return s.get ()
        return value
      )
      return 42
    )
  return result
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`local State storage retains scoped captures through suspension and compiled imports (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-local-store-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/state.blot`;
    const archive = `${directory}/state.blotdep`;
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      for (const dependencies of [undefined, archive]) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false,
        });
        const sources = { [entry]: main, [dependency]: library };
        try {
          const built = await compiler.build({ sources });
          assert(built.success, JSON.stringify(built));
          const sync = await instantiateGuest(built.bytes);
          try {
            const host = sync.capability({
              parameter: "Unit",
              result: "U32",
              call: () => 3,
            });
            assert.equal(sync.call("answer", host), 10);
          } finally {
            sync.dispose();
          }
          const guest = await instantiateGuest(built.bytes, {
            asynchronous: true,
          });
          try {
            const host = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: async () => {
                await Promise.resolve();
                return 3;
              },
            });
            assert.equal(await guest.callAsync("answer", host), 10);
            const rejected = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: () => Promise.reject(new Error("stored capture rejected")),
            });
            await assert.rejects(guest.callAsync("answer", rejected));
            assert.equal(await guest.callAsync("answer", host), 10);
          } finally {
            guest.dispose();
          }
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            dependencies,
            codegenTier,
            cacheDirectory: false,
            checkpoint,
          });
          try {
            const rebuilt = await restored.build({ sources });
            assert(rebuilt.success, JSON.stringify(rebuilt));
            assert.deepEqual(rebuilt.bytes, built.bytes);
          } finally {
            await restored.dispose();
          }
          for (
            const invalid of [
              older,
              main.replace("return result\n)", "return stored\n)"),
              main.replace(
                "@effect.state Box.get Box.set (fn () => 0)",
                "@effect.provider Box.set (fn callback => ())",
              ),
            ]
          ) {
            const before = await compiler.exportCheckpoint();
            const rejected = await compiler.build({
              sources: { ...sources, [entry]: invalid },
            });
            assert(!rejected.success, JSON.stringify(rejected));
            assert(
              rejected.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
              JSON.stringify(rejected),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), before);
            const recovered = await compiler.build({ sources });
            assert(recovered.success, JSON.stringify(recovered));
            assert.deepEqual(recovered.bytes, built.bytes);
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
