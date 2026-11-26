# Working on Blot and Gdev

## Current frontier (26–27 November 2026)

Recent completed milestones on `origin/main`:

- **Direct codegen Waves 1–2 & scalar-project polish (`beff39f7`, `bac9eb2e`):** Compile-time `U32` mul/div/rem strength reduction (shifts/masks + exact 64-bit Granlund-Montgomery reciprocals) and `U64` power-of-two reduction, loop-invariant runtime `U32` div/rem reciprocal hoisting, `knownMutable` / `constU32` BCE and dominating `CheckedArray` preservation, pure scalar binary-recursion-to-loop lowering, unboxed tagged-word Wasm `v128` SIMD128 lowering for `@simd.*` / `std/simd` (plus `Tier 6B-1` matmul `self`-update fix), `isPureScalarProject` hoisting across `noStorageResize`/`scanLoopResize`/`bodyNoAlloc`/`deadFillExprUsesOrCalls`/`isPureSelectExpr`, and 8-byte fast `memory.fill`.
- **Granular numeric types Wave 3 (`b9c04470`):** Built-in `U8`, `I32`, `U64`, `I64`, and `F64` end-to-end across parser, typechecker, Core, dependency adapters, `#run` staging, `std/prelude.blot`, and direct Wasm backend — 1-byte packed `#[U8]` arrays, native `i64`/`f64` lowering & 8-byte arrays, contextual literals with strict range checks (preserving `U32`/`F32` defaults and exact decimal-to-binary32 rounding), full cross-type conversions, canonical `0x7ff8000000000000` NaN on `F64`, and ABI 8 preservation.
- **Cross-language benchmark suites & Wave 4 refresh (`bcf5cf14`, `bac9eb2e` + this commit):** Added `bddicken/languages` (4 workloads) and `PLB` (9 workloads) alongside the 16-benchmark Goose suite in [BENCHMARK.md](BENCHMARK.md) with editorial SVG bar charts. Upgraded benchmarks to native `U64`/`I64`/`#[U8]` and unboxed `v128` `std/simd`: Goose suite geomean runtime dropped `2.90× -> 2.07×` vs C++ expert (**9/16** wins over idiomatic C++, **#1 overall** on `particles` at `179.8 ms`), geomean RSS dropped `1.10× -> 1.03×` (**13/16** wins over idiomatic C++), `bddicken` beats C (`clang -O3`) on **3/4** compute workloads (`loops` `1.81×`, `levenshtein` `1.08×`, `fibonacci` `1.05×`), and `PLB` `pidigits` sped up `2.15×` (`10.13 s -> 4.72 s`).
- **Preceding 26 November 2026 milestones** (value-returning `@storage.push` `c79a8354`, parallel compiler throughput `5a0ddb9a`..`559a0311`, contextual `io` entry syntax `76fabf10`, typed `#kernel`/`#process` coordination `eb4d3d89`, `blotc doc-project`/`blot doc` `df207b98`, and Waves 1–4 compiler soundness) are preserved in `git show ddd6f991:CONTINUE.md`.
- **Installed CLI / sibling checkout note:** `~/.local/bin/blotc` and `~/.local/bin/blot` remain pinned to the pre-`io` build (`df207b98`) until sibling checkouts `../pen`, `../ink`, and `../gdev` migrate from `#entry` to `io` in lockstep.

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `blot2` | `bac9eb2e` (+ this commit) | Direct codegen Waves 1–2 (`beff39f7`), granular numerics Wave 3 (`b9c04470`), scalar-project hoisting & U64/8B polish (`bac9eb2e`), full `bddicken`/`PLB`/Goose-16 benchmark refresh |
| `../pen` | `96cc3b5` (local edits) | Last qualified at `92e2ef7` (Stage-0 Blot generators `pen:plugin@0.3.0`, `blot:traps` v1 `f2047ec`, unified `pen test-blot` `eb8f575`) |
| `../ink` | `bea40aa` | Last qualified at `46111bd` + local edits (`493/493` Blot + `257/257` Rust tests); generic comptime decoders (`f7486d3`) |
| `../gdev` | `1fd0548` (local edits) | Last live Vulkan hardware frame qualified at `4e891d2` (and verified byte-identical 640×480 PNG on Wave 3 `b9c04470`) |
| `../wtime` | `4aee74d` | `wtime-aot 0.1.7` (`x64-v4`) |

## Hard Invariants

- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (Page-0 offset `640` = `arena_oom_flag`, offset `772` = optional trap-site ID; optional `blot:finish_invocation`, `blot:kernels`, `blot:processes`, `blot:traps` v1; `blot:tests` v1 in `--test` builds only).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15` uses `request == 0` host→guest provenance (`CAP`, `CTL`, `BATCH_ERR`, `BATCH_OK`), strips live-only `CAP` before `Recorded`, filters `request == 0` in `ink/lib/pen/host.blot`, and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries` are excluded and cleared on restore; `world_storage.blot` preserves `input` (3), `god_hand` (114), optional `impact` (157 v1), canonical scene section order, and immediate `restore_scene` + `app.hold_frame` on `restore_stash`.
- **Canonical quiet NaN determinism:** `0x7fc00000` (`F32`) and `0x7ff8000000000000` (`F64`) across `function_spark`, `scalarOp`, `std/simd`, and `#run`.
- **Unified `#[T]` ownership & read-only references:** `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` fixed-length; `#[Bool]` and `#[U8]` 1-byte packed); local `let` generalizes only on syntactic `func` values; `&T`, `&[T]`, `^T`, and `*T` are read-only; `:=`, `@storage.push` (value-returning), `@storage.pop`, `@storage.truncate`, and `@simd.store` enforce unique ownership (`ownedInPlacePath`), keeping module `const` pools deeply immutable (`mode = 2`).

