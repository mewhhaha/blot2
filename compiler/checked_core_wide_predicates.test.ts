import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as {
  "checked_core.same_predicates"(
    left: BendList<Node>,
    right: BendList<Node>,
  ): boolean;
};

Deno.test("checked interfaces compare a wide ordered predicate list without stack growth", () => {
  const u32: Node = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.U32Ty" },
  };
  const f32: Node = {
    $: "model.TypeRepPredicate",
    represented: { $: "model.F32Ty" },
  };
  const ordered = Array.from({ length: 12_000 }, () => u32);
  const left = bendList(ordered);
  equal(api["checked_core.same_predicates"](left, bendList(ordered)), true);
  equal(
    api["checked_core.same_predicates"](
      left,
      bendList([...ordered.slice(0, -1), f32]),
    ),
    false,
  );
  equal(
    api["checked_core.same_predicates"](left, bendList([...ordered, u32])),
    false,
  );
});
