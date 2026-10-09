# 004 — Summarize predicate bearing callees

## Status, dependencies, and originating requirements

- **Status:** Ready — design dependency 003 is complete; no implementation
  completion is claimed.
- **Dependencies:** [003](003-specify-general-call-summaries.md)
- **Originating requirements:** PLAN: Hill 1 / generic callee sharing. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Share checked predicate-bearing callee summaries without unfolding the
transitive call graph at each use.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#admission-and-caller-interface)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

[check_shared_scheme_tests.zig](../zig-native/src/check_shared_scheme_tests.zig)
covers frontend scheme sharing; [core_eval.zig](../zig-native/src/core_eval.zig)
admits declared global schemes only when residual predicates are absent.
`collectCall`, the summary queue and `validated_calls` are the integration
points for task 003.

## Implementation checklist

- [ ] Instantiate residual predicates with fresh region-local variables and
      preserve argument/result-directed obligations and effect rows.
- [ ] Schedule dependency summaries iteratively and publish only complete
      judgments. Preserve deferred checking, reachability and independently
      successful proofs.
- [ ] Keep ordinary collection as the authoritative failure path; do not infer
      principal facts from a caller-selected implementation or introduce
      name-based optimizations.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Extend native shared-scheme and call-summary execution laws with
  associated/member/field/operation predicates, imports, repeated diamonds and
  deep chains.
- Compare ordered diagnostics for missing or incompatible evidence at an
  argument witness, unused versus reachable code, and failed-edit correction.
- Round-trip dependency bundles/checkpoints and run allocation-failure sweeps
  over queue creation and publication; profile scopes and constraint visits.

## Acceptance criteria

- [ ] Repeated predicate-bearing uses share the checked result under complete
      inputs, with bounded graph work.
- [ ] Fallback diagnostic order, execution, recovery and ownership match
      ordinary checking; deterministic counters show the intended reduction.
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
