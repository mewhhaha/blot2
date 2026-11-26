# Working on Blot and Gdev

## Current frontier (26 November 2026)

Recent completed milestones on `origin/main`:

- **Value-returning `@storage.push` (`c79a8354`):** `@storage.push` returns the updated `#[T]` handle in place (matching `@simd.store` move/fresh/alias/fork-taint rules); `Array.push` in [std/prelude.blot](std/prelude.blot) simplifies to `return @storage.push values value`, and docs/examples/skills use `:= self.push ...`.
- **Parallel compiler throughput (`5a0ddb9a`..`559a0311`):** Parallel `build-project` load/check/lower + deferred-patch parallel Wasm emit pool, compact Core IPC streamed from the persist arena, THP hugepages, and 4-way composite/pure-row fast paths.
- **Cross-language benchmark suites & `wtime-aot 0.1.7` (`b0596602`, `ddd6f991`):** Refreshed kernel/AoS/multi-core/ECS benchmarks on `wtime-aot 0.1.7` (`x64-v4`), added the full 16-benchmark Goose suite with Blot and editorial SVG bar charts, and consolidated all per-suite results in [BENCHMARK.md](BENCHMARK.md).
- **Preceding 26 November 2026 milestones** (contextual `io` entry syntax `76fabf10`, typed `#kernel`/`#process` coordination `eb4d3d89`, `blotc doc-project`/`blot doc` `df207b98`, and Waves 1–4 compiler soundness + Solid-2 diagnostics + `blot:traps` v1 `c5109160`/`7157f22a`) are preserved in `git show ddd6f991:CONTINUE.md`.
- **Installed CLI / sibling checkout note:** `~/.local/bin/blotc` and `~/.local/bin/blot` remain pinned to the pre-`io` build (`df207b98`) until sibling checkouts `../pen`, `../ink`, and `../gdev` migrate from `#entry` to `io` in lockstep.

## Checkpoints on `origin/main`

| Repo | Observed HEAD | Status / Frontier |
|---|---|---|
| `blot2` | `ddd6f991` (+ this commit) | `@storage.push` return (`c79a8354`), compiler throughput (`559a0311`), `wtime-aot 0.1.7` + 16-bench Goose suite (`b0596602`, `ddd6f991`), `BENCHMARK.md` & `CONTINUE.md` cleanup |
| `../pen` | `96cc3b5` (local edits) | Last qualified at `92e2ef7` (Stage-0 Blot generators `pen:plugin@0.3.0`, `blot:traps` v1 `f2047ec`, unified `pen test-blot` `eb8f575`) |
| `../ink` | `bea40aa` | Last qualified at `46111bd` + local edits (`493/493` Blot + `257/257` Rust tests); generic comptime decoders (`f7486d3`) |
| `../gdev` | `1fd0548` (local edits) | Last live Vulkan hardware frame qualified at `4e891d2` |
| `../wtime` | `4aee74d` | `wtime-aot 0.1.7` (`x64-v4`) |

## Hard Invariants

- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (Page-0 offset `640` = `arena_oom_flag`, offset `772` = optional trap-site ID; optional `blot:finish_invocation`, `blot:kernels`, `blot:processes`, `blot:traps` v1; `blot:tests` v1 in `--test` builds only).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15` uses `request == 0` host→guest provenance (`CAP`, `CTL`, `BATCH_ERR`, `BATCH_OK`), strips live-only `CAP` before `Recorded`, filters `request == 0` in `ink/lib/pen/host.blot`, and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries` are excluded and cleared on restore; `world_storage.blot` preserves `input` (3), `god_hand` (114), optional `impact` (157 v1), canonical scene section order, and immediate `restore_scene` + `app.hold_frame` on `restore_stash`.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`, `scalarOp`, `std/simd`, and `#run`.
- **Unified `#[T]` ownership & read-only references:** `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` fixed-length); local `let` generalizes only on syntactic `func` values; `&T`, `&[T]`, `^T`, and `*T` are read-only; `:=`, `@storage.push` (value-returning), `@storage.pop`, `@storage.truncate`, and `@simd.store` enforce unique ownership (`ownedInPlacePath`), keeping module `const` pools deeply immutable (`mode = 2`).

## Verified Identities & Qualification Evidence

Historical qualification records below qualify their exact cited revisions, not later edits.

