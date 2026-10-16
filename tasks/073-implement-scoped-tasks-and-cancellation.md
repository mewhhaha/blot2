# 073 — Implement scoped tasks and cancellation

## Status, dependencies, and originating requirements

- **Status:** In progress — focused implementation checks pass (see
  [STRUCTURED_TASK_QUALIFICATION](../zig-native/STRUCTURED_TASK_QUALIFICATION.md));
  scope closed to fixed acceptance traces by owner decision on 15 October 2026;
  task 035 and a passing full gate remain.
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
[runtime_cleanup.zig](../zig-native/src/runtime/runtime_cleanup.zig),
[request_runtime.zig](../zig-native/src/runtime/request_runtime.zig) and
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

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the acceptance traces of the
[structured concurrency design](../zig-native/STRUCTURED_CONCURRENCY.md) listed
below.

| Acceptance trace                                       | Expected result                                                         |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| Nested group exits normally with two unjoined children | Join children before closing group and releasing parent resource.       |
| Sibling1 fails while sibling2 is suspended             | Request cancellation, await settlement, drop both, then report failure. |
| Cancel before child starts                             | Do not invoke thunk; drop transferred owners once.                      |

Forms outside these traces (detached tasks, shared mutable state across tasks,
host worker transport, simultaneous Wasm reentry, unknown or overlapping
partition evidence) must reject, as recorded in
[the implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#deliberate-limits-and-remaining-qualification).

Focused evidence: the private implementation passed 12 checker, four backend,
one native-context, 26 task/context/resource and 35 guest/resource laws, with 34
descriptors executed in sync and JSPI modes (see
[the implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#focused-checks)).
The task completes when each trace maps to named passing laws in the full
compiler gate on the committed source and task
[035](035-remove-the-tracing-runtime.md) is complete.

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
