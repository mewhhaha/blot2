# 027 — Represent ownership in resolved ir

## Status, dependencies, and originating requirements

- **Status:** Complete at `c226967`.
- **Dependencies:** [026](026-resolve-structured-control-flow.md)
- **Originating requirements:** PLAN: Earlier semantic compilation / resolved
  ownership. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Encode allocation, borrowing, transfer, sharing and cleanup roles explicitly in
resolved IR.

## Starting point

[runtime_layout.zig](../zig-native/src/runtime/runtime_layout.zig),
[runtime_ir.zig](../zig-native/src/backend/runtime_ir.zig) and
[wasm_lifetimes.zig](../zig-native/src/backend/wasm_lifetimes.zig) describe
layouts and machine-level lifetime facts. Ownership is not inferable from
arbitrary i32 words; task 026 provides explicit edges.

## Implementation checklist

- [x] Attach typed allocation and field roles from checked layouts, including
      shared/owned pointers, scalar payloads and allocation bases.
- [x] Represent transfers, borrows, escapes and cleanup on each
      normal/exceptional edge, retaining conservative unknown cases.
- [x] Preserve aliases, persistent collection snapshots, cyclic groups and
      suspended payload lifetimes.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Test scalar words resembling pointers, reference-bearing rows, escaping
  groups, shared children and cycles.
- Check branch/loop liveness, last borrows, returns, request cancellation and
  allocation-failure cleanup.
- Compare lifetime optimizations with conservative execution and fresh/retained
  output.

## Acceptance criteria

- [x] Ownership roles come from checked layouts and explicit operations, never
      raw machine-word types.
- [x] Every admitted transfer/cleanup has a valid edge and alias proof; unknown
      ownership remains conservative.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `c226967` ("Carry ownership roles from checked layouts into runtime
  IR").
- Change: [runtime_ir.zig](../zig-native/src/backend/runtime_ir.zig) adds roles
  (scalar, reference, value, unknown), per-function parameter roles and an
  `ownership` annotation op whose runs give each constant-size allocation's word
  roles. The emitter derives both from checked layouts and the runtime
  structures' role tables; the journal records parameter roles and both replays
  restore them. The encoder drops annotations, and size heuristics and
  machine-code sharing ignore them. The lifetime pass treats only non-scalar
  `i32` parameters as candidate addresses, lets a scalar word never carry a
  followed reference, and counts contrary stores as `role_conflicts`.
- Edges: releases stay on the control-flow edges the lifetime plan chooses,
  transfers are owned-result summaries, borrows are parameter extents, unproved
  values escape to arena policy, and structured exits discharge scoped cleanup
  (task 026); unknown roles stay conservative.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 647 guest/client tests; `deno task lint:zig` reports zero findings. Native
  laws cover annotation runs and their boundaries, scalar words and scalar
  parameters in the lifetime pass, encoding and journal replay; a process law
  covers template captures, constructor cells, records, arrays and request loops
  through edits with zero conflicts, and fails when the capture environment rule
  is reverted. Seventeen source files whose inline tests were never registered,
  including the lifetime pass's own ownership laws, now run in the native suite;
  one stale demand law is skipped pending task
  [098](098-type-check-recursive-demand-forwarding.md).
- Comparison: every public example, the synthetic corpus in every phase and gdev
  emit byte-identical Wasm (gdev SHA-256 `3158216b…def0`, 840,534 bytes) with
  zero role conflicts; gdev annotates 4,318 allocations and gives 1,873
  functions parameter roles. The conflict counter first exposed captured
  templates stored under a unit placeholder role, which changed gdev by 52 bytes
  until the capture rule was fixed.
- Remaining limitations: roles do not drive reference counting yet (tasks
  030–035); `value` words still need their checked type at each use; runtime
  helpers' functions and allocations carry no roles.
- Durable record: [ownership roles](../zig-native/OWNERSHIP_ROLES.md).
