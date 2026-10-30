# 104 — Reduce requested allocation below 100 MB

## Status, dependencies, and originating requirements

- **Status:** Pending — split from task 084 by owner decision on 15 October
  2026; no completion is claimed.
- **19 October 2026:** final solver capacities are 109 MB, led by effect rows at
  37 MB (CT56, deferred). Getting under 100 MB needs solver stores that outlive
  a region's arena. CT60 and CT61 raised requested allocation to 266 MB (solver)
  and 132 MB (scratch). See
  [COMPILE_HILLS.md](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md).
- **Dependencies:** [084](084-qualify-the-complete-program.md)
- **Originating requirements:** PLAN: Hill 7 / under-100-MB cumulative requested
  allocation. Sources: [PLAN.md](../PLAN.md),
  [README final gates](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#final-qualification-gates).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Fresh compilation of the pinned workload requests under 100 MB cumulative
compiler allocation, measured separately from live memory and RSS.

## Starting point

The qualified starting value was 321.2 MB cumulative requested allocation on the
earlier gdev workload ([STATUS.md](../zig-native/STATUS.md)). Task
[011](011-reduce-semantic-allocation-traffic.md) attributes allocation by owner.
No current figure exists for the 084 workload.

## Implementation checklist

- [ ] Attribute cumulative requested allocation by owner on the 084 workload.
- [ ] Remove redundant copies and temporary buffers, keeping atomic publication
      and allocation-failure cleanup.
- [ ] Record every remaining owner that blocks the target with its reason.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Measure on the workload pinned by task
[084](084-qualify-the-complete-program.md): alternating paired runs against the
084 baseline compiler, child user plus system CPU, persistence settings stated,
fresh/retained Wasm and diagnostics byte-identical.

## Acceptance criteria

- [ ] Cumulative requested allocation on the 084 workload is under 100 MB, or
      each remaining owner is attributed and the gap stays open.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task.
- Comparison: pending; record baseline/candidate hashes and paired distributions
  on the 084 workload.
- Remaining limitations: not yet assessed.
- Durable record: pending; link qualification outside `tasks/` before cleanup.
