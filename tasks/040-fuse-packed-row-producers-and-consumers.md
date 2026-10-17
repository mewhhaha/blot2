# 040 — Fuse packed row producers and consumers

## Status, dependencies, and originating requirements

- **Status:** Complete at `2689ad5`.
- **Dependencies:** [002](002-close-packed-list-traversal-regression.md),
  [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / broader row fusion.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Broaden packed-row fusion through ordinary typed source producers and consumers.

## Starting point

[packed_layout.zig](../zig-native/src/backend/packed_layout.zig),
[collection_edit_call.zig](../zig-native/src/backend/collection_edit_call.zig),
[core_backend.zig](../zig-native/src/backend/core_backend.zig) and scalar
replacement handle admitted flat rows. Task 002 qualifies traversal and task 027
provides explicit layout/ownership facts.

## Implementation checklist

- [x] Fuse eligible producer/consumer paths using checked shapes and use
      evidence, without recognizing library declaration names.
- [x] Keep snapshots, logical row counts, F32 operation order, effect boundaries
      and evaluation/trap order exact.
- [x] Retain ordinary representation for escapes, unsupported shapes and unknown
      effects; do not expose interior row pointers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test flat tuple/record pipelines at widths 1–16, crossing leaves, slices,
  saved intermediates and shared updates.
- Compare effectful callbacks, early exits, traps and reference-bearing/nested
  fallback against unfused behavior.
- Measure row boxes/copies, guest allocation and runtime plus fresh/retained
  compiler cost.

## Acceptance criteria

- [x] Additional ordinary typed pipelines demonstrably fuse with fewer
      intermediate allocations.
- [x] Snapshots, order, effects and fallback remain correct across source and
      dependency builds.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2689ad5`; qualified tree `92e09418…51fb6a`, Zig 0.17.0 LLVM/Fast
  release SHA256 `9ea894d4…8b21`.
- Validation: full native suite, 925 guest/client tests, eight unchanged
  allocation budgets and 349 analyzer files/zero. Widths 1–16, F32/U32 order,
  slices/snapshots, escapes, effects/traps, source/compiled/checkpoint edits and
  exhaustive OOM controls pass.
- Comparison: native optimized callers eliminate temporary scalar row boxes; 31
  alternating 100,000-row guest pairs have named/composed CPU ratios .0212–.0521
  versus qualified 039/055. Direct controls, committed memory and seven
  fresh/retained compiler pairs are reported separately; no general compiler
  speedup is claimed.
- Remaining limits: bounded small-body fusion; lazy/escaped/nested/reference/
  width-17/unknown uses retain owned fallback. Collection construction and
  general iterator-state elimination remain separate work.
- Durable record: [ROW_FUSION](../zig-native/ROW_FUSION.md), including exact
  pins, rejected prototypes, raw distributions and combined costs.
