# 034 — Reclaim cyclic ownership

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [033](033-own-suspended-effects-and-cancellation.md)
- **Originating requirements:** PLAN: Earlier programs / runtime cycles.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement the cycle-reclamation strategy specified in task 030.

## Starting point

[tests/arena_gc_execution.test.ts](../zig-native/tests/arena_gc_execution.test.ts)
contains the executed State/closure/demand counterexample. Typed RC and
suspended roots now expose the complete graph needed for cycle handling.

## Implementation checklist

- [ ] Implement candidate discovery, root/reachability treatment and reclamation
      using the agreed strategy.
- [ ] Retain reachable cycles and their strong memoized results; changing State
      may remove a root but must not mutate the cached value.
- [ ] Reclaim discarded cycles including shared subgraphs and suspended/canceled
      objects without interfering with ordinary RC destruction.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run the existing cycle law unchanged, plus multiple cycles sharing children,
  self-cycles and cycles rooted through suspended values.
- Drop roots in different orders, clear/repopulate State and force cached
  results before and after collection opportunities.
- Run long loops creating/discarding cycles and measure bounded live memory and
  reclamation work.

## Acceptance criteria

- [ ] Reachable cycle behavior is unchanged, including strong demand memo
      results after State writes.
- [ ] Discarded cycles reclaim under sustained execution without leaks, double
      frees or invalid suspension state.
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
