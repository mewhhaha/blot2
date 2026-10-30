# 118 — Migrate Gdev systems to owned pools

- **Status:** In progress — two Sol lanes own groups 1–2 and 3–4; source migration underway, no compilation or qualification claimed.
- **Dependencies:** API handoffs from 114–117 and the concrete owner schema from
  119. Implement alongside 119; compile after the batch.
- **Contract:** [Review](../zig-native/STORAGE_REWRITE_REVIEW.md),
  [schedule and gates](STORAGE_REWRITE.md).

## Outcome and ownership

Preserve gameplay policy and deterministic ordering while systems mutate the
application's owned pools through explicit access. Remove returned-world,
implicit-snapshot and effect-provider assumptions. Keep game-specific types,
assets, defaults and policy in Gdev.

Own these Gdev source groups, in this order, plus their corresponding handwritten
tests:

1. `src/world/**` and `src/buildings/**`.
2. `src/actors/**`.
3. `src/player/**` and `src/effects/**`.
4. `src/ui/**`, `src/progression/**`, `src/platform/**`, `src/debug/**`.

Task 119 exclusively owns `src/{game,library,main}.blot`, the new owner/schema
module, `devtools/**`, configuration and shared codec fixtures. Send it schema
additions and ordering constraints instead of editing those files. For any
generated module, change its generator input/template and regenerate through
the integration owner; do not hand-edit generated outputs.

## Implementation

- [ ] Inventory component/resource declarations and registrations by source
  group. Give 119 the concrete row types, defaults, capacities, interpolation
  copy requirements and save-codec keys.
- [ ] Pass explicit access bundles to each system. Replace `ecs.get/set/read`
  effect use with borrowed read and pool mutation; specialize callbacks at
  composition. Runtime state stores data and ADT tags, not function objects.
- [ ] Flatten independently growing payloads into separate pools. Replace
  historical copies made by assignment with named explicit copy operations.
  Avoid cloning the whole world once per frame.
- [ ] Use deterministic deferred structural commands where a traversal would
  otherwise observe changing membership. Keep scalar payload updates immediate.
  Keep entity identity distinct from a row index that an algorithm might sort.
- [ ] Preserve only required previous values for interpolation. Keep game RNG,
  timestep, caches and numeric behavior explicit; source numerical kernels
  should change only where ownership requires it.
- [ ] Update tests that kept `before` and `after` aliases to take explicit
  snapshots. Preserve their behavioral assertions rather than deleting them.
- [ ] Keep codec keys/versions for unchanged lanes. Change an individual codec
  version when its lanes change; change `state_schema` only for a changed save
  envelope, coordinated through 119.

## Acceptance at shared checkpoint 3

- Gdev game and devtools compile through the new backend, with no counted
  fallback or storage-trigger declaration used to select semantics.
- A bounded scenario exercises construction, actor movement/work, interaction,
  UI output and scene restore with deterministic state/save witnesses.
- Registered interpolation snapshots survive later writes independently;
  transient outputs reset at the frame boundary and held/paused frames keep
  their intended ordering.
- Required application tests run together after the source batch. Document
  actual failures and intentional contract changes; do not treat pre-existing
  failures or the old test-suite wall time as new performance measurements.

## Evidence

Pending: changed source identities, executable compiler identity, commands,
behavior results and any remaining module gaps. Use task 121 for final timings.
