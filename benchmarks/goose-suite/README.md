# 16-Benchmark Cross-Language Suite: Blot vs Goose, Rust & C++

This page reproduces all **16 benchmarks** from Goose's main benchmark suite (`sum`, `push`, `strlist`, `records`, `tree`, `interp`, `graph`, `words`, `particles`, `sexp`, `lru`, `scene`, `calc`, `bintrees`, `respond`, `blur`) on the same Linux machine, adding **Blot** (`blotc-goose` → WebAssembly ABI 8 → `wtime-aot` x64) alongside **Goose** (`clang -O2`), **C++20** (`clang++ -O2`, idiomatic and expert), and **Rust** (`rustc -O -C codegen-units=1`, idiomatic and arena/expert).

Every implementation across all 16 benchmarks (88 rows total) runs the exact same workload, generates the same inputs from `xorshift64`, and is verified for **100% byte-for-byte identical checksum output**.

---

## Executive Summary

![16-Benchmark Suite Summary: Blot vs Goose, Rust & C++](../evidence/measurements/2026-11-26-goose-suite/summary_overview.svg)

Across all 16 benchmarks at **medium** size on **AMD Ryzen 7 7800X3D (Linux)** (`blotc-goose` `bac9eb2e`):

- **Cold compile time (geomean):** **Blot builds in 24.0 ms** (`14.7 ms` `blotc-goose` + `9.2 ms` `wtime-aot`, `20.7–32.2 ms` range) — **9.3× faster than C++** (`222.1 ms`), **5.1× faster than Goose** (`121.2 ms`), and **3.6× faster than Rust** (`85.3 ms`), producing self-contained **5.3–26.8 KiB** `.wasm` modules.
- **Peak memory (geomean exact per-process RSS vs C++ expert):** **Blot averages 1.03×** (down from `1.10×`), edging out **idiomatic Rust (1.12×)** and **idiomatic C++ (1.31×)** (with Goose at `0.73×`, Rust expert `0.87×`, C++ expert `1.00×`). Blot uses less memory than idiomatic C++ on **13/16** benchmarks, less than idiomatic Rust on **8/16**, achieves the **lowest peak memory of every language in the suite** on `words` (**91.2 MiB** vs Goose `138.1`, Rust `142.4`, C++ `150.3`) and `sexp` (**110.8 MiB** vs Goose `128.0`, Rust `225.9–481.7`, C++ `290.1–631.0`), and matches C++ on `blur` (**11.9 MiB** via 1-byte `#[U8]` buffers).
- **Runtime (geomean CPU time vs C++ expert):** Inside a deterministic, bounds-checked Wasm32 sandbox with no LLVM optimizer in the compiler, **Blot averages 2.07× C++ expert** (`1.08×` idiomatic C++ at `1.92×`, down from `2.90×`; Goose `0.90×`, Rust expert `1.03×`, Rust idiomatic `1.72×`). Blot beats **idiomatic C++** on **9/16** benchmarks (`strlist` **1.14×**, `records` **1.23×**, `tree` **1.11×**, `graph` **1.75×**, `particles` **1.20×**, `sexp` **1.89×**, `lru` **1.80×**, `calc` **1.09×**, `bintrees` **1.59×**), beats **idiomatic Rust** on **7/16** (`strlist`, `records`, `graph`, `particles`, `sexp`, `bintrees`, `respond`), and finishes **#1 fastest overall** on `particles` (**179.8 ms** with unboxed 4-wide `v128` SIMD vs C++ expert `185.4 ms`, Rust `186.8 ms`, Goose `190.5 ms`).

---

## Runtime Comparison (All 16 Benchmarks)

Lower is better. Bars are sorted fastest → slowest per benchmark and report best single-process CPU time (`ru_utime + ru_stime`, ms) across 3 timed runs after 2 warmups.

### Benchmarks 1–8: Arrays, Strings, Records, Trees, Dispatch, Graph & Words

![Runtime: Benchmarks 1–8](../evidence/measurements/2026-11-26-goose-suite/runtime_part1.svg)

### Benchmarks 9–16: Particles, S-Expressions, LRU, Scene Graph, Parser, Binary Trees, JSON & Blur

![Runtime: Benchmarks 9–16](../evidence/measurements/2026-11-26-goose-suite/runtime_part2.svg)

---

## Peak Memory Comparison (All 16 Benchmarks)

Lower is better. Measured with a minimal native `posix_spawnp` + `wait4` harness (`ru_maxrss`) so parent-process memory never leaks into child RSS measurements.

### Benchmarks 1–8

![Peak Process Memory: Benchmarks 1–8](../evidence/measurements/2026-11-26-goose-suite/memory_part1.svg)

### Benchmarks 9–16

![Peak Process Memory: Benchmarks 9–16](../evidence/measurements/2026-11-26-goose-suite/memory_part2.svg)

---

## Cold Compile Speed & Blot `.wasm` Output Size

Blot's stacked bars show both `blotc-goose` compilation (dark teal) and `wtime-aot` native x64 compilation (light teal) against full cold builds of `rustc -O`, `goose + clang -O2`, and `clang++ -O2`.

