# Working on Squid and Gdev

## Current frontier (27 November 2026)

Recent completed milestones on `origin/main`:

- **Rebrand to Squid (`e7807f00`):** Renamed language, repo (`mewhhaha/squid-lang`), compiler (`squidc-goose` / `generated/compiler/squidc.gz`), CLI (`squid`/`spm`), configs (`squid.json`, `squid-workspace.yaml`, `squid.lock.json`), source extension (`.sq`), Wasm ABI exports/sections (`squid:*`), and sibling checkouts (`../pen` `acf6b0f`, `../ink` `29b672f`, `../gdev` `373c4ba`).
- **Collection families `%[T]` & `~[T]` codegen optimizations (`b27d4d3a`, `6a455eae`):** Added 2-level outer-leaf / inner-element specialized `~[T]` loops (`emitSeqLoopCore`), once-only mutable focus flush, dense 16+1 right-spine leaf append (`ensureSeqTreePushLeaf`), zero-copy `readFlat` inline SoA/Sum packing in `ensureSeqFocusToLeaf`, header-cached `PACKED_SOA` column offsets (`function_packed.goose`), tuned leaf caps, inline FocusGap deque fast paths, and removed 7 spurious `noteAllocation` calls from in-place `Seq` mutators.
- **`PersistentSafe` numeric primitives fix (`abb9acaf`):** Added `U8`, `I32`, `U64`, `I64`, and `F64` to `wire_schema.goose`'s `checkPersistentSafe` and `encodeTypeId` so `#process` / `#kernel` persistent states can hold `#[U64]` (including upgraded `ink/ecs` `Entities` bitsets) and 64-bit / 8-bit scalars, with guest regression coverage.
- **All 8 cross-language benchmark suites refreshed on `wtime-aot 0.1.11 --guard-pages` (`66698119` + this commit):**
  - **Suite 8 (`benchmarks/collections/`):** New 12-workload cross-language collection suite comparing Squid (`#[T]`, `%[T]`, `~[T]`) against C++20 (`-O3 -march=native`: `std::vector`, `std::deque`, manual SoA/split), Rust (`Vec`, `VecDeque`, manual SoA/split), and `imbl::Vector 6.1` with 12/12 bit-exact checksum parity (`~[T]` beats `imbl::Vector` on **11/12** by `1.49×`–`1,199×`, hits `123×` vs C++ `std::vector` on `packed_sum_cow`, `33.6×` on `generative_1m`, `27.1×` on `reverse_ops`, `10–19×` on `cursor_insert`).
  - **Suite 1 (`goose-suite`, 16 benchmarks / 88 impls):** Post-rebrand `abb9acaf` achieves **`1.10×` C++ expert runtime** (`1.88×` faster than idiomatic C++, `1.66×` faster than idiomatic Rust, `#1` overall on `sum` and `particles`), **`0.86×` C++ expert peak RSS** (`#2` overall, `#1` lowest RSS on `strlist`/`words`/`sexp`), and **`29.9 ms` cold build** (`8.5×` faster than `clang++ -O2`).
  - **Suites 2–4 (`comparison`):** **6/6** kernels faster than native `rustc -O3` (`lcg` `4.87×`, `mandelbrot` `6.64×`, `particle_spark_simd` `1.82×`), 8T `mandelbrot` `1.06 ms` (`4.77×` scaling, `4.35×` vs native Rust), `#process` no-op `48.4 ns/step` (`20.67M` steps/sec), Ink ECS updated for upgraded sparse/dense/bitset `Pool` + `#[U64]` `Entities` (SoA `spark` `7.33×`, snapshot `14.8×`, batch spawn `2.17×` vs Bevy 0.20.1).
  - **Suite 6 (`bddicken`):** Squid beats C (`clang -O3`) and C++ on **3/3** compute workloads (`loops` `58.8 ms` = `2.14×` vs C / `2.15×` vs Rust, `levenshtein` `47.5 ms` beating Goose/C++/C, `fibonacci` `48.1 ms` beating C/C++).
  - **Suite 7 (`PLB`, 13 problems / 26 unittests + full SHA-256):** **`2.18×` faster than Go** on geomean CPU across 12 non-trivial problems with **`1.83×` less RAM**, beating Go on **9/12**.
- **Preceding milestones** (direct codegen Waves 1–3, granular numeric types, Wave A/B compiler & `wtime-aot` optimizations, `squid doc`, `#kernel`/`#process`, contextual `io` syntax) are preserved in pinned Git history (`git show b9c04470:CONTINUE.md`, `git show ddd6f991:CONTINUE.md`).

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `squid` | `66698119` (+ this commit) | `~[T]`/`%[T]` codegen optimizations (`b27d4d3a`, `6a455eae`), `PersistentSafe` numerics (`abb9acaf`), Suite 8 + Suites 1–7 refreshed on `wtime-aot 0.1.11 --guard-pages` |
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

