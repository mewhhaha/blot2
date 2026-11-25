# Working on Blot and Gdev

## Current frontier: Extended `#for` Comptime Reflection, Stage-0 Blot Virtual Module Generators & Generic Comptime Decoders (25 November 2026)

Extended `#for` reflection, Stage-0 Blot-written virtual module generators,
generic comptime decoders in Ink, local toolchain reinstall, and fresh live
NVIDIA Vulkan Gdev hardware frame qualification are complete and verified at
`blotc-goose` SHA-256
`34193f6a25d67ea4c603cb32410ef0bd0aaecf0d5874691b85534f8d931a87e1`
(`9,548,536` B; `generated/compiler/blotc.gz` SHA-256
`fd641bde68fe939b9e18f9e1a57d9cbfe3b814cf62e28ea3512dcef54ec7f981`,
`4,061,310` B):

- **Extended `#for` comptime reflection (`a24fc85c`):**
  - Added comptime field write `val.(field) := expr` (with `UpdateKind.comptime_field`, wire code `2`) supporting `self` shorthand, heterogeneous trait dispatch, nested field/index paths, flat and boxed records, read-only rejection (`*T`/`&T`), and full uniqueness checking (`aliased_update` / `spent_value`).
  - Added expression-position comptime record builder `#for field in #fields T:` constructing structural and single-constructor nominal `data` types (including generic `t`) field-by-field via `break value`, carrying mutable locals across `#if` and runtime branches, and preserving early function `return`.
  - Added `field.index` (declared order on nominal types, canonical order on structural records) and cross-module `field.default` (resolving defaults in the defining module, including after retained edits).
  - Covered in [vnext_with_traits_comptime.test.ts](tests/guest/vnext_with_traits_comptime.test.ts).

- **Stage-0 Blot-written virtual module generators (`a24fc85c`):**
  - Extended `AssetModule` in [host/assets.ts](host/assets.ts) with raw Blot `source?: string` (composable with structured exports and host `CompiledAsset` references) and added [host/generators.ts](host/generators.ts) (`createBlotGenerator`, `expandGeneratorRules`).
  - Generators are plain `.blot` modules exporting `#entry func generate` (supporting `#[U32]`/`Text` or `{ path, bytes/text }` inputs and `Text` or `Result [Text, Text]` outputs), compiled once to sandboxed Wasm with two-level SHA-256 caching (unchanged builds reuse generated modules; input edits reuse compiled generator Wasm; generator/helper edits recompile Stage 0 automatically).
  - Wired `"generators"` manifest rules (explicit `module`/`input` and `match` globs) into `blot.json` ([host/packages.ts](host/packages.ts)), `blot check` / `blot build` ([host/cli.ts](host/cli.ts)), `blot test` ([host/test_runner.ts](host/test_runner.ts)), and LSP completion on unsaved assets ([host/lsp.ts](host/lsp.ts)), exported from [mod.ts](mod.ts), and documented in [docs/host/assets.md](docs/host/assets.md).
  - Shipped pure-Blot [wgsl_gen.blot](examples/generators/wgsl_gen.blot) and [csv_gen.blot](examples/generators/csv_gen.blot) examples with full host and LSP tests in [generators.test.ts](tests/host/generators.test.ts) and [lsp.test.ts](tests/host/lsp.test.ts).

- **Generic comptime decoders in Ink (`../ink` `f7486d3`):**
  - Added `codec.decode_lanes` and `codec.decode_record` in `../ink/lib/codec.blot` using `#for field in #fields t:` record builders and `field.default`, collapsed the 20-line handwritten decoder in `../ink/tests/comptime_codec.blot` to a single call, and updated `../ink/docs/blot.md`.

- **Preceding 25 November 2026 milestones (full details in `git show b6462804:CONTINUE.md`):**
  - `goosew` fast dev/check wiring (`9df8c3ab`, `check_source.py` `2.76 s`, dev emit `~4.5 s`), per-declaration single-file reuse (`9df8c3ab`, `robots.blot` `117 → 1` elabs/lowers, `check` `25.0 → 5.6 ms`, compiler total `57.2 → 34.1 ms`, byte-exact Wasm), `#entry`/`#kernel`/`#process` modifiers (`c482fccb`), first-class `test "..."` + `std/test` + unified `pen test-blot` (`7b1468cb`, `91a06cbe`, `../pen` `eb8f575`), and 16 migrated flat lane encoders (`../ink` `d0611db`, `../gdev` `b35ce22`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `a24fc85c`) | Extended `#for` reflection & Stage-0 Blot generators (`a24fc85c`), `goosew` dev/check & per-declaration reuse (`9df8c3ab`), `#entry`/`#kernel`/`#process` (`c482fccb`), first-class `test "..."` & `std/test` (`91a06cbe`, `7b1468cb`) |
