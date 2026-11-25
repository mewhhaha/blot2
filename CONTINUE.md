# Working on Blot and Gdev

## Current frontier: Structural Edit Localization (`fresh=1`), Expanded FBIP Reuse, `wtime-aot 0.1.3` Qualification, Comptime `#for` Codecs & Dead-Subsystem Prune (25 November 2026)

All five follow-up tracks and full cross-repo qualification (including live
NVIDIA Vulkan Gdev hardware frame and Save Schema 26 rewind determinism) are
complete and verified at `blotc-goose` SHA-256
`7d608127020fe12e5bea6b3ee58ab5ceac90fe31b31c8354d1f57bad56d25e46` (`9,273,424` B;
`generated/compiler/blotc.gz` SHA-256
`abcf1875115b6fd2dec56a1a9d03feb0b7ad32b8b567012b3eb1d9fb70595fbe`, `3,935,874` B):

- **Track 1 — Single-file structural edit localization (`389ecb87`):**
  - Switched `Nominal`, `Constructor`, `EffectFamily`, and `EffectTemplate`
    identities in `check/check.goose` from raw AST node IDs to stable
    declaration-order ordinals (updating AST lookup sites in `check.goose`,
    `core_builder.goose`, and `editor_completion.goose`).
  - Compacted lazily-materialized external `callee_use` and imported
    `associated` bindings after header bindings in canonical `(unit, binding)`
    order in `reuse/dependency_snapshot.goose` so body-local binding shifts and
    call encounter order never perturb persistent interface packets.
  - Preserved existing project symbols verbatim in `project.goose`
    `linkCheckingNames` and appended new symbols from edited non-entry units
    without shifting downstream units; split `symbol_shifted` from `affected`
    in `reuse/retained_project.goose`.
  - Broadened `reuse/body_image.goose` `sameCoreExpr` (`type_constructor`,
    `type_same`, `operation_value`, `flat_op`) and `findEditedBindings`
    (global-only binding index check + resolved `associated` targets) so
    `replayEdits` handles new local bindings cleanly.
  - **Measured on 319-module / 6.19 MB Gdev (`blotc-goose -O2`, `frontendWorkers=8`):**
    single-file structural edits in `116 KB` `src/actors/robots.blot` (including
    edits before `type` declarations and adding a `let` with an existing or
    brand-new identifier) dropped from **`237–254 ms`** (`fresh=11–28`, backend
    `208 ms`) to **`61.5–90.4 ms`** (**`fresh=1, cached=318`**, backend
    **`3.1–6.0 ms`** — up to **67× backend speedup**), 100% byte-exact against
    cold oracle. Covered in
    [retained_project_execution.test.ts](tests/guest/retained_project_execution.test.ts).

- **Track 2 — Compiler dead-subsystem prune & `goose-to-wasm` fast dev loop (`0d0dbe69`):**
  - Removed 7 dead `.goose` modules (`407` LOC), 12 dead AST tags, 5 dead parse
    codes, and `Fixity`, and resolved Goose §5.2 recursive-storage lifetimes so
    `../goose-to-wasm` compiles the entire Blot2 compiler to Wasm64 in **3.7 s**.

- **Track 3 — Comptime `#for #fields` / `#variants` codecs (`36232076`, `../ink` `d611e63`, `../gdev` `80f5ee4`):**
  - Fixed `#for field in #fields T` (`direct/function_control.goose`
    `comptimeFieldPos`) to iterate nominal single-constructor data types in
    **declared field order** (matching `#variants T` and positional
    constructors), with regression coverage in
    [vnext_with_traits_comptime.test.ts](tests/guest/vnext_with_traits_comptime.test.ts).
  - Added generic comptime codec primitives to `../ink/lib/codec.blot`:
    `FieldId`/`Skip`/`VariantTag` tags, `LaneEncode` trait + `encode_lanes`,
    `encode_record`, `check_header`, `read_field`, `record_field_count`,
    `record_field_ids`, `describe_record_parts`, `variant_tags`, and
    `variant_count`, with 4 new tests in `../ink/tests/comptime_codec.blot`.
  - Migrated `../ink/lib/{orbit,view,transform}.blot` and
    `../gdev/src/{ui/loading,effects/electricity,ui/build_bar}.blot` to
    `codec.encode_lanes`, preserving Save Schema 26 bit-for-bit.

