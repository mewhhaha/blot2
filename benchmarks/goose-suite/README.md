# 16-Benchmark Cross-Language Suite: Blot vs Goose, Rust & C++

This page reproduces all **16 benchmarks** from Goose's main benchmark suite (`sum`, `push`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`, `blur`) on the same Linux machine, adding **Blot** (`blotc-goose` → WebAssembly ABI 8 → `wtime-aot` x64) alongside **Goose** (`clang -O2`), **C++20** (`clang++ -O2`, idiomatic and expert), and **Rust** (`rustc -O -C codegen-units=1`, idiomatic and arena/expert).

Every implementation across all 16 benchmarks (88 rows total) runs the exact same workload, generates the same inputs from `xorshift64`, and is verified for **100% byte-for-byte identical checksum output**.

---

## Executive Summary

![16-Benchmark Suite Summary: Blot vs Goose, Rust & C++](../evidence/measurements/2026-11-27-goose-suite/summary_overview.svg)

Across all 16 benchmarks at **medium** size on **AMD Ryzen 7 7800X3D (Linux)**:

- **Cold compile time (geomean):** **Blot builds in 26.9 ms** (`17.9 ms` `blotc-goose` + `8.9 ms` `wtime-aot`, `24.1–31.8 ms` range) — **8.7× faster than C++** (`234.5 ms`), **4.8× faster than Goose** (`128.2 ms`), and **3.2× faster than Rust** (`85.4 ms`), producing self-contained **5.6–17.4 KiB** `.wasm` modules.
- **Peak memory (geomean exact per-process RSS vs C++ expert):** **Blot averages 0.86×** (down from `1.03×` on Nov 26) — **#2 lowest peak memory in the suite**, edging out **Rust expert (`0.87×`)**, **C++ expert (`1.00×`)**, **idiomatic Rust (`1.12×`)**, and **idiomatic C++ (`1.31×`)** (with Goose at `0.73×`). Blot uses less memory than idiomatic C++ on **14/16** benchmarks, less than C++ expert on **11/16**, less than idiomatic Rust on **8/16**, less than Goose on **6/16**, achieves the **lowest peak memory of every language in the suite** on `strlist` (**43.4 MiB**), `words` (**79.6 MiB**), and `sexp` (**109.2 MiB**), and halves `sum` (`129.3 → 64.9 MiB`) and `tree` (`61.1 → 27.9 MiB`) peak RSS via `Array.with_capacity`.
- **Runtime (geomean CPU time vs C++ expert):** Inside a deterministic, bounds-checked Wasm32 sandbox with no LLVM optimizer in the compiler, **Blot averages 1.07× C++ expert** (down from `1.09×` compiler-only Wave B, `1.15×` Wave A, `1.41×` pre-Wave-A on Nov 27, `2.07×` on Nov 26, and `2.90×` originally — **`0.54×` of idiomatic C++** at `1.99×` = **`1.86×` faster**, **`0.63×` of idiomatic Rust** at `1.70×` = **`1.59×` faster**, within **`1.8%`** of Rust expert at `1.05×`, and **`1.15×` of Goose** at `0.93×`; excluding `particles`, **`1.13×` C++ expert / `1.23×` Goose**). Blot beats idiomatic C++ on **15/16** benchmarks (`sum` **1.33×**, `push` **1.18×**, `strlist` **1.52×**, `records` **1.41×**, `tree` **2.68×**, `interp` **1.39×**, `graph` **2.42×**, `words` **1.42×**, `particles` **2.64×**, `sexp` **2.06×**, `lru` **2.75×**, `scene` **1.55×**, `calc` **2.13×**, `bintrees` **10.06×**, `respond` **1.32×**), beats **idiomatic Rust** on **14/16** (`sum`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`), beats **C++ expert** on **6/16** (`sum`, `strlist`, `records`, `graph`, `particles`, `bintrees`), beats **Rust expert** on **6/16** (`sum`, `strlist`, `records`, `graph`, `particles`, `bintrees`), beats **Goose** on **4/16** (`sum`, `strlist`, `particles`, `blur`), and finishes **#1 fastest overall** on **3/16** (`sum` **39.6 ms** vs Goose `47.8 ms` / Rust `49.7 ms` / C++ expert `50.8 ms`, `strlist` **70.9 ms** vs Goose `73.3 ms` / C++ expert `74.3 ms`, and `particles` **83.0 ms** vs C++ expert `185.6 ms` / Rust `186.3 ms` / Goose `192.5 ms`). Notable `wtime-aot` Wave B speedups on top of compiler-only Wave B (`1.09× → 1.07×` geomean): `sum` **`59.9 → 39.6 ms` (`1.51×`)**, `strlist` **`73.5 → 70.9 ms` (`1.04×`)**, `sexp` **`576.3 → 561.4 ms` (`1.03×`)**, `graph` **`85.2 → 83.2 ms` (`1.02×`)**.

---

## Runtime Comparison (All 16 Benchmarks)

Lower is better. Bars are sorted fastest → slowest per benchmark and report best single-process CPU time (`ru_utime + ru_stime`, ms) across 3 timed runs after 2 warmups.

### Benchmarks 1–8: Arrays, Strings, Records, Trees, Dispatch, Graph & Words

![Runtime: Benchmarks 1–8](../evidence/measurements/2026-11-27-goose-suite/runtime_part1.svg)

### Benchmarks 9–16: Particles, S-Expressions, LRU, Scene Graph, Parser, Binary Trees, JSON & Blur

![Runtime: Benchmarks 9–16](../evidence/measurements/2026-11-27-goose-suite/runtime_part2.svg)

---

## Peak Memory Comparison (All 16 Benchmarks)

Lower is better. Measured with a minimal native `posix_spawnp` + `wait4` harness (`ru_maxrss`) so parent-process memory never leaks into child RSS measurements.

### Benchmarks 1–8

![Peak Process Memory: Benchmarks 1–8](../evidence/measurements/2026-11-27-goose-suite/memory_part1.svg)

### Benchmarks 9–16

![Peak Process Memory: Benchmarks 9–16](../evidence/measurements/2026-11-27-goose-suite/memory_part2.svg)

---

## Cold Compile Speed & Blot `.wasm` Output Size

Blot's stacked bars show both `blotc-goose` compilation (dark teal) and `wtime-aot` native x64 compilation (light teal) against full cold builds of `rustc -O`, `goose + clang -O2`, and `clang++ -O2`.

![Cold Compile Time & Blot Wasm Binary Size](../evidence/measurements/2026-11-27-goose-suite/compile_and_size.svg)

---

## Honest Diagnosis: Where Blot Wins and Where the Remaining Gap Comes From

### Where Blot shines

- **Unboxed `v128` SIMD, widening map-reduce & whole-program unobservable-NaN elision (`particles`, `sum`, `blur`, `scene`):** With unboxed `v128` lowering for `F32x4`/`U32x4` and `F64x2`/`U64x2`/`U8x16`/`I16x8`, whole-program float-bit observability analysis, Mode-4 `v128` wide-float worker ABI packing, and `wtime-aot`'s AVX-512/AVX2/NEON widening `u32 -> u64` map-reduce vectorizer, Blot finishes **#1 fastest of every language in the suite** on `particles` (`83.0 ms`, **2.24× faster than C++ expert**, **2.32× faster than Goose**) and `sum` (`39.6 ms`, **1.21× faster than Goose**, **1.28× faster than C++ expert**), pushes `blur` to **`28.3 ms`** (beating Goose `29.8 ms`, down `4.21×` from `119.3 ms`), and drops `scene` to **`59.3 ms`** (down `3.52×` from `208.9 ms`).
- **Validated recursive descriptor workers & arena workloads (`bintrees`, `tree`, `interp`, `scene`, `calc`, `sexp`, `lru`, `respond`, `words`, `records`, `strlist`, `graph`):** SCC-wide recursive owner/effect analysis checks array owners once in the wrapper and passes validated `(base, len)` or `entry` descriptors across recursive calls (with `no_scope_alloc` elision, right-spine associative TCO, 1-level leaf peeling, and external direct worker dispatch), while `.rodata` constant tables, scalar-packed `DirectArray` buffers, wide-aggregate leaf inlining, masked loop-carry `mask == len - 1` proofs, same-array `ifNode` merge reuse, and non-resizing `own`-helper preservation remove redundant owner checks and scratch traffic. `strlist` (`70.9 ms`) finishes **#1 fastest overall**, `bintrees` (`66.5 ms`) and `graph` (`83.2 ms`) beat both C++ expert and Rust expert, `records` (`115.1 ms`) beats C++ expert and Rust, `interp` (`9.7 ms`) sits within `1.8%` of Rust expert, `respond` (`183.3 ms`) beats Goose/C++/Rust DTO, and `sexp` runs **2.06× faster** with **5.78× less memory** than idiomatic C++.
- **Data density (`strlist`, `words`, `sexp`, `records`, `sum`, `tree`):** Native 1-byte `#[U8]` arrays, exact-size `Array.with_capacity` backing, and flat index arenas keep Blot's geomean peak RSS at **`0.86×` of C++ expert** (#2 overall, ahead of Rust expert), with the #1 lowest peak RSS overall on `strlist`, `words`, and `sexp`.
- **Iteration speed:** Without LLVM in the loop, Blot compiles + AOTs all 16 benchmarks in **~26.9 ms geomean** (**8.7× faster** than `clang++ -O2`).

### Why Blot still trails expert LLVM (`clang -O2` / `rustc -O`) by ~7% on geomean (13% excl. `particles`)

1. **Native codegen vs full LLVM backend (`wtime-aot` vs `clang -O2` / `rustc -O`):** `wtime-aot` compiles Wasm in ~9 ms using an SSA optimizer, helper inlining, widening SIMD reduction vectorization, hardware `mul r64` fusion, and cross-block linear-scan register allocation with multi-instruction scratch spill caching, but still trails LLVM's global register allocation and instruction scheduling on large parser/hash bodies (`sexp`, `calc`, `words`, `lru`, `respond`) and wide-call multi-value traffic (`scene`).
2. **Explicit software bounds checks & sandbox guarantees:** Array loads/stores outside proven induction/masked/affine ranges execute explicit bounds checks (while Wasm linear-memory accesses use 4 GiB hardware `--guard-pages`), and observable floating-point outputs preserve deterministic canonical NaNs.
3. **Wasm32 linear-memory address translation & branch-heavy loops (`lru`, `words`, `respond`):** Even with validated descriptor workers and hoisted owner checks, Wasm32 indexed loads add `base + (idx << shift)` on top of the linear-memory base register, and LLVM's GVN/LICM/switch lowering still yields a ~1.2–1.5× edge on branchy hash-table and streaming loops.

---

## Methodology, Hardware & Reproduction

- **Machine:** AMD Ryzen 7 7800X3D (8C / 16T), Linux `x86_64`.
- **Toolchains:**
  - **Blot:** `blotc-goose` (`ff6f061a`, optimized build) + `wtime-aot 0.1.11` (`--backend x64 --target-cpu native --guard-pages --blot-cdylib`, executed via standalone native [`blot_runner.c`](blot_runner.c) reading ABI 8 `#[U32]` checksum packets).
  - **Goose:** `goose` (`d5ae5bb`, `build-precision`, `-O2 --standalone`) + `clang 23.1.5 -O2`.
  - **C++:** `clang++ 23.1.5 -O2 -std=c++20` (both idiomatic and expert variants from Goose's suite).
  - **Rust:** `rustc 1.96.0-nightly (1d419d203 2026-04-06) -O -C codegen-units=1` (idiomatic and arena/expert variants from Goose's suite).
- **Timing & memory:** Every child execution is spawned via [`measure_proc.c`](measure_proc.c) (`posix_spawnp` + `wait4`), recording best single-process CPU time (`ru_utime + ru_stime`), wall time (`CLOCK_MONOTONIC`), and exact per-child peak RSS (`ru_maxrss`). Each implementation runs 2 discarded warmups followed by 3 timed reps, and its stdout is checked byte-for-byte against all other implementations of the same benchmark.
- **Raw recorded data:** [`results.json`](../evidence/measurements/2026-11-27-goose-suite/results.json) (Nov 26 baseline preserved in [`../evidence/measurements/2026-11-26-goose-suite/`](../evidence/measurements/2026-11-26-goose-suite/results.json)).

### Running locally

```sh
# Run all 16 benchmarks at medium size across Blot, Goose, C++, and Rust:
python3 benchmarks/goose-suite/run_suite.py --sizes medium --reps 3 --warmups 2

# Regenerate all 6 SVG bar charts from results.json:
python3 benchmarks/goose-suite/plot_charts.py
```
