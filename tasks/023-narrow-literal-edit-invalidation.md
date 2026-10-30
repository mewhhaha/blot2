# 023 — Narrow literal edit invalidation

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `fbe28c8`.
- **Dependencies:** [022](022-retain-constants-and-relocatable-data.md)
- **Originating requirements:** PLAN: Hill 6 / literal edits under 30 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Re-evaluate only affected constants and update changed data, instructions and
relocations after literal edits.

## Starting point

The baseline gdev literal edit takes 150/140 ms and can rebuild the seed.
[retained_revision.zig](../zig-native/src/reuse/retained_revision.zig),
[core_backend.zig](../zig-native/src/backend/core_backend.zig) and query
dependency records now have the foundations for narrower invalidation.

## Implementation checklist

- [x] Trace a literal change through exact staged consumers, data and executable
      dependencies; preserve unrelated bodies and metadata.
- [x] Patch candidate-owned data/instructions/relocations through normal
      compiler APIs, never generated output as a workaround.
- [x] Retain conservative rebuilds when value-dependent identities or
      unsupported graphs prevent a proof.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Edit and revert scalar, aggregate and captured literals, including the frozen
  gdev `floor_half_extent` edit.
- Compare fresh/retained bytes, constants and execution after dependency/restart
  loading, failed edits and repeated revisions.
- Record rebuilt bodies, metadata copies, first/subsequent edit CPU and
  allocation; preserve no-op behavior.

## Acceptance criteria

- [x] Counters and artifacts show unrelated bodies and metadata remain reusable
      across admitted literal edits.
- [x] The under-30-ms literal target is demonstrated in paired measurements or
      remains explicitly open for task 084/follow-up work.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `fbe28c88a45b253289402fef4503dae6d3e42147` (compiler milestone).
- Implementation: the reuse gate compares the effect-operation catalog exactly
  instead of disabling itself for any edited module with operation values.
  Witnesses are projected by their owning declaration, so a changed provider,
  state initial value or witness dirties only that declaration and its
  consumers; unaffected bodies in effectful modules and in every other module
  stay reusable. Dependency certificates share, by lease, the image of each unit
  the gate proved exactly unchanged instead of re-serializing every module per
  edit. Retained fragments still patch data, instructions and relocations
  through the ordinary replay path (task 022); no generated output is patched.
  Added or shifted operation values, type and associated-catalog edits still
  disable the gate.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 629 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 309 files. Native laws
  cover body, witness and state-provider literal edits, declined catalog shifts,
  certificate sharing (exactness, stamp and forgery checks) and
  allocation-failure sweeps; a mutant with the old catalog rule fails the four
  laws that depend on it. A process-level law edits, reverts, breaks and
  re-edits ten literals in public examples (including ecs, requests,
  generic_effects, host_io and host_capabilities) against fresh servers, and
  executes a generated state-provider/witness program. The frozen gdev
  `floor_half_extent` edit was not run: gdev is private and unavailable.
- Comparison: 21 alternating repetitions of nine rounds over thirteen workloads
  emit identical Wasm in every phase. Effectful edits now reuse unaffected code
  (a 40-function import: 0 → 80 of 82 named functions; ecs 0 → 6 of 20).
  Pure-module edits are 5–18% faster with 196–327 KB less requested per edit
  from shared certificate images. Effectful edits at public-example size are
  CPU-neutral to 6–14% slower (the 40-function import 1.003, ecs 1.064) because
  verification and fragment replay cost about what small functions cost to
  specialize; first edits after population are 1.1–1.8 × slower there. Steady
  CPU geomeans are 0.970 (edit) and 0.968 (revert). Baseline `9734227` (sources
  of `62241e2`).
- Remaining limitations: invalidation stays per declaration, so consumers of an
  edited constant rebuild even when they read only unchanged parts (ecs
  `simulation`); population publishes no certificate; constants are still
  evaluated every revision. The under-30-ms literal target is not demonstrated
  and remains open for task 084, since gdev is unavailable here.
- Durable record: [literal edits](../zig-native/LITERAL_EDITS.md),
  [distributions](../zig-native/qualification/literal-edits.csv) and
  [pins](../zig-native/qualification/literal-edits-pins.json).
