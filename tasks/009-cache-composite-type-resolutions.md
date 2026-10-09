# 009 — Cache composite type resolutions

## Status, dependencies, and originating requirements

- **Status:** In progress — an isolated dependency-certificate prototype is
  being tested; no production change or completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** PLAN: Hill 5 / solver hot paths. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend dependency-aware resolution caching from variables to composite types
without changing chronological substitution semantics.

## Starting point

[types.zig](../zig-native/src/types.zig) has node-local variable certificates;
[resolution_cache.zig](../zig-native/src/resolution_cache.zig) and
[epoch_resolution_cache.zig](../zig-native/src/epoch_resolution_cache.zig)
support generation checks. Current composite resolution still loses reuse across
unrelated writes; occurs-DAG traversal is already complete.

## Implementation checklist

- [ ] Record the type/effect dependencies of composite answers and validate only
      relevant writes within the correct chronological window.
- [ ] Revoke cached answers on rollback, physical edits, owner/depth changes and
      saturated clocks; distinguish fresh variable/effect identities.
- [ ] Keep certificate metadata solver-local and ensure failed cache growth
      leaves existing answers intact.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare cached resolution with ordinary traversal over generated histories,
  historical windows, unrelated writes, aliases and shared DAGs.
- Exercise rollback/recycled IDs, physical type and effect mutation, clock
  saturation and allocation failures.
- Measure resolve visits, cold CPU and requested allocation; do not revive the
  previously rejected closed-cache prototype without new evidence.

## Acceptance criteria

- [ ] Composite cache hits survive unrelated writes and every invalidating
      mutation produces the same answer as ordinary traversal.
- [ ] Ownership and OOM laws pass and paired measurements demonstrate the
      retained cache is justified.
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
- Isolated work: `/tmp/blot-composite-cache-prototype/` tests bounded
  certificates that retain unresolved type/effect frontiers and revoke future
  variable views when the shared clock advances. It starts from current main,
  not the previously rejected closed-cache implementation. No performance or
  correctness result is claimed before qualification completes.
