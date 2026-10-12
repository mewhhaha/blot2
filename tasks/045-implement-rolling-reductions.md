# 045 — Implement rolling reductions

## Status, dependencies, and originating requirements

- **Status:** Complete — ordinary APIs, ownership and release qualification at
  `4013b10`.
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

- [x] Implement the accepted algorithm and ordinary source-facing API with the
      specified identity/inverse or fallback requirements.
- [x] Preserve numeric order, saved windows, updates, empty inputs and
      invalid-window diagnostics.
- [x] Make ownership and cleanup explicit for retained window state and
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

- [x] All specified operations and edge cases match the reference semantics.
- [x] Measured time/storage follow the promised bounds; a fast subset does not
      stand in for the full specified API.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `4013b10`.
- Validation: Zig 0.17.0; `deno task test:compiler` passes full native/OOM and
  961 guest/client tests, both tiers, all eight unchanged budgets. Analyzer
  351/zero.
- Comparison: seven alternating compiler pairs against 850793 f;31 warmed guest
  pairs, private callback counts and requested/live/committed memory. Qualified
  LLVM SHA starts 44 af 80 a 9; source/report pins are in
  `build/bench/joint-024-035-045-046/qualification-pins.json`.
- Remaining limitations: caller-provided algebra; ordinary reference/cycle
  collection costs; generic iterator elimination remains 047. No universal CPU
  or compiler speedup is claimed.
- Durable record:
  [Rolling and summary qualification](../zig-native/ROLLING_SUMMARIES_QUALIFICATION.md).
