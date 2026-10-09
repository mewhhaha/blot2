# 001 — Qualify list span prototype

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
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

- [ ] Inventory and hash the prototype, baseline, compiler identities and source
      diff before changing anything. Preserve the ignored work and distinguish
      the packed main baseline from the older boxed baseline.
- [ ] Keep the corrected native test using explicit `@u32.add` intrinsics so it
      needs no implicit prelude. Verify the allocation-failure sweep also
      preserves the frozen Core stamp.
- [ ] Run the pending executed-Wasm, analyzer, differential and runtime
      measurements. Handle whole rows and leaf crossings without exposing
      interior pointers; retain reference-bearing fallback.
- [ ] If qualified, port only the reviewed source/tests and record intentional
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

- [ ] A recorded merge-or-reject decision identifies the exact source and
      executable hashes and every pending gate result.
- [ ] No incomplete execution, analyzer or measurement run is reported as a
      pass; task 002 retains the full boxed-baseline regression obligation.
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
