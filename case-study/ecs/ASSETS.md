# Renderer and assets

`protocol.ts` is an explicit TypeScript presentation/input boundary, not a
generated Blot ABI. The host converts ECS state to immutable render frames; the
renderer does not implement game or editor decisions. The renderer, asset
formats, shaders, and sample assets were ported from the local `gdev`
experiment. No sibling repository is needed at runtime.

## Asset formats

Asset keys are relative to `assets/`. Absolute paths, parent escapes, and
resolved symlinks outside that directory are rejected.

- Mesh JSON contains `positions` and `normals` (three numbers per vertex), `uvs`
  (two per vertex), and triangle `indices`. Vertices become interleaved float32
  position/normal/UV records; indices become uint32. Meshes use CCW front faces.
- Material JSON names a `shader`, an optional `texture`, a four-channel `color`,
  and `lighting: "lit" | "unlit"`. Materials are opaque: color alpha must be
  one.
- Textures are PNG or JPEG, decoded with the pinned ImageScript Wasm codecs into
  independent RGBA bytes and uploaded as `rgba8unorm-srgb`.
- WGSL exposes `vertex` and `fragment` entry points using the layout in
  `assets/scene.wgsl`: scene uniforms in group 0; model/normal/material
  uniforms, texture, and sampler in group 1. This is a fixed renderer shader
  interface.

## Reload guarantees

The asset watcher debounces file events for 75 ms. A replacement is prepared
before publication. Parse errors, missing files, shader errors, invalid
textures, and GPU validation/allocation failures emit `AssetFailed` and keep the
last usable asset. Successful replacements emit `AssetReady`; revisions are
ordinary numbers.

Material publication also requires a usable shader and texture. A material
naming new missing or broken dependencies keeps the previous material and draw.
Editing a dependency retries dependent materials automatically, so fixing the
texture or shader publishes the waiting material without another material-file
edit. On the first load, an incomplete material is not drawn; it is not silently
replaced with a placeholder. These are dependency-readiness transactions, not a
filesystem-wide snapshot of simultaneous edits.

Superseded and stale mesh buffers/textures are destroyed. Pipeline/shader
objects have no explicit WebGPU destroy operation and are released by dropping
references. The store caches requested asset keys until `close()`; it does not
evict orphaned keys. Closing stops the watcher, drains pending loads, and
destroys resident GPU resources. Unexpected callback/invariant failures remain
fatal rather than being reported as ordinary asset parse errors.

## Picking

`renderer.pick(frame, { x, y })` uses the same viewport coordinate units as the
render target. It intersects the actual loaded triangles after the affine model
transform, applies front-face culling and camera clipping, and returns the
nearest hit. `distance` is measured in world units from the near clipping plane.
Camera and draw matrices are column-major; projection depth is WebGPU's 0..1
range.

An omitted `draw.entity` means noneditable geometry, not invisible geometry: a
ground hit can still occlude entities behind it. Selection outlines should carry
the same entity as the object they enclose. Blot receives the hit and decides
what to select or manipulate. Custom WGSL vertex displacement or fragment
discard is outside CPU-picking parity; picking uses the supplied mesh and model
transform.

## Verification

From the repository root:

```sh
deno check --config case-study/ecs/deno.json case-study/ecs/renderer.test.ts
deno test --config case-study/ecs/deno.json --allow-read --allow-write --allow-env=IMAGESCRIPT_WASM_SIMD case-study/ecs/renderer.test.ts
```

The tests use an offscreen WebGPU target and read pixels back. They cover
separate textured draws, depth, transformed picking, camera/viewport changes,
malformed and stale assets, watched edits, dependency transactions, buffer
disposal, and recovery after a rejected oversized draw list. A real WebGPU
implementation is required; software Vulkan adapters such as llvmpipe also work.
No tests silently skip the GPU path. Deno requires unscoped read/write
permission for the symlink-boundary test; ImageScript reads its pinned Wasm
codec from the Deno package cache.

The native-window integration follows the current
[Deno raw WebGPU documentation](https://docs.deno.com/runtime/desktop/webgpu/):
acquire a device before wrapping the window, resize the surface with the window,
get a fresh target view each frame, and present after submission.
