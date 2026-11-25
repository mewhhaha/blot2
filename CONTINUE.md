# Working on Blot and Gdev

## Current frontier: Retained-Edit Fast Paths, `body_image::relocate` F32 Soundness Fix, Timeline Rewind Determinism & Live NVIDIA Hardware Frame Qualification (25 November 2026)

All `FAST_COMPILE.md` cold and retained-edit targets, all `timeline::contract_tests`
rewind divergences, and live NVIDIA Vulkan Gdev hardware-frame qualification are
complete and verified at `blotc-goose` SHA-256
`f7ab3612437a20e45f206024bc9b5661703b5385d44ae1f55d49438fa3e3d795` (`9,269,192` B;
`generated/compiler/blotc.gz` SHA-256
`9ec202aab9dce38dc9fa084c26d75eb929f05c3492c6df7e634c04247d934710`, `3,934,266` B):

- **Retained single-file edit & load fast paths + `body_image::relocate` soundness fix (this commit, after `98f277f2`):**
  - **Symbol pool, zero-copy source views & asset reader (`parse/symbols.goose`, `reuse/project_check_engine.goose`, `reuse/revision_inputs.goose`, `reuse/project.goose`, `reuse/editor_completion.goose`, `backend/native_assets.goose`):**
    Added `Pool::reserve` and bulk `Pool::appendUniqueSlice` (eliminating ~15k
    `wyhash` calls per retained build in `replaySymbols`, `reuseSyntax`, and
    `linkCheckingNames`), exact power-of-2 single-alloc chunked-zero
    `reserve_buckets`, and length-prefixed `find`; added zero-copy `readView`
    across `revision_inputs`/`project`/`editor_completion` (removing 3.34 MB
    `source_buf` copies per warm build); added an unchanged-graph fast path in
    `linkCheckingNames` (skipping ~15k `intern_hashed` and 311
    `prepareUnitNames` calls on unchanged/entry edits); switched
    `native_assets::readInput` from 128 KB zero-fill `resize` per file to a
    64 KB stack buffer.
  - **Trivia-only & single scalar-literal retained bypasses (`reuse/retained_project.goose`):**
    Added `sameTriviaSyntax` (guarded by `sameSymbolPrefix` and zero parse
    diagnostics) to skip `check` + `lower` + `backend` on comment/whitespace-only
    edits, and `revisedScalarLiteral` to generalize `revisedCallLiteral` to any
    single same-length `U32` or `F32` literal inside a `function_declaration`
    body (`isSafeU32LiteralUse` across all `Core.Tag` variants, guarding
    `add`/`sub`/`mul` `0`/`1`, loops, sparks, updates, matches, array/storage
    ops, and external builtins; `isSafeF32LiteralPatch` guarding NaN/Inf,
    peephole constants `0/-0/1/2/-2`, `|x| <= 1.0`, and bounded-finite
    `< 0x50000000` classes).
  - **Pre-existing F32 relocation soundness fix (`reuse/body_image.goose`):**
    Added `isSafeF32Relocation` to `body_image::relocate` (matching both
    `Core.Node.ty == f32_type` and `OP_f32_const` sites) so edits crossing
    `2.0 * x → x + x` strength-reduction or bounded-finite NaN-elision classes
    never patch a dead/mismatched `f32.const` and instead fall back cleanly to
    per-body `replayEdits`. Covered with byte-exact oracle assertions in
    [retained_project_execution.test.ts](tests/guest/retained_project_execution.test.ts).
  - **Gdev 312-module / 3.34 MB / 4,480-function measurements (`frontendWorkers=8`, Wasm `6,074,962` B, SHA-256 `c189789db5d2...`):**
    - Cold build: **`400.3 ms`** build (`390.3 ms` compiler total: `load 41.3 ms`,
      `check 152.7 ms`, `lower 21.2 ms`, `backend 152.5 ms`, `assets 13.7 ms`,
      `other 8.4 ms`) — beating the `565 ms` `-O2` and `432 ms` PGO targets in
      [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) without PGO.
    - Warm-session edits on `116 KB` `src/actors/robots.blot` (beating the
      `26–37 ms` target in [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md)):
      - `no-op-2`: **`18.9 ms` wall / `10.91 ms` compiler** (`load 6.18`, `back 0.35`, `assets 3.31`, `other 1.07`)
      - `robots-comment`: **`20.8 ms` wall / `14.17 ms` compiler** (`elab=0`, down from `62.0 ms` wall / `50.3 ms` comp — **3.5× faster compiler**)
      - `robots-u32-0->1`: **`22.6 ms` wall / `15.39 ms` compiler** (`elab=0`, down from `54.9 ms` wall / `46.1 ms` comp — **3.0× faster compiler**)
      - `robots-u32-1->2`: **`22.1 ms` wall / `14.24 ms` compiler** (`elab=0`)
      - `robots-float-edit` (`0.25 → 0.35`): **`20.7 ms` wall / `13.81 ms` compiler** (`elab=0`, down from `51.8 ms` wall / `44.9 ms` comp — **3.25× faster compiler**, 100% byte-exact match against cold oracle `99bc26030b85`)
      - `restore` (multi-edit structural fallback): `53.9 ms` wall / `46.78 ms` compiler (`elab=117`, bit-exact match with cold SHA-256).

