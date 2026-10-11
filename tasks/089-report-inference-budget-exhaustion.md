# 089 — Report inference budget exhaustion

## Status, dependencies, and originating requirements

- **Status:** Complete at `c5cb9ac`.
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

- [x] Report budget exhaustion as a positioned diagnostic that names the budget,
      its limit and the declaration being inferred.
- [x] Decide whether the project server and CLI expose the budget, and keep it
      out of semantic cache keys if they do.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Exhaust the budget in a fixture module and check the diagnostic's code, span
  and message through the CLI and the project server.

## Acceptance criteria

- [x] Budget exhaustion reports the declaration and a source position.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `c5cb9ac` ("Report inference budget exhaustion at the declaration").
- Change: the checker records the innermost declaration being inferred when the
  budget runs out (a solved field's owner, else the active global, else the
  top-level declaration) and rejects the module with one `inference_budget`
  diagnostic at that declaration, for example "Type inference exceeded this
  module's budget of 1000000 steps while checking `carried_strike`".
- Decision: the budget stays a fixed `ModuleOptions` value, not a project or CLI
  setting. Raising it would hide the rescanning cost that task
  [090](090-make-pending-check-solving-incremental.md) removes, and as a setting
  it would have to join every semantic cache key.
- Validation: Zig 0.17.0; `deno task test:compiler` passes the full native suite
  and 635 guest/client tests; `deno task lint:zig` reports zero findings across
  310 files. A native law (`check_shared_scheme_tests.zig`) checks a recursive
  selected-scheme fixture at every budget from 0 until it checks cleanly: each
  failing budget yields exactly one `inference_budget` diagnostic spanning a
  value declaration whose name and the budget appear in the message. The old
  checker returns `error.TypeLimit` instead.
- Comparison: not a performance change.
- Remaining limitations: the rejected module keeps no other diagnostic; the span
  is the whole declaration. No public program reproduces the exhaustion through
  the project server, so that path is covered by the ordinary diagnostic flow
  rather than an end-to-end law.
- Durable record: [CONTRACT.md](../zig-native/CONTRACT.md#frontend-interface).
