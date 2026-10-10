# 007 — Infer recursive components jointly

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified at `4f898b0`; joint inference and heap
  scheduling preserve ordinary diagnostics and executed budgets.
- **Dependencies:** [006](006-summarize-lexical-closures.md)
- **Originating requirements:** PLAN: Hills 1–3 / recursive components and depth
  limits. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Infer each recursive component through a bounded joint region and iterative
scheduling.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#recursive-components-and-bounded-scheduling)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

At the task 006 baseline, active recursive targets fell back into their inline
region in [core_eval.zig](../zig-native/src/core_eval.zig). Its call-summary
queue already removes native recursion for admitted acyclic jobs;
[tests/compile_budget.test.ts](../zig-native/tests/compile_budget.test.ts)
preserves deep-chain budgets.

Task 004's source-normalization qualification found a source inquiry that did
not finish for `Seed.build -> parent.read -> Box.read -> parent`, even with
written arrows. Task 007's phase isolation corrects the original frontend
attribution: checking and lowering finish on the baseline, while the ordinary
Core source-interface inquiry does not. The bounded principal-publication cycle
law passes; it does not qualify ordinary recursive inference. Preserve and bound
this direct source case as part of component work. The
[durable investigation](../zig-native/CALL_SUMMARIES.md#live-headers-and-source-normalized-graphs-10-october-2026)
records the probe and separates debug self-backend depth failures from the
passing release LLVM gate.

## Implementation checklist

- [x] Identify recursive components using stable body/call identities and place
      mutually dependent obligations in one joint region.
- [x] Schedule component dependencies iteratively; bound fixed-point work and
      keep executed evaluation depth distinct from inference limits.
- [x] Preserve source-order diagnostics, independent proof publication and
      failed-job cleanup without retaining partial component results.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Cover direct/mutual recursion, polymorphic and higher-order recursion, a
  recursive diamond and an ill-typed recursive leaf.
- Retain annotated chains at 300/1,000, generic chains at 300 and diamond
  execution; test limit exhaustion, OOM and correction after failure.
- Profile largest region time and scope counts on gdev and synthetic components.

## Acceptance criteria

- [x] Every recursive component has bounded joint inference without a
      native-stack depth cliff.
- [x] Limits and failures preserve diagnostic order and leave the session
      reusable; measurements track progress toward the under-50-ms region
      target.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `4f898b0c0c9e7bd7025e84e2d0646ab7d6a7bb94`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 615 guest/client tests. `deno task lint:zig` reports zero findings across
  294 files. Exact comparisons pass 608 public cases / 1,216 invocations, with
  five qualified deep-inference acceptance corrections. Initial output passes 29
  guests / 112 calls; edited output passes 66 guests / 7,188 calls. Limit, OOM,
  same-session retry, diagnostic order, effects and invalid witness laws pass.
- Comparison: immutable task 006 lexical baseline versus the final component
  pin. Fifteen alternating pairs cover 65 common-success workloads; 45
  candidate-only samples cover the three new deep component acceptances. Seven
  alternating retained/restart pairs cover 64 workloads / 5,376 phase samples,
  with no parity problems. Exact hashes, CPU distributions, scope counts and
  profile durations are in the durable record.
- Remaining limitations: the frozen private gdev snapshot is unavailable. This
  public batch's maximum recorded region duration is 35.563 ms; it does not
  prove the under-50-ms target for all programs. The median workload CPU ratio
  is 1.052, and recursive diamond32 rises from 10.872 to 19.634 ms. Component
  rebuilding, duplicate scoped checks and allocation costs remain optimization
  work; no general speedup is claimed.
- Durable record:
  [joint recursive inference](../zig-native/CALL_SUMMARIES.md#joint-recursive-inference-10-october-2026)
  records the implementation, exact pins, all gates, measurements and
  limitations.
