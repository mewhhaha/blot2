# 047 — Eliminate generic iterator state

## Status, dependencies, and originating requirements

- **Status:** In progress — packed cursors and scalar adapters including strict
  zip are qualified; window state and broader ownership cases remain open.
- **Dependencies:** [040](040-fuse-packed-row-producers-and-consumers.md),
  [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / iterator step and
  cursor allocation. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

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
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

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

- The combined working-tree implementation exposes evaluated named fold calls
  and fixes static scalar List seed ownership metadata. Optimized named
  range/map/filter/take folds allocate zero; Window folding still makes 40,954
  requests at 4,096 inputs. The all-changes-off causal byte control passes.
  Repaired private receipt fixtures retain their proof and allocation-failure
  assertions, and forced LLVM execution passes all 2,504 native laws with zero
  skips, failures, leaks or logged errors. All 37 harness checks pass. A
  complete guest scan finds four canonical-constructor regressions and one
  missing selected-query fixture. A bounded constructor-capture fallback and the
  repaired fixture pass a new native OOM/replay law and twelve executed guest
  groups, including the positive zero-allocation folds. Both analyzers pass.
  LLVM guest preflight passes all 1,588 checks and forced execution passes all
  2,505 native laws, but the full guest phase stops on a client shutdown race.
  The deterministic process regression and 88 other focused checks pass after
  the repair. The complete forced LLVM gate passes 2,505 native laws, 1,589
  guest/client checks and 37 harness checks, with zero native skips, failures,
  leaks or logged errors. Compiler cost and final combined all-width
  confirmation remain open. See the
  [evaluated-call and seed record](../zig-native/ITERATOR_STATE.md#evaluated-fold-calls-and-static-scalar-seeds-focused-qualification).
- The preselected fifteen-pair compiler CPU comparison fails at paired median
  1.059034 against the 1.05 limit; the seven-pair identity control passes. The
  failed result remains preserved. Diagnostic instruction/allocation ratios
  1.000737/1.001240 do not waive that limit. P1's closed-row cache passes three
  focused native/OOM controls and the LLVM payoff screen: 3.90% fewer simulated
  instructions, identical game Wasm and eleven work counters, requested bytes
  +0.0029%, and fifteen-pair CPU median 0.914 against current 047. Its measured
  `Store` growth is 128 bytes. Its complete guest preflight passes 1,588 checks
  and fails one unchanged allocation budget by 508 bytes. The smaller
  eight-entry version adds 64 bytes and passes the focused native/OOM controls
  and LLVM build. Its guest preflight also passes 1,588 checks and fails the
  same budget, now by 1,488 bytes. Exact allocation tracing now attributes the
  extra bytes to region-pool growth. A model reproduces all three measured
  request sequences; the four-entry successor adds 32 bytes and passes the
  focused native/OOM and size controls. Both analyzers and all 1,589 LLVM guests
  pass for that successor. N=64 requests 8,497,291 bytes, exactly the model's
  predicted 3,060 bytes over the control and below the unchanged 8,505,963
  budget. Its instruction screen passes with 3.77% fewer simulated instructions,
  identical game Wasm and eleven work counters, and requested build bytes
  +0.000715%. Its complete forced LLVM gate passes 2,506 native laws, 1,589
  guests and 37 harness checks, with zero skips, failures, leaks or logged
  errors. Guest files use concurrency one after a preserved four-file LSP
  deadline failure; the 250 ms deadline and assertions are unchanged. The
  subsequent 74-sample retained-output control fails with 16 within-binary game
  edit/revert byte mismatches, identically before and after P1. A private
  control disabling only evaluated named calls restores exact last-qualified
  bytes in seven phases. Tracing proves replay omits the serializer's shared
  value/layout entry. The repair keeps direct static materializers fresh while
  retaining ordinary constant replay and scalar evaluated-call reuse. Its public
  Array repro is red before and green after; two native/OOM/source-immutability
  laws and three guest checks pass. Both analyzers report zero findings; the
  complete LLVM gate finishes with 2,507 native passes and one failure in the
  existing positive static-closure reuse law, with zero skips, leaks or logged
  errors. The conservative fallback is unqualified; preserve the law and review
  a precise repair. The gate stops before guests; both builds and 37 harness
  checks pass. The owner requested a pause for scope/tool-efficiency review, and
  all three queued follow-ups are canceled. The current failure is saved in
  `build/bench/task047-static-sharing-v2-native-failure/`. Development resumed
  using Zig's backend. The precise successor restores only graph-proved
  value/layout sharing bindings; derived capture-free closures undergo ordinary
  current specialization and complete graph comparison. Eleven affected native
  laws, second-edit/OOM, ordering and alias controls, three both-tier guests,
  both analyzers and all seven exact original game phases pass. Evidence is in
  `build/bench/task047-static-sharing-precise-preflight/`. Final LLVM
  qualification remains required. The preselected seven identity/31 comparison
  CPU pairs and final runtime qualification have not started. Raw
  retained-output failures remain in
  `build/bench/task047-p1-four-retained-parity-failure/`.
- Current compiler baseline: local `4fda7c2` passes 2,497 executed native laws,
  1,585 guest/client checks, 37 harness checks and both analyzers at zero. This
  qualifies the existing iterator code; the remaining 047 performance/state
  requirements are still open.
- The 20 October shared-path experiment passes focused native/OOM and eight
  guest groups, then regresses selected U32 cursor runtime 2.80–2.94×. It is
  rejected outside main. The
  [current iterator record](../zig-native/ITERATOR_STATE.md#shared-traversal-path-screen-rejected)
  retains the exact artifacts. A scoped directory successor passes focused
  native/OOM and guest checks, reduces selected U32 cursor CPU ratios to
  0.223–0.267, and preserves stable roots/leases. All 62 supported width/type/
  shape cases pass against each rebuilt historical reference and current std
  separately, with no cursor regression across 186 pairs. Native compiler cost
  and LLVM/full qualification remain open. See the
  [focused directory screen](../zig-native/ITERATOR_STATE.md#scoped-directory-candidate-focused-checks-passed).
- Earlier full-gate checkpoint: `0d77afc` passes 1,701 native tests, 1,075
  guests, 1,050 complete OOM sweeps plus two expected-error harness laws, and
  375 analyzer files with zero findings. Strict zip retains zero objects;
  windows at 4,096 rows fall from 81,894 to 77,800 objects (1,277,540 to
  1,244,788 payload bytes) at release runtime ratio 0.9933; all 62 packed
  width/type outputs stay exact
  ([checkpoint](../zig-native/CONTINUATION_QUALIFICATION.md#callback-and-record-footprints-completed-window-producers-13-october-2026)).
- Since then: direct collection progress and
  [single-leaf traversal](../zig-native/ITERATOR_STATE.md#single-leaf-traversal-14-october-2026)
  (window screen 53,236 → 49,142 objects, runtime ratio 0.9526) joined the
  [qualified 14 October continuation](../zig-native/CONTINUATION_QUALIFICATION.md#qualified-continuation-14-october-2026);
  later focused cursor, frame, snapshot and closure-capture slices are pinned in
  [the iterator record](../zig-native/ITERATOR_STATE.md).
- Remaining (why the task is open): Window state and reducer captures, inner
  fold/step/cursor and semantic-buffer allocations, final release confirmation
  of the passing all-width screen, compiler cost and common qualification.
  Rejected variants remain preserved; nothing is pushed.
