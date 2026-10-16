# 074 — Implement disjoint access and host execution

## Status, dependencies, and originating requirements

- **Status:** In progress — focused implementation checks pass (see
  [STRUCTURED_TASK_QUALIFICATION](../zig-native/STRUCTURED_TASK_QUALIFICATION.md));
  scope closed to fixed acceptance traces by owner decision on 15 October 2026;
  task 035 and a passing full gate remain.
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

- [ ] Check ownership/disjoint-access evidence before concurrent access,
      retaining conservative rejection for overlapping or unknown aliases.
- [ ] Integrate host scheduling, completion, failures and cancellation using the
      agreed ABI and lifetime rules.
- [ ] Preserve capability scope, task joining and only the nondeterminism
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

- [ ] Concurrent accesses require sound disjointness or allowed sharing and
      invalid escapes are rejected.
- [ ] Host execution handles failures/cancellation within the specified
      nondeterminism and ownership contract.
- [ ] Applicable checks pass and completion evidence records remaining
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
