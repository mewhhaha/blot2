# 002 — Close packed list traversal regression

## Status, dependencies, and originating requirements

- **Status:** Complete — current all-width fold closure qualified at `dd6a66a`;
  cursor follow-up remains task 047.
- **Dependencies:** [001](001-qualify-list-span-prototype.md)
- **Originating requirements:** PLAN: Earlier programs still open / Collections.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Close the read-only packed List fold regression and investigate the related
cursor regression on reproducible current workloads. On 11 October 2026 the
owner waived restoring the missing legacy benchmark binaries and historical gdev
snapshot. Historical results remain evidence of the original problem; current
qualification must pin its own inputs and reference implementation.

## Starting point

[std/PERFORMANCE.md](../std/PERFORMANCE.md#choosing-collections) records roughly
1.9× fold CPU and 1.5× cursor CPU.
[core_backend.zig](../zig-native/src/backend/core_backend.zig) contains
`Emitter.readListRow`, direct loop lowering and cursor extraction;
[list_runtime.zig](../zig-native/src/runtime/list_runtime.zig) owns leaf
traversal. Task 001 determines whether its narrower span change lands.

## Implementation checklist

- [x] Locate and pin the older boxed compiler and matching library/workload from
      the preserved packed-row qualification evidence; retain a separate
      current-main comparison.
- [x] Profile fold and cursor costs, then remove repeated leaf lookup, bounds
      work or row materialization only where typed layout and control-flow
      proofs permit it.
- [x] Cover all supported scalar row widths 1–16, cross-leaf rows, nested loops,
      forks and snapshots. Keep List distinct from Array and expose no public
      List indexing.
- [x] Retain boxed paths for nested, nominal, reference-bearing, erased and
      wider rows. Record the cursor diagnosis and any remaining cursor work
      explicitly.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

- Run packed-row, packed-row revision, cursor-fork, iterator and collection
  execution suites, plus native immutable-Core/allocation-failure laws.
- Compare empty, single-leaf, multi-leaf and crossing-row traversal, early break
  and saved cursors after persistent updates, including F32 bit preservation.
- Use alternating packed/boxed `scripts/bench_packed_rows.ts` runs and the
  iterator harness with matched libraries. Report fold and cursor distributions,
  compiler overhead, allocation and guest memory.

## Acceptance criteria

- [x] Paired evidence demonstrates the read-only fold regression is closed over
      the supported shapes; a partial-width improvement is not full completion.
- [x] The related cursor regression is measured and explained. Any unresolved
      required behavior or performance work has a bounded follow-up before final
      qualification.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Final implementation: `dd6a66a`; a separate record commit follows. Zig 0.17.0;
  `deno task test:compiler` passes the full native suite and 892 guest/client
  laws, including eight unchanged release allocation budgets. Analyzer: 344 Zig
  files, zero findings. Three complete merged all-width F32 paired batches
  preserve source-ordered scalar results and close the boxed fold gap (worst
  paired ratios 0.994328 records / 0.994013 tuples); U32 rows stay below boxed
  at every width.
- Seven cold public and seven synthetic fresh/retained/restart pairs preserve
  declared counters, diagnostics, output parity and zero teardown ownership. The
  [joint durable record](../zig-native/CYCLIC_OWNERSHIP_QUALIFICATION.md#integrated-qualification--12-october-2026)
  pins exact source/binary/commands/distributions.
- Implementation: a rooted private tree walk advances through leaves without
  repeated root lookup; checked scalar-only row uses and flat tuple bindings
  borrow scoped views; crossing rows use a hoisted private scalar buffer with
  constant-size copies; exact contiguous U32 sums use vector lanes with scalar
  tails. Escaping rows stay owned, and nested, nominal, reference-bearing,
  erased and wider rows keep boxed paths.
- Milestones: `c6654ec` merged dependency 001; `bcff12b` recorded the tested
  sequential-leaf implementation; `90bd532` added qualified U32 row reductions
  and bounded callee admission (native suite, 598 guest/client tests, analyzer);
  the V13 handoff of 12 October 2026 closed every F32 width before the
  integrated `dd6a66a` gate.
- Rejected or unlanded: larger global leaves (shared append memory), a
  fixed-size crossing copy, float load grouping, a reduced traversal guard and
  the 9 October storage-word loop counter (no consistent F32 gain; U32 tuple
  width 5 median 1.096). Pins and measurements are in
  [word positions at leaf boundaries](../zig-native/LIST_TRAVERSAL.md#word-positions-at-leaf-boundaries-9-october-2026)
  and the surrounding sections.
- Owner decision, 11 October 2026: skip restoration of legacy artifacts. This
  removes that prerequisite, not the current correctness and all-width
  performance checks. See
  [current qualification scope](../zig-native/LIST_TRAVERSAL.md#current-qualification-scope-11-october-2026).
- Remaining scope: task 047 owns the measured cursor regression (the explicit
  cursor still allocates persistent progress and extracts rows through its
  cached lookup); localized shared-append tails remain explicit; task 035 owns
  the pre-existing nested-loop retention counterexample. No memory/update win
  over boxed is claimed. Nothing is pushed.
- Durable record: [List traversal](../zig-native/LIST_TRAVERSAL.md) records the
  ownership boundary, binary identities, every width's ratios, cursor and memory
  measurements, benchmark-safety checks and rejected candidates;
  [integrated fold closure](../zig-native/LIST_TRAVERSAL.md#integrated-fold-closure-12-october-2026)
  and
  [V13 handoff](../zig-native/LIST_TRAVERSAL.md#current-v13-release-handoff-12-october-2026)
  hold the final qualification.
