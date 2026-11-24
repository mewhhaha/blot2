# Working on Blot and Gdev

## Current frontier: Direct-Backend Tier 1 Runtime Optimizations & Unified Dynamic Arrays (24 November 2026)

Tier 1 direct-backend runtime optimizations (loop-invariant array-check hoisting,
scoped element-address reuse, and zero-allocation loop release elision) are
complete and qualified on top of the six-phase unified dynamic-array (`#[T]`)
and `purity.goose` retirement milestones:

- **Tier 1 direct-backend runtime optimizations (this commit, after `9de59b4c`):**
  - Extended `noStorageResize` in `direct/function_control.goose` to walk
    `Tag.match_`, `Tag.loop_`, and `Tag.pattern_bind` (budget 512) and pre-hoist
    loop-invariant `Tag.array` `ensureCheckedArray` calls once before `OP_loop`
    (skipping non-in-place array carries).
  - Reused pre-RHS element addresses in `direct/function_data.goose:indexedUpdate`
    whenever `noStorageResize` proves `info.value` cannot resize storage, and
    added a scoped `CheckedElem` cache (`function.goose`, `function_storage.goose`)
    gated exclusively to immutable user expression index sites (`readElement` /
    `indexedUpdate`) and invalidated alongside `CheckedArray`.
  - Added conservative `bodyNoAlloc` in `direct/function_control.goose` to skip
    per-iteration `markInto` and `escape_min_slot` global save/merge churn on
    non-allocating `for ever:` / `for` loops.
  - Regenerated `structural_adapters.goose` & `json_adapters.goose`, added
    executed-Wasm edge-case regression laws in `tests/guest/loop_hoist_execution.test.ts`,
    and re-recorded `compiler-goose/tests/fixtures/expected.json` (18 of 109
    fixtures changed, every one strictly smaller in `wasm_bytes`).
  - Measured climb on AMD Ryzen 7 7800X3D (bit-exact checksum parity,
    [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    Ink ECS cached query `9.30 → 2.31 ms` (**4.02×**), Pool direct
    `6.39 → 2.31 ms` (**2.76×**, `1.80×` of native Bevy `1.28 ms`), sparse
    filtered `0.422 → 0.138 ms` (**3.06×**, `1.62×` of native Bevy `0.085 ms`),
    `matmul_64` `1.15 → 0.289 ms` (**3.97×**), `merge_sort` `14.56 → 7.27 ms`
    (**2.00×**, `1.18×` of Rust `-O3` Wasm), `prime_sieve` `0.425 → 0.223 ms`
    (**1.91×**), and `particle_spark_simd` `0.842 → 0.745 ms` (**1.02×** of
    Rust `-O3` Wasm `0.729 ms`), while cold 6-kernel compile dropped to `13.3 ms`
    and Wasm shrank to `10,931` bytes (**138×** smaller than `rustc -O3`).
- **Phase 6 — Retire `check/purity.goose` & unconditional `mode = 2` const pools (`30899f4b`):**
  - Deleted `compiler-goose/src/check/purity.goose` (3,100+ lines) and its
    diagnostic codes (`spark_mutates_capture`, `kernel_mutates_context`,
    `process_mutates_global`, `purity_limit`) plus all `imm_pools` /
    `deeply_immutable_digest` plumbing across `direct/`, `compile.goose`,
    `wire_schema.goose`, and `reuse/`.
  - Because Phase 5 uniqueness bans all mutations of module `const` globals,
    every module `const` pool (and recursive box persisted inside one) is
    unconditionally deeply immutable and emits `mode = 2`
    (`static_pool_flag | live_flag`) in `direct/function_calls.goose`.
  - Regenerated adapters (`structural_adapters.goose`, `json_adapters.goose`)
    and re-recorded `compiler-goose/tests/fixtures/expected.json`: 100 of 109
    fixtures remained byte-identical; the 9 fixtures with module `const` pools
    changed only `wasm_sha256` (identical byte sizes, exit codes, and records).
  - Added positive `spark` deep-copy coverage for flat-element shared
    composites (`copy sw` on `*Holder { arr: #[U32] }`) in
    `tests/guest/concurrency_purity_phase1.test.ts`.
  - Compiler binary shrank by ~409 KiB (`8,496,320` → `8,087,056` bytes),
    release build dropped to `93.08 s`, `../ink` `pen test-blot` dropped from
    `1.7 s` → `1.1 s`, and `../gdev` `pen test-blot` dropped from `72.5 s` →
    `47.6 s` (34% faster).
- **Phase 5 — Enforce owned length mutation & drop `GrowArray`/`ResizeArray`/`seal` (`7da11d2d`):**
  - Removed `#[+T]`/`#[~T]`, `GrowArray`/`ResizeArray`, `seal`,
    `@storage.freeze`, `@storage.reserve`, and `Runtime.freeze` across parser,
    checker, core lowering, direct backend, `std/`, `host/derive.ts`, and tests.
  - Enforced `ownedInPlacePath` on `@storage.push`, `@storage.pop`,
    `@storage.truncate`, and `@simd.store` (supporting `deep` owned array-index
    paths such as `rows[i].owner` and row-polymorphic record fields while
    rejecting views, shared handles, `shell` elements, method dispatches,
    captured locals, borrowed parameters, and module `const`s), locking target
    base places across argument evaluation and weakening via `sharedIntoPlace`.
  - Added uniqueness laws `o01..o07` (206 total) and re-recorded
    `runtime.expected` (7707 bytes), `tests/uniqueness/expected.json`, and
    `tests/fixtures/expected.json`.
- **Phases 1–4 — Soundness fixes, backend hardening, & sibling migrations (`ebf2f026` + sibling checkouts):**
  - Closed `@storage.copy` nested-container ownership and `entry kernel`/
    `entry process` callable holes; hardened `Tag.array` backend invariants
    (stack-to-heap promotion, `fork` journaling, checked-array invalidation,
    `escape_min_slot` promotion); migrated `std/`, `../pen/examples/bounce`,
    `../ink`, and `../gdev` to unified dynamic `Array T` (`#[T]`) and
    `own`-threaded length mutation.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `9de59b4c`) | Tier 1 direct-backend runtime optimizations & refreshed charts (`this commit`), README SVG benchmark charts (`9de59b4c`), Consumer README & Rust/Bevy ECS comparison benchmarks (`7d87b31a`), Phase 6 `purity.goose` retirement (`30899f4b`), Phase 5 owned length mutation & unified `#[T]` (`7da11d2d`), Phases 1–2 soundness & backend hardening (`ebf2f026`) |
| `../pen` | `08e1224` | Unified `#[T]` migration in `blot-host` + `kernels_law6_tests` (`08e1224`); HRTF/EQ/reverb/haptics/text/netplay, GTAO/SSGI/ribbons, Hi-Z occlusion, Session-2 double-restore |
| `../ink` | `fc7259e` | Unified `#[T]` migration across `lib/`, `tests/`, `docs/` (`fc7259e`); Pen 250-lane bindings, SSGI/ribbons, terrain/water/foliage |
| `../gdev` | `017f8cd` | Unified `#[T]` migration across `src/`, `devtools/`, `tests/`, `test_support/`, `performance/` + synced `pen/` bindings (`017f8cd`); Moebius look default |

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
- **Unified dynamic arrays, single update `:=`, value restriction, and read-only references:**
  `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` for fixed-length);
  `#[+T]`/`#[~T]`/`GrowArray`/`ResizeArray`/`seal`/`@storage.freeze`/`@storage.reserve`
  and `=`/`lent`/`purity.goose` are retired; local `let` generalizes only on
  syntactic `func` values; `&T`, `&[T]`, `^T`, and `*T` are strictly read-only;
  `:=`, `@simd.store`, `@storage.push`, `@storage.pop`, and `@storage.truncate`
  enforce unique ownership (`ownedInPlacePath`), guaranteeing all module `const`
  pools are deeply immutable (`mode = 2`).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `9c3a57e59d66b0a8ca756a201ad7760249f6a82f004f4e36a6dd90762d12d2e8`
    (`8,099,608` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `c4787490772e6b474fcfe6075bbe868249983773e120e4e872d9613d0cf1a5a1`
    (`3,520,255` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `268d82af8ed6d858288df6f94cb4d37c7ab193f7ddf64fd27a1995f2a1e0a003`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 — `harness` (3.24 s),
    `release-build` (117.07 s), `reference-direct` **2/2** (`runtime` 7707 B,
    `writer` 352 B), `reference-uniqueness` **206/206**, `reference-fixtures`
    **109/109**, `pack` OK, `guests` **1,101 passed, 0 failed, 75 ignored**
    (26.02 s); `deno fmt --check` (85 files), `deno check`,
    `deno task test:editor` (**6/6**).
  - `../pen`: `cargo test -p blot-host` **40/40 passed** (29 unit + 5 concurrency
    + 3 owned_storage + 3 processes), `examples/bounce` `pen check` clean (0.06 s).
  - `../ink`: `pen test-blot` exit 0 against new `blotc-goose` — all Blot
    modules plus **245/245** native f64-reference tests passed (0 failed).
  - `../gdev`: `build_gdev.ts --timeout-ms 15000 --profile` exit 0
    (`success: true`, `wasmBytes: 4,093,381`, `buildMs: 704.7 ms`);
    `run_pen.py --launch --hardware` exit 0 (`success: true`,
    `screenshot_640x480: true`, `complete_render: true`,
    `compiled_wasm_unchanged: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-n6pdnv2o/frame.png`,
    SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`).

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
