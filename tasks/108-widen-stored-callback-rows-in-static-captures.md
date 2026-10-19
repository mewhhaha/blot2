# 108 — Widen stored callback rows in static captures

## Status, dependencies, and originating requirements

- **Status:** Complete — the fix and committed law pass the qualified source
  gate; owner-approved recreated full-Ink probes pass both tiers and retained
  replay, with verified pre-fix failure controls on 19 October 2026.
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

- [x] The owner-approved recreated Ink probes and the new law build and run; nominal
      argument invariance laws in `zig-native/src/check/types_tests.zig` still
      pass.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Replacement decision, 19 October 2026: the original local `v0`, `v1` and
  `v3` files did not survive and are absent from the available history. The
  owner authorized recreated probes using the checked-out Ink ECS library:
  `one_resource`, `two_resources` and `snapshot_resource`. These are replacement
  acceptance inputs, not recovered originals. Qualification must record their
  exact source/library/compiler pins, both code generation tiers, retained edit
  and revert parity, execution and ownership witnesses, and a pre-fix
  `effect_mismatch` control. The qualification below supplies that evidence.
- Implementation commit: `f6a2942`; qualified production source: `e29dd0d`.
- Prior report: Ink's `v0`, `v1`, `v3`, `v2` and `u1` built with the patched
  development compiler. Their missing original source files prevent using that
  report as reproducible acceptance evidence. The committed trimmed law and
  nominal invariance laws pass the forced 2,470-law native gate and 1,556
  guest/client checks on qualified source `e29dd0d`.
- Current acceptance: the portable `scripts/qualify_static_capture_rows.ts`
  passes three full-Ink inputs at Ink `1a291a1b`, two code generation tiers,
  retained edits/reverts, fresh byte equality and 1,854 executed result checks.
  All recorded input pins verify. Parent `05401a9`, built in development mode
  with its own standard library, reports `effect_mismatch` for `one_resource`
  and `two_resources`; `snapshot_resource` is a positive control. Harness
  formatting, type checking and lint pass. This qualifies the callback fix in
  the prior production source; uncommitted task-053 changes remain unqualified.
- Comparison: not applicable; evaluator typing only.
- Remaining limitations: the original files were lost; the owner approved the
  replacement inputs. Scalar guest memory visibility does not measure private
  heap usage, and this typing qualification makes no heap claim.
- Durable record: [stored callback captures](../zig-native/STATIC_CAPTURE_ROWS.md),
  the comment at the fix site and the committed regression law.
