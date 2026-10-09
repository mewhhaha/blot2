# 004 — Summarize predicate bearing callees

## Status, dependencies, and originating requirements

- **Status:** In progress — the written-predicate milestone is qualified;
  general summaries remain unfinished.
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
now admits checked written predicates on first-order global schemes alongside
the original predicate-free path. Inferred predicates and general graphs still
need wider admission and proof sharing. `collectCall`, the summary queue and
`validated_calls` are the integration points for task 003.

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

- Commit: `fd8cd3f` lands the qualified checked written-predicate milestone; it
  does not complete task 004.
- Baseline: with the qualified task 001 compiler (SHA-256
  `034d660ce38691df9a18c895ab228c4d0a76d618aa1969117d16604e06ee2833`), an
  explicit associated-predicate chain grows from 36 scopes at 16 wrappers to 260
  scopes at 128 wrappers. At 128 wrappers an explicit field chain uses 130
  scopes. Reproduction sources and results are in
  `build/bench/call-summary-explicit-baseline/`.
- Isolated investigation:
  `/tmp/blot-list-field-prototype/zig-native/src/core_eval.zig` currently
  contains a task 004 probe, separate from the main working tree's task 002
  candidate. It admits explicit dispatch, field and update obligations through
  the existing fresh-variable job path and classifies shared callee graphs once,
  propagating rejected descendants to their ancestors. The original file is
  preserved at `/tmp/core_eval_before_explicit_summary.zig`.
- Prototype results: twelve associated/field/missing-evidence cases at depths 0,
  16, 64 and 128 preserve outcomes and ordered diagnostics. At depth 128, the
  associated case's largest region drops from 260 to 2 scopes and the field
  case's from 130 to 1. The existing five call-summary execution tests pass,
  including deep chains, callbacks/effects, diagnostic fallback, dependencies,
  checkpoints and failed-edit recovery. Eleven qualified-row, explicit-evidence
  and named-contract execution laws also pass, including separate compilation
  and retained recovery. Results are in
  `build/bench/call-summary-graph-prototype/` and
  `build/bench/call-summary-explicit-baseline/graph-call-summary-tests.log`.
- Cost requiring investigation: in the associated case, total regions rise from
  135 to 393 and solver passes from 535 to 2,083. Smaller regions alone do not
  establish a faster or lower-allocation compiler. No performance or completion
  claim is made for this probe.
- Release qualification: sixteen existing execution laws, eighteen ordered
  diagnostic-boundary cases and twelve synthetic cases across seven alternating
  pairs passed. At depth 128, associated-chain CPU rose from 10.242 to 11.716 ms
  and requested allocation from 5,406,388 to 8,803,028 bytes; field-chain CPU
  rose from 9.171 to 9.775 ms and allocation from 5,135,019 to 8,555,007 bytes.
  Gdev counters and Wasm were unchanged. The admission expansion was rejected
  for landing; complete commands, pins and comparisons are recorded in the
  [durable experiment record](../zig-native/CALL_SUMMARIES.md#predicate-admission-experiment-9-october-2026)
  and `build/bench/call-summary-graph-release/`.
- Remaining implementation and validation: complete principal/residual graph
  coverage, unsupported explicit and result-directed cases, authoritative
  witness diagnostics, bounded graph admission, ownership/allocation failures,
  repeated diamonds, separate compilation and paired CPU/allocation evidence. A
  wider admission rule alone does not complete this task.
- Follow-on written-scheme candidate: import the checked explicit residual
  predicates with fresh scope variables, preserving source argument witnesses
  and delaying closed proof publication until obligations are solved. The
  source-interface associated chain at depth 128 drops from 260 to 4 scopes and
  the field chain from 130 to 2, without multiplying successful jobs. The
  isolated candidate passes 305 corpus comparisons (610 invocations), all with
  identical diagnostics and Wasm, eighteen diagnostic-boundary comparisons,
  seventeen execution laws, and a native immutable-input/allocation-failure law.
  The execution laws include independently instantiated U32/F32 witnesses,
  imports, dependency bundles, checkpoints, edits, failure and recovery. Release
  SHA-256: `d46f5bda8ea02630366467ac8028d34b304361bab1c033c0269589db8d021775`.
  Its full native suite and all 596 guest/client tests pass, with zero findings
  across 287 Zig files. Seven synthetic pairs reduce depth-128 associated
  allocation from 5,406,379 to 4,740,399 bytes and field allocation from
  5,135,010 to 4,619,098 bytes. A 98-request retained probe passes failed-edit,
  repeated failure, recovery, body-edit, restore and no-op comparisons. The
  combined production-tree gate passes the native suite and all 596 guest/client
  tests, with zero findings across 287 Zig files. Seven final compiler pairs
  preserve Wasm equality and measure 942/953 ms cold CPU, 250/250 ms first edit
  and 220/220 ms subsequent edit; they establish no gdev speedup. Restart
  comparisons also pass. Implicit requirements and general principal graphs
  still require implementation.
- Durable specification, bounded milestone and rejected experiment
  qualification: [CALL_SUMMARIES.md](../zig-native/CALL_SUMMARIES.md).
- The next admission milestone keeps the existing supported obligations and
  classifies each reachable callee once, with bounded nodes/edges and atomic
  publication. Its isolated release passes the allocation-failure/visit-bound
  law, seventeen execution laws and all 305 corpus comparisons. At depth 128,
  associated allocation falls from 7,292,829 to 6,755,861 bytes and field
  allocation from 7,272,429 to 6,744,317 bytes. Gdev CPU results are mixed; no
  general speedup is claimed. This classifies admission efficiently but does not
  implement the remaining principal/residual graph requirements. The
  production-tree full gate passes the native suite and all 598 guest/client
  tests, with zero analyzer findings across 288 Zig files.
