# Working on Blot and Gdev

## Current frontier: Purity Analyzer & Session Compile-Speed Optimization (24 November 2026)

All five phases of Memory Model A ([tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)),
the post-Phase-5 multi-harness council review fixes (`0fce6177`), and the
concurrency purity / session compile-speed optimization pass are complete and
verified across `blot2`, `std`, `../ink`, and `../gdev`:

- **Purity Analyzer & Session Fast-Path Optimization (this commit, after `0fce6177`):**
  - Eliminated the 6.5 s purity bottleneck that had regressed cold Gdev compiles
    to `6.96 s` and warm no-op/trivia builds to `3.31 s`, returning Gdev to
    subsecond cold builds (`391.7 ms` / `403.5 ms` median `-O2`, beating even
    the `432 ms` PGO target in [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md))
    with **byte-identical** Wasm output:
  - **Concurrency-root-only seeding & lazy unit registration (`purity.goose`):**
    Replaced eager whole-program `registerAllCallables` across all 306 units and
    422k Core nodes with lazy per-unit registration (`ensureUnitRegistered` /
    `lookupBodyFn`). Removed whole-game `exported_ctxs` (`main`) seeding in
    `analyzeInto`; after Memory Model Phases 1–5 (no `=`, no `lent`, unique `:=`
    and `@simd.store`), non-growable `const` globals cannot be mutated after
    startup unless they retain a handle/view to a growable global. A fast
    body-header scan collects growable globals and seeds immutable-typed pool
    initializers only when a mutable global exists (transitively flagging any
    const view/alias to a growable global).
  - **Asymptotic graph & dispatch indexing (`purity.goose`):** Added per-`(ctx, src)`
    indexed adjacency lists (`ctx_src_base_edges`, `ctx_src_written_edges`,
    `EdgeNode.next_src`) turning `stepLabelHead` / `reachHead` / `evalUpdate`
    from `O(E)` / `O(V·E)` to `O(out-degree)` / `O(V+E)`; O(1) hash-set
    summary dedup & comparison in `publishSummary`; per-function context lists
    (`fn_ctx_head` / `FnCtx.next_same_fn`); lazy O(1) associated-method and
    contract-implementation indexes (`assoc_by_name`, `impl_by_name`,
    `impl_by_contract`); O(1) `field_name_map`; memoized `isPureScalarCached`
    that skips dead fresh allocations/edges for pure-scalar `product`/`record`/
    `construct` nodes; and `usage`/`forall` unwrapping on scalar `associated` ops.
  - **Single-pass analysis & 0-change warm fast path (`direct.goose`,
    `compile.goose`, `reuse/{body_image,dependency_consumer,partial_dependency,zig_project_server_build}.goose`):**
    Passed precomputed `(ProgramInfo, imm_pools)` from `buildPrepared` into
    `emitTrackedWithAnalysis` / `emitWithAnalysis` (removing the duplicate
    `wire_schema::analyze` + `purity::analyzeInto` run on every cold and
    non-relocated build), and added a 0-changed-module fast path before
    re-running wire-schema/purity validation on unchanged cached revisions.
  - Added mutable-global view-alias regression coverage in
    `tests/guest/concurrency_purity_phase1.test.ts` and synced
    `tests/guest/owned_render_copy_fixture.ts` with `../ink` `3df2bff`
    (`ribbons`, `haptics` on `render.FrameAccess`).
- **Council Soundness Hardening (`0fce6177`) & Memory Model Phase 5 (`2de831a6`):**
  - Fixed all 5 verified `HIGH` findings from Opus 5.5 + Neon (loop outer-local
    weakening in `uniqueness.goose`, deferred polymorphic closure captures in
    `direct/function*.goose`, strict `in_same_fn` `ownedInPlace`, permanent
    freeze invalidation & zero-fallback `Op.freeze` with `non_escaping_params`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `0fce6177`) | Purity & session compile-speed optimization (`6.96 s` → `0.40 s` cold Gdev), Council soundness hardening (`0fce6177`), Memory Model Phase 5 (`2de831a6`), Phase 4 (`9b589d5c`), Phase 3 (`1560e6a7`), Concurrency Phases 1–5 (`67fc95b8`) |
| `../pen` | `77bf4e1` | HRTF/EQ/reverb/haptics/text/netplay (`77bf4e1`), GTAO/SSGI/ribbons (`6efa720`), Hi-Z occlusion (`be951ce`), Session-2 double-restore (`913d470`) |
| `../ink` | `3df2bff` | Pen 250-lane bindings (`3df2bff`), 247-lane SSGI/ribbons (`84c79a2`), terrain/water/foliage (`e399ff7`) |
| `../gdev` | `f94a42c` | Pen 250-lane bindings (`f94a42c`), 247-lane sync (`49703bc`), 245-lane sync (`889b336`) |

### Hard Invariants Preserved
- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (zero extra
  exports; Page-0 offset `640` carries `arena_oom_flag`; optional
  `blot:finish_invocation` / `blot:kernels` / `blot:processes`).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15`
  uses unambiguous `request == 0` host→guest provenance (`CAP`, `CTL`,
  `BATCH_ERR`, `BATCH_OK`), strips live-only unrecorded `CAP` before `Recorded`
  (preserving old-Pen `service <= 14` replay compatibility), filters
  `request == 0` events in `ink/lib/pen/host.blot` before `app.advance`, and
  normalizes render packets via `pen_protocol::canonical_render_packet`
  (updating header slots `134` `SERVICE_COUNT` and `135` `SERVICE_LANES`).
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries`
  are excluded from Save 26 and cleared on restore; `world_storage.blot`
  preserves `input` (key 3) and `god_hand` (key 114), canonical scene section
  order, and immediate `restore_scene` with `app.hold_frame` on `restore_stash`.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.
