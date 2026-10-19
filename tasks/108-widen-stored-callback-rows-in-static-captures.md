# 108 — Widen stored callback rows in static captures

## Status, dependencies, and originating requirements

- **Status:** In progress — fix and law recorded on 17 October 2026 and
  committed in `f6a2942`; later full gates on main pass. The acceptance evidence
  (Ink repros) remains to be recorded.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 16 October
  2026 (`effect_mismatch` on `fn () => ecs.checkpoint engine` with a generic
  `engine`); owner asked for it to be finished on 17 October 2026.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A lambda that captures a static nominal value whose stored callback is pure
compiles when the checked type widened that callback's row.

## Starting point

The evaluator rebuilt a captured static value's type from its fields in
`ClosureRegion.addAggregate` (`zig-native/src/eval/core_eval.zig`, nominal arm).
A stored `fn () => ()` has an exact closed pure row, which fixed the invariant
nominal argument before the capture was unified with the checker's declared
type, whose row lists six State operations. `openCovariant` does not descend
into nominal arguments by design, so `captureShape` failed with
`effect_mismatch` at emission. A named curried function (`checkpointer engine`)
or a global engine avoided the static-capture path.

## Implementation checklist

- [x] Reopen the covariant rows of a nominal payload's field values before
      unifying them with the constructor payload, as the checker does per use.
- [x] Add `zig-native/tests/static_capture_row_execution.test.ts`, a two-module
      project with a trimmed Ink ECS library, which fails with `effect_mismatch`
      before the fix.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` before the local milestone
commit.

## Acceptance criteria

- [ ] Ink's `v0`, `v1` and `v3` repros and the new law build and run; nominal
      argument invariance laws in `zig-native/src/check/types_tests.zig` still
      pass.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending.
- Validation: Ink's `v0`, `v1`, `v3`, `v2` and `u1` build with the patched dev
  compiler; the new law passes and fails on the previous compiler.
- Comparison: not applicable; evaluator typing only.
- Remaining limitations: none known.
- Durable record: the comment at the fix site and this law.
