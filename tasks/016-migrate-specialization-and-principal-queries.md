# 016 — Migrate specialization and principal queries

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [015](015-migrate-refinement-queries.md)
- **Originating requirements:** PLAN: Hill 12 / specialization and principal
  queries. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Migrate specialization and principal-query reuse to the common table with
complete capture and evidence validation.

## Starting point

[specialization_receipt.zig](../zig-native/src/specialization_receipt.zig),
[principal_reuse_gate.zig](../zig-native/src/principal_reuse_gate.zig),
[principal_evidence_reuse.zig](../zig-native/src/principal_evidence_reuse.zig)
and [principal_archive.zig](../zig-native/src/principal_archive.zig) retain
selected and principal answers under different checks.

## Implementation checklist

- [ ] Translate keys and dependency records without merging caller-selected
      evidence with principal schemes.
- [ ] Preserve complete capture graphs, scalar types, nominal-cache
      absence/true/false observations and translated closed-call proofs.
- [ ] Retain conservative treatment of live staged hints and static capture
      jobs; remove old indexes only after all admission paths pass parity.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run principal reuse, static capture, source-template and specialized closure
  tests across same-type/different-value edits.
- Round-trip imported evidence and checkpoints; test failed graph import, OOM
  during reservation and recovery across repeated revisions.
- Compare query counts, CPU and retained memory with the preceding
  implementation.

## Acceptance criteria

- [ ] Both selected and principal queries use the shared model while retaining
      their distinct proofs.
- [ ] No stale answer survives a changed capture, identity or observed memo
      fact, and redundant indexes are gone.
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
