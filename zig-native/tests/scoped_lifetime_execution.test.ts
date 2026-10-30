import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
entry const answer = func () => return @effect.scope (func (left: State U32) => return do:
  let longer = @effect.scope (func (right: State U32) => return {saved: left})
  let read = longer.saved.get
  let (state, result) = do (@effect.state longer.saved.get longer.saved.set 7):
    break read ()
  break result
)
entry const array = func () => return @effect.scope (func (left: State U32) => return do:
  let longer = @effect.scope (func (right: State U32) => return #[left])
  let selected = @array.get longer 0
  let (state, result) = do (@effect.state selected.get selected.set 9):
    break selected.get ()
  break result
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`nested scope exit preserves longer lived structural authority (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-lifetime-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const sources = { [entry]: source };
      const built = await compiler.build({ sources });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (let i = 0; i < 10; i++) {
          assert.equal(guest.call("answer", null), 7);
          assert.equal(guest.call("array", null), 9);
        }
      } finally {
        guest.dispose();
      }
      const checkpoint = await compiler.exportCheckpoint();
      const restored = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
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
      const rejected = await compiler.build({
        sources: { [entry]: source.replace("{saved: left}", "{saved: right}") },
      });
      assert(!rejected.success);
      assert.equal(rejected.diagnostics[0].code, "capability_escape");
      assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
