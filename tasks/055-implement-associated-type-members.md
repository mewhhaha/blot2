# 055 — Implement associated type members

## Status, dependencies, and originating requirements

- **Status:** Complete — implementation `46bf8b9`, qualified 12 October 2026.
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

- [x] Add checked associated members/projections and substitute through generic
      types, rows and function evidence.
- [x] Preserve scope and identity across imports/opaque boundaries; bound
      recursive projection normalization and reject escapes.
- [x] Represent complete projection dependencies in portable interfaces and
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

- [x] Associated members and projections check and specialize consistently
      across source and artifacts.
- [x] Invalid or escaping evidence is rejected with the specified diagnostics
      and bounded inference.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `46bf8b9`; complete native suite, 914 guest/client laws, eight
  unchanged allocation budgets, 348 analyzer files/zero; Zig 0.17.0. Regenerated
  host parser, formatter and TreeSitter tooling pass.
- Standard LLVM Fast release:
  `47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`.
  Source/portable origin, row-recipe forgery, independent generic binders,
  congruent equality, nested substitution, OOM and failure/recovery/restart
  controls pass. Known abstract storage reports `missing_implementation`; open
  generic storage reports `missing_predicate`.
- Final release screens retain fresh/restart/executable parity, exact no-feature
  allocation counts/type nodes and bounded projection DAG work. No-feature
  requested-byte growth is 0.029–0.160%; retained CPU overhead and named
  allocation scopes are recorded rather than hidden.
- Limits: abstract projections have no guessed runtime layout. Implementation
  declarations, selection and member execution belong to dependent task 056.
- Durable evidence:
  [associated type qualification](../zig-native/ASSOCIATED_TYPES_QUALIFICATION.md)
  and
  [combined qualification](../zig-native/FRONTEND_OWNERSHIP_QUALIFICATION.md).
