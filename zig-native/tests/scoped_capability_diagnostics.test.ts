import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const declarations = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
type Save a is effect = {keep: (Unit -> a) -> Unit}
`;
const escaping = `
import {State, Save} from "./library"
entry const bad = fn () => do:
  let (saved, result) = @state.run (fn () => 0) (fn () => do (@effect.provider (Save.keep U32) (fn value => @state.set value)):
    return @effect.scope (fn (s: State U32) => do:
      use Save.keep U32 (fn () => do:
        let (state, result) = do (@effect.state s.get s.set 0):
          return 42
        return result
      )
      return 42
    )
  )
  return saved ()
`;
const valid = `
import {State, Save} from "./library"
entry const answer = fn () => @effect.scope (fn (s: State U32) => 42)
`;

Deno.test("explicit generic operations reject shorter authority at source and compiled storage sinks", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scoped-store-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/library.blot`;
  const archive = `${directory}/library.blotdep`;
  try {
    await Deno.writeTextFile(entry, valid);
    await Deno.writeTextFile(dependency, declarations);
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
        cacheDirectory: false,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: valid } });
        assert(built.success, JSON.stringify(built));
        const checkpoint = await compiler.exportCheckpoint();
        const rejected = await compiler.build({
          sources: { [entry]: escaping },
        });
        assert(!rejected.success);
        const diagnostic = rejected.diagnostics.find((item) =>
          item.code === "capability_escape"
        );
        assert(diagnostic, JSON.stringify(rejected));
        assert.equal(diagnostic.filename, entry);
        assert(
          escaping.slice(diagnostic.start, diagnostic.end).includes(
            "fn () => do:",
          ),
        );
        assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
        const recovered = await compiler.build({ sources: { [entry]: valid } });
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
