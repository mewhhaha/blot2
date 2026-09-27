import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList<Node>([]);
const state: Node = {
  $: "model.AppliedTy",
  identity: { $: "model.TypeId", module_name: "main", declaration: "Counter" },
  arguments: nil,
};
const value: Node = { $: "model.VariableTy", index: 63n };
const key = "n4:main7:Counter0:";
const read = api["state_specialize.read_identity"](key) as Node;
const write = api["state_specialize.write_identity"](key) as Node;
const closed: Node = { $: "model.ClosedRow" };
const variable = (index: bigint): Node => ({ $: "model.RowVariable", index });
const row = (operations: readonly Node[], tail: Node): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail,
});
const arrow = (parameter: Node, result: Node, effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const pair = (left: Node, right: Node): Node => ({
  $: "model.ProductTy",
  elements: bendList([left, right]),
});

function specimen({
  result = value,
  callbackTail = variable(60n),
  invocationTail = variable(60n),
  predicateState = state,
  readIdentity = read,
  writeIdentity = write,
  invocationLabels = [] as Node[],
  callbackLabels,
  member = "@state.run",
  templates = [] as Node[],
}: {
  result?: Node;
  callbackTail?: Node;
  invocationTail?: Node;
  predicateState?: Node;
  readIdentity?: Node;
  writeIdentity?: Node;
  invocationLabels?: Node[];
  callbackLabels?: Node[];
  member?: string;
  templates?: Node[];
} = {}) {
  const callback = arrow(
    { $: "model.UnitTy" },
    result,
    row(
      callbackLabels ?? [readIdentity, writeIdentity, ...invocationLabels],
      callbackTail,
    ),
  );
  const output = pair(state, result);
  const invocation = row(invocationLabels, invocationTail);
  const signature = arrow(
    state,
    arrow(callback, output, invocation),
    row([], closed),
  );
  const predicate: Node = {
    $: "model.AssociatedPredicate",
    member,
    templates: bendList(templates),
    left: predicateState,
    right: callback,
    result: pair(predicateState, result),
    invocation,
  };
  const evidence: Node = {
    $: "constraints.SelectedFunction",
    name: "$state[4]",
    signature,
  };
  return { predicate, evidence };
}

const run = api["state_specialize.function_for"](
  { $: "state_specialize.Run" },
  read,
  write,
  "$state[4]",
  4n,
) as Node;
const operations = bendArray(
  api["state_specialize.operations"](key, state, nil) as BendList<Node>,
);
const moduleWith = (
  functions: readonly Node[] = [run],
  catalog: readonly Node[] = operations,
): Node => ({
  $: "model.Module",
  constants: nil,
  functions: bendList(functions),
  data_types: nil,
  operations: bendList(catalog),
});
const certify = (
  predicate: Node,
  evidence: Node,
  bound: readonly bigint[],
  module: Node = moduleWith(),
): boolean =>
  api["state_run_evidence.certify_run"](
    predicate,
    evidence,
    bendList(bound),
    module,
  ) as boolean;

Deno.test("State.run universal evidence requires the exact generated body, catalog, and owner-bound variables", () => {
  const good = specimen();
  equal(certify(good.predicate, good.evidence, [60n, 63n]), true);

  const wrongBody = api["state_specialize.function_for"](
    { $: "state_specialize.Read" },
    read,
    write,
    "$state[4]",
    4n,
  ) as Node;
  equal(
    certify(good.predicate, good.evidence, [60n, 63n], moduleWith([wrongBody])),
    false,
  );
  equal(
    certify(good.predicate, good.evidence, [60n, 63n], moduleWith([run, run])),
    false,
  );

  const wrongRead = { ...operations[0], result: { $: "model.U32Ty" } };
  equal(
    certify(
      good.predicate,
      good.evidence,
      [60n, 63n],
      moduleWith([run], [wrongRead, operations[1]]),
    ),
    false,
  );
  equal(
    certify(
      good.predicate,
      good.evidence,
      [60n, 63n],
      moduleWith([run], [...operations, operations[0]]),
    ),
    false,
  );
  equal(
    certify(
      good.predicate,
      good.evidence,
      [60n, 63n],
      moduleWith([run], [...operations, {
        $: "model.OperationTemplate",
        identity: read,
        parameters: 0n,
        parameter: { $: "model.UnitTy" },
        result: state,
      }]),
    ),
    false,
  );

  const other = specimen({
    predicateState: {
      $: "model.AppliedTy",
      identity: {
        $: "model.TypeId",
        module_name: "main",
        declaration: "Other",
      },
      arguments: nil,
    },
  });
  equal(certify(other.predicate, other.evidence, [60n, 63n]), false);
  const mismatchedRow = specimen({ callbackTail: variable(61n) });
  equal(
    certify(mismatchedRow.predicate, mismatchedRow.evidence, [60n, 61n, 63n]),
    false,
  );
  equal(certify(good.predicate, good.evidence, [60n]), false);

  const sourceRow = specimen({
    callbackTail: { $: "model.FreeRow", scope: "source", name: "e" },
    invocationTail: { $: "model.FreeRow", scope: "source", name: "e" },
  });
  equal(certify(sourceRow.predicate, sourceRow.evidence, [63n]), false);
  const sourceValue = specimen({
    result: { $: "model.FreeTy", scope: "source", name: "a" },
  });
  equal(certify(sourceValue.predicate, sourceValue.evidence, [60n]), false);
  const rigidValue = specimen({
    result: { $: "model.ParameterTy", index: 0n },
  });
  equal(certify(rigidValue.predicate, rigidValue.evidence, [60n]), false);
});

Deno.test("State.run evidence scopes nested result types and effects", () => {
  const composite = specimen({ result: pair({ $: "model.UnitTy" }, value) });
  equal(certify(composite.predicate, composite.evidence, [60n, 63n]), true);
  for (
    const tail of [{ $: "model.FreeRow", scope: "source", name: "e" }, {
      $: "model.RowParameter",
      index: 0n,
    }, variable(64n)]
  ) {
    const nested = specimen({
      result: arrow({ $: "model.UnitTy" }, value, row([], tail)),
    });
    equal(certify(nested.predicate, nested.evidence, [60n, 63n]), false);
  }
});

Deno.test("State.run predicate callback rows retain multiplicity independently of order", () => {
  const trace: Node = {
    $: "model.TypeId",
    module_name: "main",
    declaration: "Trace",
  };
  const good = specimen({ invocationLabels: [trace, trace] });
  const callback = good.predicate.right as Node;
  const reordered = {
    ...good.predicate,
    right: {
      ...callback,
      effects: row([trace, write, trace, read], variable(60n)),
    },
  };
  equal(certify(reordered, good.evidence, [60n, 63n]), true);
  for (
    const changed of [
      { ...callback, effects: row([trace, write, read], variable(60n)) },
      { ...callback, effects: row([trace, write, trace, read], variable(61n)) },
      { ...callback, result: { $: "model.UnitTy" } },
      { ...callback, parameter: state },
    ]
  ) {
    equal(
      certify({ ...good.predicate, right: changed }, good.evidence, [
        60n,
        61n,
        63n,
      ]),
      false,
    );
  }
});

Deno.test("nested State.run retains the exact residual invocation multiset", () => {
  const ghostGet = {
    $: "model.TypeId",
    module_name: "main",
    declaration: "Ghost.get",
  };
  const ghostSet = {
    $: "model.TypeId",
    module_name: "main",
    declaration: "Ghost.set",
  };
  const residual = [ghostGet, ghostSet] as Node[];
  const nested = specimen({ invocationLabels: residual });
  equal(certify(nested.predicate, nested.evidence, [60n, 63n]), true);
  equal(certify(nested.predicate, nested.evidence, [63n]), false);
  const reordered = specimen({
    invocationLabels: residual,
    callbackLabels: [ghostSet, read, ghostGet, write],
  });
  equal(certify(reordered.predicate, reordered.evidence, [60n, 63n]), true);

  // Resolution sorts predicate rows independently of the selected signature.
  const reorderedPredicate = {
    ...nested.predicate,
    invocation: row([ghostSet, ghostGet], variable(60n)),
  };
  equal(certify(reorderedPredicate, nested.evidence, [60n, 63n]), true);
  for (const labels of [[ghostGet], [ghostGet, ghostSet, ghostSet]]) {
    const changedPredicate = {
      ...nested.predicate,
      invocation: row(labels, variable(60n)),
    };
    equal(certify(changedPredicate, nested.evidence, [60n, 63n]), false);
  }

  const duplicated = specimen({
    invocationLabels: [ghostGet, ghostGet, ghostSet],
  });
  equal(certify(duplicated.predicate, duplicated.evidence, [60n, 63n]), true);
  const droppedCopy = specimen({
    invocationLabels: [ghostGet, ghostGet, ghostSet],
    callbackLabels: [read, write, ghostGet, ghostSet],
  });
  equal(
    certify(droppedCopy.predicate, droppedCopy.evidence, [60n, 63n]),
    false,
  );
  const inventedCallback = specimen({
    invocationLabels: residual,
    callbackLabels: [read, write, ghostGet, ghostSet, ghostSet],
  });
  equal(
    certify(inventedCallback.predicate, inventedCallback.evidence, [60n, 63n]),
    false,
  );
  const unhandledInvocation = specimen({
    invocationLabels: residual,
    callbackLabels: [read, write, ghostGet],
  });
  equal(
    certify(unhandledInvocation.predicate, unhandledInvocation.evidence, [
      60n,
      63n,
    ]),
    false,
  );
  const wrongTail = specimen({
    invocationLabels: residual,
    callbackTail: variable(61n),
  });
  equal(
    certify(wrongTail.predicate, wrongTail.evidence, [60n, 61n, 63n]),
    false,
  );
});

Deno.test("declared effect.run family certifies only its exact instantiated operations and generated body", () => {
  const readTemplate: Node = {
    $: "model.TypeId",
    module_name: "main",
    declaration: "Cell.get",
  };
  const writeTemplate: Node = {
    $: "model.TypeId",
    module_name: "main",
    declaration: "Cell.set",
  };
  // TypesKey{[state]} adds one length-delimited component to TypeKey{state}.
  const instanceKey = `${key.length}:${key}`;
  const instance = (template: Node): Node => ({
    $: "model.TypeId",
    module_name: template.module_name as string,
    declaration: `${template.declaration as string}<${instanceKey}>`,
  });
  const familyRead = instance(readTemplate);
  const familyWrite = instance(writeTemplate);
  const templateRead: Node = {
    $: "model.OperationTemplate",
    identity: readTemplate,
    parameters: 1n,
    parameter: { $: "model.UnitTy" },
    result: { $: "model.ParameterTy", index: 0n },
  };
  const templateWrite: Node = {
    $: "model.OperationTemplate",
    identity: writeTemplate,
    parameters: 1n,
    parameter: { $: "model.ParameterTy", index: 0n },
    result: { $: "model.UnitTy" },
  };
  const concreteRead: Node = {
    $: "model.Operation",
    identity: familyRead,
    parameter: { $: "model.UnitTy" },
    result: state,
  };
  const concreteWrite: Node = {
    $: "model.Operation",
    identity: familyWrite,
    parameter: state,
    result: { $: "model.UnitTy" },
  };
  const catalog = [templateRead, templateWrite, concreteRead, concreteWrite];
  const familyRun = api["state_specialize.function_for"](
    { $: "state_specialize.Run" },
    familyRead,
    familyWrite,
    "$state[4]",
    4n,
  ) as Node;
  const familyModule = (
    operations: readonly Node[] = catalog,
    functions: readonly Node[] = [familyRun],
  ) => moduleWith(functions, operations);
  const family = specimen({
    readIdentity: familyRead,
    writeIdentity: familyWrite,
    member: "@effect.run",
    templates: [readTemplate, writeTemplate],
  });
  equal(
    certify(family.predicate, family.evidence, [60n, 63n], familyModule()),
    true,
  );
  const nestedFamily = specimen({
    readIdentity: familyRead,
    writeIdentity: familyWrite,
    member: "@effect.run",
    templates: [readTemplate, writeTemplate],
    invocationLabels: [familyRead, familyWrite],
  });
  equal(
    certify(
      nestedFamily.predicate,
      nestedFamily.evidence,
      [60n, 63n],
      familyModule(),
    ),
    true,
  );
  equal(
    certify(family.predicate, family.evidence, [60n], familyModule()),
    false,
  );

  // The predicate's declared family, instantiated signatures, and selected
  // implementation must all describe the same get/set pair.
  const wrongTemplate = specimen({
    readIdentity: familyRead,
    writeIdentity: familyWrite,
    member: "@effect.run",
    templates: [writeTemplate, readTemplate],
  });
  equal(
    certify(
      wrongTemplate.predicate,
      wrongTemplate.evidence,
      [60n, 63n],
      familyModule(),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule(catalog.slice(1)),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule(catalog.slice(0, 3)),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule([
        { ...templateRead, result: { $: "model.U32Ty" } },
        ...catalog.slice(1),
      ]),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule([
        ...catalog.slice(0, 3),
        { ...concreteWrite, parameter: { $: "model.U32Ty" } },
      ]),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule([...catalog, templateRead]),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule([...catalog, concreteRead]),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule([
        ...catalog,
        {
          $: "model.OperationTemplate",
          identity: familyRead,
          parameters: 0n,
          parameter: { $: "model.UnitTy" },
          result: state,
        },
      ]),
    ),
    false,
  );
  equal(
    certify(
      family.predicate,
      family.evidence,
      [60n, 63n],
      familyModule(catalog, [run]),
    ),
    false,
  );

  const sourceRow = specimen({
    readIdentity: familyRead,
    writeIdentity: familyWrite,
    member: "@effect.run",
    templates: [readTemplate, writeTemplate],
    callbackTail: { $: "model.FreeRow", scope: "source", name: "e" },
    invocationTail: { $: "model.FreeRow", scope: "source", name: "e" },
  });
  equal(
    certify(sourceRow.predicate, sourceRow.evidence, [63n], familyModule()),
    false,
  );
});
