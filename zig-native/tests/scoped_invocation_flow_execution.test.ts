import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const header = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const first = fn callback => fn left => fn right => callback ()
const shadow = fn callback => fn callback => fn unused => callback ()
`;
const libraries = {
  parameter: header +
    `const invoke = fn (left: State a) => fn (right: State b) => fn (callback: Unit -> U32 ! {left.get, right.get | e}) => callback ()
`,
  arrow: header +
    `const invoke: (left: State a) -> ((right: State b) -> ((Unit -> U32 ! {left.get, right.get | e}) -> U32 ! {left.get, right.get | e})) = fn x => fn y => fn callback => callback ()
`,
};
const main = `import {State, invoke, first, shadow} from "./state"
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use a <- invoke left right (fn () => do:
        use x <- left.get ()
        use y <- right.get ()
        use z <- host x
        break @u32.add z y
      )
      use b <- invoke right left (fn () => do:
        use x <- right.get ()
        use y <- left.get ()
        break @u32.add x y
      )
      use c <- first (fn () => left.get ()) left left
      use d <- first (fn () => left.get ()) left right
      use e <- shadow left (fn () => right.get ()) right
      break @u32.add (@u32.add a b) (@u32.add c (@u32.add d e))
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
entry const mixed = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State F32) => do:
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 1.5):
      break invoke left right (fn () => do:
        use value <- left.get ()
        use ignored <- right.get ()
        break host value
      )
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
entry const repeated = fn () => @effect.scope (fn (state: State U32) => do:
  use outer <- do (@effect.state state.get state.set 7):
    use inner <- do (@effect.state state.get state.set 11):
      break invoke state state (fn () => do:
        use x <- state.get ()
        use y <- state.get ()
        break @u32.add x y
      )
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
)
`;
const unmatched = `import {State, invoke} from "./state"
entry const invalid = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  use handled <- do (@effect.state left.get left.set 7):
    break invoke left right (fn () => do:
      use x <- left.get ()
      use y <- right.get ()
      break @u32.add x y
    )
  let (state, result) = handled
  break result
))
`;
for (const [syntax, library] of Object.entries(libraries)) {
  for (const codegenTier of ["optimized", "development"] as const) {
    Deno.test(`multi-input Unit invocation preserves exact callback owners (${syntax}, ${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-scoped-invoke-",
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
            const sync = await instantiateGuest(built.bytes);
            try {
              const host = sync.capability({
                parameter: "U32",
                result: "U32",
                call: (value) => Number(value) + 2,
              });
              assert.equal(sync.call("answer", host), 330);
              assert.equal(sync.call("mixed", host), 9);
              assert.equal(sync.call("repeated", null), 22);
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
              assert.equal(await guest.callAsync("answer", host), 330);
              assert.equal(await guest.callAsync("mixed", host), 9);
              const rejected = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                call: () => Promise.reject(new Error("invocation rejected")),
              });
              await assert.rejects(
                guest.callAsync("answer", rejected),
                (error) => {
                  assert.equal(
                    (error as { code: string }).code,
                    "host_exception",
                  );
                  return true;
                },
              );
              assert.equal(await guest.callAsync("answer", host), 330);
            } finally {
              guest.dispose();
            }
            const checkpoint = await compiler.exportCheckpoint();
            const invalid = await compiler.build({
              sources: { ...sources, [entry]: unmatched },
            });
            assert(!invalid.success);
            assert.equal(invalid.diagnostics[0].code, "capability_escape");
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
            const duplicate = await compiler.build({
              sources: {
                ...sources,
                [entry]: unmatched.replaceAll(
                  "invoke left right",
                  "invoke left left",
                ).replaceAll("use y <- right.get ()", "use y <- left.get ()"),
              },
            });
            assert(!duplicate.success);
            assert.equal(duplicate.diagnostics[0].code, "capability_escape");
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
            const lost = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  "=> callback ()",
                  "=> do:\n  let saved = callback\n  break saved ()",
                ),
              },
            });
            assert(!lost.success);
            assert.equal(lost.diagnostics[0].code, "capability_escape");
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
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
              assert.equal(edited.call("answer", host), 346);
            } finally {
              edited.dispose();
            }
            const reverted = await compiler.build({ sources });
            assert(reverted.success, JSON.stringify(reverted));
            assert.deepEqual(reverted.bytes, built.bytes);
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
              const result = await restored.build({ sources });
              assert(result.success, JSON.stringify(result));
              assert.deepEqual(result.bytes, built.bytes);
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
}
