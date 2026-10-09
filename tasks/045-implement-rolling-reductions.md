# 045 — Implement rolling reductions

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [044](044-specify-rolling-and-summary-operations.md)
- **Originating requirements:** PLAN: Earlier programs / rolling reductions.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement the specified rolling operations with bounded per-step work and
storage.

## Starting point

Existing List/Array folds and [std/iter.blot](../std/iter.blot) windows
establish ordering and persistent snapshot behavior; task 044 defines the new
APIs and admissible reducers.

## Implementation checklist

- [ ] Implement the accepted algorithm and ordinary source-facing API with the
      specified identity/inverse or fallback requirements.
- [ ] Preserve numeric order, saved windows, updates, empty inputs and
      invalid-window diagnostics.
- [ ] Make ownership and cleanup explicit for retained window state and
      reference-bearing accumulators.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare with straightforward recomputation for empty, singleton, full-width
  and over-wide windows, plus streaming updates.
- Test ordered/noncommutative reducers, U32 wrap, F32 corner cases and
  unsupported reducer fallback.
- Measure scaling across input/window sizes and verify bounded live storage
  under long streams.

## Acceptance criteria

- [ ] All specified operations and edge cases match the reference semantics.
- [ ] Measured time/storage follow the promised bounds; a fast subset does not
      stand in for the full specified API.
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