- **Track 4 — Expanded FBIP boxed-block reuse & `wtime-aot 0.1.3` benchmarks (`e4d768ce`, `b9f013d7`):**
  - Broadened direct-backend FBIP in-place reuse (`function.goose`,
    `function_control.goose`, `function_data.goose`) to support up to 4
    mutually-exclusive tail constructs (`collectTailConstructs` across `suite`,
    `return_`, `block_` → `return_`, statement-match tail `bind`, `if_value`,
    and `if_stmt`), statement matches, and `copiedBox` loop carries; shrank
    `direct/boxed_records.blot` from `6,312 → 6,121` Wasm bytes (`-191 B`,
    identical outputs) and added zero-allocation + alias-soundness coverage in
    [fbip_reuse_execution.test.ts](tests/guest/fbip_reuse_execution.test.ts).
  - Qualified and recorded fresh comparison benchmarks on **`wtime-aot 0.1.3`**
    (`1125fd5`, native 256-opcode register SIMD + `--wasm3`) in
    [2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json](benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json):
    - `particle_spark_simd`: **`0.3327 ms`** (`1.32×` faster than `0.1.2`, **`2.02×` faster** than native Rust `-O3`).
    - `aos_vec4_euler_65k_x32`: **`1.9446 ms`** (`1.44×` faster than native Rust `-O3`); `aos_vec2_euler` (`--wasm3`): **`0.6439 ms`**.
    - 8-thread Mandelbrot: **`1.021 ms`** (**`5.52×` scaling**, **`4.24×` faster** than 8-thread native Rust).
    - Ink ECS `dense_iter_10k_x100`: `ink_soa_spark_simd` **`0.3233 ms`** (**`3.81×` faster** than Bevy `0.20.1` native), `ink_cached_query` **`0.5393 ms`**, `ink_pool_direct` **`0.4680 ms`**.
    - All 6 kernels beat both Rust `wasm32 -O3` (`0.20×–0.73×`) and native Rust `-O3` (`0.18×–0.91×`) with bit-exact checksum parity.

- **Track 5 — Pre-existing `../gdev` test fixes & Pen qualification (`../gdev` `e2e6714`):**
  - Fixed pre-existing `lighting_look.blot`, `tutorial.blot`, and `gdev-tech`
    test assertions so the entire Gdev suite passes cleanly (`1,431/1,431` Blot
    + `16/16` Rust).

- **Recent preceding milestones (full narratives in pinned Git history `git show 7c06d4e6:CONTINUE.md` and `git show 98f277f2:CONTINUE.md`):**
  - Retained-edit fast paths (`sameTriviaSyntax`, `revisedScalarLiteral`,
    `body_image::relocate` F32 soundness fix), `timeline::contract_tests` rewind
    determinism (`../pen` `9fbfa0c`, `../gdev` `877af8a`), Track 3 compile-speed
    & `canSkipWireSchema` (`98f277f2`), `--wasm3`/BCE/AoS SIMD (`68e5b886`),
    Solid-2 agent diagnostics (`b254444b`, `b54f4c03`), Direct Backend Tiers
    1–7 (`58adc750`..`3ef81d12`), and Storage & Purity Rewrite Phases 1–6
    (`ebf2f026`..`30899f4b`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `b9f013d7`) | `Tag.block_` FBIP fix (`b9f013d7`), declared-order nominal `#fields` (`36232076`), FBIP reuse & `wtime-aot 0.1.3` benchmarks (`e4d768ce`), structural edit `fresh=1` localization (`389ecb87`), dead-subsystem prune & `goose-to-wasm` (`0d0dbe69`), retained-edit fast paths (`7c06d4e6`) |
| `../pen` | `c3e1d01` | Rebuilt release binary, Thin G-Buffer & ReSTIR DI/GI (`0acf665`), `wtime-aot v0.1.3` (`3327481`), resolved retained-frame hashing (`9fbfa0c`), Pen blame spans (`6d15e26`) |
| `../ink` | `d611e63` | Comptime `#for #fields`/`#variants` codecs & `orbit`/`view`/`transform` migration (`d611e63`), map/frozen & nav hot-path opts + fuzz suite (`9227732`) |
| `../gdev` | `80f5ee4` | Migrate `loading`/`electricity`/`build_bar` to `codec.encode_lanes` (`80f5ee4`), Ink feature lab (`35ecab7`), Moebius/tech test fixes (`e2e6714`), Save 26 key `157` (`877af8a`) |

### Hard Invariants Preserved
- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (zero extra
  exports; Page-0 offset `640` carries `arena_oom_flag`; optional
  `blot:finish_invocation` / `blot:kernels` / `blot:processes`).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15`
  uses unambiguous `request == 0` host→guest provenance (`CAP`, `CTL`,
  `BATCH_ERR`, `BATCH_OK`), strips live-only unrecorded `CAP` before `Recorded`,
  filters `request == 0` events in `ink/lib/pen/host.blot` before `app.advance`,
  and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries`
  are excluded from Save 26 and cleared on restore; `world_storage.blot`
  preserves `input` (key 3), `god_hand` (key 114), optional `impact` (key 157
  v1), canonical scene section order, and immediate `restore_scene` with
  `app.hold_frame` on `restore_stash`.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.
