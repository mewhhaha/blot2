# 103 — Bound the largest inference region

## Status, dependencies, and originating requirements

- **Status:** Pending — split from task 084 by owner decision on 15 October
  2026; no completion is claimed.
- **Dependencies:** [084](084-qualify-the-complete-program.md)
- **Originating requirements:** PLAN: final performance / largest inference
  region under 50 ms. Sources: [PLAN.md](../PLAN.md),
  [README final gates](README.md#final-qualification-gates).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

No single inference region in the pinned workload takes 50 ms CPU or more.

## Starting point

The earlier gdev baseline's largest region had 8,041 scopes; task 086 once
measured one entry constant's nested inference at about 276 ms before task 088
let that region replay. No current per-region timing exists for the 084
workload.

## Implementation checklist

- [ ] Report per-region CPU and scope counts for the 084 workload, fresh and
      retained.
- [ ] Split, summarize or replay the regions above 50 ms without changing
      judgments or diagnostics.
- [ ] Record every region that still exceeds the bound with its reason.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Measure on the workload pinned by task
[084](084-qualify-the-complete-program.md): alternating paired runs against the
084 baseline compiler, child user plus system CPU, persistence settings stated,
fresh/retained Wasm and diagnostics byte-identical.

## Acceptance criteria

- [ ] The largest inference region on the 084 workload is under 50 ms CPU, or
      each remaining region is attributed and the gap stays open.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task.
- Comparison: pending; record baseline/candidate hashes and paired distributions
  on the 084 workload.
- Remaining limitations: not yet assessed.
- Durable record: pending; link qualification outside `tasks/` before cleanup.
