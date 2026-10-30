# 116 — Migrate Ink render and UI

## Status and dependencies

- **Status:** In progress — ownership source batch handed off; shared consumer compilation and qualification pending.
- Begin after task 114 hands off storage/access APIs; parallel with 115 and 117.
- Coordinate frame/output lifetime with 117 and transform input with 115.
- Root integrator owns shared fixtures, generator infrastructure and composition.

## Outcome

Presentation borrows live simulation state and constructs explicitly owned frame
output. Retained rendering/UI caches update mutable storage through revisions
rather than preserving whole immutable worlds or page trees.

## Exclusive ownership

In the sibling checkout `/home/mewhhaha/src/ink/lib/`, own these `.blot` files and directories:
`audio`, `brush`, `camera`, `color`, `debug`, `events`, `gizmos`, `graphics`,
`input`, `input/`, `lighting`, `locale`, `menu`, `orbit`, `picking`, `profile`,
`render`, `render/`, `shadow`, `sound`, `text`, `ui`, `ui/`, `view`.
Own matching presentation/UI/input tests. `editor`, persistence and every `pen/`
adapter belong to 117; do not edit those or shared fixtures/generators.

## Implementation batch

- Pass explicit resource/pool access to input, camera, audio and presentation
  mechanisms; remove reliance on ECS effect scopes and immutable read snapshots.
- Use separate named instance-owned stores for growing retained tables and UI
  collections. Borrow access bundles; do not embed independent growing owners
  in one movable aggregate or assume descriptor copies freeze nested data.
- Build immediate output in a frame-owned arena/pool that remains live through
  wire encoding. Reset it at the declared boundary agreed with 117.
- Current/previous interpolation inputs are borrowed from distinct owning pools.
  Do not retain a view beyond restore/reset or pool shrink.
- Ref/View/Link remain address-valid across nonmoving growth; existing view
  length stays captured. Query membership and UI topology revisions separately
  govern whether an iteration/preparation is semantically current.
- Replace paged persistent retained identities, scene snapshots and prepared UI
  trees with mutable stores plus explicit dirty/revision inputs.
- Preserve deterministic draw order, retained updates/removals, instance identity,
  focus/modal/visibility behavior and audio/service output ordering.
- Make application-requested frozen geometry/UI/frame retention an explicit
  independent copy, with a declared nested-payload copy policy.
- Replace runtime callable records/arrays such as font glyph policies with
  compile-known policy parameters or direct static dispatch. Keep data in records.
- Keep GPU/platform resource ownership in Pen. Adapter changes flow through 117;
  do not introduce a second host/render transport or a new generator dependency.
- Keep renderer transaction rejection distinct from simulation rollback, which
  task 117 deliberately removes from the session protocol.

## Lean acceptance

At shared gate 2, reuse compact witnesses for interpolation, dirty UI preparation,
focus/modal behavior, retained ordered updates/removals and audio output.
At gate 3 inspect bounded real headless game render witnesses through Pen.
Do not open desktop windows or run GPU consumers concurrently. No per-edit
compilation or image-golden expansion is required for this ownership migration.

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
