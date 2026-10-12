# 044 — Specify rolling and summary operations

## Status, dependencies, and originating requirements

- **Status:** Complete at `20ef28d` (design only).
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

- [x] Define signatures, identities, combination laws, query/update operations
      and failure diagnostics using ordinary source APIs.
- [x] Specify ordering, associativity requirements, floating-point behavior,
      purity/effects and persistence of saved versions.
- [x] Set complexity/storage expectations and fallback behavior for
      noninvertible/nonassociative reducers, empty inputs and invalid windows.
- [x] Document examples and acceptance laws for tasks 045–046 without silently
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

- [x] Durable API and algebra documentation settles semantics, representation,
      diagnostics and compatibility.
- [x] Complexity claims and numeric laws are concrete enough to test separately
      from implementation.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: `20ef28d`; reviewed against qualified compiler `2689ad5`.
- Validation: Deno2.9.7 Markdown formatting/local links; independent U32
  wrapping, F32 order and noncommutative left-inverse trace assertions. No
  compiler source or executable fixtures changed; compiler builds were not
  needed for this documentation milestone.
- Comparison: concrete callback/node/time/storage bounds are specified for
  ordered fold, monoid/group windows and persistent summary build/get/query/
  update/concatenation. Measurements belong to045–046.
- Remaining limits: arbitrary algebra laws and reducer agreement are explicit
  caller promises, not compiler-certified proofs or guessed function identity.
  No executable API/optimization is claimed by this design.
- Durable record: [ROLLING_SUMMARIES](../zig-native/ROLLING_SUMMARIES.md), with
  exact purity/pull/trap/snapshot/numeric and acceptance laws.
