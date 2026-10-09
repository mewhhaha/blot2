# 041 — Broaden numeric simd

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [040](040-fuse-packed-row-producers-and-consumers.md)
- **Originating requirements:** PLAN: Earlier programs / broader SIMD. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend SIMD admission to additional proved numeric loops and row shapes.

## Starting point

[wasm_vectorize.zig](../zig-native/src/wasm_vectorize.zig),
[wasm_simd_ops.zig](../zig-native/src/wasm_simd_ops.zig) and
[simd_intrinsics.zig](../zig-native/src/simd_intrinsics.zig) implement current
vectorization; [compiler/guide.md](../compiler/guide.md#simd) pins wrapping and
F32 behavior.

## Implementation checklist

- [ ] Admit new loop/row shapes only with independent lane, bounds, ownership
      and effect proofs.
- [ ] Preserve U32 wrapping, F32 expression/reduction order, NaNs and signed
      zero, and original bounds/trap behavior.
- [ ] Generate correct scalar tails and retain scalar fallback for unsupported
      operations or unproved loops.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare scalar/vector execution at lengths 0–5 and around lane/leaf
  boundaries, with overflow, NaNs, infinities and signed zero.
- Test division/trap cases, misaligned ranges, shared snapshots and effectful
  callbacks that must remain scalar.
- Measure runtime, emitted instructions/code size and compilation overhead in
  both compilation tiers.

## Acceptance criteria

- [ ] New shapes show proved SIMD lowering with scalar-equivalent observable
      results.
- [ ] Tail, bounds and trap behavior stay exact and unsupported cases use the
      ordinary path.
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
