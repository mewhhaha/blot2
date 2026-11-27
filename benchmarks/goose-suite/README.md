# 16-Benchmark Cross-Language Suite: Squid vs Goose, Rust & C++

This page reproduces all **16 benchmarks** from Goose's main benchmark suite (`sum`, `push`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`, `blur`) on the same Linux machine, adding **Squid** (`squidc-goose` → WebAssembly ABI 8 → `wtime-aot` x64) alongside **Goose** (`clang -O2`), **C++20** (`clang++ -O2`, idiomatic and expert), and **Rust** (`rustc -O -C codegen-units=1`, idiomatic and arena/expert).

Every implementation across all 16 benchmarks (88 rows total) runs the exact same workload, generates the same inputs from `xorshift64`, and is verified for **100% byte-for-byte identical checksum output**.

---

## Executive Summary

![16-Benchmark Suite Summary: Squid vs Goose, Rust & C++](../evidence/measurements/2026-11-27-goose-suite/summary_overview.svg)

Across all 16 benchmarks at **medium** size on **AMD Ryzen 7 7800X3D (Linux)**:

- **Cold compile time (geomean):** **Squid builds in 29.9 ms** (`20.6 ms` `squidc-goose` + `9.2 ms` `wtime-aot`, `26.6–33.2 ms` range) — **8.5× faster than C++** (`253.1 ms`), **4.5× faster than Goose** (`134.4 ms`), and **3.1× faster than Rust** (`93.3 ms`), producing self-contained **5.6–17.4 KiB** `.wasm` modules.
- **Peak memory (geomean exact per-process RSS vs C++ expert):** **Squid averages 0.86×** (down from `1.03×` on Nov 26) — **#2 lowest peak memory in the suite**, edging out **Rust expert (`0.87×`)**, **C++ expert (`1.00×`)**, **idiomatic Rust (`1.12×`)**, and **idiomatic C++ (`1.31×`)** (with Goose at `0.72×`). Squid uses less memory than idiomatic C++ on **13/16** benchmarks, less than C++ expert on **11/16**, less than idiomatic Rust on **8/16**, less than Goose on **6/16**, achieves the **lowest peak memory of every language in the suite** on `strlist` (**43.4 MiB**), `words` (**79.6 MiB**), and `sexp` (**109.1 MiB**), and halves `sum` (`129.3 → 64.8 MiB`) and `tree` (`61.1 → 27.9 MiB`) peak RSS via `Array.with_capacity`.
- **Runtime (geomean CPU time vs C++ expert):** Inside a deterministic, bounds-checked Wasm32 sandbox with no LLVM optimizer in the compiler, **Squid averages 1.10× C++ expert** (down from `2.07×` on Nov 26 and `2.90×` originally — **`0.53×` of idiomatic C++** at `2.06×` = **`1.88×` faster**, **`0.60×` of idiomatic Rust** at `1.82×` = **`1.66×` faster**, within **`3.6%`** of Rust expert at `1.06×`; excluding `particles`, **`1.16×` C++ expert / `1.33×` Goose**). Squid beats idiomatic C++ on **14/16** benchmarks (`sum`, `push`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`), beats **idiomatic Rust** on **14/16** (`sum`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`), beats **Rust expert** on **7/16** (`sum`, `strlist`, `records`, `interp`, `graph`, `particles`, `bintrees`), beats **C++ expert** on **5/16** (`sum`, `push`, `records`, `particles`, `bintrees`), beats **Goose** on **2/16** (`sum`, `particles`), and finishes **#1 fastest overall** on **2/16** (`sum` **44.5 ms** vs Rust `51.8 ms` / Goose `52.8 ms` / C++ expert `53.0 ms`, and `particles` **86.9 ms** vs C++ expert `190.7 ms` / Rust `193.1 ms` / Goose `201.2 ms`).

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

## Cold Compile Speed & Squid `.wasm` Output Size

Squid's stacked bars show both `squidc-goose` compilation (dark teal) and `wtime-aot` native x64 compilation (light teal) against full cold builds of `rustc -O`, `goose + clang -O2`, and `clang++ -O2`.

![Cold Compile Time & Squid Wasm Binary Size](../evidence/measurements/2026-11-27-goose-suite/compile_and_size.svg)

---

## Honest Diagnosis: Where Squid Wins and Where the Remaining Gap Comes From

### Where Squid shines

