# 004 — Summarize predicate bearing callees

## Status, dependencies, and originating requirements

- **Status:** Complete — bounded first-order principal/residual graphs and
  source-normalized admission are qualified at `3a8b6ee`.
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
covers checked written predicates, owned inferred first-order graphs and
source-only normalized graphs alongside the original predicate-free path.
`collectCall`, the summary queue and `validated_calls` implement the boundaries
specified in task 003. Higher-order/capture/component extensions follow in tasks
005–007.

## Implementation checklist

- [x] Instantiate residual predicates with fresh region-local variables and
      preserve argument/result-directed obligations and effect rows.
- [x] Schedule dependency summaries iteratively and publish only complete
      judgments. Preserve deferred checking, reachability and independently
      successful proofs.
- [x] Keep ordinary collection as the authoritative failure path; do not infer
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

- [x] Repeated predicate-bearing uses share the checked result under complete
      inputs, with bounded graph work.
- [x] Fallback diagnostic order, execution, recovery and ownership match
      ordinary checking; deterministic counters show the intended reduction.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Compiler milestone: `3a8b6ee` completes bounded first-order principal/residual
  graphs, exact live header scheduling and source-only normalization. Earlier
  milestones `fd8cd3f`, `90bd532`, `f7be6e7`, `099e700` and `ef8f4b9` remain
  qualified foundations; rejected admission/result experiments remain separate.
- Validation: Zig 0.17.0; the full native suite and all 607 guest/client tests
  pass, and the analyzer reports zero findings across 291 files. All 509 public
  differential cases (1,018 invocations, 350 successes) preserve ordered
  diagnostics and successful Wasm. Every available memory record returns to zero
  live bytes. Source-selected edges revealed after normalization, mandatory
  header failures, active handlers, independent instantiations, depth-64
  diamonds, immutable input, rollback and allocation failure have native laws.
  Imports, bundles, checkpoints, retained edits and recovery have executed laws.
- Comparison: fifteen alternating pairs over 23 cache-disabled workloads and
  seven official fresh/retained/restart pairs for synthetic and factory sources
  preserve Wasm equality. The representation diamond at depth 12 drops from
  60.262 to 6.868 ms CPU, 43,473,545 to 4,847,090 requested bytes and 102,396 to
  163 constraint visits. Structured type heads drop from 4,353.041 to 6.676 ms
  CPU. Small operation wrappers instead add about 20% CPU/21% allocation, and
  factory restart adds about 15% allocation. No general compiler speedup is
  claimed. Binary, identity and source patch hashes, all distributions and exact
  commands are in the durable record.
- Remaining limitations: higher-order callbacks, lexical captures, joint
  recursive components and canonical cross-session keys are tasks 005–008.
  Optional cyclic source publication declines atomically; the discovered direct
  source frontend retry still needs task 007. Missing historical boxed/private
  gdev artifacts keep final historical and program-wide qualification open.
- Durable specification, implementation boundaries, earlier experiments and
  final qualification:
  [CALL_SUMMARIES.md](../zig-native/CALL_SUMMARIES.md#live-headers-and-source-normalized-graphs-10-october-2026).
