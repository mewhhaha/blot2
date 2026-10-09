# 009 — Cache composite type resolutions

## Status, dependencies, and originating requirements

- **Status:** Complete — cost-gated composite certificates are qualified and
  committed as `d736d45`.
- **Dependencies:** None.
- **Originating requirements:** PLAN: Hill 5 / solver hot paths. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend dependency-aware resolution caching from variables to composite types
without changing chronological substitution semantics.

## Starting point

[types.zig](../zig-native/src/types.zig) has node-local variable certificates;
[resolution_cache.zig](../zig-native/src/resolution_cache.zig) and
[epoch_resolution_cache.zig](../zig-native/src/epoch_resolution_cache.zig)
support generation checks. At task start, composite resolution still lost reuse
across unrelated writes; occurs-DAG traversal was already complete.

## Implementation checklist

- [x] Record the type/effect dependencies of composite answers and validate only
      relevant writes within the correct chronological window.
- [x] Revoke cached answers on rollback, physical edits, owner/depth changes and
      saturated clocks; distinguish fresh variable/effect identities.
- [x] Keep certificate metadata solver-local and ensure failed cache growth
      leaves existing answers intact.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare cached resolution with ordinary traversal over generated histories,
  historical windows, unrelated writes, aliases and shared DAGs.
- Exercise rollback/recycled IDs, physical type and effect mutation, clock
  saturation and allocation failures.
- Measure resolve visits, cold CPU and requested allocation; do not revive the
  previously rejected closed-cache prototype without new evidence.

## Acceptance criteria

- [x] Composite cache hits survive unrelated writes and every invalidating
      mutation produces the same answer as ordinary traversal.
- [x] Ownership and OOM laws pass and paired measurements demonstrate the
      retained cache is justified.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `d736d45` adds the production cache, ownership contract and durable
  qualification record. The earlier future-alias correction remains in
  `8a40c1a`.
- Validation: Zig 0.17.0; the full native suite and all 598 guest/client tests
  pass, with zero analyzer findings across 289 Zig files. The focused native
  resolution filter passes 41 checks including discovery. Generated histories,
  chronological windows, unrelated writes, aliases, physical type/effect edits,
  rollback/recycled IDs, future views, saturated clocks and allocation failures
  are covered. The isolated candidate also passes 305 corpus cases (610
  invocations) with identical diagnostics and Wasm, and fourteen focused
  execution laws including dependencies, checkpoints and failed revisions.
- Comparison: production release
  `0e78ed2c1e6343c41fb92cc1565fc0f11ffa007a74ca869826cf67307ddcb78d` is pinned
  in `build/bench/composite-cache-main/`. Three integration pairs measure
  baseline/candidate fresh CPU at 954/957 ms, population at 1,110/1,120 ms,
  first edits at 250/250 ms and subsequent edits at 230/220 ms. A separate
  restart batch measures 637/639 ms restart CPU. All byte comparisons pass.
  Fresh requested allocation falls from 321,139,550 to 321,088,050 bytes. These
  loaded-host observations do not establish a general compiler speedup.
- Justification: seven alternating Store microbenchmark pairs resolve a 32-layer
  array after 10,000 unrelated writes. Median CPU falls from 9.251 to 1.089 ms
  and type nodes from 320,040 to 72, with identical checked results. The default
  policy retains only normalizations creating at least four nodes; cheaper
  queries avoid the certificate cost identified in rejected probes.
- Remaining limitations: 16 direct-mapped slots, eight frontier dependencies,
  256 visited nodes and a 128-entry traversal stack bound retained cost.
  Unsupported or larger proofs use ordinary resolution. The final compiler CPU,
  edit and cumulative-allocation targets remain open in their own tasks.
- Durable record: [resolution caching](../zig-native/RESOLUTION_CACHING.md)
  preserves the contract, accepted implementation, rejected experiments, binary
  identities, commands and raw-data locations outside this task directory.
