import { deepStrictEqual as equal, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result = { readonly $: "Done"; readonly value: Node } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "types.empty"(): Node;
  "dispatch_resolution.unified"(
    found: Node,
    name: string,
    signature: Node,
    invocation: Node,
    dispatch: Node,
    state: Node,
  ): Result;
};

const u32 = { $: "model.U32Ty" };
const closed = { $: "model.ClosedRow" };
const pure = { $: "model.EffectRow", operations: bendList([]), tail: closed };
const tick = {
  $: "model.EffectRow",
  operations: bendList([
    { $: "model.TypeId", module_name: "probe", declaration: "Tick" },
  ]),
  tail: closed,
};
const binary = (row: Node) => ({
  $: "model.FunctionTy",
  parameter: u32,
  result: { $: "model.FunctionTy", parameter: u32, result: u32, effects: row },
  effects: row,
});

function linked(invocation: Node): Result {
  const binding = {
    $: "infer.Binding",
    name: "pure.add",
    inferred_type: binary(pure),
    variables: bendList([]),
    predicates: bendList([]),
  };
  const state = {
    $: "infer.State",
    substitutions: api["types.empty"](),
    next: 100n,
    annotations: { $: "MTip" },
  };
  return api["dispatch_resolution.unified"](
    { $: "Some", value: binding },
    "pure.add",
    binary(tick),
    invocation,
    { $: "model.BinaryDispatch" },
    state,
  );
}

Deno.test("resolving links the selected pure invocation while retaining a Tick ambient row", () => {
  const selected = linked({ $: "Some", value: pure });
  equal(selected.$, "Done");
  if (selected.$ === "Done") equal(selected.value.signature, binary(pure));

  const mismatched = linked({ $: "Some", value: tick });
  equal(mismatched.$, "Fail");
  if (mismatched.$ === "Fail") equal(mismatched.error.code, "effect_mismatch");

  // Sites without an invocation requirement retain the requested type.
  const ordinary = linked({ $: "None" });
  equal(ordinary.$, "Done");
  if (ordinary.$ === "Done") equal(ordinary.value.signature, binary(tick));
});

const source = (invocation: string) => `
type Tick is effect = Unit -> Unit
const twice: a -> a ! {Tick} where { associated "add" a a a ! {${invocation}} } = fn value => do:
  use Tick ()
  return value + value
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  return twice 21
`;

Deno.test("source keeps a qualified pure add separate from Tick and rejects a Tick claim", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(source(""));
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
    throws(
      () => compiler.compile(source("Tick")),
      (error) =>
        error instanceof SourceError && error.code === "effect_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});
