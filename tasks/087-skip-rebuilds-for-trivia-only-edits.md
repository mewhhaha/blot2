# 087 — Skip rebuilds for trivia-only edits

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** none.
- **Originating requirements:** discovered while qualifying task
  [085](085-gate-principal-graph-sharing-on-payoff.md); PLAN: Hill 6 / cheap
  edits. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

An edit that changes only comments, blank lines or other trivia publishes the
previous revision's output and semantic results with updated source positions
instead of rebuilding.

## Starting point

A separate session measured gdev's dev loop with the task-024 compiler: a
comment-only edit in one module costs the full 1044–1077 ms (`generate_us`
735–768 ms, `reused_output: false`) and emits byte-identical Wasm. Retained
revisions already reuse output for unchanged sources; any byte change, including
trivia, currently invalidates the module's syntax, Core spans and everything
downstream.

## Implementation checklist

- [ ] Decide which source changes are trivia (comments, whitespace that does not
      change layout-sensitive structure) and prove the token stream otherwise
      identical, including indentation-significant blocks.
- [ ] Reuse the previous output and retained artifacts while updating every
      source position that diagnostics, debug names and later edits read.
- [ ] Keep diagnostics, failed-revision rollback and fresh/retained equality
      exact.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Comment, blank-line and indentation edits, including ones that do change
  layout; a later real edit and a later error must report current positions.
- Measure trivia-only and following edits against fresh builds.

## Acceptance criteria

- [ ] Trivia-only edits avoid backend work while later diagnostics carry the
      current positions.
- [ ] Layout-changing whitespace still rebuilds.
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
