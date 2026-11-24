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
2. **Subsecond iteration and tiny Wasm binaries.** Blot's native compiler (`blotc-goose`) emits WebAssembly directly without LLVM. A 6-kernel module compiles cold in **14 ms** (**11.5 KiB** Wasm); a 9-module ECS app builds in **24 ms** (**53.4 KiB**); a **307-module / 3.09 MB** 3D game builds cold in **0.55 s** (`pen check` in **0.42 s**).
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

- **Blot (`blotc-goose` `30899f4b`)** running on **Wasmtime `49.0.7`** (`OptLevel::Speed`, `wasm_simd(true)`).
- **Rust (`rustc 1.96.0-nightly`, `-C opt-level=3`)** compiled both to **`wasm32-unknown-unknown +simd128` (`panic=abort`)** on the exact same Wasmtime `49.0.7` engine and to **native `x86_64`** (`-O3`, thin LTO, `codegen-units = 1`).

Every kernel reports the median of 15 timed runs after warmup and verified **bit-exact checksum parity** across all three targets. Source and runner live in [benchmarks/comparison/](benchmarks/comparison/README.md); raw JSON measurements are recorded in [2026-11-24-rust-and-bevy-ecs.json](benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json).

### Compile Time & Output Size

| Project | Blot (`blotc-goose`) | Rust `-O3` (`wasm32`) | Rust `-O3` (native `rlib`) |
| --- | ---: | ---: | ---: |
| **6-kernel benchmark suite** (cold build) | **14.0 ms** | 98.6 ms *(7.0× slower)* | 85.1 ms *(6.1× slower)* |
| **6-kernel `.wasm` binary size** | **11.5 KiB** | 1,468 KiB *(128× larger)* | — |
| **9-module Ink ECS app** (`ink/ecs` + `query`, cold) | **23.9 ms** (**53.4 KiB**) | — | — |
| **307-module 3D game (`gdev`, 3.09 MB source, 5,029 fns)** | **549.4 ms** (**4.08 MB** Wasm) | — | — |

### Runtime: Compute, Memory & Auto-SIMD

| Benchmark | Blot (Wasmtime) | Rust `-O3` (Wasmtime) | Rust `-O3` (Native x86_64) | Blot vs Rust Wasm | Blot vs Rust Native |
| --- | ---: | ---: | ---: | ---: | ---: |
| **`particle_spark_simd`** *(65k particles × 32, `spark` `v128`)* | **0.84 ms** | 0.69 ms | 0.43 ms | **1.21×** | **1.95×** |
| **`mandelbrot_f32`** *(256×256 scalar FP, 100 max iter)* | **4.95 ms** | 3.44 ms | 3.94 ms | **1.44×** | **1.26×** |
| **`merge_sort`** *(100k `U32`, owned ping-pong buffers)* | **14.56 ms** | 6.70 ms | 4.87 ms | **2.17×** | **2.99×** |
| **`lcg_recurrence`** *(1,000,000 tight integer steps)* | **0.94 ms** | 0.29 ms | 0.35 ms | **3.22×** | **2.67×** |
| **`prime_sieve`** *(100k flags, bounds-checked writes)* | **0.43 ms** | 0.11 ms | 0.09 ms | **4.02×** | **4.99×** |
| **`matmul_64`** *(64×64 `F32` scalar triple loop)* | **1.15 ms** | 0.029 ms | 0.020 ms | **39.4×** | **58.4×** |

**Reading these numbers honestly:**
- Where Blot uses **`spark` SIMD** (`particle_spark_simd`) or scalar FP compute (`mandelbrot_f32`), it runs within **1.21×–1.44×** of LLVM `-O3` Wasm and **1.26×–1.95×** of native x86_64 Rust — even while enforcing canonical quiet NaN determinism and full array bounds checks.
- On tight scalar loops (`lcg_recurrence`, `prime_sieve`, `matmul_64`), LLVM's optimizer unrolls loops, hoists bounds checks, and auto-vectorizes ordinary `for` loops into AVX2/SIMD FMA. Blot's direct Wasm emitter prioritizes **14 ms** compiles over LLVM-grade scalar loop optimization; hot numerical passes should use `spark` comprehensions or SoA layouts.

---

## Ink ECS vs Bevy ECS

We benchmarked **Ink ECS** (`ink/ecs` + `ink/ecs/query`, written in pure Blot and compiled to a **53.4 KiB** Wasm module running on Wasmtime `49.0.7`) against **Bevy ECS `0.20.1`** (native x86_64 Rust `-O3` + thin LTO) on identical 10,000-entity worlds (`Pos { x, y, z }`, `Vel { vx, vy, vz }`, 10% `Active`, 5% `Frozen`) with **bit-exact checksum parity** on all matching workloads ([ink_ecs_bench.blot](benchmarks/comparison/ink_ecs_bench.blot), [rust_bench_main.rs](benchmarks/comparison/rust_bench_main.rs)):

| Workload (10,000 entities) | Ink ECS (Blot → Wasmtime) | Bevy ECS `0.20.1` (Native Rust `-O3`) | Winner / Note |
| --- | ---: | ---: | --- |
| **Dense iteration** (`Pos += Vel`, 10k × 100 ticks) — `ink/ecs` `Pool` scan | 6.39 ms | **1.28 ms** | Bevy **5.0×** faster |
| **Dense iteration** (`Pos += Vel`, 10k × 100 ticks) — `ink/ecs/query` cached | 9.30 ms | **1.28 ms** | Bevy **7.2×** faster |
| **Dense iteration** (`Pos += Vel`, 10k × 100 ticks) — **Blot SoA + `spark` SIMD** | **0.65 ms** | 1.28 ms *(AoS `Pos`/`Vel`)* | **Blot `spark` 2.0× faster** |
| **Sparse filtered iteration** (`With Active, Without Frozen`, 500/10k × 100) | 0.42 ms | **0.069 ms** | Bevy **6.1×** faster |
| **Batch spawn** (10,000 entities: `Pos` + `Vel` + 10% `Active`) | 0.72 ms | **0.19 ms** | Bevy **3.8×** faster |
| **Structural tag churn** (2,000 `Active` insert/remove ops on 10k world) | **0.035 ms** *(35 µs)* | 0.084 ms *(84 µs)* | **Ink 2.4× faster** |
| **Full-world snapshot copy** (all 10,000 entities & 5 pools/components) | **0.010 ms** *(10 µs)* | 0.237 ms *(237 µs)* | **Ink 23.6× faster** |

**Why the two architectures trade wins:**
- **Bevy ECS excels at archetype-table queries:** Grouping matching component bundles into dense untagged native Rust slices avoids `Maybe` tag checks, ID indirection, and Wasm bounds checks — giving Bevy a clear **3.8×–7.2×** edge on AoS component iteration and batch spawns.
- **Ink ECS excels at structural edits, snapshots, and flat SIMD columns:** Ink stores each component in an entity-indexed owned column (`ecs.Pool T`) with zero compiler ECS magic. Adding or removing a tag (`Active`) flips one slot without copying `Pos`/`Vel` between archetypes (**2.4× faster**), snapshotting the entire 10k-entity world for rollback netcode or rewind is five contiguous `@storage.copy` memcpys (**10 µs**, **23.6× faster** than rebuilding a `bevy_ecs::World`), and splitting hot physics columns into flat SoA + `spark` SIMD hits **0.65 ms** from inside a Wasm sandbox (**2.0× faster** than native Bevy AoS — though native Rust/Bevy could likewise adopt SoA columns or multi-threaded queries).

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
