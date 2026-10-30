# 100 — Reach the cold compilation target

## Status, dependencies, and originating requirements

- **Status:** Pending — split from task 084 by owner decision on 15 October
  2026; no completion is claimed.
- **19 October 2026:** cold gdev game is about 2.3 s wall through serve-project
  with 4 codegen workers (CT89), from 3.0 s CPU at the CT1 baseline. See
  [COMPILE_HILLS.md](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/COMPILE_HILLS.md).
- **Dependencies:** [084](084-qualify-the-complete-program.md)
- **Originating requirements:** PLAN: final performance / cold compilation of
  approximately 500 ms. Sources: [PLAN.md](../PLAN.md),
  [README final gates](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#final-qualification-gates).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Fresh compilation of the pinned workload costs approximately 500 ms CPU with
persistence disabled.

## Starting point

The only qualified cold figure is about 647 ms CPU on the earlier frozen private
gdev workload ([STATUS.md](../zig-native/STATUS.md)). That manifest was waived
on 11 October 2026; it does not describe the current 415-input captured project.
Task 084 measures the current cold cost and records the gap here.

## Implementation checklist

- [ ] Attribute fresh CPU by phase (parse, check, evaluation, backend, emission)
      with deterministic counters and a profile on the pinned workload.
- [ ] Remove costs that do not pay for themselves while keeping judgments,
      diagnostics and Wasm identical.
- [ ] Record every remaining cost that blocks the target with its reason.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Measure on the workload pinned by task
[084](084-qualify-the-complete-program.md): alternating paired runs against the
084 baseline compiler, child user plus system CPU, persistence settings stated,
fresh/retained Wasm and diagnostics byte-identical.

## Acceptance criteria

- [ ] Fresh compilation of the 084 workload is approximately 500 ms CPU in
      paired measurements, or each remaining cost is attributed and the gap
      stays open.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task.
- Comparison: pending; record baseline/candidate hashes and paired distributions
  on the 084 workload.
- Remaining limitations: not yet assessed.
- Durable record: pending; link qualification outside `tasks/` before cleanup.
