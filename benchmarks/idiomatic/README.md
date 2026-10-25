# Idiomatic Blot and Rust workloads

These public source pairs implement the same computation using ordinary language
features and standard libraries. They compare small programs, not whole language
ecosystems or application build systems. Both compile to WebAssembly and execute
in the same Deno/V8 process. Native Rust is a separate comparison and is not
included here.

```sh
rustup target add wasm32-unknown-unknown
deno task build:compiler
deno task bench:idiomatic --out build/bench/idiomatic-release
```

Use `--compiler PATH`, `--rounds 5`, `--samples 31`, or
`--cases fibonacci,tree_reduce` to control a campaign. `--verify-only` compiles
each program once and validates outputs without publishing runtime samples. The
output directory must not exist. An interrupted or failed report has
`complete: false`; it is not a benchmark result.

## Workloads

Every program exports `run(seed: U32) -> U32`. Seeds enter at runtime; all
generated data contributes to the checked result. Every measured call includes
data construction, computation and release. Workloads use wrapping unsigned
arithmetic in both languages. Seven seeds include zero and unsigned boundary
values.

| Program               | Work per call                                              |
| --------------------- | ---------------------------------------------------------- |
| Fibonacci             | 2,048 iterative sequences of 24–39 steps                   |
| GCD                   | 4,096 Euclidean greatest-common-divisor computations       |
| Prime sieve           | Sieve and sum primes below 16,384–17,407                   |
| Integer recurrence    | 65,536 dependent LCG updates and checksum                  |
| Array map/reduce      | Generate 8,192 words, transform and reduce                 |
| Array filter          | Generate 8,192 words, select multiples of three and reduce |
| Prefix scan           | Inclusive sums over 8,192 words, then checksum             |
| Histogram             | 16,384 generated samples into 256 bins                     |
| Dot product           | Generate two 8,192-word arrays and reduce their products   |
| Matrix multiplication | Generate and multiply two 24×24 integer matrices           |
| Binary search         | 4,096 queries against 4,096 sorted words                   |
| List pipeline         | Build 4,096 values, map, filter and reduce                 |
| Option pipeline       | Transform/filter/reduce 16,384 optional values             |
| Decimal formatting    | Format 512 numbers and separators, then hash text          |
| CSV numbers           | Format and parse 512 comma-separated unsigned numbers      |
| Tree reduction        | Construct, sum and release a depth-10 binary tree          |
| Expression evaluation | Construct, evaluate and release a depth-9 expression tree  |
| Run-length encoding   | Encode 8,192 words into runs and checksum the runs         |

## What the comparison includes

Compilation uses fresh compiler processes, alternating language order and
workload order across rounds. Filesystem caches are warm; there is no claim of
cold disk performance. Rust uses
`--edition=2024 --crate-type=cdylib
--target=wasm32-unknown-unknown -C opt-level=3 -C panic=abort`.
Blot uses its optimized release tier and standard prelude. Rust links a
precompiled standard library; Blot checks imported library source. Timings
include each compiler's code generation and linking. Wrapper startup, toolchain
installation and compiler self-builds are excluded. The process wrapper records
wall time, child CPU and peak RSS on Linux.

Runtime samples alternate between languages after warmup. Each sample performs
enough calls to target about 5 ms, bounded to 7–7,168 calls, using balanced seed
cycles. Every sample's checksum is validated outside its timed interval.
Independent TypeScript witnesses validate both programs; the Blot adapter is
also checked against the public guest API. Timed Blot calls use the required
ownership entry/exit and arena reset hooks; Rust calls include its generated
allocation and drop code. Module compilation/instantiation and JavaScript
argument validation are excluded from runtime samples. Scalar calls avoid array
marshalling costs.

Language differences remain visible. Rust iterators can fuse map/filter/scan
pipelines where Blot's standard functions construct intermediate collections.
Blot Lists are persistent collections; Rust uses the idiomatic `Vec` for these
sequential workloads. Text workloads use ASCII but retain native representation:
Blot Unicode scalar arrays and Rust UTF-8 strings. Tree allocations and
ownership representations differ. The prime sieve uses each language's ordinary
boolean collection. Results should not be described as identical low-level
algorithms or proof that one compiler is universally faster.

The JSON report preserves exact commands, toolchain versions, host CPU/affinity,
compiler/source hashes (including Rust target libraries and bundled compiler/
linker libraries), Wasm hashes and sizes, all samples, output witnesses, and
committed Wasm memory. Committed memory is not live heap size or process RSS.
Compiler hashes and all pinned sources must remain unchanged throughout a run.

Rust target behavior and optimization flags are documented in the
[Rust target guide](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html)
and
[code-generation options](https://doc.rust-lang.org/rustc/codegen-options/index.html).
