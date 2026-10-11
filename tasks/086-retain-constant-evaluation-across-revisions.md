# 086 — Retain constant evaluation across revisions

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** discovered while qualifying task
  [023](023-narrow-literal-edit-invalidation.md); PLAN: Hill 6 / literal edits
  under 30 ms. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Re-evaluate only constants whose inputs changed; reuse every other evaluated
constant, including its serialized data, across retained revisions.

## Starting point

Task 023 keeps code and metadata of unaffected bodies, but every revision still
evaluates all constants in a new Session. A separate session profiled a
top-level scalar literal edit on the current gdev checkout with the `fbe28c8`
compiler at about 1.1 s CPU; about 60% was `core_eval.Session.prepare` →
`Session.constant` re-evaluating entry constants, dominated by
`const sandbox =
game …` (213,919 region nodes, 3,638 scopes, 276 ms alone).
Task 022 already replays graph-equal constant children of retained fragments but
re-serializes them.

## Implementation checklist

- [ ] Record each constant's exact value dependencies (source bodies, reads,
      providers, generative identities and fuel/failure outcomes).
- [ ] Reuse an evaluated value and its data only when all dependencies are
      unchanged; keep demand cells, generative values and failures exact.
- [ ] Preserve evaluation order, diagnostics, failed-revision rollback and
      fresh/retained byte equality.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit.

- Edit unrelated literals, a constant's own input, a provider and a trapping
  constant; compare executed results and bytes with fresh builds.
- Measure retained literal edits on workloads with large entry constants and on
  gdev when available.

## Acceptance criteria

- [ ] Unaffected constants are not re-evaluated across admitted edits, with
      counters and laws.
- [ ] The literal-edit target is measured or remains explicitly open for task
      [084](084-qualify-the-complete-program.md).
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
