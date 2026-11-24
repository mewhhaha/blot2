# Working on Blot and Gdev

## Current frontier: Memory Model Phases 1–5 Complete — Read-Only References (A4) & Remaining In-Place Ownership Paths (24 November 2026)

All five phases of Memory Model A ([tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md))
are now complete and verified across `blot2`, `std`, `../ink`, and `../gdev`:

- **Phase 5 (`direct/function_storage.goose`, `direct/function_calls.goose`,
  `check/purity.goose`, `check/uniqueness.goose`):**
  - Implemented read-only `&local` / `&record.field` (`Op.ref`, A4) in the
    direct backend (1-element stack owner with `noteStoreToSlot`, `writeFlat`,
    and persistent `const`-pool support in `persistFlatAt` for stack-backed
    `Ref`/`Link`/`View`).
  - Fixed `purity.goose` `Op.ref` points-to modeling (`f --LBL_ELEM--> target`)
    so `@storage.load (&pool)` cannot bypass `spark`/`kernel` purity checks.
  - Enforced unique ownership on `@simd.store` and `@storage.freeze` (`seal`) in
    `uniqueness.goose`, unified `Op.link` (`^pool[i]`) with `Op.view`/`Op.ref`/
    `Op.at` borrow-and-return-at-last-read tracking, and prevented wildcard
    `let _ = ...` from spuriously killing owned values.
  - `std`, `../ink`, and `../gdev` required zero source changes.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `9b589d5c`) | Memory Model Phase 5 read-only references (A4) & `@simd.store`/`@storage.freeze` ownership, Phase 4 (`9b589d5c`), Phase 3 (`1560e6a7`), Concurrency Phases 1–5 (`67fc95b8`) |
| `../pen` | `f58251f` | Standard surface lighting (`f58251f`), bloom glare (`4916c95`), Session-2 double-restore (`913d470`), Law #6 owned migration (`53a89f3`) |
| `../ink` | `891f396` | Test/inventory cleanup (`891f396`), lighting/clear-coat (`75e013f`, `a89fd5d`), auto exposure/grade (`15ad905`), Phase 3 (`71b1809`) |
| `../gdev` | `7d9f482` | Shared lighting sync (`7d9f482`), volumetric fog (`e503911`), firepit/snowman finger status (`5a717c7`), all `pen test-blot` + `gdev-tech` clean |

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
    `077d87db8c2c20070bf0ac72537fb9c1726101b89692d65655d73cd2c81dbb6c`
    (source identity `0776bd250cd19900404eefa0e8292a4da7c50f2de7e0754e70a5ef9c73b04fbe`)
  - `generated/compiler/blotc.gz` SHA-256:
    `a021d47dfc9f365a068c9a081645459a5190a8ed457b5083613a2d3a0fc4cbae`
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` SHA-256:
    `c7223d469ca8055f5b7b84aa42d59fd9e4a27faf5036b9d1ba2761fc2172e807`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 (`harness` **25/25**,
    `release-build` 84.44 s, `reference-direct` **2/2**,
    `reference-uniqueness` **199/199**, `reference-fixtures` **109/109**,
    `pack` OK, `guests` **1,095 passed, 0 failed, 76 ignored**);
    `deno fmt --check` (85 files), `deno check`, `deno task test:editor` (**6/6**).
  - `../ink` (`891f396`): `pen test-blot` **379 passed, 0 failed** in 90 Blot
    modules (`45/45` must-trap, `4/4` must-not-compile).
  - `../gdev` (`7d9f482`): `pen check` clean (`main.blot`, `saved.json`,
    `devtools/main.blot`, 562 assets); `pen test-blot`: **1,398 passed,
    0 failed** across 219 modules (**1,243/1,243** checks, **148/148**
    must-trap, **7/7** must-not-compile) plus `tools/tech` (`gdev-tech`)
    **16/16** native tests; `build_gdev.ts --timeout-ms 15000`:
    `wasmBytes: 3,813,902`, `buildMs: 7.06 s`, `freshModules: 306`,
    `emittedFunctions: 5,042`; `run_pen.py --launch --hardware` exit 0
    (`success: true`, `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-e3n13cel/frame.png`,
    byte-identical SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`).
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
