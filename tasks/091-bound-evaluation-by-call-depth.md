# 091 — Bound compile-time evaluation by call depth

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by a separate
  session developing gdev against the `b822ccf` compiler; compile-time
  evaluation limits. Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Compile-time evaluation limits recursion by call depth (or exempts tail calls)
rather than by nested expressions, so recursive walks over long lists evaluate.

## Starting point

`core_eval.Session.expressionInner` fails with `constant_fuel` when
`Session.depth` reaches `Options.max_depth` (256), and depth grows with every
nested expression. A recursive walk over gdev's ECS registration list
(`Entry.contains`) therefore fails at about 80 registered types, far below any
real stack limit.

## Implementation checklist

- [ ] Count call depth (or do not count tail calls) for the evaluation limit,
      while keeping a structural bound on native recursion.
- [ ] Keep fuel, failures and their diagnostics deterministic and equal between
      fresh and retained builds.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Evaluate a recursive constant walk over several hundred elements, and a
  non-terminating recursion that must still fail deterministically.

## Acceptance criteria

- [ ] The recursive walk evaluates; runaway recursion still fails with a
      positioned diagnostic.
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
