# 064 — Check higher rank types and skolems

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
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

- [ ] Represent rank annotations and skolem scopes distinctly from ordinary
      inference variables.
- [ ] Check annotated polymorphic arguments/results and transport required
      evidence without generalizing local skolems.
- [ ] Bound recursive checking and preserve effect/capability/usage constraints
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

- [ ] Annotated higher-rank programs obey the specified checking rules.
- [ ] Skolems never escape their scope and excessive/unsupported inference fails
      predictably with bounded work.
- [ ] Applicable checks pass and completion evidence records remaining
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
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: the managed Array U32 extension passes four focused native laws,
  source/archive/checkpoint/restart execution in both tiers and eight carrier/
  package neighbors. Forged same-layout witnesses, effects and bodies reject.
  Exact pins and logs: `build/bench/finish-program-20261014/array-rank/`. The
  final full compiler gate remains required.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record:
  [implementation and remaining qualification](../zig-native/POLYMORPHIC_PACKAGE_IMPLEMENTATION.md).
