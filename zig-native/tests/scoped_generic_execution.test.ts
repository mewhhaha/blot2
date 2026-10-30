import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
const local = func (value: a) => return @effect.scope (func (s: State a) => return do:
  let (state, result) = do (@effect.state s.get s.set value):
    break s.get ()
  break result
)
const pair = func (value: a) => return @effect.scope (func (left: State a) => return @effect.scope (func (right: State a) => return do:
  let (outer, result) = do (@effect.state left.get left.set value):
    use nested <- do (@effect.state right.get right.set value):
      use a <- left.get ()
      use b <- right.get ()
      break #[a, b]
    let (inner, reads) = nested
    break reads
  break result
))
`;
const main = `
import {local, pair} from "./library"
entry const integer = func () => return local 7
entry const fraction = func () => return local 1.5
entry const integers = func () => return pair 7
entry const fractions = func () => return pair 1.5
`;

Deno.test("symbolic scoped factories preserve source dependency and retained specialization identity", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scoped-generic-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/library.blot`;
  const archive = `${directory}/library.blotdep`;
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
      for (const codegenTier of ["optimized", "development"] as const) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false,
        });
        try {
          for (const value of [7, 8, 7]) {
            const sources = {
              [entry]: main.replaceAll("local 7", `local ${value}`).replaceAll(
                "pair 7",
                `pair ${value}`,
              ),
            };
            const built = await compiler.build({ sources });
            assert(built.success, JSON.stringify(built));
            const guest = await instantiateGuest(built.bytes);
            try {
              for (let i = 0; i < 5; i++) {
                assert.equal(guest.call("integer", null), value);
                assert.equal(guest.call("fraction", null), 1.5);
                assert.deepEqual(
                  Array.from(guest.call("integers", null) as Uint32Array),
                  [value, value],
                );
                assert.deepEqual(
                  Array.from(guest.call("fractions", null) as Float32Array),
                  [1.5, 1.5],
                );
              }
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
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
