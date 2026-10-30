# 054 — Specify associated types and implementations

## Status, dependencies, and originating requirements

- **Status:** Complete — local implementation `f184dde`; qualified evidence
  below.
- **Dependencies:** [052](052-implement-opaque-types-and-privacy.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 3 / generic
  contracts. Sources: [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify associated type members and implementation declarations with coherent
selection and portable evidence.

## Starting point

[compiler/guide.md](../compiler/guide.md#qualified-bindings) defines named
predicate bundles and current associated dispatch.
[check_contract_tests.zig](../zig-native/src/check/check_contract_tests.zig) and
[associated_catalog_tests.zig](../zig-native/src/eval/associated_catalog_tests.zig)
cover existing contracts/catalogs; associated type members remain open.

## Implementation checklist

- [x] Settle declaration/projection syntax, parameter scopes, implementation
      matching, overlap/coherence and selection precedence.
- [x] Define evidence representation, associated-type equality/substitution,
      effect interaction and public/private visibility.
- [x] Specify missing, incompatible and ambiguous evidence diagnostics and
      artifact versions, including separate-compilation selection.
- [x] Give accepted/rejected examples and bounded inference rules for tasks
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

- [x] Durable syntax, selection/coherence, representation and diagnostics are
      settled.
- [x] Evidence and artifact behavior is precise enough to implement without
      guessing.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: local implementation `f184dde`; the separate record commit contains
  this completion evidence. Nothing is pushed.
- Validation: Zig 0.17.0; `deno task test:compiler` passes all 1,400 native and
  871 guest/client laws; eight unchanged release allocation budgets pass.
  `deno task lint:zig` checks 343 files with zero findings. The specification
  passes no-config Markdown formatting and local link/anchor checks. Examples
  were reviewed against current contracts, dispatch, privacy and ownership
  behavior. The accompanying compiler batch is independently qualified.
- Comparison: Documentation-only specification: no associated-member performance
  claim. Task 055 wire version 3 and task 056 wire version 4 are specified;
  their counters, bounded-work and performance laws remain executable work.
- Remaining limitations: Tasks 055–056 implement the specified members,
  projections, equality, implementations, coherence, methods and portable
  evidence. No such behavior is claimed by this design milestone.
- Durable record: [ASSOCIATED_CONTRACTS](../zig-native/ASSOCIATED_CONTRACTS.md);
  exact combined pins, commands, rejected attempts and raw evidence are in
  [integrated qualification](../zig-native/MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026).
