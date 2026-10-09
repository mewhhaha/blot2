# 072 — Specify structured concurrency

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [059](059-reject-escaping-capabilities.md),
  [062](062-implement-resource-cleanup-contracts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 10 / structured
  concurrency; DEMANDS: concurrent forcing boundary. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify task scopes, joining, cancellation, ownership/capability transfer,
disjoint access and host execution.

## Starting point

The runtime supports synchronous/JSPI guest calls but not general structured
tasks. Tasks 059/062 provide capability and cleanup contracts;
[zig-native/DEMANDS.md](../zig-native/DEMANDS.md) explicitly leaves concurrent
forcing unspecified.

## Implementation checklist

- [ ] Settle task/spawn/join syntax and APIs, lifetime nesting, failure
      propagation, cancellation and cleanup order.
- [ ] Define ownership and capability transfer, allowed sharing, disjoint-access
      evidence and host scheduling integration.
- [ ] Specify demand forcing across tasks, synchronization/state rules or
      explicit rejection, and permitted nondeterminism.
- [ ] Document artifact/ABI compatibility, diagnostics and acceptance traces for
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

- [ ] Durable task semantics settle syntax, representation, diagnostics,
      transfer and cancellation rules.
- [ ] Demand and host interactions are explicit; concurrency is not inferred
      from existing effect labels.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
