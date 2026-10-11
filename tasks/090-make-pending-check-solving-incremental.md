# 090 — Make pending-check solving incremental

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
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

## Implementation checklist

- [ ] Index pending checks by the variables and rows that can settle them, and
      park effect operations until their effects change.
- [ ] Avoid re-creating a global's closure checks at every use where the
      judgment is unchanged.
- [ ] Keep diagnostics, their order and their positions identical.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Add a step-count law for many pending effect operations and closure-holding
  globals; compare diagnostics with the current checker on the public examples
  and the frontend corpus.
- Measure check time on gdev when available.

## Acceptance criteria

- [ ] Inference steps grow linearly in the fixture shapes above, with laws.
- [ ] Diagnostics are unchanged.
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