| `../pen` | `082f314` | Unified `pen test-blot` on `test "..."` & `blot:tests` v1 (`eb8f575`), `wtime-aot v0.1.5` (`b31666d`), `#entry`/`#kernel`/`#process` (`ff7beed`) |
| `../ink` | `f7486d3` | Generic comptime `decode_lanes` & `decode_record` (`f7486d3`), comptime `#for` codecs & `LaneDecode` (`d0611db`), `#entry`/`#kernel`/`#process` (`7edbfcc`) |
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
    `34193f6a25d67ea4c603cb32410ef0bd0aaecf0d5874691b85534f8d931a87e1`
    (`9,548,536` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `fd641bde68fe939b9e18f9e1a57d9cbfe3b814cf62e28ea3512dcef54ec7f981`
    (`4,061,310` bytes; decompressed byte-identical to `blotc-goose`)
  - `~/.local/bin/blot` SHA-256:
    `ac8a2fc9da5b7b1a8a9982d1368cde28f8303be768f92bfacdb21c16c5f1e09c`
    (`144,821,200` bytes; embeds `blotc.gz`, parser Wasm, `std/`, `guide.md`,
    `CHEATSHEET.md`, `host/generators.ts`, and `host/test_worker.ts`)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `9367939bf125c19eea0dc52082ccf19055cd45e986db3f236a9fd75ba2ac27dd`
- **Qualification gates:**
  - `blot2` (`a24fc85c`): `deno task check && deno task check:editor` exit 0
    (`run-b1477857773037ae`) — `fmt --check` (92 files), `deno check`,
    `test:editor` (**6/6**), `harness` (`3.12 s`), `release-build` (`104.18 s`),
    `reference-direct` (**2/2**), `reference-uniqueness` (**206/206**),
    `reference-fixtures` (**109/109**), `pack` OK, `guests` exit 0 (`19.07 s`,
    incl. extended `#for` comptime tests, Stage-0 generator suite, and LSP
    generator completion), `test:std` (**6 modules, 17 tests, 115 assertions, 0
    failed**, `93.1 ms`), `check:editor` (**10/10** corpus + **19/19**
    highlight suites). External `/tmp` verification passed `blot check` on
    `wgsl_gen.blot`/`csv_gen.blot` and `blot test tests/std` (**17/17**, `133.4 ms`).
  - `../ink` (`f7486d3`): `pen test-blot --project ../ink` exit 0 — **486
    passed, 0 failed** in 106 Blot modules (`1.6 s`, `429` checks, `53`
    must-trap, `4` must-not-compile) + **257 passed, 0 failed** native
    f64-reference Rust tests (`8.35 s`); `pen tool ink -- fmt --check` OK.
  - `../gdev` (`642ad53`) live NVIDIA Vulkan hardware frame:
    - Compiled via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile`
      (`build/gdev-first-frame/main-a8c0d39e80c89854/main.wasm`, `6,237,227` B,
      SHA-256 `70e11fcfce8544579cea7ea860c43da634b882f9aa40e70897b9e03a7e149216`,
      `319` modules / `4,539` functions, **`433.7 ms`** build,
      `parallel_retries=0`, `parallel_batches=1`).
    - Executed on **`NVIDIA GeForce RTX 4080 SUPER (Vulkan)`** via
      `LD_LIBRARY_PATH="$HOME/.local/lib/pen-runtime"
      VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json python3
      scripts/integration/run_pen.py --launch --hardware` →
      `build/storage-integration/gdev-one-frame/attempt-_1xxm8ie/frame.png`
      (inspected `640×480` PNG, SHA-256
      `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
      `frames.trace`: `0 7062536994385978 eaf61059c134506c`, `guest 9.345 ms`,
      `render 0.499 ms`, `total 12.239 ms`, all 6 runner checks `true`,
      `compiled_wasm_unchanged: true`).

## Remaining work

All planned frontier tracks are complete, installed, and green across `blot2`,
`../pen`, `../ink`, and `../gdev`. Optional future directions:

1. **Wire Stage-0 Blot generators into `../pen` (`pen.json`):** Extend
   `pen-plugins` / `plugins/blot` to discover and run Stage-0 `.blot`
   generators in Pen projects (mirroring `blot.json` `"generators"`).
2. **Incremental uniqueness validation & backend replay for Track 5:** Scoping
   uniqueness validation to the spliced binding's dependency cone and
   broadening backend body-image replay on behavior-changing edits would push
   single-body structural edits on `robots.blot` below `20 ms`.
3. **Migrate remaining flat lane decoders in Ink & Gdev:** Adopt the new
   generic `codec.decode_lanes` / `codec.decode_record` across simple flat
   records where no extra domain range clamps are needed.

## Pinned history & evidence

Superseded checkpoint narratives are preserved in pinned Git history and in
their dedicated task and measurement records:

- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
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
