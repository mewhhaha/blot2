# 002 — Close packed list traversal regression

## Status, dependencies, and originating requirements

- **Status:** In progress — task 001 is qualified; no completion is claimed.
- **Dependencies:** [001](001-qualify-list-span-prototype.md)
- **Originating requirements:** PLAN: Earlier programs still open / Collections.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Close the read-only packed List fold regression and investigate the related
cursor regression against the preserved pre-packed boxed baseline.

## Starting point

[std/PERFORMANCE.md](../std/PERFORMANCE.md#choosing-collections) records roughly
1.9× fold CPU and 1.5× cursor CPU.
[core_backend.zig](../zig-native/src/core_backend.zig) contains
`Emitter.readListRow`, direct loop lowering and cursor extraction;
[list_runtime.zig](../zig-native/src/list_runtime.zig) owns leaf traversal. Task
001 determines whether its narrower span change lands.

## Implementation checklist

- [x] Locate and pin the older boxed compiler and matching library/workload from
      the preserved packed-row qualification evidence; retain a separate
      current-main comparison.
- [ ] Profile fold and cursor costs, then remove repeated leaf lookup, bounds
      work or row materialization only where typed layout and control-flow
      proofs permit it.
- [ ] Cover all supported scalar row widths 1–16, cross-leaf rows, nested loops,
      forks and snapshots. Keep List distinct from Array and expose no public
      List indexing.
- [ ] Retain boxed paths for nested, nominal, reference-bearing, erased and
      wider rows. Record the cursor diagnosis and any remaining cursor work
      explicitly.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run packed-row, packed-row revision, cursor-fork, iterator and collection
  execution suites, plus native immutable-Core/allocation-failure laws.
- Compare empty, single-leaf, multi-leaf and crossing-row traversal, early break
  and saved cursors after persistent updates, including F32 bit preservation.
- Use alternating packed/boxed `scripts/bench_packed_rows.ts` runs and the
  iterator harness with matched libraries. Report fold and cursor distributions,
  compiler overhead, allocation and guest memory.

## Acceptance criteria

- [ ] Paired evidence demonstrates the read-only fold regression is closed over
      the supported shapes; a partial-width improvement is not full completion.
- [ ] The related cursor regression is measured and explained. Any unresolved
      required behavior or performance work has a bounded follow-up before final
      qualification.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending. Dependency 001 was merged as `c6654ec`.
- Validation: the initial span baseline has task 001's full compiler gate. The
  next candidate has been ported from `/tmp/blot-list-field-prototype/` to the
  working tree. Its final release and full compiler gate are running; prototype
  results are not completion evidence for that final binary.
- Comparison: `scripts/bench_list_traversal.ts` measures all widths 1–16 with
  retained Lists, fold and cursor cases, 20 warmups and 31 alternating samples
  of 16 traversals by default, with an explicit repeat override for longer
  measurements. Record widths 1–16 and tuple widths 2–16 are separate modes. It
  pins compiler, library and workload hashes, checks values/Wasm validity, and
  separates compiler allocation from guest memory. The older boxed compiler is
  pinned at SHA-256
  `150c2b032b43490434ba99c0bd91911de4bc8723fa3d4e4cf803d0f8fb88c413`. Its
  prelude/list/array/vector sources match the current library at the recorded
  starting revision. Initial samples in `build/bench/list-widths-boxed-span/`
  confirm that task 001 alone does not close the regression.
- Investigation: scalar replacement copies more fields than each temporary
  accessor needs, and packed traversal restarts tree lookup at many more leaf
  boundaries. The candidate adds a rooted private tree walk, scalar-only row
  views, a loop bounded by each leaf, and selective field copies. Crossing rows
  keep a private scalar buffer; escaping rows remain owned. Experimental
  measurements and focused tests are in `build/bench/list-field-qualified/`. A
  missing direct test import for `wasm_sroa.zig` was corrected so its focused
  ownership tests actually run. Three new execution laws cover old-row
  snapshots, tuple bindings, F32 bits, and nested collection. The prototype
  passes them, but some wider-row samples still regress slightly; final paired
  measurements are required.
- Benchmark safety: `bench:compile --allow-wasm-diff` now permits only
  cross-compiler differences. Nondeterministic, retained and restart failures
  remain fatal. A deliberately nondeterministic wrapper failed the gate with
  this flag; a stable wrapper adding the same harmless custom section passed.
  Raw evidence is in
  `build/bench/list-leaf-qualified/harness-{negative,positive}`.
- Remaining limitations: the fold and cursor gates are still open. Prototype
  successes do not establish the all-width acceptance criteria.
- Durable record: the candidate's ownership boundary and open gates are recorded
  in [LIST_TRAVERSAL.md](../zig-native/LIST_TRAVERSAL.md). Task 047 now
  explicitly owns the remaining all-width cursor performance gate; task 035
  includes the pre-existing nested-loop retention counterexample. Final
  qualification is still pending.
