# 101 — Reach the literal-edit target

## Status, dependencies, and originating requirements

- **Status:** Pending — split from task 084 by owner decision on 15 October
  2026; no completion is claimed.
- **19 October 2026:** the literal edit is about 1.0 s; see task 093's note.
- **Dependencies:** [084](084-qualify-the-complete-program.md),
  [086](086-retain-constant-evaluation-across-revisions.md),
  [093](093-close-the-gdev-edit-gap.md)
- **Originating requirements:** PLAN: Hill 6 / literal edits under 30 ms.
  Sources: [PLAN.md](../PLAN.md),
  [README final gates](README.md#final-qualification-gates).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A retained scalar literal edit on the pinned workload costs under 30 ms CPU.

## Starting point

Task [093](093-close-the-gdev-edit-gap.md) brought gdev retained literal edits
to about 440 ms against 400 ms at `f7be6e7`; that is about 13x the target, so
finishing 093 does not finish this task. Task
[086](086-retain-constant-evaluation-across-revisions.md) found unchanged
inference and backend preparation, not constant evaluation, dominating the
captured project's retained edit. Since 17 October 2026, 086 is gated on a
release measurement of unaffected-constant work; if 086 closes as not needed,
that measured constant cost becomes one of the costs this task attributes.

## Implementation checklist

- [ ] Attribute retained literal-edit CPU on the 084 workload by phase,
      including integrity checks, inference replay, fragment lookup and
      assembly.
- [ ] Skip work whose inputs the literal cannot affect, keeping fresh/retained
      byte equality, diagnostics and failed-revision rollback.
- [ ] Record every remaining cost that blocks the target with its reason.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Measure on the workload pinned by task
[084](084-qualify-the-complete-program.md): alternating paired runs against the
084 baseline compiler, child user plus system CPU, persistence settings stated,
fresh/retained Wasm and diagnostics byte-identical.

## Acceptance criteria

- [ ] Retained literal edits on the 084 workload cost under 30 ms CPU, or each
      remaining cost is attributed and the gap stays open.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task.
- Comparison: pending; record baseline/candidate hashes and paired distributions
  on the 084 workload.
- Remaining limitations: not yet assessed.
- Durable record: pending; link qualification outside `tasks/` before cleanup.
