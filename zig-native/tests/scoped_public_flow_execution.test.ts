import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `const identity = fn value => value
const invoke = fn callback => callback ()
`;
const main = `import {identity, invoke} from "./flow"
type State a is effect = {get: Unit -> a, set: a -> Unit}
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (s: State U32) => do:
  let capability = identity s
  use nested <- do (@effect.state capability.get capability.set 7):
    return invoke (identity (fn () => do:
      use value <- capability.get ()
      use next <- host value
      use capability.set next
      return capability.get ()
    ))
  let (state, result) = nested
  return result
)
entry const floating = fn () => @effect.scope (fn (s: State F32) => do:
  let capability = identity s
  let (state, result) = do (@effect.state capability.get capability.set 1.5):
    return invoke (identity capability.get)
  return result
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`owned scoped public flow survives dependencies edits JSPI and checkpoints (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-scoped-flow-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/flow.blot`;
    const archive = `${directory}/flow.blotdep`;
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
          const synchronous = await instantiateGuest(built.bytes);
          try {
            const host = synchronous.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(synchronous.call("answer", host), 9);
            assert.equal(synchronous.call("floating", null), 1.5);
          } finally {
            synchronous.dispose();
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
            assert.equal(await guest.callAsync("answer", host), 9);
            const rejection = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: () => Promise.reject(new Error("public flow rejected")),
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
            assert.equal(await guest.callAsync("answer", host), 9);
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
          const escaped = await compiler.build({
            sources: {
              ...sources,
              [entry]: main +
                `entry const escaped = fn () => @effect.scope (fn (s: State U32) => identity s)\n`,
            },
          });
          assert(!escaped.success, JSON.stringify(escaped));
          assert(
            escaped.diagnostics.some((item) =>
              item.code === "capability_escape"
            ),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          if (dependencies === undefined) {
            // The ordinary type header stays a -> a. The public flow proof
            // changes and must invalidate a retained caller admission.
            const rejected = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  "fn value => value",
                  `fn value => do:
  let same = value
  return same`,
                ),
              },
            });
            assert(!rejected.success, JSON.stringify(rejected));
            assert(
              rejected.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          }
          const recovered = await compiler.build({ sources });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
        } finally {
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
