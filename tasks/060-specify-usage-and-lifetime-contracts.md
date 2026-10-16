# 060 — Specify usage and lifetime contracts

## Status, dependencies, and originating requirements

- **Status:** Complete design — implementation and dependency qualification
  remain separate; no executable feature completion is claimed.
- **Dependencies:** [059](059-reject-escaping-capabilities.md),
  [030](030-specify-shared-and-cyclic-ownership.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 5 / usage and
  lifetime contracts. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify unique/shared, borrowed, once/many, capture and cleanup contracts for
source and separate compilation.

## Starting point

[wasm_lifetimes.zig](../zig-native/src/backend/wasm_lifetimes.zig) infers
optimization facts but does not provide public usage contracts. Tasks 030 and
059 define runtime ownership and capability lifetimes.

## Implementation checklist

- [x] Settle source annotations, subtyping/conversion and branch/loop rules for
      uniqueness, borrowing and invocation multiplicity.
- [x] Define capture transfer, resource cleanup, exceptional exits and
      interactions with demands and suspended effects.
- [x] Specify exported evidence and imported-call checking so separate
      compilation cannot erase usage/lifetime obligations.
- [x] Document diagnostics and accepted/rejected examples, including the exact
      meaning of once versus exactly-once.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review aliases, repeated/conditional calls, borrowed returns, resource scopes,
  closures and callback captures.
- Trace ownership at cancellation/trap boundaries and across opaque/compiled
  interfaces.

## Acceptance criteria

- [x] Durable contracts settle syntax, semantics, representation, diagnostics
      and compatibility.
- [x] Tasks 061–062 have clear proof obligations for multiplicity and cleanup
      without relying on optimizer heuristics.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Source milestone: isolated design checkpoint based on `ef57ec5`; no compiler
  source or executable fixtures changed in this specification checkpoint.
- Durable record: [Usage Contracts](../zig-native/USAGE_CONTRACTS.md).
- Validation: `deno fmt --no-config --check` on the four specifications and task
  records, plus local path/heading validation; results recorded in
  [design qualification](../zig-native/LANGUAGE_DESIGN_QUALIFICATION.md).
- Comparison: documentation only; no runtime or compiler performance claim.
- Remaining limitations: dependent implementation tasks remain open. The design
  fixes syntax, ownership/identity, portable evidence and rejection boundaries;
  it does not claim those mechanisms are executable or qualified yet.
