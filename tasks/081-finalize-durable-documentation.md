# 081 — Finalize durable documentation

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [080](080-organize-the-source-tree.md)
- **Originating requirements:** PLAN: Hill 19; LANGUAGE_EVOLUTION and DEMANDS
  status. Sources: [PLAN.md](../PLAN.md),
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md),
  [Demand evaluation](../zig-native/DEMANDS.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Update durable language, architecture, ownership, status and library guidance to
describe completed behavior accurately.

## Starting point

[compiler/guide.md](../compiler/guide.md),
[zig-native/ARCHITECTURE.md](../zig-native/ARCHITECTURE.md),
[zig-native/CONTRACT.md](../zig-native/CONTRACT.md),
[zig-native/STATUS.md](../zig-native/STATUS.md),
[zig-native/LANGUAGE_EVOLUTION.md](../zig-native/LANGUAGE_EVOLUTION.md),
[zig-native/DEMANDS.md](../zig-native/DEMANDS.md) and
[std/PERFORMANCE.md](../std/PERFORMANCE.md) hold durable knowledge; task files
are temporary.

## Implementation checklist

- [ ] Reconcile implemented syntax/APIs, diagnostics, representations and
      ownership contracts with the final code and examples.
- [ ] Publish one qualified current measurement table with revisions/workloads
      and retain essential decisions, limitations and evidence outside `tasks/`.
- [ ] Update moved paths and distinguish completed behavior from proposals; keep
      private workloads and unnecessary historical journals out of the
      repository.

## Validation

Apply the relevant [shared validation](README.md#shared-validation) rules. Use
formatting, link, consistency and evidence checks for documentation-only
changes; run code gates only when code or build inputs change.

- Run formatting, local-link and consistency checks on documentation and
  cross-check examples against existing executable laws.
- Audit each design/qualification task for information that would be lost when
  tasks and PLAN are deleted.
- Run compiler tests only if examples or code change, or a previously unverified
  claim requires an executable check.

## Acceptance criteria

- [ ] Durable docs accurately cover the final language, runtime, architecture,
      tooling and measurements.
- [ ] Essential specifications and qualification evidence survive task 999
      without reliance on temporary task links.
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
