# Programming-Language-Benchmarks (PLB): Blot vs Official Go, Rust, C & C++

Thirteen problems from [Programming-Language-Benchmarks (`hanabi1224/Programming-Language-Benchmarks`)](https://github.com/hanabi1224/Programming-Language-Benchmarks) — including the four `F64` / GeoJSON workloads (`nbody`, `spectral-norm`, `mandelbrot`, `json-serde`) — comparing **Blot** (`blotc-goose` `ff6f061a` + `wtime-aot 0.1.11` `--guard-pages`, x64 native) directly against **unmodified official PLB Go (`go 1.27.4`), Rust (`rustc 1.96.0-nightly -O -C lto=fat`), C (`clang -O3 -march=native`), and C++ (`clang++ -O3 -march=native`)** reference implementations on the same AMD Ryzen 7 7800X3D host.

Every program passes all official PLB `*_out` unittests (**26/26 fixtures**) and produces a **100% identical full-input stdout SHA-256** across every language on the full benchmark inputs.

![PLB Runtime](../evidence/measurements/2026-11-27-plb/plb_runtime.svg)

![PLB Peak Memory](../evidence/measurements/2026-11-27-plb/plb_memory.svg)

## Methodology & Fairness Notes

- **Measurement**: Exact per-child single-process CPU time (`ru_utime + ru_stime`), wall time, and peak RSS (`ru_maxrss`) via [`../goose-suite/measure_proc.c`](../goose-suite/measure_proc.c) (`posix_spawnp` + `wait4`), best CPU time across 3 interleaved repetitions (`helloworld`: median wall time across 15 launches).
- **Single-threaded normalization**: All reference programs run with `GOMAXPROCS=1` and `OMP_NUM_THREADS=1`. Note that official PLB Go `fannkuch-redux/1.go` and `fasta` explicitly override `GOMAXPROCS` / spawn goroutines inside `main`; reporting total CPU time (`cpu_ms`) keeps total compute work directly comparable.
- **Algorithmic transparency**:
  - `binarytrees`, `merkletrees`: use direct recursive `own` tree construction/traversal into stack-backed `Array.with_capacity` arenas (`binarytrees`) and a single `#[MNode]` pool (`merkletrees`), lowered to validated Mode-M/Mode-R recursive descriptor workers with 1-level leaf peeling and right-spine TCO.
  - `lru`: uses an open-addressed hash table over a single `#[Node]` doubly-linked pool (`nodes: #[Node]`).
  - `coro-prime-sieve`: Blot has no language-level coroutines/channels, so `coro_prime_sieve.blot` runs the iterative prime-filter chain (`primes[0..k-1]`), whereas official Go `1.go` spawns 4,000 goroutines and channels.
  - `pidigits`: `pidigits.blot` implements big integers in pure Blot using full base-`2^64` `U64` limbs (`#[U64]`) via `U64.mul_wide` (lowered by `wtime-aot` into hardware `mul r64` instructions via schoolbook `MulHiU` recognition + adjacent `(Mul, MulHiU)` fusion), whereas Go `8.go` uses Go's assembly-accelerated 64-bit `math/big`.
  - `nsieve`: `nsieve.blot` uses 1-byte `#[U8]` sieve flags (`42.9 MiB` RSS via best-fit stack chunk reuse), matching Go, Rust, and C.
  - `nbody`, `spectral-norm`, `mandelbrot`: use unboxed `F64x2` Wasm `v128` SIMD (`std/simd`) with compiler `F64`/`F64x2` NaN-canonicalization elision on non-escaping loops and return raw `#[U8]` ABI 8 output packets.
  - `json-serde`: parses and serializes `canada.json` (`2.2 MiB`, compiled with `--transport-mb 8`) using flat typed arenas, exact 128-bit `U64.mul_wide` IEEE-754 decimal-to-`F64` conversion, pure-integer Ryu shortest-decimal `F64` formatting, and RFC 1321 MD5 with direct `.rodata` constant tables (`280.2 ms` vs Go `318.3 ms`, `52.9 MiB` RSS vs Go `138.6 MiB`).
  - `rust` / `c` / `cpp` coverage: Only unmodified official PLB reference files that compile without third-party Cargo crates or external libraries (`apr_pools`, GMP, OpenMP, etc.) are included alongside Go (which covers all 13 with pure stdlib).
- **Remaining 5 of 18 PLB problems not yet ported**:
  - `regex-redux`, `http-server`: require regex engines / TCP HTTP networking.
  - `knucleotide`, `edigits`, `secp256k1`: require streaming large DNA stdin or multi-word bigints / elliptic-curve math.

## Reproduce

```bash
python3 benchmarks/plb/run_plb.py
```

- **Raw evidence**: [`results.json`](../evidence/measurements/2026-11-27-plb/results.json) (Nov 26 9-problem baseline preserved in [`../evidence/measurements/2026-11-26-plb/`](../evidence/measurements/2026-11-26-plb/results.json))
