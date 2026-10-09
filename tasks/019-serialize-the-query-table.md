# 019 — Serialize the query table

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [018](018-migrate-executable-reuse-queries.md)
- **Originating requirements:** PLAN: Hill 12 / query archives. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Serialize complete query records through the dependency format and backend
checkpoints.

## Starting point

[dependency_format.zig](../zig-native/src/dependency_format.zig),
[backend_checkpoint.zig](../zig-native/src/backend_checkpoint.zig),
[principal_archive.zig](../zig-native/src/principal_archive.zig) and
[optimized_archive.zig](../zig-native/src/optimized_archive.zig) already encode
bounded portable candidates, with compiler identity and checksums.

## Implementation checklist

- [ ] Version typed query keys, dependency records and supported values in both
      archive paths.
- [ ] Encode owned portable data only; reject native pointers, capacities,
      unresolved solver IDs and incomplete records.
- [ ] Validate sizes, counts, indexes, exact identities and checksums before
      atomic import; preserve optional-cache fallback and explicit-import error
      behavior.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Round-trip each supported query kind across processes and compare behavior
  with fresh work.
- Exercise truncation, corrupt lengths, unknown versions, identity mismatch,
  duplicate records and missing dependencies.
- Sweep allocation failure in decoding/import/publication and verify no
  half-published query survives.

## Acceptance criteria

- [ ] Complete supported query records survive both serialization paths with
      reconstructed ownership.
- [ ] Corrupt, incompatible or incomplete inputs decline safely under the
      documented cache/import contract.
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
