# 042 — Specify ragged builders

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [011](011-reduce-semantic-allocation-traffic.md),
  [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / ragged builders.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify when ragged construction may use counting/sizing passes and direct final
storage.

## Starting point

[exact_builder.zig](../zig-native/src/exact_builder.zig) handles up to four
rectangular finite generators;
[eval_indexed_builder.zig](../zig-native/src/eval_indexed_builder.zig) handles
private staged updates. Ragged, filtered and effectful regions currently keep
ordinary builders.

## Implementation checklist

- [ ] Define source-shape admission, representation, counting/filling APIs and
      ownership of scratch/final storage.
- [ ] Specify purity, termination, traps, repeated evaluation, filters,
      dependent dimensions, integer overflow and empty dimensions.
- [ ] Require identical observable order and exceptions; define conservative
      fallback where a sizing pass would duplicate work observably.
- [ ] Document durable examples and performance metrics for runtime and constant
      evaluation.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review nested dependent bounds, pure-but-trapping predicates, side effects,
  all-filtered results and overflow before allocation.
- Compare proposed counting/filling traces with the ordinary builder and record
  rejected cases.

## Acceptance criteria

- [ ] A durable specification unambiguously admits or rejects each
      counting/sizing scenario.
- [ ] Task 043 has defined APIs, semantics, layouts, diagnostics and executable
      acceptance examples.
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
