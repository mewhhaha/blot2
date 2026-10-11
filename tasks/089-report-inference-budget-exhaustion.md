# 089 — Report inference budget exhaustion

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** reported on 11 October 2026 by a separate
  session developing gdev against the `b822ccf` compiler; diagnostics quality.
  Sources: that session's report.
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Exhausting the checker's per-module inference budget reports which declaration
exhausted it and where, instead of an operation failure without a position.

## Starting point

`check.zig` bounds each module's inference with `max_inference_transitions`
(1,000,000, `ModuleOptions`). A gdev station fixture exhausted it and the build
failed with `TypeLimit: Compiler operation failed` at span 0–0. The name reads
like a nesting limit, and the session spent hours locating the declaration
(`carried_strike`). The budget is per module, so test modules that concatenate
many probes reach it first, and the project server offers no way to raise it.

## Implementation checklist

- [ ] Report budget exhaustion as a positioned diagnostic that names the budget,
      its limit and the declaration being inferred.
- [ ] Decide whether the project server and CLI expose the budget, and keep it
      out of semantic cache keys if they do.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Exhaust the budget in a fixture module and check the diagnostic's code, span
  and message through the CLI and the project server.

## Acceptance criteria

- [ ] Budget exhaustion reports the declaration and a source position.
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
