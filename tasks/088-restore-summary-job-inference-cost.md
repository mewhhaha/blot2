# 088 — Restore summary-job inference cost on large programs

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** [085](085-gate-principal-graph-sharing-on-payoff.md)
- **Originating requirements:** discovered while qualifying task
  [085](085-gate-principal-graph-sharing-on-payoff.md); PLAN: Hill 6 / cheap
  edits and Hill 2 / call summaries. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

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

- [ ] Bisect the region and inference growth with deterministic counters and
      paired CPU, and profile the extra regions.
- [ ] Remove the overhead where summary jobs do not pay, keeping equal
      judgments, diagnostics and the qualified summary workloads' benefits.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Pair gdev retained edits and cold builds, the call-summary workloads and the
  public examples against the current compiler.

## Acceptance criteria

- [ ] The source of the region/inference growth is identified with evidence.
- [ ] Measured inference on gdev drops without regressing the qualified summary
      workloads, or the remaining cost is justified explicitly.
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
