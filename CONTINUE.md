# Working on Blot and Gdev

## Current frontier: Blot vNext Concurrency, SIMD `spark`, `KernelPool`, `Processes` & Pen/Gdev Bridge — Phases 1–5 Complete (23 November 2026)

All five phases of [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md)
(`v38`, Laws #1–#6) are implemented, qualified end to end across all four
repositories (`blot2`, `../pen`, `../ink`, `../gdev`), and pushed to
`origin/main`.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Phase 1–5 Rollout Commits |
|---|---|---|
| `blot2` | `d0ae1652` (+ this `CONTINUE.md` update) | Phase 1 `e2b8461d`, Phase 2 `f1f3daff`, Phase 3 `af5f0d96`, Phase 4 `bf995c86`, Phase 5 `d0ae1652` (`std/kernel.blot`, `tests/guest/kernel_std.test.ts`) |
| `../pen` | `b7cba0c` (`blot-host` cc-probe v6) | Phase 4 `333cbc5`, Phase 5 `15620ae` (`service::KERNEL = 15`, `KernelService`, `canonical_render_packet`, `pen-web` kernels, Law #6) |
| `../ink` | `2f15da1` | Phase 4 `64f9f4c`, Phase 5 `2f15da1` (`lib/kernel_transport.blot`, `host.measure_frame_floats`, `request == 0` lane separation; `lib/services.blot` untouched) |
| `../gdev` | `c4edf26` | Phase 1 `837f26e`, Phase 4 `8cf382d`, Phase 5 `c4edf26` (`entry kernel plan_routes`, shared `colony_paths.build_mesh_into`, query-keyed prewarmed routes, `tests/kernel_routes.blot`) |

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
- **Save Schema 26:** `../ink/lib/services.blot` (`max_id = 16,777,215`)
  remains **100% untouched**; ephemeral `KernelTransport` and Gdev
  `prewarm_entries` are excluded from Save 26 and cleared on restore.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.

### Verified Phase 5 Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `8aad01ec27f825a50c4f10f4a3cdcafed662a6a995d8bb21bddbc427598fe887`
    (source identity `c37395b1256943f8a1b957bcbaeddf2eaa81bb9fcaf6eb367c09748417b19c5c`)
  - `std/prelude.blot` SHA-256:
    `cc908f217d65f9adb519c0df21ed57006544eb2ea896b397747bdc32655242c9`
  - `../pen/target/release/pen` (`15620ae`) SHA-256:
    `2282282228547c81ec76178cb67732e24d7b1f3b99c44fe4629d2f340d0646c0`
- **Qualification gates:**
  - `blot2` (`d0ae1652`): `deno fmt --check` (85 files), `deno check`,
    `deno task test:editor` (6/6), `deno task check:editor` (10/10 parses,
    19/19 highlight suites), concurrency & `std/kernel` suite **16/16 passed**
    (`kernel_std.test.ts`, `spark_spawn_execution.test.ts`,
    `spark_copy_execution.test.ts`, `process_replay_execution.test.ts`,
    `concurrency_phase4.test.ts`).
  - `../pen` (`15620ae`): `pen-codegen` **10/10**, `pen-protocol` unit
    **11/11**, `pen-runtime mods` **5/5** (incl. `splice_enforces_max_events_bound`),
    `pen kernels` **4/4** (all nine Law #6 witnesses (a)–(i), real Gdev
    `main.blot` `plan_routes` bit-identical across `workers = 0, 1, 2, 4`, and
    Worker ON vs. Worker OFF bit-identical Save-26 & `canonical_render_packet`
    equivalence), `pen services` (**6/6** + `services::replay` **1/1** on fresh
    exported Gdev bundle), `pen net::tests` (**3/3** incl.
    `two_peers_play_the_game_over_udp` on fresh exported Gdev bundle),
    `pen --no-default-features` check clean, `pen-web --target wasm32-unknown-unknown`
    check clean.
  - `../ink` (`2f15da1`): `ink/tools/native` `cargo +1.99.0 test` **113/113
    passed, 0 failed** (`lib/services.blot` 0 diff; untracked
    `tools/native/target/` preserved).
  - `../gdev` (`c4edf26`): `pen codegen --check` & `pen check` clean (`main.blot`
    with `entry kernel plan_routes`, `saved.json`, `devtools/main.blot`, 557
    assets), `build_gdev.ts --timeout-ms 15000` pass (`wasmBytes: 3,532,591`,
    `buildMs: 9.61 s`), `pen test-blot` **zero new failing test identities vs.
    pinned pre-Phase-1 baseline (`a13c3f17c65b`: 81 pre-existing failures;
    1,315 passed across 219 modules incl. 3/3 new `tests/kernel_routes.blot`
    tests and 27/27 devtools tests)**, and real hardware Vulkan capture
    `run_pen.py --launch --hardware` exit 0 (`success: true`,
    `screenshot_640x480: true`, visually inspected
    `build/storage-integration/gdev-one-frame/attempt-c4blf46t/frame.png`).

## Remaining work

1. **Migrate remaining borrowed-mutator `=` stores (`tasks/MEMORY_MODEL.md`
   Phase 3) and remove the ~25-LOC `=` compatibility shim.**
   `lent` is completely retired (0 occurrences across all four repos), and
   `#[+T]` / `#[~T]` ownership checks cover array length changes. The remaining
   store compatibility shim (`tag_store_stmt` / `UpdateInfo.store`) is kept
   solely for **487 borrowed-mutator functions / 996 store lines across 212
   files** in `../ink` and `../gdev`, plus `../pen/crates/pen-codegen/src/blot.rs:414`
   (tracked by [count_stores.py](scripts/integration/count_stores.py)). Once
   those callers migrate to `own` / `:=`, remove the `=` shim completely.
2. **Work through the remaining 81 pre-existing Gdev `pen test-blot` failures by name.**
   Down from 108 failures at `be489b79` to **81** (`1,315 passed, 81 failed`
   across 219 modules). Compare affected tests and the 120-frame replay against
   the pinned reference
   ([raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-runtime.raw.json.gz)),
   and investigate the pre-existing Session-2 post-restore `viewport` offset in
   Pen `timeline::contract_tests` rewinds (`sprites[36].x` shifted by 480 px)
   and the pre-existing Session-2 double-restore mismatch in `pen-runtime`
   `session_started_is_absent_from_live_input_recordings_and_state_replacements`.
3. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main 565 ms `-O2` / 432 ms PGO; retained edits
   26–37 ms). Further `trees` / `view` / `write` runtime tuning can target the
   remaining 1.4–1.55× gap to Rust `-O3`.

## Pinned history & evidence

Superseded checkpoint narratives from 17–22 November 2026 (including Checkpoint
F compiler pruning / Batch 1B–1D at `git show d0ae1652:CONTINUE.md` and earlier
checkpoints at `git show a1a117b5:CONTINUE.md`) are preserved in pinned Git
history and in their dedicated task and measurement records:

- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
