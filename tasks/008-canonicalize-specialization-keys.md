# 008 — Canonicalize specialization keys

## Status, dependencies, and originating requirements

- **Status:** Complete — session-owned complete canonical proofs rebuild outputs
  against current captures; public fresh/retained/restart qualification passes.
- **Dependencies:** [007](007-infer-recursive-components-jointly.md)
- **Originating requirements:** PLAN: Hill 4 / canonical specialization keys.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Key semantic specialization by body identity and complete evidence, eliminating
duplicate regions only when the full proof permits sharing.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#lexical-captures-and-canonical-inputs)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

`specialized_closures` and frozen capture proofs in
[core_eval.zig](../zig-native/src/core_eval.zig) still retain value-specific
keys. [specialization.zig](../zig-native/src/specialization.zig),
[specialization_receipt.zig](../zig-native/src/specialization_receipt.zig) and
[completed_specialization_query.zig](../zig-native/src/completed_specialization_query.zig)
provide the current selected-evidence boundaries.

## Implementation checklist

- [x] Define canonical keys for the body, type/effect evidence, captures and
      every value-dependent input identified by summary analysis.
- [x] Preserve generative/nominal/provider identities, alias graphs, settings
      and principal-versus-selected modes; use exact equality after hash lookup.
- [x] Unify only proved equivalent requests, preserve region-local variables,
      and keep unknown value dependencies conservative.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Check duplicate equivalent requests and non-equivalent captures, effects,
  staged values and nominal identities, including forced hash collisions.
- Exercise fresh/retained specialization, dependency/checkpoint translation,
  failed publication and OOM recovery.
- Inspect `--profile` and deterministic counters for repeated gdev bodies and
  synthetic diamonds.

## Acceptance criteria

- [x] No duplicate inference regions remain for the same complete canonical
      body/evidence key.
- [x] Any input capable of changing semantics distinguishes keys or declines
      sharing; evidence proves this across retained and portable paths.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: qualified local milestone; revision is recorded after the compiler
  commit.
- Validation: Zig 0.17.0; full LLVM native suite and 617 guest/client tests
  pass; 79 focused native laws pass; 295 Zig files have zero analyzer findings.
  Strict comparison covers 617 cases / 1,234 invocations with identical
  diagnostics and Wasm; all teardown records have zero live requested bytes.
  Initial output executes in 52 guests / 3,148 calls and edited output in 84
  guests / 10,212 calls, matching retained hashes.
- Comparison: immutable task-007 baseline and `candidate-canonical/` hashes, 77
  fresh workloads / 15 alternating pairs and 73 retained/restart workloads /
  seven pairs are recorded in the durable qualification. Scalar/Box width-128
  regions fall 269→141 / 267→139, with 127 hits each; median CPU falls
  3,176→2,814 / 4,408→3,825 µs. Overall median CPU ratio is 0.987.
- Remaining limitations: incomplete interfaces and unsupported mutable
  demand/provider inputs decline sharing; nested-callback controls can add
  allocation overhead. Retained CPU quantization prevents edit speedup claims.
  Private gdev remains unavailable; task 011 owns allocation follow-up and task
  084 retains the application allocation/performance targets.
- Durable record:
  [session-local canonical specialization](../zig-native/CALL_SUMMARIES.md#session-local-canonical-specialization-10-october-2026).