- **Current built `blot2` artifacts (`c79a8354`):**
  - `compiler-goose/build/blotc-goose`: SHA-256 `0a9296b53ce842fb4b8c66ecef53403199937a945ef1dcc1c2411067f5eb4588` (`10,114,064` B)
  - `generated/compiler/blotc.gz`: SHA-256 `6c1049e59662d63b2812f7fb23775a5c4b9d7ca90c92163b015777b25c873cff` (`4,284,617` B)
  - `std/prelude.blot`: SHA-256 `509f1ea67f28909202a3d81db3e54b41ce251ef9effcba76ffd69770af309e5f`
- **Qualification gates:**
  - `blot2` (`c79a8354`): full compiler qualification passed (`store_uniqueness_execution.test.ts` value-returning `@storage.push` tests, `test_fixtures.py` 109/109 with 108/109 bit-exact Wasm parity and `immutable_survivor.blot` updated).
  - `blot2` (`76fabf10`, contextual `io` syntax): `deno fmt --check` (97 files), `deno check`, `test:editor` (6/6), `harness`, `release-build`, `reference-direct` (2/2), `reference-uniqueness` (206/206), `reference-fixtures` (109/109, zero Wasm diffs), `pack`, `test:guest`, `test:std` (7 modules / 18 tests / 146 assertions), `check:editor` (11/11 corpus + 19/19 highlight), `blot doc std --test --check-links` (3/3).
  - `../pen` (`92e2ef7`, binary SHA-256 `deec51f8d7c689701dcc6c21d70888f59e59b86b9016cfa3353edf2de0bfe0f6`, `plugins/blot.wasm` SHA-256 `3f291f7a3e6c203b959ceaf19d1b808e77e35dbb3c79522a52380a88b103c901`): `plugins/blot` (24/24), `pen-plugins` (9 unit + 10 WASI integration), `pen plugin_build` (4/4), `pen test-blot` Stage-0 smoke; `f2047ec` qualified `pen-runtime` (218/218), `blot-host` (33 unit + 11 integration), and `pen blot_test` (17/17).
  - `../ink` (`46111bd` + local edits): `pen test-blot --project ../ink` **493/493** Blot tests (108 modules, `1.7 s`) + **257/257** native Rust f64-reference tests (`9.43 s`).
  - `../gdev` (`4e891d2`) live NVIDIA Vulkan hardware frame: built via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile` (`320` modules / `4,555` functions, `6,530,935` B `.wasm`, SHA-256 `a51952caafaba76540c566b834e1af736a2d66734a494a4dfd59760ae4ce4d63`, `885.1 ms`) and rendered on `NVIDIA GeForce RTX 4080 SUPER (Vulkan)` via `scripts/integration/run_pen.py --launch --hardware` (`640×480` inspected PNG SHA-256 `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`, `frames.trace` `0 7062536994385978 f1af2247052533db`, `guest 9.577 ms`, `render 0.614 ms`, `total 12.497 ms`, 6/6 runner checks `true`).

## Remaining / Optional Next Tracks

1. **Lockstep sibling migration (`#entry` → `io`, `@storage.push` return) & CLI install:** Migrate `../pen`, `../ink`, and `../gdev` sources together, re-qualify live Gdev Vulkan frame against current `blotc-goose`, and install updated `~/.local/bin/blotc` / `~/.local/bin/blot`.
2. **Close the 16-benchmark runtime gaps identified in [BENCHMARK.md](BENCHMARK.md):** Native `U64` and `U8` array storage, loop bounds-check hoisting, and recursive owned-storage lowering.
3. **Incremental uniqueness & backend replay (Track 5):** Scope uniqueness validation to the spliced binding's dependency cone and broaden backend body-image replay to push structural edits below `20 ms`.
4. **Adopt generic flat lane decoders in Ink & Gdev:** Migrate simple flat decoders to `codec.decode_lanes` / `codec.decode_record`.

## Pinned History & References

- Waves 1–4, `blot doc`, `eb4d3d89` coordination & `76fabf10` `io` entry syntax: `git show ddd6f991:CONTINUE.md`
- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Earlier checkpoints: `c482fccb`, `7c06d4e6`, `98f277f2`, `67fc95b8`, `d0ae1652`
- Benchmarks & tasks: [BENCHMARK.md](BENCHMARK.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- Qualification commands: `deno task test:compiler` for compiler changes; [scripts/integration/build_gdev.ts](scripts/integration/build_gdev.ts) and [scripts/integration/run_pen.py](scripts/integration/run_pen.py) for integration.
