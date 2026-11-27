# 16-Benchmark Cross-Language Suite: Blot vs Goose, Rust & C++

This page reproduces all **16 benchmarks** from Goose's main benchmark suite (`sum`, `push`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`, `blur`) on the same Linux machine, adding **Blot** (`blotc-goose` → WebAssembly ABI 8 → `wtime-aot` x64) alongside **Goose** (`clang -O2`), **C++20** (`clang++ -O2`, idiomatic and expert), and **Rust** (`rustc -O -C codegen-units=1`, idiomatic and arena/expert).

Every implementation across all 16 benchmarks (88 rows total) runs the exact same workload, generates the same inputs from `xorshift64`, and is verified for **100% byte-for-byte identical checksum output**.

---

## Executive Summary

![16-Benchmark Suite Summary: Blot vs Goose, Rust & C++](../evidence/measurements/2026-11-27-goose-suite/summary_overview.svg)

Across all 16 benchmarks at **medium** size on **AMD Ryzen 7 7800X3D (Linux)**:

- **Cold compile time (geomean):** **Blot builds in 28.3 ms** (`18.3 ms` `blotc-goose` + `9.8 ms` `wtime-aot`, `23.4–35.7 ms` range) — **8.4× faster than C++** (`237.0 ms`), **4.6× faster than Goose** (`130.4 ms`), and **3.3× faster than Rust** (`93.5 ms`), producing self-contained **5.7–27.6 KiB** `.wasm` modules.
- **Peak memory (geomean exact per-process RSS vs C++ expert):** **Blot averages 0.86×** (down from `1.03×` on Nov 26) — **#2 lowest peak memory in the suite**, edging out **Rust expert (`0.87×`)**, **C++ expert (`1.00×`)**, **idiomatic Rust (`1.12×`)**, and **idiomatic C++ (`1.32×`)** (with Goose at `0.73×`). Blot uses less memory than idiomatic C++ on **14/16** benchmarks, less than idiomatic Rust on **8/16**, achieves the **lowest peak memory of every language in the suite** on `strlist` (**43.0 MiB**), `words` (**78.8 MiB**), and `sexp` (**109.7 MiB**), and halves `sum` (`129.3 → 64.9 MiB`) and `tree` (`61.1 → 27.9 MiB`) peak RSS via `Array.with_capacity`.
- **Runtime (geomean CPU time vs C++ expert):** Inside a deterministic, bounds-checked Wasm32 sandbox with no LLVM optimizer in the compiler, **Blot averages 1.76× C++ expert** (**`0.91×` of idiomatic C++** at `1.93×`, down from `2.07×` on Nov 26 and `2.90×` earlier; Goose `0.88×`, Rust expert `1.03×`, Rust idiomatic `1.73×`). Blot now **beats idiomatic C++ on geomean runtime** and on **10/16** benchmarks (`strlist` **1.08×**, `records` **1.26×**, `tree` **1.36×**, `graph` **1.63×**, `words` **1.14×**, `particles` **1.16×**, `sexp` **1.97×**, `lru` **2.08×**, `calc` **1.13×**, `bintrees` **1.50×**), beats **idiomatic Rust** on **9/16** (`strlist`, `records`, `interp`, `graph`, `words`, `particles`, `sexp`, `bintrees`, `respond`), beats **C++ expert** on `records` (`131.0 ms` vs `133.9 ms`), and finishes **#1 fastest overall** on `particles` (**186.1 ms** vs C++ expert `186.3 ms`, Rust `187.5 ms`, Goose `192.7 ms`). Biggest per-benchmark wins: `blur` **`119.3 → 32.1 ms` (`3.72×`)** via 16-wide `U8x16`/`I16x8` SIMD, `scene` **`208.9 → 99.9 ms` (`2.09×`)** via boxed-array direct projection & subfield updates, and `words` **`351.2 → 254.3 ms` (`1.38×`)** via bulk `Array.extend_view`.

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

- **Unboxed `v128` SIMD (`particles`, `blur`):** With unboxed `v128` lowering for `F32x4`/`U32x4` and `F64x2`/`U64x2`/`U8x16`/`I16x8`, Blot's SoA `particles` kernel (`186.1 ms`) finishes **#1 fastest of every language in the suite**, and 16-wide `U8x16`/`I16x8` SIMD cut `blur` **3.72×** (`119.3 → 32.1 ms`).
- **Allocator-heavy & graph/tree workloads (`sexp`, `bintrees`, `graph`, `lru`, `records`, `calc`, `words`):** Blot's contiguous owned `#[T]` pools, `Array.with_capacity`/`extend_view` inline fast paths, and explicit handles avoid per-node `malloc`/`free` and pointer chasing. On Goose's flagship `sexp` benchmark, Blot runs **1.97× faster** and uses **5.76× less memory** than idiomatic C++ (`109.7 MiB` vs `632.2 MiB`), while beating even Goose (`127.8 MiB`) on peak memory.
- **Data density (`strlist`, `words`, `sexp`, `records`, `sum`, `tree`):** Native 1-byte `#[U8]` arrays, exact-size `Array.with_capacity` backing, and flat index arenas push Blot's geomean peak RSS to **`0.86×` of C++ expert** (#2 overall, ahead of Rust expert), with the #1 lowest peak RSS overall on `strlist`, `words`, and `sexp`.
- **Iteration speed:** Without LLVM in the loop, Blot compiles + AOTs all 16 benchmarks in **~28 ms geomean** (**8.4× faster** than `clang++ -O2`).

### Why Blot still trails expert LLVM (`clang -O2` / `rustc -O`) on tight scalar loops

1. **Single-pass register allocation & instruction scheduling in `wtime-aot`:** `wtime-aot` compiles Wasm in ~10 ms using a fast single-pass codegen rather than LLVM's multi-pass register allocator and scheduler, leaving a ~1.4–2× gap on tight branchy/indexed loops (`lru`, `calc`, `bintrees`, `scene`).
2. **Explicit software bounds checks & sandbox guarantees:** Array loads/stores outside proven induction/masked/affine ranges execute explicit bounds checks, and `F32`/`F64` operations enforce deterministic canonical NaNs.
3. **Iterative explicit stacks for tree/parser recursion:** Blot's current owned-storage checker strips `own` qualifiers from recursive self-calls, so `tree`, `interp`, `bintrees`, `sexp`, `scene`, and `calc` use explicit fixed-size traversal stacks while preserving exact arenas, node layouts, and traversal semantics.

---

## Methodology, Hardware & Reproduction

- **Machine:** AMD Ryzen 7 7800X3D (8C / 16T), Linux `x86_64`.
- **Toolchains:**
  - **Blot:** `blotc-goose` (optimized build) + `wtime-aot 0.1.7` (`4aee74d`, `--backend x64 --target-cpu native --blot-cdylib`, executed via standalone native [`blot_runner.c`](blot_runner.c) reading ABI 8 `#[U32]` checksum packets).
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
