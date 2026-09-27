import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList<Node>([]);
const unit: Node = { $: "model.UnitTy" };
const closed: Node = { $: "model.ClosedRow" };
const state: Node = {
  $: "model.AppliedTy",
  identity: { $: "model.TypeId", module_name: "main", declaration: "Counter" },
  arguments: nil,
};
const value: Node = { $: "model.VariableTy", index: 63n };
const residual: Node = {
  $: "model.TypeId",
  module_name: "main",
  declaration: "Trace",
};
const otherResidual: Node = {
  $: "model.TypeId",
  module_name: "main",
  declaration: "Audit",
};
const tail = (index: bigint): Node => ({ $: "model.RowVariable", index });
const row = (operations: readonly Node[], rest: Node): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail: rest,
});
const arrow = (parameter: Node, result: Node, effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const pair = (first: Node, second: Node): Node => ({
  $: "model.ProductTy",
  elements: bendList([first, second]),
});
const typeId = (declaration: string): Node => ({
  $: "model.TypeId",
  module_name: "main",
  declaration,
});
type Variant = "reader" | "writer";
type Source = "family" | "builtin";

function specimen(
  variant: Variant,
  source: Source,
  options: {
    witness?: Node;
    result?: Node;
    residual?: Node[];
    implementationLabels?: Node[];
    actionLabels?: Node[];
    invocationLabels?: Node[];
    implementationTail?: Node;
    actionTail?: Node;
    invocationTail?: Node;
  } = {},
) {
  const request: Node = {
    $: variant === "reader"
      ? "state_specialize.Reader"
      : "state_specialize.Writer",
  };
  const template = typeId(variant === "reader" ? "Cell.get" : "Cell.set");
  const keyResult = api["state_specialize.type_key"](
    65_536n,
    source === "family"
      ? { $: "state_specialize.TypesKey", types: bendList([state]) }
      : { $: "state_specialize.TypeKey", ty: state },
  ) as Node;
  if (keyResult.$ !== "Done") throw new Error("Expected a concrete state key");
  const key = keyResult.value as string;
  const read = source === "family"
    ? api["state_run_evidence.family_identity"](template, key) as Node
    : api["state_specialize.read_identity"](key) as Node;
  const write = source === "family"
    ? read
    : api["state_specialize.write_identity"](key) as Node;
  const operation = variant === "reader" ? read : write;
  const labels = options.residual ?? [residual, otherResidual, residual];
  const invocation = row(
    options.invocationLabels ?? labels,
    options.invocationTail ?? tail(60n),
  );
  const implementation = arrow(
    variant === "reader" ? unit : state,
    variant === "reader" ? state : unit,
    row(
      options.implementationLabels ?? labels,
      options.implementationTail ?? tail(60n),
    ),
  );
  const action = arrow(
    unit,
    options.result ?? value,
    row(
      options.actionLabels ?? [operation, ...labels],
      options.actionTail ?? tail(60n),
    ),
  );
  const witness = options.witness ?? state;
  const signature = arrow(
    witness,
    arrow(pair(implementation, action), options.result ?? value, invocation),
    row([], closed),
  );
  const predicate: Node = {
    $: "model.AssociatedPredicate",
    member: source === "family" ? `@effect.${variant}` : `@state.${variant}`,
    templates: source === "family" ? bendList([template]) : nil,
    left: witness,
    right: pair(implementation, action),
    result: options.result ?? value,
    invocation,
  };
  const name = "$state[7]";
  const evidence: Node = { $: "constraints.SelectedFunction", name, signature };
  const generated = api["state_specialize.function_for"](
    request,
    read,
    write,
    name,
    7n,
  ) as Node;
  const catalog: Node[] = source === "family"
    ? [{
      $: "model.OperationTemplate",
      identity: template,
      parameters: 1n,
      parameter: variant === "reader"
        ? unit
        : { $: "model.ParameterTy", index: 0n },
      result: variant === "reader"
        ? { $: "model.ParameterTy", index: 0n }
        : unit,
    }, {
      $: "model.Operation",
      identity: operation,
      parameter: variant === "reader" ? unit : state,
      result: variant === "reader" ? state : unit,
    }]
    : bendArray(
      api["state_specialize.operations"](key, state, nil) as BendList<Node>,
    );
  const moduleWith = (
    functions: readonly Node[] = [generated],
    operations: readonly Node[] = catalog,
  ): Node => ({
    $: "model.Module",
    constants: nil,
    functions: bendList(functions),
    data_types: nil,
    operations: bendList(operations),
  });
  const certify = (
    checkedPredicate: Node = predicate,
    checkedEvidence: Node = evidence,
    bound: readonly bigint[] = [60n, 63n],
    module: Node = moduleWith(),
  ): boolean =>
    api["state_scoped_evidence.certify_scoped"](
      checkedPredicate,
      checkedEvidence,
      bendList(bound),
      module,
    ) as boolean;
  return {
    predicate,
    evidence,
    generated,
    catalog,
    operation,
    moduleWith,
    certify,
  };
}

Deno.test("canonical reader and writer certify nested residual effects exactly", () => {
  for (const source of ["family", "builtin"] as const) {
    for (const variant of ["reader", "writer"] as const) {
      const checked = specimen(variant, source);
      equal(checked.certify(), true);
      const reorderedPredicate = {
        ...checked.predicate,
        invocation: row([otherResidual, residual, residual], tail(60n)),
      };
      equal(checked.certify(reorderedPredicate), true);
      const witness = arrow(unit, state, row([], closed));
      equal(specimen(variant, source, { witness }).certify(), true);
    }
  }
});

Deno.test("reader and writer compare predicate callback rows as complete multisets", () => {
  for (const source of ["family", "builtin"] as const) {
    for (const variant of ["reader", "writer"] as const) {
      const checked = specimen(variant, source);
      const [implementation, action] = bendArray(
        (checked.predicate.right as Node).elements as BendList<Node>,
      );
      const reordered = {
        ...checked.predicate,
        right: pair({
          ...implementation,
          effects: row([otherResidual, residual, residual], tail(60n)),
        }, {
          ...action,
          effects: row(
            [residual, checked.operation, otherResidual, residual],
            tail(60n),
          ),
        }),
      };
      equal(checked.certify(reordered), true);
      for (
        const [effects, result] of [
          [
            row([checked.operation, residual, otherResidual], tail(60n)),
            action.result,
          ],
          [
            row(
              [checked.operation, residual, otherResidual, residual],
              tail(61n),
            ),
            action.result,
          ],
          [
            row(
              [checked.operation, residual, otherResidual, residual],
              tail(60n),
            ),
            unit,
          ],
        ]
      ) {
        equal(
          checked.certify({
            ...reordered,
            right: pair(implementation, { ...action, effects, result }),
          }),
          false,
        );
      }
    }
  }
});

Deno.test("reader and writer reject altered bodies, catalog operations, and duplicate labels", () => {
  for (const variant of ["reader", "writer"] as const) {
    const checked = specimen(variant, "family");
    const other = api["state_specialize.function_for"](
      { $: "state_specialize.Run" },
      checked.operation,
      checked.operation,
      "$state[7]",
      7n,
    ) as Node;
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([other]),
      ),
      false,
    );
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([checked.generated, checked.generated]),
      ),
      false,
    );
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([checked.generated], checked.catalog.slice(0, 1)),
      ),
      false,
    );
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([checked.generated], [
          ...checked.catalog,
          checked.catalog[1],
        ]),
      ),
      false,
    );
    const wrongConcrete = {
      ...checked.catalog[1],
      result: variant === "reader" ? unit : state,
    };
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([checked.generated], [
          checked.catalog[0],
          wrongConcrete,
        ]),
      ),
      false,
    );
    const wrongTemplate = { ...checked.catalog[0], parameters: 2n };
    equal(
      checked.certify(
        checked.predicate,
        checked.evidence,
        [60n, 63n],
        checked.moduleWith([checked.generated], [
          wrongTemplate,
          checked.catalog[1],
        ]),
      ),
      false,
    );
    const missing = specimen(variant, "family", {
      actionLabels: [checked.operation, residual, otherResidual],
    });
    equal(missing.certify(), false);
    const extra = specimen(variant, "family", {
      actionLabels: [
        checked.operation,
        residual,
        otherResidual,
        residual,
        residual,
      ],
    });
    equal(extra.certify(), false);
    const wrongHandler = specimen(variant, "family", {
      implementationLabels: [residual, otherResidual],
    });
    equal(wrongHandler.certify(), false);
    const wrongPredicate = {
      ...checked.predicate,
      invocation: row([residual, otherResidual], tail(60n)),
    };
    equal(checked.certify(wrongPredicate), false);
    equal(
      checked.certify({ ...checked.predicate, member: "@effect.run" }),
      false,
    );
  }
});

