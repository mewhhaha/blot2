import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: Node;
};
// Keep the previous generalization algorithm as an independent test oracle.
// Calls cross the ordinary Bend module boundary; emitted code is untouched.
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const call = (name: string, ...args: unknown[]) => api[name](...args);
function value(name: string, ...args: unknown[]): unknown {
  const result = call(name, ...args) as Result<unknown>;
  if (result.$ === "Fail") throw result;
  return result.value;
}
const nil = bendList([]);
const ty = (name: string, fields: Record<string, unknown> = {}): Node => ({
  $: `model.${name}`,
  ...fields,
});
const row = (tail = ty("ClosedRow")): Node =>
  ty("EffectRow", { operations: nil, tail });
const binding = (
  name: string,
  type: Node,
  variables: readonly bigint[] = [],
  predicates: readonly Node[] = [],
): Node => ({
  $: "infer.Binding",
  name,
  inferred_type: type,
  variables: bendList(variables),
  predicates: bendList(predicates),
});
function context(bindings: readonly Node[], ambient = row()): Node {
  return {
    $: "infer.Context",
    globals: nil,
    locals: bendList(bindings),
    labels: nil,
    data_types: nil,
    operations: nil,
    subject: "test",
    function_names: nil,
    ambient,
  };
}
function previous(
  type: Node,
  predicates: BendList<Node>,
  ctx: Node,
  state: Node,
  blocked: BendList<bigint>,
): Result<Node> {
  const substitutions = state.substitutions;
  try {
    const resolved = value("types.resolve", substitutions, type);
    const needs = call(
      "constraints.canonical_predicates",
      value("constraints.resolve_list", substitutions, predicates),
      nil,
    );
    const typeFree = value("types.free", resolved);
    const predicateFree = value("constraints.free_list", needs);
    const environment = call("infer.environment_bindings", ctx) as BendList<
      Node
    >;
    const annotations = call(
      "infer.annotation_bindings",
      call("infer.annotation_types", state),
    ) as BendList<Node>;
    // Append only in the test oracle, preserving the original binding order.
    const bindings: Node[] = [];
    for (const list of [environment, annotations]) {
      for (let cursor = list; cursor.$ === "Con"; cursor = cursor.tail) {
        bindings.push(cursor.head);
      }
    }
    const excluded = value(
      "infer.binding_free",
      bendList(bindings),
      substitutions,
    );
    const union = (a: unknown, b: unknown) => call("types.union", a, b);
    const difference = (a: unknown, b: unknown) =>
      call("types.difference", a, b);
    const variables = difference(
      union(typeFree, predicateFree),
      union(
        blocked,
        union(
          excluded,
          call(
            "types.row_free",
            call("types.resolve_row", substitutions, ctx.ambient),
          ),
        ),
      ),
    );
    const closed = value(
      "types.close_covariant",
      resolved,
      variables,
      predicateFree,
    );
    const remaining = value("types.free", closed);
    return {
      $: "Done",
      value: {
        $: "infer.Generalization",
        binding: {
          $: "infer.Binding",
          name: "result",
          inferred_type: closed,
          variables: difference(
            variables,
            difference(variables, union(remaining, predicateFree)),
          ),
          predicates: needs,
        },
        variables,
      },
    };
  } catch (error) {
    if ((error as Result<unknown>).$ === "Fail") return error as Result<Node>;
    throw error;
  }
}

Deno.test("closed generalization matches the original environment-exclusion algorithm", () => {
  const variable = (index: bigint) => ty("VariableTy", { index });
  const functionType = (parameter: Node, result: Node, effects = row()) =>
    ty("FunctionTy", { parameter, result, effects });
  const types = [
    ...[
      "UnitTy",
      "U32Ty",
      "F32Ty",
      "BoolTy",
      "NeverTy",
      "EffectDescriptorTy",
      "EffectSetTy",
    ].map((name) => ty(name)),
    variable(0n),
    variable(1n),
    variable(2n),
    ty("ArrayTy", { element: ty("U32Ty") }),
    ty("ArrayTy", { element: variable(1n) }),
    ty("ProductTy", { elements: bendList([ty("U32Ty"), variable(1n)]) }),
    functionType(variable(0n), variable(0n)),
    functionType(
      ty("U32Ty"),
      ty("BoolTy"),
      row(ty("RowVariable", { index: 3n })),
    ),
  ];
  const contexts = [
    context([]),
    context([binding("outer", variable(0n))]),
    context([
      binding("scheme", functionType(variable(1n), variable(1n)), [1n]),
    ]),
    context([
      binding("qualified", ty("U32Ty"), [], [
        ty("TypeRepPredicate", { represented: variable(2n) }),
      ]),
    ]),
    context([], row(ty("RowVariable", { index: 3n }))),
  ];
  const histories = [
    [],
    [{ $: "types.Substitution", variable: 0n, replacement: ty("U32Ty") }],
    [{ $: "types.Substitution", variable: 0n, replacement: variable(1n) }],
  ];
  let comparisons = 0;
  for (const type of types) {
    for (const ctx of contexts) {
      for (const history of histories) {
        const state: Node = {
          $: "infer.State",
          substitutions: call("types.from_list", bendList(history)),
          next: 100n,
          annotations: { $: "MTip" },
        };
        for (
          const predicates of [[], [
            ty("TypeRepPredicate", { represented: variable(2n) }),
          ]]
        ) {
          for (const blocked of [[], [1n, 2n, 3n]]) {
            const needs = bendList(predicates);
            const excluded = bendList(blocked);
            equal(
              call(
                "infer.generalization_qualified_excluding",
                type,
                needs,
                ctx,
                state,
                "result",
                excluded,
              ),
              previous(type, needs, ctx, state, excluded),
            );
            comparisons++;
          }
        }
      }
    }
  }
  equal(comparisons, 900);
});
