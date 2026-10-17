# 059 — Reject escaping capabilities

## Status, dependencies, and originating requirements

- **Status:** Complete — closed on 17 October 2026 against the two
  capability-lifetime rows of
  [language qualification](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  gate at `05401a9`.
- **Dependencies:** [058](058-implement-effect-instances-and-subtraction.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 4 / capability
  escape. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Reject invalid scoped-capability escapes while preserving valid uses inside
their lifetime.

## Starting point

Task 058 gives capabilities stable scoped identities.
[check.zig](../zig-native/src/check/check.zig),
[specialization.zig](../zig-native/src/eval/specialization.zig) and captured
evidence now need the escape rules from task 057.

## Implementation checklist

- [x] Track capability scope through closures, demands, aggregates, generic
      calls and module interfaces.
- [x] Reject results or captures that expose a shorter-lived capability beyond
      its permitted scope, including hidden higher-order paths.
- [x] Preserve legal local callbacks, nested handlers and separately compiled
      generic functions with sufficient contracts.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test local use and nonescaping callbacks as positive cases; return/store
  scoped closures, demands and nested aggregates as negative cases.
- Attempt escape through polymorphic identity, opaque modules, associated
  evidence and compiled dependencies.
- Check precise origins, bounded analysis, retained edits and allocation-failure
  recovery.

## Acceptance criteria

- [x] Every specified invalid escape is rejected even through abstraction and
      polymorphism.
- [x] Valid scoped uses remain executable with unchanged routing and effect
      behavior.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the rows of
[language qualification](../zig-native/LANGUAGE_QUALIFICATION.md) listed below.
Forms outside these rows ("general" captures, stores, transports and shapes) are
not required work: they must reject or decline conservatively with a stable
diagnostic and are recorded as limitations. The acceptance criteria below are
read against these rows.

| Contract             | Qualified requirements                       |
| -------------------- | -------------------------------------------- |
| Capability lifetimes | Closures, demands, aggregates, projections   |
| Capability lifetimes | Sinks, opaque contracts, bounded diagnostics |

Intentional rejections under the normative design: unproved storage lifetimes.

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
  names 26 native laws and 9 guest tests for the seven requirements of the two
  capability-lifetime rows; all passed in the `05401a9` gate.
- Comparison: performance measurement does not apply; the closed rows are
  acceptance and rejection laws with no performance target. Escape analysis is
  bounded: structural queries stop at depth 128 and 65,536 visits, and immutable
  scope rejection spends one shared semantic work budget. The scoped-State costs
  recorded for task [058](058-implement-effect-instances-and-subtraction.md)
  include these checks.
- Remaining limitations: unproved storage lifetimes remain an intentional
  rejection under the normative design. Forms outside the rows are excluded
  scope under the owner decision of 15 October 2026 (closed acceptance above;
  [README owner decisions](README.md#task-index)), not open work. Such forms
  reject conservatively with stable diagnostics, which also rejects some
  authority-free values and legal storage or callback flows
  ([conservative limits](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md#conservative-limits);
  later sections of that record narrow the boundary).
- Durable record:
  [row-to-law index](../zig-native/LANGUAGE_QUALIFICATION.md#row-to-law-index-17-october-2026),
  [scoped effect qualification](../zig-native/SCOPED_EFFECTS_QUALIFICATION.md)
  and the
  [lifetime design](../zig-native/SCOPED_EFFECTS.md#lifetime-and-capture).
