# 011 — Reduce semantic allocation traffic

## Status, dependencies, and originating requirements

- **Status:** Complete — explicit owner attribution and redundant capture-copy
  removal pass semantic and measured qualification.
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

- [x] Attribute remaining allocation to graph cloning, evidence imports, scratch
      growth and publication before changing owners.
- [x] Share immutable subgraphs only within valid owner lifetimes; keep
      region-local variables, chronological views and independent active regions
      separate.
- [x] Remove redundant copies and temporary retained buffers while reserving
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

- [x] Measured redundant semantic allocation is removed with explicit owners and
      no scratch IDs escaping.
- [x] Results retain atomic publication and recovery; remaining work toward
      under-100-MB cumulative allocation stays visible until task 084 passes.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: the local milestone includes this record; its full source revision is
  recorded in `candidate-allocation/manifest.json` and the durable record.
- Validation: Zig 0.17.0; full LLVM native suite and 618 guest/client tests
  pass, with zero findings across 295 Zig files. New
  immutable-input/owned-snapshot laws sweep every allocation failure; nested
  client-meter laws pass. Strict comparison checks 620 cases / 1,240 invocations
  with identical diagnostics and Wasm and zero live teardown bytes. Initial
  execution passes 58 guests / 3,436 calls; edited execution passes 90 guests /
  10,500 calls.
- Comparison: immutable canonical baseline and allocation candidate hashes are
  recorded in the durable qualification. Eighty fresh workloads / 15 alternating
  pairs / 2,400 invocations have median workload CPU ratio 1.00023. Width128's
  16 distinct factories remove 14,720 requested bytes and 32 allocation calls.
  Seventy-six retained/restart workloads / seven pairs / 6,384 phase samples
  preserve strict parity. Four direct retained workloads / seven pairs / 4,704
  revision samples plateau per phase through 20 edit/revert cycles and release
  to zero; 168 additional production CLI invocations measure fresh,
  cache-population and restart bytes/counts/peaks and CPU separately.
- Remaining limitations: small controls and no-op adapters add bounded traffic;
  no general CPU or memory-peak improvement is claimed. Attribution is not a
  complete disjoint partition. Private gdev remains absent and task 084 retains
  the under-100-MB target; public revision plateaus are not a universal bound.
- Durable record:
  [semantic allocation ownership](../zig-native/SEMANTIC_ALLOCATION.md).
