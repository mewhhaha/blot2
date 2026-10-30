# 114 — Replace Ink storage and ECS

## Status and dependencies

- **Status:** In progress — Sol Ink storage/ECS lane; shared compilation pending.
- Uses the compiler interfaces agreed in tasks 110–113; source work need not wait
  for their compilation or qualification.
- Hand off the concrete pool, borrow, revision and copy APIs before 115–117 join.
- Shared fixtures, generator infrastructure and repository composition belong to
  the root integrator. No new world generator is a prerequisite.

## Outcome

Ink owns mutable pools and collections with borrowed access and explicit copies.
Delete the persistent COW/RC implementation and immutable-world branch contract.
Use named instance-owned pools with a static schema: do not build one movable
record containing many independently growing owners. A world-access bundle borrows
those owners; each aggregate owner has at most one resizable tail.
Task 119 hand-authors Gdev's concrete owner module after this API handoff.

The first concrete API passes row-owner descriptors and separately named
`Array U32` metadata `[epoch, payload_revision, structure_revision]`. `Pool a`
aliases `ResizeArray (Maybe a)`; entity presence is a separate `ResizeArray Bool`.
`read` copies a fixed inline row; `rows` returns a captured borrowed view.
This avoids requiring references to mutable aggregate-owner records or implicit
field dereferencing before the application slice can run.

## Exclusive ownership

In the sibling checkout `/home/mewhhaha/src/ink/lib/`, own these `.blot` files and directories:
`arrays`, `buffer`, `pages`, `map`, `map/`, `set`, `hash`, `lookup`, `handles`,
`changes`, `messages`, `journal`, `relations`, `history`, `reconcile`, `graph`,
`partition`, `claims`, `task_queue`, `ecs`, `ecs/`, `schedule`, `derived`,
`derived/`, `sort`, `statistics`.
Own matching subsystem tests. Do not edit shared fixtures or generators without
an explicit ownership transfer from the root integrator.

## Implementation batch

- Publish read/write/insert/remove, borrowed rows, copy-into, checkpoint and
  deterministic command-flush contracts before changing downstream call sites.
- Start with monotonic U32 entity IDs and entity-indexed component slots with
  presence information; preserve ascending deterministic iteration.
- Replace `State`/`Maintenance` effect handlers and stored scope closures with
  explicit access parameters and statically known maintenance calls.
- Separate payload revisions, membership revisions and lineage epochs; reset
  query caches/readers on restore. Flush structural edits at declared boundaries.
- Growth is nonmoving: existing Ref/View/Link targets remain valid, while a
  captured View length does not extend. Membership/query invalidation is a
  separate semantic rule. Enforce shrink/lifetime rules rather than banning growth.
- Snapshot copies own independent data; define nested payload copying explicitly.
  Plain descriptor copies are aliases, not independent snapshots.
- Replace persistent tries/page directories with owned mutable storage. Retain
  public mechanisms only where useful; delete obsolete COW batching scaffolding.
- Keep data job queues, epoch tickets and ordered publication; no language tasks
  or retained Wasm continuations. Policy callbacks must be compile-known.

## Lean acceptance

The real `Ink/tests/ecs.blot` module now compiles and executes with the shared
development compiler: five checks pass (growth/view/checkpoint independence,
structural commands, query revision invalidation, journal retention reset and
explicit span-payload copying). Evidence is in
`build/storage-integration/ink-ecs.log`. This is the storage/ECS integration
slice, not complete Ink qualification. Query key words, selected IDs and build
metadata now live in three caller-owned buffers rather than an owning Cache row.
Batch insertion/spawning/replacement APIs and readonly lookup views are written;
their broader callers still await application integration.

At shared gate 1, witness nested-copy independence, previous-component independence,
despawn cleanup, deterministic membership flush and query invalidation. Reuse
existing queue/journal witnesses for ordered completion and reset behavior.
No retained old world or collection silently changes after an explicit copy.

## Shared integration policy

Write complete subsystem batches before compiling; do not compile after each edit.
Use three shared gates, coordinated by the integration owner:
1. Storage/ECS ownership fixture after the API and compiler foundations join.
2. Complete Ink compilation and a compact set of existing behavior witnesses.
3. Gdev compilation, bounded gameplay/save/replay and headless rendering witnesses.
Run required final qualification once on the integrated candidate, not per module.
Do not report a partial run as a pass or infer frame performance from compile time.

## References

- [Rewrite review](../zig-native/STORAGE_REWRITE_REVIEW.md)
- [Storage rewrite](STORAGE_REWRITE.md)
- Ink `docs/architecture.md`, `docs/blot.md`; compiler `zig-native/SCOPED_STORAGE.md`.
