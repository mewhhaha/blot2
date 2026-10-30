# 088 — Restore summary-job inference cost on large programs

## Status, dependencies, and originating requirements

- **Status:** Complete at `86db5b1`; the residual gap to `f7be6e7` is task
  [093](093-close-the-gdev-edit-gap.md).
- **Dependencies:** [085](085-gate-principal-graph-sharing-on-payoff.md)
- **Originating requirements:** discovered while qualifying task
  [085](085-gate-principal-graph-sharing-on-payoff.md); PLAN: Hill 6 / cheap
  edits and Hill 2 / call summaries. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Bring retained-edit inference on large generic programs back to (or below) the
cost before call-summary jobs, without losing their benefits on the qualified
workloads.

## Starting point

On the frozen gdev copy, deterministic counters per retained edit show 433
inference regions at `f7be6e7` and about 1,713 with principal-graph sharing
disabled on the task-085 compiler; inference roughly doubled (about 226k versus
474k µs at comparable load). Single-sample counters per commit place the growth
across `652f4d6` "Describe parametric callback obligations in independent type
jobs", `71c0f2a` "Own lexical capture inputs for independent summary jobs" and
successors; see
[call summaries](../zig-native/CALL_SUMMARIES.md#open-principal-payoff-11-october-2026).
Per-commit gdev binaries from that bisect are in `/var/tmp/bisect-bins/` on the
owner's machine.

## Implementation checklist

- [x] Bisect the region and inference growth with deterministic counters and
      paired CPU, and profile the extra regions.
- [x] Remove the overhead where summary jobs do not pay, keeping equal
      judgments, diagnostics and the qualified summary workloads' benefits.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Pair gdev retained edits and cold builds, the call-summary workloads and the
  public examples against the current compiler.

## Acceptance criteria

- [x] The source of the region/inference growth is identified with evidence.
- [x] Measured inference on gdev drops without regressing the qualified summary
      workloads, or the remaining cost is justified explicitly.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `86db5b19821ace11f5d4d6b9047fec4c0ca87f5e` ("Keep principal input keys
  through recorded summary work").
- Cause: with sharing off, `652f4d6` raised regions per edit from 601 to 1,768
  because consumed callback-input job results counted as unrecorded call reads,
  so `sandbox`'s principal lost its input key; `71c0f2a` added 100–130 ms CPU
  through a lexical capture scan that projected every region scope per closure.
  With sharing on, foreign graph sources and memo facts decided by detached
  graph descriptions also dropped the key.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 635 guest/client tests; `deno task lint:zig` reports zero findings across
  310 files. Native laws (`core_eval.zig`, `core_eval_tests.zig`) and process
  laws (`tests/summary_job_principal_reuse.test.ts`,
  `tests/lexical_capture_scan.test.ts`) each fail against their mutant.
- Comparison: baseline `6275e38` (SHA-256 `3762f868…cb0a`), candidate SHA-256
  `73a2dec7…453f`, `f7be6e7` SHA-256 `b8898fa6…e940`. Five gdev pairs: retained
  edits 780 → 570 ms CPU (0.73×), inference 448 → 240 ms, regions 2,026 → 1,034;
  cold builds 1,260 → 1,170 ms. `f7be6e7` edits: 400 ms, inference 199 ms.
  Diamonds and public examples keep identical counters; the synthetic corpus has
  CPU ratio 1.000 with identical Wasm.
- Remaining limitations: gdev edits cost 1.43× `f7be6e7` (inference +30 ms, and
  lookup, capture and prepare timers +92 ms), now task
  [093](093-close-the-gdev-edit-gap.md). Non-source-complete graphs and jobs
  finished outside a recording still drop principal keys.
- Durable record:
  [summary-job cost](../zig-native/CALL_SUMMARIES.md#summary-job-cost-11-october-2026),
  [CONTRACT.md](../zig-native/CONTRACT.md),
  [pins](../zig-native/qualification/summary-job-cost-pins.json),
  [gdev CSV](../zig-native/qualification/summary-job-cost-gdev.csv) and
  [public results](../zig-native/qualification/summary-job-cost-public.jsonl).
