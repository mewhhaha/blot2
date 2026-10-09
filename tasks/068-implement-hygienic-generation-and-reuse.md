# 068 — Implement hygienic generation and reuse

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [067](067-implement-typed-code-and-descriptors.md),
  [024](024-apply-general-body-interface-cutoff.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 8 / hygiene and
  staged dependencies. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Preserve binding identity and exact tracked staged inputs through generation,
reuse and failed revisions.

## Starting point

Task 067 supplies typed code and task 024 body cutoffs.
[symbols.zig](../zig-native/src/symbols.zig),
[declaration_dependencies.zig](../zig-native/src/declaration_dependencies.zig)
and [compiler/assets.ts](../compiler/assets.ts) provide identity and
tracked-input foundations.

## Implementation checklist

- [ ] Generate declarations with hygienic lexical identities across shadowing,
      imports and multiple expansion sites.
- [ ] Record every code/descriptor/input dependency and include generated body
      semantics in executable invalidation.
- [ ] Reuse only complete generated results with matching inputs; preserve
      last-good artifacts on generation failure.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Generate same-spelled locals at different sites, capture intended outer
  bindings and compose imported generators.
- Edit a tracked input or generator body with an unchanged result type and
  verify affected callers rebuild.
- Compare fresh/retained/restart artifacts, failed-edit correction, OOM and
  unchanged-input reuse work.

## Acceptance criteria

- [ ] Generated code preserves intended bindings without accidental capture.
- [ ] Exact staging inputs govern reuse and every failed generation leaves the
      previous revision usable.
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
