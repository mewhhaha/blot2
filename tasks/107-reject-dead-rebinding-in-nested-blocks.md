# 107 — Reject dead rebinding in nested blocks

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 17 October
  2026 as [issue #11](https://github.com/mewhhaha/blot2/issues/11), a silent
  miscompile.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A `:=` in a statement `case` arm carries out of the case like an `if` branch
(owner-approved language change, 17 October 2026), and a `:=` that still cannot
change anything — in any other nested `do:` — is rejected instead of silently
compiled.

## Starting point

A statement `case` is an ordinary expression statement, and each `do:` arm is a
nested block that keeps its own scope, as [the guide](../compiler/guide.md)
states. `count := 7` in an arm therefore made a successor visible only inside
that arm, and the enclosing local kept its old value with no diagnostic. A plain
statement-level nested `do:` behaved the same. The constant evaluator and Wasm
emission agree, so the fault is checker scoping
(`zig-native/src/check/check.zig` `blockExpression` and `rebindStatement`).
Already wrong on `86a527b`.

## Implementation checklist

- [x] Record whether a binding is read (`Binding.read`, set in `instantiate`).
- [x] At the exit of a nested `do:` (not a lambda's own body), report
      `dead_rebinding` for each last version of an enclosing name rebound in the
      block that is never read.
- [x] Count a read of any version made in the block, including versions in
      branches, so Ink's `lib/ui/tree.blot` focus blur is not rejected.
- [x] Carry statement-`case` arm rebinding outward as chained binary merges
      (nested two-arm statement matches, like `if let`); rebinding arms inline
      their `do:` suite (`Checked.statement_arms`, cached and replayed); a
      `return` nested in an `if` or loop of a rebinding arm is rejected with
      `case_arm_return`; loops carry names rebound in statement-case arms
      (`zig-native/src/backend/loop_targets.zig`, which dropped them before).
- [x] Document the rules in the guide's rebinding and loop paragraphs and the
      merge shape in `zig-native/CONTRACT.md`.
- [x] Add executed-Wasm laws in
      `zig-native/tests/nested_block_rebinding_execution.test.ts`, and a
      cross-module generic receiver dispatch law in
      `zig-native/tests/receiver_dispatch_module_execution.test.ts` (the second
      Ink finding, already fixed since `86a527b`).

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` before the local milestone
commit.

## Acceptance criteria

- [x] The issue repro returns 7 and 3; one-arm, single-arm, three-arm, field,
      guarded, type-changing, looped and owned-array arms execute correctly with
      stable guest memory; a plain statement `do:` with an unread `:=` is
      rejected with `dead_rebinding`; a nested `return` in a rebinding arm is
      rejected with `case_arm_return`.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Current local milestone: `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`; compiler
  and exact source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: All nested-block rebinding and rejection laws pass the current
  native/OOM and executed guest gate.
- Remaining limits: Plain nested do blocks keep their scope; nested returns in
  rebinding statement-case arms reject with case_arm_return as documented.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending.
- Validation: in the implementation worktree the full gate passed with 2,360
  native laws (zero leaks), 1,506 guest, 48 smoke and 28 harness tests, and lint
  reported zero findings. Ink's ECS probes, its 66 test modules and the
  repository examples raise no `dead_rebinding`. New Zig laws:
  `zig-native/src/check/core_case_statement_tests.zig`, plus evaluator,
  body-cache replay and loop-target laws.
- Comparison: not applicable; checker diagnostic only.
- Remaining limitations: a plain nested `do:` and arms of a `case` whose value
  is used keep their own scope; a `return` nested in an `if` or loop of a
  rebinding statement-case arm is rejected rather than supported. Existing
  statement-case arms that rebind an outer local now carry it out, which can
  surface `type_mismatch` when arms disagree.
- Durable record: [compiler/guide.md](../compiler/guide.md) rebinding paragraph.
