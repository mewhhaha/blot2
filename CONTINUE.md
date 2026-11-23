# Working on Blot and Gdev

## Current frontier: Memory Model Phase 3 Complete — Borrowed-Mutator `=` Stores Removed Across All Four Repos (23 November 2026)

Phase 3 of [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md) is complete across
all four repositories (`blot2`, `../pen`, `../ink`, `../gdev`), on top of
Blot vNext Concurrency Phases 1–5 (`67fc95b8`). All `=` borrowed-mutator
stores are migrated to `own` / `:=`, the `=` compatibility shim
(`tag_store_stmt` / `UpdateInfo.store`) is deleted from the Blot compiler,
adapters and Baba host parser, `aliased_update` no longer suggests `=`, and
all four repositories are qualified against the shim-free optimized
`blotc-goose`.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Phase 3 & Prior Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `3dcc7d97`) | Shim removal (`tag_store_stmt` / `UpdateInfo.store`), regenerated adapters & Baba parser, updated reference records (`199/199` uniqueness, `109/109` fixtures), migrated tests/examples/benchmarks/docs; Concurrency Phases 1–5 at `67fc95b8` |
| `../pen` | `53a89f3` | `kernels_law6_tests.rs` migrated off `=` onto owned Ink/Gdev APIs (0 `=` stores); Concurrency Phases 4–5 at `15620ae` |
| `../ink` | `5ad36c0` | Phase 3 owned-mutator migration completed at `71b1809` (0 `=` stores); Concurrency Phases 4–5 at `2f15da1` |
| `../gdev` | `a1aa3c9` | Phase 3 owned-mutator caller migration completed at `a1aa3c9` (0 real `=` stores); Concurrency Phases 1–5 at `c4edf26` |

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
  are excluded from Save 26 and cleared on restore.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.
- **Single update operator `:=`:** Zero `=` store statements remain in Blot
  grammar, compiler, std, tests, benchmarks, `../pen`, `../ink`, or `../gdev`
  (`lent` and `=` shim completely removed).

### Verified Phase 3 Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `9856376bf704f4b97e7a18a4ee706bc8ff9259849d8faea574689cb02e1ea775`
    (source identity `701131807d477109d33bd003d5b7596764f526dbf15c8102ec95ec30c9cc63f8`)
  - `generated/compiler/blotc.gz` SHA-256:
    `2b318801346980fbdf5e66817fc3ba760592c09ce52bd2fa39cb3fe7412cb1e8`
    (3,612,879 bytes)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` SHA-256:
    `a2ebb35d4323400dfea2f711499afcbf6449ddd69634a92d4f3897e9affe4cf3`
- **Qualification gates:**
  - `blot2`: `deno task test:compiler` exit 0 (`harness` **25/25**,
    `release-build` 89.2 s, `reference-direct` **2/2**,
    `reference-uniqueness` **199/199** after retiring `h04`–`h06` store-only
    laws and updating `aliased_update`, `reference-fixtures` **109/109** after
    migrating 16 fixtures off `=`, `pack` OK, `guests` **1,091 passed, 0 failed,
    76 ignored**); `deno fmt --check` (85 files), `deno check`,
    `deno task test:editor` (**6/6**), and all 10 migrated benchmark `.blot`
    files compile cleanly.
  - `../pen` (`53a89f3`): `pen-codegen` **10/10**, `blot-host --test
    concurrency_phase4` **5/5**, `pen-plugins --test blot` **8/8**, and
    `pen kernels` **4/4** (all nine Law #6 witnesses `(a)`–`(i)` plus real Gdev
    `main.blot` `plan_routes` worker determinism across worker counts).
  - `../ink` (`5ad36c0`): `pen test-blot` **333 passed, 0 failed** in 81
    modules (`0.9 s`); `ink/tools/native` Rust tests **177 passed, 0 failed**.
  - `../gdev` (`a1aa3c9`): `pen codegen --check` & `pen check` clean (`main.blot`
    with `entry kernel plan_routes`, `saved.json`, `devtools/main.blot`, 557
    assets), `build_gdev.ts --timeout-ms 15000` pass (`wasmBytes: 3,748,553`,
    `buildMs: 6.70 s`, `freshModules: 302`, `emittedFunctions: 4,976`),
    `pen test-blot` **1,339 passed, 57 failed** across 219 modules (**zero
    regressions** vs. `2026-11-17-owned-runtime.raw.json.gz`; 51 previously
    failing tests fixed, all 57 remaining failures verified pre-existing,
    148/148 must-trap, 7/7 must-not-compile), and real hardware Vulkan capture
    `run_pen.py --launch --hardware` exit 0 (`success: true`,
    `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-4gq9mwv6/frame.png`,
    SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`).

## Remaining work

1. **Work through the remaining 57 pre-existing Gdev `pen test-blot` failures by name.**
   Down from 108 failures at `be489b79` and 81 at Phase 5 to **57** (`1,339
   passed, 57 failed` across 219 modules; start with
   `tests/salt_flight.blot: test_miners_deliver_through_the_cart_obstacle_and_nearby_piles_without_double_credit`).
   Compare affected tests and the 120-frame replay against the pinned reference
   ([raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-runtime.raw.json.gz)),
   and investigate the pre-existing Session-2 post-restore `viewport` offset in
   Pen `timeline::contract_tests` rewinds (`sprites[36].x` shifted by 480 px)
   and the pre-existing Session-2 double-restore mismatch in `pen-runtime`
   `session_started_is_absent_from_live_input_recordings_and_state_replacements`.
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