- **Unboxed `v128` SIMD, widening map-reduce & whole-program unobservable-NaN elision (`particles`, `sum`, `blur`, `scene`):** With unboxed `v128` lowering for `F32x4`/`U32x4` and `F64x2`/`U64x2`/`U8x16`/`I16x8`, whole-program float-bit observability analysis, Mode-4 `v128` wide-float worker ABI packing, and `wtime-aot`'s AVX-512/AVX2/NEON widening `u32 -> u64` map-reduce vectorizer, Squid finishes **#1 fastest of every language in the suite** on `particles` (`86.9 ms`, **2.19× faster than C++ expert**, **2.31× faster than Goose**) and `sum` (`44.5 ms`, **1.16× faster than Rust**, **1.19× faster than Goose & C++ expert**), pushes `blur` to **`28.5 ms`** (down `4.19×` from `119.3 ms`), and drops `scene` to **`66.9 ms`** (down `3.12×` from `208.9 ms`).
- **Validated recursive descriptor workers & arena workloads (`bintrees`, `tree`, `interp`, `scene`, `calc`, `sexp`, `lru`, `respond`, `words`, `records`, `strlist`, `graph`):** SCC-wide recursive owner/effect analysis checks array owners once in the wrapper and passes validated `(base, len)` or `entry` descriptors across recursive calls (with `no_scope_alloc` elision, right-spine associative TCO, 1-level leaf peeling, and external direct worker dispatch), while `.rodata` constant tables, scalar-packed `DirectArray` buffers, wide-aggregate leaf inlining, masked loop-carry `mask == len - 1` proofs, same-array `ifNode` merge reuse, and non-resizing `own`-helper preservation remove redundant owner checks and scratch traffic. `bintrees` (`67.2 ms`) and `records` (`112.0 ms`) beat both C++ expert and Rust expert, `strlist` (`81.4 ms`), `interp` (`10.5 ms`), and `graph` (`123.3 ms`) beat Rust expert, `push` (`44.5 ms`) beats C++ expert, and `sexp` runs **2.17× faster** with **5.78× less memory** than idiomatic C++.
- **Data density (`strlist`, `words`, `sexp`, `records`, `sum`, `tree`):** Native 1-byte `#[U8]` arrays, exact-size `Array.with_capacity` backing, and flat index arenas keep Squid's geomean peak RSS at **`0.86×` of C++ expert** (#2 overall, ahead of Rust expert), with the #1 lowest peak RSS overall on `strlist`, `words`, and `sexp`.
- **Iteration speed:** Without LLVM in the loop, Squid compiles + AOTs all 16 benchmarks in **~29.9 ms geomean** (**8.5× faster** than `clang++ -O2`).

### Why Squid still trails expert LLVM (`clang -O2` / `rustc -O`) by ~10% on geomean (16% excl. `particles`)

1. **Native codegen vs full LLVM backend (`wtime-aot` vs `clang -O2` / `rustc -O`):** `wtime-aot` compiles Wasm in ~9 ms using an SSA optimizer, helper inlining, widening SIMD reduction vectorization, hardware `mul r64` fusion, and cross-block linear-scan register allocation with multi-instruction scratch spill caching, but still trails LLVM's global register allocation and instruction scheduling on large parser/hash bodies (`sexp`, `calc`, `words`, `lru`, `respond`) and wide-call multi-value traffic (`scene`).
2. **Explicit software bounds checks & sandbox guarantees:** Array loads/stores outside proven induction/masked/affine ranges execute explicit bounds checks (while Wasm linear-memory accesses use 4 GiB hardware `--guard-pages`), and observable floating-point outputs preserve deterministic canonical NaNs.
3. **Wasm32 linear-memory address translation & branch-heavy loops (`lru`, `words`, `respond`):** Even with validated descriptor workers and hoisted owner checks, Wasm32 indexed loads add `base + (idx << shift)` on top of the linear-memory base register, and LLVM's GVN/LICM/switch lowering still yields a ~1.2–1.5× edge on branchy hash-table and streaming loops.

---

## Methodology, Hardware & Reproduction

- **Machine:** AMD Ryzen 7 7800X3D (8C / 16T), Linux `x86_64`.
- **Toolchains:**
  - **Squid:** `squidc-goose` (`abb9acaf`, optimized build) + `wtime-aot 0.1.11` (`--backend x64 --target-cpu native --guard-pages --blot-cdylib`, executed via standalone native [`squid_runner.c`](squid_runner.c) reading ABI 8 `#[U32]` checksum packets).
  - **Goose:** `goose` (`d5ae5bb`, `build-precision`, `-O2 --standalone`) + `clang 23.1.5 -O2`.
  - **C++:** `clang++ 23.1.5 -O2 -std=c++20` (both idiomatic and expert variants from Goose's suite).
  - **Rust:** `rustc 1.96.0-nightly (3645249d7 2026-03-16) -O -C codegen-units=1` (idiomatic and arena/expert variants from Goose's suite).
- **Timing & memory:** Every child execution is spawned via [`measure_proc.c`](measure_proc.c) (`posix_spawnp` + `wait4`), recording best single-process CPU time (`ru_utime + ru_stime`), wall time (`CLOCK_MONOTONIC`), and exact per-child peak RSS (`ru_maxrss`). Each implementation runs 2 discarded warmups followed by 3 timed reps, and its stdout is checked byte-for-byte against all other implementations of the same benchmark.
- **Raw recorded data:** [`results.json`](../evidence/measurements/2026-11-27-goose-suite/results.json) (Nov 26 baseline preserved in [`../evidence/measurements/2026-11-26-goose-suite/`](../evidence/measurements/2026-11-26-goose-suite/results.json)).

### Running locally

```sh
# Run all 16 benchmarks at medium size across Squid, Goose, C++, and Rust:
python3 benchmarks/goose-suite/run_suite.py --sizes medium --reps 3 --warmups 2

# Regenerate all 6 SVG bar charts from results.json:
python3 benchmarks/goose-suite/plot_charts.py
```
