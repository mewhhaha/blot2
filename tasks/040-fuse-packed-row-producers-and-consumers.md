# 040 — Fuse packed row producers and consumers

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [002](002-close-packed-list-traversal-regression.md),
  [027](027-represent-ownership-in-resolved-ir.md)
- **Originating requirements:** PLAN: Earlier programs / broader row fusion.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Broaden packed-row fusion through ordinary typed source producers and consumers.

## Starting point

[packed_layout.zig](../zig-native/src/packed_layout.zig),
[collection_edit_call.zig](../zig-native/src/collection_edit_call.zig),
[core_backend.zig](../zig-native/src/core_backend.zig) and scalar replacement
handle admitted flat rows. Task 002 qualifies traversal and task 027 provides
explicit layout/ownership facts.

## Implementation checklist

- [ ] Fuse eligible producer/consumer paths using checked shapes and use
      evidence, without recognizing library declaration names.
- [ ] Keep snapshots, logical row counts, F32 operation order, effect boundaries
      and evaluation/trap order exact.
- [ ] Retain ordinary representation for escapes, unsupported shapes and unknown
      effects; do not expose interior row pointers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test flat tuple/record pipelines at widths 1–16, crossing leaves, slices,
  saved intermediates and shared updates.
- Compare effectful callbacks, early exits, traps and reference-bearing/nested
  fallback against unfused behavior.
- Measure row boxes/copies, guest allocation and runtime plus fresh/retained
  compiler cost.

## Acceptance criteria

- [ ] Additional ordinary typed pipelines demonstrably fuse with fewer
      intermediate allocations.
- [ ] Snapshots, order, effects and fallback remain correct across source and
      dependency builds.
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
