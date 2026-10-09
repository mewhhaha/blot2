# 069 — Specify bounded erased proofs

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:**
  [056](056-implement-declarations-and-evidence-diagnostics.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 9 / erased proofs.
  Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify numeric/index witnesses, proof scopes, branch facts, erasure and bounded
checking.

## Starting point

Current array accesses retain bounds checks, even inside guards.
[types.zig](../zig-native/src/types.zig),
[type_evidence.zig](../zig-native/src/type_evidence.zig) and
[wasm_control_flow.zig](../zig-native/src/wasm_control_flow.zig) can carry
facts, but numeric proof witnesses are a new feature.

## Implementation checklist

- [ ] Define witness syntax, proposition forms, introduction/use rules and
      arithmetic semantics including U32 wrap and range bounds.
- [ ] Specify branch fact scope, joins, invalidation, contradictions and
      forbidden evidence forging/escape.
- [ ] Bound solver work and define conservative fallback, diagnostics, artifact
      transport and complete runtime erasure.
- [ ] Provide check-removal examples where necessary traps are preserved.

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

- [ ] Durable witness and branch-fact rules settle semantics, representation,
      diagnostics and limits.
- [ ] Tasks 070–071 have precise soundness, erasure and bounded-cost acceptance
      examples.
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
