import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const certify = api["type_eq_evidence.certified_signature"] as (
  predicate: Node,
  outer: Node,
  sameSite: bigint,
  same: Node,
  module: Node,
) => Node;
const cloneSite = api["type_eq_evidence.clone_site"] as (
  outer: Node,
  module: Node,
) => Node;
const nil = bendList<Node>([]);
const none: Node = { $: "None" };
const some = (value: Node): Node => ({ $: "Some", value });
const id = (declaration: string, module_name = "std/prelude"): Node => ({
  $: "model.TypeId",
  module_name,
  declaration,
});
const open = (index: bigint, operations: Node[] = []): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail: { $: "model.RowVariable", index },
});
const pure: Node = {
  $: "model.EffectRow",
  operations: nil,
  tail: { $: "model.ClosedRow" },
};
const fn = (parameter: Node, result: Node, effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const nominal = (name: string): Node => ({
  $: "model.AppliedTy",
  identity: id(name, "main"),
  arguments: nil,
});
const typeOf = (argument: Node): Node => ({
  $: "model.AppliedTy",
  identity: id("Type"),
  arguments: bendList([argument]),
});
const at = (offset: bigint, value: Node): Node => ({
  $: "model.SourceExpr",
  offset,
  annotation: none,
  value,
});
const localAt = (offset: bigint, name: string): Node =>
  at(offset, {
    $: "model.InstantiationExpr",
    site: offset * 16n + 500n,
    value: { $: "model.LocalExpr", name },
  });
const pattern = (name: string): Node => ({
  $: "model.ConstructorPattern",
  constructor: "$prelude.Type",
  payload: some({ $: "model.BindingPattern", name }),
});

function clone(
  rightScrutinee = "right$382",
  rightOperand = "b$393",
  operation = "@type.same",
): Node {
  return {
    $: "model.Function",
    name: "$mono[3].$prelude.Type.eq",
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
        values: bendList([
          localAt(385n, "left$379"),
          localAt(387n, rightScrutinee),
        ]),
        arms: bendList([{
          $: "model.MatchArm",
          patterns: bendList([pattern("a$390"), pattern("b$393")]),
          body: at(395n, {
            $: "model.AssociatedExpr",
            identity: 895n,
            dispatch: { $: "model.BinaryDispatch" },
            member: operation,
            templates: nil,
            left: localAt(396n, "a$390"),
            right: localAt(397n, rightOperand),
          }),
        }]),
      }),
    }),
  };
}

const typeDeclaration = (module_name = "std/prelude"): Node => ({
  $: "model.DataType",
  identity: id("Type", module_name),
  parameters: 1n,
  constructors: bendList([{
    $: "model.Constructor",
    name: "$prelude.Type",
    payload: some({ $: "model.ParameterTy", index: 0n }),
    fields: nil,
  }]),
});
const typeCatalog = bendList<Node>([typeDeclaration()]);

function fixture(
  cloneBody = clone(),
  sameAnswer = false,
  leftPayload: Node = fn({ $: "model.UnitTy" }, nominal("Count"), open(20n)),
  rightPayload: Node = fn({ $: "model.UnitTy" }, nominal("Other"), open(26n)),
  types = typeCatalog,
) {
  const left = typeOf(leftPayload);
  const right = typeOf(rightPayload);
  const bool: Node = { $: "model.BoolTy" };
  const contaminated = open(14n, [id("Trace", "main"), id("Foreign", "blot")]);
  const outer: Node = {
    $: "constraints.SelectedFunction",
    name: cloneBody.name,
    signature: fn(left, fn(right, bool, contaminated), contaminated),
  };
  const sameName = "$type[4].same";
  const same: Node = {
    $: "constraints.SelectedFunction",
    name: sameName,
    signature: fn(leftPayload, fn(rightPayload, bool, open(31n)), open(31n)),
  };
  const sameFunction: Node = {
    $: "model.Function",
    name: sameName,
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
      body: { $: "model.BoolExpr", value: sameAnswer },
    },
  };
  const predicate: Node = {
    $: "model.AssociatedPredicate",
    member: "eq",
    templates: nil,
    left,
    right,
    result: bool,
    invocation: open(31n),
  };
  const module: Node = {
    $: "model.Module",
    constants: nil,
    functions: bendList([cloneBody, sameFunction]),
    data_types: types,
    operations: nil,
  };
  return { predicate, outer, same, module, left, right, bool };
}

Deno.test("canonical Type.eq certifies only invocation arrows as pure", () => {
  const value = fixture();
  equal(cloneSite(value.outer, value.module), { $: "Some", value: 895n });
  equal(certify(value.predicate, value.outer, 895n, value.same, value.module), {
    $: "Some",
    value: fn(value.left, fn(value.right, value.bool, pure), pure),
  });
});

Deno.test("Type.eq certificate ties both scrutinees and @type.same operands to their binders", () => {
  for (
    const altered of [
      clone("left$379"),
      clone("right$382", "a$390"),
      clone("right$382", "b$393", "@state.run"),
    ]
  ) {
    const value = fixture(altered);
    equal(
      certify(value.predicate, value.outer, 895n, value.same, value.module),
      none,
    );
  }
});

Deno.test("Type.eq certificate rejects a wrong site, nominal owner, or selected Bool answer", () => {
  const value = fixture();
  equal(
    certify(value.predicate, value.outer, 896n, value.same, value.module),
    none,
  );
  equal(
    certify(
      { ...value.predicate, invocation: open(31n, [id("Tick", "main")]) },
      value.outer,
      895n,
      value.same,
      value.module,
    ),
    none,
  );
  equal(
    certify(
      { ...value.predicate, invocation: open(20n) },
      value.outer,
      895n,
      value.same,
      value.module,
    ),
    none,
  );
  const wrongOwner = bendList<Node>([typeDeclaration("main")]);
  const nominal = fixture(clone(), false, undefined, undefined, wrongOwner);
  equal(
    certify(
      nominal.predicate,
      nominal.outer,
      895n,
      nominal.same,
      nominal.module,
    ),
    none,
  );
  const wrongAnswer = fixture(clone(), true);
  equal(
    certify(
      wrongAnswer.predicate,
      wrongAnswer.outer,
      895n,
      wrongAnswer.same,
      wrongAnswer.module,
    ),
    none,
  );
  const duplicated = fixture(
    clone(),
    false,
    undefined,
    undefined,
    bendList<Node>([typeDeclaration(), typeDeclaration()]),
  );
  equal(
    certify(
      duplicated.predicate,
      duplicated.outer,
      895n,
      duplicated.same,
      duplicated.module,
    ),
    none,
  );
});

Deno.test("Type.eq certificate rejects open callable rows retained below the erased witness head", () => {
  const nested: Node = {
    $: "model.ArrayTy",
    element: fn({ $: "model.UnitTy" }, nominal("Count"), open(60n)),
  };
  const value = fixture(clone(), false, nested, nested);
  equal(
    certify(value.predicate, value.outer, 895n, value.same, value.module),
    none,
  );
});
