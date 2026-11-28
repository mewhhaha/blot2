# Working on Squid and Gdev

## Current frontier (28 November 2026)

Recent completed milestones on `origin/main`:

- **Backtick infix functions, exact float reductions, `U64` reciprocals, Track 5 incremental reuse & Gdev/Ink fixes (`160eeee6` + this commit):**
  - **Backtick infix functions:** ``a `f` b``, ``a `mod.f` b``, and ``a `Type.f` b`` parsed at precedence `80` (left-associative, tighter than `**`, looser than application) and desugared to `Apply(Apply(callee, lhs), rhs)` across `compiler-goose`, Baba CST/generated parser, `host/format.ts`, `editor/tree-sitter-squid`, tests, `docs/language/guide.md`, and `CHEATSHEET.md`.
  - **Exact IEEE-754 float reductions & `U64` constant-divisor reciprocals:** 4× unrolled left-to-right `F32`/`F64` `for`-in `+` reductions with once-at-end canonical NaN across `#[T]`, `%[T]`, `~[T]` (`direct/pools.sq` re-recorded `5165 -> 5328` B, SHA-256 `8246ab0a...`), plus Granlund-Montgomery `U64` reciprocals (`emitMulHi64` Form 1 & Form 2 matching `wtime-aot`'s `MulHiU`). PLB `json-serde` (`canada.json × 15`) improved `293.2 ms -> 286.6 ms` (`53.0 MiB` RSS vs Go `316.9 ms` / `118.1 MiB`, identical output SHA-256 `cd6c92b0fc20a7d5`).
  - **Track 5 cone-scoped uniqueness & replay (`tasks/FAST_COMPILE.md`):** Preserved per-body `declaration_dependencies` across consecutive splices (`spliceDependencies`), scoped `uniqueness::checkSelected` to reverse caller cone `R` + forward callee cone `F`, broadened `body_image.goose` replay (`record_payload`, `with_handle`, `contract_method`, `effect_provider`, `state_provider`), and interned/refreshed `squid:traps` entries during structural replay (`function.goose`, `writer.goose`, `direct.goose`, `body_image.goose`). Measured `-O2` 200-fn spliced edit at **`2.05 ms`** (`0.44 ms` check, `0.71 ms` lower, `0.046 ms` replay); on real 69k-LOC Gdev, literal edits complete in **`16.2–16.9 ms`** compiler time (`0.97 ms` backend) and `trails.sq` structural edits replay in **`3.43–5.08 ms`** backend (`31.2–37.3 ms` total compiler time).
  - **Polymorphic associated operator uniqueness fix (this commit):** Added `Tag.associated` and `Tag.result_associated` borrowing arms to `uniqueness.goose` so polymorphic binary operators (`f934486d`) borrow rather than escape unique owners, fixing `../gdev/src/world/salt_simulation.sq` while keeping open-result `@type.call` loans sound.
- **All-collection SIMD, fast range-push, split-sum & indirect AoS SIMD (`e508d586`, benchmarks refreshed at `b20f8a1e`):**
  - **Suite 8 (`benchmarks/collections/`, 12 workloads, 12/12 bit-exact):** Squid wins **#1 fastest overall on 11/12**; `~[T]` sweeps `imbl::Vector` 12/12 (`1.37×`–`2,895×`); `%[T]` beats hand-written C++20/Rust split-stream (`1.30–1.88×`) and manual SoA (`3.77–3.93×`).
  - **Suites 2–4 (`comparison`):** **6/6** faster than native `rustc -O3` (`aos_vec4` `1.435 ms` / `1.336 ms` `--wasm3`, `2.18–2.34×` vs native Rust); **Ink ECS vs Bevy 0.20.1 wins 4/5** with all 3 dense paths `4.2×–5.4×` faster.
  - **Suite 1 (`goose-suite`, 16 benchmarks / 88 impls):** **`1.07×` C++ expert runtime** (`1.79×` faster than idiomatic C++, `1.60×` faster than idiomatic Rust), **`0.87×` C++ expert peak RSS**, and **`27.5 ms` cold build** (`8.2×` faster than `clang++ -O2`).
  - **Suites 6–7 (`bddicken`, `PLB`, baseline `abb9acaf`):** `bddicken` beats C/C++ 3/3 compute; `PLB` `2.18×` faster than Go on geomean CPU across 12 problems with `1.83×` less RAM (9/12 wins; `json-serde` further improved to `286.6 ms` on `160eeee6`).
- **Preceding milestones** (`e508d586`, `e7807f00`, `b27d4d3a`/`6a455eae`, `abb9acaf`, Waves 1–3) are preserved in pinned Git history (`git show b20f8a1e:CONTINUE.md`, `git show 3b71de42:CONTINUE.md`, `git show b9c04470:CONTINUE.md`).

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `squid` | `160eeee6` (+ this commit) | Backtick infix functions, exact 4× float reductions, `U64` reciprocals, Track 5 cone-scoped uniqueness + trap-interned replay, `Tag.associated` uniqueness fix; post-rebrand Pen/Ink & live Vulkan Gdev frame re-qualified |
| `../pen` | `b301f55` (1 dirty) | Rebranded to Squid (`pen` SHA-256 `d325efba...`); verified on `../ink` (`515/515` Squid + `267/267` Rust) and live NVIDIA Vulkan Gdev frame |
| `../ink` | `29b672f` (1 dirty) | Rebranded to Squid + dense/bitset/sparse `ecs.Pool` & `#[U64]` `Entities`; **515/515** Squid + **267/267** Rust passing on current `squidc-goose`. Note: `lib/brush.sq:533` still uses `for row in brushes:` instead of `for bi in 0 .. brushes.length: brushes.at bi` for `ecs.Pool Stored` callers |
| `../gdev` | `373c4ba` (10 dirty) | Rebranded to Squid; preserved untouched on disk. `../ink` `089eea0` (`ecs.PoolRead` / `Entities` bitset) leaves 19 `../gdev/src/*.sq` callers + `../ink/lib/brush.sq:533` unmigrated; verified with an in-memory 20-file `PoolRead` overlay to build cleanly (`581.9 ms`) and render the bit-identical golden 640×480 Vulkan frame |
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
  - `compiler-goose/build/squidc-goose`: SHA-256 `9030befe9a7f31862cc1647b781d9e13a8c474a168a4a2da29ad53de7a4677b9` (`11,729,632` B)
  - `generated/compiler/squidc.gz`: SHA-256 `a62eb3de2cd871fa9f210cf044378861d3766da88001f38a2afd41236fe6600d` (`4,834,600` B)
  - `std/prelude.sq`: SHA-256 `d5670b1e48c9b9ccd8f4aa56c1edd76aa0db23fbfe86592ed9a0f25c433108f9` (`26,986` B)
- **Qualification gates:**
  - `squid` (this commit): full `deno task test:compiler && deno task test:std` passed (`harness` 2.49s, `release-build` 137.60s, `reference-direct` 0.87s, `reference-uniqueness` 1.90s, `reference-fixtures` 3.58s 109/109, `pack` 0.42s, `guests` 30.45s incl. backtick infix, exact float reductions, `U64` reciprocals, `Tag.associated` uniqueness/soundness, and Track 5 splice/replay trap interning tests; `test:std` 9 modules / 20 tests / 171 assertions; `deno task test:editor` 6/6 at `160eeee6`).
  - `../ink` (`29b672f`) via `../pen` (`b301f55`, binary SHA-256 `d325efba3a6284ab658a4479fdeff7818af8fa239bb2565f064c402d6830149d`): `../pen/target/release/pen test-squid --project ../ink` **515/515** Squid tests (`511` checks in 100 modules + `4` must-not-compile in 4 modules, `2.3 s`, 8 jobs) + **267/267** native Rust reference tests (`12.38 s`).
  - `../gdev` (`373c4ba` + 20-file in-memory `PoolRead` / `brush.draw` overlay; sibling checkouts untouched on disk) live NVIDIA Vulkan hardware frame: built with `frontendWorkers: 8` (`3,803` functions, `8,201,788` B `.wasm`, SHA-256 `3552cf845110bc259ff49c84573ffcdaf09fbff17334ccc1626245fbec3ab866`, **`581.9 ms`** cold vs `885.1 ms` prior) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware --compiled-main ...` (`640×480` visually inspected PNG SHA-256 **`19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`** — bit-identical to the `4e891d2` golden frame; `frames.trace` `0 2a4a73fc5946f6f2 a679663248d91929`, `wtime-aot 279 ms`, **`guest 7.397 ms`**, **`render 0.361 ms`**, **`total 9.259 ms`**, 6/6 runner checks `true`, `compiled_wasm_unchanged: true`).

## Remaining / Optional Next Tracks

1. **Upstream `../gdev` + `../ink/lib/brush.sq` `PoolRead` migration:** Apply the verified 1-line `brush.draw` fix in `../ink` (`lib/brush.sq:533`) and the 19-file `ecs.PoolRead` / `Entities` caller updates in `../gdev` so unmodified `scripts/integration/build_gdev.ts` builds directly against `../ink` `29b672f`.
2. **Track 5 remaining <20 ms structural edit headroom on 69k-LOC Gdev:** Investigate why `trails.sq` fell back from selective splice (`elab=108` vs `1`) and why `simulation.sq`/`presentation.sq` missed `replayEdits` (`backend=215–236 ms` vs `3.4–5.1 ms` on `trails.sq`), plus shrink per-build `load` (`~9 ms`) to push all Gdev structural edits below `20 ms`.
3. **Library flat lane decoders:** `#[U8]`/`#[F32]` generic flat lane decoders in Ink & Gdev (`codec.decode_lanes` / `codec.decode_record`).

## Pinned History & References

- All-collection SIMD (`e508d586`) & refreshed Suites 1–4/8 benchmark baseline: `git show b20f8a1e:CONTINUE.md`
- Waves 1–3, `bddicken`/PLB/Goose-16 Nov 26 baseline: `git show b9c04470:CONTINUE.md`
- Waves 1–4, `squid doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
