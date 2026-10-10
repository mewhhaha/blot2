# 006 — Summarize lexical closures

## Status, dependencies, and originating requirements

- **Status:** Complete — owned complete capture environments key independent
  jobs while ordinary checking preserves incomplete and observed inputs.
- **Dependencies:** [005](005-summarize-higher-order-callees.md)
- **Originating requirements:** PLAN: Hill 2 / lexical closure summaries.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Make captured variables explicit summary inputs while preserving aliases and the
distinction between principal facts and selected evidence.

## Starting point

Use the
[approved summary interface](../zig-native/CALL_SUMMARIES.md#lexical-captures-and-canonical-inputs)
and its
[acceptance cases](../zig-native/CALL_SUMMARIES.md#acceptance-examples-for-the-implementation-sequence).

[core_eval.zig](../zig-native/src/core_eval.zig) tracks closure values and
frozen capture proofs;
[completed_specialization_query.zig](../zig-native/src/completed_specialization_query.zig)
and [source_value_template.zig](../zig-native/src/source_value_template.zig)
compare captured graphs. Selected live accessor hints deliberately cannot
certify reusable semantic results.

## Implementation checklist

- [x] Implement typed capture inputs from task 003, including binding versions,
      alias relationships, nominal/provider identities and latent effects.
- [x] Admit shared summaries only when complete capture evidence is known;
      preserve conservative behavior for staged, dynamic or unresolved captures.
- [x] Keep caller-selected facts out of principal schemes and ensure every
      published result owns its imported evidence.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test closures capturing the same type but different values, rebinding
  snapshots, shared aggregates, demands, nested closures and provider-sensitive
  callbacks.
- Run frozen-capture, static-capture-key and retained-capture tests with
  dependency/checkpoint round trips and allocation failures.
- Change only a capture or its alias graph while preserving the body and check
  that invalid sharing is rejected.

## Acceptance criteria

- [x] Every admitted lexical summary names and validates all captured inputs,
      including alias-sensitive evidence.
- [x] Different capture semantics never collide; failed or unsupported capture
      proofs publish nothing and recovery matches fresh compilation.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `71c0f2a` on local `main`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 610 guest/client tests. `deno task lint:zig` reports zero findings across
  292 files. Twelve focused native laws include all-allocation failures,
  same-session OOM retry, alias/value/provider/demand keys and bounded refusal.
  Guest laws retain dependency/checkpoint round trips and failed-edit recovery.
- Comparison: 587 public cases / 1,174 fresh invocations preserve ordered
  diagnostics; only three qualified shared-Box outputs differ by exactly 12
  static bytes per closure. Initial and edited output each pass 42 guests and
  7,056 calls. Fifteen release pairs cover 53 workloads; seven pairs cover 52
  fresh/retained/restart workloads with strict per-variant output consistency.
  All binary/identity pins remain unchanged.
- Remaining limitations: incomplete, staged, cyclic or actively observed
  environments use ordinary checking. Some demand/provider controls add CPU
  and allocation overhead. The largest recorded candidate region is 35.776 ms;
  missing profiles establish no program-wide bound. General principal lexical
  graphs, joint components and portable keys remain later work. Private gdev
  and historical task 002 evidence are unavailable.
- Durable record:
  [owned lexical inputs and qualification](../zig-native/CALL_SUMMARIES.md#owned-lexical-inputs-10-october-2026)
  preserves ownership rules, exact pins, commands, distributions and limitations.
