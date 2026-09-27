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
  "public_exports.unchecked_module"(module: Node): Node;
};
const none: Node = { $: "None" };
const pure: Node = {
  $: "model.EffectRow",
  operations: bendList([]),
  tail: { $: "model.ClosedRow" },
};
const u32: Node = { $: "model.U32Ty" };
const unit: Node = { $: "model.UnitTy" };
const variable: Node = { $: "model.VariableTy", index: 0n };
const arrow = (parameter: Node, result: Node, effects: Node = pure): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const fn = (name: string): Node => ({
  $: "model.Function",
  name,
  exported: true,
  parameter: "argument",
  parameter_type: none,
  result_type: none,
  body: { $: "model.U32Expr", value: 7 },
});
const constant = (name: string): Node => ({
  $: "model.Constant",
  name,
  exported: true,
  annotation: none,
  value: { $: "model.UnitExpr" },
});
const binding = (name: string, ty: Node, variables: bigint[] = []): Node => ({
  $: "infer.Binding",
  predicates: { $: "Nil" },

  name,
  inferred_type: ty,
  variables: bendList(variables),
});
const signature = (name: string, ty: Node, variables: bigint[] = []): Node => {
  if (ty.$ !== "model.FunctionTy") {
    throw new Error("function signature needs arrow");
  }
  return {
    $: "model.Signature",
    name,
    parameter: ty.parameter,
    result: ty.result,
    variables: bendList(variables),
    effects: ty.effects,
  };
};
function checkedFunction(name: string, ty: Node, variables: bigint[] = []) {
  return {
    $: "model.CheckedFunction",
    function: fn(name),
    signature: signature(name, ty, variables),
    effects: bendList([]),
  };
}
function checkedConstant(name: string, ty: Node, variables: bigint[] = []) {
  return {
    $: "model.CheckedConstant",
    constant: constant(name),
    inferred_type: ty,
    variables: bendList(variables),
  };
}
function moduleOf(functions: Node[], constants: Node[]) {
  return {
    $: "model.CheckedModule",
    constants: bendList(constants),
    functions: bendList(functions),
    data_types: bendList([]),
    operations: bendList([]),
  };
}
function legacySelected(checked: Node, bindings: Node[]): Node {
  const input = api["public_exports.unchecked_module"](checked);
  const result = api["public_exports.select"](
    input,
    bendList(bindings),
    { $: "public_exports.Resolved" },
  );
  if (result.$ === "Fail") throw new Error(String(result.error));
  return result.value;
}

Deno.test("checked-driven export selection matches resolved selection for ABI-ready signatures", () => {
  const cases: Array<[Node[], Node[], Node[]]> = [
    [
      [checkedFunction("plain", arrow(u32, u32))],
      [checkedConstant("number", u32)],
      [binding("plain", arrow(u32, u32)), binding("number", u32)],
    ],
    [
      [],
      [checkedConstant("factory", arrow(u32, u32))],
      [binding("factory", arrow(u32, u32))],
    ],
  ];
  for (const [functions, constants, bindings] of cases) {
    const checked = moduleOf(functions, constants);
    const selected = api["public_exports.select_checked"](checked);
    equal(
      api["public_exports.unchecked_module"](selected),
      legacySelected(checked, bindings),
    );
  }
});

Deno.test("resolved pre-check intent is distinct from final ABI rejection", () => {
  const open: Node = {
    $: "model.EffectRow",
    operations: bendList([]),
    tail: { $: "model.RowVariable", index: 1n },
  };
  const cases: Array<[string, Node, bigint[]]> = [
    ["open_effect", arrow(unit, u32, open), []],
    ["generic", arrow(variable, variable), [0n]],
  ];
  for (const [name, ty, variables] of cases) {
    const checked = moduleOf([checkedFunction(name, ty, variables)], []);
    const preliminary = legacySelected(checked, [binding(name, ty, variables)]);
    const preliminaryFunction = bendArray(
      preliminary.functions as BendList<Node>,
    )[0];
    equal(preliminaryFunction.exported, true);

    // The inferred signature can still change after this pre-check. Its
    // unresolved form cannot pass the final guest ABI check unchanged.
    const final = api["public_exports.select_checked"](checked);
    const finalFunction = bendArray(
      final.functions as BendList<Node>,
    )[0] as Node;
    equal((finalFunction.function as Node).exported, false);
  }
});

Deno.test("checked callable-constant wrapper has the inferred signature", () => {
  const checked = moduleOf([], [checkedConstant("factory", arrow(u32, u32))]);
  const selected = api["public_exports.select_checked"](checked);
  const functions = bendArray(
    (selected as unknown as { functions: BendList<Node> }).functions,
  );
  equal(functions.length, 1);
  equal((functions[0] as unknown as { signature: Node }).signature, {
    $: "model.Signature",
    name: "$public:factory",
    parameter: u32,
    result: u32,
    variables: bendList([]),
    effects: pure,
  });
});
