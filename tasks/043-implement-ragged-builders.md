# 043 — Implement ragged builders

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified local implementation `2226d50`.
- **Dependencies:** [042](042-specify-ragged-builders.md)
- **Originating requirements:** PLAN: Earlier programs / direct ragged
  construction. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Allocate final storage for ragged construction admitted by task 042 while
preserving ordinary builders elsewhere.

## Starting point

[exact_builder.zig](../zig-native/src/backend/exact_builder.zig),
[eval_indexed_builder.zig](../zig-native/src/eval/eval_indexed_builder.zig) and
[core_backend.zig](../zig-native/src/backend/core_backend.zig) contain the
current construction paths. The approved ragged design defines legal extra
passes.

## Implementation checklist

- [x] Implement admitted sizing/counting, overflow checks, allocation and
      filling with exact logical lengths.
- [x] Initialize reference slots safely, preserve source order and publish only
      complete immutable values.
- [x] Keep the ordinary builder for rejected shapes and ensure failures discard
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

- [x] Every admitted shape uses final storage and matches the specified
      semantics.
- [x] Non-admitted cases retain correct ordinary behavior and measurements show
      the actual cost tradeoffs.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `2226d50` (joint 043/050 implementation); this record is separate.
- Validation: Zig 0.17.0; full native and 807 guest/client laws pass, all eight
  allocation budgets unchanged; analyzer zero across 336 Zig files. Focused
  native/OOM and executed-Wasm checks pass. Ordinary/runtime/staged parity,
  overflow/fuel, snapshots, failed allocation and retained recovery laws pass.
- Comparison: 136 runtime rows and 84 compile-phase rows compare final release
  pairs. All twelve K>=1,000 cases pass; runtime ratios 0.028–0.458. Fresh/edit
  add 0.708/0.702 ms, within the 2 ms allowance.
- Remaining limitations: Bounded admission retains ordinary builders for
  unknown/effectful/trapping shapes. Exhausted K=0 probing regresses 2.37x;
  compiler peak is unchanged.
- Durable record:
  [qualification](../zig-native/RAGGED_BUILDERS_QUALIFICATION.md); exact release
  pins, distributions and ignored evidence paths are recorded there.
