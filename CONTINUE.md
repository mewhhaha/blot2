# Working on Blot and Gdev

## Current frontier: Default Self-TCO & Opt-In Wasm 3.0 Features (25 November 2026)

Default MVP self-tail-call-to-loop TCO and opt-in Wasm 3.0 flags
(`--tail-calls`, `--relaxed-simd`, `--wasm3`) are complete and qualified
(`blotc-goose` SHA-256
`5e61297b6be2aaf3515671538af8e38a87f3b23ed26953648db7f516940a9eb7`, `8,516,776` B;
`generated/compiler/blotc.gz` SHA-256
`bf2dad2e0e4f6c140599cf962d315f708b6bae1fcad3c7f1e5634191d24c86d4`, `3,679,802` B),
keeping default compilation 100% deterministic (canonical `0x7fc00000` quiet NaN)
and admitted by both V8/Deno and `wtime-aot --backend x64`, while unlocking Wasm
3.0 general tail calls (`return_call`) and fused SIMD multiply-add
(`f32x4.relaxed_madd` / `f32x4.relaxed_nmadd`) behind opt-in flags:

- **Default Self-TCO & Opt-In Wasm 3.0 Features (this commit, after `08c35720`):**
  - **Flag plumbing & compiler identity isolation (`direct/writer.goose`, `direct/function_ops.goose`, `main.goose`, `driver/cli.goose`, `host/cli.ts`, `host/zig_project_client.ts`):**
    Added `--relaxed-simd`, `--tail-calls`, and `--wasm3` (enabling both) to
    `blotc` (`build`, `build-project`, `serve-project`), `host/cli.ts`, and
    `ZigProjectCompilerOptions` (`relaxedSimd`, `tailCalls`, `wasm3`). When
    non-default flags are active, `configureWasmFeatures` mixes `"wasm-features"`
    into `configured_identity` via `blake3` to keep build/cache keys isolated
    while keeping default output and default identity byte-identical.
  - **Default MVP self-TCO loop + opt-in `return_call` (`direct/function.goose`, `direct/function_entry.goose`, `direct/function_control.goose`, `direct/function_calls.goose`):**
    Lowered eligible self-tail calls by default into a parallel-swap-safe
    `OP_loop` backedge (`push` args → reverse `lset` into `self_tco_inputs` →
    clear caches → `br self_tco_loop`), guarded against `fork` rollback regions
    (`tco_inhibit`), active handles, scratch cuts, and releasing loops. Under
    `--tail-calls` / `--wasm3`, eligible non-self tail calls with matching result
    shapes emit Wasm 3.0 `OP_return_call` (`0x12`), skipping `inlineSmall` on
    call-bearing callees so mutual recursion stays in tail position and guarding
    entry/exit `release` wrapping with `!f.emitted_return_call`.
  - **Opt-in `--relaxed-simd` FMA lowering (`direct/function_control.goose`, `direct/function_spark.goose`):**
    Added `f32x4.relaxed_madd` (`0xfd 0x105`) and `f32x4.relaxed_nmadd`
    (`0xfd 0x106`) lowering across all three blocked/vectorized matmul paths
    (`6B-1`, `5C`, `4C`), `spark`/`for` auto-SIMD (`x*y + z`, `z + x*y`,
    `z - x*y`), and escape-time SIMD (`6C`, `5E`), preserving canonical
    `0x7fc00000` NaN normalization where required.
  - **Deno V8 FMA measurements & `wtime-aot x64` compatibility note:**
    On AMD Ryzen 7 7800X3D (Deno V8, median of 15 runs, `blot_kernels.blot`
    default `21,355` B vs `--relaxed-simd` `21,163` B with `64 × f32x4.relaxed_madd`):
    `matmul_64` `0.0210 → 0.0184 ms` (**1.15× faster**, exact checksum `6538500`),
    `particle_spark_simd` `0.4531 → 0.4263 ms` (**1.06× faster**, exact checksum
    `13338354`), and `mandelbrot_f32` `0.7008 → 0.6733 ms` (**1.04× faster**,
    checksum `1686413` vs `1686408` — 5 boundary pixels shifted by 1 iteration
    from single-rounding FMA vs IEEE two-rounding `mul+add`, confirming why
    `--relaxed-simd` must remain opt-in). Verified `wtime-aot 0.1.1 --backend x64`
    cleanly admits default `blot_kernels.wasm` and default self-TCO modules;
    `wtime-aot`'s `x64_validate_features()` currently rejects `tail_call` and
    `relaxed_simd` (`ErrorKind::DisabledFeature`), so those opt-in flags target
    V8/Deno and `wtime-runtime` today and are ready for `wtime-aot x64` once
    enabled upstream.
  - **Qualification:** `deno task test:compiler` (`1127 passed | 0 failed` guests
    incl. new `tests/guest/wasm3_features_execution.test.ts`, `109/109` fixtures
    byte-identical, `206/206` uniqueness), `deno task test:editor` (`6/6`),
    `deno fmt --check` & `deno check`, and `../pen` (`cargo test -p blot-host`
    `40/40` + `examples/bounce` `pen check`).