## Verified Identities & Qualification Evidence

Historical qualification records below qualify their exact cited revisions, not later edits.

- **Current built `blot2` artifacts (`bac9eb2e`):**
  - `compiler-goose/build/blotc-goose`: SHA-256 `5226e38a479717fe828686d88bdbad7afd31a446364ec13effc42fe67a10cdfc` (`9,929,816` B)
  - `generated/compiler/blotc.gz`: SHA-256 `d7101183e12d87088b96ecc6988ec9052ef267d65876aef91cb8ee5b40191b56` (`4,260,808` B)
  - `std/prelude.blot`: SHA-256 `270281f9f094b781105021bc0b77767a1f18d75b7ec574b05a97579aa8c131db` (`16,508` B)
- **Qualification gates:**
  - `blot2` (`bac9eb2e`): full `deno task test:compiler && deno task test:std` passed (`harness` 2.78s, `release-build` 101.88s, `reference-direct` 2/2, `reference-uniqueness` 206/206, `reference-fixtures` 109/109 with `live_bytes == 0`, `pack`, `guests` 1,019+ tests incl. Wave 1–3 tests, `test:std` 7 modules / 18 tests / 146 assertions).
  - `blot2` (`76fabf10`, contextual `io` syntax): `deno fmt --check` (97 files), `deno check`, `test:editor` (6/6), `check:editor` (11/11 corpus + 19/19 highlight), `blot doc std --test --check-links` (3/3).
  - `../pen` (`92e2ef7`, binary SHA-256 `deec51f8d7c689701dcc6c21d70888f59e59b86b9016cfa3353edf2de0bfe0f6`, `plugins/blot.wasm` SHA-256 `3f291f7a3e6c203b959ceaf19d1b808e77e35dbb3c79522a52380a88b103c901`): `plugins/blot` (24/24), `pen-plugins` (9 unit + 10 WASI integration), `pen plugin_build` (4/4), `pen test-blot` Stage-0 smoke; `f2047ec` qualified `pen-runtime` (218/218), `blot-host` (33 unit + 11 integration), and `pen blot_test` (17/17).
  - `../ink` (`46111bd` + local edits): `pen test-blot --project ../ink` **493/493** Blot tests (108 modules, `1.7 s`) + **257/257** native Rust f64-reference tests (`9.43 s`).
  - `../gdev` (`4e891d2`) live NVIDIA Vulkan hardware frame: built via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile` (`320` modules / `4,555` functions, `6,530,935` B `.wasm`, SHA-256 `a51952caafaba76540c566b834e1af736a2d66734a494a4dfd59760ae4ce4d63`, `885.1 ms`) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware` (`640×480` inspected PNG SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`, `frames.trace` `0 7062536994385978 f1af2247052533db`, `guest 9.577 ms`, `render 0.614 ms`, `total 12.497 ms`, 6/6 runner checks `true`).

## Remaining / Optional Next Tracks

1. **Lockstep sibling migration (`#entry` → `io`, `@storage.push` return) & CLI install:** Migrate `../pen`, `../ink`, and `../gdev` sources together, re-qualify live Gdev Vulkan frame against current `blotc-goose`, and install updated `~/.local/bin/blotc` / `~/.local/bin/blot`.
2. **Remaining benchmark & backend opportunities:** Constant-divisor 64-bit `U64` reciprocals, `#[U8]` stencil SIMD (`v128` byte ops for `blur`), recursive owned-storage lowering, and porting the 4 `F64` PLB workloads (`nbody`, `spectral-norm`, `mandelbrot`, `json-serde`).
3. **Incremental uniqueness & backend replay (Track 5):** Scope uniqueness validation to the spliced binding's dependency cone and broaden backend body-image replay to push structural edits below `20 ms`.
4. **Adopt generic flat lane decoders in Ink & Gdev:** Migrate simple flat decoders to `codec.decode_lanes` / `codec.decode_record`.

## Pinned History & References

- Waves 1–4, `blot doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Earlier checkpoints: `c482fccb`, `7c06d4e6`, `98f277f2`, `67fc95b8`, `d0ae1652`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
