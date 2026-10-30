# 117 — Migrate Ink application lifetime

## Status and dependencies

- **Status:** In progress — Sol lane implementing the ownership API batch; shared consumer compilation pending.
- Start after task 114's API handoff; parallel with 115 and 116.
- Coordinate host/Foreign foundation interfaces with 113; no per-edit builds.
- Root integrator owns shared fixtures, generators and shared composition changes.

## Outcome and deliberate greenfield cut

One mutable simulation session owns named component/resource pools. Static schema
and stage calls replace stored world/scope/system closure chains. **Drop automatic
simulation rollback when a presentation is rejected.** Preserve transactional Pen
renderer/cache publication and explicit Snapshot/Restore, including netplay
restore/replay. Do not silently retry a frame and step simulation twice.
Partial mutations after a trap are not rolled back as a whole world; invalidate
the affected session and recreate it from an explicit checkpoint when recovery
is needed. Remove general `app.preview`; explicit copied sandboxes are separate.

## Exclusive ownership

In sibling `/home/mewhhaha/src/ink/lib/`, own `.blot` files/directories `app`, `codec`, `editor`, `lanes`,
`persist`, `persist/`, `preferences`, `services`, `services/`, `tune`, `pen/`.
Own matching tests and Pen session-protocol/version/acknowledgement changes,
including these paths under sibling `/home/mewhhaha/src/pen/`:

- `crates/pen-runtime/src/{program,game}.rs`: session/runtime semantics.
- `crates/pen/src/program.rs`: native acknowledgements.
- `crates/pen-web/src/program.rs` and `crates/pen-web/structured-source.ts`: browser
  session path.
- `crates/pen-codegen/src/program.rs`: protocol template/version; regenerate
  bindings rather than hand-patching generated output.
- Matching session/recovery fixtures: explicit checkpoint recovery/replay.

Preserve renderer transactions in `pen-runtime`.
Do not edit `../pen/crates/blot-host/src/lib.rs` or `native.rs`: task 113 owns them.
Shared fixtures/generators remain with root integrator; coordinate any necessary
cross-owner host interface change before editing.

## Implementation batch

- Replace ECS State/Maintenance scope plumbing with explicit access parameters;
  static stage functions replace runtime arrays of callable systems and wrappers.
- Compile-known codec/service/font-style policy calls must not require escaping
  function values. Replace tracing effect plumbing with explicit trace output.
- Session owners are named instance pools, not one movable record with multiple
  resizable tails. Task 119 hand-authors Gdev composition; no generator prerequisite.
- Keep frame order explicit: reset transient output, events, fixed checkpoints /
  updates, requested restore and normalization, rendering, encoding, output reset.
- Copy only registered interpolation state before fixed updates; specify deep
  copy rules for nested owners. Borrowed views never become saved snapshots.
- Preserve codec keys/version/migration behavior where saved lanes are unchanged.
  Restore resets transient caches, journals/readers and epochs as required.
- Keep editor history as locally owned encoded scene copies with explicit undo/
  redo limits. Delete immutable world forks and alias-based preview/rejection paths.
- Revise Ink–Pen protocol version and both native/browser acknowledgements to
  distinguish renderer publication from simulation advancement. Audit rejection,
  reload/recovery, input replay and netplay explicit restore paths together.
- Keep copied numeric host transport and isolated workers/prepared sessions;
  retain data queues and ordered job publication, remove language-task assumptions.
- Nonmoving growth preserves Ref/View/Link targets; view length stays captured.
  Membership invalidation and restore epochs remain separate application rules.

## Lean acceptance

At shared gates 2–3 reuse save/scene round trips, editor undo/redo, pause/hold and
normalization witnesses. Add one bounded native/browser rejection witness proving
simulation does not roll back or double-step, plus explicit restore/replay and
trap recovery from a checkpoint. Verify renderer rejection still leaves accepted
GPU cache state untouched. No exhaustive matrix after each edit.

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
