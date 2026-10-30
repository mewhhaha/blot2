# 112 — Admit flat data and control

## Status and scope

- **Status:** In progress — source batch handed to root integration. Seven
  executed flat-data checks pass, including same-owner indexed writes through
  nested loops, case-statement rebinding, inferred physical fields and rejection
  of fresh-owner backedges. The five real Ink ECS ownership checks also pass.
  The shared `scoped-storage` development gate passes (26 native laws, 45 guest
  witnesses, lint and local checks); full qualification is pending.
- **Dependencies:** Task 110's early layout/value/root/exit interface; coordinate
  sequence allocation with the runtime region owner. Do not wait for a build.
- **Context:** [Task index](STORAGE_REWRITE.md) and
  [conversion review](../zig-native/STORAGE_REWRITE_REVIEW.md).
- **Outcome:** Ordinary fixed data, ADTs, traversal and immutable lists use the
  owned storage plan without nested owning layouts or variable aggregate tails.

## File ownership

Own new files under `zig-native/src/backend/`: `storage_layout.zig`,
`storage_control.zig`, `storage_patterns.zig`, `storage_collections.zig`, and
`storage_data_tests.zig`. Own affected flat APIs in `std/array.blot` and
`std/list.blot`; coordinate prelude changes with the integrator instead of
editing `std/prelude.blot` independently. Own new executed witnesses in
`zig-native/tests/storage_flat_data_execution.test.ts`.
Do not edit `scoped_backend.zig`, runtime modules or shared test registration;
send the integration owner the small adapter changes those files need.

## Early interface handoff

Agree layout constructors, field offsets, ADT discriminants and descriptor
widths with task 110 and the runtime owner. Publish example layouts for
`(U32, F32)`, `Maybe U32`, a fixed record containing a typed link, and `List U32`.
State alignment, checked size arithmetic, payload initialization and root roles.
Control planning returns explicit normal/return/break/continue outcomes.
Collection planning accepts region destinations and known callback evidence;
it must not introduce an alternative call or lifetime analysis.

## Implementation steps

- Admit fixed tuples, records and nominal ADTs with an inline discriminant and
  fixed maximum payload width. Validate tags before interpreting payloads.
  Preserve source evaluation order independently of physical field order.
- Keep pool identity and lifetime on typed links; fixed layout is no authority
  to forge a link, expose private nominal fields or read uninitialized payloads.
- Add constructor/literal/wildcard/binder patterns, ordered guards and nested
  fixed patterns. Evaluate match inputs once; only a selected arm executes.
- Join only normally completing branches. Never-valued return/trap/break paths
  contribute no placeholder layout or root. Cleanup follows their real exits.
- Admit fixed aggregates and borrows as loop carries. Snapshot all backedge
  values before destination assignments so swaps and aliases retain meaning.
  Keep outer borrows live across backedges; close iteration scratch on continue,
  break and return. Fresh owning aggregate carries remain out of this task.
- Traverse arrays, views and lists using logical element counts and checked
  fixed strides. Evaluate the collection once and retain its owner throughout
  the traversal. Reject shrinking that invalidates a live traversal borrow.
- Implement `[]` as immutable flat sequences, distinct from mutable pool
  capabilities. Initially admit fixed inline elements without nested owners.
  Provide literals/spreads, length, traversal, generate/fill, append/prepend,
  concat/slice, and explicit Array/List conversions for the selected slice.
- Preserve immutable value and cursor snapshots. Copies may replace the old
  shared tree representation; array mutation cannot alter a previously created
  list. Do not add List indexing or `set`, or promise persistent-tree complexity.
- Route higher-order collection operations through task 110's known callback
  specializations. Reject unresolved callbacks, callable elements, nested owning
  collections and variable-tail records with source diagnostics.
- Update source API comments where tree sharing is no longer the contract.
  Do not disguise unsupported APIs as empty results or counted runtime calls.

## Acceptance and integration

`Maybe (U32, F32)` constructs and matches without losing F32 bits. A guarded
match evaluates only the chosen body. An array-producing conditional whose
other branch returns does not fail due to a Unit placeholder. A fixed tuple
carry swaps both values correctly; continue and early return recover scratch.
A saved list and cursor preserve their contents after the source array is
explicitly written. List append/concat preserve both input values and written
callback order. A borrow hidden in an ADT still cannot escape its owner or be
stored in an older pool. Variable owning tails and runtime callable elements
produce diagnostics before Wasm publication.

Use a compact executed-Wasm witness family and the native proof/cleanup laws
needed for these boundaries. Work in batches against the shared interfaces;
do not compile per edit or run separate exhaustive suites. The integrator owns
the shared native/Wasm integration batch and required final compiler gate and
Zig lint, using Zig 0.17 and `-Dllvm=false` for native development compilation.
