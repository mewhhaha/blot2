import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const chooseBody =
  `const choose = fn flag => fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = if flag then left else right
  let alias = identity selected
  use outer <- do (@effect.state left.get left.set 7):
    use inner <- do (@effect.state right.get right.set 100):
      use chosen <- do (@effect.state selected.get selected.set 41):
        use a <- read alias
        use next <- host a
        use alias.set next
        use b <- alias.get ()
        use c <- left.get ()
        use d <- right.get ()
        break @u32.add (@u32.add b c) d
      let (state, result) = chosen
      break result
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
const settle = fn initial => @effect.scope (fn (left: State a) => @effect.scope (fn (right: State a) => do:
  let selected = if #True then left else right
  let (state, result) = do (@effect.state selected.get selected.set initial):
    use selected.set 7
    break read selected
  break result
))
const floating_choose = fn flag => @effect.scope (fn (left: State F32) => @effect.scope (fn (right: State F32) => do:
  let selected = if flag then left else right
  use outer <- do (@effect.state left.get left.set 1.5):
    use inner <- do (@effect.state right.get right.set 2.5):
      use chosen <- do (@effect.state selected.get selected.set 4.5):
        use a <- read selected
        use b <- left.get ()
        use c <- right.get ()
        break @f32.add (@f32.add a b) c
      let (state, result) = chosen
      break result
    let (state, result) = inner
    break result
  let (state, result) = outer
  break result
))
`;
const libraries = {
  parameter: `type State a is effect = {get: Unit -> a, set: a -> Unit}
const read = fn (state: State a) => state.get ()
const identity = fn value => value
${chooseBody}`,
  arrow: `type State a is effect = {get: Unit -> a, set: a -> Unit}
const read: (state: State a) -> a ! {state.get} = fn input => input.get ()
const identity = fn value => value
${chooseBody}`,
};
const main = `import {choose, floating_choose, settle} from "./state"
entry const answer = fn host => choose #True host
entry const other = fn host => choose #False host
entry const floating = fn () => floating_choose #False
entry const settled = fn (value: U32) => settle value
`;
const unmatched = `import {State} from "./state"
entry const invalid = fn flag => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = if flag then left else right
  use nested <- do (@effect.state selected.get selected.set 7):
    break left.get ()
  let (state, result) = nested
  break result
))
`;
const rejectedSelections = [
  { code: "capability_escape", body: "break selected" },
  { code: "capability_escape", body: "break [selected]" },
  { code: "capability_escape", body: "break selected.get" },
  { code: "capability_escape", body: "break fn () => selected.get ()" },
  {
    code: "capability_escape",
    body: `let independent = if flag then left else right
  use nested <- do (@effect.state selected.get selected.set 7):
    break independent.get ()
  let (state, result) = nested
  break result`,
  },
  {
    code: "capability_escape",
    body: `let later = fn () => if flag then left else right
  break later`,
  },
  {
    code: "effect_identity_scope",
    body: `for index in 0..2:
    let repeated = if flag then left else right
  break 42`,
  },
];
const cases = Object.entries(libraries).flatMap(([syntax, library]) =>
  (["optimized", "development"] as const).map((codegenTier) => ({
    syntax,
    library,
    codegenTier,
  }))
);
for (const { syntax, library, codegenTier } of cases) {
  Deno.test(`selected scoped capability values retain exact terms through compiled imports and JSPI (${syntax}, ${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-selection-",
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
            assert.equal(sync.call("answer", host), 186);
            assert.equal(sync.call("other", host), 93);
            assert.equal(sync.call("floating", null), 10.5);
            assert.equal(sync.call("settled", 42), 7);
            assert.equal(sync.call("settled", 99), 7);
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
            assert.equal(await guest.callAsync("answer", host), 186);
            assert.equal(await guest.callAsync("other", host), 93);
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
            assert.equal(await guest.callAsync("answer", host), 186);
            assert.equal(await guest.callAsync("other", host), 93);
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
              [dependency]: library.replace("set 41", "set 43"),
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
            assert.equal(edited.call("answer", host), 190);
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
          for (const rejectedSelection of rejectedSelections) {
            const badSource = `import {State} from "./state"
entry const invalid = fn flag => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = if flag then left else right
  ${rejectedSelection.body}
))
`;
            const rejected = await compiler.build({
              sources: { ...sources, [entry]: badSource },
            });
            assert(!rejected.success, JSON.stringify(rejected));
            assert(
              rejected.diagnostics.some((item) =>
                item.code === rejectedSelection.code
              ),
              JSON.stringify(rejected),
            );
            assert.deepEqual(
              await compiler.exportCheckpoint(),
              beforeUnmatched,
            );
          }
          const afterUnmatched = await compiler.build({ sources });
          assert(afterUnmatched.success, JSON.stringify(afterUnmatched));
          assert.deepEqual(afterUnmatched.bytes, built.bytes);
          if (dependencies === undefined) {
            const before = await compiler.exportCheckpoint();
            let fragment = "=> state.get ()";
            let replacement = `=> do:
  let operation = state.get
  break operation ()`;
            if (syntax === "arrow") {
              fragment = "=> input.get ()";
              replacement = `=> do:
  let operation = input.get
  break operation ()`;
            }
            const rejected = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  fragment,
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
