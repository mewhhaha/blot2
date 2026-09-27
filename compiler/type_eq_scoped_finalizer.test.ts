import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const finalize = api["monomorph.finalize_choice_scoped"] as (
  found: Node,
  substitutions: Node,
  subject: string,
  bound: Node,
  module: Node,
  choices: Node,
  bindings: Node,
) => Node;
const emptySubstitutions = api["types.empty"] as () => Node;
const nil = bendList<Node>([]);
const none: Node = { $: "None" };
const some = (value: Node): Node => ({ $: "Some", value });
const id = (name: string, module_name = "std/prelude"): Node => ({
  $: "model.TypeId",
  module_name,
  declaration: name,
});
const row = (tail: Node, operations: Node[] = []): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail,
});
const pure = row({ $: "model.ClosedRow" });
const open = (index: bigint): Node => row({ $: "model.RowVariable", index });
const arrow = (parameter: Node, result: Node, effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const typeOf = (argument: Node): Node => ({
  $: "model.AppliedTy",
  identity: id("Type"),
  arguments: bendList([argument]),
});
const local = (offset: bigint, name: string): Node => ({
  $: "model.SourceExpr",
  offset,
  annotation: none,
  value: {
    $: "model.InstantiationExpr",
    site: 500n + offset * 16n,
    value: { $: "model.LocalExpr", name },
  },
});
const pattern = (name: string): Node => ({
  $: "model.ConstructorPattern",
  constructor: "$prelude.Type",
  payload: some({ $: "model.BindingPattern", name }),
});
const at = (offset: bigint, value: Node): Node => ({
  $: "model.SourceExpr",
  offset,
  annotation: none,
  value,
});

// This is the exact lowered Type.eq body after cloning; no generic source
// inference or relinking is run in this fixture, modeling an unreached answer.
const outerName = "$mono[3].$prelude.Type.eq";
const innerName = "$type[4].same";
const innerSite = 895n;
const clone: Node = {
  $: "model.Function",
  name: outerName,
  exported: false,
  parameter: "left$379",
  parameter_type: none,
  result_type: none,
  body: at(381n, {
    $: "model.LambdaExpr",
    identity: 881n,
    parameter: "right$382",
    parameter_type: none,
    result_type: none,
    body: at(384n, {
      $: "model.MatchExpr",
      values: bendList([local(385n, "left$379"), local(387n, "right$382")]),
      arms: bendList([{
        $: "model.MatchArm",
        patterns: bendList([pattern("a$390"), pattern("b$393")]),
        body: at(395n, {
          $: "model.AssociatedExpr",
          identity: innerSite,
          dispatch: { $: "model.BinaryDispatch" },
          member: "@type.same",
          templates: nil,
          left: local(396n, "a$390"),
          right: local(397n, "b$393"),
        }),
      }]),
    }),
  }),
};

const count: Node = {
  $: "model.AppliedTy",
  identity: id("Count", "main"),
  arguments: nil,
};
const other: Node = {
  $: "model.AppliedTy",
  identity: id("Other", "main"),
  arguments: nil,
};
const leftPayload = arrow({ $: "model.UnitTy" }, count, open(20n));
const rightPayload = arrow({ $: "model.UnitTy" }, other, open(26n));
const left = typeOf(leftPayload);
const right = typeOf(rightPayload);
const bool: Node = { $: "model.BoolTy" };
const outerSignature = arrow(left, arrow(right, bool, pure), pure);
const sameSignature = arrow(leftPayload, arrow(rightPayload, bool, pure), pure);
const sameFunction: Node = {
  $: "model.Function",
  name: innerName,
  exported: false,
  parameter: "$type.left",
  parameter_type: none,
  result_type: none,
  body: {
    $: "model.LambdaExpr",
    identity: 901n,
    parameter: "$type.right",
    parameter_type: none,
    result_type: none,
    body: { $: "model.BoolExpr", value: false },
  },
};
const module: Node = {
  $: "model.Module",
  constants: nil,
  functions: bendList([clone, sameFunction]),
  data_types: bendList([{
    $: "model.DataType",
    identity: id("Type"),
    parameters: 1n,
    constructors: bendList([{
      $: "model.Constructor",
      name: "$prelude.Type",
      payload: some({ $: "model.ParameterTy", index: 0n }),
      fields: nil,
    }]),
  }]),
  operations: nil,
};
const choices: Node = {
  $: "MLeaf",
  key: "895",
  val: {
    $: "monomorph.FunctionChoice",
    name: innerName,
    signature: sameSignature,
  },
};
const evidence: Node = {
  $: "constraints.SelectedFunction",
  name: outerName,
  signature: outerSignature,
};
const predicate = (invocation: Node): Node => ({
  $: "model.AssociatedPredicate",
  member: "eq",
  templates: nil,
  left,
  right,
  result: bool,
  invocation,
});
const selected = (invocation: Node): Node =>
  some({
    $: "monomorph.QualifiedChoice",
    solved: bendList([predicate(invocation)]),
    answers: bendList([{
      $: "constraints.EvidenceAnswer",
      predicate: predicate(invocation),
      evidence,
    }]),
  });

Deno.test("scoped Type.eq proof accepts erased witness rows only after invocation is closed pure", () => {
  const result = finalize(
    selected(pure),
    emptySubstitutions(),
    "offset:8492",
    nil,
    module,
    choices,
    nil,
  );
  equal(result.$, "Done");
  const choice = result.value as Node;
  equal(choice.$, "monomorph.QualifiedChoice");
  const answers = bendArray(choice.answers as BendList<Node>);
  equal(answers.length, 1);
  equal(answers[0].evidence, evidence);
});

Deno.test("unreached Type.eq answer cannot publish an open or labeled invocation", () => {
  for (
    const invocation of [
      open(31n),
      row({ $: "model.ClosedRow" }, [id("Tick", "main")]),
    ]
  ) {
    const result = finalize(
      selected(invocation),
      emptySubstitutions(),
      "offset:8492",
      nil,
      module,
      choices,
      nil,
    );
    equal(result.$, "Fail");
    equal((result.error as Node).code, "ambiguous_qualified");
  }
});

Deno.test("scoped Type.eq proof requires the inner choice at its exact source site", () => {
  const result = finalize(
    selected(pure),
    emptySubstitutions(),
    "offset:8492",
    nil,
    module,
    { ...choices, key: "896" },
    nil,
  );
  equal(result.$, "Fail");
  equal((result.error as Node).code, "ambiguous_qualified");
});
