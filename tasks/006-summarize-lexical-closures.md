# 006 — Summarize lexical closures

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Implement typed capture inputs from task 003, including binding versions,
      alias relationships, nominal/provider identities and latent effects.
- [ ] Admit shared summaries only when complete capture evidence is known;
      preserve conservative behavior for staged, dynamic or unresolved captures.
- [ ] Keep caller-selected facts out of principal schemes and ensure every
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

- [ ] Every admitted lexical summary names and validates all captured inputs,
      including alias-sensitive evidence.
- [ ] Different capture semantics never collide; failed or unsupported capture
      proofs publish nothing and recovery matches fresh compilation.
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
