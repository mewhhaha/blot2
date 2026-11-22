# Working on Blot and Gdev

## Next step: Blot vNext Concurrency, Data-Parallelism & Kernel Architecture (`tasks/CONCURRENCY_VNEXT.md`)

The approved end-to-end architecture plan is finalized and checked in at
[tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) (`v38`, commit
`4d1ded71`; dual-audited to **9.0/10** by GPT 6.2 Sol High and **10.0/10** by
Second Neon on `v37`, with the final `v37` box-aware 4-lane `@simd.load`/`@simd.store`,
standalone native repackaging, and Pen Web asset-list polish folded in).

- **Hard invariants preserved:** Guest ABI 8 (`blot:abi` v8, `blot:invocation`
  v1, zero extra exports), Session Protocol 2 (`Operation 0..=6`, live-only
  unrecorded `CAP`, `request == 0` kernel provenance), Save Schema 26
  (`ink/lib/services.blot` `max_id = 16,777,215` untouched), and canonical
  `0x7fc00000` quiet NaN determinism.
- **Live checkouts at plan lock:** `blot2` (`4d1ded71`), `../pen` (`1505604`,
  preserve existing uncommitted local edits), `../ink` (`4adfd09`, preserve
  untracked `tools/native/target/`), `../gdev` (`a13c3f1`).
