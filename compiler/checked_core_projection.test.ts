import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Maybe<T> = { readonly $: "Some"; readonly value: T } | {
  readonly $: "None";
};
const api = compiled as unknown as {
  "checked_core.index_for"(module: Node, certificates: BendList<Node>): Node;
  "checked_core.lookup"(
    indexed: Node,
    job: Node,
    subset: Node,
    imports: BendList<Node>,
  ): Maybe<Node>;
};
const nil = bendList<Node>([]);
const id = (declaration: string): Node => ({
  $: "TypeId",
  module_name: "scope",
  declaration,
});
const operation = (identity: Node): Node => ({
  $: "OperationEffect",
  identity,
});
const row = (identities: readonly Node[]): Node => ({
  $: "EffectRow",
  operations: bendList(identities),
  tail: { $: "ClosedRow" },
});
const functionType = (effects: Node): Node => ({
  $: "FunctionTy",
  parameter: { $: "U32Ty" },
  result: { $: "U32Ty" },
  effects,
});
const sourceFunction = (name: string): Node => ({
  $: "Function",
  name,
  exported: false,
  parameter: "value",
  parameter_type: { $: "None" },
  result_type: { $: "None" },
  body: { $: "LocalExpr", name: "value" },
});
const checkedFunction = (fn: Node): Node => ({
  $: "CheckedFunction",
  function: fn,
  signature: {
    $: "Signature",
    name: fn.name,
    parameter: { $: "U32Ty" },
    result: { $: "U32Ty" },
    variables: bendList([]),
    effects: row([]),
  },
  effects: bendList([]),
});
const moduleWith = (functions: readonly Node[]): Node => ({
  $: "Module",
  constants: nil,
  functions: bendList(functions),
  data_types: nil,
  operations: nil,
});
const imported = (
  identities: readonly Node[],
  metadata = identities,
): Node => ({
  $: "Interface",
  name: "dependency",
  kind: { $: "FunctionInterface" },
  template: functionType(row(identities)),
  parameters: 0n,
  effects: bendList(metadata.map(operation)),
});