Deno.test("reader and writer reject unbound values and source or mismatched rows", () => {
  const writer = specimen("writer", "family");
  equal(writer.certify(writer.predicate, writer.evidence, [60n]), false);
  equal(writer.certify(writer.predicate, writer.evidence, [63n]), false);
  equal(
    specimen("writer", "family", { actionTail: tail(61n) }).certify(
      undefined,
      undefined,
      [60n, 61n, 63n],
    ),
    false,
  );
  equal(
    specimen("reader", "family", {
      invocationTail: { $: "model.FreeRow", scope: "source", name: "e" },
    }).certify(),
    false,
  );
  equal(
    specimen("reader", "family", {
      result: { $: "model.FreeTy", scope: "source", name: "a" },
    }).certify(),
    false,
  );
  const phantom = arrow(
    { $: "model.VariableTy", index: 64n },
    state,
    row([], closed),
  );
  equal(specimen("reader", "family", { witness: phantom }).certify(), false);
  equal(
    specimen("reader", "family", { witness: phantom }).certify(
      undefined,
      undefined,
      [60n, 63n, 64n],
    ),
    true,
  );
  const phantomRow = arrow(unit, state, row([], tail(64n)));
  equal(
    specimen("writer", "family", { witness: phantomRow }).certify(
      undefined,
      undefined,
      [60n, 63n, 64n],
    ),
    true,
  );
  equal(specimen("writer", "family", { witness: phantomRow }).certify(), false);
  const sourceRow = arrow(
    unit,
    state,
    row([], {
      $: "model.FreeRow",
      scope: "source",
      name: "e",
    }),
  );
  equal(specimen("reader", "family", { witness: sourceRow }).certify(), false);
  const sourceType = arrow(
    {
      $: "model.FreeTy",
      scope: "source",
      name: "a",
    },
    state,
    row([], closed),
  );
  equal(specimen("reader", "family", { witness: sourceType }).certify(), false);
});
