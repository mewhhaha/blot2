import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";

const source = `
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}
type Get a is effect = Unit -> a

const update = fn () => do:
  use previous <- State.get U32 ()
  use State.set U32 (@u32.add previous 1)
  return previous
const fetch = fn () => Get U32 ()
const invoke_state = fn (callback: Unit -> U32 ! {State U32}) => callback ()
const invoke_get = fn (callback: Unit -> U32 ! {Get U32}) => callback ()
const annotation_only = fn (callback: Unit -> U32 ! {State F32, Get F32}) => 0

const answer = fn () => do:
  let (next, previous) = do (@effect.state (State.get U32) (State.set U32) 41):
    return invoke_state update
  let provider = @effect.provider (Get U32) (fn () => next)
  use current <- do provider:
    return invoke_get fetch
  return @u32.add previous current

const run = fn () => answer ()
const expected = answer ()
`;

function labels(
  row: { readonly operations: readonly { readonly declaration: string }[] },
) {
  return row.operations.map((operation) => operation.declaration).sort();
}

Deno.test("effect family rows expand applied families and execute with providers", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const update = artifact.analysis.functions.find((fn) =>
      fn.name === "update"
    );
    const fetch = artifact.analysis.functions.find((fn) => fn.name === "fetch");
    const invoke_state = artifact.analysis.functions.find((fn) =>
      fn.name === "invoke_state"
    );
    const invoke_get = artifact.analysis.functions.find((fn) =>
      fn.name === "invoke_get"
    );
    const annotation_only = artifact.analysis.functions.find((fn) =>
      fn.name === "annotation_only"
    );
    ok(update);
    ok(fetch);
    ok(invoke_state);
    ok(invoke_get);
    ok(annotation_only);
    equal(labels(update.effect_row), ["State.get<1:i>", "State.set<1:i>"]);
    equal(labels(fetch.effect_row), ["Get<1:i>"]);
    ok(invoke_state.parameter.$ === "FunctionTy");
    ok(invoke_get.parameter.$ === "FunctionTy");
    equal(labels(invoke_state.parameter.effects), [
      "State.get<1:i>",
      "State.set<1:i>",
    ]);
    equal(labels(invoke_get.parameter.effects), ["Get<1:i>"]);
    ok(annotation_only.parameter.$ === "FunctionTy");
    equal(labels(annotation_only.parameter.effects), [
      "Get<1:f>",
      "State.get<1:f>",
      "State.set<1:f>",
    ]);

    ok(WebAssembly.validate(artifact.bytes));
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.run as CallableFunction)(), 83);
    equal((instance.exports.expected as WebAssembly.Global).value, 83);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
