# 005 — Summarize higher order callees

## Status, dependencies, and originating requirements

- **Status:** In progress — dedicated callback obligations and independent
  higher-order jobs are being implemented; no completion is claimed.
- **Dependencies:** [004](004-summarize-predicate-bearing-callees.md)
- **Originating requirements:** PLAN: Hill 2 / the sandbox region. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Represent obligations of function parameters parametrically and split valid
higher-order calls into independent inference regions.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#higher-order-obligations-and-effects)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

Predicate-free callbacks already use checked schemes. `ClosureRegion` and
`principalEvidence` in [core_eval.zig](../zig-native/src/core_eval.zig) still
combine general higher-order graphs;
[callback_row_tests.zig](../zig-native/src/callback_row_tests.zig) and
[tests/callback_row_execution.test.ts](../zig-native/tests/callback_row_execution.test.ts)
cover latent callback rows.

## Implementation checklist

- [ ] Implement the callback-obligation form specified in task 003, including
      generic argument/result relationships and latent effects.
- [ ] Partition only when complete callback evidence permits it, preserving
      callback captures and source-interface checks.
- [ ] Distinguish unresolved or escaping callback facts from principal
      information and preserve the bounded conservative fallback.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Exercise pure/effectful reducers, callbacks returning callbacks, unused
  callback rows, incompatible results and imported generic combinators.
- Test same code with different captures, providers and callback evidence
  through fresh, retained, checkpoint and dependency paths.
- Measure the sandbox region and higher-order fan-out work; compare diagnostic
  order and OOM recovery.

## Acceptance criteria

- [ ] Valid higher-order jobs no longer require their entire transitive graph in
      one region.
- [ ] Callback effects and captures remain exact, and unresolved cases retain
      correct diagnostics without unbounded retry.
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
