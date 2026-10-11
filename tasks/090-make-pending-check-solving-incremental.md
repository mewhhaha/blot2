# 090 — Make pending-check solving incremental

## Status, dependencies, and originating requirements

- **Status:** Complete at `7589df2`.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by a separate
  session developing gdev against the `b822ccf` compiler; PLAN: Hill 5 / solver
  hot paths. Sources: that session's report, [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

The checker re-examines only pending checks that a change can affect, so module
inference is linear in the checks instead of checks × passes.

## Starting point

The same gdev fixture spent about 97% of its inference steps in
`solveFieldsFrom`, which walks every pending check from the start on each pass
and charges a step per unsolved one. About 1,800 pending checks per `app.run`
use (1,303 effect operations, 328 equalities, 173 calls) were each scanned about
31 times across 67 passes. Effect-operation checks such as `ecs.get` on a type
whose handler is not in scope cannot settle until a handler or annotation
arrives, yet are rescanned every pass. Every use of a global whose type holds
closures also re-creates those closures' pending checks: gdev's old persist kept
one closure per saved type, so each saved type added three pending effect
operations to every helper using the app (a saved section cost about 4,700
steps; walking saved types as plain data cut it to about 350). Task 010 made
`core_eval` solving incremental in the same way. This is probably also part of
the inference cost on gdev literal edits.

A public shape reproduces the growth: a module whose global record holds N
closures performing an unhandled effect operation, with N helpers each binding
that record and invoking one closure, checks in 22 ms at N = 40, 272 ms at 120
and 3.8 s at 300 (`blotc check` on 11 October 2026, after `86db5b1`).

## Implementation checklist

- [x] Index pending checks by the variables and rows that can settle them, and
      park effect operations until their effects change.
- [x] Avoid re-creating a global's closure checks at every use where the
      judgment is unchanged.
- [x] Keep diagnostics, their order and their positions identical.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Add a step-count law for many pending effect operations and closure-holding
  globals; compare diagnostics with the current checker on the public examples
  and the frontend corpus.
- Measure check time on gdev when available.

## Acceptance criteria

- [x] Inference steps grow linearly in the fixture shapes above, with laws.
- [x] Diagnostics are unchanged.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commits: `660bbe8` ("Let pending effect operations wait for their types") and
  `7589df2` ("Let open uses of settled callees wait for their types").
- Change: the checker's pending obligations run through the shared solver
  worklist. Unsettled effect operations sleep on their argument and signature
  types, and open uses of settled callees on their instance types; other kinds
  are retried each pass. Covariant row closing copies inherited membership lists
  linearly. Checker counters report `inference_steps`.
- Re-created closure checks: each use of the closure record instantiates checks
  that become that helper's own effect requirements, so the judgments are not
  unchanged across uses and are not shared; they now cost about one step each
  instead of one per pass.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 640 guest/client tests; `deno task lint:zig` reports zero findings across
  310 files. A native law and two process laws bound steps per obligation; each
  fails on its mutant or the previous compiler. Diagnostics and public results
  are unchanged.
- Comparison: closure record N = 300 checks in 1.67 s (was 3.67 s) at 1.1 steps
  per obligation; 128 late operator uses take 5,620 steps (was 72,211); gdev
  edits unchanged, cold builds about 2% faster.
- Remaining limitations: the closure record still grows about as N^2.4 from
  per-use instantiation and generalization (`schemeInto` scans every pending
  obligation); other kinds and uses of callees still being inferred are retried
  each pass.
- Durable record:
  [frontend pending checks](../zig-native/INDEXED_SOLVER.md#frontend-pending-checks-11-october-2026)
  and [checker step laws](../zig-native/tests/checker_steps.test.ts).