- **Tier 6 direct-backend runtime optimizations (`08c35720`, after `a6fe57b1`):**
  Qualified at `blotc-goose` SHA-256 `cc6640fc5c4eab7129fcfb1e20248bb804e7f8b91af98801254e869cf38af012`
  (`8,504,056` B; `generated/compiler/blotc.gz` SHA-256
  `d2d340ba703eeddaa13af610b3f4f76a15ad15472a37a4052eb778ccc5def187`, `3,674,983` B),
  sweeping **6 / 6 kernels vs Rust `-O3` Wasm (`0.44×` geomean — 2.29× faster)**,
  beating **native Rust `-O3` on 5 / 6 kernels with a 1.1% dead heat on `matmul_64`
  (`0.54×` geomean — 1.85× faster)**, and pushing Ink ECS pure-Wasm AoS dense loops
  **2.20×–2.57× faster than native Bevy ECS `0.20.1`** (`0.47 ms` Pool direct /
  `0.55 ms` cached query vs `1.22 ms` Bevy) on **`wtime-aot 0.1.1` (`--backend x64`,
  `x64-v3`, `1201395`)**:
  - **6A (4× coalesced `v128` loops for 16-byte `Maybe Vec3` + dynamic `ids` monotonicity classification):**
    Factored `Vec3MaybeMatch` / `matchVec3MaybeSimdUpdate` and added
    `tryEmitVec3MaybeLoop4x` (`direct/function_control.goose`,
    `direct/function.goose`, `direct/function_calls.goose`) to unroll 16-byte
    `Maybe Vec3` updates 4× with descending `48,32,16,0` loads/stores (4× fewer
    `wtime` software bounds checks) and ONE combined `v128.or` + `extract_lane 0`
    tag check across all 4 entities (falling back per-lane when any of the 4 is
    `$Nothing`). Extended `5B-2`'s pre-loop scan (`Fn.indirect_bound_distinct_local`)
    to dynamically classify indirect `ids` into `2` (strictly contiguous
    `ids[k] == ids[0] + k` → zero-`ids`-load contiguous 4× descending `v128`),
    `1` (strictly increasing distinct IDs + `pos_base != vel_base` → 4×
    descending `ids` loads `12,8,4,0` + 4-way pipelined gather/scatter with 1
    combined tag check), or `0` (duplicate/unsorted/self-aliased → sequential
    4× unrolled fallback).
  - **6B (4×8 `2×k`-unrolled matmul + 4-wide `v128` SIMD affine-LCG array-init + `isFiniteVecF32`):**
    Upgraded `tryEmitBlockedMatmulRowLoop` (`direct/function_control.goose`)
    with a 4-row × 8-col (`8 × v128` accumulators) `2×k`-unrolled fast path
    sharing descending `16,0` `b` loads across 4 rows (with descending `4,0` `a`
    loads, odd-`n` `k` tail, 4-row `m % 8` scalar col tail, and fallback to `5C`
    2-row × 16-col / `4C` single-row). Added `tryEmitAffineInitLoop` and exact
    IEEE-754 `isFiniteVecF32` NaN-elision (`convert_{u32,i32}_f32` × finite F32
    constant can never produce NaN) in `direct/function_spark.goose`,
    vectorizing both `matmul_64`'s 2-step matrix init and `merge_sort`'s 1-step
    array init in 4-wide `v128` with exact lane-3 state extraction.
  - **6C (Dual-stream 8-pixel `v128` escape SIMD + `prep_swap`-safe FP comparisons):**
    Upgraded `tryEmitVectorEscapeLoop` (`direct/function_spark.goose`) to emit
    a dual-stream 8-pixel `v128` escape loop executing Stream A then Stream B
    sequentially per step so temporary `pre_exit`/`post_exit` vectors share
    locals (keeping peak live XMM ≤ 14), checking `v128.any_true(v128.or(act_a, act_b))`,
    and combining `it_a + it_b` for 4 lane extracts per 8 pixels (falling through
    to 4-pixel + scalar tails). Lowered `f32x4` `>` / `>=` as operand-swapped
    `f32x4.lt` / `f32x4.le` and escape mask updates as `v128.not` + `v128.and`
    (100% IEEE-754 exact on both V8 and `wtime-aot`, avoiding `wtime-aot x64`'s
    `prep_swap` spill clobber bug when operand `b` reloads into `SFP2`).
  - Regenerated adapters (`structural_adapters.goose`, `json_adapters.goose`),
    added executed-Wasm regression coverage in `tests/guest/tier6_opt_execution.test.ts`
    (all 6A–6C fast paths, tails, NaN canonicalization, duplicate/unsorted/self-aliased
    IDs, aliasing fallbacks, and OOB traps), and passed the full qualification gate
    (`deno task test:compiler` with `1124 passed, 0 failed` guests, `109/109`
    fixtures byte-identical, `206/206` uniqueness, `test:editor` 6/6, Pen
    `cargo test -p blot-host` 40/40 + `examples/bounce`; sibling `../ink` had
    unrelated active user WIP in `lib/audio/acoustics.blot`, with all 241 other
    Ink tests passing).
  - Measured results on AMD Ryzen 7 7800X3D (`wtime-aot 0.1.1 x64-v3`, bit-exact
    checksum parity, [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `mandelbrot_f32` `0.992 → 0.611 ms` (**1.62× faster; 0.20× Rust Wasm, 0.18× native!**),
    `matmul_64` `0.0227 → 0.0199 ms` (**1.14× faster; 0.67× Rust Wasm, 1.01× native dead heat!**),
    `merge_sort` `4.269 → 3.972 ms` (**0.70× Rust Wasm, 0.80× native!**),
    `particle_spark_simd` `0.400 ms` (**0.55× Rust Wasm, 0.58× native!**),
    `prime_sieve` `0.062 ms` (**0.46× Rust Wasm, 0.93× native!**),
    `lcg_recurrence` `0.115 ms` (**0.30× Rust Wasm, 0.34× native!**),
    Ink ECS Pool direct `1.489 → 0.474 ms` (**3.14× faster; 2.57× faster than native Bevy `1.219 ms`!**),
    Ink ECS cached query `1.387 → 0.553 ms` (**2.51× faster; 2.20× faster than native Bevy!**),
    Blot SoA + `spark` SIMD `0.327 ms` (**3.72× faster than native Bevy!**),
    Ink ECS sparse query `0.100 → 0.079 ms` (**1.27× faster; 1.14× Bevy `0.069 ms`**),
    Ink ECS `batch_spawn_10k` `0.301 ms` (**1.07× faster than Bevy `0.322 ms`!**),
    Ink ECS `structural_churn` `15.7 µs` (**5.3× faster than Bevy `83.5 µs`!**),
    Ink ECS `world_snapshot_copy_10k` `16.5 µs` (**24.6× faster than Bevy `405.4 µs`**);
    cold Wasm compile `12.3 ms` (`21,355` B, `7.3×` faster & `70×` smaller than `rustc -O3 wasm32`; `wtime-aot x64` AOT: `4.1 ms`).

- **Tier 5 direct-backend runtime optimizations (`a6fe57b1`, after `fc29d049`):**
  - **5A (`merge_sort` branchless `select`, `memory.copy` tails, `k < dst_len` hoisting & deep inlining):**
    Added `tryIfBranchlessStore` (branchless `select` / `cmov` for same-target
    indexed updates), `tryIfShortCircuitBreak` (direct short-circuit `or`-break),
    `tryEmitCopyTailLoop` (`memory.copy` fast path with disjointness & bounds
    guards), `tryEmitFastMergeLoop` (invariant `k + (mid - i) + (hi - j) <= dst_len`
    hoisting eliminating all inner bounds checks in 2-way merge loops),
    interprocedural handle-preservation (`calleeReturnsParamHandle`), `Tag.usage`
    hoist candidates in `collectLoopArrayUses`, and raised loop-bearing helper
    inlining budgets (`168/152/32`, `break_` support in `canInlineBody`) so
    `merge_pass` and `merge_range` inline completely into `merge_sort`
    (`direct/function_control.goose`, `direct/function_calls.goose`).
  - **5B (Intra-element `v128` SIMD for 16-byte `Maybe Vec3` & pre-loop indirect-index bounds scans):**
    Added `tryEmitVec3MaybeSimdUpdate` (`direct/function_control.goose`) to
    collapse `if let $Some ($Pos { x, y, z }) = pos[idx]: if let $Some ($Vel { ... }) = vel[idx]: pos[idx] := $Some ($Pos { x: x +- vx, ... })`
    into `2 × v128.load + i32x4.extract_lane 0 + f32x4.{add,sub} + v128.store`
    (preserving lane-0 `$Some` tag `0 == +0.0` and arbitrary record field orders
    via `m.recordDestinations`), plus `tryMatchIndirectIndexScan` +
    `Fn.indirect_bound_binding` / `Fn.indirect_bound_len` (`direct/function.goose`)
    to scan read-only `dense_ids`/`sparse_ids` once before `4A` outer loops,
    eliminating all inner bounds checks across Ink ECS `world_step` `cmd 1–3`.
  - **5C (2-row × 16-col `8 × v128` register-blocked outer-row matmul):**
    Factored `matchMatmulKLoop` and added `tryEmitBlockedMatmulRowLoop`
    (`direct/function_control.goose`) to tile 2 rows × 16 columns (`8 × v128`
    accumulators) sharing descending `48,32,16,0` `b` loads across both rows
    with non-overlapping `c_stride >= m` + disjointness guards, 2-row scalar
    tail, and clean odd-row fallback to `4C`.
  - **5D (16-wide `v128` SIMD masked `#[Bool]` & unmasked `#[U32]` reductions):**
    Added `tryEmitVectorReductionLoop` (`direct/function_spark.goose`) processing
    16 `Bool` bytes (descending `12,8,4,0` `v128.load32_zero` + zero-extend) or
    16 `U32` words (descending `48,32,16,0`) per iteration, eliminating branch
    mispredicts in `prime_sieve`'s prime count/sum scan.
  - **5E (4-pixel `v128` outer-loop escape-time SIMD + SIMD `2.0*x → x+x`):**
    Added `tryEmitVectorEscapeLoop` and exact `2.0 * x → x + x` SIMD peephole
    (`direct/function_spark.goose`) to run 4 escape-time pixels simultaneously
    in `v128` with monotone lane disable (`v128.andnot`), `v128.any_true` early
    exit, exact `i32x4.sub(it_v, active_v)`, and scalar tail for `< 4` pixels.
  - **5F (16-wide `4 × v128` SIMD affine LCG recurrence + 8× scalar unrolling):**
    Upgraded `tryEmitAffineUnrollLoop` (`direct/function_control.goose`) with a
    16-wide (`4 × v128` streams advancing by `(A^16, C_16)` exact mod 2³²) SIMD
    fast path for associative `^`/`+` single-accumulator LCG loops and 8× scalar
    parallel-power unrolling for general affine loops.
  - Regenerated adapters (`structural_adapters.goose`, `json_adapters.goose`),
    added executed-Wasm regression coverage in `tests/guest/tier5_opt_execution.test.ts`
    (all 6 passes + edge cases, NaN canonicalization, aliasing fallbacks, OOB
    traps), re-recorded `compiler-goose/tests/fixtures/expected.json` (107 of
    109 byte-identical; 2 shrank from deeper inlining, 0 diagnostic/counter
    changes), and passed the full qualification gate (`deno task test:compiler`
    with `1120 passed, 0 failed` guests, `109/109` fixtures, `206/206`
    uniqueness, `test:editor` 6/6, Ink `pen test-blot` `427 passed, 0 failed`,
    Pen `cargo test -p blot-host`, and `examples/bounce`).
  - Measured results on AMD Ryzen 7 7800X3D (`wtime-aot 0.1.1 x64-v3`, bit-exact
    checksum parity, [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `lcg_recurrence` `0.374 → 0.096 ms` (**3.9× faster; 0.26× Rust Wasm, 0.27× native!**),
    `mandelbrot_f32` `3.344 → 0.992 ms` (**3.4× faster; 0.31× Rust Wasm, 0.29× native!**),
    `prime_sieve` `0.112 → 0.063 ms` (**1.8× faster; 0.45× Rust Wasm, 0.90× native!**),
    `particle_spark_simd` `0.448 ms` (**0.63× Rust Wasm, 0.67× native!**),
    `merge_sort` `6.625 → 4.269 ms` (**1.55× faster; 0.72× Rust Wasm, 0.83× native!**),
    `matmul_64` `0.025 → 0.023 ms` (**0.75× Rust Wasm, 1.14× native**),
    Blot SoA + `spark` SIMD `0.348 ms` (**3.94× faster than Bevy AoS `1.369 ms`!**),
    Ink ECS cached query `2.070 → 1.387 ms` (**1.49× faster; 1.01× Bevy!**),
    Ink ECS Pool direct `1.652 → 1.489 ms` (**1.09× Bevy**),
    Ink ECS sparse query `0.136 → 0.100 ms` (**1.36× faster; 1.45× Bevy**),
    Ink ECS `batch_spawn_10k` `0.293 ms` (**1.12× faster than Bevy `0.329 ms`!**),
    Ink ECS `structural_churn` `15.6 µs` (**5.8× faster than Bevy `90.1 µs`!**),
    Ink ECS `world_snapshot_copy_10k` `23.5 µs` (**17.7× faster than Bevy `416.4 µs`**);
    cold Wasm compile `12.9 ms` (`18,026` B, `7.6×` faster & `83×` smaller than `rustc -O3 wasm32`; `wtime-aot x64` AOT: `4.3 ms`).

- **Tier 4 direct-backend runtime optimizations (`fc29d049`, after `656371cd`):**
  - **4A (Deferred NaN canonicalization on pure-FP counted loops):**
    Added `canDeferLoopF32Nan` / `bodyValidDeferF32Nan` (`direct/function_control.goose`,
    `direct/function_values.goose`, `direct/function_calls.goose`, `direct/function_spark.goose`)
    to split pure-FP counted loops (`0..end-1` with `f.defer_f32_nan = true`, then
    final iteration `end-1` with canonicalization restored) for both `spark` loops
    (`step_soa`, `particle_spark_simd`) and strictly-monotone same-constructor
    `if let` variant-update loops (`world_step` `cmd 1–3`), preserving bit-exact
    `0x7fc00000` NaNs at every observable boundary.
  - **4B (Variant tag-store elision & pre-loop `CheckedLe` bounds hoisting):**
    Recorded `CheckedElem.known_tag` inside lazy variant `match_` arms and
    `recordConstTag` in `wrapVariant` (`direct/function.goose`, `direct/function_data.goose`,
    `direct/function_control.goose`) to skip redundant offset-0 tag `i32.store`s
    on same-tag overwrites; added transitive `CheckedLeBound` + `collectLoopPreBounds`
    pre-loop specialization (`if a <= b`) eliminating inner-loop bounds checks on
    `world_step` `vel[i]` and `merge_range` `src[i]`/`src[j]`.
  - **4C (Register-blocked 4×`v128` matmul `k`-loop + descending `48,32,16,0` BCE SIMD):**
    Added `tryEmitBlockedMatmulKLoop` (`direct/function_control.goose`) to tile
    16 columns (`4 × v128` accumulators) in registers across the entire `k` loop
    with single post-`k` canonicalization, scalar tail for `m % 16 != 0`, and
    runtime bounds/overflow/disjointness guards; reordered 4× unrolled SIMD loads
    and stores in `function_spark.goose` and 4C to descending offsets (`48,32,16,0`)
    so `wtime-aot` Pass 2 BCE coalesces 4 software bounds checks into 1 per stripe
    (without modifying `../wtime`, which had active uncommitted user work).
  - **4D (`CheckedGrow` reuse, depth-3/`spark` inlining & loop-depth-scoped `unique_owned`):**
    Taught `ensureCheckedArray` (`direct/function_storage.goose`) to reuse cached
    `CheckedGrow` entries, hoisted `ensureCheckedGrow` on resized loop arrays,
    raised `inlineSmall` to depth 3 (budgets `72/48/28`) with `spark` bodies and
    `enclosingBody` (`inlined_body_binding`), and scoped `f.unique_owned` by
    `f.loop_depth` (`direct/function.goose`, `direct/function_calls.goose`,
    `direct/function_control.goose`) so inlined `integrate_particles` reuses `out`
    in place across all 32 iterations while never aliasing outer loop-invariant arrays.
  - **4E (Exact `2.0*x → x+x`, 2× scalar `for ever` unroll & 4× strided fill):**
    Strength-reduced exact IEEE-754 `2.0 * x` / `x * 2.0` to `x + x`
    (`direct/function_values.goose`), 2×-unrolled small pure-scalar `for ever`
    loops (`isPureScalarForeverBody`, `mandelbrot_f32`), and added 4×-unrolled
    pointer-increment strided array fill (`tryEmitStridedFillLoop`, `prime_sieve`).
  - Regenerated adapters (`structural_adapters.goose`, `json_adapters.goose`),
    added executed-Wasm regression coverage in `tests/guest/tier4_opt_execution.test.ts`
    (covering all 4A–4E edge cases, traps, NaNs, and loop-invariant alias safety),
    and re-recorded `compiler-goose/tests/fixtures/expected.json` (8 of 109
    fixtures changed Wasm bytes/SHA; 0 diagnostic or work-counter changes).
  - Measured results on AMD Ryzen 7 7800X3D (`wtime-aot 0.1.1 x64-v3`, bit-exact
    checksum parity, [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `particle_spark_simd` `0.718 → 0.390 ms` (**1.84× faster; 0.52× Rust `-O3` Wasm, 0.59× native Rust!**),
    `matmul_64` `0.067 → 0.025 ms` (**2.66× faster; 0.85× Rust `-O3` Wasm, 1.29× native!**),
    `prime_sieve` `0.148 → 0.112 ms` (**1.32× faster; 0.86× Rust `-O3` Wasm**),
    `mandelbrot_f32` `3.49 → 3.34 ms` (**0.97× native Rust `3.45 ms`, 1.09× Wasm**),
    `lcg_recurrence` `0.374 ms` (`1.05×` Wasm, `1.10×` native),
    `merge_sort` `6.62 ms` (`1.16×` Wasm, `1.33×` native),
    Blot SoA + `spark` SIMD `0.657 → 0.332 ms` (**1.98× faster; 3.67× faster than Bevy AoS `1.22 ms`!**),
    Ink ECS Pool direct `2.22 → 1.65 ms` (**1.35× faster; 1.36× Bevy**),
    Ink ECS cached query `2.47 → 2.07 ms` (**1.19× faster; 1.70× Bevy**),
    Ink ECS sparse query `0.151 → 0.136 ms` (`2.01×` Bevy),
    Ink ECS `batch_spawn_10k` `0.363 → 0.290 ms` (**1.25× faster; 1.10× faster than native Bevy `0.319 ms`!**),
    Ink ECS `structural_churn` `18.9 → 15.6 µs` (**5.4× faster than native Bevy `83.9 µs`!**),
    Ink ECS `world_snapshot_copy_10k` `17.1 µs` (**23.2× faster than Bevy `395.9 µs`**);
    cold Wasm compile `12.9 ms` (6 kernels, `13,970` B, `6.8×` faster & `108×` smaller than `rustc -O3 wasm32`; `wtime-aot x64` AOT: `3.5 ms`).
- **Tier 3 direct-backend runtime optimizations (`656371cd`):**
  - **3A (4× unrolled 16-element `v128` SIMD + streamlined prologues):**
    Unrolled `tryEmitVectorSpark` and `tryEmitVectorForLoop` (`direct/function_spark.goose`)
    to 16 elements (`64 B` cache line) per iteration using immediate
    `mem_offset = 0, 16, 32, 48`, deduplicating shared/self-stream base pointers,
    eliding zero-start/zero-offset arithmetic, and adding `spark` to
    `noStorageResize` and `collectLoopArrayUses`.
  - **3B (Cross-loop `CheckedArray`, branch/short-circuit bounds & `if`-to-`select`):**
    Preserved surviving pre-loop `CheckedArray` entries across non-resizing
    in-place carry loops (`saved_ca`), recorded `CheckedBound` inside `if idx < len:`,
    `if idx >= len:` `else`, short-circuit `and`/`or`, and compound-`or`
    early-exit guards, and added `tryIfSelectConvert` (`direct/function_control.goose`,
    `direct/function_values.goose`) for branchless scalar carry updates.
  - **3C (Selective invalidation, expanded inlining & `CheckedElem` scalar reuse):**
    Added `invalidateCheckedOwner` (`direct/function.goose`), `scanLoopResize` +
    fixed-point `propagateResizedAliases` across `bind`/`update`/nested
    `loopCarries`/`branchMerges` (`direct/function_control.goose`), expanded
    `canInlineBody` (`direct/function_calls.goose`) to include `apply`, `update`,
    and small `loop_` helpers (`ecs.contains`, `put_row`, `bump_insert`,
    `bump_membership`, `spawn_entity`), and cached scalar element values in
    `CheckedElem.val_local` across `ifNode` `then`/`else` branches (`direct/function_storage.goose`,
    `direct/function_data.goose`, `direct/function_control.goose`).
  - **3D (4× algebraic parallel-power affine recurrence unrolling):**
    Added `tryEmitAffineUnrollLoop` (`direct/function_control.goose`) to detect
    pure counted `U32` loops with `s := s * A + C` and compute 4 consecutive
    states in parallel mod 2³² from `base_s`, breaking serial `imul+add`
    latency chains.
  - **3E (Bounded-finite `F32` provenance & lazy variant payload loading):**
    Tracked provably bounded-finite `F32` values (`|x| <= 2^33`, `Fn.finite_f32`
    + `isBoundedFiniteF32` in `direct/function.goose`, `direct/function_values.goose`)
    to omit mathematically dead `f32.eq + select(nan)` on `add`/`sub`/`mul` while
    keeping exact `0x7fc00000` canonicalization everywhere NaN is possible; added
    `resolveLazyVariantArrayRead` (`direct/function_control.goose`) to load only
    the 4-byte tag before branching and load payload words only inside matching
    non-wildcard constructor arms.
  - **3F (Zero-allocation persistent process fast-commit):**
    Added fast-path staging in `direct/function_persist.goose:emitStageRoot(..., is_step = true)`
    for non-recursive unboxed (`SoaWorld`) and boxed (`EcsWorld`) persistent
    roots whose plain-element `Tag.array` handles are bit-identical to the
    committed root, skipping all 7 `open_vec` + 6 `open_hmap` allocations.
  - **`wtime-aot x64` comparison suite & evidence:**
    Switched `benchmarks/comparison/` (`Cargo.toml`, `rust_bench_main.rs`,
    `plot_benchmarks.py`, `README.md`) from `wasmtime` to `wtime-aot 0.1.1`
    (`--backend x64 --target-cpu native --blot-cdylib`, `35850f9`, loaded via
    `libc::dlopen`/`dlsym`), added Tier 3 regression coverage in
    `tests/guest/tier3_opt_execution.test.ts` (including a GOAP-shape nested
    update+push regression caught by `../ink`), regenerated adapters, and
    re-recorded `compiler-goose/tests/fixtures/expected.json` (25 of 109 fixtures
    changed Wasm only, 24 strictly smaller).
  - Measured results on AMD Ryzen 7 7800X3D (`wtime-aot 0.1.1 x64-v3`, bit-exact
    checksum parity, [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `lcg_recurrence` `0.901 → 0.375 ms` (**2.4× faster; 1.01× of Rust `-O3` Wasm `0.372 ms`, 1.08× native**),
    `particle_spark_simd` `0.718 ms` (**0.91× of Rust `-O3` Wasm `0.791 ms`, 1.04× native**),
    `merge_sort` `7.11 → 6.20 ms` (**1.08× of Rust `-O3` Wasm `5.76 ms`, 1.23× native**),
    `prime_sieve` `0.170 → 0.148 ms` (**1.12× of Rust `-O3` Wasm `0.131 ms`**),
    `mandelbrot_f32` `3.49 ms` (**1.14× of Rust `-O3` Wasm, 0.90× native `3.90 ms`**),
    `matmul_64` `0.067 ms` (`2.25×` Rust Wasm),
    Ink ECS `batch_spawn_10k` `0.692 → 0.363 ms` (**1.9× faster; 1.14× of native Bevy `0.319 ms`**),
    Ink ECS `structural_churn` `34.5 → 18.9 µs` (**4.5× faster than native Bevy `84.9 µs`**),
    Ink ECS `world_snapshot_copy_10k` `16.7 µs` (**24.2× faster than Bevy `404.1 µs`**),
    Blot SoA + `spark` SIMD `0.657 ms` (**1.9× faster than native Bevy AoS `1.25 ms`**);
    cold Wasm compile `11.7 ms` (6 kernels, `11,197` B, `7.3×` faster & `134×` smaller than `rustc -O3 wasm32`; `wtime-aot x64` AOT: `3.8 ms`).
- **Tier 2 direct-backend runtime optimizations (`f2632136`):**
  - **2A (Generate closure inlining):** Inlined direct syntactic closures
    `(func i => body)` in `@array.generate` and 2-arg wrappers like
    `std/array.generate` (`direct/function_storage.goose`,
    `direct/function_calls.goose`), eliminating `call_indirect` in
    `ecs_spawn_batch` (0 `call_indirect` in the 9-module Ink ECS Wasm).
  - **2B (Local F32 NaN-canonicalization elision):** Added `scanNanUses` /
    `bindingIgnoresNanPayload` (`direct/function.goose`) to omit per-`let`
    `0x7fc00000` NaN normalization on register-only `F32` locals whose uses are
    strictly `isCanonicalF32Consumer`, while preserving exact `0x7fc00000`
    canonicalization at every return, bitcast, store, call, or join boundary.
  - **2C (`spark` SIMD polish & in-place buffer reuse):** Hoisted loop-invariant
    outer scalar splats and `0x7fc00000` NaN vector outside `OP_loop`, dropped
    dead `iter_vlocal` when unused, and added uniquely-owned destination reuse
    (`unique_owned` + `scanOwnedUses` + runtime `start == 0 && count == cand_len`
    fast path in `direct/function_spark.goose` & `direct/function_control.goose`).
  - **2D (Guard-derived bounds & `ifNode` check preservation):** Recorded
    `CheckedBound` after early-exit guards (`if m >= limit: break`), preserved
    `range.end_local` on local `U32` loop ends, and preserved surviving pre-`if`
    `CheckedArray` entries across `ifNode` branch merges.
  - **2E (Byte-packed `#[Bool]` arrays):** Lowered bare `#[Bool]` elements to
    1-byte stride (`i32.load8_u` / `i32.store8`, single `memory.fill`, 4-wide
    `v128` SIMD load/store via `v128.load32_zero` + `extend_low_*_u` and
    `narrow_*_u` + `v128.store32_lane`, ABI 8 4-byte packet conversion in
    `fromPacket`/`toPacket`, and `FlatNumeric` loops in `function_kernels.goose`)
    while preserving `flatBytes(Tag.boolean) == 4` inside records/tuples/variants.
  - **2F (In-place range `for`-loop auto-SIMD):** Added `tryEmitVectorForLoop`
    in `direct/function_spark.goose` to vectorize simple in-place range `for`
    loops (`dst[dst_off + col] := vec_expr(...)`) into 4-wide `v128` SIMD with
    runtime bounds, non-wrapping, and strict alias/disjointness guards feeding
    into the scalar tail loop.
  - **Host deadlock fix:** Fixed `runFixed`'s `triggerFatalAbort` in
    `host/kernels.ts` to drain `fixedCopyQueue` (`convertQueueToDiscard()`),
    eliminating an intermittent deadlock in `Law #4(b)-(f)` (`byobFaultPool`).
  - Regenerated `structural_adapters.goose` & `json_adapters.goose`, added
    executed-Wasm regression laws in `tests/guest/tier2_opt_execution.test.ts`,
    and re-recorded `compiler-goose/tests/fixtures/expected.json` (24 of 109
    fixtures changed, every one strictly smaller or fewer functions).
  - Measured climb on AMD Ryzen 7 7800X3D (bit-exact checksum parity,
    [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json)):
    `matmul_64` `0.289 → 0.053 ms` (**5.4× over Tier 1; 21.7× over baseline; 1.66× of Rust `-O3` Wasm**),
    `mandelbrot_f32` `4.88 → 3.20 ms` (**1.53×; 0.98× of Rust `-O3` Wasm `3.24 ms`, 0.77× of native `4.13 ms`**),
    `particle_spark_simd` `0.740 ms` (**0.95× of Rust `-O3` Wasm `0.775 ms`**),
    `prime_sieve` `0.223 → 0.170 ms` (**1.31×; 1.45× of Rust `-O3` Wasm**),
    `merge_sort` `7.11 ms` (**1.20× of Rust `-O3` Wasm**),
    Ink SoA + `spark` SIMD `0.638 → 0.428 ms` (**1.49×; 2.9× faster than native Bevy AoS `1.25 ms`**),
    Ink Pool direct `2.31 → 2.07 ms`, Ink cached query `2.31 → 2.11 ms`,
    full-world snapshot `9.1 µs` (**24× faster than Bevy**), structural churn
    `34.5 µs` (**2.4× faster**); Wasm shrank further to `10,879` B (6 kernels,
    **138×** smaller than Rust `-O3`) and `53,231` B (9-module Ink ECS).
- **Tier 1 direct-backend runtime optimizations (`58adc750`):**
  - Extended `noStorageResize`, pre-hoisted loop-invariant `ensureCheckedArray`
    checks, reused pre-RHS element addresses via scoped `CheckedElem`, and added
    `bodyNoAlloc` loop mark/release elision (`tests/guest/loop_hoist_execution.test.ts`).
- **Phase 6 — Retire `check/purity.goose` & unconditional `mode = 2` const pools (`30899f4b`):**
  - Deleted `compiler-goose/src/check/purity.goose` (3,100+ lines) and its
    diagnostic codes (`spark_mutates_capture`, `kernel_mutates_context`,
    `process_mutates_global`, `purity_limit`) plus all `imm_pools` /
    `deeply_immutable_digest` plumbing across `direct/`, `compile.goose`,
    `wire_schema.goose`, and `reuse/`.
  - Because Phase 5 uniqueness bans all mutations of module `const` globals,
    every module `const` pool (and recursive box persisted inside one) is
    unconditionally deeply immutable and emits `mode = 2`
    (`static_pool_flag | live_flag`) in `direct/function_calls.goose`.
  - Regenerated adapters (`structural_adapters.goose`, `json_adapters.goose`)
    and re-recorded `compiler-goose/tests/fixtures/expected.json`: 100 of 109
    fixtures remained byte-identical; the 9 fixtures with module `const` pools
    changed only `wasm_sha256` (identical byte sizes, exit codes, and records).
  - Added positive `spark` deep-copy coverage for flat-element shared
    composites (`copy sw` on `*Holder { arr: #[U32] }`) in
    `tests/guest/concurrency_purity_phase1.test.ts`.
  - Compiler binary shrank by ~409 KiB (`8,496,320` → `8,087,056` bytes),
    release build dropped to `93.08 s`, `../ink` `pen test-blot` dropped from
    `1.7 s` → `1.1 s`, and `../gdev` `pen test-blot` dropped from `72.5 s` →
    `47.6 s` (34% faster).
- **Phase 5 — Enforce owned length mutation & drop `GrowArray`/`ResizeArray`/`seal` (`7da11d2d`):**
  - Removed `#[+T]`/`#[~T]`, `GrowArray`/`ResizeArray`, `seal`,
    `@storage.freeze`, `@storage.reserve`, and `Runtime.freeze` across parser,
    checker, core lowering, direct backend, `std/`, `host/derive.ts`, and tests.
  - Enforced `ownedInPlacePath` on `@storage.push`, `@storage.pop`,
    `@storage.truncate`, and `@simd.store` (supporting `deep` owned array-index
    paths such as `rows[i].owner` and row-polymorphic record fields while
    rejecting views, shared handles, `shell` elements, method dispatches,
    captured locals, borrowed parameters, and module `const`s), locking target
    base places across argument evaluation and weakening via `sharedIntoPlace`.
  - Added uniqueness laws `o01..o07` (206 total) and re-recorded
    `runtime.expected` (7707 bytes), `tests/uniqueness/expected.json`, and
    `tests/fixtures/expected.json`.
- **Phases 1–4 — Soundness fixes, backend hardening, & sibling migrations (`ebf2f026` + sibling checkouts):**
  - Closed `@storage.copy` nested-container ownership and `entry kernel`/
    `entry process` callable holes; hardened `Tag.array` backend invariants
    (stack-to-heap promotion, `fork` journaling, checked-array invalidation,
    `escape_min_slot` promotion); migrated `std/`, `../pen/examples/bounce`,
    `../ink`, and `../gdev` to unified dynamic `Array T` (`#[T]`) and
    `own`-threaded length mutation.

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `656371cd`) | Tier 4 direct-backend runtime optimizations 4A–4E & descending BCE SIMD (`this commit`), Tier 3 direct-backend runtime optimizations 3A–3F & `wtime-aot x64` comparison benchmarks (`656371cd`), Tier 2 direct-backend runtime optimizations 2A–2F & `runFixed` abort fix (`f2632136`), Tier 1 loop-hoist runtime optimizations (`58adc750`), README SVG benchmark charts (`9de59b4c`), Consumer README & Rust/Bevy ECS comparison benchmarks (`7d87b31a`), Phase 6 `purity.goose` retirement (`30899f4b`), Phase 5 owned length mutation & unified `#[T]` (`7da11d2d`) |
| `../pen` | `08e1224` | Unified `#[T]` migration in `blot-host` + `kernels_law6_tests` (`08e1224`); HRTF/EQ/reverb/haptics/text/netplay, GTAO/SSGI/ribbons, Hi-Z occlusion, Session-2 double-restore |
| `../ink` | `fc7259e` | Unified `#[T]` migration across `lib/`, `tests/`, `docs/` (`fc7259e`); Pen 250-lane bindings, SSGI/ribbons, terrain/water/foliage |
| `../gdev` | `017f8cd` | Unified `#[T]` migration across `src/`, `devtools/`, `tests/`, `test_support/`, `performance/` + synced `pen/` bindings (`017f8cd`); Moebius look default |

### Hard Invariants Preserved
- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (zero extra
  exports; Page-0 offset `640` carries `arena_oom_flag`; optional
  `blot:finish_invocation` / `blot:kernels` / `blot:processes`).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15`
  uses unambiguous `request == 0` host→guest provenance (`CAP`, `CTL`,
  `BATCH_ERR`, `BATCH_OK`), strips live-only unrecorded `CAP` before `Recorded`
  (preserving old-Pen `service <= 14` replay compatibility), filters
  `request == 0` events in `ink/lib/pen/host.blot` before `app.advance`, and
  normalizes render packets via `pen_protocol::canonical_render_packet`
  (updating header slots `134` `SERVICE_COUNT` and `135` `SERVICE_LANES`).
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries`
  are excluded from Save 26 and cleared on restore; `world_storage.blot`
  preserves `input` (key 3) and `god_hand` (key 114), canonical scene section
  order, and immediate `restore_scene` with `app.hold_frame` on `restore_stash`.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.
- **Unified dynamic arrays, single update `:=`, value restriction, and read-only references:**
  `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` for fixed-length);
  `#[+T]`/`#[~T]`/`GrowArray`/`ResizeArray`/`seal`/`@storage.freeze`/`@storage.reserve`
  and `=`/`lent`/`purity.goose` are retired; local `let` generalizes only on
  syntactic `func` values; `&T`, `&[T]`, `^T`, and `*T` are strictly read-only;
  `:=`, `@simd.store`, `@storage.push`, `@storage.pop`, and `@storage.truncate`
  enforce unique ownership (`ownedInPlacePath`), guaranteeing all module `const`
  pools are deeply immutable (`mode = 2`).

### Verified Identities & Qualification Evidence
- **Compiler & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `2f78ab22ff9ddeda70a2b52d70aaee5287bcf4e741feb2d8f35342f7ef36db35`
    (`8,329,616` bytes)
  - `generated/compiler/blotc.gz` SHA-256:
    `c6fc85a22eb9df052d562e0c2e45b2d047cb99314f98e264850509dd8eb0b898`
    (`3,612,254` bytes)
  - `std/prelude.blot` SHA-256:
    `eef42c717a9c644a7930f4fc20a646879f5c1afd1f1140f3d945d0d48c4ccdd7`
  - `../pen/target/release/pen` SHA-256:
    `268d82af8ed6d858288df6f94cb4d37c7ab193f7ddf64fd27a1995f2a1e0a003`
- **Qualification gates:**
  - `blot2` (this commit): `deno task test:compiler` exit 0 — `harness` (2.81 s),
    `release-build` (89.81 s), `reference-direct` **2/2** (`runtime` 7707 B,
    `writer` 352 B), `reference-uniqueness` **206/206**, `reference-fixtures`
    **109/109**, `pack` OK, `guests` **1,114 passed, 0 failed, 75 ignored**
    (16.28 s); `deno fmt --check` (85 files), `deno check`,
    `deno task test:editor` (**6/6**).
  - `../pen`: `cargo test -p blot-host` **40/40 passed** (29 unit + 5 concurrency
    + 3 owned_storage + 3 processes), `examples/bounce` `pen check` clean (0.06 s).
  - `../ink`: `pen test-blot` exit 0 against new `blotc-goose` — all Blot
    modules plus **245/245** native f64-reference tests passed (0 failed).
  - `../gdev`: working tree had active uncommitted user edits across 175 files
    (including `src/effects/shader_styles.blot` failing `function_return_required`,
    preserved untouched); Tier 1 (`58adc750`) hardware frame checkpoint on clean
    `017f8cd` remains `build/storage-integration/gdev-one-frame/attempt-n6pdnv2o/frame.png`
    (SHA-256 `e9cd29bf2f844cc5fc5f0b285591ea4d5f908bde1a46fde254e510d540d6a931`). Re-run
    `build_gdev.ts` + `run_pen.py --launch --hardware` once `../gdev`'s active
    `shader_styles.blot` edits compile cleanly.

## Remaining work

1. **Compile-speed & runtime follow-ups.**
   The [compile-speed plan](tasks/FAST_COMPILE.md) retains the subsecond and
   Wasm-size targets (cold Gdev Main 565 ms `-O2` / 432 ms PGO; retained edits
   26–37 ms). Further `trees` / `view` / `write` runtime tuning can target the
   remaining 1.4–1.55× gap to Rust `-O3`.
2. **Pen `timeline::contract_tests` rewind determinism (2 items):**
   - `../ink` `15ad905` (`feat/exposure`): `app.invalidate` sets `exposure.cut := true`
     on the first frame after every restore, causing `exposure[13].cut` (`false`
     vs `true`) to diverge across all 6 `timeline::contract_tests` rewinds.
   - `../gdev` `impact.finger` (`src/effects/impact.blot`): `21542ff` added
     multi-second `finger_heat` (`god_hand` `extra[8].w`) while leaving `impact`
     unsaved (`tests/hand_impact.blot:191` asserts `restored == 0.0`,
     `docs/reference.md:270`), conflicting with
     `rewinds_among_the_crowd_give_the_first_packets` at frame 210 (`0.18177669`
     vs `0.0`). Decide whether to persist `impact` or exempt transient feedback.

## Pinned history & evidence

Superseded checkpoint narratives from 17–23 November 2026 (including Concurrency
vNext Phases 1–5 at `git show 67fc95b8:CONTINUE.md`, Checkpoint F compiler
pruning / Batch 1B–1D at `git show d0ae1652:CONTINUE.md`, and earlier
checkpoints at `git show a1a117b5:CONTINUE.md`) are preserved in pinned Git
history and in their dedicated task and measurement records:

- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
