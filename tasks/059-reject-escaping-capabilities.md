# 059 — Reject escaping capabilities

## Status, dependencies, and originating requirements

- **Status:** In progress — scope closed to fixed language-qualification rows by
  owner decision on 15 October 2026; waiting for a passing full gate on current
  source.
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

- [ ] Track capability scope through closures, demands, aggregates, generic
      calls and module interfaces.
- [ ] Reject results or captures that expose a shorter-lived capability beyond
      its permitted scope, including hidden higher-order paths.
- [ ] Preserve legal local callbacks, nested handlers and separately compiled
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

- [ ] Every specified invalid escape is rejected even through abstraction and
      polymorphism.
- [ ] Valid scoped uses remain executable with unchanged routing and effect
      behavior.
- [ ] Applicable checks pass and completion evidence records remaining
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
freeze `3548546c…`, but the current working tree failed 20 native laws on the
evening of 15 October, so completion waits for a passing gate on current source.
The original acceptance index
(`build/bench/finish-rest-20261015/language-acceptance/qualified-baseline.json`)
was removed with `build/`; regenerate the row-to-law mapping from the passing
gate's native test names and guest JUnit report and record it durably in
[LANGUAGE_QUALIFICATION.md](../zig-native/LANGUAGE_QUALIFICATION.md).

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