- **Single update operator `:=`, value restriction, and read-only references:**
  Zero `=` store statements remain (`lent` and `=` shim removed in Phase 3);
  local `let` generalizes only on syntactic `func` values (Phase 4); `&T`,
  `&[T]`, `^T`, and `*T` are strictly read-only, `&local`/`&field` lower in the
  direct backend, and `@simd.store` / `@storage.freeze` enforce ownership
  (Phase 5).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `9a9de0aca6d5e43cb0152822c5ef1a4b5e21da311d832f0cccf697522777e444`
    (source identity `c6d027bb69d573a6385479d501a8059f956c6f150c89f2778c97d8d9fe1c315c`, `8,496,320` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `5a3fdd310a388e8ba08f3c61fec9ff5416485df4c78ab80b7acd8023fae6e7a8`
    (`3,650,255` bytes)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` SHA-256:
    `1bcc42a008146034fdea1960e64d2487438a4b78f0fb912709cf66fa102c5acb`
- **Gdev compile-time before/after (`../gdev` `f94a42c`, 306 modules, 2.98 MB, 5,059 funcs, byte-identical `3,842,468` B Wasm `8454653cde8ca19f...`):**
  - Cold build: `6,963.7 ms` (`backend: 6,719.2 ms`) → **`391.7 ms`** (`backend: 152.9 ms`; 3-run median **`403.5 ms`**, **17.8× faster**)
  - Warm no-op (`0/306`): `3,304.6 ms` (`backend: 3,289.8 ms`) → **`16.5 ms`** (`backend: 0.3 ms`, **200× faster**)
  - Warm trivia (`1/305`): `3,311.3 ms` (`backend: 3,290.3 ms`) → **`45.3 ms`** (`backend: 25.3 ms`, **73× faster**; leaf trivia **`40.7 ms`**)
  - Warm body edit (`1/305` `src/main.blot`): `6,697.5 ms` (`backend: 6,678.1 ms`) → **`170.3 ms`** (`backend: 151.2 ms`, **39× faster**, byte-identical `a49f17f91a74c05e...`)
- **Qualification gates:**
  - `blot2` (this commit): `harness` **25/25**, `release-build` 85.74 s,
    `reference-direct` **2/2**, `reference-uniqueness` **199/199**,
    `reference-fixtures` **109/109**, `pack` OK, `guests` **1,096 passed,
    0 failed, 76 ignored** (16.22 s); `deno fmt --check` (85 files),
    `deno check`, `deno task test:editor` (**6/6**).
  - `../ink` (`3df2bff`): `pen test-blot` exit 0 — **408 passed, 0 failed** in
    95 Blot modules (1.1 s; `359/359` checks, `45/45` must-trap,
    `4/4` must-not-compile) plus **237/237** native Rust tests.
  - `../gdev` (`f94a42c`): `pen check` clean (`main.blot` **0.40 s** unchanged,
    `saved.json`, `devtools/main.blot` 0.69 s, 562 assets);
    `build_gdev.ts --timeout-ms 15000 --profile`: `wasmBytes: 3,842,468`,
    `buildMs: 399.5 ms` (`total_us: 392.0 ms`, `backend: 153.8 ms`),
    `freshModules: 306`, `emittedFunctions: 5,059`;
    `run_pen.py --launch --hardware` (NVIDIA GeForce RTX 4080 SUPER Vulkan)
    exit 0 (`success: true`, `screenshot_640x480: true`,
    `compiled_wasm_unchanged: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-uh6es9_w/frame.png`,
    SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`).
  - `../pen` (historical `913d470` / `f50b644` / `53a89f3`): `pen-runtime`
    **173/173**, `pen-codegen` **10/10**, `blot-host --test concurrency_phase4`
    **5/5**, `pen-plugins --test blot` **8/8**, `pen kernels` **4/4**.

## Remaining work

1. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main 565 ms `-O2` / 432 ms PGO; retained edits
   26–37 ms). Further `trees` / `view` / `write` runtime tuning can target the
   remaining 1.4–1.55× gap to Rust `-O3`.
2. **Pen `timeline::contract_tests` rewind determinism (2 items):**
   - `../ink` `15ad905` (`feat/exposure`): `app.invalidate` sets `exposure.cut := true`
     on the first frame after every restore, causing `exposure[13].cut` (`false`
     vs `true`) to diverge across all 6 `timeline::contract_tests` rewinds.
   - `../gdev` `impact.finger` (`src/effects/impact.blot`): `21542ff` added
     multi-second `finger_heat` (`god_hand` `extra[8].w`) while leaving `impact`
     unsaved (`tests/hand_impact.blot:191` asserts `restored == 0.0`,
     `docs/reference.md:270`), conflicting with
     `rewinds_among_the_crowd_give_the_first_packets` at frame 210 (`0.18177669`
     vs `0.0`). Decide whether to persist `impact` or exempt transient feedback.

## Pinned history & evidence

Superseded checkpoint narratives from 17–23 November 2026 (including Concurrency
vNext Phases 1–5 at `git show 67fc95b8:CONTINUE.md`, Checkpoint F compiler
pruning / Batch 1B–1D at `git show d0ae1652:CONTINUE.md`, and earlier
checkpoints at `git show a1a117b5:CONTINUE.md`) are preserved in pinned Git
history and in their dedicated task and measurement records:

- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
