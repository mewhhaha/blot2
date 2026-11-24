# Working on Blot and Gdev

## Current frontier: Memory Model Phases 1–5 Complete & Council Soundness Hardening (24 November 2026)

All five phases of Memory Model A ([tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md))
and the post-Phase-5 multi-harness council review fixes are complete and verified
across `blot2`, `std`, `../ink`, and `../gdev`:

- **Phase 5 (`2de831a6`) — Read-only `&local`/`&field` (A4), purity & ownership:**
  - Lowered `Op.ref` to a 1-element stack owner with persistent `const`-pool
    support (`persistFlatAt`), fixed `purity.goose` `Op.ref` points-to edges,
    enforced ownership on `@simd.store` and `@storage.freeze`, unified `Op.link`
    borrow-return tracking, and stopped wildcard `let _ = ...` from spuriously
    killing owned values.
- **Council Review & Soundness Hardening (this commit, after `2de831a6`):**
  - Reviewed `71cf5629..2de831a6` with Claude Code (Opus 5.5: 1 verified `HIGH`)
    and Antigravity (Neon: 4 verified `HIGH`); Codex (Sol 6 Daybreak) was blocked
    by hardware-key session authentication. Every verified finding was fixed with
    regression tests:
  - **Loop outer-local weakening (`uniqueness.goose`, Opus 5.5):** Added
    `LoopOuter` / `recordLoopOuter` so non-carried outer locals aliased inside a
    loop body (e.g. `keep := xs`, `r := &xs`, or before `continue`) propagate
    across probe rollback and fixpoint retries for non-rebinding `@simd.store`.
  - **Deferred polymorphic closure captures (`direct/function*.goose`, Neon #1):**
    `captureValue` no longer prematurely monomorphizes polymorphic local
    `Tag.closure` captures at the outer closure creation site; it packs only
    their concrete captures (`packPolyCaptures`) and forwards their polymorphic
    entries via `polyCaptureKey`/`recordPolyCapture`/`restorePolyCapture` so
    nested polymorphic closures instantiate cleanly at every concrete layout.
  - **Strict `in_same_fn` `ownedInPlace` (`uniqueness.goose`, Neon #2):**
    Removed the `!in_same_fn` `self_.captured` bypass from `ownedInPlace`,
    blocking `@simd.store` and `@storage.freeze` on outer locals inside closures.
  - **Permanent freeze invalidation & zero-fallback `Op.freeze`
    (`uniqueness.goose`, Neon #3 & #4):** Non-moved `@storage.freeze` now
    permanently invalidates the frozen local or record field instead of returning
    a reversible borrow loan, and `Op.freeze` strictly requires `ownedInPlace`
    with zero fallback heuristics. Added a least-fixed-point `non_escaping_params`
    / `non_escaping_arity` scan (for saturated growable `.push`/`.truncate`,
    non-escaping local helpers, and pure effect-polymorphic downward closures)
    so helper patterns that mutate a `GrowArray` without escaping it keep the
    caller's `deep` uniqueness intact.
  - Updated `tests/guest/owned_render_copy_fixture.ts` for `../ink` `71bb1a3`'s
    new `render.FrameAccess` fields (`bone_matrices`, `morph_weights`, `motions`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `2de831a6`) | Council soundness hardening (5 verified `HIGH` fixes), Memory Model Phase 5 (`2de831a6`), Phase 4 (`9b589d5c`), Phase 3 (`1560e6a7`), Concurrency Phases 1–5 (`67fc95b8`) |
| `../pen` | `cef87ca` | TAA/motion blur/DoF protocol sync (`cef87ca`), standard surface lighting (`f58251f`), Session-2 double-restore (`913d470`), Law #6 owned migration (`53a89f3`) |
| `../ink` | `71bb1a3` | Pen 245-lane protocol (`71bb1a3`), 237-lane `bone_matrices`/`morph_weights` (`771480b`), audio/UI/net/streaming (`9c3078e`) |
| `../gdev` | `889b336` | Pen wire sync (`889b336`), shared lighting sync (`7d9f482`), volumetric fog (`e503911`) |

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
    `3602bc01d423b90533ae0a83e9f10cfefee7a89a9f3265dbf8f9deceba93fed0`
    (source identity `214ec3e3b37afc905ebbf5b439122e78ce203dff78d407464163f711e3d68443`)
  - `generated/compiler/blotc.gz` SHA-256:
    `831906a6a5119fd5fd313778e59839b307d0b07df67a8001a5ab2f41436504c0`
    (`3,623,375` bytes)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` SHA-256:
    `8d2037f38d4132fd257fd50193a6b6e58c0315de46d66bce358ee5431b0dae3f`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 (`harness` **25/25**,
    `release-build` 86.05 s, `reference-direct` **2/2**,
    `reference-uniqueness` **199/199**, `reference-fixtures` **109/109**,
    `pack` OK, `guests` **1,096 passed, 0 failed, 76 ignored**);
    `deno fmt --check` (85 files), `deno check`, `deno task test:editor` (**6/6**).
  - `../ink` (`71bb1a3`): `pen test-blot` exit 0 — **405 passed, 0 failed** in
    94 Blot modules (`356/356` checks, `45/45` must-trap, `4/4` must-not-compile)
    plus **234/234** native Rust tests.
  - `../gdev` (`889b336`): `pen check` clean (`main.blot` 6.97 s, `saved.json`,
    `devtools/main.blot` 0.72 s, 562 assets); `menu_focus.blot`,
    `performance_semantics.blot`, and `pickup_visibility.blot` all compile cleanly
    on release `blotc-goose` under strict `ownedInPlace` `@storage.freeze`;
    `build_gdev.ts --timeout-ms 15000`: `wasmBytes: 3,830,232`, `buildMs: 6.95 s`,
    `freshModules: 306`, `emittedFunctions: 5,053`; `run_pen.py --launch --hardware`
    (NVIDIA GeForce RTX 4080 SUPER Vulkan) exit 0 (`success: true`,
    `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-451z1ovf/frame.png`,
    SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`).
    (Full `../gdev` `pen test-blot` **1,398/1,398** + **16/16** `gdev-tech` passed
    on `2de831a6` prior to `../ink` `771480b`/`71bb1a3` adding `bone_matrices`/
    `morph_weights`/`motions` ahead of `../gdev/tests/minor_support/owned.blot`.)
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
