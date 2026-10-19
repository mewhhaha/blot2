# 109 — Restore Array loop throughput

## Status, dependencies, and originating requirements

- **Status:** Complete — implementation `3cf6de1` passes the current full gate;
  the original issue repro and all four Ink probes pass current-host timing,
  witness and memory qualification on 19 October 2026.
- **Dependencies:** None.
- **Originating requirements:** Reported from Ink as
  [issue #9](https://github.com/mewhhaha/blot2/issues/9): a guarded insertion
  sort ran about 21 times slower than on Ink's pinned compiler `86a527b`.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

In-place Array loops run at the pinned compiler's speed while checked ownership
stays sound: no tracing fallback, no pointer guesses, and the `break_writes`
copy fix stays linear.

## Starting point

Two kinds of per-iteration work were statically removable:

- Every iteration opened and closed a journal frame and republished each
  reference carry. Every carry assignment also stored into the carry's stable
  slot, even when the value was the same pointer. Both cleanup passes,
  `root_borrows.zig` and `empty_root_scopes.zig`, skipped any function whose
  result role was not scalar. `root_borrows.zig` also gave up on more than 256
  locals or 4096 instructions, on any call or memory write, and on component
  seeds that conflicted. The result-role gate had no recorded reason: both
  passes landed in one integration commit (`23a934f`) for scalar row folds.
- Numeric element writes called the checked `store_word` helper, which looks up
  the header layout bitmap at run time. `arrayFill` already used annotated
  scalar stores.

## Implementation checklist

- [x] Store numeric Array elements with `ir.scalarStore`-annotated stores for
      index updates and `Array.set`, keeping bounds checks
      (`zig-native/src/backend/backend_emission.zig`).
- [x] Rewrite `root_borrows.zig` as a region proof with a forward must-copy
      dataflow. It removes duplicate stores into a slot that keeps one value,
      the lexical publications of that value, and other slots that only ever
      hold it. It ignores the result role, accepts ordinary calls and object
      writes, keeps only the start-dominated part of the region, and scales to
      8192 locals and 65536 instructions under a work budget.
- [x] Let `empty_root_scopes.zig` accept checked scalar stores, traps,
      journal-neutral leaf calls and nested frames it has already proved empty,
      for any result role, and ignore dead predecessors.
- [x] Static laws: IR boundaries and in-place carry laws in `root_borrows.zig`,
      nesting/trap/leaf-call laws in `empty_root_scopes.zig`, and source laws in
      `zig-native/src/backend/persistent_roots_tests.zig`. The source laws check
      for no loop journal calls through retained, checkpoint, replay and OOM
      runs, and check that shared, fresh and owning-element loops keep their
      journal calls.
- [x] Executed-Wasm law in
      `zig-native/tests/persistent_roots_execution.test.ts`. It covers an
      insertion sort with breaks, an Array-of-references carry repeated 3,000
      times with stable memory, an aliasing snapshot that must copy, and a
      throughput guard: journal retains per call must not grow with the
      iteration count.
- [x] Document the rules in `zig-native/PERSISTENT_ROOTS.md`,
      `zig-native/SHARED_RC.md` and `zig-native/CONTRACT.md`.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). Run
`deno task test:compiler` and `deno task lint:zig` before the local milestone
commit. Time the issue repro and Ink's four compiler-probe benches on old, main
and patched release builds with the same harness.

## Acceptance criteria

- [x] The issue repro and Ink's `inline_writes`, `unsigned_sort` and
      `pathfinding` at 2000 run within 1.5 times the pinned compiler, and
      `break_writes` stays linear.
- [x] Loops whose carries are shared, replaced or stored as owning elements keep
      their journal operations, and module admission stays complete.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Recording milestone: `237a5065ecd8a5debc406ef77a79d4a489c37b9b` on local
  `main`; no push. The final harness passes Deno type, format and lint checks.
- Current qualification: compiler source milestone
  `e29dd0d2c6faa2ad16a39e4a06ef254cede3ff2c`, with unchanged native inputs and
  the executed 2,470-native/1,556-guest/37-harness gate and zero CI lint
  findings. The original `guarded_sum(256)` runs at 1.107 times `86a527b`; Ink's
  three required probes are at 1.082, 1.089 and 0.008. `break_writes` scales by
  1.821 when count doubles. All witnesses and warmed memory checks pass over
  60,480 calls. The
  [durable current record](../zig-native/PERSISTENT_ROOTS.md#current-array-throughput-qualification-19-october-2026)
  pins source archives, binaries, harness, distributions and limitations.

### Historical implementation qualification, 17 October 2026

- Validation: in the implementation worktree `deno task test:compiler` passed
  2,365 native laws with zero leaks, 1,517 guest, 48 smoke and 28 harness tests
  in 19 min 37 s; lint reported zero findings across 487 Zig files; Ink's suite
  passed 362 of 362 tests on the gated build. On pre-fix main `48eda0a` the new
  executed law fails its throughput guard: journal retains per call are 8, 2,416
  and 133,298 at counts 2, 64 and 512. See the dated record in
  [PERSISTENT_ROOTS.md](../zig-native/PERSISTENT_ROOTS.md#array-loop-throughput-17-october-2026).
- Comparison: median release-guest times, in ms, after 400 warm-up rounds,
  paired on one host:

  | Bench                   | `86a527b` | main `48eda0a` | Patched |
  | ----------------------- | --------: | -------------: | ------: |
  | repro `guarded_sum` 256 |     0.116 |          1.821 |   0.134 |
  | `inline_writes` 2000    |    0.0063 |         0.0490 |  0.0053 |
  | `break_writes` 2000     |    0.8273 |         0.0542 |  0.0058 |
  | `unsigned_sort` 2000    |    0.0677 |         0.6434 |  0.0711 |
  | `pathfinding` 2000      |    0.2386 |         3.1595 |  0.1799 |

- Remaining limitations: function frames, the opening carry store and
  reservation, and each loop's collector safe point stay. Frames of iterations
  that allocate, or that hold a copy-path edit, keep their journal work. Some
  sources still take the copy path: an `if`/`else` form of the sort that writes
  `ids[j - 1] := ids[j]` copies on both main and patched builds. That is an
  `ownsArrayUpdate` limitation outside this task.
- Durable record:
  [PERSISTENT_ROOTS.md](../zig-native/PERSISTENT_ROOTS.md#counted-owners).
