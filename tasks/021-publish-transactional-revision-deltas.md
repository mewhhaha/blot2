# 021 — Publish transactional revision deltas

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [017](017-unify-source-and-revision-validation.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** PLAN: Hill 6 and earlier semantic compilation /
  revision deltas. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Publish changed revision metadata as transactional deltas while reusing
unchanged immutable data.

## Starting point

[retained_revision.zig](../zig-native/src/retained_revision.zig),
[project.zig](../zig-native/src/project.zig),
[revision_inputs.zig](../zig-native/src/revision_inputs.zig) and
[frozen_dependency.zig](../zig-native/src/frozen_dependency.zig) preserve
last-good revisions but still reconstruct metadata on edits.

## Implementation checklist

- [ ] Separate unchanged immutable metadata from candidate-owned changes and
      commit the delta only after all required work succeeds.
- [ ] Share owners with explicit lifetime rules and bounded compaction; avoid an
      unbounded chain of previous revisions.
- [ ] Release failed candidate allocations without touching prior source bytes,
      query records, exports or checkpoint eligibility.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Repeat literal/body/import edits, no-ops and failed corrections across many
  revisions and compare fresh results.
- Inject failure at delta preparation, import and publication; verify the old
  revision and its exported checkpoint remain usable.
- Measure metadata copies, retained capacity and peak/cumulative allocation
  separately from semantic and emission work.

## Acceptance criteria

- [ ] Unchanged metadata is reused and only complete deltas become visible.
- [ ] Repeated edits keep ownership bounded; failed edits/OOM preserve the
      previous revision exactly.
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
