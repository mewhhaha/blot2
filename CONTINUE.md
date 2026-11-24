# Working on Blot and Gdev

## Current frontier: Unified Dynamic Arrays & Purity Analyzer Retirement (24 November 2026)

All six phases of the unified dynamic-array (`#[T]` replacing `#[+T]`/`#[~T]`),
owned length-mutation, and `purity.goose` retirement plan are complete and
qualified across `blot2`, `std/`, `../pen`, `../ink`, and `../gdev`:

- **Phase 6 — Retire `check/purity.goose` & unconditional `mode = 2` const pools (this commit, after `7da11d2d`):**
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
| `blot2` | this commit (after `30899f4b`) | Consumer README & Rust/Bevy ECS comparison benchmarks (`this commit`), Phase 6 `purity.goose` retirement (`30899f4b`), Phase 5 owned length mutation & unified `#[T]` (`7da11d2d`), Phases 1–2 soundness & backend hardening (`ebf2f026`), Purity & session compile-speed optimization (`f650b6fb`), Council soundness hardening (`0fce6177`) |
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
    `a476a6da69d372c54756cfa158f060503827d806b2b012bcaba3c2e298780e8c`
    (source identity `d5f8808e02900ec0c9672ac87e8f0181076a4f1cce7c1ad30316947218f8fbca`, `8,087,056` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `d20b59eb2ca3cbc63d2568e9f4b240c0438134ddbdd86b2b3566774bb6ca12c2`
    (`3,513,022` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `9ce17d3dd112c4cdbab4fea5061529fa112b690c0d44949bde923d4554b6aa29`
- **Qualification gates:**
  - `blot2` (this commit): `harness` **25/25** (2.48 s), `release-build` 93.08 s,
    `reference-direct` **2/2** (`runtime` 7707 B, `writer` 352 B),
    `reference-uniqueness` **206/206**, `reference-fixtures` **109/109**,
    `pack` OK, `guests` **1,100 passed, 0 failed, 75 ignored** (19.69 s);
    `deno fmt --check` (85 files), `deno check`, `deno task test:editor` (**6/6**).
  - `../pen`: `cargo test -p blot-host` **40/40 passed** (29 unit + 5 concurrency
    + 3 owned_storage + 3 processes), `examples/bounce` `pen check` clean (0.06 s).
  - `../ink`: `pen test-blot` exit 0 — **425 passed, 0 failed** in 100 Blot
    modules (1.1 s; `376/376` checks, `45/45` must-trap, `4/4` must-not-compile)
    plus **244/244** `ink/tools/native` Rust tests.
  - `../gdev`: `pen check` clean (`main.blot` **0.42 s**, `devtools/main.blot`
    `2.95 s`, 563 assets); `pen test-blot` **1,398 passed** across all 219
    modules in **47.6 s** (0 compile errors, `148/148` must-trap, `7/7`
    must-not-compile; only the 4 pre-existing Moebius runtime checks in
    `tests/lighting_look.blot` and `tests/tutorial.blot` from `566f33f`);
    `build_gdev.ts --timeout-ms 15000 --profile`: `wasmBytes: 4,079,841`,
    `buildMs: 549.4 ms` (`check: 247.6 ms`, `lower: 29.6 ms`, `backend: 174.0 ms`),
    `freshModules: 307`, `sourceBytes: 3,088,471`, `emittedFunctions: 5,029`;
    `run_pen.py --launch --hardware` (NVIDIA Vulkan) exit 0 (`success: true`,
    `screenshot_640x480: true`, `complete_render: true`,
    `compiled_wasm_unchanged: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-dtmi5j3o/frame.png`,
    SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
    bit-for-bit identical to the prior hardware Vulkan baseline).

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
