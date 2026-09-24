# Implementation and verification contract

The target is a runnable 3D sandbox/editor close to `gdev`, not a substitute
scalar benchmark. Live reload has priority. The user also requested a reasonable
prelude and improved compilation times.

## Source-library migration

**Revised requirement:** ECS is an ordinary Blot library. Compiler-recognized
`@ecs.*`, component/resource attributes, query planning, storage layouts and
system dispatch have been removed from the compiler. The guest backend and its
measurements are historical prototypes, not the current runnable architecture.

Window/render/input/asset services are source-declared host effects too. The
entrypoint receives an explicit `io` capability; effect declarations never grant
ambient IO authority. See
[the capability contract](../../compiler/effects-and-io.md).

The compiler boundary must instead supply reusable numeric/memory operations,
typed effects/providers, compile-time type/effect descriptors and platform/FFI
boundaries. Component registration, query derivation, storage and scheduling
belong in source. Ordinary `ecs.*` wrappers over hard-coded `@ecs.*` operations
do not count as this migration.

The [game source](game.blot) now illustrates this boundary without domain
intrinsics; [source-api.md](source-api.md) specifies its proposed libraries and
explicit capability entrypoint. It is a source-only migration, not a completed
library/runtime port or a restored executable sandbox. Local `engine/` modules
now separate application registration/lifecycle, input, camera, spatial math and
box rendering from game policy. The builder records individual system effects
and explicit resource defaults; its external ECS/render/snapshot foundations
still need source implementations and the missing generic language features.

The next boundary moves scene construction, systems, input policy and render
description into Blot, with JavaScript limited to platform services and an ABI
adapter. The earlier verification below records the host-ECS baseline, not this
migration's completion.

- [ ] Wasm with explicit generic host callbacks, no ambient/domain imports, owns
      source-defined ECS storage, queries, startup and system dispatch.
- [ ] A documented versioned memory contract separates persistent state from
      transient constructors/closures and carries typed asset/render references.
- [ ] Reload preserves the latest world without replaying startup. Failed code,
      schema changes, first frames and pending assets cannot publish bad state.
- [ ] Platform commands execute only after a successful frame; input and
      commands are neither lost nor replayed while waiting for assets.
- [ ] An unrelated Blot application runs through the unchanged host.
- [ ] Native/JS compiler parity, guest boundaries, sandbox tests, Bend proofs,
      native window and current compile/reload measurements pass.

Before resuming the sandbox, establish a generic non-ECS effect example that
passes an effectful function as a value, infers its row, handles a selected
effect in source, and rejects unhandled effects at its export. That independent
core boundary prevents another domain-specific implementation from replacing the
missing language machinery.

### Current generic foundation

- [x] Closed operations, inferred higher-order effect rows, source providers and
      explicit scalar host capabilities execute independently of ECS.
- [x] Source-declared effect families use space-applied types such as
      `State U32`; concrete instances are monomorphized with distinct
      operations.
- [x] Const composition, `:=` shadowing, `for` loops and scoped state resolvers
      execute in the generic core.
- [x] Tuples and homogeneous immutable arrays work across inference, bounded
      const evaluation, native transport, caches and Wasm. Array updates
      preserve aliases by copying; there is no uniqueness optimization yet.
- [x] Relative/mapped file imports preserve private scopes, nominal identities,
      and per-file diagnostics. `std/array` is an executable source module.
- [x] Named record construction/patterns and nested tuple patterns lower into
      ordinary algebraic data/products, including generic fields and captures.
- [ ] Record field access/update and array builders.
- [ ] Parameterized/type-valued descriptors and source-interpreted ECS effects.
- [ ] Composite capability bundles and a stable data-only state-transfer ABI.
- [ ] Source ECS/render libraries and project-wide incremental compilation.
- [ ] Reconnect the desktop host, restore `just study`, and exercise live
      reload.

These generic data/module milestones do not change the paused `just study` task
or revive the old compiler-specific runtime.

## Historical prototype verification (not current acceptance)

The checked items below describe the retired compiler-coupled baseline. They
must be verified again against the eventual source-defined ECS.

### Executable foundation

- [x] Real F32 syntax, type checking, const evaluation, native protocol, Wasm
      operations, host exports, and typed ECS storage, with cross-backend tests.
- [x] A documented prelude of useful functional, Maybe/Result, numeric, and
      game-math operations, exercised by applications and boundary tests.
- [x] Immutable resource input, entity lifecycle, and state transfer at the ECS
      provider boundary, with failed operations publishing no partial state.

## Application

- [x] Runnable Deno Desktop/WebGPU window with meshes, materials, textures,
      lighting, resizing, and explicit lifecycle cleanup.
- [x] Blot-driven camera orbit/zoom and scene updates.
- [x] Picking, selection, drag/move, placement/removal, scale, rotation, and
      material changes, tested as observable editor actions.
- [x] Fixed simulation steps, bounded catch-up, interpolation, focus-loss input
      clearing, and ordered one-shot event consumption.
- [x] Save/load with validated version/schema boundaries and immutable snapshot
      preservation; bad saves must not replace the live world.

## Live iteration

- [x] Source watching and background compilation while frames continue.
- [x] Successful edits change behavior without resetting world/camera/editor
      state; queued input survives the handoff.
- [x] Failed compile, incompatible layout, bad first render, and stale candidate
      completion leave the old game running and report a useful diagnostic.
- [x] Asset edits replace usable GPU assets; failed replacements retain the
      previous revision, and replaced resources are released.
- [x] Compiler caching/optimization improves measured compilation or edit-to-
      publication latency without bypassing typing, effects, or const budgets.

## Completion evidence

- [x] Reproducible run/check/test/benchmark commands under `case-study/ecs`,
      integrated into the root tasks/Justfile where useful.
- [x] Real compiler/Wasm integration tests, editor-state and reload tests,
      offscreen GPU pixel/picking tests, and a sustained frame/memory check.
- [x] Native window exercised and inspected, not inferred from offscreen tests.
- [x] Before/after compile measurements with matching feature sets, source and
      compiler hashes, cache counters, warmup/sample rules, and startup
      boundaries.
- [x] Root compiler/editor checks and Bend proofs pass after integration.
- [x] Final README documents controls, architecture, timings, resolved issues,
      remaining limits, and how to reproduce the evidence.

## Verified 2026-09-20

- `deno task check`: formatting/types, native and JS builds, 33 Bend laws,
  native constructor-ownership guards at 1/4 threads, 274 compiler tests, and
  six editor-configuration tests pass.
- `deno task check:editor`: both highlight fixtures pass (266 assertions), and
  all three editor specimens parse.
- `deno task test:study`: type/lint checks and 31 tests with seven game substeps
  pass, including actual filesystem watches and WebGPU pixel readback; exit 0.
- Native Wayland window: 3,600 frames completed; an additional 180-frame run
  captured the actual surface to `build/ecs-native.png`, visually inspected.
- `deno task bench:study`: seven samples per edit, two discarded warmups, exact
  clean-compile Wasm parity, and unchanged source/prelude hashes.
- [Matched-input compiler comparison](performance-baseline.md): seven-sample
  before/after reports, source/compiler hashes, and execution/reload assertions.

The [README](README.md) records commands, measured results, and explicit limits,
including scalar-only storage, serial scheduling, and Deno WebGPU/platform
caveats. Completion here applies to this case study, not the entire proposed
Blot language or full `gdev` library parity.
