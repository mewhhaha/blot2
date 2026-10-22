import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
entry const pure = fn () => do:
  let callback = @effect.scope (fn (s: State U32) => fn () => 42)
  break callback ()
entry const capture = fn (value: U32) => do:
  let callback = @effect.scope (fn (s: State U32) => fn () => @u32.add value 1)
  break callback ()
entry const outer = fn () => @effect.scope (fn (left: State U32) => do:
  let read = left.get
  let write = left.set
  let callback = @effect.scope (fn (right: State U32) => fn () => do:
    let (state, result) = do (@effect.state read write 7):
      break read ()
    break result
  )
  break callback ()
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`returned source closure footprints preserve data and longer lived captures (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-closure-",
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
          assert.equal(guest.call("pure", null), 42);
          assert.equal(guest.call("capture", i), i + 1);
          assert.equal(guest.call("outer", null), 7);
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
      const captured = source.replace(
        "fn () => 42)",
        `fn () => do:
    let (state, result) = do (@effect.state s.get s.set 0):
      break 42
    break result
  )`,
      );
      const rejected = await compiler.build({ sources: { [entry]: captured } });
      assert(!rejected.success);
      assert.equal(rejected.diagnostics[0].code, "capability_escape");
      assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
