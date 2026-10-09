# 078 — Split backend state and emission

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [077](077-split-checker-responsibilities.md)
- **Originating requirements:** PLAN: Hill 14 / backend structure. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Separate backend planning, serialization, layouts and emission and split
remaining large compilation routines.

## Starting point

[core_backend.zig](../zig-native/src/core_backend.zig) contains `Generator`,
`compileWithOptions`, `serialize` and emission state. Tasks 025–028 already
establish the semantic boundary.

## Implementation checklist

- [ ] Extract planning, static data serialization, layout and resolved
      instruction emission into cohesive owners.
- [ ] Reduce oversized `Generator` state and long functions toward the
      approximately 120-line target.
- [ ] Preserve resolved-body, optimizer, relocation and cleanup boundaries with
      explicit ownership and no forwarding-only layers.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare complete Wasm, diagnostics, data layouts and code-instance counts
  across the full suite.
- Run serialization/relocation, ownership/OOM, dependency/checkpoint and
  failed-revision gates.
- Measure cold/retained CPU and allocation and document remaining justified size
  exceptions.

## Acceptance criteria

- [ ] Backend responsibilities and state owners are separated and large routines
      are substantially reduced.
- [ ] Code generation, cleanup, relocation and reuse remain equivalent.
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
