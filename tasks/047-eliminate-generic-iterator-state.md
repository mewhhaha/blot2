# 047 — Eliminate generic iterator state

## Status, dependencies, and originating requirements

- **Status:** In progress — packed cursors and scalar adapters including strict
  zip are qualified; window state and broader ownership cases remain open.
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
- [ ] Close the packed List cursor regression measured in task 002. Bound
      sequential leaf traversal and row extraction without mutating published
      cursors or sharing progress between forks.

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
- Run both record and tuple modes of `scripts/bench_list_traversal.ts` against
  the pinned boxed compiler and the task 002 release, over every supported row
  width. Preserve cursor snapshots, cross-leaf rows and reference fallbacks.

## Acceptance criteria

- [ ] Eligible adapter chains show structural elimination of step/cursor
      allocations.
- [ ] Pull order, early termination, snapshots and escaping fallback remain
      correct.
- [ ] The packed cursor cost is closed over the supported widths; the direct
      loop improvement from task 002 does not count as cursor qualification.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

`121eb59` passes the full gate: 1,688 native tests, 1,066 guests, 1,036 complete
OOM sweeps plus two expected-error harness laws, and 375 analyzer files with
zero findings. Strict zip falls 45,062→0 objects and 2.899→0.030 ms at 4,096
rows; earlier range/map/filter/take/enumerate/zip/pipeline elimination remains.
All 62 packed U32/F32 record/tuple width outputs exactly match the previously
qualified all-width comparison. Windows remains at 81,894 objects; independent
runtime ratios 1.0264 and 0.9868 establish no improvement.

[The current merged record](../zig-native/CONTINUATION_QUALIFICATION.md) pins
source/binary, allocations, runtime/compiler costs and limits. The
[original record](../zig-native/ITERATOR_CONSTANTS_QUALIFICATION.md) is
preserved. Further explicit root-lifetime experiments remain isolated. No
broader completion or push is claimed.
