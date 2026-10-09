# 001 — Qualify list span prototype

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified and merged locally as `c6654ec`.
- **Dependencies:** None.
- **Originating requirements:** PLAN: Earlier programs still open / Collections.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Qualify the existing ignored List span prototype and either merge the bounded
change or reject it with reproducible evidence.

## Starting point

The prototype is in `build/experiments/list-span-source/`. Its
`Emitter.readListRow` accepts an optional span end and direct loops pass that
bound. Changes also include `src/collection_tests.zig` and
`tests/list_span_execution.test.ts` in that checkout. The supplied continuation
records a successful experimental release and corrected native
allocation-failure test; these are prior results, not a completed qualification.
See the exact paths and binary hashes in
[README.md](README.md#list-span-continuation).

## Implementation checklist

- [x] Inventory and hash the prototype, baseline, compiler identities and source
      diff before changing anything. Preserve the ignored work and distinguish
      the packed main baseline from the older boxed baseline.
- [x] Keep the corrected native test using explicit `@u32.add` intrinsics so it
      needs no implicit prelude. Verify the allocation-failure sweep also
      preserves the frozen Core stamp.
- [x] Run the pending executed-Wasm, analyzer, differential and runtime
      measurements. Handle whole rows and leaf crossings without exposing
      interior pointers; retain reference-bearing fallback.
- [x] If qualified, port only the reviewed source/tests and record intentional
      generated-code changes. If rejected, retain the evidence and describe what
      task 002 must solve; rejection does not close the traversal regression.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run the prototype native filter `packed List span emission`, then its
  `list_span_execution.test.ts`, packed-row/revision, cursor and collection
  execution coverage, followed by the full compiler and analyzer gates for any
  proposed merge.
- Exercise widths 1–16 around 248-word leaf boundaries, zero rows, nested
  traversal, early exits and preserved snapshots. Compare values, diagnostics,
  effects and recovery against main.
- Run paired `scripts/bench_packed_rows.ts` and `scripts/bench_runtime_costs.ts`
  measurements plus `bench:compile`; separate guest runtime/memory from
  fresh/retained compiler CPU and allocation. Preserve same-compiler
  fresh/retained byte equality.

## Acceptance criteria

- [x] A recorded merge-or-reject decision identifies the exact source and
      executable hashes and every pending gate result.
- [x] No incomplete execution, analyzer or measurement run is reported as a
      pass; task 002 retains the full boxed-baseline regression obligation.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `c6654ec3f7d8171c2530809849366997ed925a2c` — Qualify packed List loop
  span reads and preserve allocation laws.
- Validation: Zig 0.17.0; `deno task test:compiler` passed the native suite and
  all 590 guest/client tests. `deno task lint:zig` checked 285 files with zero
  findings. The focused native filter passed 16 tests, including the
  immutable-Core allocation-failure sweep. All 17 focused guest tests passed.
  Differential compilation had no semantic mismatches across 305 cases; all 488
  successful Wasm modules validate. Both versions of the changed guide module
  execute identically.
- Comparison: 25 alternating packed-row samples measured the retained List fold
  at 0.401/0.303 ms CPU with equal memory. All 13 runtime-cost workloads passed
  with identical Wasm. Two seven-pair gdev batches covered disabled persistence
  and cache population/restart separately. Fresh CPU was 938/940 ms, population
  1,070/1,070 ms, first edit 240/240 ms and later edit 220/220 ms in this
  heavily loaded run. Allocation and deterministic work counters matched; every
  required fresh/retained/restart byte comparison passed. No compiler speedup is
  claimed.
- Decision: merge the bounded direct-loop check improvement. The exact baseline,
  prototype and production hashes are in the durable record.
- Remaining limitations: task 002 retains the all-width regression against the
  older boxed baseline and the cursor investigation. Its initial all-width probe
  confirms the broader regression remains. This change affects direct packed
  List loops and does not change cursor emission.
- Durable record: [LIST_TRAVERSAL.md](../zig-native/LIST_TRAVERSAL.md) preserves
  identities, commands/harnesses, semantic checks, measurements and limits. Raw
  logs and samples remain in ignored `build/bench/list-span-qualified/`.
