# 010 — Schedule constraints by variable

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [009](009-cache-composite-type-resolutions.md)
- **Originating requirements:** PLAN: Hill 5 / indexed solver worklist. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Replace repeated whole-region scans with variable-indexed constraint and alias
worklists.

## Starting point

`ClosureRegion.solveMode`, `solveStep` and `solveDataAliases` in
[core_eval.zig](../zig-native/src/core_eval.zig) repeatedly scan work.
[types.zig](../zig-native/src/types.zig) owns chronological writes;
[work_counters.zig](../zig-native/src/work_counters.zig) records passes and
visits.

## Implementation checklist

- [ ] Index each constraint and data alias by every variable/effect dependency
      that can make it ready, updating watches as resolutions change.
- [ ] Enqueue affected work on writes, preserve fixed-point completeness, and
      make queue ordering reproduce authoritative source diagnostics.
- [ ] Handle new constraints, rollback, component re-entry and unsolved
      obligations without missed wakeups or infinite retries.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare worklist and existing solver behavior over chains, diamonds, row
  aliases, callback effects and mutually recursive components.
- Test constraints added during solving, multiple writes before dequeue,
  unresolved cycles, limits and OOM cleanup.
- Record solver passes/constraint visits and paired fresh/retained CPU; tighten
  applicable compile budgets after demonstrated reductions.

## Acceptance criteria

- [ ] All dependency changes wake the necessary constraints and aliases and
      reach the same fixed point and diagnostic order.
- [ ] Repeated unrelated full scans disappear in measured workloads without an
      allocation or recovery regression.
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
