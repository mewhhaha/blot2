# 094 — Locate specialization failures at their use

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** [048](048-explain-dispatch-and-evidence.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 1 / explainable
  inference; found while completing task 048. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md),
  [dispatch explanations](../zig-native/DISPATCH_EXPLANATIONS.md#remaining-scope).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

A dispatch or obligation that fails while a callee is specialized for a caller's
types is reported at the caller's source use, with the callee's location kept as
secondary context.

## Starting point

`#Box 1 + #Box 2` in a program without `Box.add` reports `missing_associated` at
`std/prelude.blot` 603–630, the `@type.call` inside `add`, because the checker
leaves the concrete dispatch to specialization and
[core_eval.zig](../zig-native/src/core_eval.zig) fails while validating the
specialized `add` body. Task 048's explanation names the operand types, but the
location is still the prelude. `anchorRecursion` already moves recursion
diagnostics to a call site.

## Implementation checklist

- [ ] Carry the outermost entry-project use through specialization and report
      obligation and dispatch failures there, keeping the callee's span as
      secondary context in the published diagnostic.
- [ ] Keep diagnostic ordering, codes and explanations unchanged, and keep
      failures that belong to the callee itself located in the callee.
- [ ] Extend the client schema for the secondary location with defensive
      decoding.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Operators over user, imported and compiled-dependency types without a member;
  generic callbacks; nested generic callees; failures inside a library's own
  body that must stay there.
- Fresh and retained builds, CLI and project server.

## Acceptance criteria

- [ ] A specialization failure caused by a caller's types points at the caller's
      expression in the user's file, with the callee location available.
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
