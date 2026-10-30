# 084 — Qualify the complete program

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [082](082-qualify-the-remote-analyzer-workflow.md),
  [083](083-review-and-clean-old-build-artifacts.md),
  [085](085-gate-principal-graph-sharing-on-payoff.md),
  [086](086-retain-constant-evaluation-across-revisions.md),
  [087](087-skip-rebuilds-for-trivia-only-edits.md),
  [088](088-restore-summary-job-inference-cost.md),
  [089](089-report-inference-budget-exhaustion.md),
  [090](090-make-pending-check-solving-incremental.md),
  [091](091-bound-evaluation-by-call-depth.md),
  [092](092-format-current-syntax.md), [093](093-close-the-gdev-edit-gap.md),
  [094](094-locate-specialization-failures-at-their-use.md),
  [095](095-specify-and-version-the-project-protocol.md),
  [096](096-compile-typed-asset-imports-natively.md),
  [097](097-resolve-array-cursor-representation-in-gdev-fixtures.md),
  [098](098-type-check-recursive-demand-forwarding.md),
  [099](099-survive-long-stage-chains-without-crashing.md)
- **Originating requirements:** PLAN: All open programs and final performance
  gates. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Audit full scope coverage and qualify the completed semantic, runtime, language,
tooling and performance program.

## Starting point

The task index and coverage matrix track implementation and external gates.
[zig-native/STATUS.md](../zig-native/STATUS.md) must hold current qualified
results rather than the starting baseline.

## Implementation checklist

- [ ] Audit every mapped requirement and predecessor evidence; verify that
      design/prototype completion has not been substituted for feature
      completion.
- [ ] Run final semantic/ownership, sync/JSPI, editor, packaging, analyzer,
      source-layout, dependency/checkpoint, retained/restart and failed-edit
      recovery gates.
- [x] Pin the owner-approved recreated gdev workload and record its manifest
      durably: 583 files and 69 test entries, with exact source and manifest
      hashes in
      [current qualification](../zig-native/CLOUD_QUALIFICATION.md#current-workload-pin).
- [ ] Measure that workload against pinned baselines in paired runs, including
      cold/population/first-edit/later-edit/no-op/restart/recovery and guest
      runtime/memory.
- [ ] Record each performance row's measured value and gap in its follow-up
      task: cold compilation [100](100-reach-the-cold-compilation-target.md),
      literal edits [101](101-reach-the-literal-edit-target.md), general body
      edits [102](102-reach-the-body-edit-target.md), largest inference region
      [103](103-bound-the-largest-inference-region.md) and requested allocation
      [104](104-reduce-requested-allocation-below-100-mb.md).
- [ ] Keep every missed requirement open. Add bounded numbered follow-up tasks
      before 999, update coverage/dependencies and finish them before cleanup.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Run the final qualification command set in README with exact revisions, binary
  hashes and workload manifests.
- Measure cold CPU, literal edits, general body edits, the largest inference
  region and cumulative requested allocation on the pinned workload. By owner
  decision on 15 October 2026 these five targets are owned by tasks 100–104;
  this task records the measurements and does not close them.
- Verify no duplicate regions for a complete canonical key, qualified tracing
  replacement, closed traversal regression, full new language/demand gates and
  complete remote/tooling evidence.

## Acceptance criteria

- [ ] Every non-performance row of the README final-gate table passes with
      durable evidence; a missed target keeps the task incomplete. The five
      performance rows are measured, recorded and handed to tasks 100–104.
- [ ] All discovered follow-ups and external gates are complete and the
      directory is ready for the conditional cleanup audit.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Partial qualification: the current workload pin and the executed compiler gate
  are recorded in [current qualification](../zig-native/CLOUD_QUALIFICATION.md).
  The other predecessor requirements, final-source analyzer gate and complete
  final measurement set remain open; this does not complete task 084.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
