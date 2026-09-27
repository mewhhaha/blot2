import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
const api = compiled as unknown as {
  "public_exports.select"(
    module: Node,
    bindings: BendList<Node>,
    mode: Node,
  ): Result<Node>;
  "public_exports.select_checked"(module: Node): Node;
  "entry_points.verify"(entries: BendList<Node>, checked: Node): Result<Node>;
};
const unit: Node = { $: "model.UnitTy" };
const u32: Node = { $: "model.U32Ty" };
const closed: Node = { $: "model.ClosedRow" };
const row = (operations: Node[], tail: Node = closed): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail,
});
const pure = row([]);
const tick = row([
  { $: "model.TypeId", module_name: "probe", declaration: "Tick" },
]);
const open = row([], { $: "model.RowVariable", index: 14n });
const arrow = (effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter: unit,
  result: u32,
  effects,
});
const fn = (exported = true): Node => ({
  $: "model.Function",
  name: "answer",
  exported,
  parameter: "argument",
  parameter_type: { $: "None" },
  result_type: { $: "None" },
  body: { $: "model.U32Expr", value: 42 },
});
const binding = (ty: Node): Node => ({
  $: "infer.Binding",
  name: "answer",
  inferred_type: ty,
  variables: bendList([]),
  predicates: bendList([]),
});
const module = (functionValue: Node): Node => ({
  $: "model.Module",
  constants: bendList([]),
  functions: bendList([functionValue]),
  data_types: bendList([]),
  operations: bendList([]),
});
function exported(moduleValue: Node): boolean {
  const functions = bendArray(
    moduleValue.functions as BendList<Node>,
  );
  return functions[0].exported as boolean;
}
function checked(precheckedFunction: Node, effects: Node): Node {
  return {
    $: "model.CheckedModule",
    constants: bendList([]),
    functions: bendList([{
      $: "model.CheckedFunction",
      function: precheckedFunction,
      signature: {
        $: "model.Signature",
        name: "answer",
        parameter: unit,
        result: u32,
        variables: bendList([]),
        effects,
      },
      effects: bendList([]),
    }]),
    data_types: bendList([]),
    operations: bendList([]),
  };
}
const entry = bendList([{
  $: "entry_points.Entry",
  name: "answer",
  runtime: false,
}]);

Deno.test("a provisional open function entry survives until its final pure ABI check", () => {
  const preliminary = api["public_exports.select"](
    module(fn()),
    bendList([binding(arrow(open))]),
    { $: "public_exports.Resolved" },
  );
  equal(preliminary.$, "Done");
  if (preliminary.$ !== "Done") return;
  equal(exported(preliminary.value), true);

  const rawFunction = bendArray(
    preliminary.value.functions as BendList<Node>,
  )[0];
  const final = api["public_exports.select_checked"](
    checked(rawFunction, pure),
  );
  const finalFunction = bendArray(
    final.functions as BendList<Node>,
  )[0];
  equal((finalFunction.function as Node).exported, true);
  equal(api["entry_points.verify"](entry, final).$, "Done");
});

Deno.test("a genuinely unsupported final effect row still rejects the entry", () => {
  const preliminary = api["public_exports.select"](
    module(fn()),
    bendList([binding(arrow(open))]),
    { $: "public_exports.Resolved" },
  );
  equal(preliminary.$, "Done");
  if (preliminary.$ !== "Done") return;
  const rawFunction = bendArray(
    preliminary.value.functions as BendList<Node>,
  )[0];
  const final = api["public_exports.select_checked"](
    checked(rawFunction, tick),
  );
  const finalFunction = bendArray(
    final.functions as BendList<Node>,
  )[0];
  equal((finalFunction.function as Node).exported, false);
  const verified = api["entry_points.verify"](entry, final);
  equal(verified.$, "Fail");
  if (verified.$ === "Fail") equal(verified.error.code, "entry_type");
});

Deno.test("preliminary function selection still requires an inferred binding", () => {
  const selected = api["public_exports.select"](
    module(fn()),
    bendList([]),
    { $: "public_exports.Resolved" },
  );
  equal(selected.$, "Fail");
  if (selected.$ === "Fail") equal(selected.error.code, "internal_error");
});
