import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type Value = { readonly $: string; readonly [field: string]: unknown };
function list(values: readonly unknown[]): Value {
  return values.reduceRight<Value>((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
}
const nil = list([]);
const emptyRow: Value = { $: "model.EffectRow", operations: nil, tail: { $: "model.ClosedRow" } };
const variable = (index: bigint): Value => ({ $: "model.VariableTy", index });
const u32: Value = { $: "model.U32Ty" };
const bool: Value = { $: "model.BoolTy" };
const backend = compiled as unknown as {
  "types.from_list"(history: Value): Value;
  "types.resolve"(substitutions: Value, ty: Value): unknown;
  "types.resolve_reference"(substitutions: Value, ty: Value): unknown;
  "types.unify_at"(left: Value, right: Value, substitutions: Value, next: bigint, subject: string): unknown;
  "types.unify_at_reference"(left: Value, right: Value, substitutions: Value, next: bigint, subject: string): unknown;
  "types.unify_rows_at"(left: Value, right: Value, substitutions: Value, next: bigint, subject: string): unknown;
  "types.unify_rows_at_reference"(left: Value, right: Value, substitutions: Value, next: bigint, subject: string): unknown;
  "infer.generalization_qualified_excluding"(ty: Value, predicates: Value, context: Value, state: Value, name: string, blocked: Value): unknown;
  "infer.generalization_qualified_excluding_reference"(ty: Value, predicates: Value, context: Value, state: Value, name: string, blocked: Value): unknown;
};
const row = (index: bigint): Value => ({ ...emptyRow, tail: { $: "model.RowVariable", index } });
const fn = (parameter: Value, result: Value, effects = emptyRow): Value => ({ $: "model.FunctionTy", parameter, result, effects });
const types: Value[] = [
  ...["UnitTy", "U32Ty", "F32Ty", "BoolTy", "NeverTy", "EffectDescriptorTy", "EffectSetTy"].map((s) => ({ $: `model.${s}` })),
  { $: "model.ParameterTy", index: 4n },
  { $: "model.FreeTy", scope: "module", name: "a" },
  variable(0n), variable(1n), variable(20n),
  { $: "model.ArrayTy", element: u32 },
  { $: "model.ArrayTy", element: variable(1n) },
  fn(u32, bool), fn(variable(0n), variable(1n), row(10n)),
  { $: "model.ProductTy", elements: list([u32, fn(variable(20n), variable(20n), row(21n))]) },
];

Deno.test("inference fast paths match resolution and unification including histories and errors", () => {
  for (const history of [
    [],
    [{ $: "types.Substitution", variable: 0n, replacement: u32 }],
    [{ $: "types.Substitution", variable: 0n, replacement: variable(1n) }, { $: "types.Substitution", variable: 1n, replacement: bool }],
    [{ $: "types.Substitution", variable: 0n, replacement: bool }, { $: "types.Substitution", variable: 0n, replacement: u32 }],
    [{ $: "types.RowSubstitution", variable: 10n, replacement: emptyRow }],
  ]) {
    const substitutions = backend["types.from_list"](list(history));
    const snapshot = structuredClone(substitutions);
    for (const left of types) {
      equal(backend["types.resolve"](substitutions, left), backend["types.resolve_reference"](substitutions, left));
      for (const right of types) {
        equal(backend["types.unify_at"](left, right, substitutions, 40n, "fixture"), backend["types.unify_at_reference"](left, right, substitutions, 40n, "fixture"));
      }
    }
    for (const left of [emptyRow, row(10n), row(11n)]) for (const right of [emptyRow, row(10n), row(12n)]) {
      equal(backend["types.unify_rows_at"](left, right, substitutions, 40n, "row"), backend["types.unify_rows_at_reference"](left, right, substitutions, 40n, "row"));
    }
    equal(substitutions, snapshot);
  }
});

Deno.test("closed generalization shortcut preserves open rows, predicates, annotations and blocked variables", () => {
  const binding = (name: string, inferred_type: Value, variables = nil): Value => ({ $: "infer.Binding", name, inferred_type, variables, predicates: nil });
  const substitutions = backend["types.from_list"](list([{ $: "types.Substitution", variable: 0n, replacement: u32 }]));
  const state: Value = { $: "infer.State", substitutions, next: 40n, annotations: { $: "MLeaf", key: "annotated", val: variable(20n) } };
  const context: Value = {
    $: "infer.Context", globals: list([binding("global", u32)]),
    locals: list([binding("outer", fn(variable(1n), variable(1n), row(10n))), binding("poly", variable(20n), list([20n]))]),
    labels: list([{ $: "infer.Label", identity: 0n, result: variable(20n) }]),
    data_types: nil, operations: nil, subject: "fixture", function_names: nil, ambient: row(11n),
  };
  const snapshot = structuredClone({ context, state });
  for (const ty of types) for (const predicates of [nil, list([{ $: "model.TypeRepPredicate", represented: u32 }]), list([{ $: "model.TypeRepPredicate", represented: variable(20n) }]), list([{ $: "model.EffectRepPredicate", row: row(21n) }])]) {
    for (const blocked of [nil, list([20n, 21n])]) {
      equal(backend["infer.generalization_qualified_excluding"](ty, predicates, context, state, "value", blocked), backend["infer.generalization_qualified_excluding_reference"](ty, predicates, context, state, "value", blocked));
    }
  }
  equal({ context, state }, snapshot);
});
