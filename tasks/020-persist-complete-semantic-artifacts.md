# 020 — Persist complete semantic artifacts

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [019](019-serialize-the-query-table.md)
- **Originating requirements:** PLAN: Earlier programs / portable complete
  semantic artifacts. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend portable artifacts to fully represented semantic results and their
dependencies across processes.

## Starting point

Existing [backend_checkpoint.zig](../zig-native/src/backend_checkpoint.zig) and
[dependency_bundle.zig](../zig-native/src/dependency_bundle.zig) retain only
eligible subsets.
[source_value_template.zig](../zig-native/src/source_value_template.zig) and
evidence import code represent ownership-sensitive graphs; unsupported providers
and generative domains currently decline.

## Implementation checklist

- [ ] Identify and implement every graph node needed for complete semantic
      results admitted by the design, including type/effect evidence and capture
      relationships.
- [ ] Reconstruct owners, aliases, source and nominal identities on import;
      never reuse native IDs as cross-process identities.
- [ ] Record all semantic dependencies and reject unsupported or incomplete
      graphs conservatively. Document represented versus deliberately declined
      cases.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Run process-boundary round trips for higher-order, captured, nominal,
  effectful and recursive semantic results.
- Test unsupported nodes, forged identities, missing edges, corruption and OOM
  during graph remapping.
- Compare fresh, retained, dependency-loaded and restarted
  diagnostics/execution, including failed-edit correction.

## Acceptance criteria

- [ ] Every supported semantic result is represented completely and reconstructs
      valid independent ownership.
- [ ] No incomplete artifact certifies reuse; remaining unsupported cases are
      explicit and cannot be mislabeled as complete coverage.
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
