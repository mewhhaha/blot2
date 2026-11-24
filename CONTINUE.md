# Working on Blot and Gdev

## Current frontier: Direct-Backend Tier 2 Runtime Optimizations (2A–2F) & Unified Dynamic Arrays (24 November 2026)

Tier 2 direct-backend runtime optimizations (2A–2F: closure inlining in
`@array.generate`/`std/array.generate`, local F32 canonical-NaN elision, `spark`
SIMD pre-splatting & in-place destination reuse, guard-derived bounds & `ifNode`
check preservation, byte-packed `#[Bool]` arrays, and auto-vectorized in-place
range `for` loops) are complete and qualified on top of Tier 1 (`58adc750`) and
the six-phase unified dynamic-array (`#[T]`) milestones:

- **Tier 2 direct-backend runtime optimizations (this commit, after `58adc750`):**
  - **2A (Generate closure inlining):** Inlined direct syntactic closures
    `(func i => body)` in `@array.generate` and 2-arg wrappers like
    `std/array.generate` (`direct/function_storage.goose`,
    `direct/function_calls.goose`), eliminating `call_indirect` in
    `ecs_spawn_batch` (0 `call_indirect` in the 9-module Ink ECS Wasm).
  - **2B (Local F32 NaN-canonicalization elision):** Added `scanNanUses` /
    `bindingIgnoresNanPayload` (`direct/function.goose`) to omit per-`let`
    `0x7fc00000` NaN normalization on register-only `F32` locals whose uses are
    strictly `isCanonicalF32Consumer`, while preserving exact `0x7fc00000`
    canonicalization at every return, bitcast, store, call, or join boundary.
  - **2C (`spark` SIMD polish & in-place buffer reuse):** Hoisted loop-invariant
    outer scalar splats and `0x7fc00000` NaN vector outside `OP_loop`, dropped
    dead `iter_vlocal` when unused, and added uniquely-owned destination reuse
    (`unique_owned` + `scanOwnedUses` + runtime `start == 0 && count == cand_len`
    fast path in `direct/function_spark.goose` & `direct/function_control.goose`).
  - **2D (Guard-derived bounds & `ifNode` check preservation):** Recorded
    `CheckedBound` after early-exit guards (`if m >= limit: break`), preserved
    `range.end_local` on local `U32` loop ends, and preserved surviving pre-`if`
    `CheckedArray` entries across `ifNode` branch merges.
  - **2E (Byte-packed `#[Bool]` arrays):** Lowered bare `#[Bool]` elements to
    1-byte stride (`i32.load8_u` / `i32.store8`, single `memory.fill`, 4-wide
    `v128` SIMD load/store via `v128.load32_zero` + `extend_low_*_u` and
    `narrow_*_u` + `v128.store32_lane`, ABI 8 4-byte packet conversion in
    `fromPacket`/`toPacket`, and `FlatNumeric` loops in `function_kernels.goose`)
    while preserving `flatBytes(Tag.boolean) == 4` inside records/tuples/variants.
  - **2F (In-place range `for`-loop auto-SIMD):** Added `tryEmitVectorForLoop`
    in `direct/function_spark.goose` to vectorize simple in-place range `for`
    loops (`dst[dst_off + col] := vec_expr(...)`) into 4-wide `v128` SIMD with
    runtime bounds, non-wrapping, and strict alias/disjointness guards feeding
    into the scalar tail loop.
  - **Host deadlock fix:** Fixed `runFixed`'s `triggerFatalAbort` in
    `host/kernels.ts` to drain `fixedCopyQueue` (`convertQueueToDiscard()`),
    eliminating an intermittent deadlock in `Law #4(b)-(f)` (`byobFaultPool`).
  - Regenerated `structural_adapters.goose` & `json_adapters.goose`, added
    executed-Wasm regression laws in `tests/guest/tier2_opt_execution.test.ts`,
    and re-recorded `compiler-goose/tests/fixtures/expected.json` (24 of 109
    fixtures changed, every one strictly smaller or fewer functions).
  - Measured climb on AMD Ryzen 7 7800X3D (bit-exact checksum parity,
    [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `matmul_64` `0.289 → 0.053 ms` (**5.4× over Tier 1; 21.7× over baseline; 1.66× of Rust `-O3` Wasm**),
    `mandelbrot_f32` `4.88 → 3.20 ms` (**1.53×; 0.98× of Rust `-O3` Wasm `3.24 ms`, 0.77× of native `4.13 ms`**),
    `particle_spark_simd` `0.740 ms` (**0.95× of Rust `-O3` Wasm `0.775 ms`**),
    `prime_sieve` `0.223 → 0.170 ms` (**1.31×; 1.45× of Rust `-O3` Wasm**),
    `merge_sort` `7.11 ms` (**1.20× of Rust `-O3` Wasm**),
    Ink SoA + `spark` SIMD `0.638 → 0.428 ms` (**1.49×; 2.9× faster than native Bevy AoS `1.25 ms`**),
    Ink Pool direct `2.31 → 2.07 ms`, Ink cached query `2.31 → 2.11 ms`,
    full-world snapshot `9.1 µs` (**24× faster than Bevy**), structural churn
    `34.5 µs` (**2.4× faster**); Wasm shrank further to `10,879` B (6 kernels,
    **138×** smaller than Rust `-O3`) and `53,231` B (9-module Ink ECS).
- **Tier 1 direct-backend runtime optimizations (`58adc750`):**
  - Extended `noStorageResize`, pre-hoisted loop-invariant `ensureCheckedArray`
    checks, reused pre-RHS element addresses via scoped `CheckedElem`, and added
    `bodyNoAlloc` loop mark/release elision (`tests/guest/loop_hoist_execution.test.ts`).
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
| `blot2` | this commit (after `58adc750`) | Tier 2 direct-backend runtime optimizations 2A–2F & `runFixed` abort fix (`this commit`), Tier 1 loop-hoist runtime optimizations (`58adc750`), README SVG benchmark charts (`9de59b4c`), Consumer README & Rust/Bevy ECS comparison benchmarks (`7d87b31a`), Phase 6 `purity.goose` retirement (`30899f4b`), Phase 5 owned length mutation & unified `#[T]` (`7da11d2d`) |
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
    `0e46193013871d19b01147176f92e5b902c7c95dae0373ef5e900c6947a3a77f`
    (`8,191,328` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `88313e73b2e5b42eefc776c396cac82f4b05f4296a778e9a1d8bf643e1f8e050`
    (`3,556,553` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `268d82af8ed6d858288df6f94cb4d37c7ab193f7ddf64fd27a1995f2a1e0a003`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 — `harness` (2.46 s),
    `release-build` (87.97 s), `reference-direct` **2/2** (`runtime` 7707 B,
    `writer` 352 B), `reference-uniqueness` **206/206**, `reference-fixtures`
    **109/109**, `pack` OK, `guests` **1,104 passed, 0 failed, 75 ignored**
    (16.20 s); `deno fmt --check` (85 files), `deno check`,
    `deno task test:editor` (**6/6**).
  - `../pen`: `cargo test -p blot-host` **40/40 passed** (29 unit + 5 concurrency
    + 3 owned_storage + 3 processes), `examples/bounce` `pen check` clean (0.06 s).
  - `../ink`: `pen test-blot` exit 0 against new `blotc-goose` — all Blot
    modules plus **245/245** native f64-reference tests passed (0 failed).
  - `../gdev`: working tree had active uncommitted user edits across 175 files
    (including `src/effects/shader_styles.blot` failing `function_return_required`,
    preserved untouched); Tier 1 (`58adc750`) hardware frame checkpoint on clean
    `017f8cd` remains `build/storage-integration/gdev-one-frame/attempt-n6pdnv2o/frame.png`
    (SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`). Re-run
    `build_gdev.ts` + `run_pen.py --launch --hardware` once `../gdev`'s active
    `shader_styles.blot` edits compile cleanly.

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
