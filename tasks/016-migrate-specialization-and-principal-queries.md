# 016 — Migrate specialization and principal queries

## Status, dependencies, and originating requirements

- **Status:** Complete — qualified at `913a59f`.
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

- [x] Translate keys and dependency records without merging caller-selected
      evidence with principal schemes.
- [x] Preserve complete capture graphs, scalar types, nominal-cache
      absence/true/false observations and translated closed-call proofs.
- [x] Retain conservative treatment of live staged hints and static capture
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

- [x] Both selected and principal queries use the shared model while retaining
      their distinct proofs.
- [x] No stale answer survives a changed capture, identity or observed memo
      fact, and redundant indexes are gone.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `913a59f308fc58b6b3aad0197903149f16c780c4` (local compiler milestone).
- Validation: Zig 0.17.0; full LLVM `deno task test:compiler` passes native laws
  and 623 guest/client tests; `deno task lint:zig` reports zero findings across
  300 files; package check and 248 focused production tests pass. Strict
  626-case six-policy diagnostics/Wasm parity and
  executed/retained/checkpoint/OOM laws pass, including additional
  empty/nonempty principal probes.
- Comparison: immutable task-015/016 binaries and 413 final source/test inputs
  are pinned in the durable record. Fifteen-pair fresh measurements cover 86
  workloads; seven-pair native/CLI retained/restart measurements cover 13. CPU
  is near neutral overall; small principal records add bounded storage and some
  small controls cost more. Full distributions, counters, table storage,
  retained plateaus and zero teardown are recorded.
- Remaining limitations: per-owner bounds do not claim an RSS/global allocation
  reduction. Local open residual storage is law-qualified but has no positive
  public retained-storage sample. Reader storage is omitted by the CLI; restart
  hits and total allocations are measured. Query serialization/portable semantic
  expansion remain tasks 019/020; historical boxed/private gdev gates remain
  open under 002/084.
- Durable record:
  [specialization/principal query specification and
  qualification](../zig-native/SPECIALIZATION_PRINCIPAL_QUERIES.md), including
  tracked distribution CSVs, source/pin maps and the exact native probe.
