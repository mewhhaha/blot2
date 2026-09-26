import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList([]);
const none = { $: "None" };
const variable = { $: "VariableTy", index: 19n };
const unit = { $: "UnitTy" };
const callable = {
  $: "FunctionTy",
  parameter: variable,
  result: variable,
  effects: { $: "EffectRow", operations: nil, tail: { $: "ClosedRow" } },
};
const binding = (name: string, inferred_type: unknown) => ({
  $: "Binding",
  name,
  inferred_type,
  variables: nil,
});
const value = (name: string, expression: unknown) => ({
  $: "Constant",
  name,
  exported: false,
  annotation: none,
  value: expression,
});

Deno.test("specialization filters preserve declaration order and duplicate bindings", () => {
  equal(
    api["monomorph.generic_templates"](
      bendList([
        binding("unused", callable),
        binding("first", callable),
        binding("closed", unit),
        binding("last", callable),
        binding("first", callable),
      ]),
      bendList(["last", "first", "closed", "first"]),
    ),
    bendList(["first", "last", "first"]),
  );
  const first = value("first", {
    $: "CallExpr",
    callee: "make",
    argument: { $: "UnitExpr" },
  });
  const last = value("last", {
    $: "CallExpr",
    callee: "make",
    argument: { $: "UnitExpr" },
  });
  const runtime = value("runtime", {
    $: "RuntimeInitExpr",
    value: { $: "UnitExpr" },
  });
  equal(
    api["monomorph.specialized_constants"](
      bendList([first, runtime, value("closed", { $: "UnitExpr" }), last]),
      bendList(["last", "closed", "runtime", "first"]),
      bendList([
        binding("first", callable),
        binding("last", callable),
        binding("closed", unit),
        binding("runtime", callable),
      ]),
    ),
    bendList([first, last]),
  );
});

Deno.test("shared specialization bound covers free variables in all shape bindings", () => {
  equal(
    api["monomorph.shape_limit"](
      bendList([
        binding("closed", unit),
        binding("generic", callable),
        binding("later", { $: "VariableTy", index: 47n }),
      ]),
      0n,
    ),
    { $: "Done", value: 48n },
  );
});
