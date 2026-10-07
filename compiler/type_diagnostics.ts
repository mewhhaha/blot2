/** Bounded semantic graphs. All indexes/identities are local to one diagnostic. */
export type DiagnosticTypeKind =
  | "truncated"
  | "absent"
  | "unit"
  | "boolean"
  | "u32"
  | "f32"
  | "never"
  | "variable"
  | "function"
  | "product"
  | "record"
  | "nominal"
  | "array"
  | "list"
  | "cursor"
  | "demand"
  | "type_constructor"
  | "resolver"
  | "provider"
  | "state_provider"
  | "effects"
  | "operation"
  | "row_variable"
  | "row_parameter";
export interface DiagnosticSpan {
  start: number;
  len: number;
}
export interface DiagnosticType {
  kind: DiagnosticTypeKind;
  name: string | null;
  identity: { unit: number; decl: number } | null;
  variable: number | null;
  /** Indexes edges; function children are parameter/result, record edges named. */
  children: DiagnosticSpan;
  /** Optional effects node. Its children preserve repeated operation labels. */
  effects: number | null;
}
export type DiagnosticRequirementKind =
  | "arithmetic"
  | "ordered"
  | "equality"
  | "integer"
  | "field"
  | "writable_field"
  | "dispatch"
  | "result_dispatch"
  | "monad_factory"
  | "resolver_dispatch"
  | "resolver_shape"
  | "effect_operation"
  | "effect_handler"
  | "receiver"
  | "update"
  | "type_rep"
  | "effect_rep"
  | "type_head"
  | "collection"
  | "record_merge";
export interface DiagnosticRequirement {
  kind: DiagnosticRequirementKind;
  name: string | null;
  subject: number;
  argument: number | null;
  result: number | null;
  signature: number | null;
  explicit: boolean;
}
export interface TypedHoleDiagnostic {
  expected: number;
  nodes: DiagnosticType[];
  edges: { name: string | null; type: number }[];
  scope: { name: string; type: number; requirements: DiagnosticSpan }[];
  requirements: DiagnosticRequirement[];
  /** The enclosing binding's declared/inferred scheme requirements. */
  enclosing: DiagnosticSpan;
  truncated: boolean;
}

const kinds = new Set<DiagnosticTypeKind>([
  "truncated",
  "absent",
  "unit",
  "boolean",
  "u32",
  "f32",
  "never",
  "variable",
  "function",
  "product",
  "record",
  "nominal",
  "array",
  "list",
  "cursor",
  "demand",
  "type_constructor",
  "resolver",
  "provider",
  "state_provider",
  "effects",
  "operation",
  "row_variable",
  "row_parameter",
]);
const predicates = new Set<DiagnosticRequirementKind>([
  "arithmetic",
  "ordered",
  "equality",
  "integer",
  "field",
  "writable_field",
  "dispatch",
  "result_dispatch",
  "monad_factory",
  "resolver_dispatch",
  "resolver_shape",
  "effect_operation",
  "effect_handler",
  "receiver",
  "update",
  "type_rep",
  "effect_rep",
  "type_head",
  "collection",
  "record_merge",
]);
/** Validate graph bounds before exposing a compiler peer's structured payload. */
export function readTypedHole(value: unknown): TypedHoleDiagnostic {
  const fail = (): never => {
    throw new TypeError("Invalid typed-hole diagnostic");
  };
  const object = (v: unknown): Record<string, unknown> =>
    v && typeof v === "object" && !Array.isArray(v)
      ? v as Record<string, unknown>
      : fail();
  const uint = (v: unknown): number =>
    Number.isSafeInteger(v) && (v as number) >= 0 &&
      (v as number) <= 0xffff_ffff
      ? v as number
      : fail();
  const array = (v: unknown, max: number): unknown[] =>
    Array.isArray(v) && v.length <= max ? v : fail();
  let textBytes = 0;
  const encoder = new TextEncoder();
  const text = (v: unknown, nullable = true): void => {
    if (nullable && v === null) return;
    if (typeof v !== "string" || !v.isWellFormed()) fail();
    textBytes += encoder.encode(v as string).length;
    if (textBytes > 16384) fail();
  };
  const hole = object(value);
  const nodes = array(hole.nodes, 1025);
  const edges = array(hole.edges, 4096);
  const scope = array(hole.scope, 32);
  const requirements = array(hole.requirements, 64);
  const ref = (v: unknown, nullable = false): void => {
    if (nullable && v === null) return;
    if (uint(v) >= nodes.length) fail();
  };
  const span = (v: unknown, bound: number): void => {
    const s = object(v);
    if (uint(s.start) + uint(s.len) > bound) fail();
  };
  ref(hole.expected);
  if (typeof hole.truncated !== "boolean") fail();
  span(hole.enclosing, requirements.length);
  const edgeOwners = new Uint8Array(edges.length);
  for (const raw of nodes) {
    const node = object(raw);
    if (!kinds.has(node.kind as DiagnosticTypeKind)) fail();
    text(node.name);
    if (node.identity !== null) {
      const identity = object(node.identity);
      uint(identity.unit);
      uint(identity.decl);
    }
    if (node.variable !== null) uint(node.variable);
    span(node.children, edges.length);
    const children = node.children as unknown as DiagnosticSpan;
    for (let i = children.start; i < children.start + children.len; i++) {
      if (edgeOwners[i]) fail();
      edgeOwners[i] = 1;
    }
    ref(node.effects, true);
  }
  for (const raw of edges) {
    const edge = object(raw);
    text(edge.name);
    ref(edge.type);
  }
  for (const raw of scope) {
    const binding = object(raw);
    text(binding.name, false);
    ref(binding.type);
    span(binding.requirements, requirements.length);
  }
  for (const raw of requirements) {
    const requirement = object(raw);
    if (!predicates.has(requirement.kind as DiagnosticRequirementKind)) fail();
    text(requirement.name);
    ref(requirement.subject);
    ref(requirement.argument, true);
    ref(requirement.result, true);
    ref(requirement.signature, true);
    if (typeof requirement.explicit !== "boolean") fail();
  }
  // A malformed peer must not introduce cycles that recursive editor walkers
  // could follow forever. Checking this flat graph is O(nodes + edges).
  const color = new Uint8Array(nodes.length);
  for (let root = 0; root < nodes.length; root++) {
    if (color[root]) continue;
    const stack: { id: number; exit: boolean }[] = [{ id: root, exit: false }];
    while (stack.length) {
      const frame = stack.pop()!;
      if (frame.exit) {
        color[frame.id] = 2;
        continue;
      }
      if (color[frame.id] === 1) fail();
      if (color[frame.id] === 2) continue;
      color[frame.id] = 1;
      stack.push({ id: frame.id, exit: true });
      const node = nodes[frame.id] as unknown as DiagnosticType;
      if (node.effects !== null) stack.push({ id: node.effects, exit: false });
      for (let i = 0; i < node.children.len; i++) {
        stack.push({
          id: (edges[node.children.start + i] as { type: number }).type,
          exit: false,
        });
      }
    }
  }
  return value as TypedHoleDiagnostic;
}
