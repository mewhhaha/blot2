# 056 — Implement declarations and evidence diagnostics

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [055](055-implement-associated-type-members.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 3 / implementation
  declarations and evidence. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement declaration checking and selection, with explanations for missing,
incompatible and ambiguous evidence.

## Starting point

Task 055 adds associated members and task 048 bounded explanations.
[associated_catalog_tests.zig](../zig-native/src/associated_catalog_tests.zig),
[check.zig](../zig-native/src/check.zig) and client diagnostic schemas are the
selection/publication boundaries.

## Implementation checklist

- [ ] Check implementation declarations and apply the exact coherence/visibility
      rules from task 054.
- [ ] Select evidence with associated substitutions, retain all dependencies and
      preserve current dispatch compatibility.
- [ ] Explain rejection/ambiguity consistently for source and compiled
      dependency declarations.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test unique matches, generic implementations, associated outputs and
  imported/re-exported contracts.
- Reject overlapping or incompatible declarations and diagnose missing evidence
  with candidate origins.
- Change a selected implementation through retained edits and artifact reload;
  verify correct invalidation and OOM cleanup.

## Acceptance criteria

- [ ] Declaration checking and selection obey the documented coherence rules.
- [ ] Missing/incompatible/ambiguous evidence has bounded native/client
      explanations across dependency boundaries.
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
