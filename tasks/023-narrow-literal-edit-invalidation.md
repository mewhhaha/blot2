# 023 — Narrow literal edit invalidation

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [022](022-retain-constants-and-relocatable-data.md)
- **Originating requirements:** PLAN: Hill 6 / literal edits under 30 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Re-evaluate only affected constants and update changed data, instructions and
relocations after literal edits.

## Starting point

The baseline gdev literal edit takes 150/140 ms and can rebuild the seed.
[retained_revision.zig](../zig-native/src/retained_revision.zig),
[core_backend.zig](../zig-native/src/core_backend.zig) and query dependency
records now have the foundations for narrower invalidation.

## Implementation checklist

- [ ] Trace a literal change through exact staged consumers, data and executable
      dependencies; preserve unrelated bodies and metadata.
- [ ] Patch candidate-owned data/instructions/relocations through normal
      compiler APIs, never generated output as a workaround.
- [ ] Retain conservative rebuilds when value-dependent identities or
      unsupported graphs prevent a proof.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit and revert scalar, aggregate and captured literals, including the frozen
  gdev `floor_half_extent` edit.
- Compare fresh/retained bytes, constants and execution after dependency/restart
  loading, failed edits and repeated revisions.
- Record rebuilt bodies, metadata copies, first/subsequent edit CPU and
  allocation; preserve no-op behavior.

## Acceptance criteria

- [ ] Counters and artifacts show unrelated bodies and metadata remain reusable
      across admitted literal edits.
- [ ] The under-30-ms literal target is demonstrated in paired measurements or
      remains explicitly open for task 084/follow-up work.
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
