# 014 — Specify unified query table

## Status, dependencies, and originating requirements

- **Status:** Complete — durable typed query design and migration contract
  reviewed against current ownership and validity paths.
- **Dependencies:** [008](008-canonicalize-specialization-keys.md)
- **Originating requirements:** PLAN: Hill 12 / one reuse-query model. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify one typed query table with recorded dependencies, fingerprints, early
cutoff and transactional publication.

## Starting point

[refinement_receipt.zig](../zig-native/src/refinement_receipt.zig),
[specialization_receipt.zig](../zig-native/src/specialization_receipt.zig),
[principal_inputs.zig](../zig-native/src/principal_inputs.zig),
[dependency_certificate.zig](../zig-native/src/dependency_certificate.zig) and
[revision_inputs.zig](../zig-native/src/revision_inputs.zig) implement separate
validity paths.
[declaration_dependencies.zig](../zig-native/src/declaration_dependencies.zig)
and [dependency_closure.zig](../zig-native/src/dependency_closure.zig) supply
dependency information.

## Implementation checklist

- [x] Define typed keys and owned values for refinement, specialization,
      principal, source-validation and executable queries, using complete
      canonical evidence.
- [x] Specify dependency recording, exact equality after fingerprints, early
      cutoff, invalidation, failed candidates and concurrent publication.
- [x] Keep semantic interfaces, executable behavior and evaluated values as
      distinct validity claims; unchanged types cannot certify unchanged bodies.
- [x] Document a staged migration and portable schema through
      `dependency_format`, including versioning, corruption bounds and
      conservative fallback.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Walk literal, body, capture, namespace, catalog and failed-edit examples
  through the proposed table.
- Review allocation ownership, collision handling, recursive query cycles,
  incomplete records and restart compatibility.

## Acceptance criteria

- [x] A durable design specifies APIs, representations, diagnostics,
      compatibility and acceptance examples for tasks 015–020.
- [x] Each existing cache has a migration destination without weakening its
      validity proof.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `8219cf3` (local design milestone), with reviewed task mapping and
  compatibility corrections recorded in its qualification follow-up.
- Validation: changed Markdown is formatted; local file/fragment links and
  task-015–020 migration destinations are checked. Read-only review covered
  current receipts, principal/source validation, artifact ownership and all
  acceptance walks, including open-residual versus complete-proof submodes.
- Comparison: performance measurement does not apply to this design-only task;
  compiler code and executable fixtures are unchanged by task 014.
- Remaining limitations: the shared table, migrations and portable records
  remain unimplemented tasks 015–020. The design preserves conservative
  unsupported domains and makes no new performance or complete-artifact coverage
  claim.
- Durable record: [typed reuse queries](../zig-native/QUERY_TABLE.md), including
  APIs, owned representations, diagnostics, compatibility, migration mapping and
  acceptance examples.
