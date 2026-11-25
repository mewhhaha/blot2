# Working on Blot and Gdev

## Current frontier: `#entry`/`#kernel`/`#process`, First-Class Tests (`std/test` & Unified `pen test-blot`), `goosew` Dev Loop, Per-Declaration Single-File Reuse & Expanded Comptime Codecs (25 November 2026)

All six follow-up tracks, the `#entry`/`#kernel`/`#process` surface migration,
local toolchain & Helix reinstall, and fresh live NVIDIA Vulkan Gdev hardware
frame qualification are complete and verified at `blotc-goose` SHA-256
`ec2673434aee6442dc926e766fe8059b2d3e20f09a1f165d0fbb90f2598374ea`
(`9,522,656` B; `generated/compiler/blotc.gz` SHA-256
`fb7f7e4a9d953b04272c82e9b66944ff79e28640b5a608d68b1542e455ba1db5`,
`4,048,426` B):

- **Unified `#entry` / `#kernel` / `#process` declaration modifiers (`c482fccb`, `../pen` `ff7beed`, `../ink` `7edbfcc`, `../gdev` `9e569e7`):**
  - Replaced bare `entry` declarations with explicit `#entry`, `#kernel`, and
    `#process` modifiers across the compiler, fixtures, Tree-sitter/Helix
    grammar, stdlib, docs, tests, benchmarks, Pen, Ink, and Gdev.
  - Preserved `private #entry`, required `const` for prepared `#kernel` and
    isolated `#process` descriptors, and rejected bare `entry`, `pub`, and
    misplaced `private` with `unknown_modifier`.

- **First-class `test "..."`, `std/test` (`BTST` v1), and unified `pen test-blot` (`7b1468cb`, `91a06cbe`, `../pen` `eb8f575`):**
  - Added `std/test` effect library (`Check`, `check.*` assertions, `BTST` v1
    packet encoding) and the `blot test` CLI runner, plus first-class
    `test "name" => ...` / `test expect_trap "name" => ...` declarations,
    `--test` compilation mode, and `blot:tests` v1 Wasm custom section metadata.
  - Unified `../pen`'s `pen test-blot` and `plugins/blot` on `--test` +
    `blot:tests` v1 + `BTST` v1 (`Unit`, `Bool`, `BTST`, `check.report`, and
    `expect_trap`) alongside legacy `#entry func test_*`/`trap_*` without
    duplicate execution.

- **Track 1 — `goosew` fast dev/check wiring (`9df8c3ab`):**
  - Wired `../goose-to-wasm/build/bin/goosew` (with upstream `d5ae5bb` stdlib
    and `--cflag=-Wno-parentheses-equality`) as the default backend for
    `compiler-goose/build.sh` dev builds (`~4.5 s` emit, `~48 s` total dev
    build) and `compiler-goose/tools/check_source.py` (`--reachable-program`,
    full compiler source check in **2.76 s**).
  - Kept `--release` and `--pgo` on patched upstream C++ Goose by default for
    peak runtime speed (`421.5 ms` Gdev build) and runtime allocation observer
    hooks, with `GOOSE_USE_UPSTREAM=1` / `GOOSE_USE_GOOSEW=1` overrides.

- **Track 5 — Per-declaration single-file check & lower reuse (`9df8c3ab`):**
  - Added structural declaration diffing (`retained_project.goose`), selective
    checking and retained scheme seeding (`check.goose`, `check_factory.goose`,
    `check_scheme_import.goose`, `source_operators.goose`,
    `project_check_module.goose`), and selective Core splicing with full
    uniqueness verification (`core.goose`, `core_builder.goose`,
    `body_image.goose`, `declaration_dependencies.goose`,
    `partial_dependency.goose`).
  - **Measured on 319-module Gdev `src/actors/robots.blot` (`116 KB`, `117`
    top-level bodies, optimized `blotc-goose`):** single-body structural edits
    dropped from **`117` elaborations / `117` lowerings** to **`1` / `1`**
    (`fresh=1, cached=318`), cutting `check` from **`25.0 → 5.6 ms`**, `lower`
    from **`7.3 → 5.5 ms`** (including full spliced uniqueness validation),
    compiler total from **`57.2 → 34.1 ms`**, and wall time from
    **`70.5 → 45.8 ms`**, 100% byte-exact against cold Wasm across all 7 paired
    runs and behavior-changing edits. Covered in
    [retained_project_execution.test.ts](tests/guest/retained_project_execution.test.ts).

- **Track 6 — Expanded comptime `#for` codecs & lane decode helpers (`../ink` `d0611db`, `../gdev` `b35ce22`):**
  - Added `LaneDecode`, typed/generic cursor readers, and comptime `lane_count`
    to `../ink/lib/codec.blot`, documented comptime field-write reflection
    limits in `../ink/docs/blot.md`, and migrated 16 flat lane encoders across
    Ink (`app`, `render`, `timeline`, `menu`) and Gdev (`meals`, `frog_shop`,
    `access`, `reports`, `cursor`, `god_hand`, `hand_gesture`, `hover_state`,
    `goals`, `menu`, `arena`) to `codec.encode_lanes`, preserving Save Schema
    26 bit-for-bit.