- **Pen `timeline::contract_tests` rewind determinism (`../pen` `9fbfa0c`, `../gdev` `877af8a`):**
  - `../gdev` (`877af8a`): refreshed `arena.camera_room` lens/orbit access in
    `world_storage.blot:reset_derived` for paused/interface restores, and
    persisted `impact` (`State`, `sites`, `smoke`) in Save Schema 26 optional
    section key `157` v1 (`src/effects/impact.blot`, `src/world_storage.blot`,
    `tests/hand_impact.blot`, `tests/codec_saved_state.blot`, `docs/reference.md`).
  - `../pen` (`9fbfa0c`, ancestor of `0acf665`): added `hash_resolved_frame` in
    `crates/pen-runtime/src/game.rs` so retained frames hash canonical
    post-`instances.resolve` draws (normalizing `exposure.cut` and filtering
    `service::KERNEL`), eliminating live-delta vs `retained_reset` hash
    divergence (`timeline::contract_tests` **6/6 passed**, `diverge::tests`
    **3/3 passed** against the freshly exported Gdev bundle).

- **Recent preceding milestones (full narratives in pinned Git history `git show 98f277f2:CONTINUE.md`):**
  - **Track 3 (`98f277f2`):** Profile-guided hashing/map/type/backend/zero-copy
    Section-10 optimizations, `canSkipWireSchema` off the kernel dependency
    cone, and `Tag.panic` structural-replay fix (`backend` cold `215 → 152 ms`,
    incremental backend `9.9 → 0.5–0.9 ms`).
  - **Track 2 & Track 4 (`68e5b886`):** `--wasm3` (`return_call_indirect`,
    `relaxed_min`/`max`/`trunc`), generalized `#[n; T]` dependent/post-trap BCE,
    AoS `#[Vec2]`/`#[Vec4]` auto-SIMD (`2.06 ms` `--wasm3` vs `2.77 ms` native
    Rust; 8-thread `wtime-aot` `1.18 ms` / `3.69×` faster than 8-thread Rust;
    ABI 8 `entry process` `47 ns/step`).
  - **Track 1 & Solid-2 Agent Diagnostics (`b54f4c03`, `b254444b`, `../pen` `6d15e26`):**
    Structured uniqueness blame spans (`OriginInfo`/`OriginDetails`), Solid-2
    CLI/LSP/Pen diagnostics, `blot explain`, `CHEATSHEET.md`, and `skills/blot*`.
  - **Direct Backend Tiers 1–7 (`58adc750`..`3ef81d12`):** Complete 11/11 sweep
    on `wtime-aot x64-v3` vs native Rust `-O3` (`0.51×` geomean), Rust `-O3`
    Wasm (`0.42×` geomean), and native Bevy ECS `0.20.1` (`5/5`), plus default
    self-TCO (`cfdabee4`).
  - **Storage & Purity Rewrite Phases 1–6 (`ebf2f026`..`30899f4b`):** Unified
    dynamic `#[T]`, `own`-threaded length mutation, and retirement of
    `check/purity.goose` (`mode = 2` const pools).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `98f277f2`) | Retained-edit fast paths & `body_image::relocate` F32 soundness fix (`this commit`), Track 3 compile-speed & `canSkipWireSchema` (`98f277f2`), Track 2 & 4 `--wasm3`/BCE/AoS SIMD (`68e5b886`), Track 1 LSP/Pen blame spans (`b54f4c03`), Solid-2 agent diagnostics (`b254444b`), Tiers 1–7 runtime opts (`58adc750`..`3ef81d12`), Phases 1–6 storage/purity rewrite (`ebf2f026`..`30899f4b`) |
