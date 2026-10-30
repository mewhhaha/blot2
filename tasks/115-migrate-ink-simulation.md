# 115 — Migrate Ink simulation

## Status and dependencies

- **Status:** In progress — ownership source batch handed off; shared consumer compilation and qualification pending.
- Start from task 114's API handoff; proceed in parallel with 116 and 117.
- Use compiler 110–113 contracts without waiting for repeated compiler builds.
- Root integrator owns shared fixtures, generators and cross-cluster API arbitration.

## Outcome

Simulation uses caller-owned pools, borrowed inputs and invocation-local scratch.
Preserve deterministic numerical and gameplay mechanisms while deleting accidental
immutable snapshots and ownership-through-closure machinery.

## Exclusive ownership

In the sibling checkout `/home/mewhhaha/src/ink/lib/`, own these `.blot` files and directories:
`animation`, `behavior`, `character`, `clock`, `contact`, `daylight`, `director`,
`environment`, `field`, `field/`, `joints`, `logic`, `math`, `motion`, `motion/`,
`navigation`, `navigation/`, `noise`, `particles`, `path`, `physics`, `physics/`,
`placement`, `polar`, `radial`, `random`, `rig`, `rigid`, `scene`, `shapes`,
`spatial`, `spatial/`, `spline`, `steering`, `terrain`, `tiles`, `time`, `timeline`,
`trajectory`, `transform`, `tween`.
Own matching numerical/simulation tests; shared fixtures/generators stay with
root integrator. Do not change task 114's storage or task 116's presentation files.

## Implementation batch

- Pass explicit pool/resource access through simulation entry points; no ECS
  State/Maintenance effects or hidden retained world scope.
- Put independently growing arrays in separate named instance-owned pools.
  Access bundles borrow them; do not introduce a movable multi-tail world record.
- Keep fixed-layout scalar/vector kernels direct. Allocate work arrays in bounded
  invocation scratch and reuse them within the explicit operation lifetime.
- Scene, spatial, field and prepared-physics caches mutate owned storage using
  revisions/dirty sources. Replace persistent-page sharing with direct updates.
- Make any old-scene retention an explicit copy with a nested-payload policy.
  Keep immutable authored geometry read-only where its lifetime is explicit.
- Update Ink `AGENTS.md` and scene documentation together: its historical
  automatic snapshot rule is superseded by explicitly copied snapshots, as
  recorded in the rewrite review. Coordinate shared architecture docs with root.
- Transform previous-state storage is independently owned and copied at the
  fixed-step boundary; do not alias current transforms as the previous frame.
- Keep seeds, contact caches, timesteps and solver policy caller-owned. Contact
  IDs remain U32; preserve affine/shear and finite static-terrain conventions.
- Preserve behavior continuation data and action IDs. Replace stored function
  arrays and general escaping closures with static dispatch/compile-known helpers.
- Growth preserves existing Ref/View/Link addresses, but captured view length is
  fixed. Never confuse this with membership validity after structural edits.
- Do not keep temporary scene/query borrows across restore or pool truncation.
  Flush membership changes in deterministic order at declared boundaries.
- Remove obsolete snapshot-only branches and update matching API documentation
  through the integrator rather than preserving compatibility wrappers.

## Lean acceptance

At shared gate 2, reuse a compact set of meaningful numerical/physics witnesses:
deterministic seeded replay, transforms/interpolation, contact IDs and scene
queries after sparse updates. Include one prepared-cache invalidation witness.
Compare observable results, not allocation implementation details. Preserve
correctness boundary cases; defer new performance claims until measured.

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
