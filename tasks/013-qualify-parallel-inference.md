# 013 — Qualify parallel inference

## Status, dependencies, and originating requirements

- **Status:** In progress — worker CPU/wall and allocation qualification is
  next; no completion or default enablement is claimed.
- **Dependencies:** [011](011-reduce-semantic-allocation-traffic.md),
  [012](012-schedule-independent-semantic-jobs.md)
- **Originating requirements:** PLAN: Hill 9 / default policy qualification.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Qualify parallel inference across worker counts and enable it by default only
when both CPU and wall time improve.

## Starting point

Task 012 supplies isolated jobs;
[execution_policy.zig](../zig-native/src/execution_policy.zig) and
[scripts/bench_compile.ts](../scripts/bench_compile.ts) are the policy and
measurement boundaries. Previous worker measurements were dominated by one
region and do not justify a default change.

## Implementation checklist

- [ ] Pin compiler/library/workload hashes and measure one worker plus multiple
      feasible worker counts on an idle machine.
- [ ] Separate coordination, allocation and job costs for small and large
      workloads, fresh compilation and retained phases.
- [ ] Choose and document a workload threshold/default only if paired CPU and
      wall time improve. Otherwise retain a qualified opt-in path with its
      limitations.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run alternating measurements with scheduler conditions recorded; do not treat
  SCHED_IDLE wall-time noise as a gain.
- Require deterministic diagnostics, work results and emitted bytes for every
  worker count, including failure/cancellation and restart.
- Compare allocation/peak memory against task 011 and report distributions,
  overhead and negative results.

## Acceptance criteria

- [ ] Durable evidence records every tested worker count and a justified
      default-or-opt-in decision.
- [ ] No default enablement occurs without both CPU and wall improvements;
      equivalence and failure gates pass.
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
