# Working on Squid and Gdev

## Current frontier (28 November 2026)

Recent completed milestones on `origin/main`:

- **Batch 6 General Benchmark & Memory Optimizations (this commit):**
  - **Direct backend optimizations (`compiler-goose/src/direct/`):**
    - Loop-invariant `U64` reciprocal strength reduction (`function_values.goose`, `function_control.goose`, `function_calls.goose`, `function.goose`), skipping compile-time constant `U64` divisors via `unit == 0xffffffff` derived-const markers so `wtime-aot` preserves 4-instruction constant magic multiplies (`words`, `lru` `1.13×` idle A/B).
    - Expanded `bodyNoAlloc` (`@simd.*`, 1-op `@simd.*` wrappers, unboxed `update`, unboxed `~[T]` mutations, budget `512 → 2048`), `CheckedSimdWindow` loop bounds-check hoisting, and Mode-2 `own #[U8]` SIMD store workers (`blur` `1.16–1.20×` idle A/B, zero `runtime.check` / zero traps in hot SIMD loop).
    - `~[T]` `front_deque` optimizations (`function_spark.goose`, `function_seq.goose`, `function_calls.goose`): reverse 64B/iter `v128` SIMD bulk `push_front` + zero-alloc `pop_front` focus reuse (`29.86 → 6.11 µs` idle A/B, beating Rust `VecDeque` `7.6 µs` and C++ `std::deque` `10.5 µs`).
    - Disjoint range-copy / BCE / RMW optimizations (`function_control.goose`, `function_storage.goose`, `function_data.goose`): zero-loop overlapping `v128` copy for 4..16 disjoint 4B elements, `tryEmitForeverEqBoundLoop`, constant-`0 < len` BCE from any `x < b <= len`, and RMW `checked_elems` retention (`fannkuch-redux` zero hot-loop traps).
    - Non-recursive Mode-1/2/3 array-descriptor workers (`function_entry.goose`, `function_calls.goose`) with `canInlineWorkerHelper` (monomorphic depth-2 `bodyOnlyUsesWorkerMOps` guard), `!res_boxed` guard on `Tag.tuple` `drop_param`, `key.parent == 0` / `from_external && emitted` / `parallel_readonly` guards in `resolveWorkerSpec`, plus `emitExtendFromRodata` `knownMutable` fast path (`respond` `1.17×` idle A/B).
    - Shared cold `push_grow` (`runtime.goose`, `runtime.expected` `8,371 → 8,571 B`) and `runtime.push_entry_grow` (`function_storage.goose`) with gated `>= 8 MiB` in-place tail extension at `arena_top` (`free_lists[ext_cls] == 0` and `!mustUndo`), dropping `scene` medium peak RSS **`57.5 → 41.5 MiB` (-28%)** while speeding up execution (`65.9 → 63.1 ms` idle A/B), plus escape-loop `v128` constant hoisting & `v128.andnot` (`function_spark.goose`).
  - **Regression coverage & references:** Added 6 end-to-end soundness tests in `tests/guest/batch6_benchmark_opts.test.ts` (incl. boxed tuple return, polymorphic helper call, and closure-specialized worker regression coverage caught by `../ink`), updated `vnext_fork_callables_fbip.test.ts` to inspect worker bodies alongside wrappers, and re-recorded `runtime.expected` (8,571 B) and `expected.json` (0 exit/diagnostic/frontend diffs across 109 fixtures). Note: full idle-CPU chart refreshes in `BENCHMARK.md` were deferred because the workstation had external CPU load (`~24–40` load avg) during final sign-off; clean Nov 27 baseline charts remain untouched.
