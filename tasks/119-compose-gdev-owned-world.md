# 119 — Compose the owned Gdev world and static stages

- **Status:** In progress — concrete access schema agreed with task 118; composition source follows the task 117 handoff, no compilation or qualification claimed.
- **Dependencies:** 114 storage API, 117 application/session API; coordinate
  concrete pool declarations with 118 before either completes.
- **Contract:** [Review](../zig-native/STORAGE_REWRITE_REVIEW.md),
  [schedule and gates](STORAGE_REWRITE.md).

## Outcome and ownership

One instance owns the game's named pools. A small access bundle passes borrowed
handles to static stage functions. No runtime array of system closures or chain
of immutable world scopes remains.

Own Gdev `src/{game,library,main}.blot`, new `src/world_storage.blot`,
`devtools/**`, `pen.json`, root composition tests and
`tests/codec_support/state.blot`. Own root documentation and coordinate generator
inputs and generated bindings. Task 118 owns all listed game subsystem
directories and their direct tests. Do not duplicate reusable Ink mechanisms.

## Implementation

- [ ] Publish the concrete owner/access schema early: entity presence, component
  rows, resources, variable payload pools, interpolation destinations and frame
  scratch. Preserve deterministic registration order and game defaults.
- [ ] Hand-author the first concrete schema and stage calls. Do not block on a
  new reflection or world-codegen project. Use existing code generation only
  where it already owns bindings, codecs or model outputs.
- [ ] Supply actual pool/metadata/transport capacity requirements to 110/111/113.
  Report budget assumptions and checked overflow behavior; no hidden 1 MiB
  charge per component or implicit relocation.
- [ ] Compose start, normalize, interface, event, fixed-update, settle and render
  stages as known direct calls. Preserve conditions, ordering, pause/hold,
  frame reset and post-restore normalization from the old application.
- [ ] Initialize instance pools before publication. Export only copied packets;
  do not retain invocation-local refs or expose owner descriptors to Pen.
- [ ] Integrate explicit save/scene/undo paths and the revised acknowledgement
  protocol. A rejected presentation cannot silently replay a mutated frame.
  Keep explicit restore/replay used by tooling and netplay.
- [ ] Migrate devtools to borrowed reads and explicit mutations/snapshots. Keep
  diagnostic inspection from accidentally retaining a live frame borrow.
- [ ] Regenerate outputs from their inputs. Change codec versions for changed
  payloads; update `state_schema`, `src/main.scene` and codec fixtures together
  only if the save envelope changes.

## Acceptance at shared checkpoint 3

- Game and devtools run with the same compiler artifact through Pen and browser
  guest interfaces; both use the new protocol and explicit storage model.
- Initial state, one fixed update, paused/held update, scene load, save/restore
  and bounded restore/replay work. Pool state persists across exported calls;
  frame scratch does not become a persistent root.
- A real bounded headless scene renders; inspect the resulting GPU screenshot
  when visible behavior changes. GPU checks run sequentially, without desktop
  windows.
- Run Gdev `pen check`, `pen codegen --check` and `pen test-blot` as one consumer
  batch, recording baseline failures and intentional expectation changes.

## Evidence

Pending: schema and budgets, compiler/source identities, generated-output check,
behavior/host evidence. Task 121 records fresh/retained compilation and already
compiled runtime separately; this task makes no performance claim.

### Source batch notes (not qualification)

- `src/world_storage.blot` declares separate named owners, static save/scene
  calls, explicit restore epochs, synchronous editor stash/restore callbacks,
  bounded encoded-scene history, and invocation-only frame binding. Its known
  continuation encloses the complete `host.run` Foreign loop; owners are not
  recreated per frame. Compiler 110 must demonstrate this retained lifetime.
- `src/game.blot` and `devtools/main.blot` compose direct stage calls. Core
  devtools console/log/history/macros use flat rows and separate text pools;
  diagnostic panel storage remains an active source dependency.
- Terrain initialization uses 37,249 samples per F32 lane: three terrain lanes
  446,988 bytes, bare-field lane 148,996 bytes, 169 revision tiles 1,352 bytes.
  Activity history uses 278 by 22 U32 values (24,464 bytes) and 88 bytes of rates.
  Editor history is explicitly capped at 64 entries / 1,048,576 F32 lanes.
  Gdev config now selects shared temporary 2 MiB, each plain global region
  256 KiB, transport 2 MiB and 4,096 owner slots. Grower budget remains the
  compiler default pending region inventory and per-owner reservations; the
  4 MiB history cap is preserved. Whole-game memory qualification is unresolved,
  and these settings do not claim a uniform 1 MiB grower budget suffices.
- Existing font/codecs/Pen generators were changed and outputs regenerated.
  `scripts/generate-text.py` emits one immutable character pool plus plain span
  tables. Its pinned `(text ()).field` projection must be inspected in the first
  compiled game: do not assume the large accessor record is free to construct.
- Section payload keys, versions and numeric framing are preserved. Static
  section ordering is deterministic but raw full-save byte equality with the
  previous registration chain is not claimed. Scenes contain entities/current
  component columns, seed interpolation copies explicitly, and leave resources
  live, matching the prior scene contract.
- `tests/owned_devtools.blot` contains unrun exact macro-v1 roundtrip/compaction
  and parser-span growth witnesses. No Blot compilation, execution, frame-time
  measurement or GPU qualification is claimed by this source batch.
