# 003 — Specify general call summaries

## Status, dependencies, and originating requirements

- **Status:** Ready — no completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** PLAN: Hills 1–3 / summaries and the sandbox
  region. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Write a durable specification for general call summaries, covering obligations,
captures, effects and recursive component boundaries.

## Starting point

[core_eval.zig](../zig-native/src/core_eval.zig) has `Session.call_summaries`,
`ClosureRegion.collectCall`, `principalEvidence` and iterative job draining.
Predicate-free global schemes and closed first-order jobs are already shared;
[zig-native/CONTRACT.md](../zig-native/CONTRACT.md) documents their fallback and
publication rules.

## Implementation checklist

- [ ] Specify summary inputs/results for residual predicates, function-parameter
      obligations, lexical captures and latent effect rows, keeping principal
      schemes separate from caller-selected evidence.
- [ ] Define admission, closed and unresolved states, recursive-component
      membership, bounded iteration, versioning, ownership and atomic
      publication. Include independently completed jobs surviving caller
      failure.
- [ ] Specify fallback to ordinary checking and source-ordered authoritative
      diagnostics, including argument witness sites and deferred obligations.
- [ ] Save the design under `zig-native/` and link it from the
      architecture/contract. Give tasks 004–008 explicit interfaces and
      acceptance examples; implementation remains separate.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review examples for a predicate-bearing generic, higher-order reducer,
  captured alias, latent effect and mutual recursion, including a failing leaf
  and failed enclosing caller.
- Trace each example through summary admission, fallback and publication;
  document limits and serialization compatibility rather than assuming all
  inputs close.

## Acceptance criteria

- [ ] Durable documentation settles the summary representation, semantics,
      diagnostic order, ownership and fallback API.
- [ ] Every later summary task has positive, negative and recovery examples; the
      design does not claim those features are implemented.
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
