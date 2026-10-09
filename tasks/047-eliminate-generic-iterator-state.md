# 047 — Eliminate generic iterator state

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [040](040-fuse-packed-row-producers-and-consumers.md),
  [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / iterator step and
  cursor allocation. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Eliminate eligible generic iterator step and cursor allocations across adapters
and loops.

## Starting point

[std/iter.blot](../std/iter.blot),
[known_call.zig](../zig-native/src/known_call.zig),
[wasm_sroa.zig](../zig-native/src/wasm_sroa.zig) and
[wasm_inline.zig](../zig-native/src/wasm_inline.zig) remove some wrappers, but
generic step/cursor allocations persist.
[tests/iterator_execution.test.ts](../zig-native/tests/iterator_execution.test.ts)
pins pull semantics.

## Implementation checklist

- [ ] Use resolved call/layout/ownership facts to keep nonescaping adapter state
      and steps in locals.
- [ ] Preserve one cursor per iterator creation, independent forks, written pull
      order and early exit.
- [ ] Retain ordinary heap state for escaping/unknown uses and preserve
      effectful iter/next behavior.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test map/filter/take/take_while/enumerate/zip/zip_strict/windows pipelines,
  especially take 0 and a right side ending first.
- Compare nested loops, independent cursors, saved windows, breaks/returns and
  effect traces with fallback.
- Use `scripts/bench_iterators.ts` to measure step/cursor allocation, runtime
  and compiler overhead separately.

## Acceptance criteria

- [ ] Eligible adapter chains show structural elimination of step/cursor
      allocations.
- [ ] Pull order, early termination, snapshots and escaping fallback remain
      correct.
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