- **Start here when resuming ([tasks/CONCURRENCY_VNEXT.md §6.2](tasks/CONCURRENCY_VNEXT.md#62-phased-rollout--checkpoints)):**
  1. **Pre-Phase 1:** Capture and pin the exact pre-change Gdev `pen test-blot`
     passing/failing test identities on live `../gdev` `HEAD` (`a13c3f1`) before
     making any code edits.
  2. **Phase 1:** Language spec updates, lexer/parser/checker/Core for `spark`,
     `entry kernel`, `entry process`, §2.5 context-sensitive relational purity
     proof, `@flat.*` frontend/Core, Phase 1 direct-backend `k == 1` tuple-record
     fixes, escape-safe scalar `Tag.spark` lowering, Phase 1 syntax cleanup
     (incl. renaming both `spark` bindings in `../gdev/src/actors/kites.blot:536, 540`),
     Goose adapters, and Baba/formatter/Tree-sitter (`deno task test:compiler` +
     Law #3).
  3. **Phase 2:** `function_spark.goose` 4-wide Wasm SIMD `v128` auto-vectorization,
     uniform producer-site `0x7fc00000` NaN canonicalization across all 4 emitters,
     `offset = -2` `unpatchableOperand`, and fixture requalification.
  4. **Phase 3:** Persistent arena runtime (active-only exact-cap stack free lists,
     unified transport pool + `blot:reset` release, zero-export Page-0 offset `640`
     `arena_oom_flag`, `rt.escape_min_slot` + `must_undo` + box-aware 4-lane
     `@simd.load`/`@simd.store`, iterative two-phase staging, recursive
     physical-stride `FlatNumeric`, `[0xffffffff]` sentinel, `blot:kernels` /
     `blot:processes`, transitive `LayoutReceipt`) + Laws #1 & #2.
  5. **Phase 4:** Unified `KernelPool` & deterministic `Processes` across Pen
     Rust, Deno TS (`Deno.Command` subprocesses), and Pen Web (`kernels.js` +
     worker script wired into `build.sh`, `Justfile`, and `project.rs:918`),
     plus lockstep migration/retirement of legacy workers/sparks + Laws #4 & #5.
  6. **Phase 5:** Pen `service::KERNEL = 15`, `std/kernel`, `KernelService`,
     Gdev shared `colony_paths.build_mesh_into` + query-keyed route pre-warm,
     Law #6, canonical Save-26/render equivalence, and inspected hardware
     `frame.png`.

Commit and push verified checkpoints to `origin/main` after each phase.

## Phase 1 compiler pruning, on-demand memory, and Batch 1B–1D completion (22 November 2026)

All Phase 1 compiler pruning batches ([docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md)
1A–1D) and the prior runtime/memory items (#1–#4) are implemented, qualified
end to end across `blot2`, `pen`, `ink`, and `gdev`, and checkpointed on `main`:

- **On-demand linear memory (Checkpoint A):** Wasm modules start at 1 page
  (64 KiB) with `memory.grow` up to the planned budget, using a 2-level paged
  owner directory, chunk-list scratch stack with loop-free `rewind_stack` fast
  path and guarded `releaseTo`, and lazy transport/undo buffers. Both
  previously failing Ink committed-memory-cap tests now pass (`113/113` native).
- **Effect-order & owning lowering + Gdev failure reduction (Checkpoints B & C):**
  Effectful trait/contract lowering and structural wrapper preservation fixed;
  Gdev `pen test-blot` failures dropped from 108 → **83** (`1,291 passed, 83
  failed` across all 218 modules).
- **Batch 1C (`5842e97e`, `gdev` `d95f3d9`):** Retired `List` / `@cursor` /
  `std/list` / `std/iter`, `@requests` / `yield` / `complete`, `do (monad ...)`,
  `@record.merge`, custom fixity declarations / backtick operators (replaced by
  the fixed 19-operator built-in table), and `lent` (0 occurrences across all
  four repos).
- **Batch 1B (`bd4d7f79`):** Replaced legacy `eval/` evidence and equation
  machinery (~4.1k LOC) with nominal trait records (`compiler-goose/src/eval/`
  is now **0 LOC**).
- **Batch 1D & scalar/prelude codegen fix (Checkpoint F):**
  - Collapsed `compiler-goose/src/reuse/dependency_payload.goose`
    (**7,038 → 704 LOC**, -90.0%) and `reuse/payload_bytes.goose`
    (**176 → 12 LOC**, -93.2%, O(1)) via the new generator
    [write_dependency_payload.py](compiler-goose/tools/write_dependency_payload.py),
    and stripped all remaining dead Batch 1A–1C wire descriptors (**205 → 161**).
  - Slimmed worker interface replies (omitted retired `fixities` /
    `obligation_spans`, unused `Kind.external` bindings, imported nominal
    diagnostic metadata on signature-only builds, and dead execution-Core tables):
    `parallel_worker_reply_bytes` on Gdev Main dropped from **67.17 → 59.60 MB**
    (`59,597,600 B`, -11.3%).
  - Restored direct `Tag.scalar` / `Tag.associated` lowering for built-in
    scalar operators (`!=`, `<=`, `>`, `>=`, etc.) and fixed
    `core_builder.goose::directArity` for primitive intrinsic aliases (`const
    F32.add = @f32.add`, etc.), eliminating closure allocations and
    `call_indirect` calls in scalar comparisons and `std/prelude.blot` math
    helpers.
- **Compiler footprint & build speed:** **165 `.goose` files, 56,432 LOC**
  (down from 221 files, 70,962 LOC pre-pruning → **-56 files, -14,530 LOC,
  -20.5%**; `eval/` 0 LOC, `reuse/` 11,156 LOC, `check/` 18,234 LOC, `direct/`
  14,535 LOC, `support/` 6,230 LOC). Optimized `-O2` binary **7.0 MB**
  (`generated/compiler/blotc.gz` **3.1 MB**), standalone `-O2` build
  **133.6 s** (down from ~420 s baseline).
- **Verified `-O2` compile & runtime benchmarks (final Checkpoint F candidate):**
  - Cold Gdev Main (295 modules, 2.55 MB source, 8 workers, 3 runs):
    **564.76 ms** median (`544.68`, `564.76`, `629.57 ms`; `load 58 ms`,
    `check 219–231 ms`, `lower 25–28 ms`, `backend 189–211 ms`; peak RSS
    `210–221 MiB`; `parallel_worker_reply_bytes` **59,597,600 B**).
  - Gdev Main Wasm: **3,223,711 B**, **4,655** emitted functions (down from
    4,703 in R2 and 6,228 pre-R2), SHA-256
    `7c9feeb946d71d30066f69028b394edfb03759b37f3cecfad1892cbcd2e05eb9`.
  - Retained Gdev edits (`scripts/integration/time_gdev_edits.ts`, 8 workers,
    3 reps, bit-for-bit oracle verified): `edit` **37.35 ms** median (`32.05`,
    `37.35`, `40.01 ms`), `recover` **25.98 ms** (`25.79`, `25.98`, `31.13 ms`),
    `revert` **30.08 ms** (`27.79`, `30.08`, `33.26 ms`).
  - Checked-grid runtime (`benchmarks/tools/bench_checked_grid.py`, 3 rounds,
    Wasmtime Cranelift, paired against Rust `-O3` in the same run):

    | Workload | Blot (`-O2`, `inline0` / `inline1`) | Rust (`-O3`, `inline0` / `inline1`) | Best Blot vs Rust |
    |---|---:|---:|---:|
    | `hills` | 157.46 / **154.37 µs** | 303.04 / 299.00 µs | **0.52× (1.94× faster)** |
    | `parse` | 20.86 / **14.51 µs** | 18.00 / 18.57 µs | **0.78× (1.28× faster)** |
    | `scan` | **8.84** / 11.91 µs | 8.93 / 9.16 µs | **0.99× (faster)** |
    | `trees` | 1094.49 / **859.46 µs** | 600.87 / 591.01 µs | 1.45× |
    | `packet` | 0.10 / **0.08 µs** | 0.05 / 0.06 µs | 1.33× |
    | `view` | **3.16** / 4.41 µs | 2.04 / 2.09 µs | 1.55× |
    | `write` | **19.08** / 23.54 µs | 13.67 / 13.86 µs | 1.40× |

- **Verified identities & cross-repo qualification (Checkpoint F):**
  - `compiler-goose/build/blotc-goose` (`-O2`) SHA-256: `fa1ec7e9127afdfa8241fe599576c4c09fec619a047a66cd598313806c17c760`
  - `generated/compiler/blotc.gz` SHA-256: `2b465a0728e9fc79fa1e99dbbd60b3e0e23a04f27492ea3b92284fe84921f8cb`
  - `std/prelude.blot` SHA-256: `3472bf7adf59d34b6e24f9fa40445086c1fc84150436ecfbf625e0f2ef743ba1`
  - `../pen/target/release/pen` (`61c8464`) SHA-256: `a5b0de283b5f940703a69a0ebd404b732e80af26e26ff44b67b5a1f498370489`
  - `blot2`: `deno fmt --check` (83 files), `deno check`, `deno task test:editor`
    (6/6), `deno task check:editor` (10/10 parses, 19/19 highlight suites),
    `deno task test:compiler` **exit 0** (`test_direct.py`, `test_uniqueness.py`
    **202/202**, `test_fixtures.py` **109/109**, `pack`, `guests` **1,066 passed,
    0 failed, 76 ignored**).
  - `pen` (`61c8464`): `blot-host` **30/30**, `pen-plugins --test blot --
    --test-threads=1` **8/8**, `bounce` **7/7**.
  - `ink` (`4adfd09`): `pen test-blot` **285/285** across 74 modules (1.4 s) +
    **113/113** native tests; `ink/tools/native` `cargo +1.99.0 test` **113/113**.
  - `gdev` (`d95f3d9`): `pen check` pass (Main 0.51 s, Devtools 0.50 s, state
    adapter checked, 554 assets clean), `pen test-blot` **218/218 modules
    compile** (**1,291 passed, 83 failed**), `run_pen.py --launch --hardware`
    exit 0 (`compiled_wasm_unchanged: true`, `complete_render: true`,
    `screenshot_640x480: true`), visually inspected 640×480
    `build/storage-integration/gdev-one-frame/attempt-zkjptv4u/frame.png`.

## Compilation-speed and runtime-performance push (22 November 2026)

Four reviewed, qualified checkpoints (`dfc8c989` R1, `a0ad4557` C1, `73aadb42` C2,
`06d7ba75` R2) pushed both cold/retained compilation latency and direct-backend
Wasm runtime performance:

- **Direct-backend runtime optimizations (R1 `dfc8c989` + R2 `06d7ba75`):**
  - R1: scoped `CheckedArray` / `CheckedGrow` / `CheckedView` hoisting,
    in-place owner loop carries (`carryStaysInPlace`), method-call
    `apply(project(...))` unwinding, single-op array/storage forwarding,
    `createUninit` + dynamic repeated-byte `memory.fill`, inline
    `GrowArray.push` fast path, dead-load elimination in `indexedUpdate`,
    zero-allocation `continue` skipping, and zero-copy pure entry packet input
    with overlap-safe output.
  - R2: small pure leaf-function inlining (`inlineSmall`, <=72 Core nodes at
    depth 0 / <=24 at depth 1, preserving caller `CheckedArray`/`CheckedView`
    descriptors and recording inlined callees for replay soundness), bulk
    contiguous slice/array-to-`GrowArray` push loops (`tryBulkPushLoop` ->
    single ensure + `memory.copy`), small constant-array `for`-loop unrolling
    (`tryUnrollConstArrayLoop`, 1..4 scalar/nullary elements), compile-time
    constant-tag `match` arm pruning (`Fn.const_tags`), direct inline emission
    of non-exported scalar and nullary-constructor constants (with
    `suppressed_unit` replay soundness in `relocations.goose`), and
    `noStorageResize` `Tag.construct` fix.
- **Compiler latency & retained structural replay (C1 `a0ad4557` + C2 `73aadb42`):**
  - Native asset ingestion & load fast paths, `probeHit` + reusable touched-slot
    `WordMap`, stack free-variable sets, flat arrays in `uniqueness.goose`,
    `blot_copy_u32` / `blot_copy_u8`, pooled container realloc-churn fixes,
    checker `usesAsCapabilityParam` gate and `Tag.variable` leaf fast paths,
    first-byte keyword lexer dispatch, flat per-unit direct-backend caches,
    1-byte LEB128 fast paths, `putExecutionCore`/`getExecutionCore`
    `Constructor.name` fix (24 B/ctor, restoring parallel-build scalar
    relocation and `#variants`), `freezePersistent` trimming, and production
    per-body structural Wasm replay (`reuse/body_image.goose::replayEdits` with
    `State.inlined_callees` soundness tracking).
- **Verified paired `-O2` runtime results (`benchmarks/tools/bench_checked_grid.py`, 3 rounds, Wasmtime Cranelift `inline1` unless noted):**

  | Workload | Pre-R1 | R1/C2 (`-O2`) | **R2 (`-O2`)** | Rust (`-O3`) | R2 vs Pre-R1 | R2 vs Rust |
  |---|---:|---:|---:|---:|---:|---:|
  | `parse` | 194.50 µs | 50.06 µs | **15.25 µs** | 16.24 µs | 12.8× | 0.94× (faster) |
  | `scan` | 11.62 µs | 7.99 µs | **7.92 µs** | 8.04 µs | 1.47× | 0.99× (faster) |
  | `hills` | 725.34 µs | 434.92 µs | **275.34 µs** | 268.07 µs | 2.63× | 1.03× |
  | `trees` | 1131.88 µs | 897.53 µs | **601.50 µs** | 530.43 µs | 1.88× | 1.13× |
  | `packet` | 1.71 µs | 0.06 µs | **0.06 µs** | 0.05 µs | 28.5× | 1.20× |
  | `view` (`inline0`/`1`) | 7.30 µs | 2.83 / 3.63 µs | **2.83 / 3.63 µs** | 1.84 µs | 2.58× | 1.54× |
  | `write` (`inline0`/`1`) | 39.04 µs | 16.97 / 18.30 µs | **16.96 / 18.30 µs** | 12.29 µs | 2.30× | 1.38× |

- **Verified paired cold & retained Gdev Main compile latency (295 modules, 2.55 MB source, 8 workers):**
  - Cold Main: Pre-C1 (`-O2`) **565.97 ms** → C1 (`-O2`) **530.06 ms** → C2 (`-O2`) **428.12 ms** (5-round paired vs C1 `487.10 ms`; `444.76 ms` paired vs R2) → R2 (`-O2`) **473.40 ms** → **R2 (`-O2 + PGO`) 431.61 ms** (`load 53.9 ms`, `check 170.2 ms`, `lower 26.8 ms`, `backend 128.4 ms`; bit-for-bit identical Wasm).
  - Retained Gdev edits (`src/effects/lighting_look.blot`, bit-for-bit oracle verified): `dark` **132.9 → 27.3 ms** (`27.7 ms` PGO), `choose_body` **745.5 → 26.9 ms** (`26.6 ms` PGO), `base_back` **727.2 → 26.7 ms** (`25.5 ms` PGO), `choose_scalar` **725.1 → 26.9 ms** (`26.0 ms` PGO).
- **Verified identities & cross-repo qualification (R2 `06d7ba75`):**
  - `blotc-goose` (`-O2`) SHA-256: `c465b06efe5542a7a4c23af0a8c226801c03b0333347d8f1b8085e82d8a0e4c9`
  - `blotc-goose-pgo` (`-O2 + PGO`, training profile `633a026626dfe99860b0d0c99790f16c4f2d4930e50009fd9122e00a1019797f`) SHA-256: `51c9fb5019fe37ecbd0666c686b95b5af8544c137b3436188b4dc4642cbe75fb`
  - Gdev Main Wasm (identical across `-O2` and PGO): **3,183,295 B**, **4,703** emitted functions (down from 6,228), SHA-256 `5c395121fa28aca2b9d77a297121780f83103fa091a783882cea21f1a54a8ab9`.
  - `deno task test:compiler`: **exit 0** (`harness` 2.9s, `release-build` 154.2s, `test_direct.py` `runtime: 3373 B` / `writer: 352 B`, `test_uniqueness.py` **212/212**, `test_fixtures.py` **189/189**, `pack`, `guests` **1,141/1,141** in 22.6s).
  - `pen` (`b7b3d0f`): `blot-host` **30/30**, `pen-plugins --test blot -- --test-threads=1` **8/8**, `bounce` **7/7**.
  - `ink` (`113bfd7`): `pen test-blot` **285/285 Blot checks** across 74 modules in **1.2 s** (`111/113` native; only the 2 pre-existing 753-page committed-memory-cap tests fail).
  - `gdev` (`5eaa821`): `scripts/integration/run_pen.py --launch --hardware` exited 0 (`compiled_wasm_unchanged: true`, `complete_render: true`), visually inspected 640×480 `frame.png` (`build/storage-integration/gdev-one-frame/attempt-oxekbekj/frame.png`).

## Blot vNext implementation and compiler prune (21 November 2026)

Blot vNext ([docs/language/spec.md](docs/language/spec.md), Revision 4) is
implemented end to end in the Goose compiler, tree-sitter/formatter/editor
tooling, `std/prelude.blot`, `examples/`, and across all sibling repositories
(`pen` `b7b3d0f`, `ink` `113bfd7`, `gdev` `5eaa821`), alongside Phase 1A of the
[compiler pruning roadmap](docs/compiler/VNEXT_ROADMAP.md):

- **Language & backend surface:** implicit-return single-expression `func` and
  block-bodied `func` with `return` / `return use`; `#[T]`, `#[+T]`, `#[~T]`,
  `#[n; T]`, `&[T]`, `*T` (`freeze`/`seal`), and `*(A -> B)`; scoped inline
  `with Effect = { ... }:` handlers; `fork x:` linear speculative undo scopes
  (rejecting `Foreign` inside `fork`); `for #field in #fields T:` /
  `#variants T` / `#if` compile-time unrolling with `val.(field)`; 2A downward
  templated callables, FBIP sum-variant reuse, and `#[n; T]` bounds-check
  elimination.
- **Compiler prune & determinism fix (`71345e22`):** removed 41 retired Goose
  modules across zero-use pre-vNext subsystems (packages/higher-rank, scoped
  capability lifetimes/contracts, numeric proofs, usage contracts, typed code
  staging, language tasks, retired equation/generative/dictionary/resolver/
  cleanup modules, `cli_migrate_stores.goose`). Compiler source shrank from
  **221 → 180 `.goose` files** (**70,962 → 62,074 LOC**), wire descriptors
  shrank from **205 → 175**, and the optimized compiler release build dropped
  from **~7m → 183.6 s** (`8.4 MB` binary, `3.7 MB` `blotc.gz`). Removed
  `blot_check_effects::Row` from `FLAT_SLICES` in `write_project_packet.py`
  (fixing uninitialized `Tail.closed` union payload bytes in cross-worker
  interface packets) and enforced a generator-time invariant rejecting tagged
  unions from `FLAT_SLICES`.
- **Verified qualification (candidate `blotc-goose` SHA256 `af66ea227fff97ffaeea4356c46aac8da9552eb1be29d480b6a9bf6c2e141a2d`, `std/prelude.blot` SHA256 `6f0fa1e17aa2673905355bf5eb02370e908827d9d609a8164187821eff351ca0`):**
  - `blot2`: `deno fmt --check`, `deno check`, `deno task test:editor` (6/6),
    `deno task check:editor` (10/10 tree-sitter parses + 19 highlight suites),
    `test_direct.py` (`runtime: 3373 B`, `writer: 352 B`),
    `test_uniqueness.py` (**212/212**), `test_fixtures.py` (**189/189** with
    zero exit/Wasm diffs from `std/prelude.blot` migration),
    `deno task test:guest` (**1,140 passed, 0 failed, 92 ignored** in 27 s).
  - `gdev` (`5eaa821`): `scripts/integration/build_gdev.ts` compiled **295
    modules / 6,932 functions** in **666 ms** (**2,680,686 Wasm bytes**);
    `scripts/integration/run_pen.py --launch --hardware` exited 0 with
    `compiled_wasm_unchanged: true`, `complete_render: true`, and visually
    inspected 640×480 `frame.png`
    (`build/storage-integration/gdev-one-frame/attempt-rb2094f7/frame.png`).
  - `ink` (`113bfd7`): `pen test-blot` passed **285/285 Blot guest checks**
    across 74 modules in 3.1 s (`230 checks`, `51 must trap`,
    `4 must not compile`); `ink_tools` native passed **111 passed, 2 failed**
    (the 2 pre-existing committed-memory-cap failures below).
  - `pen` (`b7b3d0f`): `pen test-blot --project ../pen/examples/bounce` passed
    **7/7 checks** across 2 modules in 0.1 s.

### Next compiler pruning frontier

Phase 1 (Batches 1A–1D of [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md))
is complete, except for the ~25-LOC `=` (`tag_store_stmt` / `UpdateInfo.store`)
compatibility shim retained pending `tasks/MEMORY_MODEL.md` Phase 3 (see
Remaining work item #1 below).

## Earlier Gdev & backend checkpoint notes

The Gdev backend experiment can now compile its baseline before learning
which function will change. The simulation edit measured **165.6 ms** for
full emission and **12.7 ms** to screen the checked modules, recompile one
body and assemble identical Wasm. Forking, reading all 293 checked modules
and writing the candidate took **52.3 ms**. The production session last
measured **182 ms** end to end. Next, use the session's existing unchanged-module
information and track declaration dependencies across edits.
[Checkpoint timings, input identities and qualification](tasks/FAST_COMPILE.md#choosing-the-edit-after-initial-emission)

On Gdev `cc4bbbf`, a running compiler rebuilds input, simulation and
rendering edits in **201, 182 and 189 ms** median, down from **235, 206
and 207 ms**. Fresh Main took **702 → 697 ms** across 32 pairs, within
timing uncertainty. The structural replay experiment above isolates backend time.
Adding a multiplication to one simulation call cost **117 ms** in the backend,
and just **one of 7,028** emitted function bodies changed. Both GPU captures,
the replay and both reference renderers matched.
[Stage timings, comparison with fresh Wasm and qualification](tasks/FAST_COMPILE.md#checking-game-stages-independently)

The checker now skips substitution setup for schemes without variables or
obligations and reuses unchanged types during substitution. Pinned Gdev
created **20.8% fewer substitution nodes**, and the fixed 20-module
dependency path created **31.4% fewer**. Fresh release builds measured
**661 → 654 ms** in 24 pairs. The interval included zero. A retained
lighting edit took **42 ms**, checking one module and emitting complete Wasm.
[Substitution counts, timings and qualification](tasks/FAST_COMPILE.md#reusing-unchanged-types-during-substitution)

Fixed scalar scans now reuse the checked array descriptor across a proved range.
With release inlining the scan measured **13.45 → 12.87 µs** median and **25.86 →
21.84 µs** p95. Pinned Gdev retained identical Wasm and measured **817 → 824 ms**
across six fresh-build pairs under load.
[Checked ranges, native instructions and controls](tasks/121-qualify-and-measure-owned-applications.md#reusing-the-descriptor-in-a-scalar-range)

On pinned Gdev Main, unification takes **17.2% fewer recursive resolver
entries**. The checker makes **559,567 fewer** entries overall. Open function
unification measured **19.94 → 15.39 ms** in an isolated CPU benchmark.
Pinned eight-worker fresh builds measured **789 → 810 ms** across 24 pairs.
The latest tested Gdev (`5e98f8b`) measured **1,022 → 991 ms** in six pairs.
All four timing intervals include zero, and all four revisions kept identical
Wasm. Next, sample variable substitution and effect-row handling on the
unchanged function operands that still account for 540,795 recursive entries.
[Unification work, release timings and qualification](tasks/FAST_COMPILE.md#unifying-ordinary-function-types)

The preceding change cut imported constructor finalization from 589,219 to
56,129 visits on the pinned input.
[Constructor measurements](tasks/FAST_COMPILE.md#finishing-imported-constructor-types)

On Gdev Main the Wasm backend read 728 constructor signatures, all from their
defining modules. Workers now omit all **41,786** imported copies. This removed
**80,419 Core type nodes** and cut worker replies from **71.28 to 67.17 MB**.
Fresh Gdev compiles measured **853 → 849 ms** in 16 pairs and **1,303 → 1,308
ms** in a busier 24-pair window. Both timing intervals included zero. The
2,754,496-byte Wasm, Ink outcomes, hardware frame and replay matched.
[Constructor reads, packing experiment and release measurements](tasks/FAST_COMPILE.md#constructor-signatures-in-wasm-compilation)

The previous change cut local inference nodes created by imports from
306,968 to 263,793 by deferring known constructor results.
[Local import reads and measurements](tasks/FAST_COMPILE.md#deferring-imported-constructor-results)

The previous checker change reused settled expression and binding types and
generic call arguments. An earlier prototype cut imported nodes by 41% but
changed an exact inference-budget boundary. Its two edit-count failures also
reproduce on the unmodified debug compiler. The optimized release passes both.
[Finalization measurements and import experiments](tasks/FAST_COMPILE.md#final-types-generic-calls-and-imported-definitions)

The type checker now shares repeated tuple and record shapes in inferred
generic results. On 13 nested pair declarations, checking went from
**33.9 to 4.3 ms** and type nodes fell from **32,934 to 880**. The new
checker also checked 22 declarations in 7.2 ms. The previous process
exceeded the one-second deadline on that input. Gdev showed no measurable
whole-build gain in the paired run. [Scaling curves and qualification](tasks/FAST_COMPILE.md#sharing-inferred-tuple-and-record-signatures)

The previous checker change avoids an eager scan of quantified variables
and scales ownership-contract instantiation to the input. Three-term contracts
took **938 → 591 ns**. Across 19 source workloads checker timings were mixed.
Fresh Gdev Main took **975 → 972 ms** in that window with identical Wasm.
[Ownership results and general checker plan](tasks/FAST_COMPILE.md#general-type-checker-performance)

The checker sizes temporary storage to each capability contract. On pinned
Gdev Main, validator calls to clear memory fell from 1.78 GB to 0.30 MB.
Fresh compile medians were **890 → 864 ms** across 30 eight-worker pairs.
The median paired saving was 23 ms (95% bootstrap interval −1 to +34 ms).
[Measurements and output checks](benchmarks/evidence/measurements/2026-11-19-gdev-checker.json)

Splitting Gdev's robot motion, housing and staffing let four consumers start
checking 33–73 ms before the full robot interface was ready. Fresh eight-worker
builds went from **854 to 823 ms** with byte-identical Wasm across 24 pairs.
The active Blot2 work targets finalization, constraint solving and ownership
checking across programs. [General type-checker plan](tasks/FAST_COMPILE.md#general-type-checker-performance)
[Timings and queue traces](tasks/FAST_COMPILE.md#earlier-robot-interfaces-19-november-2026)

An earlier Gdev revision took **870 ms** with eight workers and **1,434 ms**
when the same workers shared two physical cores.
[Phase timings, CPU contention and the dependency chain](tasks/FAST_COMPILE.md#fresh-gdev-compilation-under-cpu-contention-19-november-2026)

`@spark` now maps bounded scalar expressions over one array in order.
`@spawn` asks a scoped provider to admit a child with private Wasm state
and a bounded mailbox. Explicit Deno worker batches reserve all numeric
payload copies and hold their worker slots and memory quota until retirement.
Pen can run registered processes on the caller's thread. Native and Deno
Wasm witnesses preserve private state, terminal mailboxes and replay at each
application tick. `@spark.within` remains unavailable because the array ABI
copies both input and result packets.

Two Deno runs measured **4.99 → 2.39 ms** for 128 Gdev forecasts with
eight workers, and **0.25 → 0.43 ms** for the four-route result with selection.
The native copied worker profile uses a fresh sandbox per job. Keep four-route
gameplay direct. The current evidence measures route stages with fixed inputs.
Production Gdev placement and hard budgets for Pen's blocking prepared workers
remain open. [Native and Deno evidence](benchmarks/evidence/measurements/2026-11-20-spark-process-drivers.json) ·
[Native route stage breakdown](benchmarks/language/NATIVE_ROUTES.md) ·
[Browser route stages](benchmarks/language/BROWSER_ROUTES.md) ·
[Previous compiler, frame and replay qualification](benchmarks/evidence/measurements/2026-11-19-spark-spawn.json)

Whole-pile replacement now takes and returns the salt owner. Authoring 66
piles, replacing them with zero and then one, and restoring the original save
recovers all original IDs, the active slots and the last pile's grid lookup.
The compiler rejects a retained alias of the old grid. The same owning rebuild
prepares a restored world for hauling.

All 1,345 existing Gdev outcomes matched and both new checks passed (1,240
passes and 107 existing failures). All 242 replay files, the hardware frame
and its trace matched. Across seven fresh eight-worker pairs on a shared host,
median Main compile time went from 1,297 to 1,212 ms. Main shrank by 2,543
bytes to 2,718,922. The lookup workload took 2.76 → 2.63 ms with 2,000
piles and 0.55 → 0.59 ms with 256.
[Replacement and restore qualification](benchmarks/evidence/measurements/2026-11-19-owned-pile-replacement.json)

Editing an existing salt pile now takes and returns its owner. Active piles
stay in slot order. A relocated pile queues its own slot for cleanup, and a
sparse sweep produces the same saved world as a full sweep. Player pickups,
haulers and miners use this path. A miner sees earlier successful withdrawals
in its tick and can retry a rejected throw without consuming a brick.

On the pinned Gdev sources, all 1,340 existing test outcomes matched and
three new checks passed (1,236 passes, 107 existing failures). All 242 files
from the 120-frame replay, the hardware screenshot and its trace matched.
Median fresh Main compile time was **966 → 989 ms** across seven eight-worker
pairs with warm files. Main grew **4,929 bytes** to **2,716,145**. Across 17
guest samples, batched edits took 0.408 → 0.373 ms, direct edits took
0.624 → 0.693 ms and the short economy run took 8.44 → 8.88 ms. The complete
published Gdev tree also built and rendered its first frame.
[Inputs, checks and timings](benchmarks/evidence/measurements/2026-11-19-owned-pile-edits.json)

The preceding insertion change made player and worker drops pass one salt owner through pile insertion, the
active index and the cleanup journal. Of 400 seeded piles, the first cleanup
previously queued 33 for another sweep. Checking the final positions left one
genuine retry. After it clears, inserting at slot 400 selects only that slot.
An explicit snapshot survives a later drop, and all three backing arrays keep
their address and capacity when shortened from eight to six and grown to seven.

That pinned Gdev comparison gained one repaired check and three new passes,
with 107 existing failures. All 242 replay files and the hardware frame matched.
Across seven fresh eight-worker build pairs on a shared host, median Main
compile time went from 2,326 to 2,339 ms and Wasm grew by 1,234 bytes to
2,658,171. The subsecond figures below belong to an earlier comparison.
[Salt ownership qualification](benchmarks/evidence/measurements/2026-11-19-owned-salt-insertion.json)

All 44 previously unbuilt Gdev test modules now execute. This includes the 34
blocked on result selection for `from`. The starting-salt, scene, terrain
restore and editor hooks now pass their successor world to their callers.
Ink runs its original 2,048-body prepared-physics workload. Pen releases
invocation-scoped owners and callbacks immediately after a return or a trap.

The Goose compiler now resolves a binary operation on its left operand and
can evaluate an ordinary callback or return a closure from `#run`. A
declared function can use this to build a lookup table from an asset at
compile time and accept its index at runtime.
[Qualification and exact inputs](benchmarks/evidence/measurements/2026-11-19-language-design.json)

A borrowed slice now rejects indexed stores, including writes through a
generic record field. The old compiler let such a helper change the middle
element of `#[5, 7, 11]` to 42 through a slice. Ink's collision and physics
queries now expose read-only ranges. Gdev builds its optional construction
previews separately so the original drawing stays available. The compiler
gate passed 1,109 tests. Ink passed 282 guest checks. The pinned Gdev
hardware screenshot and trace matched the previous frame, as did all 242
files of the 120-frame compiler comparison. All 1,332 named Gdev test
outcomes matched the control (1,224 passed, 108 failed). On six paired
fresh builds with eight workers and warm files, the previous compiler took
899 ms and this release took 873 ms at the median. Both emitted the same
2,656,241-byte Main. The standalone prepared-physics fixture grew by 12,003
bytes. Its normal, walker and joint workloads returned the same results at
256 and 2,048 static colliders.
[Slice and ownership qualification](benchmarks/evidence/measurements/2026-11-19-read-only-slices.json)

Gdev's hauling planner now imports the salt read model independently. Its
Wasm returns the expected height even when the salt writer has a type error.
Writing out public signatures in Ink's motion module gave **791 ms** to
compile Gdev Main and **51 ms** after an edit on eight workers. Leaving
those signatures inferred gave **789 ms** and **50 ms**. Private helpers
remain inferred. [Signature experiment](tasks/FAST_COMPILE.md#export-signatures-and-module-boundaries-19-november-2026)

The previous type-system checkpoint at Blot `be489b79` reduced six layers
of `(x, 0, x)` from a three-second timeout to 3.4 ms. Nested inferred
signatures still grow during construction.
[Type-system assessment](tasks/FAST_COMPILE.md#shared-types-in-ownership-analysis-19-november-2026)

Ordinary `#run` functions can construct records, tuples, constructors, arrays
and lists. `std/build.include` reads project-declared files. A real Gdev
asset probe changed the selected image and observed a new read set. Unselected
file edits reused the complete Wasm. Gdev's existing asset readers are still
in use. Scene consumers check against `SceneHooks world`; a storage edit
rechecked four modules, down from six. A terrain update reused the allocation
for all 169 tiles and preserved a copied snapshot.
[Scene interface](benchmarks/evidence/measurements/2026-11-18-gdev-scene-interface.json)

The released compiler now has a Blot benchmark for building and sharing
lists of Gdev intents. Joining 128 chunks and traversing them fell from
**169.7 to 14.7 µs** using chunk references. Bulk copies fell from 5,282,560
to 1,008 bytes. Grouping the packed payloads by width reserved **45.5 KiB**
for a 4,096-intent tail and two prefixes, down from 160 KiB. Packing still
costs Wasm bytes and the shipping layout remains fixed stride. A private
list can now grow through exclusive tail appends in `case` and `if` arms.
Selecting 1,171 home IDs copied **8,176 bytes** and kept **one owner**, down
from 2,740,140 bytes and 1,172 owners. The saved-prefix and callback-order
laws pass, and the 8,192-input regression now returns its complete array.
[Blot builder experiments](benchmarks/intent/README.md#building-and-sharing-lists-in-blot)

Workers transfer 13 more Core and interface tables as verified Goose arrays.
Across all 269 modules, writing the captured Core records fell from
**36.2 to 4.6 ms**. All 538 portable records matched, and total
checker replies fell from 72,858,303 to 71,856,423 bytes. The full compiler
gate, named Gdev and Ink outcomes, 120-frame replay and inspected frame
qualified the release.

Changing the history capacity from 64 to 65 in `world_storage.blot`
returns finished Wasm in **35.0 ms**, down from **82.2 ms**.
The retained checker reuses the checked type, callee and scalar argument
position. The session copies the changed module’s Core nodes and updates
one Wasm operand. Other body edits still use module-level checking.
[Measurements and qualification](benchmarks/evidence/measurements/2026-11-19-gdev-call-literals.json) · [Compiler work](tasks/FAST_COMPILE.md)

## Earlier runtime qualification at Blot `be489b79`

| Suite | Starting checkpoint | Qualified release |
| --- | --- | --- |
| Gdev Pen | 919 passed, 112 failed, 44 unbuilt | 1,220 passed, 108 failed, all 210 modules execute |
| Ink Pen | 268 passed, 1 failed, 3 unbuilt | 280 passed, all 73 modules execute |
| Ink native | 92 passed, 21 failed on the pre-services reference | 111 passed, 2 failed |
| Compiler | | 192 recorded Wasm fixtures, 212 lowering fixtures, both direct references, 1,101 guest and host tests passed, 100 ignored |

All 919 prior Gdev passes survived. Of the earlier failures, 34 now pass.
Another 267 newly executable checks pass and 30 fail. The remaining 108
failures comprise 70 assertions, 18 stack traps, 11 heap traps and 9 failed
`require` calls. Six independent hauling scenarios now run in Pen.

The qualified release matches every named Gdev and Ink outcome from the
ownership release. Pen checked Main, Devtools and 545 assets. All 242 files
of the 120-frame replay matched, including the final snapshot. The inspected
640×480 hardware frame and trace also matched. The earlier ownership release
used Blot `9b7cd3e8` and Gdev `42e005c`. Its 200,000-frame run measured
0.14 ms median and 1.00 ms p95 guest time on a shared host.
[Ownership qualification](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json)

All 136 prepared-physics exports and 1,800 tower tick packets matched the
reference. Two 16,384-lane compiler witnesses return 16,837 in a 68 KiB
temporary stack after releasing the last read of a terminal scalar producer.
The historical Ink physics source at `58e6b02` still exhausts its stack in
`source_values`.

## Remaining work

1. **Execute Blot vNext concurrency, SIMD `spark`, `KernelPool` & `Processes`
   ([tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md), Pre-Phase 1 →
   Phase 5).**
   Start with Pre-Phase 1 live Gdev baseline capture on `a13c3f1`, then land
   Phases 1–5 with verified checkpoints pushed to `origin/main`.
2. **Migrate remaining borrowed-mutator `=` stores (`tasks/MEMORY_MODEL.md`
   Phase 3) and remove the ~25-LOC `=` compatibility shim.**
   `lent` is completely retired (0 occurrences across all four repos), and
   `#[+T]` / `#[~T]` ownership checks cover array length changes. The remaining
   store compatibility shim (`tag_store_stmt` / `UpdateInfo.store`) is kept
   solely for **487 borrowed-mutator functions / 996 store lines across 212
   files** in `../ink` and `../gdev`, plus `../pen/crates/pen-codegen/src/blot.rs:414`
   (including Gdev's `salt.decode_rows_into` / `write_rows`, tracked by
   [count_stores.py](scripts/integration/count_stores.py)). Once those callers
   migrate to `own` / `:=`, remove the `=` shim completely.
3. **Work through the remaining 83 Gdev `pen test-blot` failures by name.**
   Down from 108 failures at `be489b79` to **83** (`1,291 passed, 83 failed`
   across all 218 modules). Compare affected tests and the 120-frame replay
   against the pinned reference ([raw evidence](benchmarks/evidence/qualification/2026-11-17-owned-runtime.raw.json.gz)).
4. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main is 565 ms `-O2` / 432 ms PGO; retained
   edits are 26–37 ms). Further `trees` / `view` / `write` runtime tuning can
   target the remaining 1.4–1.55× gap to Rust `-O3`.

Keep guest ABI 8, session protocol 2 and save schema 26. The optional
`blot:finish_invocation` export released all six owners after the SIMD fault.
Native, JSPI and worker checks cover callback lifetime across suspension.
The JSPI and worker adapters ran under Deno. The export changed 93 Wasm
references, with every existing fixture function body byte-identical.

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