- **Track 2 — Local toolchain & Helix reinstall:**
  - Atomically installed `~/.local/bin/blot` (standalone CLI bundling
    `blotc.gz`, parser Wasm, `std/`, `guide.md`, `CHEATSHEET.md`, and
    `test_worker.ts`), `~/.local/bin/blotc`, `~/.local/lib/pen-runtime/`
    (`pen`, `player/`, `plugins/blot.wasm`, `web/`, `wtime-aot v0.1.5`) via
    `../pen` `just install`, and Helix Tree-sitter grammar/queries/LSP via
    `deno task helix:install` (`hx --health blot` green).

- **Recent preceding milestones (full narratives in pinned Git history `git show c482fccb:CONTINUE.md` and `git show 7c06d4e6:CONTINUE.md`):**
  - Structural edit localization (`fresh=1`, `389ecb87`), FBIP boxed-block
    reuse & `wtime-aot 0.1.3` benchmarks (`e4d768ce`, `b9f013d7`), declared-order
    nominal `#fields` (`36232076`), dead-subsystem prune (`0d0dbe69`),
    retained-edit fast paths (`7c06d4e6`), `timeline::contract_tests` rewind
    determinism (`../pen` `9fbfa0c`, `../gdev` `877af8a`), Solid-2 diagnostics
    (`b254444b`, `b54f4c03`), Direct Backend Tiers 1–7 (`58adc750`..`3ef81d12`),
    and Storage & Purity Rewrite Phases 1–6 (`ebf2f026`..`30899f4b`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `9df8c3ab`) | `goosew` dev/check wiring & per-declaration single-file reuse (`9df8c3ab`), `#entry`/`#kernel`/`#process` modifiers (`c482fccb`), first-class `test "..."` & `blot:tests` v1 (`91a06cbe`), `std/test` & `blot test` (`7b1468cb`), README refresh (`64f8a32b`) |
| `../pen` | `eb8f575` | Unified `pen test-blot` on `test "..."` & `blot:tests` v1 (`eb8f575`), `wtime-aot v0.1.5` & no-fallback host (`b31666d`), 2D/Hi-Z/ViewportOverlay (`b6e3f71`), `#entry`/`#kernel`/`#process` (`ff7beed`) |
| `../ink` | `d0611db` | Comptime `#for` codecs & `LaneDecode` helpers (`d0611db`), typed Pen 2D render extensions (`b50894f`), `#entry`/`#kernel`/`#process` (`7edbfcc`), accessible UI/i18n (`7081e49`) |
| `../gdev` | `642ad53` | >8192 rad trig NaN fix & physical brick counts (`642ad53`), 11 flat lane encoders migrated to `codec.encode_lanes` (`b35ce22`), `#entry`/`#kernel`/`#process` (`9e569e7`) |

### Hard Invariants Preserved
- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (zero extra
  runtime exports; Page-0 offset `640` carries `arena_oom_flag`; optional
  `blot:finish_invocation` / `blot:kernels` / `blot:processes`; optional
  `blot:tests` v1 custom section in `--test` builds only).
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
  and `*T` are strictly read-only; `:=`, `@storage.push`, `@storage.pop`,
  `@storage.truncate`, and `@simd.store` enforce unique ownership
  (`ownedInPlacePath`), guaranteeing all module `const` pools are deeply
  immutable (`mode = 2`).

