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
[known_call.zig](../zig-native/src/backend/known_call.zig),
[wasm_sroa.zig](../zig-native/src/backend/wasm_sroa.zig) and
[wasm_inline.zig](../zig-native/src/backend/wasm_inline.zig) remove some
wrappers, but generic step/cursor allocations persist.
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

- Last full-gate checkpoint: `0d77afc` passes 1,701 native tests, 1,075 guests,
  1,050 complete OOM sweeps plus two expected-error harness laws, and 375
  analyzer files with zero findings. Strict zip retains zero objects; windows at
  4,096 rows fall from 81,894 to 77,800 objects (1,277,540 to 1,244,788 payload
  bytes) at release runtime ratio 0.9933; all 62 packed width/type outputs stay
  exact
  ([checkpoint](../zig-native/CONTINUATION_QUALIFICATION.md#callback-and-record-footprints-completed-window-producers-13-october-2026)).
- Since then: direct collection progress and
  [single-leaf traversal](../zig-native/ITERATOR_STATE.md#single-leaf-traversal-14-october-2026)
  (window screen 53,236 → 49,142 objects, runtime ratio 0.9526) joined the
  [qualified 14 October continuation](../zig-native/CONTINUATION_QUALIFICATION.md#qualified-continuation-14-october-2026);
  later focused cursor, frame, snapshot and closure-capture slices are pinned in
  [the iterator record](../zig-native/ITERATOR_STATE.md).
- Remaining (why the task is open): Window state and reducer captures, inner
  fold/step/cursor and semantic-buffer allocations, the all-width packed cursor
  comparison against the boxed and task 002 references, compiler cost and final
  common release qualification. Rejected variants remain preserved; nothing is
  pushed.
