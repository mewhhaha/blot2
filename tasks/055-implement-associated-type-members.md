# 055 — Implement associated type members

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [054](054-specify-associated-types-and-implementations.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 3 / associated
  type members. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Implement associated type checking, substitution, projection, imports and
specialization.

## Starting point

[types.zig](../zig-native/src/types.zig),
[check.zig](../zig-native/src/check.zig),
[type_evidence.zig](../zig-native/src/type_evidence.zig) and
[specialization.zig](../zig-native/src/specialization.zig) carry current
contract evidence. Task 054 defines associated members and projection syntax.

## Implementation checklist

- [ ] Add checked associated members/projections and substitute through generic
      types, rows and function evidence.
- [ ] Preserve scope and identity across imports/opaque boundaries; bound
      recursive projection normalization and reject escapes.
- [ ] Represent complete projection dependencies in portable interfaces and
      specialization keys.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test nested/generic projections, multiple same-named members, imported
  contracts and type equality at uses.
- Reject missing members, mismatched projections, cycles beyond limits and
  escaped local type variables.
- Round-trip dependencies/checkpoints and exercise failed edits, OOM and bounded
  work.

## Acceptance criteria

- [ ] Associated members and projections check and specialize consistently
      across source and artifacts.
- [ ] Invalid or escaping evidence is rejected with the specified diagnostics
      and bounded inference.
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
