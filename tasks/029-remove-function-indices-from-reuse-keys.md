# 029 — Remove function indices from reuse keys

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `2798ff9`.
- **Dependencies:** [018](018-migrate-executable-reuse-queries.md),
  [028](028-make-emission-consume-resolved-bodies.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / stable
  optimized-body identities. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Use stable symbolic call/body identities for optimized-body reuse and relocate
final indices during assembly.

## Starting point

[optimized_bodies.zig](../zig-native/src/backend/optimized_bodies.zig),
[runtime_function_key.zig](../zig-native/src/backend/runtime_function_key.zig)
and
[runtime_body_relocation.zig](../zig-native/src/backend/runtime_body_relocation.zig)
currently include incidental function positions in reuse matching, despite
existing relocation proofs.

## Implementation checklist

- [x] Replace positional identities in stored keys with stable symbolic bodies
      and complete callee/signature/lifetime dependencies.
- [x] Relocate direct calls and table/global references on owned output copies
      during final assembly, validating cycles and consistent mappings.
- [x] Decline ambiguous or exhausted relocation proofs and preserve separate
      public Wasm identities.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Insert, remove and reorder unrelated functions and compare cache reuse plus
  final fresh/retained bytes.
- Test recursive call graphs, imports, changed callee lifetime facts, duplicate
  bodies and indirect table slots.
- Exercise allocation failure and failed assembly without modifying retained
  optimized bodies.

## Acceptance criteria

- [x] Incidental function-index changes no longer invalidate otherwise identical
      optimized bodies.
- [x] Final relocation remains exact and rejects changed or ambiguous semantic
      targets.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2798ff9` (joint 029/032/037 compiler and bpm milestone).
- Implementation: Normalized body/tier keys, exact bounded graph proofs and
  owned output relocation remove incidental positions from reuse identity.
  Portable v3 captures own complete reference, role and lifetime facts.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native
  suite, 844 guest/client laws and all eight unchanged allocation budgets.
  `deno task lint:zig` checks 339 files with zero findings. Focused execution,
  OOM, archive/checkpoint, unchanged-Core and failed-edit recovery laws pass.
- Comparison: seven alternating release pairs over 13 public examples and four
  synthetic workloads. Old semantic counters match; each compiler's output is
  stable and fresh/retained/restart parity holds. Ownership helpers
  intentionally change public Wasm. Peak deltas and teardown live bytes are
  zero; CPU is mixed. Exact pins, distributions and isolated runtime costs are
  retained in the
  [shared qualification](../zig-native/PERSISTENT_ROOTS.md#integrated-qualification-12-october-2026).
- Remaining limitations: Changed semantic targets, conflicting maps, incomplete
  captures and exhausted proofs decline. Public identities remain separate;
  physical machine-body sharing is unchanged.
- Durable record: [SYMBOLIC_BODY_REUSE](../zig-native/SYMBOLIC_BODY_REUSE.md).
