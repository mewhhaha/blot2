# Source-library sandbox

[game.blot](game.blot) contains scene/editor policy and a const-time application
builder. Reusable Blot modules now live in [engine/](engine/). This is a
**source design specimen, not a runnable game**: declaration transforms, record
field access/update, array spread/indexing sugar, runtime text, type-valued
descriptors, the proposed composite host boundary and the foundation packages
below still need implementation.

Relative and explicitly mapped imports, tuple values/patterns, named record
construction/patterns, and immutable homogeneous arrays now compile and execute
in the generic core. Const composition, `:=` shadowing, `for` loops, scoped
state and numeric-array guest ABI 2 are also executable. The sibling gdev
checkout now implements a source ECS with const-derived storage and effect-based
access; this specimen retains a broader proposed API. Array updates still copy.
See the [executable guide](../../compiler/guide.md) and
[state/effect boundary](../../compiler/effects-and-io.md) for current support.

The local modules contain source bodies, not wrappers over retired compiler
hooks. The external `engine/ecs`, `engine/render`, `engine/assets`,
`engine/snapshot`, `std/bytes` and `std/host` imports remain proposed
foundations, not installed packages. Their namespaces are library names; the
compiler must not recognize them specially. The executable
[scalar callback example](../../examples/host_io.blot) demonstrates only the
smaller implemented ABI.

## Module boundaries

| Module                                       | Responsibility                                                                                               |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [game.blot](game.blot)                       | Assets, bindings, seed scene, play/edit mode, selection/dragging, animation and application composition.     |
| [engine/app.blot](engine/app.blot)           | Immutable registration builder, lifecycle scopes, frame validation, save/load and narrow capability capture. |
| [engine/platform.blot](engine/platform.blot) | Explicit input/frame values, capability records, errors and returned application callbacks.                  |
| [engine/input.blot](engine/input.blot)       | Platform event decoding, held keys, press edges, pointer deltas and focus-loss reset.                        |
| [engine/camera.blot](engine/camera.blot)     | Orbit controls, camera interpolation/projection and pure ground-plane intersection.                          |
| [engine/spatial.blot](engine/spatial.blot)   | Vectors, yaw-only transforms, interpolation and column-major model matrices.                                 |
| [engine/boxes.blot](engine/boxes.blot)       | Mesh queries, frame draws and twelve-edge box outlines. No scene-specific asset paths.                       |

`Editor`, `Mode`, `Action`, `Spin` and `Surface` stay in the game. Transform
fields form a record rather than seven scalar components. Selection and grab
offsets use `Maybe`; commands and modes use named constructors rather than
numeric flags. Independent conditions are matched together, for example:

```blot
case action, editor.mode, editor.selected, ground_point of
  Resize factor, Edit, Some entity, _ => ecs.at entity (resize factor)
  Rotate, Edit, Some entity, _ => ecs.at entity rotate
  _, _, _, _ => ()
```

The input module folds ASCII letter case before tracking holds, suppresses
repeated key-down edges, and clears holds on focus loss. Camera and editor
systems independently clear their gestures on that same event. Game bindings and
camera key choices remain explicit. Mesh drawing uses one generic
`Transform`/`Mesh` query; the selection pass explicitly scopes the selected
entity. An axis/sign product generates the twelve outline edges without sentinel
indices or repeated component reads.

## Building an application

```blot
const sandbox = do:
  let application = app.new "Blot — PLAY"
  application := input.plugin self
  // camera.plugin registers its resources and Event/Update/Render systems.
  application := app.insert_resource (Editor {
    mode: Play, selected: Nothing, grab_offset: Nothing,
  }) self
  application := app.add_system Start seed_scene self
  application := app.add_system Event edit_scene self
  application := app.add_system Update animate self
  application := app.add_system Render boxes.draw_mesh self
  return app.build application

const main = fn (io: Io) => app.bind sandbox io
```

This abbreviated example omits camera and scene/selection rendering
registration; the complete builder is at the bottom of `game.blot`. A plugin is
an ordinary builder-to-builder function, not a special compiler mechanism. `:=`
creates an immutable successor binding and `self` means the previous value.

In this proposed descriptor API, each system is registered separately **before**
its function becomes an `ecs.Descriptor`. An array of differently effectful
callbacks could otherwise unify their rows or lose the per-system access
information required for queries. The descriptor array is const-time metadata,
not a runtime callback vtable. `ecs.build` derives a schema/world type and stage
runners from those descriptors. It must retain callback identity,
component/resource effects, query boundaries and explicit ordering.

Executable gdev instead composes resource/component state directly, discards
registration metadata in `ecs.build`, and stores a runtime array of ordered
system callbacks. It uses explicit `query`/`query_pair` calls. The descriptor
inspection and automatic query derivation described here are not implemented.

The proposed foundation operations used by the local builder are:

- `ecs.resource value`: a nominal resource descriptor with an explicit initial
  value. Duplicate initializers are errors, not silently replaced defaults.
- `ecs.system (stage, function)`: an individual system descriptor retaining its
  inferred effects. Unknown resource reads/writes without an initializer are
  build errors. Component reads constrain queries; insertions declare storage
  but do not require a component already to exist.
- `ecs.build descriptors`: constructs `schema`, `world_type`, `create ()` and
  effectful `run stage`. The source library, not the compiler, implements
  descriptor inspection, storage, scheduling and query construction.

