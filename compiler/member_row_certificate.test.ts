import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
const api = compiled as unknown as Record<
  string,
  (...args: unknown[]) => unknown
>;
const nil = bendList<Node>([]);
const unit: Node = { $: "model.UnitTy" };
const bool: Node = { $: "model.BoolTy" };
const row = (tail: Node): Node => ({
  $: "model.EffectRow",
  operations: nil,
  tail,
});
const closed: Node = { $: "model.ClosedRow" };
const variable = (index: bigint): Node => ({ $: "model.RowVariable", index });
const arrow = (parameter: Node, result: Node, effects: Node): Node => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const signature = (outer: Node = closed): Node =>
  arrow(unit, arrow(unit, bool, row(variable(1042n))), row(outer));
const evidence = (name: string, ty: Node): Node => ({
  $: "constraints.SelectedFunction",
  name,
  signature: ty,
});
const certificate = (name: string, ty: Node): Node => ({
  $: "monomorph.MemberEvidenceCertificate",
  name,
  signature: ty,
});
const binding = (name: string, ty: Node): Node => ({
  $: "infer.Binding",
  name,
  inferred_type: ty,
  variables: bendList([1042n]),
  // A checked body certificate must not discard later generalized predicates.
  predicates: bendList([{ $: "model.TypeRepPredicate", represented: unit }]),
});
const predicate: Node = {
  $: "model.ReceiverPredicate",
  member: "contains",
  templates: nil,
  receiver: unit,
  argument: unit,
  result: arrow(unit, bool, row(variable(1042n))),
  invocation: row(closed),
};
const empty = api["types.empty"]() as Node;
const selected = signature();
const named = "$mono[1619].Entry.contains";
const accept = (
  chosen: Node,
  certificates: Node[],
  bindings: Node[] = [binding(named, selected)],
  ownerBound: bigint[] = [1042n],
  request: Node = predicate,
): Node =>
  api["monomorph.member_certificate_accept"](
    request,
    chosen,
    bendList(ownerBound),
    bendList(bindings),
    empty,
    bendList(certificates),
  ) as Node;

Deno.test("checked member certificate is confined to its exact selected body and owner", () => {
  const checked = certificate(named, selected);
  equal(accept(evidence(named, selected), [checked]).$, "Done");
  equal(accept(evidence("other", selected), [checked]).$, "Fail");
  equal(
    accept(evidence(named, arrow(unit, unit, row(closed))), [checked]).$,
    "Fail",
  );
  equal(accept(evidence(named, selected), [checked], undefined, []).$, "Fail");
  equal(
    accept(evidence(named, selected), [checked], [
      binding(named, selected),
      binding(named, selected),
    ]).$,
    "Fail",
  );
  equal(accept(evidence(named, selected), [checked, checked]).$, "Fail");
});

Deno.test("checked member certificate cannot accept an open qualified invocation", () => {
  const open = signature(variable(1030n));
  equal(
    accept(
      evidence(named, open),
      [certificate(named, open)],
      [binding(named, open)],
      [1030n, 1042n],
    ).$,
    "Fail",
  );
});

Deno.test("body proof rejects a fresh constraint on the retained phantom witness row", () => {
  const originalType = signature(variable(1030n));
  const original = {
    $: "infer.Binding",
    name: named,
    inferred_type: originalType,
    variables: nil,
    predicates: nil,
  };
  const trial = api["types.append_substitution"](
    empty,
    { $: "types.RowSubstitution", variable: 1030n, replacement: row(closed) },
  ) as Node;
  const exact = api["monomorph.checked_member_certificate"](
    { $: "Some", value: original },
    named,
    originalType,
    trial,
    trial,
  ) as Node;
  equal(exact.$, "Done");
  const constrained = api["types.append_substitution"](
    trial,
    { $: "types.RowSubstitution", variable: 1042n, replacement: row(closed) },
  ) as Node;
  const invalid = api["monomorph.checked_member_certificate"](
    { $: "Some", value: original },
    named,
    originalType,
    trial,
    constrained,
  ) as Node;
  equal(invalid.$, "Fail");
});
