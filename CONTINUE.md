# Working on Blot and Gdev

## Current frontier: All 57 Pre-Existing Gdev Tests Fixed (`1,396/1,396` Blot + `16/16` Native), Ink `346/346`, Pen Runtime `173/173` (23 November 2026)

All 57 pre-existing Gdev `pen test-blot` failures (down from 108 at `be489b79`
and 57 after Memory Model Phase 3 `1560e6a7`), the 14 broken `gdev-tech` native
tests, the `../ink` editor/scene-persistence failures, the `../pen`
`pen-runtime` Session-2 double-restore mismatch, and the pre-existing Session-2
post-restore viewport offset (`sprites[36].x`) are resolved and pushed to
`origin/main` across all four repositories.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `1560e6a7`) | Memory Model Phase 3 shim removal (`1560e6a7`), Concurrency Phases 1–5 (`67fc95b8`) |
| `../pen` | `f50b644` | Session-2 double-restore fix (`913d470`), Law #6 owned migration (`53a89f3`), auto exposure/grade (`8973e37` / `f50b644`) |
| `../ink` | `15ad905` | Editor `camera_previous` + snapshotted scene component writer (`056494f`), auto exposure/grade (`15ad905`), Phase 3 (`71b1809`) |
| `../gdev` | `6eb58fb` | All 57 pre-existing `pen test-blot` failures + `gdev-tech` syntax fixed (`92de220`, `c55f3a9`), exposure bindings (`6eb58fb`), Phase 3 (`a1aa3c9`) |

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
- **Single update operator `:=`:** Zero `=` store statements remain in Blot
  grammar, compiler, std, tests, benchmarks, `../pen`, `../ink`, or `../gdev`
  (`lent` and `=` shim completely removed).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `9856376bf704f4b97e7a18a4ee706bc8ff9259849d8faea574689cb02e1ea775`
    (source identity `701131807d477109d33bd003d5b7596764f526dbf15c8102ec95ec30c9cc63f8`)
  - `generated/compiler/blotc.gz` SHA-256:
    `2b318801346980fbdf5e66817fc3ba760592c09ce52bd2fa39cb3fe7412cb1e8`
    (3,612,879 bytes)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` (at `8973e37`) SHA-256:
    `0852a81e74ba4813f54f6a4c84811dc02efb84cf793e676ff2ece663a0f6f0e5`
- **Qualification gates:**
  - `blot2` (`1560e6a7`): `deno task test:compiler` exit 0 (`harness` **25/25**,
    `release-build` 89.2 s, `reference-direct` **2/2**,
    `reference-uniqueness` **199/199**, `reference-fixtures` **109/109**,
    `pack` OK, `guests` **1,091 passed, 0 failed, 76 ignored**);
    `deno fmt --check` (85 files), `deno check`, `deno task test:editor` (**6/6**).
  - `../pen` (`913d470` / `f50b644`): `pen-runtime` **173/173** (including
    `session_started_is_absent_from_live_input_recordings_and_state_replacements`);
    at `53a89f3`, `pen-codegen` **10/10**, `blot-host --test concurrency_phase4`
    **5/5**, `pen-plugins --test blot` **8/8**, and `pen kernels` **4/4**.
    Before `feat/exposure` (`15ad905`), `timeline::contract_tests` passed **5/6**
    (clearing the pre-existing `sprites[36].x` viewport offset; only
    `rewinds_among_the_crowd_give_the_first_packets` differed on unsaved
    `impact.finger_heat`). After `feat/exposure` (`15ad905`), all 6
    `timeline::contract_tests` currently differ on `exposure[13].cut`
    (`false` vs `true` on the first frame after any restore).
  - `../ink` (`056494f`): `pen test-blot` **346 passed, 0 failed** in 82
    modules; `ink/tools/native` Rust tests **177 passed, 0 failed** (at `5ad36c0`).
  - `../gdev` (`c55f3a9` / `6eb58fb`): `pen codegen --check` & `pen check` clean
    (`main.blot` with `entry kernel plan_routes`, `saved.json`,
    `devtools/main.blot`, 560 assets); `pen test-blot` at `c55f3a9`: **1,396
    passed, 0 failed** across 219 modules (**1,241/1,241** checks, **148/148**
    must-trap, **7/7** must-not-compile) plus `tools/tech` (`gdev-tech`)
    **16/16** native tests; `build_gdev.ts --timeout-ms 15000` at `6eb58fb`:
    `wasmBytes: 3,786,422`, `buildMs: 8.70 s`, `freshModules: 304`,
    `emittedFunctions: 5,021`; hardware Vulkan capture
    `run_pen.py --launch --hardware` exit 0 (`success: true`,
    `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-xiko0k1_/frame.png`,
    SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`).

## Remaining work

1. **Pen `timeline::contract_tests` rewind determinism (2 items):**
   - `../ink` `15ad905` (`feat/exposure`): `app.invalidate` sets `exposure.cut := true`
     on the first frame after every restore, causing `exposure[13].cut` (`false`
     vs `true`) to diverge across all 6 `timeline::contract_tests` rewinds.
   - `../gdev` `impact.finger` (`src/effects/impact.blot`): `21542ff` added
     multi-second `finger_heat` (`god_hand` `extra[8].w`) while leaving `impact`
     unsaved (`tests/hand_impact.blot:191` asserts `restored == 0.0`,
     `docs/reference.md:270`), conflicting with
     `rewinds_among_the_crowd_give_the_first_packets` at frame 210 (`0.18177669`
     vs `0.0`). Decide whether to persist `impact` (new section key, schema 26)
     for full rewind determinism or exempt transient feedback.
2. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main 565 ms `-O2` / 432 ms PGO; retained edits
   26–37 ms). Further `trees` / `view` / `write` runtime tuning can target the
   remaining 1.4–1.55× gap to Rust `-O3`.
3. **Memory model Phases 4–5** ([tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)):
   full value restriction for `let` and read-only references as prioritized.

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
