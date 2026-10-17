# 046 — Implement composable summary trees

## Status, dependencies, and originating requirements

- **Status:** Complete — persistent AVL APIs and release qualification at
  `4013b10`.
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
[list_runtime.zig](../zig-native/src/runtime/list_runtime.zig) supplies
persistent tree techniques, but no general summary-tree API is assumed.

## Implementation checklist

- [x] Build balanced owned summaries and compose them in the specified order
      with explicit empty identities.
- [x] Implement range queries and persistent updates that preserve old versions
      and reference ownership.
- [x] Respect admissible algebra/numeric behavior and bound tree depth and
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

- [x] Construction, combination, query and persistent-update APIs satisfy all
      specified algebraic laws.
- [x] Measured asymptotic behavior and memory match the documented guarantees
      with snapshots intact.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `4013b10`.
- Validation: Zig 0.17.0; full native/OOM, 961 guest/client tests, both tiers,
  eight unchanged budgets and 351 analyzer files/zero. Shared 2^31-leaf bounds,
  references/cycles, saved versions and retained/restart failures pass.
- Comparison: 31 alternating warmed pairs show linear scalar build, logarithmic
  callback paths, faster interval queries and measured costs versus exclusive
  Array edits. Memory charges current/original and 64 saved versions separately.
  LLVM/source/report pins are in
  `build/bench/joint-024-035-045-046/qualification-pins.json`.
- Remaining limitations: caller algebra consistency; real retained summary
  graphs and ordinary cycle-collection cost; no universal update speedup.
- Durable record:
  [Rolling and summary qualification](../zig-native/ROLLING_SUMMARIES_QUALIFICATION.md).
