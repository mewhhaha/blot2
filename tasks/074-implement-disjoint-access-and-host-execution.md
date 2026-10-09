# 074 — Implement disjoint access and host execution

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

## Completion evidence

- Commit: pending; record the local milestone revision.
- Validation: not run for this task; record commands, versions, results and
  evidence links.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: not yet assessed; list unresolved scope explicitly.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
