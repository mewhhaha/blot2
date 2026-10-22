import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `type State a is effect = {get: Unit -> a, set: a -> Unit}
type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
entry const answer = fn () => do:
  let (stored, result) = do (@effect.state Box.get Box.set (fn () => 0)):
    break @effect.scope (fn (s: State U32) => do:
      use previous <- Box.get ()
      use Box.set (fn () => 0)
      break previous ()
    )
  break result
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`direct scope callback retains older State installation (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const compiled = await compiler.build();
      assert(compiled.success, JSON.stringify(compiled));
      for (const jspi of [false, true]) {
        const guest = await instantiateGuest(compiled.bytes, {
          asynchronous: jspi,
        });
        try {
          for (let index = 0; index < 64; index++) {
            {
              let value;
              if (jspi) value = await guest.callAsync("answer", null);
              else value = guest.call("answer", null);
              assert.equal(value, 0);
            }
          }
        } finally {
          guest.dispose();
        }
      }
      const invalid = source.replace(
        "fn () => 0)\n      break",
        "fn () => do (@effect.state s.get s.set 7):\n        break s.get ()\n      )\n      break",
      );
      const rejected = await compiler.build({ sources: { [entry]: invalid } });
      assert(!rejected.success);
      assert(
        rejected.diagnostics.some((issue) =>
          issue.code === "capability_escape"
        ),
        JSON.stringify(rejected),
      );
      const restored = await compiler.build({ sources: { [entry]: source } });
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, compiled.bytes);
    } finally {
      await compiler.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
