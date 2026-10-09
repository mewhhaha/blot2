# 015 — Migrate refinement queries

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [014](014-specify-unified-query-table.md)
- **Originating requirements:** PLAN: Hill 12 / refinement-first migration.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Move refinement receipts and their indexes into the common query model.

## Starting point

[refinement_receipt.zig](../zig-native/src/refinement_receipt.zig),
[completed_specialization_query.zig](../zig-native/src/completed_specialization_query.zig)
and [shared_query_gate.zig](../zig-native/src/shared_query_gate.zig) hold
current refinement lookups;
[source_value_template_tests.zig](../zig-native/src/source_value_template_tests.zig)
exercises dynamic facts and publication.

## Implementation checklist

- [ ] Implement the task 014 query primitives and migrate refinement keys,
      dependencies, results and first-match indexing.
- [ ] Preserve dynamic scalar/plain-data facts, imported evidence, expected
      shapes, seeds and exact source admission.
- [ ] Check collisions with full equality and publish only complete owned
      results; retire replaced refinement indexes after parity.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run refinement/source-template laws covering multiple matching candidates,
  collision buckets, changed catalogs and source-ID remapping.
- Compare fresh/retained output, repeated revisions, failed edits,
  dependency/checkpoint round trips and allocation-failure publication.
- Measure lookup work and retained storage to ensure the common table does not
  add unbounded indexing overhead.

## Acceptance criteria

- [ ] Refinement results flow through the common table with the same first-match
      and validity behavior.
- [ ] Superseded refinement indexes are removed after parity, and no dynamic
      fact or imported evidence check is lost.
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