### Verified Identities & Qualification Evidence
- **Compiler, CLI & host identities:**
  - `compiler-goose/build/blotc-goose` & `~/.local/bin/blotc` SHA-256:
    `ec2673434aee6442dc926e766fe8059b2d3e20f09a1f165d0fbb90f2598374ea`
    (`9,522,656` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `fb7f7e4a9d953b04272c82e9b66944ff79e28640b5a608d68b1542e455ba1db5`
    (`4,048,426` bytes; decompressed byte-identical to `blotc-goose`)
  - `~/.local/bin/blot` SHA-256:
    `14fad9ea1c955e3d471b74a46a9cce6a09671de8ec5de6804bc8fe9f51d61ddd`
    (`144,720,264` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` & `~/.local/lib/pen-runtime/pen` SHA-256:
    `cd4283cb6e2dd474aa3688d9da431decd297950ca41c7a0befea426fbfdb1fd5`
    (`47,063,168` bytes; `plugins/blot.wasm` SHA-256
    `e769b973bfea90703964f0a362b36121949f79d824d06423fdafb7d8d11c44a6`,
    `234,030` bytes)
- **Qualification gates:**
  - `blot2` (`9df8c3ab`): `deno task check && deno task check:editor` exit 0
    (`run-81630d808df18398`) — `fmt --check` (90 files), `deno check`,
    `test:editor` (**6/6**), `harness` (`2.48 s`), `release-build` (`93.26 s`),
    `reference-direct` (**2/2**), `reference-uniqueness` (**206/206**),
    `reference-fixtures` (**109/109**), `pack` OK, `guests` exit 0 (`16.95 s`,
    incl. new `retained declaration splices` coverage), `test:std` (**6 modules,
    17 tests, 115 assertions, 0 failed**, `89.1 ms`), `check:editor` (**10/10**
    corpus + **19/19** highlight suites); `check_source.py --phase check` via
    `goosew` exit 0 (`2.76 s`, 0 errors).
  - External-directory installed binary verification (`/tmp`): `blot --help`,
    `blot guide --cheatsheet`, `blot explain SPENT_VALUE`, `blot fmt --check`,
    `blot check`, `blot build` (byte-identical to `blotc build-project`),
    `blot test tests/std` (**17/17 tests, 115 assertions**, `130.3 ms`),
    `pen test-blot --project ../pen/examples/bounce` (**7/7 passed**, `0.1 s`),
    and `hx --health blot` (parser/highlights/rainbows/LSP ✓).
  - `../pen` (`eb8f575`): plugin tests **29/29**, `pen-runtime` +
    `pen-plugins` **225/225** (2 ignored), `pen` `blot_test` **15/15**,
    `just install` exit 0 (plugins, `pen-web` `wasm-opt -O1`, glibc 2.28
    shipping `player`, `wtime-aot v0.1.5`, release `pen --features steam`).
  - `../ink` (`d0611db`): installed `pen test-blot --project ../ink` exit 0 —
    **462 passed, 0 failed** in 106 Blot modules (`1.5 s`, `405` checks, `53`
    must-trap, `4` must-not-compile) + **257 passed, 0 failed** native
    f64-reference Rust tests (`8.53 s`).
  - `../gdev` (`b35ce22` / `642ad53`): Track 6 verified **1,431 passed, 0
    failed** in 224 Blot modules + **16 passed, 0 failed** `gdev-tech` Rust
    tests; live NVIDIA Vulkan hardware frame qualified on `642ad53`:
    - Compiled via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile`
      (`build/gdev-first-frame/main-7d7de05bd6133469/main.wasm`, `6,236,804` B,
      SHA-256 `ace582e966fd2ec7b103af77c24c663f6fbb4dee6e84cb316fd5e9cd3f3c990b`,
      `319` modules / `4,535` functions, **`421.5 ms`** build,
      `parallel_retries=0`, `parallel_batches=1`).
    - Executed on **`NVIDIA GeForce RTX 4080 SUPER (Vulkan)`** via
      `LD_LIBRARY_PATH="$HOME/.local/lib/pen-runtime"
      VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json python3
      scripts/integration/run_pen.py --launch --hardware` →
      `build/storage-integration/gdev-one-frame/attempt-janh1l_p/frame.png`
      (inspected `640×480` PNG, SHA-256
      `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
      `frames.trace`: `0 7062536994385978 eaf61059c134506c`, `guest 9.308 ms`,
      `render 1.513 ms`, `total 13.348 ms`, all 6 runner checks `true`,
      `compiled_wasm_unchanged: true`).

## Remaining work

All planned frontier tracks are complete, installed, and green across `blot2`,
`../pen`, `../ink`, and `../gdev`. Optional future directions:

1. **Incremental uniqueness validation & backend replay for Track 5:** Track 5
   already cut `robots.blot` `check` from `25.0 → 5.6 ms` (`elabs=1, lowers=1`);
   scoping uniqueness validation to the spliced binding's dependency cone and
   broadening backend body-image replay on behavior-changing edits would push
   single-body structural edits below `20 ms`.
2. **Comptime record construction / decode ergonomics:** Extending comptime
   reflection to support field-wise record construction alongside `value.(field)`
   reads would let `ink/codec` eliminate remaining handwritten `LaneDecode`
   constructors.
3. **`benchmarks/checked-grid` microbenchmark tail:** Continue tuning
   tree/string-heavy workloads in
   [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md).

## Pinned history & evidence

Superseded checkpoint narratives are preserved in pinned Git history and in
their dedicated task and measurement records:

- Structural edit localization (`fresh=1`), FBIP reuse & `wtime-aot 0.1.3`: `git show c482fccb:CONTINUE.md`
- Retained-edit fast paths & timeline rewind determinism: `git show 7c06d4e6:CONTINUE.md`
- Tier 1–7, Tracks 1–4, Solid-2 diagnostics & Phases 1–6: `git show 98f277f2:CONTINUE.md`
- Concurrency vNext Phases 1–5: `git show 67fc95b8:CONTINUE.md`
- Checkpoint F compiler pruning / Batch 1B–1D: `git show d0ae1652:CONTINUE.md`
- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json](benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json) · [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
