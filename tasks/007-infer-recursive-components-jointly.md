# 007 — Infer recursive components jointly

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [006](006-summarize-lexical-closures.md)
- **Originating requirements:** PLAN: Hills 1–3 / recursive components and depth
  limits. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Infer each recursive component through a bounded joint region and iterative
scheduling.

## Starting point

Active recursive targets currently fall back into their inline region in
[core_eval.zig](../zig-native/src/core_eval.zig). Its call-summary queue already
removes native recursion for admitted acyclic jobs;
[tests/compile_budget.test.ts](../zig-native/tests/compile_budget.test.ts)
preserves deep-chain budgets.

## Implementation checklist

- [ ] Identify recursive components using stable body/call identities and place
      mutually dependent obligations in one joint region.
- [ ] Schedule component dependencies iteratively; bound fixed-point work and
      keep executed evaluation depth distinct from inference limits.
- [ ] Preserve source-order diagnostics, independent proof publication and
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

- [ ] Every recursive component has bounded joint inference without a
      native-stack depth cliff.
- [ ] Limits and failures preserve diagnostic order and leave the session
      reusable; measurements track progress toward the under-50-ms region
      target.
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
