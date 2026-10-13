import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const apply = fn (s: State a) => fn (callback: Unit -> a ! {s.get | e}) => callback ()
`;
const main = `import {State, apply} from "./state"
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use a <- apply left (fn () => left.get ())
      use b <- apply right (fn () => right.get ())
      use next <- host a
      use left.set next
      use c <- apply left (fn () => left.get ())
      return @u32.add (@u32.add a b) c
    let (state, result) = inner
    return result
  let (state, result) = outer
  return result
))
entry const floating = fn () => @effect.scope (fn (s: State F32) => do:
  let (state, result) = do (@effect.state s.get s.set 1.5):
    return apply s (fn () => s.get ())
  return result
)
`;
const unmatched = `import {State, apply} from "./state"
entry const invalid = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  use nested <- do (@effect.state left.get left.set 7):
    return apply left (fn () => right.get ())
  let (state, result) = nested
  return result
))
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`curried scoped capability callbacks retain identity through compiled imports and JSPI (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-curried-",
    });
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
        try {
          const sources = { [entry]: main, [dependency]: library };
          const built = await compiler.build({ sources });
          assert(built.success, JSON.stringify(built));
          const sync = await instantiateGuest(built.bytes);
          try {
            const host = sync.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(sync.call("answer", host), 116);
            assert.equal(sync.call("floating", null), 1.5);
          } finally {
            sync.dispose();
          }
          const guest = await instantiateGuest(built.bytes, {
            asynchronous: true,
          });
          try {
            const host = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                return Number(value) + 2;
              },
            });
            assert.equal(await guest.callAsync("answer", host), 116);
            const rejection = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: () => Promise.reject(new Error("generic scope rejected")),
            });
            await assert.rejects(
              guest.callAsync("answer", rejection),
              (error) => {
                assert.equal(
                  (error as { code: string }).code,
                  "host_exception",
                );
                return true;
              },
            );
            assert.equal(await guest.callAsync("answer", host), 116);
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
          const changed = await compiler.build({
            sources: {
              ...sources,
              [entry]: main.replace("set 7", "set 11"),
            },
          });
          assert(changed.success, JSON.stringify(changed));
          const edited = await instantiateGuest(changed.bytes);
          try {
            const host = edited.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(edited.call("answer", host), 124);
          } finally {
            edited.dispose();
          }
          const reverted = await compiler.build({ sources });
          assert(reverted.success, JSON.stringify(reverted));
          assert.deepEqual(reverted.bytes, built.bytes);
          const beforeUnmatched = await compiler.exportCheckpoint();
          const wrongOwner = await compiler.build({
            sources: { ...sources, [entry]: unmatched },
          });
          assert(!wrongOwner.success, JSON.stringify(wrongOwner));
          assert(
            wrongOwner.diagnostics.some((item) =>
              item.code === "capability_escape"
            ),
            JSON.stringify(wrongOwner),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), beforeUnmatched);
          const afterUnmatched = await compiler.build({ sources });
          assert(afterUnmatched.success, JSON.stringify(afterUnmatched));
          assert.deepEqual(afterUnmatched.bytes, built.bytes);
          if (dependencies === undefined) {
            const before = await compiler.exportCheckpoint();
            const rejected = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  "=> callback ()",
                  `=> do:
  let operation = callback
  return operation ()`,
                ),
              },
            });
            assert(!rejected.success, JSON.stringify(rejected));
            assert(
              rejected.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
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
