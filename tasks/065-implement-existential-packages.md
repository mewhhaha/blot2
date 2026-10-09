# 065 — Implement existential packages

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [064](064-check-higher-rank-types-and-skolems.md),
  [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / existential
  packages. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement packing, unpacking, evidence passing, specialization and heterogeneous
package use across portable interfaces.

## Starting point

Task 064 provides skolem checking; task 020 portable semantic graphs.
[core.zig](../zig-native/src/core.zig),
[specialization.zig](../zig-native/src/specialization.zig) and runtime layouts
must represent the package design from task 063.

## Implementation checklist

- [ ] Check package creation against its abstract interface and introduce scoped
      abstract identities on unpacking.
- [ ] Carry the required operations/evidence into specialization without
      exposing hidden representation.
- [ ] Support heterogeneous collections and artifact transport with correct
      capture/resource ownership.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Pack different implementations behind one interface, store them together and
  invoke their permitted operations.
- Reject representation access, wrong evidence and hidden-type escape through
  results/captures.
- Round-trip source/dependency/checkpoint paths and verify retained edits,
  failure recovery and package destruction.

## Acceptance criteria

- [ ] Packages preserve abstraction and evidence through heterogeneous use and
      separate compilation.
- [ ] Packing/unpacking diagnostics, identity and ownership satisfy the
      specified laws.
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