- **Gdev/Ink `PoolRead` migration, compiler soundness/reuse fixes, `IDIOMS.md` & `squid guide` (`916b33fc`):**
  - **Sibling repo migration pushed:** Upstreamed `../ink` (`52ede57` + `46287c5`: `brush.draw` `.length`/`.at` fix + `ecs.PoolIter` / `Pool.iter` / `PoolRead.iter`) and `../gdev` (`15e63c6`: 44 `.sq` files across `src/`, `test_support/`, and `tests/` migrated to `ecs.PoolRead` / `Entities`). Unmodified `scripts/integration/build_gdev.ts` and `run_pen.py` now build and render directly against `../ink` and `../gdev` with zero overlays.
  - **Compiler fixes (`compiler-goose/src/direct/`):**
    - Fixed `nullableNiche` module-level `const` `$Nothing` inlining (`function.goose`) and const-array loop unrolling (`function_control.goose`) to emit null pointer `0` instead of raw variant tag `1`.
    - Added deferred boxed record reuse (`canDeferredReuseBoxed`) and safe non-exported `own` boxed parameter reuse (`ownBoxedParamSafe`) for records holding unshared owned storage, paired with `UNIQUE_BOXED_PREEXISTING` + `noteInPlaceBoxedWrite` (`collectFlatAnyOwnerOffsets` / `collectRegAnyOwnerSlots` + dynamic pointer/slot checks) and FBIP preexisting reuse guard so in-place writes on preexisting loop-carried / `own` blocks preserve `releaseIteration` soundness without disabling scratch reclaim on local temporaries (`editor.declare_toolbar`) or in-place `render.Frame` / `ecs.Pool` updates.
    - Regression coverage added in `tests/guest/audit_soundness_regressions.test.ts` (20/20 across `terminal_scratch_reads_execution` + `audit_soundness_regressions`).
  - **Docs & CLI guide (`IDIOMS.md`, `host/cli.ts`, `CHEATSHEET.md`, `README.md`, `docs/language/guide.md`, `skills/squid/SKILL.md`, `std/README.md`, `docs/README.md`):** Added `IDIOMS.md` (8 compilable Squid modules verified in `tests/host/diagnostics_agent.test.ts`), added `squid guide [--cheatsheet | --idioms | --list | --help | <topic>]` with 13 focused topics (matching `goosew guide`), added `IDIOMS.md` to `deno.json` `publish.include`, and refreshed all guides for `%[T]`/`~[T]`, backtick infix, `Commands`, full scalar types, and `F64` canonical NaN.
- **Backtick infix functions, exact float reductions, `U64` reciprocals, Track 5 incremental reuse & polymorphic operator uniqueness (`160eeee6` + `50500c63`):**
  - **Backtick infix functions:** ``a `f` b``, ``a `mod.f` b``, and ``a `Type.f` b`` parsed at precedence `80` (left-associative, tighter than `**`, looser than application) and desugared to `Apply(Apply(callee, lhs), rhs)`.
  - **Exact IEEE-754 float reductions & `U64` constant-divisor reciprocals:** 4× unrolled left-to-right `F32`/`F64` `for`-in `+` reductions with once-at-end canonical NaN across `#[T]`, `%[T]`, `~[T]`, plus Granlund-Montgomery `U64` reciprocals (`json-serde` `293.2 ms -> 286.6 ms`, `53.0 MiB` RSS vs Go `316.9 ms` / `118.1 MiB`).
  - **Track 5 cone-scoped uniqueness & replay (`tasks/FAST_COMPILE.md`):** Preserved per-body `declaration_dependencies` across consecutive splices (`spliceDependencies`), scoped `uniqueness::checkSelected` to reverse caller cone `R` + forward callee cone `F`, broadened `body_image.goose` replay, and interned/refreshed `squid:traps` entries (`2.05 ms` on 200-fn spliced edit; `16.2–16.9 ms` on 69k-LOC Gdev literal edits, `3.43–5.08 ms` backend on `trails.sq` structural replay).
  - **Polymorphic associated operator uniqueness (`50500c63`):** Added `Tag.associated` and `Tag.result_associated` borrowing arms to `uniqueness.goose`.
