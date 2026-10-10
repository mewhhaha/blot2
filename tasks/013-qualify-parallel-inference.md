# 013 — Qualify parallel inference

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified opt-in; the default remains serial.
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

- [x] Pin compiler/library/workload hashes and measure one worker plus multiple
      feasible worker counts on an idle machine.
- [x] Separate coordination, allocation and job costs for small and large
      workloads, fresh compilation and retained phases.
- [x] Choose and document a workload threshold/default only if paired CPU and
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

- [x] Durable evidence records every tested worker count and a justified
      default-or-opt-in decision.
- [x] No default enablement occurs without both CPU and wall improvements;
      equivalence and failure gates pass.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `4c61f25635a157c3f8e729af9f712f275e9cabe6` (local compiler milestone).
- Validation: Zig 0.17.0; full LLVM native suite and 621 guest/client tests via
  `deno task test:compiler`; `deno task lint:zig` checks 297 files with zero
  findings; 25 focused ownership tests, package/API/publish dry run and affected
  formatting pass. Task-012 equivalence: 626 cases / 3,756 invocations, ordered
  diagnostics and exact Wasm, all zero-live; 192 guests / 10,362 calls. Retained
  six-policy edits/failures/recovery/checkpoint restart: 2,106 successful
  samples, 648 guests / 41,208 original and edited calls.
- Comparison: task-011 baseline versus candidate default and workers 1/2/4/8; 83
  workloads / 15 alternating rounds / 7,470 fresh builds. Seven rounds on eight
  retained workloads yield 28,224 phases plus 1,008 production CLI
  fresh/cache-population/restart builds. Profiling separately compares 10,080
  retained phases and 120 fresh builds against unprofiled bytes/work/retained
  storage. All repeated phase plateaus and zero teardown checks pass.
- Decision: serial remains the default. Fresh geometric-mean CPU/wall ratios
  versus serial are 1.0692/1.0674 (1), 1.1292/1.1014 (2), 1.1517/1.1175 (4) and
  1.1740/1.1362 (8). No stable size threshold improves both total CPU and wall
  across fresh and retained phases; job-only phase gains do not qualify default
  enablement. Allocation distributions report worker overhead explicitly.
- Remaining limitations: four-CPU cgroup quota, uncontrolled
  shared-host/filesystem caches, executor/thread storage outside compiler
  requested bytes, overlapping private job wall sums and unsupported-context
  serial fallbacks. Historical boxed/private gdev artifacts remain absent; no
  private application or general speedup claim is made.
- Durable record: [policy qualification](../zig-native/SEMANTIC_WORKERS.md)
  links exact compiler/driver/library/workload hashes, scheduler/cgroup
  snapshots and complete fresh/retained/profiling distributions outside
  `tasks/`.
