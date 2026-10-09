# 044 — Specify rolling and summary operations

## Status, dependencies, and originating requirements

- **Status:** Pending — no completion is claimed.
- **Dependencies:** [040](040-fuse-packed-row-producers-and-consumers.md)
- **Originating requirements:** PLAN: Earlier programs / rolling reductions and
  summary trees. Sources: [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Specify source APIs and algebraic requirements for rolling reductions and
composable summaries.

## Starting point

[std/iter.blot](../std/iter.blot) already has immutable sliding windows;
[std/list.blot](../std/list.blot) and [std/array.blot](../std/array.blot) supply
folds. Incremental rolling reductions and summary trees remain open.

## Implementation checklist

- [ ] Define signatures, identities, combination laws, query/update operations
      and failure diagnostics using ordinary source APIs.
- [ ] Specify ordering, associativity requirements, floating-point behavior,
      purity/effects and persistence of saved versions.
- [ ] Set complexity/storage expectations and fallback behavior for
      noninvertible/nonassociative reducers, empty inputs and invalid windows.
- [ ] Document examples and acceptance laws for tasks 045–046 without silently
      changing existing folds/windows.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Check integer sums, noncommutative composition, F32 ordered reductions and
  reducers lacking an inverse.
- Review window boundaries, empty identities, persistent updates and queries
  spanning tree boundaries.

## Acceptance criteria

- [ ] Durable API and algebra documentation settles semantics, representation,
      diagnostics and compatibility.
- [ ] Complexity claims and numeric laws are concrete enough to test separately
      from implementation.
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
