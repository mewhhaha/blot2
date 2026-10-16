# 021 — Publish transactional revision deltas

## Status, dependencies, and originating requirements

- **Status:** Complete — local milestone `696051e`.
- **Dependencies:** [017](017-unify-source-and-revision-validation.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** PLAN: Hill 6 and earlier semantic compilation /
  revision deltas. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Publish changed revision metadata as transactional deltas while reusing
unchanged immutable data.

## Starting point

[retained_revision.zig](../zig-native/src/reuse/retained_revision.zig),
[project.zig](../zig-native/src/reuse/project.zig),
[revision_inputs.zig](../zig-native/src/reuse/revision_inputs.zig) and
[frozen_dependency.zig](../zig-native/src/reuse/frozen_dependency.zig) preserve
last-good revisions but still reconstruct metadata on edits.

## Implementation checklist

- [x] Separate unchanged immutable metadata from candidate-owned changes and
      commit the delta only after all required work succeeds.
- [x] Share owners with explicit lifetime rules and bounded compaction; avoid an
      unbounded chain of previous revisions.
- [x] Release failed candidate allocations without touching prior source bytes,
      query records, exports or checkpoint eligibility.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Repeat literal/body/import edits, no-ops and failed corrections across many
  revisions and compare fresh results.
- Inject failure at delta preparation, import and publication; verify the old
  revision and its exported checkpoint remain usable.
- Measure metadata copies, retained capacity and peak/cumulative allocation
  separately from semantic and emission work.

## Acceptance criteria

- [x] Unchanged metadata is reused and only complete deltas become visible.
- [x] Repeated edits keep ownership bounded; failed edits/OOM preserve the
      previous revision exactly.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `696051e6db35a5464636131706e559092c9f37e6` (compiler milestone).
- Implementation: [pool_leases.zig](../zig-native/src/eval/pool_leases.zig)
  gives 41 plain artifact pool slices refcounted leases. Captures with an
  in-process previous revision compare each field with its leased predecessor
  and retain equal leases, copying only changed fields. Leases are taken during
  preparation and released by failed, rejected or discarded candidates; commit
  remains an allocation-free move and old revisions release their references.
  Leases name single allocations, so edits never chain revisions. The unread
  per-body pins (`Pools.bodies`) are removed. Work counters report shared and
  copied metadata.
- Validation: Zig 0.17.0 before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and 626 guest/client tests;
  `deno task
  lint:zig` reports zero findings across 307 files. Native laws
  prove sharing exactly when content is equal with fresh-equal output, teardown
  in either order, lease restoration under an allocation-failure sweep, bounded
  storage across twelve alternating edits, and, in a retained Session, unchanged
  leases and checkpoint bytes through every preparation failure followed by
  commit. A test helper that reallocated a pool slice was corrected to release
  its lease.
- Comparison: 21 alternating repetitions of a retained-session probe over eight
  workloads (literal, body, constant and import edits; rejected edits; no-op
  corrections) emit identical Wasm per phase with per-phase retained plateaus.
  Steady edits/reverts request 62–158 KB less (1.4–6.1%), peak 25–98 KB less and
  retain 21–26 KB less; CPU geomean 0.967 (edit) and 0.958 (revert), with
  controls at 1.009 (rejected) and 0.992 (no-op). Population requests 45–112 KB
  less at CPU 0.995.
- Remaining limitations: module pins, substitutions, bridge, operation keys,
  proofs and certificates are still rebuilt; sharing is whole-field; gdev-scale
  edits are unmeasured.
- Durable record: [revision deltas](../zig-native/REVISION_DELTAS.md),
  [distributions](../zig-native/qualification/revision-deltas.csv) and
  [pins](../zig-native/qualification/revision-deltas-pins.json).
