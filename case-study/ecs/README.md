# ECS 3D sandbox/editor

> Paused prototype. The compiler-specific ECS, window, render, input, and asset
> backend has been removed. The code and instructions below describe the prior
> experiment, not a runnable application on the current compiler. `just study`
> reports this boundary. Retired compiler-side runtime/bench experiments are
> preserved in [prototype/](prototype/README.md).
>
> The replacement requires a Blot-source ECS and explicit entrypoint IO
> capabilities. See [the migration plan](PLAN.md) and
> [the compiler boundary](../../compiler/effects-and-io.md).
> [The proposed entrypoint API](../../compiler/host-api-proposal.md) includes
> Blot and host code without domain-specific compiler functions.

## Current game source

[game.blot](game.blot) now focuses on scene/editor policy and a Bevy-style
application builder: install input/camera plugins, initialize resources and
register systems. [Local engine modules](engine/) handle lifecycle/capabilities,
input edges, camera/transform math, mesh drawing and outlines. Typed records,
enums and flat multi-value matches replace scalar flags and nested dispatch.
`main(io)` binds narrow host callbacks; save/load codecs stay in Blot and host
file callbacks receive bytes.

This is not yet executable: the external ECS/render/asset/snapshot foundations,
general language features, state resolvers and composite ABI are still missing.
[The source API contract](source-api.md) documents those boundaries and the
checks. The old TypeScript host still expects the retired four-export ABI and
has not been reconnected. The sections below describe that historical prototype,
not the updated entrypoint.

The prior prototype was a live-reloading Blot/Wasm game with a Deno
Desktop/WebGPU host. It follows `gdev`'s 3D sandbox/editor workflow, with ported
renderer assets and no runtime dependency on the sibling repository. Blot owns
camera, animation, and editor policy; Deno supplies input, picking, rendering,
files, and the compiler process.

## Run

From the repository root, with Deno **2.9.6**, Bend **2.0.5**, Bun, clang, and a
working native WebGPU/display environment:

```sh
just build        # once, and again after changing the Bend compiler
just study        # watches game.blot and assets; opens the native window
just test-study   # type/lint checks and real compiler/runtime/GPU tests
just smoke-study  # 180 native frames; captures build/ecs-native.png
just bench-study  # seven samples; writes build/ecs-case-bench.json
```

Without Just, use `deno task build:compiler`, `study:ecs`, `test:study`,
`smoke:study`, and `bench:study`. For example:

```sh
deno task study:ecs --source=case-study/ecs/game.blot --save=build/my-scene.json
deno task study:ecs --frames=3600 --capture=build/ecs-native.png
```

The launcher enables Deno Desktop's TypeScript HMR and supplies a narrow native
compiler executable permission to the application. Its own read/write/env/run
permissions support Desktop's build/cache and subprocess launch. On Linux it
checks `ldconfig`; if only `libxdo.so.4` is installed, it creates a temporary
`libxdo.so.3` link for this child process and removes it on exit. It does not
change system libraries. The first Desktop launch downloads/builds its runtime;
that is not a Blot compilation measurement.

## Controls

| Input                                | Action                                            |
| ------------------------------------ | ------------------------------------------------- |
| Left/right arrows, right-button drag | Orbit the camera                                  |
| Up/down arrows, mouse wheel          | Zoom                                              |
| Tab                                  | Toggle play/edit; animation pauses while editing  |
| Left click / drag in edit mode       | Select / move on the ground plane                 |
| P / X                                | Place at the pointer / remove the selected entity |
| `=` / `-`                            | Enlarge / shrink the selected entity              |
| R / M                                | Rotate 15 degrees / cycle material                |
| F6 / F9                              | Save / load `build/ecs-quicksave.json`            |

The title shows play/edit mode, selection, and reload status. Compiler
diagnostics appear in the terminal. Losing focus clears held keys and drag/orbit
gestures. Selection is a geometric outline around the editable mesh.

## Try live reload

Run the game, move the camera, and arrange a few entities. Edit `camera_speed`,
`spin_speed`, or a system body in [game.blot](game.blot), then save. The
existing world, camera, selection, and queued input survive the replacement. Try
a syntax error: the terminal reports its position and the previous program keeps
running. Fix it and save again; no restart is needed.

The reload path is deliberately transactional:

1. A directory watcher observes saves/atomic replacements and debounces for 75
   ms.
2. A Deno worker parses the source and asks a persistent native Bend process to
   compile it. Rendering and input delivery continue independently.
3. The compiler retains lowering, inference, const, and relocatable-code caches.
   Only changed declarations cross the pipe; unchanged declarations refer to the
   last successfully acknowledged revision. Full-module validation remains.
4. Replacement Wasm is instantiated asynchronously. At the next simulation step,
   it receives the **latest** world, consumes pending input, and produces a
   validated first frame before becoming active.

Newer edits invalidate older candidates immediately. Syntax/type failures,
incompatible storage, and invalid first-frame values publish nothing. The old
world receives the same queued events if a candidate fails. Added storage is not
silently defaulted: new resources need an explicit initializer; removed or
retyped existing storage needs migration.

