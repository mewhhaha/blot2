# 073 — Implement scoped tasks and cancellation

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [072](072-specify-structured-concurrency.md),
  [035](035-remove-the-tracing-runtime.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 10 / task
  lifecycle. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement the specified structured task lifecycle and cancellation with
qualified runtime ownership.

## Starting point

Task 035 completes the tracing replacement and task 072 defines task semantics.
[runtime_cleanup.zig](../zig-native/src/runtime_cleanup.zig),
[request_runtime.zig](../zig-native/src/request_runtime.zig) and
[compiler/guest.ts](../compiler/guest.ts) handle current lifetimes and host
suspension.

## Implementation checklist

- [ ] Implement task scopes, spawn/join and result/failure ownership, joining
      children before their scope disappears.
- [ ] Apply specified cancellation and resource cleanup across nested scopes and
      suspended effects.
- [ ] Enforce the task design's demand forcing rules and prevent orphaned task
      roots or escaped capabilities.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run nested tasks, sibling failures, early scope exits, explicit cancellation
  and cancellation while suspended.
- Check deterministic cleanup obligations, join completion, host exceptions and
  demand state after interruption.
- Stress repeated task creation/failure for bounded memory and compare permitted
  execution modes.

## Acceptance criteria

- [ ] Tasks obey scoped lifecycle/join rules and cancel with complete ownership
      cleanup.
- [ ] Suspended effects, demands and nested failures satisfy the documented
      concurrency contract.
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
