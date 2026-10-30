# 039 — Guarantee and explain demand lowering

## Status, dependencies, and originating requirements

- **Status:** Complete — implementation `46bf8b9`, qualified 12 October 2026.
- **Dependencies:** [038](038-eliminate-demands-through-known-callbacks.md),
  [033](033-own-suspended-effects-and-cancellation.md)
- **Originating requirements:** DEMANDS: Predictable cost guarantee,
  diagnostics, acceptance and measurements. Sources:
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Guarantee Boolean-shaped demand elimination across supported paths and expose
bounded source-span explanations and counters.

## Starting point

Direct bounded Boolean lowering and forwarding exist, but
[zig-native/DEMANDS.md](../zig-native/DEMANDS.md) still requires a cost
guarantee across aliases/imports/bundles, loop/callback coverage and
explanations.

## Implementation checklist

- [x] Enforce branch lowering for fully applied statically resolved
      and/or-shaped bodies with known captures and proved local control,
      independent of source names.
- [x] Apply it in debug/release, aliases, custom fixities, imports and compiled
      dependencies; analyze available retained bodies when summaries are absent.
- [x] Report eliminated/direct/local-memo/stored with bounded spans/reasons and
      counters for allocations, memo slots, indirect calls, summary reuse and
      visited nodes.
- [x] Keep unknown-control fallback documented and bound cloning/long-chain
      work.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Compare false conjunction/true disjunction and taken branches with explicit
  if: no demand cell, capture allocation, memo check or demand-specific indirect
  call.
- Run the complete demand acceptance matrix: repeats, loop scopes,
  rebinding/collections, providers, persistent aliases,
  cancellation/traps/recursion, unused ill-typed arguments and body-edit
  recovery.
- Benchmark chains of 1, 8, 64 and 256 operators, taken/skipped and in loops;
  separate guest cost from compiler time, size, allocation and summary work.

## Acceptance criteria

- [x] The documented cost guarantee passes every build mode and
      source/dependency path without changing evaluation semantics.
- [x] Explanations and structural counters are bounded and accurate; retained
      edits track bodies/evidence rather than just unchanged types.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `46bf8b9`; Zig 0.17.0, complete native suite and 914
  guest/client laws, all eight unchanged allocation budgets; analyzer 348/zero.
  Independent raw-wire controls verify null/default reporting, bounded opt-in
  reports and identical executable bytes.
- Standard LLVM Fast release:
  `47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`. Three
  complete guest batches at 1/8/64/256 operators preserve zero demand storage
  and memory; paired median-of-three ratios to explicit controls are
  0.9510–1.0117. Seven public and synthetic pairs retain semantic counters,
  diagnostics and fresh/edit/restart parity. Compiler checking costs remain
  higher than explicit controls; no general speedup is claimed.
- Limits: bounded first-order proofs, source nesting limits, ordinary shared
  fallback for unknown/escaping/recursive control, report observation costs.
  These are the documented guarantee boundaries, not unresolved guarantees.
- Durable evidence: [DEMANDS](../zig-native/DEMANDS.md) and
  [combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).
