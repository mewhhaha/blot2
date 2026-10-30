# 041 — Broaden numeric simd

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified at `850793f`.
- **Dependencies:** [040](040-fuse-packed-row-producers-and-consumers.md)
- **Originating requirements:** PLAN: Earlier programs / broader SIMD. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Extend SIMD admission to additional proved numeric loops and row shapes.

## Starting point

[wasm_vectorize.zig](../zig-native/src/backend/wasm_vectorize.zig),
[wasm_simd_ops.zig](../zig-native/src/backend/wasm_simd_ops.zig) and
[simd_intrinsics.zig](../zig-native/src/backend/simd_intrinsics.zig) implement
current vectorization; [compiler/guide.md](../compiler/guide.md#simd) pins
wrapping and F32 behavior.

## Implementation checklist

- [x] Admit new loop/row shapes only with independent lane, bounds, ownership
      and effect proofs.
- [x] Preserve U32 wrapping, F32 expression/reduction order, NaNs and signed
      zero, and original bounds/trap behavior.
- [x] Generate correct scalar tails and retain scalar fallback for unsupported
      operations or unproved loops.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Compare scalar/vector execution at lengths 0–5 and around lane/leaf
  boundaries, with overflow, NaNs, infinities and signed zero.
- Test division/trap cases, misaligned ranges, shared snapshots and effectful
  callbacks that must remain scalar.
- Measure runtime, emitted instructions/code size and compilation overhead in
  both compilation tiers.

## Acceptance criteria

- [x] New shapes show proved SIMD lowering with scalar-equivalent observable
      results.
- [x] Tail, bounds and trap behavior stay exact and unsupported cases use the
      ordinary path.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `850793f`, joint implementation tree `ee33b8b5…cf46`.
- Validation: Zig 0.17.0 full native/936 guest-client gate, eight unchanged
  budgets and 350 analyzer files/zero. Both-tier tails, row widths/slices,
  snapshots, effects, F32 order/traps, retained/checkpoint edits and OOM pass.
  The initial helper-directory failure and corrected recovery are preserved.
- Comparison: LLVM/Fast `fa471c09…2387` versus qualified 040 `9ea894d4…8b21`.
  Scoped generator CPU ratios .5013/.5717; Array rows .8350–.9046, smaller List
  rows .8997–.9127. Guest memory is unchanged. Public compile CPU .9966–1.0173;
  no general compiler speedup or reliable widest-List gain is claimed.
- Remaining limitations: conditional/carrying loops, trapping/effectful kernels
  and unproved row products retain ordinary scalar lowering. Reductions are
  never automatically regrouped. Development artifacts stay scalar and exact.
- Durable record: [NUMERIC_SIMD](../zig-native/NUMERIC_SIMD.md), with exact
  pins, three isolated screens and the merged release distributions.
