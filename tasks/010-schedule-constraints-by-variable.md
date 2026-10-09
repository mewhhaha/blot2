# 010 — Schedule constraints by variable

## Status, dependencies, and originating requirements

- **Status:** Complete — `352b3ff` schedules larger inference regions with
  variable-indexed worklists; remaining limits are recorded below.
- **Dependencies:** [009](009-cache-composite-type-resolutions.md)
- **Originating requirements:** PLAN: Hill 5 / indexed solver worklist. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Replace repeated whole-region scans with variable-indexed constraint and alias
worklists.

## Starting point

`ClosureRegion.solveMode`, `solveStep` and `solveDataAliases` in
[core_eval.zig](../zig-native/src/core_eval.zig) repeatedly scan work.
[types.zig](../zig-native/src/types.zig) owns chronological writes;
[work_counters.zig](../zig-native/src/work_counters.zig) records passes and
visits.

## Implementation checklist

- [x] Index each constraint and data alias by every variable/effect dependency
      that can make it ready, updating watches as resolutions change.
- [x] Enqueue affected work on writes, preserve fixed-point completeness, and
      make queue ordering reproduce authoritative source diagnostics.
- [x] Handle new constraints, rollback, component re-entry and unsolved
      obligations without missed wakeups or infinite retries.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare worklist and existing solver behavior over chains, diamonds, row
  aliases, callback effects and mutually recursive components.
- Test constraints added during solving, multiple writes before dequeue,
  unresolved cycles, limits and OOM cleanup.
- Record solver passes/constraint visits and paired fresh/retained CPU; tighten
  applicable compile budgets after demonstrated reductions.

## Acceptance criteria

- [x] All dependency changes wake the necessary constraints and aliases and
      reach the same fixed point and diagnostic order.
- [x] Repeated unrelated full scans disappear in measured workloads without an
      allocation or recovery regression.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `352b3ff` adds the production worklists, ownership contract, budget
  update and durable qualification record on top of `34c881b`.
- Validation: Zig 0.17.0; the full native suite and all 598 guest/client tests
  pass, with zero analyzer findings across 290 Zig files. Native laws compare
  the indexed and scan schedulers over reverse constraint and data-alias chains
  (127 versus 2,080 visits at 64 links), coalesced writes, source-ordered
  rounds, rollback with recycled IDs, effect writes, future clocks, physical
  edits, saturated generations, bounded frontiers, recycled watch slots, work
  appended after a pass, the small-to-indexed transition and allocation
  failures. The 305-case corpus (610 invocations) matches the baseline for both
  debug and release candidates, with identical diagnostics, constant steps, code
  instances and Wasm, and no live compiler memory after teardown.
- Comparison: release
  `d04f4246c48a49fbaf14978cd54485171bc3df76eb9446bea9b8c4b106a92689` against
  `0e78ed2c1e6343c41fb92cc1565fc0f11ffa007a74ca869826cf67307ddcb78d`. On gdev,
  constraint visits fall from 35,215 to 29,679 and requested allocation from
  321,082,488 to 319,651,956 bytes; Wasm is identical. Seven alternating pairs
  measure 633/623 ms fresh CPU, 730/720 ms population, 150/150 ms first edit and
  130/140 ms subsequent edit; twenty-one pairs measure 660/659, 770/760, 160/160
  and 140/150 ms, with subsequent-edit means of 153.3/150.5 ms. Restart measures
  390/397 ms. The release budget workloads keep allocation within 0.04% of the
  baseline; fanout visits fall from 3,095 to 2,582 and its budget is tightened.
  An earlier allocation screen compared a debug candidate with the release
  baseline and is withdrawn.
- Scan attribution: an instrumented, non-production build records 27,023 visits
  for the 22,407 constraints in gdev's 496 indexed regions (1.21 per constraint)
  and 2,656 bounded-scan visits for the 1,644 constraints in 954 smaller
  regions.
- Remaining limitations: regions with at most eight constraints and aliases
  rescan them each pass. Body collection, rollback, physical edits, saturated
  clocks and the fallback phase wake all unresolved work. Effect-argument
  recovery, source-witness comparisons and oversized frontiers keep broad write
  watches. No compiler-speed gain is claimed; the cold, edit and allocation
  targets remain open in their own tasks.
- Durable record: [indexed inference work](../zig-native/INDEXED_SOLVER.md)
  records the contract, both candidates, the withdrawn allocation screen, binary
  identities and raw-data locations in
  `build/bench/indexed-solver-lazy-release/`.
