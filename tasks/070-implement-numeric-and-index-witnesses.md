# 070 — Implement numeric and index witnesses

## Status, dependencies, and originating requirements

- **Status:** In progress — isolated foundation only; no completion is claimed.
- **Dependencies:** [069](069-specify-bounded-erased-proofs.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / explicit
  witnesses. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Check and transport explicit numeric/index witnesses without forged or escaped
evidence.

## Starting point

Task 069 defines
[proof forms and acceptance examples](../zig-native/ERASED_PROOFS.md);
[types.zig](../zig-native/src/types.zig),
[type_evidence.zig](../zig-native/src/type_evidence.zig) and
[dependency_format.zig](../zig-native/src/dependency_format.zig) need the
corresponding checked evidence representation.

## Progress

`/var/tmp/blot2-erased-proofs-070` owns an unmerged native parser, exact
value-term owner and bounded public-contract validator. Focused native laws pass
24/24, full syntax passes 41/41, and the analyzer has zero findings across 377
files. Term import and portable ownership cover every allocation failure.
Importing 256 propositions shares one 2,049-term validation and costs 2,817
charged visits. This is deterministic import work, not compiler performance
qualification.

Source patch/pins and remaining integration are recorded under
`build/bench/continuation-20261013/proof-foundation/`. Distinct proof-kind
checking, constructor execution, use/guard validation, erasure, frontend syntax
and full release qualification remain unfinished. The prototype grants no
runtime witness authority and is not included in the qualified main compiler.

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

- Apply the complete soundness/ownership/import acceptance matrix in the design;
  proof kinds cannot instantiate ordinary data polymorphism, and complete public
  result recipes cannot capture local value identities.
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
- Validation: focused prototype checks above; full compiler/guest/release
  qualification remains required.
- Comparison: pending; record baseline/candidate hashes and benchmark
  distributions, or explain why performance measurement does not apply.
- Remaining limitations: source/runtime/boundary integration listed above; all
  acceptance criteria remain open.
- Durable record: pending; link specifications/qualification outside `tasks/`
  before cleanup.
