# 056 — Implement declarations and evidence diagnostics

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified at `10fab46`.
- **Dependencies:** [055](055-implement-associated-type-members.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 3 / implementation
  declarations and evidence. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Implement declaration checking and selection, with explanations for missing,
incompatible and ambiguous evidence.

## Starting point

Task 055 adds associated members and task 048 bounded explanations.
[associated_catalog_tests.zig](../zig-native/src/eval/associated_catalog_tests.zig),
[check.zig](../zig-native/src/check/check.zig) and client diagnostic schemas are
the selection/publication boundaries.

## Implementation checklist

- [x] Check implementation declarations and apply the exact coherence/visibility
      rules from task 054.
- [x] Select evidence with associated substitutions, retain all dependencies and
      preserve current dispatch compatibility.
- [x] Explain rejection/ambiguity consistently for source and compiled
      dependency declarations.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Test unique matches, generic implementations, associated outputs and
  imported/re-exported contracts.
- Reject overlapping or incompatible declarations and diagnose missing evidence
  with candidate origins.
- Change a selected implementation through retained edits and artifact reload;
  verify correct invalidation and OOM cleanup.

## Acceptance criteria

- [x] Declaration checking and selection obey the documented coherence rules.
- [x] Missing/incompatible/ambiguous evidence has bounded native/client
      explanations across dependency boundaries.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `10fab46` (local main; no push).
- Validation: Zig 0.17.0; full `deno task test:compiler --oom-profile`, 1,624
  native laws, 1,030 guests and 977 exhaustive allocation-failure sweeps.
  Analyzer zero across 373 files; editor/generation, Deno checks and packaging
  dry run pass.
- Comparison: 98 scaling and 98 lifecycle samples on the final LLVM/Fast binary;
  seven paired public/captured controls. The combined compiler adds 4–6% public
  CPU and about 9–12% captured CPU; task 084 retains performance qualification.
- Remaining limitations: body reuse, scoped capabilities and tracing removal
  retain their own task scopes; no task 056 semantic requirement is deferred.
- Durable record:
  [implementation qualification](../zig-native/IMPLEMENTATIONS_QUALIFICATION.md)
  and [merged inputs/costs](../zig-native/CONTINUATION_QUALIFICATION.md).