- **All-collection SIMD, fast range-push, split-sum & indirect AoS SIMD (`e508d586`, benchmarks refreshed at `b20f8a1e`):**
  - **Suite 8 (`benchmarks/collections/`, 12 workloads, 12/12 bit-exact):** Squid wins **#1 fastest overall on 11/12**; `~[T]` sweeps `imbl::Vector` 12/12 (`1.37×`–`2,895×`); `%[T]` beats hand-written C++20/Rust split-stream (`1.30–1.88×`) and manual SoA (`3.77–3.93×`).
  - **Suites 2–4 (`comparison`):** **6/6** faster than native `rustc -O3` (`aos_vec4` `1.435 ms` / `1.336 ms` `--wasm3`, `2.18–2.34×` vs native Rust); **Ink ECS vs Bevy 0.20.1 wins 4/5** with all 3 dense paths `4.2×–5.4×` faster.
  - **Suite 1 (`goose-suite`, 16 benchmarks / 88 impls):** **`1.07×` C++ expert runtime** (`1.79×` faster than idiomatic C++, `1.60×` faster than idiomatic Rust), **`0.87×` C++ expert peak RSS**, and **`27.5 ms` cold build** (`8.2×` faster than `clang++ -O2`).
  - **Suites 6–7 (`bddicken`, `PLB`, baseline `abb9acaf`):** `bddicken` beats C/C++ 3/3 compute; `PLB` `2.18×` faster than Go on geomean CPU across 12 problems with `1.83×` less RAM (9/12 wins; `json-serde` further improved to `286.6 ms` on `160eeee6`).
- **Preceding milestones** (`e508d586`, `e7807f00`, `b27d4d3a`/`6a455eae`, `abb9acaf`, Waves 1–3) are preserved in pinned Git history (`git show b20f8a1e:CONTINUE.md`, `git show 3b71de42:CONTINUE.md`, `git show b9c04470:CONTINUE.md`).

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `squid` | `916b33fc` (+ this commit) | Batch 6 general benchmark & memory optimizations (loop-inv `U64` reciprocals, `CheckedSimdWindow`, `~[T]` SIMD reverse `push_front` / zero-alloc `pop_front`, non-recursive Mode 1/2/3 workers, overlapping `v128` range-copy / `0 < len` BCE, gated `>= 8 MiB` tail extend, `v128.andnot`); full compiler/std/Ink/Gdev & live Vulkan golden frame re-qualified |
| `../pen` | `b301f55` (1 dirty) | Rebranded to Squid (`pen` SHA-256 `d325efba...`); verified on `../ink` (`515/515` Squid + `267/267` Rust), `../gdev` (`1,448/1,448` Squid + `16/16` Rust), and live NVIDIA Vulkan Gdev frame |
| `../ink` | `46287c5` (pushed) | `brush.draw` `.length`/`.at` fix (`52ede57`) + `ecs.PoolIter` / `Pool.iter` / `PoolRead.iter` (`46287c5`); **515/515** Squid + **267/267** Rust passing on current `squidc-goose` |
| `../gdev` | `15e63c6` (pushed, 9 pre-existing dirty `src/assets/*.mesh.json`) | 44 `.sq` files across `src/`, `test_support/`, `tests/` migrated to `ecs.PoolRead` / `Entities`; **1,448/1,448** Squid (226 modules) + **16/16** Rust passing; unmodified `build_gdev.ts` (`605.1 ms`) + live Vulkan golden frame verified |
| `../wtime` | `91d6cfe` (28 dirty) | `wtime-aot 0.1.11` (`x64-v4`, `--guard-pages`) |

## Hard Invariants

- **Guest ABI 8:** `squid:abi` v8 and `squid:invocation` v1 unchanged (Page-0 offset `640` = `arena_oom_flag`, offset `772` = optional trap-site ID; optional `squid:finish_invocation`, `squid:kernels`, `squid:processes`, `squid:traps` v1; `squid:tests` v1 in `--test` builds only).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15` uses `request == 0` host→guest provenance (`CAP`, `CTL`, `BATCH_ERR`, `BATCH_OK`), strips live-only `CAP` before `Recorded`, filters `request == 0` in `ink/lib/pen/host.sq`, and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries` are excluded and cleared on restore; `world_storage.sq` preserves `input` (3), `god_hand` (114), optional `impact` (157 v1), canonical scene section order, and immediate `restore_scene` + `app.hold_frame` on `restore_stash`.
- **Canonical quiet NaN determinism:** `0x7fc00000` (`F32`) and `0x7ff8000000000000` (`F64`) across `function_spark`, `scalarOp`, `std/simd`, and `#run` (elided only when whole-program float-bit observability proves NaN payloads cannot be observed).
- **Unified ownership & layout symbols:** `#[T]` (`Array T`, `#[N; T]` fixed-length, 1-byte packed `#[Bool]`/`#[U8]`), `%[T]` (`Packed T` automatic SoA / split-stream), `~[T]` (`Seq T` reversible generative SIMD-RRB), and `*T` (frozen read-only handle). `&T`, `&[T]`, `^T`, and `*T` are read-only; in-place mutators enforce unique ownership (`ownedInPlacePath`), keeping module `const` pools deeply immutable (`mode = 2`).