Deno.test("retained SCC certificate requires its whole group and exact imported evidence", () => {
  const read = id("Read");
  const write = id("Write");
  const run = sourceFunction("run");
  const sibling = sourceFunction("sibling");
  const original = moduleWith([run, sibling]);
  const checked: Node = {
    $: "CheckedGroup",
    checked: {
      $: "CheckedModule",
      constants: nil,
      functions: bendList([checkedFunction(run), checkedFunction(sibling)]),
      data_types: nil,
      operations: nil,
    },
    interfaces: nil,
  };
  const certificate: Node = {
    $: "Certificate",
    module: original,
    checked,
    imports: bendList([imported([read, write])]),
  };
  const indexed = api["checked_core.index_for"](
    original,
    bendList([certificate]),
  );
  const job: Node = {
    $: "Job",
    members: bendList(["run", "sibling"]),
    dependencies: bendList(["dependency"]),
    type_dependencies: nil,
  };
  const lookup = (subset: Node, dependency: Node, selected = job) =>
    api["checked_core.lookup"](
      indexed,
      selected,
      subset,
      bendList([dependency]),
    );

  const hit = lookup(original, imported([read, write]));
  equal(hit.$, "Some");
  if (hit.$ === "Some") {
    const result = hit.value.checked as Node;
    equal(
      bendArray(result.functions as BendList<Node>).map((fn) =>
        (fn.function as Node).name
      ),
      ["run", "sibling"],
    );
  }

  equal(
    lookup(
      moduleWith([run]),
      imported([read, write]),
      { ...job, members: bendList(["run"]) },
    ).$,
    "None",
  );

  const changedBody = { ...run, body: { $: "U32Expr", value: 42 } };
  equal(
    lookup(moduleWith([changedBody, sibling]), imported([read, write])).$,
    "None",
  );
  equal(lookup(original, imported([read])).$, "None");
  equal(lookup(original, imported([write, read])).$, "None");
  equal(lookup(original, imported([read, write, write])).$, "None");
  equal(lookup(original, imported([read, write], [read])).$, "None");
  equal(
    lookup(original, {
      ...imported([read, write]),
      kind: { $: "ConstantInterface" },
      effects: nil,
    }).$,
    "None",
  );
  ok(hit.$ === "Some");

  const box: Node = {
    $: "DataType",
    identity: id("Box"),
    parameters: 0n,
    constructors: bendList([{
      $: "Constructor",
      name: "Box",
      payload: { $: "Some", value: { $: "U32Ty" } },
      fields: bendList([]),
    }]),
  };
  const operationDefinition: Node = {
    $: "Operation",
    identity: id("Read"),
    parameter: { $: "UnitTy" },
    result: { $: "U32Ty" },
  };
  const catalog = (
    types: readonly Node[],
    operations: readonly Node[],
  ): Node => ({
    ...original,
    data_types: bendList(types),
    operations: bendList(operations),
  });
  const certified = catalog([box], [operationDefinition]);
  const catalogCertificate = { ...certificate, module: certified };
  const catalogHitWith = (candidate: Node, final: Node) => {
    const candidates = api["checked_core.index_for"](
      final,
      bendList([candidate]),
    );
    return api["checked_core.lookup"](
      candidates,
      job,
      final,
      bendList([imported([read, write])]),
    ).$;
  };
  const catalogHit = (final: Node) => catalogHitWith(catalogCertificate, final);
  equal(catalogHit(certified), "Some");
  equal(catalogHit(catalog([], [operationDefinition])), "None");
  equal(
    catalogHit(catalog([{ ...box, parameters: 1n }], [operationDefinition])),
    "None",
  );
  equal(catalogHit(catalog([box], [])), "None");
  equal(
    catalogHit(
      catalog([box], [{ ...operationDefinition, result: { $: "F32Ty" } }]),
    ),
    "None",
  );
  equal(
    catalogHit(catalog(
      [box, {
        ...box,
        identity: id("Unused"),
        constructors: bendList([{
          $: "Constructor",
          name: "Unused",
          payload: { $: "None" },
          fields: nil,
        }]),
      }],
      [operationDefinition, { ...operationDefinition, identity: id("Unused") }],
    )),
    "Some",
  );

  const wrongBox = { ...box, parameters: 1n };
  const wrongOperation = {
    ...operationDefinition,
    result: { $: "F32Ty" },
  };
  equal(catalogHit(catalog([wrongBox, box], [operationDefinition])), "None");
  equal(catalogHit(catalog([box, wrongBox], [operationDefinition])), "Some");
  equal(
    catalogHit(catalog([box], [wrongOperation, operationDefinition])),
    "None",
  );
  equal(
    catalogHit(catalog([box], [operationDefinition, wrongOperation])),
    "Some",
  );

  // The old linear search includes abstract operations in its first match.
  const shadowingTemplate: Node = {
    $: "OperationTemplate",
    identity: id("Read"),
    parameters: 1n,
    parameter: { $: "UnitTy" },
    result: { $: "U32Ty" },
  };
  equal(
    catalogHit(catalog([box], [shadowingTemplate, operationDefinition])),
    "None",
  );
  equal(
    catalogHit(catalog([box], [operationDefinition, shadowingTemplate])),
    "Some",
  );

  const collisionA = { $: "TypeId", module_name: "a::b", declaration: "c" };
  const collisionB = { $: "TypeId", module_name: "a", declaration: "b::c" };
  const collisionBox = { ...box, identity: collisionA };
  const colliding = { ...box, identity: collisionB };
  const collisionCertificate = {
    ...catalogCertificate,
    module: catalog([collisionBox], [operationDefinition]),
  };
  equal(
    catalogHitWith(
      collisionCertificate,
      catalog([colliding], [operationDefinition]),
    ),
    "None",
  );
  equal(
    catalogHitWith(
      collisionCertificate,
      catalog([colliding, collisionBox], [operationDefinition]),
    ),
    "Some",
  );

  const abstractCertificate = {
    ...catalogCertificate,
    module: catalog([box], [shadowingTemplate, {
      $: "OperationInstance",
      template: id("Read"),
      arguments: bendList([{ $: "U32Ty" }]),
    }]),
  };
  equal(catalogHitWith(abstractCertificate, catalog([box], [])), "Some");
});
