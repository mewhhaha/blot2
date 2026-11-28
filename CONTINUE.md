# Working on Squid and Gdev

## Current frontier (28 November 2026)

Recent completed milestones on `origin/main`:

- **All-collection SIMD, fast range-push, split-sum & indirect AoS SIMD (`e508d586`):**
  - Shared 16-wide `i32` / 8-wide `i64` `v128` SIMD associative integer reductions (`+`/`^`) across `#[T]`, `%[T]` (Flat & SoA), and `~[T]` (Flat & SoA).
  - Fast counted range-push lowering (`tryEmitFastPushRangeLoop`) with single pre-reserve + 64B/iter `v128` affine/const fill across `#[T]`, `%[T]` Flat/SoA, and direct full-leaf `~[T]` Flat/SoA right-spine append.
  - Header-cached `PACKED_SPLIT_SUM` with dense `OP_br_table` push/match dispatch (with `branchMerge` soundness guard) and shared 16-byte `v128` uniform-tag run skipping (`emitSplitSumHotRun16`) across `%[T]` and `~[T]`.
  - `Seq ~[T]`: 64-element `LEAF_PACKED_SUM` with `4×v128` + `i64.popcnt` O(1) rank, 64 KiB wide slabs, zero-copy `FocusGap -> LEAF_FLAT` promotion, `pop_front` leaf batch refill, radix-16 `LEAF_SPAN` guard fix, and post-`emitAll` `seq_release_fn` export patching for cross-invocation slab reclamation.
  - Generalized `k==3` (12B) cross-nominal (`Pos` + `Vel`) and Shape 2 indirect `ids[k]` AoS `F32` SIMD (`tryEmitAosF32RecordLoop`), plus nominal-aware `tyHasU32` and inner-carry unwrapping for outer deferred-NaN & 5B-2 indirect index scanning.
- **Refreshed benchmark evidence on `e508d586` + `wtime-aot 0.1.11 --guard-pages` (this commit):**
  - **Suite 8 (`benchmarks/collections/`, 12 workloads, 12/12 bit-exact):** Squid wins **#1 fastest overall on 11/12**; **`~[T]` sweeps `imbl::Vector` 12/12** (`1.37×`–`2,895×`); **`%[T]` beats hand-written C++20/Rust manual split-stream** (`376.5 µs` vs `487.9`/`708.9 µs`, `1.30–1.88×`) and **manual SoA** (`728.6 µs` vs `2.86`/`2.75 ms`, `3.77–3.93×`); `flat_scan` `#[U32]` `38.1 µs` (`1.50×` vs C++ `std::vector`) / `~[U32]` `66.9 µs` (`1.43×` vs Rust `Vec`); `random_index` `#[U32]` `268.5 µs` (#1 overall); `cursor_insert` `25.9 µs` (`34×` vs C++ `vector`); `front_deque` `37.6 µs` (`1.58×` vs `imbl`); `frozen_span` `73.2 µs` (`14.2×` vs C++ `vector`); `reverse_ops` `61.7 µs` (`64.8×` vs C++ `vector`, `2,895×` vs `imbl`).
  - **Suites 2–4 (`comparison`):** **6/6** kernels faster than native `rustc -O3` and **5/6** faster than Rust Wasm `-O3`; `aos_vec4` `1.435 ms` (`1.336 ms` `--wasm3`, `2.18×`/`2.34×` vs native Rust); **Ink ECS vs Bevy 0.20.1 wins 4/5** with all 3 dense paths `4.2×–5.4×` faster (`Pool` direct `0.230 ms` = **`5.42×`**, SoA `spark` `0.262 ms` = `4.75×`, cached query `0.295 ms` = **`4.22×`**, sparse `0.089 ms` down `4.05×`, batch spawn `0.124 ms` = `2.64×`, structural churn `74.5 µs` = `1.18×`, snapshot `34.6 µs` = `11.0×`).
  - **Suite 1 (`goose-suite`, 16 benchmarks / 88 impls):** **`1.07×` C++ expert runtime** (`1.79×` faster than idiomatic C++, `1.60×` faster than idiomatic Rust, within `3.4%` of Rust expert, `#1` overall on `sum` `44.1 ms` and `particles` `83.2 ms`), **`0.87×` C++ expert peak RSS** (`#2` overall, `#1` lowest RSS on `strlist`/`words`/`sexp`), and **`27.5 ms` cold build** (`8.2×` faster than `clang++ -O2`).
  - **Suites 6–7 (`bddicken`, `PLB`, recorded at `abb9acaf`):** `bddicken` beats C/C++ 3/3 compute (`loops` `58.8 ms` = `2.14×` vs C, `levenshtein` `47.5 ms`, `fibonacci` `48.1 ms`); `PLB` `2.18×` faster than Go on geomean CPU across 12 problems with `1.83×` less RAM (9/12 wins).
