# 063 — Specify polymorphic packages

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:**
  [056](056-implement-declarations-and-evidence-diagnostics.md),
  [059](059-reject-escaping-capabilities.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 7 / polymorphic
  packages. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify higher-rank annotations and existential packages with scoped skolems and
portable evidence.

## Starting point

Current [types.zig](../zig-native/src/types.zig) and
[check.zig](../zig-native/src/check.zig) support ordinary generic schemes; task
056 adds richer contract evidence and task 059 capability scope checking.
Explicit higher-rank/package syntax remains open.

## Implementation checklist

- [ ] Define annotation, packing/unpacking and heterogeneous-package syntax with
      precise introduction/elimination rules.
- [ ] Specify skolem scopes, evidence transport, associated types, effect/usage
      boundaries and specialization.
- [ ] Set inference/checking limits, ambiguity/escape diagnostics and portable
      interface representation.
- [ ] Provide positive/negative examples for tasks 064–065 without promising
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

- [ ] Durable syntax, type rules, representation, diagnostics and compatibility
      are settled.
- [ ] Skolem/evidence scope and bounded checking are explicit enough for
      implementation tests.
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
