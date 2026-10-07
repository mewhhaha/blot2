import { throws } from "node:assert/strict";
import { readTypedHole, type TypedHoleDiagnostic } from "./type_diagnostics.ts";

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
