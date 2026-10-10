# 017 — Unify source and revision validation

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified at `089efb0`.
- **Dependencies:** [016](016-migrate-specialization-and-principal-queries.md)
- **Originating requirements:** PLAN: Hill 12 / dependency records; earlier
  semantic compilation. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Move dependency certificates, source validation and revision inputs onto shared
dependency records.

## Starting point

[dependency_certificate.zig](../zig-native/src/dependency_certificate.zig),
[revision_inputs.zig](../zig-native/src/revision_inputs.zig),
[frozen_core_validation.zig](../zig-native/src/frozen_core_validation.zig) and
[dependency_admission.zig](../zig-native/src/dependency_admission.zig) validate
source images, bounds, pinned bytes and identities separately.

## Implementation checklist

- [x] Record exact source/catalog/namespace dependencies and observed foreign
      binding, symbol and source bounds in the shared model.
- [x] Preserve nominal and producer identity, ordered imports, pinned-byte
      validation and adversarial mutation rejection.
- [x] Keep successful validation certificates distinct from permission to reuse
      semantic, executable or evaluated results.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run source-input, revision-input, retained-catalog, frozen-Core and
  dependency-interface validation laws.
- Mutate source bytes, namespaces, catalog order, IDs and foreign bounds while
  keeping superficial hashes or interfaces stable.
- Check dependency/checkpoint round trips, allocation failure and
  last-good-revision recovery.

## Acceptance criteria

- [x] All migrated validation uses shared records with exact identity and bounds
      checks.
- [x] Forged or changed inputs cannot acquire a reuse proof, and failed
      candidates preserve the previous revision.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `089efb0b9b29504513bc0808fb20992b09c53f89` (local milestone).
- Validation: Zig 0.17.0; full LLVM `deno task test:compiler` passes native
  execution and 623 guest/client tests. `deno task lint:zig` reports 301 files
  and zero findings; package dry run passes. Final focused batch passes 31
  tests; broader source/revision/dependency/frozen-Core/recovery batch passes
  227. OOM, equal-stamp graph mutation, namespace/producer ordering,
  symbol/source/foreign bounds, moved-byte ownership and budget refusal pass.
- Comparison: immutable task-016 baseline versus final candidate across 626
  cases / 3,756 six-policy invocations preserves ordered diagnostics and Wasm.
  192 guests / 10,362 calls execute. Retained/restart proof and failure controls
  preserve fresh parity, last-good owners and diagnostics under six policies.
  Full artifact/input/driver/library/report pins are in the durable record.
- Measurement: 86 fresh workloads × 15 pairs give CPU ratio 1.0037, wall 1.0011,
  unchanged requested allocation. Fifteen retained workloads × seven pairs cover
  210 native drivers / 17,640 phases and 630 CLI builds; all plateau and
  teardown to zero. Positive entry-only edits reuse two dependency validations
  with zero fresh validations. Exact certificates increase steady-edit CPU about
  14% in those controls and add 31–64 KiB held payload; input payload and
  capacity are unchanged. No speedup or retained allocation reduction is
  claimed.
- Remaining limitations: mutable acquisition/errors remain operational;
  singleton input/certificate records need no bucket index and keep separate
  owners. Incoming dependency/interface validators and same-owner Gate leases
  remain authoritative. Native images are not wire payloads (task 019), and
  oversized optional certificates rerun validation. Private gdev/original boxed
  artifacts remain unavailable; tasks 002/084 stay open.
- Durable record: [source validation](../zig-native/SOURCE_VALIDATION.md),
  [fresh distributions](../zig-native/qualification/source-validation-queries-fresh.csv),
  [retained distributions](../zig-native/qualification/source-validation-queries-retained.csv),
  [pins](../zig-native/qualification/source-validation-queries-pins.json) and
  [identical native probe](../zig-native/qualification/source_validation_probe.zig).
