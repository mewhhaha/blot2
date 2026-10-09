# 060 — Specify usage and lifetime contracts

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
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

[wasm_lifetimes.zig](../zig-native/src/wasm_lifetimes.zig) infers optimization
facts but does not provide public usage contracts. Tasks 030 and 059 define
runtime ownership and capability lifetimes.

## Implementation checklist

- [ ] Settle source annotations, subtyping/conversion and branch/loop rules for
      uniqueness, borrowing and invocation multiplicity.
- [ ] Define capture transfer, resource cleanup, exceptional exits and
      interactions with demands and suspended effects.
- [ ] Specify exported evidence and imported-call checking so separate
      compilation cannot erase usage/lifetime obligations.
- [ ] Document diagnostics and accepted/rejected examples, including the exact
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

- [ ] Durable contracts settle syntax, semantics, representation, diagnostics
      and compatibility.
- [ ] Tasks 061–062 have clear proof obligations for multiplicity and cleanup
      without relying on optimizer heuristics.
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
