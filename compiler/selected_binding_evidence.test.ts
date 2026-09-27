import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const unit: Node = { $: "model.UnitTy" };
const u32: Node = { $: "model.U32Ty" };
const bool: Node = { $: "model.BoolTy" };
const closed: Node = { $: "model.ClosedRow" };
const variable = (index: bigint): Node => ({ $: "model.VariableTy", index });
const rowVariable = (index: bigint): Node => ({
  $: "model.RowVariable",
  index,
});
const id = (declaration: string): Node => ({
  $: "model.TypeId",
  module_name: "main",
  declaration,
});
const row = (operations: Node[] = [], tail: Node = closed): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail,
});
const arrow = (parameter: Node, result: Node, effects = row()): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const applied = (identity: Node, arguments_: Node[] = []): Node => ({
  $: "model.AppliedTy",
  identity,
  arguments: bendList(arguments_),
});
const binding = (
  name: string,
  inferred_type: Node,
  variables: bigint[],
  predicates: Node[] = [],
): Node => ({
  $: "infer.Binding",
  name,
  inferred_type,
  variables: bendList(variables),
  predicates: bendList(predicates),
});
const evidence = (name: string, signature: Node): Node => ({
  $: "constraints.SelectedFunction",
  name,
  signature,
});

function certify(
  source: Node,
  selected: Node,
  ownerBound: bigint[],
  name: string,
): boolean {
  return api["selected_binding_evidence.certify"](
    source,
    evidence(name, selected),
    bendList(ownerBound),
  ) as boolean;
}

const end = applied(id("End"));
const count = applied(id("Count"));
const endScheme = arrow(end, arrow(variable(22n), bool));
const countWitness = arrow(u32, count, row([], rowVariable(1042n)));
const endSelected = arrow(end, arrow(countWitness, bool));

Deno.test("selected binding certificate accepts only the current generalized End.contains instance", () => {
  const current = binding("End.contains", endScheme, [22n]);
  equal(certify(current, endSelected, [1042n, 1030n], "End.contains"), true);
  equal(certify(current, endSelected, [1030n], "End.contains"), false);
  equal(certify(current, endSelected, [1042n], "Other.contains"), false);
  equal(
    certify(
      binding("End.contains", endScheme, []),
      endSelected,
      [1042n],
      "End.contains",
    ),
    false,
  );
  equal(
    certify(binding("End.contains", endScheme, [22n, 22n]), endSelected, [
      1042n,
    ], "End.contains"),
    false,
  );
  equal(
    certify(
      binding("End.contains", endScheme, [22n], [{
        $: "model.TypeRepPredicate",
        represented: u32,
      }]),
      endSelected,
      [1042n],
      "End.contains",
    ),
    false,
  );
  const named = api["selected_binding_evidence.certify_named"];
  equal(
    named(
      "End.contains",
      evidence("End.contains", endSelected),
      bendList([1042n]),
      bendList([current]),
    ),
    true,
  );
  equal(
    named(
      "End.contains",
      evidence("End.contains", endSelected),
      bendList([1042n]),
      bendList([current, current]),
    ),
    false,
  );
  equal(
    named(
      "End.contains",
      evidence("End.contains", endSelected),
      bendList([1042n]),
      bendList([]),
    ),
    false,
  );
});

Deno.test("selected binding certificate preserves pure call rows and repeated scheme variables", () => {
  const type = id("Type");
  const typeNe = arrow(
    applied(type, [variable(25n)]),
    arrow(applied(type, [variable(29n)]), bool),
  );
  const current = binding("Type.ne", typeNe, [25n, 29n]);
  equal(certify(current, typeNe, [25n, 29n], "Type.ne"), true);
  const impure = arrow(
    applied(type, [variable(25n)]),
    arrow(applied(type, [variable(29n)]), bool, row([id("Foreign")])),
  );
  equal(certify(current, impure, [25n, 29n], "Type.ne"), false);

  const repeated = binding("same", arrow(variable(7n), variable(7n)), [7n]);
  equal(certify(repeated, arrow(u32, u32), [], "same"), true);
  equal(certify(repeated, arrow(u32, bool), [], "same"), false);

  const repeatedRow = binding(
    "rows",
    arrow(
      arrow(unit, u32, row([], rowVariable(9n))),
      arrow(unit, u32, row([], rowVariable(9n))),
    ),
    [9n],
  );
  const oneRow = arrow(
    arrow(unit, u32, row([], rowVariable(42n))),
    arrow(unit, u32, row([], rowVariable(42n))),
  );
  const twoRows = arrow(
    arrow(unit, u32, row([], rowVariable(42n))),
    arrow(unit, u32, row([], rowVariable(43n))),
  );
  equal(certify(repeatedRow, oneRow, [42n], "rows"), true);
  equal(certify(repeatedRow, twoRows, [42n, 43n], "rows"), false);
});

Deno.test("selected binding certificate rejects source annotations, wildcards and unbound target rows", () => {
  const freeTy: Node = { $: "model.FreeTy", scope: "module", name: "a" };
  const freeRow: Node = { $: "model.FreeRow", scope: "module", name: "e" };
  equal(
    certify(
      binding("bad", arrow(freeTy, bool), []),
      arrow(u32, bool),
      [],
      "bad",
    ),
    false,
  );
  equal(
    certify(
      binding("bad", arrow(u32, bool, row([], freeRow)), []),
      arrow(u32, bool),
      [],
      "bad",
    ),
    false,
  );
  equal(
    certify(
      binding("bad", arrow({ $: "model.ParameterTy", index: 0n }, bool), []),
      arrow(u32, bool),
      [],
      "bad",
    ),
    false,
  );
  equal(
    certify(
      binding("bad", arrow({ $: "model.NeverTy" }, bool), []),
      arrow(u32, bool),
      [],
      "bad",
    ),
    false,
  );
  equal(
    certify(
      binding("bad", arrow(u32, bool), []),
      arrow(u32, bool, row([], rowVariable(8n))),
      [8n],
      "bad",
    ),
    false,
  );
  equal(
    certify(
      binding("bad", arrow(u32, bool), []),
      arrow({ $: "model.FreeTy", scope: "module", name: "a" }, bool),
      [],
      "bad",
    ),
    false,
  );
});
