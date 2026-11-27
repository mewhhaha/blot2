# Squid vs Rust & Ink ECS vs Bevy ECS Benchmarks

Reproducible cross-language benchmark suite backing the numbers in the root
[README.md](../../README.md).

## Files

- [squid_kernels.sq](squid_kernels.sq): 6 compute, memory, sorting, and
  `spark` Wasm `v128` SIMD kernels in Squid.
- [rust_kernels.rs](rust_kernels.rs): Matching Rust implementations compiled
  both to `wasm32-unknown-unknown` (`-C opt-level=3 -C target-feature=+simd128
  -C panic=abort`) and natively (`x86_64`, `-O3`, thin LTO).
- [ink_ecs_bench.sq](ink_ecs_bench.sq): Real Ink ECS benchmark using
  `ink/ecs` (`ecs.Entities`, `ecs.Pool`, `ecs.Metadata`) and `ink/ecs/query`
  (`query.prepare`, `query.is_current`) inside ABI 8 persistent `#process`
  guests, plus an idiomatic Squid/Ink SoA + `spark` SIMD process.
- [multicore_aos_bench.sq](multicore_aos_bench.sq): Generalized AoS `#[Vec4]` /
  `#[Vec2]` record auto-SIMD particle Euler integration, stateless 256×256
  Mandelbrot tiles for multi-core isolated-guest scaling, an ABI 8 `#kernel`
  (`mandelbrot_row`) for Deno `KernelPool`, and a persistent `#process`
  (`particle_sim`) for zero-alloc step throughput.
- [bench_multicore_kernel.ts](bench_multicore_kernel.ts): Deno `KernelPool`
  (0, 1, 2, 4, 8 workers) and `Processes` runner for `multicore_aos_bench.sq`
  (default and `--wasm3`).
- [rust_bench_main.rs](rust_bench_main.rs) + [Cargo.toml](Cargo.toml): Unified
  benchmark runner executing Squid Wasm (default and `--wasm3`) and Rust Wasm on
  the same `wtime-aot 0.1.7` (`--backend x64 --target-cpu native --blot-cdylib`,
  `x64-v4` with AVX-512/AVX2/BMI2, zero external deps, explicit software bounds checks),
  native Rust `-O3` kernels, `bevy_ecs 0.20.1` native worlds, AoS `Vec2`/`Vec4`
  record SIMD, 1–8 thread isolated-guest scaling, and persistent `#process`
  throughput with bit-exact checksum verification on every matching workload.
- [plot_benchmarks.py](plot_benchmarks.py): Generates the SVG graphs embedded in
  [README.md](../../README.md) directly from the recorded JSON evidence.

## Running

Prerequisites: built `compiler-goose/build/squidc-goose`, `wtime-aot` (resolved
via `WTIME_AOT_BIN`, sibling `../wtime/tools/wtime-aot/target/release/wtime-aot`,
or `PATH`), sibling `../ink` checkout, and Rust with `wasm32-unknown-unknown`
target installed.

```sh
CARGO_TARGET_DIR=/tmp/squid_bench_target \
  cargo run --release --manifest-path benchmarks/comparison/Cargo.toml

# Deno multi-worker KernelPool & Processes showcase
deno run --allow-read --allow-write --allow-run --allow-env=SQUID_CLIENT_TEST_AMBIENT \
  benchmarks/comparison/bench_multicore_kernel.ts
```

## Recorded Evidence

- [2026-11-26-rust-and-bevy-ecs-wtime-0.1.7.json](../evidence/measurements/2026-11-26-rust-and-bevy-ecs-wtime-0.1.7.json):
  Raw medians (15 timed samples after warmup; 9 samples for compile speed) on
  AMD Ryzen 7 7800X3D with `squidc-goose` (`c79a8354`), `wtime-aot 0.1.7`
  (`--backend x64`, `x64-v4`, `4aee74d`), `rustc 1.96.0-nightly`, and
  `bevy_ecs 0.20.1`.
- [2026-11-26-rust-and-bevy-ecs-wtime-0.1.6.json](../evidence/measurements/2026-11-26-rust-and-bevy-ecs-wtime-0.1.6.json):
  Raw medians (15 timed samples after warmup; 9 samples for compile speed) on
  AMD Ryzen 7 7800X3D with `squidc-goose` (`785e9798`), `wtime-aot 0.1.6`
  (`--backend x64`, `x64-v3`, `ca3c2fc`), `rustc 1.96.0-nightly`, and
  `bevy_ecs 0.20.1`.
- [2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json](../evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json):
  Raw medians (15 timed samples after warmup; 9 samples for compile speed) on
  AMD Ryzen 7 7800X3D with `squidc-goose` (Batch C + Batch C2 FBIP reuse),
  `wtime-aot 0.1.3` (`--backend x64`, `x64-v3`, `1125fd5`, native 256-opcode
  register SIMD + `--wasm3`), `rustc 1.96.0-nightly`, and `bevy_ecs 0.20.1`.
- [2026-11-24-rust-and-bevy-ecs.json](../evidence/measurements/2026-11-24-rust-and-bevy-ecs.json):
  Earlier baseline on `wtime-aot 0.1.2` (`ad175d5`).
