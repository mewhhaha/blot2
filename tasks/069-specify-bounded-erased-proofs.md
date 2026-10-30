# 069 — Specify bounded erased proofs

## Status, dependencies, and originating requirements

- **Status:** Complete — durable design and acceptance matrix published.
- **Dependencies:**
  [056](056-implement-declarations-and-evidence-diagnostics.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / erased proofs.
  Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify numeric/index witnesses, proof scopes, branch facts, erasure and bounded
checking.

## Starting point

Current array accesses retain bounds checks, even inside guards.
[types.zig](../zig-native/src/check/types.zig),
[type_evidence.zig](../zig-native/src/eval/type_evidence.zig) and
[wasm_control_flow.zig](../zig-native/src/backend/wasm_control_flow.zig) can
carry facts, but numeric proof witnesses are a new feature.

## Implementation checklist

- [x] Define witness syntax, proposition forms, introduction/use rules and
      arithmetic semantics including U32 wrap and range bounds.
- [x] Specify branch fact scope, joins, invalidation, contradictions and
      forbidden evidence forging/escape.
- [x] Bound solver work and define conservative fallback, diagnostics, artifact
      transport and complete runtime erasure.
- [x] Provide check-removal examples where necessary traps are preserved.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review zero/maximum lengths, overflow, conflicting assumptions, nested guards
  and separate-compilation witnesses.
- Compare proven versus unproven accesses and facts that cease to hold after a
  new binding version.

## Acceptance criteria

- [x] Durable witness and branch-fact rules settle semantics, representation,
      diagnostics and limits.
- [x] Tasks 070–071 have precise soundness, erasure and bounded-cost acceptance
      examples.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Design follows qualified implementation declarations at `10fab46`; the local
  documentation milestone contains this record and the durable specification.
- Validation: `deno fmt --no-config --check` on changed Markdown, local link
  audit, and review against the current guide, ownership contract and scoped
  value-binder design. No compiler source or executable fixture changes.
- Comparison: no performance claim; tasks 070–071 must measure checking cost,
  erasure and retained invalidation on the specified positive/negative matrix.
- Remaining limitations: the proof syntax is a proposal until 070–071 implement
  it; no proof acceptance or runtime check elimination is claimed here.
- Durable record: [bounded erased proofs](../zig-native/ERASED_PROOFS.md).
