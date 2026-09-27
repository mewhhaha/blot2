import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [key: string]: unknown };
type Maybe<T> = { readonly $: "None" } | {
  readonly $: "Some";
  readonly value: T;
};

const lookup = (compiled as unknown as {
  "monomorph.member_target_definition": (
    definitions: BendList<Node>,
    name: string,
  ) => Maybe<Node>;
})["monomorph.member_target_definition"];

const nil = bendList<Node>([]);
const u32: Node = { $: "model.U32Ty" };
const f32: Node = { $: "model.F32Ty" };

function definition(name: string, type: Node): Node {
  return {
    $: "infer.Definition",
    name,
    inference: {
      $: "infer.Inference",
      inferred_type: type,
      coverage: nil,
      exits: nil,
      reflections: nil,
      predicates: nil,
      uses: nil,
    },
  };
}

Deno.test("member target lookup keeps the first definition with a matching name", () => {
  const definitions = bendList([
    definition("other", f32),
    definition("target", u32),
    definition("target", f32),
  ]);
  equal(lookup(definitions, "target"), { $: "Some", value: u32 });
  equal(lookup(definitions, "absent"), { $: "None" });
});

Deno.test("member target lookup handles a wide suffix and a missing name", () => {
  const unrelated = Array.from(
    { length: 12_000 },
    (_, index) => definition(`other.${index}`, f32),
  );
  equal(
    lookup(bendList([definition("target", u32), ...unrelated]), "target"),
    { $: "Some", value: u32 },
  );
  equal(lookup(bendList(unrelated), "target"), { $: "None" });
});
