import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
entry const operation = fn () => @effect.scope (fn (s: State U32) => do:
  let (state, result) = do (@effect.state s.get s.set 7):
    break (fn callback => callback ()) s.get
  break result
)
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (s: State U32) => do:
  use nested <- do (@effect.state s.get s.set 7):
    break (fn callback => callback ()) (fn () => do:
      use previous <- s.get ()
      use next <- host previous
      use s.set next
      break s.get ()
    )
  let (state, result) = nested
  break result
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`direct scoped callback adapter borrows authority through sync JSPI and checkpoints (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-callback-",
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
      const synchronousGuest = await instantiateGuest(built.bytes);
      try {
        const host = synchronousGuest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => Number(value) + 2,
        });
        assert.equal(synchronousGuest.call("answer", host), 9);
        assert.equal(synchronousGuest.call("operation", null), 7);
      } finally {
        synchronousGuest.dispose();
      }
      const guest = await instantiateGuest(built.bytes, { asynchronous: true });
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
          call: () => Promise.reject(new Error("callback adapter rejected")),
        });
        await assert.rejects(guest.callAsync("answer", rejection), (error) => {
          assert.equal((error as { code: string }).code, "host_exception");
          return true;
        });
        assert.equal(await guest.callAsync("answer", host), 9);
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
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