## Verified Identities & Qualification Evidence

Historical qualification records below qualify their exact cited revisions, not later edits.

- **Current built `squid` artifacts (this commit):**
  - `compiler-goose/build/squidc-goose`: SHA-256 `304987de31d46fb233eb8f86933cfbc617d542d25a6bd8ab32d2f43e8e321006` (`11,850,960` B)
  - `generated/compiler/squidc.gz`: SHA-256 `b4e34c65f3e353e963add0afe681665081f404260b8596d9874983df5091f710` (`4,876,432` B)
  - `std/prelude.sq`: SHA-256 `d5670b1e48c9b9ccd8f4aa56c1edd76aa0db23fbfe86592ed9a0f25c433108f9` (`26,986` B)
- **Qualification gates:**
  - `squid` (this commit): `deno fmt --check` (98 files), `deno check`, `deno task test:editor` (6/6), full `deno task test:compiler` (`harness` 2.57s, `release-build` 149.65s, `reference-direct` 0.96s, `reference-uniqueness` 2.20s 206/206, `reference-fixtures` 2.26s 109/109, `pack` 0.21s, `guests` 32.72s incl. 6/6 `batch6_benchmark_opts.test.ts`), `deno task test:std` (9 modules / 20 tests / 171 assertions), and `deno publish --dry-run --allow-dirty` all passed.
  - `../ink` (`46287c5`) via `../pen` (`b301f55`, binary SHA-256 `d325efba3a6284ab658a4479fdeff7818af8fa239bb2565f064c402d6830149d`): `../pen/target/release/pen test-squid --project ../ink` **515/515** Squid tests (`104` modules, `2.9 s`, 8 jobs) + **267/267** native Rust reference tests (`13.97 s`).
  - `../gdev` (`15e63c6`, unmodified checkouts) full suite via `../pen/target/release/pen test-squid --project ../gdev`: **1,448/1,448** Squid tests across `226` modules (`1,293` checks + `148` must-trap + `7` must-not-compile, `105.1 s`, 8 jobs) + **16/16** Rust (`tools/tech`, `0.14 s`).
  - `../gdev` (`15e63c6`, unmodified) live NVIDIA Vulkan hardware frame: built with unmodified `scripts/integration/build_gdev.ts --frontend-workers 8 --profile` (`3,816` functions, `8,228,215` B `.wasm`, identity `3e7003ff9fe688d26f14b3b7b99bab1f25572bad18b0c6e0d4bbc9f6fd0cff06`, `776.0 ms` under host load) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware` (`attempt-rt0q52az`, `compile_invoked: true`, `640×480` visually inspected PNG SHA-256 **`19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`** — bit-identical to the `4e891d2` golden frame; `frames.trace` `0 2a4a73fc5946f6f2 a679663248d91929`, `wtime-aot 284 ms`, **`guest 8.475 ms`**, **`render 0.689 ms`**, **`total 10.736 ms`**, 6/6 runner checks `true`, `compiled_wasm_unchanged: true`).

## Remaining / Optional Next Tracks

1. **Track 5 remaining <20 ms structural edit headroom on 69k-LOC Gdev:** Investigate why `trails.sq` fell back from selective splice (`elab=108` vs `1`) and why `simulation.sq`/`presentation.sq` missed `replayEdits` (`backend=215–236 ms` vs `3.4–5.1 ms` on `trails.sq`), plus shrink per-build `load` (`~9 ms`) to push all Gdev structural edits below `20 ms`.
2. **Library flat lane decoders:** `#[U8]`/`#[F32]` generic flat lane decoders in Ink & Gdev (`codec.decode_lanes` / `codec.decode_record`).

## Pinned History & References

- All-collection SIMD (`e508d586`) & refreshed Suites 1–4/8 benchmark baseline: `git show b20f8a1e:CONTINUE.md`
- Waves 1–3, `bddicken`/PLB/Goose-16 Nov 26 baseline: `git show b9c04470:CONTINUE.md`
- Waves 1–4, `squid doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