![Cold Compile Time & Blot Wasm Binary Size](../evidence/measurements/2026-11-26-goose-suite/compile_and_size.svg)

---

## Honest Diagnosis: Where Blot Wins and Where the Remaining Gap Comes From

### Where Blot shines

- **Unboxed `v128` SIMD (`particles`):** With Wave 2's tagged-word unboxed `v128` lowering for `std/simd`, Blot's SoA `particles` kernel (`179.8 ms`, bit-exact IEEE-754 binary32) finishes **#1 fastest of every language in the suite**, edging out C++ expert (`185.4 ms`), Rust (`186.8 ms`), and Goose (`190.5 ms`).
- **Allocator-heavy & graph/tree workloads (`sexp`, `bintrees`, `graph`, `lru`, `records`, `calc`):** Blot's contiguous owned `#[T]` pools and explicit handles avoid per-node `malloc`/`free`, pointer chasing, and recursive destructor cascades. On Goose's flagship `sexp` benchmark, Blot runs **1.89× faster** and uses **5.69× less memory** than idiomatic C++ (`110.8 MiB` vs `631.0 MiB`), while beating even Goose (`128.0 MiB`) on peak memory.
- **Data density (`words`, `sexp`, `records`, `strlist`, `blur`):** Native 1-byte `#[U8]` arrays and flat index arenas let Blot beat idiomatic C++ memory on **13/16** benchmarks, match C++ on `blur` (`11.9 MiB`), and post the #1 lowest peak RSS overall on `words` and `sexp`.
- **Iteration speed:** Without LLVM in the loop, Blot compiles + AOTs all 16 benchmarks in **~24 ms geomean** (**9.3× faster** than `clang++ -O2`).

### Why Blot still trails expert LLVM (`clang -O2` / `rustc -O`) on tight scalar loops

1. **No scalar loop auto-vectorizer in `wtime-aot`:** On `blur` (`119.3 ms` vs `18.3–23.1 ms`), `clang -O2` and `rustc -O` auto-vectorize scalar byte stencils into 128/256-bit SSE/AVX2 instructions, whereas `wtime-aot` lowers scalar Wasm loops directly to scalar x64 instructions.
2. **Explicit software bounds checks & sandbox guarantees:** Every array load/store in `wtime-aot` executes an explicit bounds check unless proven invariant/in-bounds by `blotc-goose`, and every `F32`/`F64` op enforces canonical quiet NaN (`0x7fc00000` / `0x7ff8000000000000`). Native C++, Rust (after LLVM range-check elimination), and Goose (`checkfree`) elide most inner-loop checks.
3. **64-bit constant-divisor strength reduction & register allocation:** `blotc-goose` lowers `U32` constant divisions/remainders via 64-bit Granlund-Montgomery reciprocals and `U64` powers of two via shifts/masks, while general `U64` non-power-of-two remainders still execute hardware `i64.rem_u` and `wtime-aot` uses a fast single-pass register allocator rather than LLVM's multi-pass scheduler.
4. **Iterative explicit stacks for tree/parser recursion:** Blot's current owned-storage backend restricts general recursion over dynamically resized owned arrays, so `tree`, `interp`, `bintrees`, `sexp`, `scene`, and `calc` use explicit fixed-size traversal stacks while keeping the exact same arenas, node layouts, per-tree/per-input allocations, and traversal semantics.

---

## Methodology, Hardware & Reproduction

- **Machine:** AMD Ryzen 7 7800X3D (8C / 16T), Linux `x86_64`.
- **Toolchains:**
  - **Blot:** `blotc-goose` (`bac9eb2e`, optimized build) + `wtime-aot 0.1.7` (`4aee74d`, `--backend x64 --target-cpu native --blot-cdylib`, executed via standalone native [`blot_runner.c`](blot_runner.c) reading ABI 8 `#[U32]` checksum packets).
  - **Goose:** `goose` (`d5ae5bb`, `build-precision`, `-O2 --standalone`) + `clang 23.1.5 -O2`.
  - **C++:** `clang++ 23.1.5 -O2 -std=c++20` (both idiomatic and expert variants from Goose's suite).
  - **Rust:** `rustc 1.96.0-nightly (1d419d203 2026-04-06) -O -C codegen-units=1` (idiomatic and arena/expert variants from Goose's suite).
- **Timing & memory:** Every child execution is spawned via [`measure_proc.c`](measure_proc.c) (`posix_spawnp` + `wait4`), recording best single-process CPU time (`ru_utime + ru_stime`, immune to background host scheduling load), wall time (`CLOCK_MONOTONIC`), and exact per-child peak RSS (`ru_maxrss`). Each implementation runs 2 discarded warmups followed by 3 timed reps, and its stdout is checked byte-for-byte against all other implementations of the same benchmark.
- **Raw recorded data:** [`results.json`](../evidence/measurements/2026-11-26-goose-suite/results.json).

### Running locally

```sh
# Run all 16 benchmarks at medium size across Blot, Goose, C++, and Rust:
python3 benchmarks/goose-suite/run_suite.py --sizes medium --reps 3 --warmups 2

# Regenerate all 6 SVG bar charts from results.json:
python3 benchmarks/goose-suite/plot_charts.py
```
