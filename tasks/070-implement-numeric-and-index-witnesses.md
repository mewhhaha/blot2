# 070 — Implement numeric and index witnesses

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [069](069-specify-bounded-erased-proofs.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / explicit
  witnesses. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Check and transport explicit numeric/index witnesses without forged or escaped
evidence.

## Starting point

Task 069 defines proof forms; [types.zig](../zig-native/src/types.zig),
[type_evidence.zig](../zig-native/src/type_evidence.zig) and
[dependency_format.zig](../zig-native/src/dependency_format.zig) need the
corresponding checked evidence representation.

## Implementation checklist

- [ ] Implement witness construction/use and bind proofs to exact values,
      arithmetic semantics and lexical scopes.
- [ ] Validate evidence at abstraction/dependency boundaries and reject invalid
      casts, contradictions and scope escapes.
- [ ] Preserve conservative checking at limits and serialize only complete
      portable proofs.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Test valid index/length witnesses at zero, boundaries and maximum U32,
  including wrap-sensitive arithmetic.
- Reject forged constructors, contradictory claims and witnesses reused after
  incompatible rebinding.
- Run imported proof round trips, retained invalidation, OOM and bounded-work
  tests.

## Acceptance criteria

- [ ] Accepted witnesses establish exactly their documented facts across
      separate compilation.
- [ ] Forged, contradictory or escaping evidence fails safely with the specified
      diagnostics.
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
