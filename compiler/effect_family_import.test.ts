import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";

Deno.test("imported effect families preserve operation identities across aliases and namespaces", async () => {
  const sources: Readonly<Record<string, string>> = {
    "file:///effect-family/main.blot": `import { State as Cell } from "./state"
import * as state from "./state"

entry const combined = fn () => do:
  let (count, (fraction, observed)) = do (@effect.state (Cell.get U32) (Cell.set U32) 40):
    return do (@effect.state (state.State.get F32) (state.State.set F32) 1.25):
      use old_count <- state.read_count ()
      use old_fraction <- state.read_fraction ()
      use Cell.set U32 (@u32.add old_count 2)
      use state.State.set F32 (@f32.add old_fraction 0.5)
      return @f32.add (@u32.to_f32 old_count) old_fraction
  return @f32.add (@u32.to_f32 count) (@f32.add fraction observed)

entry const answer = fn () => combined ()
entry const expected = combined ()
`,
    "file:///effect-family/state.blot": `type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}

const read_count = fn () => State.get U32 ()
const read_fraction = fn () => State.get F32 ()
`,
  };
  const project = await loadSourceProject(
    new URL("file:///effect-family/main.blot"),
    {
      readSource(url) {
        const source = sources[url.href];
        if (source === undefined) {
          throw new Error(`Missing module: ${url.href}`);
        }
        return Promise.resolve(source);
      },
    },
  );
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(project);
    equal(await native.compile(project), artifact);
    ok(WebAssembly.validate(artifact.bytes));
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 85);
    equal((instance.exports.expected as WebAssembly.Global).value, 85);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
