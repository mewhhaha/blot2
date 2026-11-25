# Blot

**Blot is a pure-ownership, zero-GC functional language that compiles directly to fast, deterministic WebAssembly in milliseconds.**

Blot is designed for real-time games, deterministic simulations, rollback netcode, and sandboxed host-embedded logic — anywhere garbage-collection pauses hurt frame pacing, Rust lifetimes and LLVM build times slow iteration, and deterministic replay matters.

[Why Blot](#why-use-blot) · [Unique Features](#unique-features) · [Benchmarks vs Rust](#benchmarks-blot-vs-rust) · [Ink ECS vs Bevy ECS](#ink-ecs-vs-bevy-ecs) · [Getting Started](#getting-started) · [Documentation](#documentation)

---

## Why Use Blot?

Most languages force an uncomfortable trade-off for interactive and simulation software:

- **Garbage-collected languages** (TypeScript, C#, Go, Lua) iterate quickly, but introduce GC pauses, implicit shared aliasing, and non-deterministic ambient I/O.
- **Systems languages** (Rust, C++) deliver peak native throughput, but slow iteration with LLVM build times and demand explicit lifetime management or manual memory safety.

Blot occupies the space in between:

1. **Zero-GC memory safety without lifetime annotations.** Values are immutable by default, dynamic arrays (`#[T]`) mutate in place when uniquely owned, and the compiler infers local borrows (`&T`, `&[T]`) and ownership transfers (`own`) statically — no garbage collector and no `'a` lifetime parameters.
2. **Subsecond iteration and tiny Wasm binaries.** Blot's native compiler (`blotc-goose`) emits WebAssembly directly without LLVM. A 6-kernel module compiles cold in **11.7 ms** (**10.9 KiB** Wasm, plus **3.8 ms** AOT to native x86-64 via `wtime-aot`); a 9-module ECS app builds in **21.9 ms** (**60.4 KiB**); a **307-module / 3.09 MB** 3D game builds cold in **0.55–0.70 s** (`pen check` in **0.42 s**).
3. **Determinism and sandboxing by construction.** Functions are pure by default, I/O and state are tracked as explicit algebraic effects, floating-point operations normalize to canonical IEEE 754 quiet NaN (`0x7fc00000`) across scalar, SIMD, and compile-time `#run`, and guests execute inside a memory-safe WebAssembly ABI 8 sandbox.
4. **Built-in data-oriented parallelism.** Write array kernels with `spark #[...]` for automatic 4-wide Wasm `v128` SIMD, fan out across host worker pools with `entry kernel`, and isolate long-lived state machines in persistent `entry process` actors.

---

## Unique Features

### 1. In-Place Ownership Without Lifetimes

Blot has one unified dynamic array type (`#[T]` / `Array T`) and fixed-length arrays (`#[N; T]`). When you uniquely own a binding, `:=` and `@storage.push` mutate it in place with zero copies. Pass `own` to transfer ownership across functions, `freeze` (`*T`) to share read-only in O(1), or `copy` for an explicit snapshot:

```blot
func append_scaled (items: own #[F32]) -> (factor: F32): #[F32] =>
  for i in 0 .. items.length:
    items[i] := self * factor
  @storage.push items factor
  return items

entry func main (): F32 =>
  let base = #[1.0, 2.0, 3.0]
  let snapshot = base.copy           // explicit deep snapshot
  let updated = append_scaled base 2.0
  return snapshot[0] + updated[3]    // 1.0 + 2.0 = 3.0
```

Module `const` pools are statically guaranteed deeply immutable — no separate `const` vs mutable array type split is required.

### 2. Auto-Vectorized `spark` SIMD & Structured Concurrency

Pure array comprehensions marked with `spark` are statically checked for independence and lowered directly to 4-wide WebAssembly `v128` SIMD instructions:

```blot
func integrate (px: #[F32]) -> (vx: #[F32]) -> (ax: #[F32]) -> (dt: F32): #[F32] =>
  let half_dt2 = 0.5 * dt * dt
  return spark #[px[i] + vx[i] * dt + ax[i] * half_dt2 | i <- 0 .. px.length]
```

For multi-core host execution, Blot provides two first-class Wasm ABI 8 entry points:
- **`entry kernel`** — pure, deterministic data-parallel kernels dispatched across host worker threads on copied packets.
- **`entry process`** — isolated persistent state machines (`{ init, step }`) whose owned state survives across host turns with zero-drift staging and automatic rollback on trap.

### 3. Pure-by-Default Algebraic Effects

Blot has no ambient globals, filesystem, clock, or RNG. Capabilities are declared as typed effects and bound lexically with providers or request loops, making deterministic simulation, mocking, and replay trivial:

```blot
type Clock is effect = { delta: Unit -> F32 }

func advance (pos: F32) -> (vel: F32): F32 =>
  use dt <- Clock.delta ()
  return pos + vel * dt

const fixed_60hz = @effect.provider Clock.delta (func () => return 0.01666667)

entry func step_frame (): F32 => do fixed_60hz:
  use next <- advance 10.0 6.0
  break next
```

### 4. Speculative Rollback (`fork`) & Compile-Time Execution (`#run`)

- **`fork` scopes** let code mutate owned arrays speculatively in place while journaling touched bytes; aborting or trapping rolls memory back cleanly without allocating full copies upfront.
- **Compile-time evaluation & reflection** (`#run`, `#fields`, `#variants`, `#if`) run real type-checked Blot code at compile time with the exact same canonical float semantics as runtime — no untyped preprocessor macros.

### 5. Clean Functional-Imperative Ergonomics

Curried functions (`->`), exhaustive algebraic data types (`$Some`, `$Nothing`), `let ... else:` early exits, `self` update shorthand (`sum := self + x`), and explicit `return` keep control flow readable without hidden exceptions or null pointers.

---

## Benchmarks: Blot vs Rust

All benchmarks below were measured on an **AMD Ryzen 7 7800X3D (8C / 16T)** running Linux, comparing:

- **Blot (`blotc-goose`)** AOT-compiled and executed via **`wtime-aot 0.1.1`** (`--backend x64 --target-cpu native --blot-cdylib`, `x64-v3`, explicit software bounds checks, zero signal handlers).
- **Rust (`rustc 1.96.0-nightly`, `-C opt-level=3`)** compiled both to **`wasm32-unknown-unknown +simd128` (`panic=abort`)** on the exact same `wtime-aot 0.1.1` (`--backend x64`) runtime and to **native `x86_64`** (`-O3`, thin LTO, `codegen-units = 1`).

Every kernel reports the median of 15 timed runs after warmup and verified **bit-exact checksum parity** across all three targets. Source and runner live in [benchmarks/comparison/](benchmarks/comparison/README.md); raw JSON measurements are recorded in [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json).

### Compile Time & Output Size

![Compile speed and WebAssembly output size: Blot vs Rust](benchmarks/evidence/measurements/2026-11-24-compile-and-size.svg)

### Runtime: Compute, Memory & Auto-SIMD

![Blot vs Rust -O3 compute, memory, and auto-SIMD benchmarks](benchmarks/evidence/measurements/2026-11-24-blot-vs-rust-kernels.svg)

**Reading these numbers honestly:**
- **Five of the six kernels sit at `0.91×–1.14×` of LLVM `-O3` Wasm on the exact same `wtime-aot x64` engine:** Blot beats LLVM `-O3` Wasm on `particle_spark_simd` (`0.72 ms vs 0.79 ms`, `0.91×`), matches it on `lcg_recurrence` (`0.375 ms vs 0.372 ms`, `1.01×`, via 4× parallel-power affine unrolling), and stays within 8–14% on `merge_sort` (`1.08×`), `prime_sieve` (`1.12×`, byte-packed `#[Bool]` + branchless `select`), and `mandelbrot_f32` (`1.14×` Wasm, `0.90×` vs native `3.90 ms`) — while preserving canonical `0x7fc00000` quiet NaN determinism at every observable boundary and full bounds safety.
- **`matmul_64` (`0.067 ms`, `2.25×` Rust Wasm, `3.38×` native)** auto-vectorizes its inner loop into 4× unrolled 16-element `v128` SIMD, where LLVM's unrolled scalar/SIMD register tiling and hoist passes retain a lead on tiny 64×64 matrices under `--blot-cdylib`'s explicit per-load software bounds checks.
- Meanwhile, Blot compiles **7.3× faster** than `rustc -O3 wasm32` (**11.7 ms** vs **85.6 ms**; even combined with `wtime-aot x64`'s **3.8 ms** AOT step it is **5.5× faster**) to **134× smaller** `.wasm` binaries (**10.9 KiB** vs **1,468 KiB**).

---

## Ink ECS vs Bevy ECS

We benchmarked **Ink ECS** (`ink/ecs` + `ink/ecs/query`, written in pure Blot and compiled to a **60.4 KiB** Wasm module executed on `wtime-aot 0.1.1 --backend x64`) against **Bevy ECS `0.20.1`** (native x86_64 Rust `-O3` + thin LTO) on identical 10,000-entity worlds (`Pos { x, y, z }`, `Vel { vx, vy, vz }`, 10% `Active`, 5% `Frozen`) with **bit-exact checksum parity** on all matching workloads ([ink_ecs_bench.blot](benchmarks/comparison/ink_ecs_bench.blot), [rust_bench_main.rs](benchmarks/comparison/rust_bench_main.rs)):

![Ink ECS vs Bevy ECS 0.20.1 performance comparison](benchmarks/evidence/measurements/2026-11-24-ink-vs-bevy-ecs.svg)

**Why the two architectures trade wins:**
- **Bevy ECS leads on AoS archetype-table queries:** Grouping matching component bundles into dense untagged native Rust slices avoids `Maybe` tag checks and Wasm bounds checks — giving native Bevy a **1.8×–2.2×** lead over Ink's pure-Wasm `Pool`/cached queries (**1.25 ms vs 2.22–2.47 ms** dense; **0.068 ms vs 0.151 ms** sparse), while batch spawn is now nearly neck-and-neck (**0.319 ms vs 0.363 ms**, **1.14×**) after Blot's Tier 3 inlining, selective invalidation, and bounded-finite `F32` optimization.
- **Ink ECS leads on structural edits, snapshots, and flat SIMD columns:** Ink stores each component in an entity-indexed owned column (`ecs.Pool T`) with zero compiler ECS magic and commits unchanged persistent process handles in zero allocations. Adding or removing a tag (`Active`) flips one slot without migrating `Pos`/`Vel` across archetypes (**18.9 µs**, **4.5× faster** than native Bevy), snapshotting the entire 10k-entity world for rollback netcode or rewind is five contiguous `@storage.copy` memcpys (**16.7 µs**, **24.2× faster** than rebuilding a `bevy_ecs::World`), and splitting hot physics columns into flat SoA + in-place `spark` SIMD hits **0.66 ms** from inside a Wasm sandbox (**1.9× faster** than native Bevy AoS — though native Rust/Bevy could likewise adopt SoA columns or multi-threaded queries).

Additional compiler, incremental-edit, multi-worker kernel, and Goose comparisons live under [benchmarks/](benchmarks/comparison/README.md) (including [multi-worker Gdev route batches](benchmarks/evidence/measurements/2026-11-19-spark-spawn.json) and [incremental capacity edits at 35.0 ms](benchmarks/evidence/measurements/2026-11-19-gdev-call-literals.json)).

---

## Getting Started

### Prerequisites

- **Deno 2** (CLI, formatter, package manager, and Wasm guest host)
- **clang, cmake, ninja, and Python 3** (to build `blotc-goose` from source)

### Build the Compiler

```sh
# Fast debug build (~90s; first run also builds the patched Goose compiler)
deno task build:compiler:dev

# Optimized release build (used by tests, Pen, Ink, and Gdev)
deno task build:compiler
```

### Check, Build, and Format Blot Code

```sh
# Type-check a Blot entry file
deno task blot check examples/syntax.blot

# Compile to WebAssembly (ABI 8)
deno task blot build examples/syntax.blot --out build/syntax.wasm

# Format Blot source files
deno task blot fmt examples/syntax.blot
```

### Run the Test Suite

```sh
# Run all guest & host tests against the built compiler
deno task test:guest

# Full compiler qualification gate (tooling, release build, reference laws, 1,100+ guest/host tests)
deno task test:compiler
```

---

## Current Status

Blot is in active development and already powers **Ink** (an engine/ECS library in pure Blot, 425 passing tests) and **Gdev** (a 307-module 3D game running on the Rust/Vulkan **Pen** host with verified hardware-rendered frames). Unified dynamic arrays (`#[T]`), compile-time uniqueness enforcement, ABI 8 kernels/processes, and Wasm `v128` `spark` SIMD are live; see [CONTINUE.md](CONTINUE.md) for current release identities and active engineering milestones.

---

## Documentation

- **Language & Examples:** [Language guide](docs/language/guide.md) · [Effects and controlled I/O](docs/language/effects-and-io.md) · [Standard library](std/README.md) · [Syntax showcase](examples/syntax.blot) · [Pure Blot ECS example](examples/ecs.blot)
- **Compiler & Host:** [Goose compiler](compiler-goose/README.md) · [Deno host & CLI](host/README.md) · [Guest ABI](docs/host/guest-abi.md) · [Packages](docs/host/packages.md)
- **Benchmarks & Project State:** [Comparison benchmark suite](benchmarks/comparison/README.md) · [Repository map](docs/README.md) · [Current frontier](CONTINUE.md) · [Contributor rules](AGENTS.md)
