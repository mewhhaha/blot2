# 042 — Specify ragged builders

## Status, dependencies, and originating requirements

- **Status:** Complete.
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

- [x] Define source-shape admission, representation, counting/filling APIs and
      ownership of scratch/final storage.
- [x] Specify purity, termination, traps, repeated evaluation, filters,
      dependent dimensions, integer overflow and empty dimensions.
- [x] Require identical observable order and exceptions; define conservative
      fallback where a sizing pass would duplicate work observably.
- [x] Document durable examples and performance metrics for runtime and constant
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

- [x] A durable specification unambiguously admits or rejects each
      counting/sizing scenario.
- [x] Task 043 has defined APIs, semantics, layouts, diagnostics and executable
      acceptance examples.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `a1df44d`.
- Validation: Deno 2.9.7;
  `deno fmt --no-config --check
  zig-native/RAGGED_BUILDERS.md zig-native/CONTRACT.md`
  passes. The shared local path/heading check validates 29
  specification/contract links before adding the final contract link to this
  file. Triangle/filter arithmetic and trapping guard/bound traces agree with
  the current guide.
- Comparison: documentation only; no compiler source or executable fixture
  changed. Task 043 owns executed parity and runtime/compiler measurements.
- Remaining limitations: initial admission has four finite generators and
  bounded pure/total controls and payloads. Unknown, effectful, trapping,
  allocating or observably intermediate construction remains ordinary.
- Durable record: [RAGGED_BUILDERS](../zig-native/RAGGED_BUILDERS.md).
