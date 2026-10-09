# 071 — Eliminate checks from proved branch facts

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [070](070-implement-numeric-and-index-witnesses.md),
  [026](026-resolve-structured-control-flow.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / branch facts
  and erasure. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Remove redundant checks from valid branch facts and erase proof representation.

## Starting point

Task 070 supplies sound witnesses and task 026 resolved control flow.
[wasm_control_flow.zig](../zig-native/src/wasm_control_flow.zig),
[runtime_ir.zig](../zig-native/src/runtime_ir.zig) and emission currently
preserve ordinary bounds/trap checks.

## Implementation checklist

- [ ] Propagate facts along dominated edges and retain only facts valid at joins
      and loop boundaries.
- [ ] Remove a check only when exact index/length and arithmetic facts prove it;
      retain all necessary traps.
- [ ] Erase witness-only runtime storage/operations and invalidate facts on
      changed inputs or evidence.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare guarded and witness-backed accesses with unproved cases across
  branches, loops, rebinding and imported helpers.
- Test false/contradictory assumptions, overflow, boundary indices and side
  effects before trapping accesses.
- Inspect generated checks/proof allocation and measure bounded checking cost
  plus retained-edit invalidation.

## Acceptance criteria

- [ ] Proven redundant checks disappear and proof values impose no runtime
      representation cost.
- [ ] Unproved or invalidated accesses keep required checks and trap/effect
      order remains exact.
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