- **Current built `squid` artifacts (`abb9acaf`):**
  - `compiler-goose/build/squidc-goose`: SHA-256 `914cfd5a55f9fa58fa60e553d26b814238139b8200ef968ec29342a1dace7651` (`11,514,312` B)
  - `generated/compiler/squidc.gz`: SHA-256 `ed4aca072feaa4f004053444b40387971e52541224e1df22b86d18177fd71153` (`4,768,270` B)
  - `std/prelude.sq`: SHA-256 `d5670b1e48c9b9ccd8f4aa56c1edd76aa0db23fbfe86592ed9a0f25c433108f9` (`26,986` B)
- **Qualification gates:**
  - `squid` (`abb9acaf`): full `deno task test:compiler && deno task test:std` passed (`harness` 2.51s, `release-build` 162.17s, `reference-direct` 2/2, `reference-uniqueness` 206/206, `reference-fixtures` 109/109 with `live_bytes == 0`, `pack`, `guests` 30.84s incl. `packed_execution`, `seq_execution`, and `PersistentSafe` numeric-primitives tests, `test:std` 9 modules / 20 tests / 171 assertions).
  - `../pen` (`92e2ef7`, binary SHA-256 `deec51f8d7c689701dcc6c21d70888f59e59b86b9016cfa3353edf2de0bfe0f6`, `plugins/squid.wasm` SHA-256 `3f291f7a3e6c203b959ceaf19d1b808e77e35dbb3c79522a52380a88b103c901`): `plugins/squid` (24/24), `pen-plugins` (9 unit + 10 WASI integration), `pen plugin_build` (4/4), `pen test-squid` Stage-0 smoke; `f2047ec` qualified `pen-runtime` (218/218), `squid-host` (33 unit + 11 integration), and `pen squid_test` (17/17).
  - `../ink` (`46111bd` + local edits): `pen test-squid --project ../ink` **493/493** Squid tests (108 modules, `1.7 s`) + **257/257** native Rust f64-reference tests (`9.43 s`).
  - `../gdev` (`4e891d2`) live NVIDIA Vulkan hardware frame: built via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile` (`320` modules / `4,555` functions, `6,530,935` B `.wasm`, SHA-256 `a51952caafaba76540c566b834e1af736a2d66734a494a4dfd59760ae4ce4d63`, `885.1 ms`) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware` (`640×480` inspected PNG SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`, `frames.trace` `0 7062536994385978 f1af2247052533db`, `guest 9.577 ms`, `render 0.614 ms`, `total 12.497 ms`, 6/6 runner checks `true`).

## Remaining / Optional Next Tracks

1. **Post-rebrand Gdev / Pen / Ink re-qualification:** Rebuild `../gdev` against post-rebrand `squidc-goose` (`abb9acaf`) + `../pen` (`acf6b0f`) + `../ink` (`29b672f`) via `scripts/integration/build_gdev.ts` and re-qualify the live Vulkan frame via `scripts/integration/run_pen.py --launch --hardware`.
2. **Dense 3-field `#[Pos]` AoS auto-SIMD & Ink ECS query speedup:** Extend `function_spark.goose`'s generalized AoS record auto-SIMD (currently 8B `Vec2` and 16B `Vec4`) to 12B 3-`F32` records (`#[Pos]`/`#[Vel]`) so upgraded `ink/ecs` dense `Pool` loops regain coalesced `v128` speedups over Bevy ECS.
3. **Incremental uniqueness & backend replay (Track 5):** Scope uniqueness validation to the spliced binding's dependency cone and broaden backend body-image replay to push structural edits below `20 ms`.
4. **Remaining `%[T]` / `~[T]` & backend opportunities:** Vectorized `v128` 2-level scans for `~[U32]`/`~[F32]` leaves, constant-divisor 64-bit `U64` reciprocals, and `#[U8]`/`#[F32]` generic flat lane decoders in Ink & Gdev (`codec.decode_lanes` / `codec.decode_record`).

## Pinned History & References

- Waves 1–3, `bddicken`/PLB/Goose-16 Nov 26 baseline: `git show b9c04470:CONTINUE.md`
- Waves 1–4, `squid doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Earlier checkpoints: `c482fccb`, `7c06d4e6`, `98f277f2`, `67fc95b8`, `d0ae1652`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
