# 043 — Implement ragged builders

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [042](042-specify-ragged-builders.md)
- **Originating requirements:** PLAN: Earlier programs / direct ragged
  construction. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Allocate final storage for ragged construction admitted by task 042 while
preserving ordinary builders elsewhere.

## Starting point

[exact_builder.zig](../zig-native/src/exact_builder.zig),
[eval_indexed_builder.zig](../zig-native/src/eval_indexed_builder.zig) and
[core_backend.zig](../zig-native/src/core_backend.zig) contain the current
construction paths. The approved ragged design defines legal extra passes.

## Implementation checklist

- [ ] Implement admitted sizing/counting, overflow checks, allocation and
      filling with exact logical lengths.
- [ ] Initialize reference slots safely, preserve source order and publish only
      complete immutable values.
- [ ] Keep the ordinary builder for rejected shapes and ensure failures discard
      private partial storage.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test dependent dimensions, filters, empty inner/outer ranges, all-filtered
  output and maximum/overflow counts.
- Compare results, effect/trap order and snapshots with ordinary building at
  runtime and compile time; inject allocation failures.
- Measure construction CPU, temporary allocation, peak storage and compiler
  overhead.

## Acceptance criteria

- [ ] Every admitted shape uses final storage and matches the specified
      semantics.
- [ ] Non-admitted cases retain correct ordinary behavior and measurements show
      the actual cost tradeoffs.
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
