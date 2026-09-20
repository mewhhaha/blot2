import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, bendList } from "./bend_list.ts";
import type { Cst, CstList } from "./syntax.ts";

const cst = compiled as unknown as {
  "cst.fields"(nodes: CstList, label: string): CstList;
};

Deno.test("CST field selection preserves order without a recursive wide-list stack", () => {
  const nodes = Array.from({ length: 32768 }, (_, index): Cst => ({
    $: "Cst",
    kind: "INTEGER",
    field: index % 3 === 0 ? "elements" : "separator",
    text: String(index),
    offset: BigInt(index),
    children: { $: "Nil" },
  }));
  const children = bendList(nodes);
  for (const label of ["elements", "separator", "absent"]) {
    equal(
      bendArray(cst["cst.fields"](children, label)),
      nodes.filter((node) => node.field === label),
    );
  }
  equal(cst["cst.fields"]({ $: "Nil" }, "elements"), { $: "Nil" });
});
