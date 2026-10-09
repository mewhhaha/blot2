# 003 — Specify general call summaries

## Status, dependencies, and originating requirements

- **Status:** Complete — design committed as `3de4bbb`.
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

- [x] Specify summary inputs/results for residual predicates, function-parameter
      obligations, lexical captures and latent effect rows, keeping principal
      schemes separate from caller-selected evidence.
- [x] Define admission, closed and unresolved states, recursive-component
      membership, bounded iteration, versioning, ownership and atomic
      publication. Include independently completed jobs surviving caller
      failure.
- [x] Specify fallback to ordinary checking and source-ordered authoritative
      diagnostics, including argument witness sites and deferred obligations.
- [x] Save the design under `zig-native/` and link it from the
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

- [x] Durable documentation settles the summary representation, semantics,
      diagnostic order, ownership and fallback API.
- [x] Every later summary task has positive, negative and recovery examples; the
      design does not claim those features are implemented.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `3de4bbb` — Specify general call summaries and recursive inference
  boundaries.
- Validation: `deno fmt --config /dev/null --check` passed for the
  specification, architecture and ownership contract. Local documentation links
  resolve. Reviewed every interface and acceptance group against
  `core_eval.zig`, the current shared-scheme tests and the language guide.
- Comparison: not applicable to this documentation-only design. Compiler
  behavior and benchmarks are unchanged; no redundant compiler test run was
  required.
- Remaining limitations: tasks [004](004-summarize-predicate-bearing-callees.md)
  through [008](008-canonicalize-specialization-keys.md) still implement and
  qualify these contracts. Portable summary records await the later query and
  artifact work; the design explicitly retains source fallback.
- Durable record: [CALL_SUMMARIES.md](../zig-native/CALL_SUMMARIES.md), linked
  from [ARCHITECTURE.md](../zig-native/ARCHITECTURE.md) and
  [CONTRACT.md](../zig-native/CONTRACT.md). It includes positive, negative and
  recovery cases for each later summary task.