- **Unified dynamic arrays, single update `:=`, value restriction, and read-only references:**
  `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` for fixed-length);
  local `let` generalizes only on syntactic `func` values; `&T`, `&[T]`, `^T`,
  and `*T` are strictly read-only; `:=`, `@simd.store`, `@storage.push`,
  `@storage.pop`, and `@storage.truncate` enforce unique ownership
  (`ownedInPlacePath`), guaranteeing all module `const` pools are deeply
  immutable (`mode = 2`).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `7d608127020fe12e5bea6b3ee58ab5ceac90fe31b31c8354d1f57bad56d25e46`
    (`9,273,424` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `abcf1875115b6fd2dec56a1a9d03feb0b7ad32b8b567012b3eb1d9fb70595fbe`
    (`3,935,874` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `dee6ce6ff099f21fe43b47d90831b85c7ae66e0942f18f47c7b7b7bedc076c5e`
    (`46,472,064` bytes)
- **Qualification gates:**
  - `blot2` (`b9f013d7`): `deno task test:compiler` exit 0 (`run-ae030dc2844afba9`) —
    `harness` (`2.46 s`), `release-build` (`101.31 s`), `reference-direct`
    **2/2**, `reference-uniqueness` **206/206**, `reference-fixtures`
    **109/109**, `pack` OK, `guests` exit 0 (`23.27 s`, incl. new
    `retained_project_execution`, `fbip_reuse_execution`, and declared-order
    `vnext_with_traits_comptime`); `deno task test:editor` (**6/6**).
  - `../pen` (`c3e1d01`): `cargo test -q -p blot-host` **42 passed, 0 failed,
    1 ignored**; `examples/bounce` `pen check` clean (`0.13 s`);
    `PEN_TEST_BUNDLE=<fresh gdev export>` `cargo test --locked -p pen
    timeline::contract_tests` **6/6 passed** (`8.22 s`) & `diverge::tests`
    **3/3 passed** (`0.22 s`).
  - `../ink` (`d611e63`): `pen tool ink -- fmt --check` OK, `pen tool ink --
    generate tools/generate.json` OK, `pen test-blot` exit 0 — **446 passed, 0
    failed** in 104 Blot modules (`2.2 s`, incl. 4 new `comptime_codec` tests &
    `4/4` must-not-compile) + **249 passed, 0 failed** native f64-reference Rust
    tests (`26.89 s`).
  - `../gdev` (`80f5ee4`): `pen test-blot` exit 0 — **1,431 passed, 0 failed**
    in 224 Blot modules (`55.3 s`, incl. `148` must-trap & `7` must-not-compile)
    + **16 passed, 0 failed** `gdev-tech` Rust tests (`0.13 s`); fresh
    `pen export` (`0.46 s`).
  - `../gdev` (`80f5ee4`) live NVIDIA Vulkan hardware frame:
    - Compiled via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile`
      (`build/gdev-first-frame/main-5403bdbdda67f406/main.wasm`, `6,195,437` B,
      SHA-256 `fc7be554a1900013dee988fc81cf1917b1528801edd871310814ffaf4ee5ae01`,
      `319` modules / `4,523` functions, `631.9 ms` build, `parallel_retries=0`,
      `parallel_batches=1`).
    - Executed via `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
      python3 scripts/integration/run_pen.py --launch --hardware` →
      `build/storage-integration/gdev-one-frame/attempt-yjwlx_gw/frame.png`
      (inspected `640×480` PNG, SHA-256
      `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
      `frames.trace`: `0 7062536994385978 eaf61059c134506c`, all 6 runner checks
      `true`, `compiled_wasm_unchanged: true`).

## Remaining work

All planned frontier tracks are complete and green across `blot2`, `../pen`,
`../ink`, and `../gdev`. Optional future directions:

1. **Per-declaration check/lower reuse inside a single edited unit:** Structural
   edits inside large files like `robots.blot` (`116 KB`, `117` bodies) now stay
   localized to `fresh=1` (`61.5–90.4 ms` wall, `3.1–6.0 ms` backend); skipping
   check/lower of the unchanged ~116 bodies inside the edited unit itself would
   push structural edits under `25 ms`.
2. **Broader comptime codec adoption:** Extend `ink/codec.encode_lanes` /
   `encode_record` across remaining handwritten `$lanes.Codec` modules in `../ink`
   and `../gdev`, or explore comptime record decoding/construction.
3. **`benchmarks/checked-grid` microbenchmark tail:** Continue tuning
   tree/string-heavy workloads in
   [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md).

## Pinned history & evidence

Superseded checkpoint narratives are preserved in pinned Git history and in
their dedicated task and measurement records:

- Retained-edit fast paths & timeline rewind determinism: `git show 7c06d4e6:CONTINUE.md`
- Tier 1–7, Tracks 1–4, Solid-2 diagnostics & Phases 1–6: `git show 98f277f2:CONTINUE.md`
- Concurrency vNext Phases 1–5: `git show 67fc95b8:CONTINUE.md`
- Checkpoint F compiler pruning / Batch 1B–1D: `git show d0ae1652:CONTINUE.md`
- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json](benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json) · [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
