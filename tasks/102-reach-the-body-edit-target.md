# 102 — Reach the general body-edit target

## Status, dependencies, and originating requirements

- **Status:** Pending — split from task 084 by owner decision on 15 October
  2026; no completion is claimed.
- **19 October 2026:** the body edit is about 1.23 s; see task 024's note.
- **Dependencies:** [084](084-qualify-the-complete-program.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** PLAN: Hill 6 / general body edits under 100 ms.
  Sources: [PLAN.md](../PLAN.md),
  [README final gates](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#final-qualification-gates).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

A general function-body edit with an unchanged interface on the pinned workload
costs under 100 ms CPU.

## Starting point

Task [024](024-apply-general-body-interface-cutoff.md) admits many body forms to
interface cutoff, but the captured project's retained edit is still about
0.9–1.3 s. 024's own analysis names the structural blockers: every body of an
edited module is rechecked, Core node and type IDs are module-global, and the
symbol table is ordered by first use. Adding admitted forms one at a time does
not remove those blockers.

By owner decision on 17 October 2026, task 024 closes against fixed acceptance
rows. The body forms it leaves on ordinary checking (listed in
[024's closed acceptance](024-apply-general-body-interface-cutoff.md#closed-acceptance--owner-decision-17-october-2026))
move here: admit one only when attribution on the 084 workload shows it among
the costs blocking the target, otherwise record it as an attributed remaining
cost.

## Implementation checklist

- [ ] Recheck only changed bodies, or record why the module must be rechecked.
- [ ] Make declaration-local IDs and symbol order stable across edits that add
      nodes, types or identifier spellings, or record why not.
- [ ] Attribute and remove the remaining retained body-edit costs on the 084
      workload, including body forms that 024 leaves on ordinary checking,
      keeping byte equality and rollback.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Measure on the workload pinned by task
[084](084-qualify-the-complete-program.md): alternating paired runs against the
084 baseline compiler, child user plus system CPU, persistence settings stated,
fresh/retained Wasm and diagnostics byte-identical.

## Acceptance criteria

- [ ] General body edits on the 084 workload cost under 100 ms CPU, or each
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
