# 064 — Check higher rank types and skolems

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the two higher-rank
  rows of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
- **Dependencies:** [063](063-specify-polymorphic-packages.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / annotated
  higher-rank checking. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement annotated higher-rank checking and precise skolem-escape rejection
with bounded work.

## Starting point

[types.zig](../zig-native/src/check/types.zig),
[check.zig](../zig-native/src/check/check.zig) and
[type_evidence.zig](../zig-native/src/eval/type_evidence.zig) implement current
scheme instantiation. Task 063 defines higher-rank introduction/elimination and
scope rules.

## Implementation checklist

- [x] Represent rank annotations and skolem scopes distinctly from ordinary
      inference variables.
- [x] Check annotated polymorphic arguments/results and transport required
      evidence without generalizing local skolems.
- [x] Bound recursive checking and preserve effect/capability/usage constraints
      in higher-order calls.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Accept rank-2 callbacks used at multiple concrete types and annotated imported
  higher-rank functions.
- Reject unannotated unsupported inference, escaped skolems, incompatible
  evidence and leaked scoped capabilities.
- Exercise diagnostic origins, dependency interfaces, failed edits and OOM
  cleanup.

## Acceptance criteria

- [x] Annotated higher-rank programs obey the specified checking rules.
- [x] Skolems never escape their scope and excessive/unsupported inference fails
      predictably with bounded work.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract    | Qualified requirements                                            |
| ----------- | ----------------------------------------------------------------- |
| Higher rank | Structural rank, annotated recursion, skolems, bounded rejection  |
| Higher rank | Row/region binders, predicates, associated evidence, dictionaries |

Intentional rejections under the normative design: unannotated higher-rank
inference.

The task completes when every native law and guest test mapped to these rows
passes in the full compiler gate (`deno task test:compiler` and
`deno task lint:zig`) on the committed source. The rows passed in the 15 October
freeze `3548546c…`. The 20 native-law failures seen on the evening of 15 October
were fixed in `23a934f`, and the gate at `05401a9` passed on 17 October. The
original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`. The row-to-law mapping regenerated from that gate's
native test names and guest JUnit report is recorded in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026).

## Completion evidence

- Revision: committed source at `05401a9` (17 October 2026), the tree the gate
  ran on; `23a934f` also passed the full gate. The closure itself is
  documentation only.
- Validation (Zig 0.17.0): the full gate at `05401a9` passes 2,355 native laws
  in two shards with zero failures and zero leaks, 1,501 guest tests with zero
  failures, and the harness and smoke phases; `deno task lint:zig` reports zero
  zig-analyzer findings over 486 files. The run's final native-input check
  refused only because another session edited `../gdev` during the run; every
  phase passed. The earlier gate at `23a934f` passed 2,354 native laws with zero
  leaks, 1,486 guest, 28 harness, 21 preflight and 48 smoke tests and zero
  analyzer findings.
- Row-to-law mapping: the
  [index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026)
  names 23 native laws and 13 guest tests for the nine requirements of the two
  higher-rank rows; all passed in the `05401a9` gate.
- Comparison: performance measurement does not apply; the closed rows set no
  performance target and no speedup is claimed. Focused development observations
  remain in the durable record.
- Remaining limitations: unannotated higher-rank inference remains an
  intentional rejection under the normative design. Forms outside the rows are
  excluded scope under the owner decision of 15 October 2026 (closed acceptance
  above; [README owner decisions](README.md#task-index)), not open work. Such
  forms reject conservatively, for example stored helper forwarding through an
  unknown `forall` and helpers whose witness no active goal determines. Physical
  layouts never supply missing evidence, and dictionary-key artifact import
  declines reuse instead of transporting unsupported evidence.
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  [implementation record](../zig-native/POLYMORPHIC_PACKAGE_IMPLEMENTATION.md)
  and the [polymorphic package design](../zig-native/POLYMORPHIC_PACKAGES.md).
