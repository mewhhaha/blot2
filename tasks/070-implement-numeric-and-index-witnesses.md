# 070 — Implement numeric and index witnesses

## Status, dependencies, and originating requirements

- **Status:** Complete — exact witness contracts, portable validation and erased
  lowering qualify in the final combined gate.
- **Dependencies:** [069](069-specify-bounded-erased-proofs.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / explicit
  witnesses. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Check and transport explicit numeric/index witnesses without forged or escaped
evidence.

## Starting point

Task 069 defines
[proof forms and acceptance examples](../zig-native/ERASED_PROOFS.md);
[types.zig](../zig-native/src/check/types.zig),
[type_evidence.zig](../zig-native/src/eval/type_evidence.zig) and
[dependency_format.zig](../zig-native/src/reuse/dependency_format.zig) need the
corresponding checked evidence representation.

## Progress

Owned witness contracts preserve exact value versions, collection lengths and
lexical scopes through source/compiled imports, portable Core and retained
edits. Independent admission rejects forged guards, recipes, rebinding,
contradictions and data-kind escapes. Both runtime tiers erase witness
representation. Local aliases preceding the first proof introduction and
imported proof aliases have unchanged semantic laws and complete
allocation-failure coverage.

The
[finite acceptance audit](../zig-native/NUMERIC_PROOFS_QUALIFICATION.md#finite-acceptance-audit-15-october-2026)
records the documented inference rules and bounded checking costs. Unknown or
exhausted optional analysis retains checks; exhausted required evidence rejects.

## Implementation checklist

- [x] Implement witness construction/use and bind proofs to exact values,
      arithmetic semantics and lexical scopes.
- [x] Validate evidence at abstraction/dependency boundaries and reject invalid
      casts, contradictions and scope escapes.
- [x] Preserve conservative checking at limits and serialize only complete
      portable proofs.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#shared-validation)
commands for focused development and the scenarios below.

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

- [x] Accepted witnesses establish exactly their documented facts across
      separate compilation.
- [x] Forged, contradictory or escaping evidence fails safely with the specified
      diagnostics.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Revision: uncommitted source based on
  `ef57ec5b99b5ea25fc5532fd2d3023108d3f10bb`; no commit or push, as requested.
  Frozen manifest SHA-256
  `3548546cb8660905de9a83922bab67270376a2b955f840f2bc7cf13fcefa53ec`.
- Validation: final Zig 0.17.0 LLVM/Fast/Safe gate passes **2,223 native laws,
  1,404 guest/client tests and 1,366 complete allocation-failure sweeps** plus
  two expected-error harness laws, with zero skips/leaks/logged errors. Full
  455-file analyzer has zero findings. Gate wall 697.812 s.
- Release executable/decompressed bundle SHA-256
  `6a83bad5560ec1a82220dc834dd366646fb8ab10370f82b26a2bcb775111ae6b`. Exact
  inputs, identities, logs, per-phase timings and post-run verification:
  `build/bench/complete-program-20261015/final-proof-repaired-gate/`.
- Comparison: finite cost measurements include 256 required consistency
  requirements in 4,902 visits/44,620 peak bytes and a shared 2,049-term graph
  in 2,817 visits/11,560 peak bytes. Twenty-five balanced whole-process pairs
  measure proof fresh/edit ratios 1.003/1.001; these are near-parity focused
  results, not release speedup claims. The ordinary Cost control remains
  byte-exact at 11,958 B/SHA-256
  1ddc5f2d50cad1760b66f7279651194cacb220d75fd747db616e06493bd133ad.
- Limits: the approved finite design retains necessary checks for unknown,
  wrapping, effectful or exhausted optional analysis. Invalid/exhausted required
  contracts reject; no arbitrary theorem solving is promised. Broader program
  performance and remote CI remain in tasks 084/093 and 082.
- Durable acceptance, erasure/import/retained/OOM controls and historical pins:
  [numeric qualification](../zig-native/NUMERIC_PROOFS_QUALIFICATION.md).
