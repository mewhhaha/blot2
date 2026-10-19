# 074 — Implement disjoint access and host execution

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified on 19 October 2026 against the fixed
  acceptance scope; see the current completion record below.
- **Dependencies:** [073](073-implement-scoped-tasks-and-cancellation.md),
  [071](071-eliminate-checks-from-proved-branch-facts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 10 / disjoint
  access and host integration. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Enforce disjoint-access proofs and deliver the specified host task execution
integration.

## Starting point

Task 073 supplies task lifecycle and task 071 bounded proof facts.
[compiler/guest.ts](../compiler/guest.ts),
[compiler/guest-abi.md](../compiler/guest-abi.md) and checked capability
contracts define host-facing boundaries.

## Implementation checklist

- [x] Check ownership/disjoint-access evidence before concurrent access,
      retaining conservative rejection for overlapping or unknown aliases.
- [x] Integrate host scheduling, completion, failures and cancellation using the
      agreed ABI and lifetime rules.
- [x] Preserve capability scope, task joining and only the nondeterminism
      explicitly permitted by task 072.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Accept disjoint regions and reject overlapping/forged ranges, hidden aliases
  and borrowed/capability escapes.
- Exercise host task failures, suspension, cancellation races and repeated
  starts/joins.
- Compare result/cleanup invariants across schedules and verify bounded memory
  and artifact compatibility.

## Acceptance criteria

- [x] Concurrent accesses require sound disjointness or allowed sharing and
      invalid escapes are rejected.
- [x] Host execution handles failures/cancellation within the specified
      nondeterminism and ownership contract.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Closed acceptance — owner decision, 15 October 2026

The owner closed this task's scope to the acceptance traces of the
[structured concurrency design](../zig-native/STRUCTURED_CONCURRENCY.md) listed
below.

| Acceptance trace                                           | Expected result                          |
| ---------------------------------------------------------- | ---------------------------------------- |
| Move unique capture to child, then parent uses old binding | Reject use after move.                   |
| Two sibling writes through aliases/overlapping views       | Reject before scheduling.                |
| Two siblings force one pending demand                      | Reject; independent cells remain legal.  |
| Child returns scoped callback/package/task handle          | Reject escaped group/capability/loan.    |
| Host completes a stale generation                          | Reject without touching a recycled task. |

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
- Acceptance: All five fixed access/host traces pass, including dedicated child
  callback/package-result rejection and recovery laws; task 035 is complete.
- Remaining limits: Unknown or overlapping partition evidence and shared pending
  demand forcing reject. Detached workers and simultaneous Wasm reentry remain
  outside the closed scope.

### Earlier implementation evidence

The checkpoints below retain their original dates and measurements. Statements
that qualification or a commit was pending refer to those earlier checkpoints.

- Commit: pending; record the local milestone revision when the task closes.
- Validation: the full gate at `05401a9` (17 October 2026) passes 2,355 native
  laws with zero leaks, 1,501 guest tests and zero analyzer findings over 486
  files, including every law in the
  [trace-to-law index](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#trace-to-law-index-17-october-2026).
  Four traces are fully mapped. For "child returns scoped callback/package/task
  handle", group, task-handle, view and loan escapes have task-specific laws; a
  child returning a scoped callback or a package relies on the ordinary
  capability and package escape laws.
- Comparison: pending; the fixed traces set no performance target. Record the
  comparison, or why it does not apply, when the task closes.
- Remaining limitations: task [035](035-remove-the-tracing-runtime.md) must
  complete before closure. The 19 October working tree supplies a task-specific
  callback/package result law and guest rejection/recovery checks; their final
  LLVM qualification is pending. See the
  [scoped result trace](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#scoped-result-trace-19-october-2026-working-tree).
  Forms outside the traces (detached tasks, shared mutable state across tasks,
  host worker transport, simultaneous Wasm reentry, unknown or overlapping
  partition evidence) reject, as recorded in the
  [implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#deliberate-limits-and-remaining-qualification).
- Durable record:
  [trace-to-law index](../zig-native/STRUCTURED_TASK_QUALIFICATION.md#trace-to-law-index-17-october-2026),
  [implementation record](../zig-native/STRUCTURED_TASK_QUALIFICATION.md) and
  the [structured concurrency design](../zig-native/STRUCTURED_CONCURRENCY.md).
