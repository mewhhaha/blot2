# 008 — Canonicalize specialization keys

## Status, dependencies, and originating requirements

- **Status:** In progress — designing complete session-owned canonical proofs
  and reconstruction against current captures; no completion is claimed.
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

- [ ] Define canonical keys for the body, type/effect evidence, captures and
      every value-dependent input identified by summary analysis.
- [ ] Preserve generative/nominal/provider identities, alias graphs, settings
      and principal-versus-selected modes; use exact equality after hash lookup.
- [ ] Unify only proved equivalent requests, preserve region-local variables,
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

- [ ] No duplicate inference regions remain for the same complete canonical
      body/evidence key.
- [ ] Any input capable of changing semantics distinguishes keys or declines
      sharing; evidence proves this across retained and portable paths.
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
