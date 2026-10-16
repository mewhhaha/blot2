import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const identity = fn value => value
const invoke = fn callback => callback ()
const read = fn unused => fn (state: State a) => fn () => state.get ()
const typed_read: (unused: State b) -> ((state: State a) -> (Unit -> a ! {state.get})) = fn x => fn y => fn () => y.get ()
`;
const main = `import {State, identity, invoke, read, typed_read} from "./flow"
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
entry const borrowed = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (older: State U32) => do:
  let callback = @effect.scope (fn (younger: State F32) => read younger older)
  let typed = @effect.scope (fn (younger: State U32) => typed_read younger older)
  use handled <- do (@effect.state older.get older.set 7):
    use a <- callback ()
    use b <- typed ()
    return host (@u32.add a b)
  let (state, result) = handled
  return result
)
entry const borrowed_float = fn () => @effect.scope (fn (older: State F32) => do:
  let callback = @effect.scope (fn (younger: State U32) => read younger older)
  let (state, result) = do (@effect.state older.get older.set 1.5):
    return callback ()
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
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
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
            assert.equal(synchronous.call("borrowed", host), 16);
            assert.equal(synchronous.call("borrowed_float", null), 1.5);
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
            assert.equal(await guest.callAsync("borrowed", host), 16);
            assert.equal(await guest.callAsync("borrowed_float", null), 1.5);
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
            await assert.rejects(
              guest.callAsync("borrowed", rejection),
              (error) => {
                assert.equal(
                  (error as { code: string }).code,
                  "host_exception",
                );
                return true;
              },
            );
            assert.equal(await guest.callAsync("borrowed", host), 16);
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
          for (
            const invalid of [
              `entry const escaped_factory = fn () => @effect.scope (fn (s: State U32) => read s s)\n`,
              `entry const escaped_selection = fn () => @effect.scope (fn (older: State U32) => @effect.scope (fn (younger: State U32) => read older (if #True then older else younger)))\n`,
              `entry const escaped_deferred = fn () => @effect.scope (fn (older: State U32) => do:
  let callback = @effect.scope (fn (younger: State U32) => read (fn () => younger.get ()) older)
  let (state, result) = do (@effect.state older.get older.set 7):
    return callback ()
  return result
)\n`,
            ]
          ) {
            const rejected = await compiler.build({
              sources: { ...sources, [entry]: main + invalid },
            });
            assert(!rejected.success, JSON.stringify(rejected));
            assert(
              rejected.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          }
          const savedCaptureSources = {
            ...sources,
            [dependency]: library.replace(
              "fn () => state.get ()",
              "fn () => do:\n  let saved = state\n  return saved.get ()",
            ),
          };
          const savedCapture = await compiler.build({
            sources: savedCaptureSources,
          });
          assert(savedCapture.success, JSON.stringify(savedCapture));
          const freshCapture = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            codegenTier,
            dependencies,
            cacheDirectory: false,
          });
          try {
            const expected = await freshCapture.build({
              sources: savedCaptureSources,
            });
            assert(expected.success, JSON.stringify(expected));
            assert.deepEqual(savedCapture.bytes, expected.bytes);
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(savedCapture.bytes, {
                asynchronous,
              });
              try {
                const host = guest.capability({
                  parameter: "U32",
                  result: "U32",
                  call: (value) => Number(value) + 2,
                });
                if (asynchronous) {
                  assert.equal(await guest.callAsync("borrowed", host), 16);
                } else assert.equal(guest.call("borrowed", host), 16);
              } finally {
                guest.dispose();
              }
            }
          } finally {
            await freshCapture.dispose();
          }
          if (dependencies === undefined) {
            // Local aliases preserve the exact input owner. A same-header
            // body edit must reconstruct that flow and agree with fresh code.
            const aliases = {
              ...sources,
              [dependency]: library.replace(
                "fn value => value",
                `fn value => do:
  let same = value
  return same`,
              ),
            };
            const retained = await compiler.build({ sources: aliases });
            assert(retained.success, JSON.stringify(retained));
            const fresh = await createZigProjectCompiler({
              executable,
              entry,
              prelude: null,
              codegenTier,
              cacheDirectory: false,
            });
            try {
              const expected = await fresh.build({ sources: aliases });
              assert(expected.success, JSON.stringify(expected));
              assert.deepEqual(retained.bytes, expected.bytes);
              const guest = await instantiateGuest(retained.bytes);
              try {
                const host = guest.capability({
                  parameter: "U32",
                  result: "U32",
                  call: (value) => Number(value) + 2,
                });
                assert.equal(guest.call("answer", host), 9);
                assert.equal(guest.call("borrowed", host), 16);
              } finally {
                guest.dispose();
              }
            } finally {
              await fresh.dispose();
            }
          }
          const changed = await compiler.build({
            sources: {
              ...sources,
              [entry]: main.replaceAll("set 7", "set 11"),
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
            assert.equal(edited.call("answer", host), 13);
            assert.equal(edited.call("borrowed", host), 24);
          } finally {
            edited.dispose();
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
