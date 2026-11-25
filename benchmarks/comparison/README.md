# Blot vs Rust & Ink ECS vs Bevy ECS Benchmarks

Reproducible cross-language benchmark suite backing the numbers in the root
[README.md](../../README.md).

## Files

- [blot_kernels.blot](blot_kernels.blot): 6 compute, memory, sorting, and
  `spark` Wasm `v128` SIMD kernels in Blot.
- [rust_kernels.rs](rust_kernels.rs): Matching Rust implementations compiled
  both to `wasm32-unknown-unknown` (`-C opt-level=3 -C target-feature=+simd128
  -C panic=abort`) and natively (`x86_64`, `-O3`, thin LTO).
- [ink_ecs_bench.blot](ink_ecs_bench.blot): Real Ink ECS benchmark using
  `ink/ecs` (`ecs.Entities`, `ecs.Pool`, `ecs.Metadata`) and `ink/ecs/query`
  (`query.prepare`, `query.is_current`) inside ABI 8 persistent `entry process`
  guests, plus an idiomatic Blot/Ink SoA + `spark` SIMD process.
- [rust_bench_main.rs](rust_bench_main.rs) + [Cargo.toml](Cargo.toml): Unified
  benchmark runner executing Blot Wasm and Rust Wasm on the same
  `wtime-aot 0.1.1` (`--backend x64 --target-cpu native --blot-cdylib`,
  `x64-v3` with AVX2/BMI2, zero external deps, explicit software bounds checks),
  native Rust `-O3` kernels, and `bevy_ecs 0.20.1` native worlds with bit-exact
  checksum verification on every matching workload.
- [plot_benchmarks.py](plot_benchmarks.py): Generates the SVG graphs embedded in
  [README.md](../../README.md) directly from the recorded JSON evidence.

## Running

Prerequisites: built `compiler-goose/build/blotc-goose`, `wtime-aot` (resolved
via `WTIME_AOT_BIN`, sibling `../wtime/tools/wtime-aot/target/release/wtime-aot`,
or `PATH`), sibling `../ink` checkout, and Rust with `wasm32-unknown-unknown`
target installed.

```sh
CARGO_TARGET_DIR=/tmp/blot_bench_target \
  cargo run --release --manifest-path benchmarks/comparison/Cargo.toml
```

## Recorded Evidence

- [2026-11-24-rust-and-bevy-ecs.json](../evidence/measurements/2026-11-24-rust-and-bevy-ecs.json):
  Raw medians (15 timed samples after warmup; 9 samples for compile speed) on
  AMD Ryzen 7 7800X3D with `blotc-goose` (Tier 7 `7A–7E`), `wtime-aot 0.1.1`
  (`--backend x64`, `x64-v3`, `ad175d5`), `rustc 1.96.0-nightly`, and
  `bevy_ecs 0.20.1`.
