# 054 — Specify associated types and implementations

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 3 / generic
  contracts. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify associated type members and implementation declarations with coherent
selection and portable evidence.

## Starting point

[compiler/guide.md](../compiler/guide.md#qualified-bindings) defines named
predicate bundles and current associated dispatch.
[check_contract_tests.zig](../zig-native/src/check_contract_tests.zig) and
[associated_catalog_tests.zig](../zig-native/src/associated_catalog_tests.zig)
cover existing contracts/catalogs; associated type members remain open.

## Implementation checklist

- [ ] Settle declaration/projection syntax, parameter scopes, implementation
      matching, overlap/coherence and selection precedence.
- [ ] Define evidence representation, associated-type equality/substitution,
      effect interaction and public/private visibility.
- [ ] Specify missing, incompatible and ambiguous evidence diagnostics and
      artifact versions, including separate-compilation selection.
- [ ] Give accepted/rejected examples and bounded inference rules for tasks
      055–056.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review generic/nested projections, overlapping implementations, recursive
  requirements and module boundaries.
- Check compatibility with current left/right dispatch and erased named
  contracts; identify intentional language changes explicitly.

## Acceptance criteria

- [ ] Durable syntax, selection/coherence, representation and diagnostics are
      settled.
- [ ] Evidence and artifact behavior is precise enough to implement without
      guessing.
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
