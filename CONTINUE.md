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

## Pinned history & evidence

Superseded checkpoint narratives from 17–22 November 2026 (Blot vNext `71345e22`,
compilation-speed & runtime push `dfc8c989`/`a0ad4557`/`73aadb42`/`06d7ba75`,
earlier `be489b79` runtime qualification, and 18–20 November incremental logs)
are preserved in pinned Git history (`git show a1a117b5:CONTINUE.md`) and in
their dedicated task and measurement records:

- [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

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