Meshes, material JSON, WGSL, and textures also reload. Invalid replacements keep
the last usable revision; material updates wait for usable dependencies. See
[ASSETS.md](ASSETS.md) for formats, resource ownership, tests, and picking
limits. This application-level Blot/asset guarantee is distinct from
[Deno Desktop HMR](https://docs.deno.com/runtime/desktop/hmr/): structural
TypeScript host changes can restart the host and do not promise world retention.

## Implementation boundaries

- [game.blot](game.blot): world construction, component initialization, explicit
  system order, input bindings, camera/transform math, editing and render
  output. Only `start`, `event`, `update`, and `render` are exported.
- [game.ts](game.ts): generic platform-event encoding and the four guest calls.
  It contains no component names, seed scene, system list or game math.
- [runtime.ts](runtime.ts): fixed 60 Hz simulation, interpolation, bounded
  catch-up, ordered input, reload publication, and save/load coordination.
- [background_compiler.ts](background_compiler.ts),
  [code_reload.ts](code_reload.ts): worker lifecycle and latest-revision
  handoff.
- [snapshot.ts](snapshot.ts): validated versioned JSON, nominal storage schema,
  adjacent-file atomic replacement, and explicit F32 negative-zero encoding.
- [archived guest runtime](prototype/guest_runtime.ts): validated
  [retired application ABI v1](prototype/guest-abi.md), render packet decoding,
  detached bank snapshots and schema-based reload/save transfer. ECS storage,
  query iteration and entity lifecycle execute inside import-free Wasm.

Simulation runs systems deterministically and serially; inferred effect batches
are not yet a parallel runtime scheduler. Entity IDs are monotonic, not
recycled. ABI v1 supports 4,096 allocated entity slots, 8,192 draws and 64
ordered platform commands per entry; saves remain capped at 8 MiB. The scene
uses scalar U32/F32 component/resource columns, not a general record/array ABI.
Source-language arrays/records, SIMD, F64, general file imports, type-valued
consts remain future compiler work. Higher-order effect inference is now part of
the generic core; the retired application ABI is unrelated to the new
[generic callback ABI](../../compiler/guest-abi.md). Numeric operators currently
target U32; F32 code uses explicit `F32.*` prelude functions.

The host never replays startup on code reload. Compatible columns/resources are
copied by nominal identity; removals and scalar-layout changes require explicit
migration. Added component columns start absent, and no new resource default is
invented. Pending new render dependencies defer publication; invalid code,
panics or unusable replacements retain the last good world/frame. `@window`
requests are drained only after a validated frame commits.

## Measured iteration cost

On this development machine (Ryzen 7 7800X3D, Linux, Deno 2.9.6, native Bend
2.0.5, one compiler thread), seven measured samples after two discarded warmups:

| Actual game edit | Compile median | Through validated handoff median | Handoff p95 |
| ---------------- | -------------: | -------------------------------: | ----------: |
| Animation body   |       25.79 ms |                         26.16 ms |    28.09 ms |
| Camera constant  |       22.20 ms |                         22.50 ms |    27.74 ms |
| Comment only     |       22.12 ms |                         22.44 ms |    25.89 ms |

Body edits lower/check/emit one changed declaration/group/code entry, reusing 56
declarations, 62 inference groups, and 150 code entries. The benchmark
alternates edited/base source, verifies exact Wasm bytes against clean native
compiles outside the timer, and includes parsing, pipe transport, native work,
response decoding, Wasm preparation, latest-world transfer, and a simulated and
validated frame. It excludes startup, file-watch debounce, and GPU presentation:
**these are not edit-to-photon measurements**. Startup, cold compile, individual
samples, counters, and source/prelude/parser/compiler hashes are in the
generated JSON. Run `just bench-study` to reproduce on your machine.

For a fixed 64-system comparison, declaration deltas reduced native body edits
from 177.30 ms to **68.01 ms**; the old JS incremental path measured 127.54 ms.
See [performance-baseline.md](performance-baseline.md) for matched feature sets,
all edit classes, exact hashes, and the remaining frontend/global-work floor.

## Verification and issues uncovered

The tests execute the actual native compiler and Wasm, real filesystem watchers,
and WebGPU pixel readback. Coverage includes behavior-changing edits,
state/input preservation, malformed code/layout/first frames, rapid saves, early
shutdown, snapshot validation, asset dependencies, picking, resizing, and GPU
disposal. The game stress check executes 100,000 direct Wasm camera/animation
ticks and 1,000 immutable-world frames with a bounded Wasm memory check.

The native Wayland window was exercised for 3,600 frames and its actual surface
captured and visually inspected. The smoke command reproduces that capture, not
an offscreen reconstruction. Offscreen tests used llvmpipe LLVM 22.1.8. Deno's
WebGPU path is unstable: an intermittent native exit 139 was observed after
completed GPU tests in earlier runs; checks and execution are separated in the
test task, but this is not a claim to have fixed Deno's driver/runtime teardown.
A forced X11 run on this machine rejected the adapter/surface queue-family
combination; Wayland is the verified native-window path.

The case study exposed and fixed F32 decimal double-rounding, stale-world reload
handoffs, worker initialization/shutdown races, failed asset dependency
publication, and repeated whole-tree native decoding. Their regression tests and
the [compiler documentation](../../compiler/README.md) preserve those
boundaries. [PLAN.md](PLAN.md) records the completion contract.
