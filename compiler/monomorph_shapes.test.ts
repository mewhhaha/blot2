import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList([]);
const none = { $: "None" };
const variable = { $: "model.VariableTy", index: 19n };
const unit = { $: "model.UnitTy" };
const callable = {
  $: "model.FunctionTy",
  parameter: variable,
  result: variable,
  effects: {
    $: "model.EffectRow",
    operations: nil,
    tail: { $: "model.ClosedRow" },
  },
};
const binding = (
  name: string,
  inferred_type: unknown,
  predicates: unknown = nil,
) => ({
  $: "infer.Binding",

  name,
  inferred_type,
  variables: nil,
  predicates,
});
const value = (name: string, expression: unknown) => ({
  $: "model.Constant",
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
    $: "model.CallExpr",
    callee: "make",
    argument: { $: "model.UnitExpr" },
  });
  const last = value("last", {
    $: "model.CallExpr",
    callee: "make",
    argument: { $: "model.UnitExpr" },
  });
  const runtime = value("runtime", {
    $: "model.RuntimeInitExpr",
    value: { $: "model.UnitExpr" },
  });
  equal(
    api["monomorph.specialized_constants"](
      bendList([
        first,
        runtime,
        value("closed", { $: "model.UnitExpr" }),
        last,
      ]),
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
        binding("later", { $: "model.VariableTy", index: 47n }),
      ]),
      0n,
    ),
    { $: "Done", value: 48n },
  );
});

Deno.test("qualified shape bound covers variables that occur only in predicates", () => {
  equal(
    api["monomorph.shape_limit"](
      bendList([binding(
        "qualified",
        unit,
        bendList([
          {
            $: "model.TypeRepPredicate",
            represented: { $: "model.VariableTy", index: 63n },
          },
          {
            $: "model.EffectRepPredicate",
            row: {
              $: "model.EffectRow",
              operations: nil,
              tail: { $: "model.RowVariable", index: 79n },
            },
          },
        ]),
      )]),
      0n,
    ),
    { $: "Done", value: 80n },
  );
});

Deno.test("selected monomorphic shapes retain explicit predicates as templates", () => {
  const predicates = bendList([{
    $: "model.TypeRepPredicate",
    represented: unit,
  }]);
  equal(
    api["monomorph.generic_templates"](
      bendList([
        binding("ignored", unit, predicates),
        binding("qualified", unit, predicates),
        binding("closed", unit),
      ]),
      bendList(["qualified", "closed"]),
    ),
    bendList(["qualified"]),
  );
});
