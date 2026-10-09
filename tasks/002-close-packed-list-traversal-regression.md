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
- [x] The related cursor regression is measured and explained. Any unresolved
      required behavior or performance work has a bounded follow-up before final
      qualification.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: pending. Dependency 001 was merged as `c6654ec`.
- Candidate: the final release is pinned at
  `build/bench/list-sequential-qualified/blotc`, SHA-256
  `742c3e91faf3dd682d33873d8d02da13eefa0f252c62da570c3fb3b0bc068053`. Its source
  and binary hashes are in that directory's `manifest.json`.
- Validation so far: Zig 0.17.0; zero analyzer findings across 287 Zig files;
  305 differential cases (610 invocations), with identical semantic counters,
  diagnostics and teardown ownership; all 488 successful Wasm outputs validate.
  Fifty intentional Wasm differences reflect scalar replacement and traversal
  lowering. `deno task test:compiler` passed the native suite and all 595
  guest/client tests. Logs are `build/bench/list-leaf-qualified/`'s
  `compiler-gate-final.log` and `analyzer-final.log`; interrupted earlier logs
  are not passing evidence.
- Implementation: a rooted private tree walk advances through leaves without
  repeated root lookup. Checked scalar-only row uses and flat tuple bindings
  borrow scoped views; crossing rows use a private scalar buffer. The leaf loop
  avoids per-row boundary and index work, projections use checked field offsets,
  and short crossing copies have constant sizes. Escaping rows remain owned.
  Scalar replacement transfers only the fields demanded by each snapshot. The
  missing direct test import for `wasm_sroa.zig` was corrected so its focused
  ownership tests actually run.
- New execution laws cover old-row snapshots, all record/tuple widths, F32 bits,
  persistent edits during traversal, nested collection, synchronous/JSPI
  suspension, return/break cancellation and recovery after host failure. The
  final release passed these checks in the full compiler gate.
- Comparison: `scripts/bench_list_traversal.ts` measures record widths 1–16 and
  tuple widths 2–16 with 20 warmups, 31 alternating samples and an explicit
  repeat count. It pins compiler, library, script and workload hashes, checks
  values/Wasm validity and separates compiler allocation from guest memory. The
  preserved boxed compiler is SHA-256
  `150c2b032b43490434ba99c0bd91911de4bc8723fa3d4e4cf803d0f8fb88c413`; its
  prelude/list/array/vector sources match the recorded library. Task 001's
  packed comparison remains separately pinned as `pre-walk-blotc`, SHA-256
  `034d660ce38691df9a18c895ab228c4d0a76d618aa1969117d16604e06ee2833`. Earlier
  width measurements improved substantially but still missed the boxed fold
  baseline at some wide rows. The corrected aggregate-probe reports measured
  record folds at widths 14/15/16 at 1.021×/1.016×/1.044× boxed CPU. All tuple
  fold medians improved, with a small margin at width 13. All 31 row shapes use
  less committed memory than boxed rows; memory counts and every width's CPU
  ratios are in the durable record. Earlier scalar-only reports remain intact,
  but their zero memory fields mean an unavailable arena. Corrected results are
  in `boxed-record-memory/` and `boxed-tuple-memory/` under the candidate's
  qualification directory. High host load prevents treating these measurements
  as an idle-machine qualification.
- Compiler comparison: seven alternating no-cache pairs measured 981→973 ms
  fresh CPU, 1,110→1,110 ms retained population, 260→250 ms first edit and
  230→230 ms subsequent edit. No-op CPU was below the 10-ms accounting
  resolution. Requested fresh allocation was 321,239,456→321,026,930 bytes;
  semantic work counters were unchanged. A separate restart-cache batch measured
  1,064→1,054 ms cold population and 647→659 ms process restart. All
  within-compiler fresh/retained/restart byte checks passed. These loaded host
  results do not replace the qualified starting baseline or meet the final
  compiler targets.
- Runtime comparison: the original packed-row harness measured retained List
  fold CPU at 0.291→0.106 ms against task 001, with unchanged 1,441,792-byte
  committed memory. Its cursor measured 0.613→0.630 ms. All 13 general runtime
  workloads retained the same committed memory. The explicit cursor still
  allocates persistent progress and extracts rows through its cached lookup; it
  does not use the direct loop's private walk or row views. Task 047 owns the
  bounded optimization and all-width cursor gate.
- Benchmark safety: `bench:compile --allow-wasm-diff` permits only
  cross-compiler differences. Nondeterministic, retained and restart failures
  remain fatal. A deliberately nondeterministic wrapper failed the gate with
  this flag; a stable wrapper adding the same harmless custom section passed.
  Raw evidence is in
  `build/bench/list-leaf-qualified/harness-{negative,positive}`.
- Remaining limitations: the all-width fold performance gate is open. Task 047
  owns the measured cursor follow-up; direct-loop improvement does not close it.
  Task 035 owns the pre-existing nested-loop retention counterexample. Neither
  design/prototype success nor a partial-width improvement completes this task.
- Durable record: [LIST_TRAVERSAL.md](../zig-native/LIST_TRAVERSAL.md) records
  the ownership boundary, experiments and remaining qualification gates.
