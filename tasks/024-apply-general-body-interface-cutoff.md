# 024 — Apply general body interface cutoff

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [023](023-narrow-literal-edit-invalidation.md)
- **Originating requirements:** PLAN: Hill 6 / general body edits under 100 ms.
  Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Recheck changed bodies individually and stop semantic propagation when their
interfaces remain unchanged.

## Starting point

[module_frontend_cutoff.zig](../zig-native/src/module_frontend_cutoff.zig) and
refinement receipts provide limited cutoffs. The unified queries distinguish
semantic dependencies from executable and staging reads.

## Implementation checklist

- [ ] Compare complete public body interfaces after individual rechecking,
      including residual predicates, effects, captures and identities.
- [ ] Stop semantic propagation only on exact interface equality; rebuild
      executable consumers of changed bodies, selected evidence, captures or
      staged inputs.
- [ ] Preserve failed-revision rollback and dependencies across imports,
      namespaces and serialized artifacts.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Edit bodies with unchanged types but changed values, effect traces, demand
  control flow or lifetime summaries; executable callers must update.
- Change signatures, predicates and captures and verify semantic propagation
  resumes; test imports, dependencies, restart and correction.
- Measure first/later general body edit CPU, reused regions and metadata with
  fresh/retained equality.

## Acceptance criteria

- [ ] Unchanged interfaces stop semantic propagation without hiding executable
      or staged changes.
- [ ] The under-100-ms body-edit target is measured or remains an explicit
      unfinished performance gate.
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
