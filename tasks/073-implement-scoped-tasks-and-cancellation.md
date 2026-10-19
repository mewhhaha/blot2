# 073 — Implement scoped tasks and cancellation

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
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

- [x] Implement task scopes, spawn/join and result/failure ownership, joining
      children before their scope disappears.
- [x] Apply specified cancellation and resource cleanup across nested scopes and
      suspended effects.
- [x] Enforce the task design's demand forcing rules and prevent orphaned task
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

- [x] Tasks obey scoped lifecycle/join rules and cancel with complete ownership
      cleanup.
- [x] Suspended effects, demands and nested failures satisfy the documented
      concurrency contract.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the acceptance traces of the
[structured concurrency design](../zig-native/STRUCTURED_CONCURRENCY.md) listed
below.

| Acceptance trace                                       | Expected result                                                         |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| Nested group exits normally with two unjoined children | Join children before closing group and releasing parent resource.       |
| Sibling 1 fails while sibling 2 is suspended           | Request cancellation, await settlement, drop both, then report failure. |
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
[035](035-remove-the-tracing-runtime.md) is complete. The
[trace-to-law index](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#trace-to-law-index-17-october-2026)
built from the gate at `05401a9` is recorded in the implementation record.

## Completion evidence

- Current local milestone: the commit containing this record; compiler and exact
  source/log hashes are recorded by the
  [cloud qualification](../zig-native/CLOUD_QUALIFICATION.md).
- Validation: the forced LLVM gate executes all 2,470 native laws without skips,
  failures, leaks or logged errors; 1,556 guest/client checks and 37 harness
  checks pass. CI lint covers 507 source files plus the fixture module with zero
  findings. Strict fresh/retained/restart/shared Wasm parity and the seven-pair
  CPU regression guard pass.
- Acceptance: All three scoped lifecycle/cancellation traces pass in the
  complete gate, and task 035 is complete.
- Remaining limits: Execution remains cooperative; detached tasks, shared
  mutable task state, host worker transport and simultaneous Wasm reentry are
  outside the fixed traces.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending; record the local milestone revision when the task closes.
- Validation: the full gate at `05401a9` (17 October 2026) passes 2,355 native
  laws with zero leaks, 1,501 guest tests and zero analyzer findings over 486
  files, including every law in the
  [trace-to-law index](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#trace-to-law-index-17-october-2026).
  All three traces are fully mapped.
- Comparison: pending; the fixed traces set no performance target. Record the
  comparison, or why it does not apply, when the task closes.
- Remaining limitations: task [035](035-remove-the-tracing-runtime.md) must
  complete before closure. Forms outside the traces (detached tasks, shared
  mutable state across tasks, host worker transport, simultaneous Wasm reentry,
  unknown or overlapping partition evidence) reject, as recorded in the
  [implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#deliberate-limits-and-remaining-qualification).
- Durable record:
  [trace-to-law index](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#trace-to-law-index-17-october-2026),
  [implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md) and
  the [structured concurrency design](../zig-native/STRUCTURED_CONCURRENCY.md).
