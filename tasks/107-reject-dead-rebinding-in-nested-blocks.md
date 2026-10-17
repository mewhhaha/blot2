# 107 — Reject dead rebinding in nested blocks

## Status, dependencies, and originating requirements

- **Status:** In progress — implemented with focused checks on 17 October 2026;
  the full gate and commit remain.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink by peer session on 17 October
  2026 as [issue #11](https://github.com/mewhhaha/blot2/issues/11), a silent
  miscompile.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A `:=` that cannot change anything is rejected instead of silently compiled.

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
- [x] Document the rule in the guide's rebinding paragraph.
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

- [ ] The issue repro, a one-arm variant and a statement `do:` are rejected;
      rebinding read in its block, carried out by `if`, assigned from a `case`
      value or carried by a loop still compiles and executes correctly.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending.
- Validation: the new laws pass with the patched compiler; Ink's ECS probes, its
  66 test modules and the repository examples raise no `dead_rebinding`.
- Comparison: not applicable; checker diagnostic only.
- Remaining limitations: a rebinding that is read inside its block but expected
  to reach the enclosing suite is still accepted; the guide states that nested
  blocks keep their own scope.
- Durable record: [compiler/guide.md](../compiler/guide.md) rebinding paragraph.
