import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";
import type { Cst } from "./syntax.ts";

type RawCst = Omit<Cst, "$" | "children"> & {
  readonly $: "cst.Cst";
  readonly children: BendList<RawCst>;
};

const cst = compiled as unknown as {
  "cst.fields"(nodes: BendList<RawCst>, label: string): BendList<RawCst>;
};

Deno.test("CST field selection preserves order without a recursive wide-list stack", () => {
  const nodes = Array.from({ length: 32768 }, (_, index): RawCst => ({
    $: "cst.Cst",
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