The first version preserves registration order **within each stage**, including
across plugins. The order is therefore input decoding → camera input → editor
input, camera tick → animation, and camera projection → scene → meshes →
selection → title during rendering. Resource conflicts alone cannot express
these dependencies. This deliberately serial design makes no parallel-runtime
claim; later independent schedule groups can carry explicit ordering edges.

`#[component]` and `#[resource]` are imported source declaration transforms.
Identity derives from the defining declaration/module, not a compiler-known
spelling. The changed record/grouping layout is not save-compatible with the old
scalar specimen; old snapshots require an explicit migration or rejection.

## State, rendering and capabilities

The proposed ECS resolver is:

```blot
let (next_world, result) = do ecs.scope world:
  use result <- computation ()
  return result
```

It threads immutable state and handles only ECS effects. Root scopes supply
resources, never an implicit entity. `ecs.at entity callback` introduces one
entity; a registered component-reading system queries matching entities.
Resource-only systems run once. Accesses inside explicit nested entity/query
scopes must not accidentally become requirements on the outer system. Non-ECS
effects continue to the enclosing provider.

`ecs.checkpoint` preserves the previous fixed-step values. Inserted components
initialize both current/previous values; `ecs.previous` supports interpolation
without advancing the world. General scoped-state resolvers now provide the
state foundation, but these exact foundation APIs remain proposed. Executable
gdev's individual previous-component reads fall back to current values when a
snapshot is missing; bulk previous columns preserve `Nothing` for missing
snapshots so rendering can choose its fallback explicitly.

Source-declared effect families can express a reusable state contract today:

```blot
type State a is effect = {
  get: Unit -> a
  set: a -> Unit
}

const increase = fn () => do:
  use count <- State.get U32 ()
  use State.set U32 (count + 1)
  return count

const read = fn (witness: input -> a) -> a => State.get ()
```

`State U32` names the concrete family instance; an explicit `! {State U32}` row
includes both operations. `State.get U32` and `State.set U32` can be supplied by
a scoped provider. Type application uses spaces, as it does for `Maybe U32`.
Generic helpers infer the family instance from ordinary argument and result
types. The `read` wrapper links the result of a constructor/function witness to
the result of `State.get`. The proposed `ecs.scope` additionally needs
entity/query selection, storage derivation and world checkpointing. Explicit
generic effect rows such as `! {State a}` are not yet supported inside
polymorphic functions.

The specimen also uses type-valued names such as `ecs.get Surface`. Current
typed selectors take constructor/function witnesses instead: for
`type Surface is data = Brass | Blue`, use `read (fn () => Brass)`. A type name
without a same-named constructor is not a value witness.

`render.collect callback` handles source packet-building effects and returns
`(RenderFrame, callback_result)`, forwarding ECS effects to the enclosing scope.
View/projection/model matrices remain column-major arrays of 16 F32 values.
Draws carry ordinary `GeometryRef`/`MaterialRef` values plus picking metadata.
Asset references are pure logical names; the host resolves its own geometry,
shader and texture resources. There is no const-time file IO.

Only the game's `main` is exported as the application entrypoint. It is now
pure: it binds the supplied capabilities into an `Application World`, without
setting a title or creating a world. Module exports are source imports, not
additional host entrypoints. The host drives:

- `create () -> World`: initializes registered resources and runs Start, once on
  first launch. It checkpoints the seeded world.
- `event world input -> Result [World, ApplicationError] ! {Foreign}`: supplies
  PendingInput, runs Event, clears the request resources, then handles
  Save/Load. It captures only file authority.
- `update world frame -> World`: validates time, checkpoints the previous tick,
  supplies Frame and runs Update. It captures no host capability.
- `render world frame -> Result [Unit, ApplicationError] ! {Foreign}`: supplies
  Frame, runs Render into one packet, reads Title, then calls window/render
  capabilities. Render-scope state is discarded, not committed to simulation.

F6/F9 request Save/Load through a typed resource. Blot encodes and validates
world bytes against `simulation.schema`; file callbacks address one authorized
slot and never receive ECS metadata/world handles. A loaded world is
checkpointed. Errors leave the caller's old world available. PendingInput and
the save/load request are cleared before encoding so they cannot replay on
restore.

Host callbacks still require `Foreign`. The only compiler intrinsic in these
modules is `@panic`. ECS, assets, window services, rendering and persistence are
never compiler primitives.

Key codes live in [`engine/keys.blot`](engine/keys.blot), using the numeric
values from the guest ABI. Action patterns use `^keys.tab`, `^keys.p`, and
similar names; the caret compares an existing value instead of introducing a
binding. Orbit controls use the same constants as ordinary expressions. The host
encoding and input module's ASCII case folding remain the ABI boundary.

## Reload boundary and verification

The host must publish a successor world only after its frame succeeds.
Window/render callbacks stage commands until commit. Save writes also need
staging, or must be withheld during speculative reload frames; arbitrary IO has
no automatic rollback. Rebinding a candidate application's capabilities must
retain/migrate the latest compatible world without calling `create` or replaying
resource defaults. New/changed resources require explicit migration.

The historical TypeScript host is still paused and expects its retired
four-export ABI. It has not been connected to these modules. No new compile-time
or reload performance claim follows from this refactor.

`deno task test:study-source` checks local import resolution/acyclicity,
registration, capability boundaries, typed source patterns, matrix layouts and
save/load ordering. `deno task check:editor` parses all local modules and runs
the highlight suite. These are source contracts and permissive editor checks,
not semantic compilation or gameplay tests. Runtime verification waits for the
missing generic language, foundation libraries and ABI work listed above.