- **Preceding milestones** (rebrand `e7807f00`, initial `%[T]`/`~[T]` `b27d4d3a`/`6a455eae`, `PersistentSafe` numerics `abb9acaf`, Waves 1–3, granular numeric types) are preserved in pinned Git history (`git show 3b71de42:CONTINUE.md`, `git show b9c04470:CONTINUE.md`).

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `squid` | `e508d586` (+ this commit) | All-collection SIMD (`#[T]`/`%[T]`/`~[T]`), fast range-push, header-cached split-sum `br_table` & 16B tag-run skip, `k==3` + Shape 2 indirect AoS SIMD; Suites 1–4 & 8 refreshed on `wtime-aot 0.1.11 --guard-pages` |
| `../pen` | `acf6b0f` (1 dirty) | Rebranded to Squid; last qualified at `92e2ef7` (Stage-0 Squid generators `pen:plugin@0.3.0`, `squid:traps` v1 `f2047ec`, unified `pen test-squid` `eb8f575`) |
| `../ink` | `29b672f` (1 dirty) | Rebranded to Squid + dense/bitset/sparse `ecs.Pool` & `#[U64]` `Entities`; last qualified at `46111bd` + local edits (`493/493` Squid + `257/257` Rust tests) |
| `../gdev` | `373c4ba` (10 dirty) | Rebranded to Squid; last live Vulkan hardware frame qualified at `4e891d2` (and verified byte-identical 640×480 PNG on Wave 3 `b9c04470`) |
| `../wtime` | `91d6cfe` (22 dirty) | `wtime-aot 0.1.11` (`x64-v4`, `--guard-pages`) |

## Hard Invariants

- **Guest ABI 8:** `squid:abi` v8 and `squid:invocation` v1 unchanged (Page-0 offset `640` = `arena_oom_flag`, offset `772` = optional trap-site ID; optional `squid:finish_invocation`, `squid:kernels`, `squid:processes`, `squid:traps` v1; `squid:tests` v1 in `--test` builds only).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15` uses `request == 0` host→guest provenance (`CAP`, `CTL`, `BATCH_ERR`, `BATCH_OK`), strips live-only `CAP` before `Recorded`, filters `request == 0` in `ink/lib/pen/host.sq`, and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries` are excluded and cleared on restore; `world_storage.sq` preserves `input` (3), `god_hand` (114), optional `impact` (157 v1), canonical scene section order, and immediate `restore_scene` + `app.hold_frame` on `restore_stash`.
- **Canonical quiet NaN determinism:** `0x7fc00000` (`F32`) and `0x7ff8000000000000` (`F64`) across `function_spark`, `scalarOp`, `std/simd`, and `#run` (elided only when whole-program float-bit observability proves NaN payloads cannot be observed).
- **Unified ownership & layout symbols:** `#[T]` (`Array T`, `#[N; T]` fixed-length, 1-byte packed `#[Bool]`/`#[U8]`), `%[T]` (`Packed T` automatic SoA / split-stream), `~[T]` (`Seq T` reversible generative SIMD-RRB), and `*T` (frozen read-only handle). `&T`, `&[T]`, `^T`, and `*T` are read-only; in-place mutators enforce unique ownership (`ownedInPlacePath`), keeping module `const` pools deeply immutable (`mode = 2`).

