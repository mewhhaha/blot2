# 017 — Unify source and revision validation

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Record exact source/catalog/namespace dependencies and observed foreign
      binding, symbol and source bounds in the shared model.
- [ ] Preserve nominal and producer identity, ordered imports, pinned-byte
      validation and adversarial mutation rejection.
- [ ] Keep successful validation certificates distinct from permission to reuse
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

- [ ] All migrated validation uses shared records with exact identity and bounds
      checks.
- [ ] Forged or changed inputs cannot acquire a reuse proof, and failed
      candidates preserve the previous revision.
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
