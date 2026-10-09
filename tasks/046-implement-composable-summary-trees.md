# 046 — Implement composable summary trees

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [045](045-implement-rolling-reductions.md)
- **Originating requirements:** PLAN: Earlier programs / composable summary
  trees. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement summary construction, combination, queries and persistent updates with
the specified laws.

## Starting point

Task 044 defines summary APIs and task 045 establishes reducer behavior.
[list_runtime.zig](../zig-native/src/list_runtime.zig) supplies persistent tree
techniques, but no general summary-tree API is assumed.

## Implementation checklist

- [ ] Build balanced owned summaries and compose them in the specified order
      with explicit empty identities.
- [ ] Implement range queries and persistent updates that preserve old versions
      and reference ownership.
- [ ] Respect admissible algebra/numeric behavior and bound tree depth and
      invalid-range handling.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare construction and range queries with reference folds over uneven
  partitions, empty ranges and tree boundaries.
- Update one leaf while retaining old versions; test shared children,
  noncommutative summaries and invalid indices.
- Measure construction/query/update scaling, retained storage and long-running
  cleanup.

## Acceptance criteria

- [ ] Construction, combination, query and persistent-update APIs satisfy all
      specified algebraic laws.
- [ ] Measured asymptotic behavior and memory match the documented guarantees
      with snapshots intact.
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
