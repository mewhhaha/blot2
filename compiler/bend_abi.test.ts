import {
  deepStrictEqual as equal,
  notStrictEqual,
  strictEqual,
  throws,
} from "node:assert/strict";
import {
  fromBendModel,
  fromBendValue,
  toBendCst,
  toBendModel,
} from "./bend_abi.ts";

Deno.test("the JS boundary qualifies Data without changing public values or sharing", () => {
  const shared = { $: "TypeId", module_name: "m", declaration: "T" };
  const publicValue = {
    $: "Module",
    data_types: { $: "Con", head: shared, tail: { $: "Nil" } },
    operations: { $: "Con", head: shared, tail: { $: "Nil" } },
    label: "model.TypeId",
  };
  const raw = toBendModel(publicValue);
  notStrictEqual(raw, publicValue);
  equal(raw.$, "model.Module");
  equal(raw.data_types.$, "Con");
  equal(raw.data_types.head.$, "model.TypeId");
  strictEqual(raw.data_types.head, raw.operations.head);
  equal(publicValue.data_types.head.$, "TypeId");
  equal(raw.label, "model.TypeId");
  equal(fromBendModel(raw), publicValue);
  throws(
    () => toBendModel({ $: "OtherModuleOnly" }),
    /Unknown model constructor/,
  );
});

Deno.test("Cst and constant values use their own Bend namespaces", () => {
  const cst = { $: "Cst", text: "cst.Cst", children: { $: "Nil" } };
  equal(toBendCst(cst), { ...cst, $: "cst.Cst" });
  equal(cst.$, "Cst");
  equal(
    fromBendValue({
      $: "const_eval.DataValue",
      identity: { $: "model.TypeId", module_name: "m", declaration: "T" },
      payload: { $: "None" },
    }),
    {
      $: "DataValue",
      identity: { $: "TypeId", module_name: "m", declaration: "T" },
      payload: { $: "None" },
    },
  );
});

Deno.test("long Bend lists cross the boundary without recursive traversal", () => {
  let value: { $: string; head?: unknown; tail?: unknown } = { $: "Nil" };
  for (let index = 0; index < 20_000; index++) {
    value = { $: "Con", head: { $: "UnitTy" }, tail: value };
  }
  const converted = toBendModel(value);
  equal(converted.$, "Con");
  equal((converted.head as { $: string }).$, "model.UnitTy");
});
