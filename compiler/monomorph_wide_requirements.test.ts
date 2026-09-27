import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as {
  "monomorph.requirements"(coverage: BendList<Node>): BendList<Node>;
};
const nil = bendList<Node>([]);
const u32: Node = { $: "model.U32Ty" };
const pure: Node = {
  $: "model.EffectRow",
  operations: nil,
  tail: { $: "model.ClosedRow" },
};
const typeId: Node = {
  $: "model.TypeId",
  module_name: "test",
  declaration: "Op",
};

function coverage(index: number): Node {
  const identity = BigInt(index);
  switch (index % 4) {
    case 0:
      return {
        $: "infer.OperationNeed",
        identity,
        template: typeId,
        arguments: nil,
        function_type: u32,
        subject: `operation ${index}`,
      };
    case 1:
      return {
        $: "infer.AssociatedNeed",
        identity,
        dispatch: { $: "model.BinaryDispatch" },
        member: "add",
        templates: nil,
        left: u32,
        right: u32,
        result: u32,
        invocation: { $: "None" },
        ambient: pure,
        subject: `associated ${index}`,
      };
    case 2:
      return {
        $: "infer.QualifiedNeed",
        site: identity,
        predicate: { $: "model.TypeRepPredicate", represented: u32 },
        subject: `qualified ${index}`,
      };
    default:
      return {
        $: "infer.ValuePatternType",
        inferred_type: u32,
        subject: `other ${index}`,
      };
  }
}

Deno.test("wide requirement filtering retains every kind in source order", () => {
  const input = Array.from({ length: 12_000 }, (_, index) => coverage(index));
  const actual = bendArray(api["monomorph.requirements"](bendList(input)));
  equal(actual, input.filter((_, index) => index % 4 !== 3));
});
