# 011 — Reduce semantic allocation traffic

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [007](007-infer-recursive-components-jointly.md),
  [008](008-canonicalize-specialization-keys.md),
  [010](010-schedule-constraints-by-variable.md)
- **Originating requirements:** PLAN: Hill 7 / region arenas and allocation
  target. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Share immutable semantic graphs and remove redundant scratch/publication copies
while preserving bounded durable ownership.

## Starting point

[region_arena.zig](../zig-native/src/region_arena.zig) already leases resettable
scratch with a 64 MiB retained cap.
[type_evidence.zig](../zig-native/src/type_evidence.zig),
[frozen_types.zig](../zig-native/src/frozen_types.zig) and
[core_eval.zig](../zig-native/src/core_eval.zig) copy graphs at semantic
boundaries. Baseline cumulative requested allocation is 321.2 MB.

## Implementation checklist

- [ ] Attribute remaining allocation to graph cloning, evidence imports, scratch
      growth and publication before changing owners.
- [ ] Share immutable subgraphs only within valid owner lifetimes; keep
      region-local variables, chronological views and independent active regions
      separate.
- [ ] Remove redundant copies and temporary retained buffers while reserving
      atomic publication capacity and bounding reusable storage.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run nested-region, immutable-input, remapping, teardown and exhaustive
  allocation-failure laws, including failure after partial preparation.
- Compare fresh, dependency population, retained edits/no-op and restart
  requested bytes, allocation counts, peak live memory and CPU.
- Ensure live requested memory returns to zero and repeated revisions do not
  grow retained capacity without bound.

## Acceptance criteria

- [ ] Measured redundant semantic allocation is removed with explicit owners and
      no scratch IDs escaping.
- [ ] Results retain atomic publication and recovery; remaining work toward
      under-100-MB cumulative allocation stays visible until task 084 passes.
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
