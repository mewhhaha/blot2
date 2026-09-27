import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const exact = api["type_eq_evidence.exact_type_constructor"] as (
  types: Node,
) => boolean;
const nil = bendList<Node>([]);
const id = (name: string, module_name = "std/prelude"): Node => ({
  $: "model.TypeId",
  module_name,
  declaration: name,
});
const canonical: Node = {
  $: "model.Constructor",
  name: "$prelude.Type",
  payload: { $: "Some", value: { $: "model.ParameterTy", index: 0n } },
  fields: nil,
};
const declaration = (
  constructors: Node[],
  module_name = "std/prelude",
): Node => ({
  $: "model.DataType",
  identity: id("Type", module_name),
  parameters: 1n,
  constructors: bendList(constructors),
});

Deno.test("Type.eq certificate requires one canonical Type owner and no competing constructor", () => {
  equal(exact(bendList([declaration([canonical])])), true);
  equal(
    exact(bendList([
      declaration([canonical, {
        $: "model.Constructor",
        name: "$prelude.Other",
        payload: { $: "None" },
        fields: nil,
      }]),
    ])),
    false,
  );
  equal(exact(bendList([declaration([canonical]), declaration([])])), false);
  equal(
    exact(bendList([
      declaration([canonical]),
      declaration([canonical], "main"),
    ])),
    false,
  );
});