| `../pen` | `0acf665` | Thin G-Buffer & ReSTIR DI/GI (`0acf665`, `2f0d459`), `wtime-aot v0.1.3` (`3327481`), resolved retained-frame hashing for timeline rewinds (`9fbfa0c`), Pen blame spans (`6d15e26`), unified `#[T]` (`08e1224`) |
| `../ink` | `9227732` | Map/frozen & nav hot-path opts + adversarial fuzz suite (`9227732`), unified `#[T]` (`fc7259e`) |
| `../gdev` | `877af8a` | Persist hand impact feedback (Save 26 key `157`) & refresh arena lens on restore (`877af8a`), unified `#[T]` (`017f8cd`) |

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
  preserves `input` (key 3), `god_hand` (key 114), optional `impact` (key 157
  v1), canonical scene section order, and immediate `restore_scene` with
  `app.hold_frame` on `restore_stash`.
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
    `f7ab3612437a20e45f206024bc9b5661703b5385d44ae1f55d49438fa3e3d795`
    (`9,269,192` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `9ec202aab9dce38dc9fa084c26d75eb929f05c3492c6df7e634c04247d934710`
    (`3,934,266` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `a226d64fdb3313fe3cc0ff9fb42ebba5ee4ae7aa8346b8fc6bdc325d99320aa5`
    (`46,371,704` bytes)
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 (`run-b413f1b95034be32`) —
    `harness` (`2.49 s`), `release-build` (`99.01 s`), `reference-direct`
    **2/2**, `reference-uniqueness` **206/206**, `reference-fixtures`
    **109/109**, `pack` OK, `preflight-regressions` OK, `guests` **1,141 passed,
    0 failed, 75 ignored** (`23.46 s`); `deno task test:editor` (**6/6**).
  - `../pen` (`0acf665`, containing `9fbfa0c`): `cargo test -q -p blot-host`
    **41 passed, 0 failed, 1 ignored**; `examples/bounce` `pen check` clean
    (`0.07 s`); `PEN_TEST_BUNDLE=<fresh gdev export>` `cargo test -p pen
    timeline::contract_tests` **6/6 passed** (`3.25 s`) & `diverge::tests`
    **3/3 passed** (`0.23 s`).
  - `../ink` (`9227732`): `../pen/target/release/pen test-blot` exit 0 —
    **442 passed, 0 failed** in 103 Blot modules (`1.4 s`, incl. `4/4`
    must-not-compile) + **249 passed, 0 failed** native f64-reference Rust
    tests (`7.92 s`).
  - `../gdev` (`877af8a`) live NVIDIA Vulkan hardware frame:
    - Compiled via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile`
      (`build/gdev-first-frame/main-bd2f6e31728397bd/main.wasm`, `6,074,962` B,
      SHA-256 `c189789db5d290e5b5fd0793336e123a7becd69b5b0156d9ba67e5cb79c4ce5d`,
      bit-identical to `pen export --out`).
    - Executed via `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
      python3 scripts/integration/run_pen.py --launch --hardware` →
      `build/storage-integration/gdev-one-frame/attempt-i9jgmm4y/frame.png`
      (inspected `640×480` PNG, SHA-256
      `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
      `frames.trace`: `0 f2fd42971336b167 eaf61059c134506c`, all 6 runner checks
      `true`, `compiled_wasm_unchanged: true`).

## Remaining work

All items tracked previously in this section (`FAST_COMPILE.md` cold/retained
targets, `timeline::contract_tests` rewind determinism, live NVIDIA Gdev
hardware frame qualification, and `CONTINUE.md` cleanup) are resolved. Optional
future follow-ups:

1. **Non-literal structural single-file edit latency:** Single-file structural
   edits inside large modules (e.g. `robots.blot` `116 KB`, `~53.9 ms` wall /
   `46.8 ms` compiler with `22.7 ms` `check` + `6.0 ms` `lower`) still re-check
   all 117 bodies in the edited file; per-declaration body reuse inside an
   edited unit would bring structural body edits below `25 ms` as well.
2. **Runtime microbenchmark tail:** Further `trees` / `view` / `write` runtime
   tuning in [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md)
   can close the remaining gap on tree/string-heavy workloads.
3. **Pre-existing `../gdev` unit test failures (unrelated to compiler/rewind):**
   `lighting_look.blot` (1 sun-angle assertion) and `tutorial.blot` (3 sprite
   count assertions) were pre-existing on `../gdev` `97aa8d5` prior to `877af8a`.

## Pinned history & evidence

Superseded checkpoint narratives are preserved in pinned Git history and in
their dedicated task and measurement records:

- Tier 1–7, Tracks 1–4, Solid-2 diagnostics & Phases 1–6: `git show 98f277f2:CONTINUE.md`
- Concurrency vNext Phases 1–5: `git show 67fc95b8:CONTINUE.md`
- Checkpoint F compiler pruning / Batch 1B–1D: `git show d0ae1652:CONTINUE.md`
- Earlier checkpoints: `git show a1a117b5:CONTINUE.md`
- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
