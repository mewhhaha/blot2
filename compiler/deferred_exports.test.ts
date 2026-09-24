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
  $: "EffectRow",
  operations: bendList([]),
  tail: { $: "ClosedRow" },
};
const u32: Node = { $: "U32Ty" };
const unit: Node = { $: "UnitTy" };
const variable: Node = { $: "VariableTy", index: 0n };
const arrow = (parameter: Node, result: Node, effects: Node = pure): Node => ({
  $: "FunctionTy",
  parameter,
  result,
  effects,
});
const fn = (name: string): Node => ({
  $: "Function",
  name,
  exported: true,
  parameter: "argument",
  parameter_type: none,
  result_type: none,
  body: { $: "U32Expr", value: 7 },
});
const constant = (name: string): Node => ({
  $: "Constant",
  name,
  exported: true,
  annotation: none,
  value: { $: "UnitExpr" },
});
const binding = (name: string, ty: Node, variables: bigint[] = []): Node => ({
  $: "Binding",
  name,
  inferred_type: ty,
  variables: bendList(variables),
});
const signature = (name: string, ty: Node, variables: bigint[] = []): Node => {
  if (ty.$ !== "FunctionTy") throw new Error("function signature needs arrow");
  return {
    $: "Signature",
    name,
    parameter: ty.parameter,
    result: ty.result,
    variables: bendList(variables),
    effects: ty.effects,
  };
};
function checkedFunction(name: string, ty: Node, variables: bigint[] = []) {
  return {
    $: "CheckedFunction",
    function: fn(name),
    signature: signature(name, ty, variables),
    effects: bendList([]),
  };
}
function checkedConstant(name: string, ty: Node, variables: bigint[] = []) {
  return {
    $: "CheckedConstant",
    constant: constant(name),
    inferred_type: ty,
    variables: bendList(variables),
  };
}
function moduleOf(functions: Node[], constants: Node[]) {
  return {
    $: "CheckedModule",
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
    { $: "Resolved" },
  );
  if (result.$ === "Fail") throw new Error(String(result.error));
  return result.value;
}

Deno.test("checked-driven export selection matches resolved selection", () => {
  const open: Node = {
    $: "EffectRow",
    operations: bendList([]),
    tail: { $: "RowVariable", index: 1n },
  };
  const cases: Array<[Node[], Node[], Node[]]> = [
    [
      [checkedFunction("plain", arrow(u32, u32))],
      [checkedConstant("number", u32)],
      [binding("plain", arrow(u32, u32)), binding("number", u32)],
    ],
    [
      [checkedFunction("open_effect", arrow(unit, u32, open))],
      [],
      [binding("open_effect", arrow(unit, u32, open))],
    ],
    [
      [checkedFunction("generic", arrow(variable, variable), [0n])],
      [],
      [binding("generic", arrow(variable, variable), [0n])],
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

Deno.test("checked callable-constant wrapper has the inferred signature", () => {
  const checked = moduleOf([], [checkedConstant("factory", arrow(u32, u32))]);
  const selected = api["public_exports.select_checked"](checked);
  const functions = bendArray(
    (selected as unknown as { functions: BendList<Node> }).functions,
  );
  equal(functions.length, 1);
  equal((functions[0] as unknown as { signature: Node }).signature, {
    $: "Signature",
    name: "$public:factory",
    parameter: u32,
    result: u32,
    variables: bendList([]),
    effects: pure,
  });
});
