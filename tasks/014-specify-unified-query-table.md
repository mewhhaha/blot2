# 014 — Specify unified query table

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

- [ ] Define typed keys and owned values for refinement, specialization,
      principal, source-validation and executable queries, using complete
      canonical evidence.
- [ ] Specify dependency recording, exact equality after fingerprints, early
      cutoff, invalidation, failed candidates and concurrent publication.
- [ ] Keep semantic interfaces, executable behavior and evaluated values as
      distinct validity claims; unchanged types cannot certify unchanged bodies.
- [ ] Document a staged migration and portable schema through
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

- [ ] A durable design specifies APIs, representations, diagnostics,
      compatibility and acceptance examples for tasks 015–020.
- [ ] Each existing cache has a migration destination without weakening its
      validity proof.
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
