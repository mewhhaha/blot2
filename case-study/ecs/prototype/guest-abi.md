> Archived compiler-coupled prototype; not part of the current compiler.

# Blot application memory ABI, version 1

Status: prototype reference, not the final compiler/library boundary. The user
requires ECS to be implemented in ordinary Blot source; the current `@ecs.*`
lowering and compiler-generated ECS runtime must be replaced by reusable core
features and a source library. The layout below records the existing prototype
for migration and does not settle the ownership of the eventual ABI generator.

`compileApp` emits an import-free Wasm module with four `Unit -> Unit` source
entrypoints: `start`, `event`, `update`, `render`. Source controls every system
invocation through `@ecs.run system` or `@ecs.at entity system`; JavaScript
never chooses component names, queries or system order. `compileEcs` remains the
older host-provider target for its existing examples and compiler benchmarks.

This is a small application ABI, not the WebAssembly Component Model canonical
ABI. Persistent storage supports nominal single-constructor U32/F32 wrappers,
not arbitrary persistent ADTs, closures, references or first-class arrays.

## Ownership and lifetime

The private `[0, 0x01000000)` region contains temporary compiler values. Export
calls reset that arena; query iterations also reclaim call-local allocations. No
pointer, closure, constructor tag or module-local asset ID may be stored in a
persistent world slot. F32 slots store IEEE binary32 bits; U32 slots store
words.

The world starts at `0x01000000`. All fields use little-endian 32-bit words. Its
256-byte header holds these byte offsets:

| Offset       | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| 16 / 20 / 24 | Current / previous / draft bank pointers                   |
| 28           | Phase: idle 0, start 1, event 2, update 3, render 4        |
| 32           | Current query entity; `0xffffffff` outside an entity scope |
| 36           | Last fault code; 0 means no fault                          |
| 40           | Initialized flag                                           |
| 44           | Commit revision                                            |

Three equal banks follow the header. Each bank starts with an entity extent at
offset 0, 12 reserved bytes, and 4,096 liveness words. Storage follows in the
exact order of `artifact.storage`: a component has 4,096 value words followed by
4,096 presence words; a resource has one value word and one presence word. Bank
stride is rounded up to 64 bytes. Presence/liveness words are 0 or 1.

Entity IDs are monotonic and not reused in this version. Spawn, draw and command
capacity overflow trap, rather than silently truncating work. The total memory
limit is 64 MiB; the compiler also keeps its own storage lookup table outside
the public packet regions.

`start` builds the cold world and establishes its initial previous snapshot.
`event` commits a draft while retaining previous simulation state. `update`
commits and makes its input world the previous bank. `render` cannot mutate
world storage. An entry trap leaves current/previous banks uncommitted, and the
next entry overwrites the failed draft. Success leaves phase idle and entity
scope cleared. `@ecs.previous Type` returns current when that entity/component
did not exist in the previous bank.

The host owns detached immutable bank snapshots for frame rollback, saves and
reload. It copies bytes, not compiler-private values, and does not perform ECS
queries. Reload maps columns by nominal module/declaration identity and scalar
kind; constructor tags, physical offsets and asset indices are relocatable.
Removal or layout changes require an explicit migration. New component columns
start absent. New resources have no implicit default; a candidate that reads one
is rejected. Startup is never replayed on reload.

## Exported layout

The module exports `memory` and immutable U32 globals prefixed `__blot_`:
`abi_version`, `world_base`, `bank_stride`, `input_base`, `render_base`,
`command_base`, `entity_capacity` (4096), `draw_capacity` (8192), and
`command_capacity` (64). The host checks all values against this ABI and rejects
modules with host imports or mismatched metadata.

Input starts after the three banks. Its 64-byte packet contains five U32 words
(`event_kind`, `key`, `button`, `picked`, `pick_valid`), then ten F32 words
(`pointer_x`, `pointer_y`, `wheel_delta`, `delta_time`, `viewport_width`,
`viewport_height`, `alpha`, `hit_x`, `hit_y`, `hit_z`), then one reserved word.

Event kinds: none 0, key down/up 1/2, focus loss 3, pointer down/up/move 4/5/6,
wheel 7, asset ready/failed 8/9. Character keys retain their Unicode scalar.
Named keys use the range above Unicode: arrows left/right/up/down
`0x110100..0x110103`, Tab/Escape/Enter `0x110104..0x110106`,
Backspace/Delete/Home/End/PageUp/PageDown `0x110107..0x11010c`, F1..F24
`0x110201..0x110218`. Space is 32; unknown keys are 0. `pick_valid` describes a
supplied geometric hit, while `picked` is the opaque draw pick ID or
`0xffffffff` for non-pickable geometry. The source decides what a key or hit
means. Asset notifications currently carry only event kind to Blot.

## Rendering and platform requests

The render packet follows input. Its 256-byte header contains:

| Offset       | Meaning                                                  |
| ------------ | -------------------------------------------------------- |
| 0            | Draw count                                               |
| 8            | Clear RGBA, four F32s                                    |
| 24 / 36 / 48 | Ambient / light direction / light color, three F32s each |
| 64 / 128     | View / projection matrices, 16 column-major F32s each    |

At offset 256, each 80-byte draw contains mesh ID, material ID, Boolean
pickability, opaque pick ID, and a 16-F32 column-major affine transform.
Matrices, lighting, asset references, pickability and capacities are validated
before presentation. Materials reference shader/texture assets; game code
chooses material/geometry references, while the host loads and reloads GPU
resources.

The 64-byte-aligned command packet follows render capacity. Its header contains
count at 0 and title ID at 4 (`0xffffffff` means unchanged). At byte 16, each
8-byte ordered command contains kind (save 1, load 2) and reserved argument 0.
Save/load use the host-configured save slot. Commands are cleared on entry and
only exposed after successful execution. The case-study host drains them after a
complete frame is validated and published, never during a candidate probe.

A single `blot:app` custom section contains LE U32 version, asset count, assets
(kind 0 mesh / 1 material, string), title count/titles, and panic
count/messages. Every string is a UTF-8 byte count followed by bytes and zero
padding to four bytes. Numeric asset/title references are local to this module.
`@panic
"message"` sets fault `0x10000 + message_index` and traps, preserving
the message for the host error.

New-frame asset dependencies must be resident before publication. Pending or
failed new dependencies keep the previous frame/world; failed replacements of
existing assets retain their last usable revision. A waiting code candidate is
retried against the latest committed world, never a compile-start snapshot.
