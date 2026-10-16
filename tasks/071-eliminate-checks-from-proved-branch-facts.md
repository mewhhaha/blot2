# 071 — Eliminate checks from proved branch facts

## Status, dependencies, and originating requirements

- **Status:** Complete — finite branch plans, required traps and erased
  representation qualify in the final combined gate.
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

Task 070 supplies sound witnesses and task 026 resolved control flow. The
[proof design](../zig-native/ERASED_PROOFS.md) defines dominated edges, exact
value versions, joins, loop limits and arithmetic rules.
[wasm_control_flow.zig](../zig-native/src/backend/wasm_control_flow.zig),
[runtime_ir.zig](../zig-native/src/backend/runtime_ir.zig) and emission
currently preserve ordinary bounds/trap checks.

## Implementation checklist

- [x] Propagate facts along dominated edges and retain only facts valid at joins
      and loop boundaries.
- [x] Remove a check only when exact index/length and arithmetic facts prove it;
      retain all necessary traps.
- [x] Erase witness-only runtime storage/operations and invalidate facts on
      changed inputs or evidence.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Apply the complete guard/rebinding/wrap/trap-order matrix in the proof design,
  including no-feature controls and required-evidence budget rejection.
- Compare guarded and witness-backed accesses with unproved cases across
  branches, loops, rebinding and imported helpers.
- Test false/contradictory assumptions, overflow, boundary indices and side
  effects before trapping accesses.
- Inspect generated checks/proof allocation and measure bounded checking cost
  plus retained-edit invalidation.

## Acceptance criteria

- [x] Proven redundant checks disappear and proof values impose no runtime
      representation cost.
- [x] Unproved or invalidated accesses keep required checks and trap/effect
      order remains exact.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Revision: uncommitted source based on
  `ef57ec5b99b5ea25fc5532fd2d3023108d3f10bb`; no commit or push, as requested.
  Frozen manifest SHA-256
  `3548546cb8660905de9a83922bab67270376a2b955f840f2bc7cf13fcefa53ec`.
- Validation: final Zig 0.17.0 LLVM/Fast/Safe gate passes **2,223 native laws,
  1,404 guest/client tests and 1,366 complete allocation-failure sweeps** plus
  two expected-error harness laws, with zero skips/leaks/logged errors. Full
  455-file analyzer has zero findings. Gate wall 697.812 s.
- Release executable/decompressed bundle SHA-256
  `6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`. Exact
  inputs, identities, logs, per-phase timings and post-run verification:
  `build/bench/complete-program-20261015/final-proof-repaired-gate/`.
- Comparison: finite cost measurements include 256 required consistency
  requirements in 4,902 visits/44,620 peak bytes and a shared 2,049-term graph
  in 2,817 visits/11,560 peak bytes. Twenty-five balanced whole-process pairs
  measure proof fresh/edit ratios 1.003/1.001; these are near-parity focused
  results, not release speedup claims. The ordinary Cost control remains
  byte-exact at 11,958 B/SHA-256
  1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad.
- Limits: the approved finite design retains necessary checks for unknown,
  wrapping, effectful or exhausted optional analysis. Invalid/exhausted required
  contracts reject; no arbitrary theorem solving is promised. Broader program
  performance and remote CI remain in tasks 084/093 and 082.
- Durable acceptance, erasure/import/retained/OOM controls and historical pins:
  [numeric qualification](../zig-native/NUMERIC_PROOFS_QUALIFICATION.md).
