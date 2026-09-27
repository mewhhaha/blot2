import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as {
  "infer.execution_needs"(uses: BendList<Node>): BendList<Node>;
};

Deno.test("wide execution needs retain predicate and plan order", () => {
  const predicate = (index: bigint): Node => ({
    $: "model.TypeRepPredicate",
    represented: { $: "model.VariableTy", index },
  });
  const plan = (site: bigint, start: number, count: number): Node => ({
    $: "constraints.UsePlan",
    site,
    subject: `site ${site}`,
    instantiated_type: { $: "model.UnitTy" },
    predicates: bendList(
      Array.from(
        { length: count },
        (_, index) => predicate(BigInt(start + index)),
      ),
    ),
  });
  const needs = bendArray(api["infer.execution_needs"](bendList([
    plan(1n, 0, 6_000),
    plan(2n, 6_000, 6_000),
  ])));
  equal(needs.length, 12_000);
  for (const index of [0, 5_999, 6_000, 11_999]) {
    const need = needs[index] as Node;
    equal(need.$, "infer.QualifiedNeed");
    equal(need.site, index < 6_000 ? 1n : 2n);
    const represented = (need.predicate as Node).represented as Node;
    equal(represented.index, BigInt(index));
  }
});
