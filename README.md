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
2. **Subsecond iteration and tiny Wasm binaries.** Blot's native compiler (`blotc-goose`) emits WebAssembly directly without LLVM. A 6-kernel module compiles cold in **12.9 ms** (**13.6 KiB** Wasm, plus **3.5 ms** AOT to native x86-64 via `wtime-aot`); a 9-module ECS app builds in **24.2 ms** (**68.1 KiB**); a **307-module / 3.09 MB** 3D game builds cold in **0.55–0.70 s** (`pen check` in **0.42 s**).
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
- **Blot matches or beats LLVM `-O3` Wasm on the exact same `wtime-aot x64` engine across all six kernels (`0.52×–1.16×`, `0.90×` geomean):** Blot beats LLVM `-O3` Wasm on `particle_spark_simd` (**0.39 ms vs 0.75 ms**, **1.92× faster** — and **1.69× faster than native Rust `-O3`** `0.66 ms` — via inlined in-place `spark` reuse, deferred NaN canonicalization, and descending `48,32,16,0` BCE-coalesced `v128` SIMD), `matmul_64` (**0.025 ms vs 0.030 ms**, **1.17× faster**, `1.29×` native, via 4×`v128` register-blocked `k`-loop tiling), and `prime_sieve` (**0.112 ms vs 0.130 ms**, **1.16× faster**, via byte-packed `#[Bool]` + 4× unrolled strided fill + branchless `select`), beats native Rust `-O3` on `mandelbrot_f32` (**3.34 ms vs 3.45 ms**, `1.09×` Wasm, via 2× scalar loop unrolling and exact `2.0*x → x+x`), and stays within 5–16% on `lcg_recurrence` (`1.05×` Wasm, `1.10×` native) and `merge_sort` (`1.16×` Wasm, `1.33×` native) — all while preserving canonical `0x7fc00000` quiet NaN determinism at every observable boundary and full bounds safety.
- Meanwhile, Blot compiles **6.8× faster** than `rustc -O3 wasm32` (**12.9 ms** vs **87.3 ms**; even combined with `wtime-aot x64`'s **3.5 ms** AOT step it is **5.3× faster**) to **108× smaller** `.wasm` binaries (**13.6 KiB** vs **1,468 KiB**).

---

## Ink ECS vs Bevy ECS

We benchmarked **Ink ECS** (`ink/ecs` + `ink/ecs/query`, written in pure Blot and compiled to a **68.1 KiB** Wasm module executed on `wtime-aot 0.1.1 --backend x64`) against **Bevy ECS `0.20.1`** (native x86_64 Rust `-O3` + thin LTO) on identical 10,000-entity worlds (`Pos { x, y, z }`, `Vel { vx, vy, vz }`, 10% `Active`, 5% `Frozen`) with **bit-exact checksum parity** on all matching workloads ([ink_ecs_bench.blot](benchmarks/comparison/ink_ecs_bench.blot), [rust_bench_main.rs](benchmarks/comparison/rust_bench_main.rs)):

![Ink ECS vs Bevy ECS 0.20.1 performance comparison](benchmarks/evidence/measurements/2026-11-24-ink-vs-bevy-ecs.svg)

**Why the two architectures trade wins:**
- **Ink ECS leads on 4 of 5 headline categories from inside a Wasm sandbox:** Storing each component in an entity-indexed owned column (`ecs.Pool T`) with zero compiler ECS magic, zero-allocation persistent process commits, and `CheckedGrow` reuse makes batch-spawning 10,000 entities **1.10× faster** than native Bevy (**0.290 ms vs 0.319 ms**), adding/removing `Active` tags **5.4× faster** (**15.6 µs vs 83.9 µs**, flipping one slot without archetype migration), snapshotting the entire 10k-entity world **23.2× faster** (**17.1 µs vs 395.9 µs** via five contiguous `@storage.copy` memcpys), and splitting hot physics columns into flat SoA + in-place `spark` SIMD **3.7× faster** than native Bevy AoS (**0.33 ms vs 1.22 ms** — though native Rust/Bevy could likewise adopt SoA columns or multi-threaded queries).
- **Bevy ECS leads on AoS archetype-table queries:** Grouping matching component bundles into dense untagged native Rust slices avoids `Maybe` tag checks and Wasm bounds checks — giving native Bevy a **1.36×–2.0×** lead over Ink's pure-Wasm `Pool`/cached queries (**1.22 ms vs 1.65–2.07 ms** dense, after Blot's Tier 4 deferred NaN canonicalization, hoisted `CheckedLe` bounds, and redundant variant tag-store elision; **0.068 ms vs 0.136 ms** sparse).

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
