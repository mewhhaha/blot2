# 063 — Specify polymorphic packages

## Status, dependencies, and originating requirements

- **Status:** Complete design — implementation and dependency qualification
  remain separate; no executable feature completion is claimed.
- **Dependencies:**
  [056](056-implement-declarations-and-evidence-diagnostics.md),
  [059](059-reject-escaping-capabilities.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / polymorphic
  packages. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify higher-rank annotations and existential packages with scoped skolems and
portable evidence.

## Starting point

Current [types.zig](../zig-native/src/check/types.zig) and
[check.zig](../zig-native/src/check/check.zig) support ordinary generic schemes;
task 056 adds richer contract evidence and task 059 capability scope checking.
Explicit higher-rank/package syntax remains open.

## Implementation checklist

- [x] Define annotation, packing/unpacking and heterogeneous-package syntax with
      precise introduction/elimination rules.
- [x] Specify skolem scopes, evidence transport, associated types, effect/usage
      boundaries and specialization.
- [x] Set inference/checking limits, ambiguity/escape diagnostics and portable
      interface representation.
- [x] Provide positive/negative examples for tasks 064–065 without promising
      unrestricted inference.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review a rank-2 callback, existential implementation package and heterogeneous
  collection of abstract packages.
- Try to escape a skolem or scoped capability through a result, closure,
  associated projection or dependency interface.

## Acceptance criteria

- [x] Durable syntax, type rules, representation, diagnostics and compatibility
      are settled.
- [x] Skolem/evidence scope and bounded checking are explicit enough for
      implementation tests.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Source milestone: isolated design checkpoint based on `ef57ec5`; no compiler
  source or executable fixtures changed in this specification checkpoint.
- Durable record: [Polymorphic Packages](../zig-native/POLYMORPHIC_PACKAGES.md).
- Validation: `deno fmt --no-config --check` on the four specifications and task
  records, plus local path/heading validation; results recorded in
  [design qualification](../zig-native/LANGUAGE_DESIGN_QUALIFICATION.md).
- Comparison: documentation only; no runtime or compiler performance claim.
- Remaining limitations: dependent implementation tasks remain open. The design
  fixes syntax, ownership/identity, portable evidence and rejection boundaries;
  it does not claim those mechanisms are executable or qualified yet.