## Verified Identities & Qualification Evidence

Historical qualification records below qualify their exact cited revisions, not later edits.

- **Current built `squid` artifacts (`e508d586`):**
  - `compiler-goose/build/squidc-goose`: SHA-256 `4cd57042376a936e31f0cffc9a55adba8a7e8f7130792f4055dac6021c0179eb` (`11,655,304` B)
  - `generated/compiler/squidc.gz`: SHA-256 `db8c45ce13ac0a5898a6f0eb81d187141ddef3c4570a489ba66733c741eb0c07` (`4,810,555` B)
  - `std/prelude.sq`: SHA-256 `d5670b1e48c9b9ccd8f4aa56c1edd76aa0db23fbfe86592ed9a0f25c433108f9` (`26,986` B)
- **Qualification gates:**
  - `squid` (`e508d586`): full `deno task test:compiler && deno task test:std` passed (`harness` 2.50s, `release-build` 127.01s, `reference-direct` 2/2, `reference-uniqueness` 206/206, `reference-fixtures` 109/109 with `live_bytes == 0` and 3 reviewed SIMD-reduction updates documented in `test_fixtures.py`, `pack`, `preflight-regressions`, `guests` 26.21s incl. expanded `packed_execution`, `seq_execution`, and `spark_simd_phase2` tests, `test:std` 9 modules / 20 tests / 171 assertions).
  - `../pen` (`92e2ef7`, binary SHA-256 `deec51f8d7c689701dcc6c21d70888f59e59b86b9016cfa3353edf2de0bfe0f6`, `plugins/squid.wasm` SHA-256 `3f291f7a3e6c203b959ceaf19d1b808e77e35dbb3c79522a52380a88b103c901`): `plugins/squid` (24/24), `pen-plugins` (9 unit + 10 WASI integration), `pen plugin_build` (4/4), `pen test-squid` Stage-0 smoke; `f2047ec` qualified `pen-runtime` (218/218), `squid-host` (33 unit + 11 integration), and `pen squid_test` (17/17).
  - `../ink` (`46111bd` + local edits): `pen test-squid --project ../ink` **493/493** Squid tests (108 modules, `1.7 s`) + **257/257** native Rust f64-reference tests (`9.43 s`).
  - `../gdev` (`4e891d2`) live NVIDIA Vulkan hardware frame: built via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile` (`320` modules / `4,555` functions, `6,530,935` B `.wasm`, SHA-256 `a51952caafaba76540c566b834e1af736a2d66734a494a4dfd59760ae4ce4d63`, `885.1 ms`) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware` (`640×480` inspected PNG SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`, `frames.trace` `0 7062536994385978 f1af2247052533db`, `guest 9.577 ms`, `render 0.614 ms`, `total 12.497 ms`, 6/6 runner checks `true`).

## Remaining / Optional Next Tracks

1. **Post-rebrand Gdev / Pen / Ink re-qualification:** Rebuild `../gdev` against `squidc-goose` (`e508d586`) + `../pen` (`acf6b0f`) + `../ink` (`29b672f`) via `scripts/integration/build_gdev.ts` and re-qualify the live Vulkan frame via `scripts/integration/run_pen.py --launch --hardware`.
2. **Incremental uniqueness & backend replay (Track 5):** Scope uniqueness validation to the spliced binding's dependency cone and broaden backend body-image replay to push structural edits below `20 ms`.
3. **Remaining backend & library opportunities:** Constant-divisor 64-bit `U64` reciprocals, `F32`/`F64` SIMD reductions in `for`-in loops, and `#[U8]`/`#[F32]` generic flat lane decoders in Ink & Gdev (`codec.decode_lanes` / `codec.decode_record`).

## Pinned History & References

- Waves 1–3, `bddicken`/PLB/Goose-16 Nov 26 baseline: `git show b9c04470:CONTINUE.md`
- Waves 1–4, `squid doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Earlier checkpoints: `c482fccb`, `7c06d4e6`, `98f277f2`, `67fc95b8`, `d0ae1652`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
