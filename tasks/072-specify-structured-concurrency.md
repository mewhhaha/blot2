# 072 — Specify structured concurrency

## Status, dependencies, and originating requirements

- **Status:** Complete design — implementation and dependency qualification
  remain separate; no executable feature completion is claimed.
- **Dependencies:** [059](059-reject-escaping-capabilities.md),
  [062](062-implement-resource-cleanup-contracts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 10 / structured
  concurrency; DEMANDS: concurrent forcing boundary. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify task scopes, joining, cancellation, ownership/capability transfer,
disjoint access and host execution.

## Starting point

The runtime supports synchronous/JSPI guest calls but not general structured
tasks. Tasks 059/062 provide capability and cleanup contracts;
[zig-native/DEMANDS.md](../zig-native/DEMANDS.md) explicitly leaves concurrent
forcing unspecified.

## Implementation checklist

- [x] Settle task/spawn/join syntax and APIs, lifetime nesting, failure
      propagation, cancellation and cleanup order.
- [x] Define ownership and capability transfer, allowed sharing, disjoint-access
      evidence and host scheduling integration.
- [x] Specify demand forcing across tasks, synchronization/state rules or
      explicit rejection, and permitted nondeterminism.
- [x] Document artifact/ABI compatibility, diagnostics and acceptance traces for
      tasks 073–074.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review nested tasks, sibling failure, cancellation during suspension, shared
  demand attempts and resource cleanup.
- Trace race-prone aliases, disjoint slices, capability escape and host
  exceptions.

## Acceptance criteria

- [x] Durable task semantics settle syntax, representation, diagnostics,
      transfer and cancellation rules.
- [x] Demand and host interactions are explicit; concurrency is not inferred
      from existing effect labels.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Source milestone: isolated design checkpoint based on `ef57ec5`; no compiler
  source or executable fixtures changed in this specification checkpoint.
- Durable record:
  [Structured Concurrency](../zig-native/STRUCTURED_CONCURRENCY.md).
- Validation: `deno fmt --no-config --check` on the four specifications and task
  records, plus local path/heading validation; results recorded in
  [design qualification](../zig-native/LANGUAGE_DESIGN_QUALIFICATION.md).
- Comparison: documentation only; no runtime or compiler performance claim.
- Remaining limitations: dependent implementation tasks remain open. The design
  fixes syntax, ownership/identity, portable evidence and rejection boundaries;
  it does not claim those mechanisms are executable or qualified yet.
