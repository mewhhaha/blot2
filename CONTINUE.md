# Working on Blot and Gdev

## Current frontier: Memory Model Phase 4 Complete — Full Value Restriction for `let` (23 November 2026)

Memory Model Phase 4 is implemented and verified across all four repositories:
local `let` bindings now generalize only when bound to a syntactic `func`
(`compiler-goose/src/check/check.goose::functionValue`), while non-`func`
`let` bindings still settle pending field requirements via `solveFields`.
A latent direct-backend capture bug surfaced by nested polymorphic local
`func`s (`compiler-goose/src/direct/function_calls.goose::captureValue`) is
also fixed so each instantiation of an enclosing polymorphic closure resolves
and builds captured polymorphic locals against its own body and environment
without polluting `f`'s monomorphic bindings. `std`, `../ink`, and `../gdev`
required zero source changes.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `71cf5629`) | Memory Model Phase 4 value restriction + polymorphic capture fix, Phase 3 (`1560e6a7`), Concurrency Phases 1–5 (`67fc95b8`) |
| `../pen` | `4916c95` | Bloom glare (`4916c95`), Session-2 double-restore (`913d470`), Law #6 owned migration (`53a89f3`), auto exposure/grade (`8973e37` / `f50b644`) |
| `../ink` | `15ad905` | Auto exposure/grade (`15ad905`), editor `camera_previous` + snapshotted scene component writer (`056494f`), Phase 3 (`71b1809`) |
| `../gdev` | `5a717c7` | Firepit/snowman finger status (`5a717c7`), exposure bindings (`6eb58fb`), all 57 `pen test-blot` failures + `gdev-tech` fixed (`92de220`, `c55f3a9`) |

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
- **Single update operator `:=` & value restriction:** Zero `=` store
  statements remain (`lent` and `=` shim removed in Phase 3); local `let`
  generalizes only on syntactic `func` values (Phase 4).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `448317454e99283690048828c604f36cfcfb042bfc5e46fadc70e9e97e88904b`
    (source identity `e5193634d544ba48a581987bfe1f484c1ea2736d13ed19e86d914255512b9727`)
  - `generated/compiler/blotc.gz` SHA-256:
    `c8c325392532fb77ec6d8ee5d06cbeb2aaca96a86a0cadeb22c17d32bb23b9c4`
    (3,615,457 bytes)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` SHA-256:
    `1341e8a385b7f7943903024ae7187d70060bc7205d9a77d541869894198d9e9c`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 (`harness` **25/25**,
    `release-build` 88.06 s, `reference-direct` **2/2**,
    `reference-uniqueness` **199/199**, `reference-fixtures` **109/109**,
    `pack` OK, `guests` **1,092 passed, 0 failed, 76 ignored**);
    `deno fmt --check` (85 files), `deno check`, `deno task test:editor` (**6/6**).
  - `../ink` (`15ad905`): `pen test-blot` **347 passed, 0 failed** in 82
    modules + **190 passed, 0 failed** native Ink Rust tests.
  - `../gdev` (`5a717c7`): `pen check` clean (`main.blot`, `saved.json`,
    `devtools/main.blot`, 562 assets); `pen test-blot`: **1,398 passed,
    0 failed** across 219 modules (**1,243/1,243** checks, **148/148**
    must-trap, **7/7** must-not-compile) plus `tools/tech` (`gdev-tech`)
    **16/16** native tests; `build_gdev.ts --timeout-ms 15000`:
    `wasmBytes: 3,799,962`, `buildMs: 7.05 s`, `freshModules: 306`,
    `emittedFunctions: 5,032`; `run_pen.py --launch --hardware` exit 0
    (`success: true`, `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-w9zoy3qc/frame.png`,
    byte-identical SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`).
  - `../pen` (historical `913d470` / `f50b644` / `53a89f3`): `pen-runtime`
    **173/173**, `pen-codegen` **10/10**, `blot-host --test concurrency_phase4`
    **5/5**, `pen-plugins --test blot` **8/8**, `pen kernels` **4/4**.

## Remaining work

1. **Memory model Phase 5** ([tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)):
   read-only references (`A4`) and retiring references as a write path (audit
   remaining `Ref`/`Link` write paths and update docs/tests).
2. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main 565 ms `-O2` / 432 ms PGO; retained edits
   26–37 ms). Further `trees` / `view` / `write` runtime tuning can target the
   remaining 1.4–1.55× gap to Rust `-O3`.
3. **Pen `timeline::contract_tests` rewind determinism (2 items):**
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
