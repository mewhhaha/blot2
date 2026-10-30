import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const libraries = {
  parameter: `type State a is effect = {get: Unit -> a, set: a -> Unit}
const first = func (left: State a) => return func (right: State b) => return left.get ()
const second = func (left: State a) => return func (right: State b) => return right.get ()
const shadow = func (input: State a) => return func (input: State b) => return input.get ()
`,
  arrow: `type State a is effect = {get: Unit -> a, set: a -> Unit}
const first: (left: State a) -> ((right: State b) -> a ! {left.get}) = func x => return func y => return x.get ()
const second: (left: State a) -> ((right: State b) -> b ! {right.get}) = func x => return func y => return y.get ()
const shadow: (left: State a) -> ((right: State b) -> b ! {right.get}) = func input => return func input => return input.get ()
`,
};
const main = `import {State, first, second, shadow} from "./state"
entry const answer = func (host: U32 -> U32 ! {Foreign}) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use a <- first left right
      use b <- second left right
      use c <- first right left
      use d <- second right left
      use e <- first left left
      use f <- second right right
      use g <- shadow left right
      use next <- host a
      break @u32.add (@u32.add (@u32.add a b) (@u32.add c d)) (@u32.add (@u32.add (@u32.add e f) g) next)
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
entry const floating = func () => return @effect.scope (func (s: State F32) => return @effect.scope (func (t: State U32) => return do:
  use outer <- do (@effect.state s.get s.set 1.5):
    use inner <- do (@effect.state t.get t.set 100):
      use a <- first s t
      use b <- second t s
      break @f32.add a b
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
`;
const unmatched = `import {State, first} from "./state"
entry const invalid = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  use nested <- do (@effect.state right.get right.set 7):
    break first left right
  let (state, result) = nested
  break result
))
`;
const cases = Object.entries(libraries).flatMap(([syntax, library]) =>
  (["optimized", "development"] as const).map((codegenTier) => ({
    syntax,
    library,
    codegenTier,
  }))
);
for (const { syntax, library, codegenTier } of cases) {
  Deno.test(`paired scoped capability inputs retain positional identities through compiled imports and JSPI (${syntax}, ${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-pair-",
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
            assert.equal(sync.call("answer", host), 430);
            assert.equal(sync.call("floating", null), 3);
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
            assert.equal(await guest.callAsync("answer", host), 430);
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
            assert.equal(await guest.callAsync("answer", host), 430);
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
            assert.equal(edited.call("answer", host), 446);
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
          assert.deepEqual(
            await compiler.exportCheckpoint(),
            beforeUnmatched,
          );
          const afterUnmatched = await compiler.build({ sources });
          assert(afterUnmatched.success, JSON.stringify(afterUnmatched));
          assert.deepEqual(afterUnmatched.bytes, built.bytes);
          if (dependencies === undefined) {
            const before = await compiler.exportCheckpoint();
            let proofFragment = "=> return left.get ()";
            let replacement = `=> return do:
  let operation = left.get
  break operation ()`;
            if (syntax === "arrow") {
              proofFragment = "=> return x.get ()";
              replacement = `=> return do:
  let operation = x.get
  break operation ()`;
            }
            const rejected = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  proofFragment,
                  replacement,
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
