import { throws } from "node:assert/strict";
import { deepStrictEqual as equal } from "node:assert/strict";
import {
  readDispatchExplanation,
  readTypedHole,
  type TypedHoleDiagnostic,
} from "./type_diagnostics.ts";

Deno.test("hole readers reject cycles, dangling edges, overlapping spans and unbounded payloads", () => {
  const basic = (): TypedHoleDiagnostic => ({
    expected: 0,
    nodes: [{
      kind: "u32",
      name: null,
      identity: null,
      variable: null,
      children: { start: 0, len: 0 },
      effects: null,
    }],
    edges: [],
    scope: [],
    requirements: [],
    enclosing: { start: 0, len: 0 },
    truncated: false,
  });
  for (
    const mutate of [
      (hole: TypedHoleDiagnostic) => {
        hole.expected = 9;
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes[0].effects = 0;
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes[0].children.len = 1;
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes[0].variable = -1;
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes[0].name = "雪".repeat(6000);
      },
      (hole: TypedHoleDiagnostic) => {
        hole.enclosing.len = 1;
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes = Array.from({ length: 1026 }, () => hole.nodes[0]);
      },
      (hole: TypedHoleDiagnostic) => {
        hole.nodes.push({ ...hole.nodes[0], children: { start: 0, len: 1 } });
        hole.nodes[0].children.len = 1;
        hole.edges.push({ name: null, type: 0 });
      },
    ]
  ) {
    const hole = basic();
    mutate(hole);
    throws(() => readTypedHole(hole), /Invalid typed-hole diagnostic/);
  }
});

Deno.test("dispatch explanation readers copy known fields and reject malformed peers", () => {
  const valid = () => ({
    operation: "+",
    member: "add",
    candidates: [
      { side: "left", operand: "main::Box", outcome: "incompatible" },
      { side: "right", operand: null, outcome: "no_member" },
    ],
    truncated: false,
  });
  const extra = { ...valid(), injected: true };
  (extra.candidates[0] as Record<string, unknown>).hidden = 1;
  equal(readDispatchExplanation(extra), valid());
  for (
    const mutate of [
      (value: Record<string, unknown>) => {
        value.candidates = "left";
      },
      (value: Record<string, unknown>) => {
        value.candidates = Array(5).fill(valid().candidates[0]);
      },
      (value: Record<string, unknown>) => {
        (value.candidates as Record<string, unknown>[])[0].side = "argument";
      },
      (value: Record<string, unknown>) => {
        (value.candidates as Record<string, unknown>[])[0].outcome = "chosen";
      },
      (value: Record<string, unknown>) => {
        (value.candidates as Record<string, unknown>[])[0].operand = 7;
      },
      (value: Record<string, unknown>) => {
        value.member = "雪".repeat(100);
      },
      (value: Record<string, unknown>) => {
        value.operation = "\ud800";
      },
      (value: Record<string, unknown>) => {
        delete value.truncated;
      },
    ]
  ) {
    const value = valid() as unknown as Record<string, unknown>;
    mutate(value);
    throws(() => readDispatchExplanation(value), TypeError);
  }
  for (const value of [null, [], "explanation", 7]) {
    throws(() => readDispatchExplanation(value), TypeError);
  }
});

Deno.test("implementation explanations validate owned origins steps and total bytes", () => {
  const value = {
    operation: null,
    member: "Source",
    candidates: [{
      side: "implementation",
      operand: null,
      outcome: "head_mismatch",
      origin: { name: "Scalar", path: "source.blot", span: null },
    }],
    steps: [{ member: "Item", ty: "U32", outcome: "requires_evidence" }],
    contexts: [{
      kind: "left_operand",
      path: "source.blot",
      span: { start: 5, end: 10 },
    }],
    truncated: false,
  };
  equal(readDispatchExplanation(value), value);
  throws(
    () =>
      readDispatchExplanation({
        ...value,
        steps: Array(9).fill(value.steps[0]),
      }),
    TypeError,
  );
  throws(
    () =>
      readDispatchExplanation({
        ...value,
        contexts: [{
          kind: "left_operand",
          path: "source.blot",
          span: { start: 10, end: 5 },
        }],
      }),
    TypeError,
  );
  throws(
    () =>
      readDispatchExplanation({
        ...value,
        contexts: [{
          kind: "left_operand",
          path: "x".repeat(257),
          span: { start: 5, end: 10 },
        }],
      }),
    TypeError,
  );
  throws(
    () =>
      readDispatchExplanation({
        ...value,
        candidates: [{
          ...value.candidates[0],
          origin: {
            name: "Scalar",
            path: "source.blot",
            span: { start: 20, end: 1 },
          },
        }],
      }),
    TypeError,
  );
  const large = {
    ...value,
    candidates: Array(4).fill({
      ...value.candidates[0],
      operand: "x".repeat(256),
      origin: { name: "x".repeat(256), path: "x".repeat(256), span: null },
    }),
  };
  throws(() => readDispatchExplanation(large), TypeError);
});
