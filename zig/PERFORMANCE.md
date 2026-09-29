> Historical measurements: these numbers describe the earlier performance patch
> against `ac59fb6`, before the syntax/protocol-14 integration. They are not
> measurements of the current `main` snapshot or evidence of a completed IR
> rewrite.

# Native Zig performance pass

This pass removes measured costs from the mechanical semantic port. It does not
replace the entire compiler: the Deno/Baba source frontend, generic semantic
value representation, most type inference and specialization, and source-derived
Wasm lowering remain. These are local before/after measurements, not a speed
claim against Bend or other languages' compilers.

## Changes

- Small semantic objects use a task-private bump cursor over 64 KiB slabs.
  Allocations above 16 KiB use the request allocator directly. The shared,
  thread-safe arena is touched on slab refills rather than every small object. A
  child never owns the backing arena, and all jobs join before it is destroyed.
- Fork/join batches reserve only the pool's spare-worker capacity. Nested or
  excess siblings run locally rather than flooding the shared queue. Contexts
  are cache-line aligned; results retain source order and immutable sharing.
- Twenty-three hot semantic entry points use handwritten Zig: name equality,
  string/numeric index lookups, persistent numeric insertion, CST field scans,
  protocol decoding, ordered free-variable operations and simple type-resolution
  cases. Numeric insertion uses a bounded path stack and copies only that path.
  Wide free-variable operations use temporary native hash tables while
  preserving the reference's order, right-hand duplicates and previous
  snapshots.
- The protocol decoder uses a native cursor, dictionary array and explicit
  parent stack. It builds only the finished semantic request/CST, preserves
  exact diagnostic precedence, and reverses only unpublished result lists in
  place.
- Known constructor and primitive identities are compile-time Zig parameters. A
  single-register result replaces the aggregate value/tail union. Optimized LLVM
  builds jump directly between known tail targets; Debug and non-LLVM builds
  retain the bounded trampoline. Dynamic closure targets still use it.
- Native overrides are gated by exact source-module hashes and dependency
  checks. Editing a corresponding reference algorithm disables its affected
  overrides until revalidated. Compound type resolution still calls the original
  algorithm compiled to ordinary Zig; there is no Bend or JavaScript runtime
  fallback.

## Measurement method

The baseline is the verified ReleaseSafe compiler artifact for `9e28dfb`; its
Zig implementation is unchanged at PR head
`a9f20b049ec54a473879385bfdd8e302597e0875`. Both binaries use Zig 0.16.0, LLVM,
ReleaseSafe and baseline x86-64 instructions, not host-specific ISA flags.

Both measurements use the existing main fixes at
`ac59fb68f98780e168ce01fa39410b1a6ef54efd`, as the GitHub PR merge checkout does
(`cd3a43e36240bcbba661a05ecbe5b4d4066825b2`). All 70 local semantic module
hashes match the baseline artifact's manifest. The speedup therefore compares
identical reference algorithms, not a mixture of the old PR branch and newer
main fixes. The candidate adds only the changes described above.

**Reproduction requires integrating that main revision into the PR branch before
applying this patch.** The branch alone has older string/numeric index sources;
the hash guards correctly disable affected native paths for those older sources.

Five existing fixtures from `compiler/benchmark_workloads.ts` were selected
before measuring the candidate. Each timing is the median of five stateless
compilations after one warmup in a persistent compiler process.
`prelude: "none"` is explicit. No retained/incremental compilation cache is
used. Process startup and toolchain build time are excluded. Source-call
measurements include the existing frontend and IPC; backend measurements replay
a previously encoded request and include IPC, semantic compilation and response
encoding but not source parsing. Backend results are checked byte for byte
against the old binary, and the emitted Wasm entry returns the fixture's
expected value in the source-call measurements.

Measurements ran serially with no concurrent compiler builds or test suites in
this four-CPU-quota, 4 GiB Linux container. It is not a dedicated benchmark
machine; these are a small fixture sample, fixed before/after run order, and not
a guarantee for arbitrary applications. Raw samples accompany the patch's
evidence bundle. Peak RSS is a separate fresh-process measurement of one encoded
request using GNU `time`, not total allocation bytes and not the Deno process's
memory.

### Complete source-to-artifact calls, one compiler thread

| Workload      | Source bytes | Before (ms) | After (ms) | Speedup |
| ------------- | -----------: | ----------: | ---------: | ------: |
| `lexical_256` |       78,535 |       809.3 |      538.7 |   1.50x |
| `nominal_256` |       15,115 |       137.5 |       68.2 |   2.02x |
| `reader_64`   |       10,808 |       111.7 |       69.7 |   1.60x |
| `balanced_64` |      153,717 |      1215.8 |      860.8 |   1.41x |
| `chain_64`    |        3,537 |        32.6 |       19.7 |   1.66x |

`lexical_256` contains eight functions with 256 bindings each. `nominal_256`
contains 256 nominal types and associated functions. `reader_64` exercises
effect handlers, `balanced_64` contains 64 arithmetic functions with 64 steps
each, and `chain_64` is a 64-function dependency chain. Fixture sizes are not
normalized to lines per second because these programs do different amounts of
semantic work.

### Existing examples with the default prelude

A separate end-to-end check used the default native API options (including its
normal prelude), one compiler thread, one warmup and three measured
compilations. Every Wasm artifact was valid and byte-identical between the two
compilers. This check ran after the full suites and optimized unit-test build
had finished.

| Program                | Before (ms) | After (ms) | Speedup |
| ---------------------- | ----------: | ---------: | ------: |
| `examples/syntax.blot` |       120.0 |       65.8 |   1.82x |
| `examples/ecs.blot`    |       434.4 |      289.7 |   1.50x |

### Encoded request to complete response

| Workload      | Threads | Before (ms) | After (ms) | Speedup |
| ------------- | ------: | ----------: | ---------: | ------: |
| `lexical_256` |       1 |       693.3 |      379.6 |   1.83x |
| `nominal_256` |       1 |       108.0 |       41.1 |   2.63x |
| `reader_64`   |       1 |        89.8 |       52.1 |   1.72x |
| `balanced_64` |       1 |      1025.6 |      624.5 |   1.64x |
| `chain_64`    |       1 |        30.1 |       15.5 |   1.94x |
| `lexical_256` |       4 |      1202.4 |      317.5 |   3.79x |
| `nominal_256` |       4 |       119.1 |       37.0 |   3.22x |
| `reader_64`   |       4 |        87.1 |       50.6 |   1.72x |
| `balanced_64` |       4 |      1176.0 |      508.4 |   2.31x |
| `chain_64`    |       4 |        28.8 |       15.6 |   1.84x |

The four-thread improvement is largely removal of the old shared-allocation and
task-queue overhead, not fourfold parallel scaling. The new compiler still has
serial work and workload-dependent scaling.

### Compiler process peak resident memory

| Workload      | Threads | Before (MiB) | After (MiB) | Reduction |
| ------------- | ------: | -----------: | ----------: | --------: |
| `lexical_256` |       1 |        355.4 |       234.6 |     34.0% |
| `nominal_256` |       1 |         63.8 |        32.9 |     48.4% |
| `reader_64`   |       1 |         48.4 |        33.4 |     30.9% |
| `balanced_64` |       1 |        461.5 |       283.2 |     38.6% |
| `chain_64`    |       1 |         20.7 |        16.3 |     21.2% |
| `lexical_256` |       4 |        361.6 |       237.0 |     34.5% |
| `nominal_256` |       4 |         64.9 |        34.2 |     47.3% |
| `reader_64`   |       4 |         49.5 |        35.2 |     29.0% |
| `balanced_64` |       4 |        474.9 |       284.9 |     40.0% |
| `chain_64`    |       4 |         21.7 |        17.4 |     20.1% |

## Validation

Validation results are recorded in the accompanying evidence bundle. No timing
benchmark or performance threshold has been added to GitHub Actions. The
existing compiler correctness/compatibility tests are unchanged.
`zig build test` additionally runs the new deterministic native-algorithm and
protocol regressions.

Native tests cover Unicode/prefix/NUL strings, persistent snapshots, all 48
numeric index branching bits, 4,096 mixed numeric-index operations checked
against an independent hash map, ordered wide free-variable operations, slab
alignment and refills, bounded fork reservations, type-resolution fallbacks and
diagnostics. The decoder regression includes a 4,096-node CST under a 1 MiB hard
stack limit.

After integrating main revision `ac59fb68f98780e168ce01fa39410b1a6ef54efd` and
applying the patch, build and test from the repository root:

```sh
(cd zig && zig build -Doptimize=ReleaseSafe)
(cd zig && zig build test -Doptimize=Debug -j1)
(cd zig && zig build test -Doptimize=ReleaseSafe -j1)
deno task blot:zig check examples/syntax.blot
deno task blot:zig build examples/syntax.blot build/syntax.wasm
```

The complete compatibility tests still need the unchanged JavaScript reference
modules for comparison. They are not needed to use the Zig compiler itself. Use
the existing source CLI/native API to select the candidate executable;
`blotc-zig` alone is the framed compiler service, not a `.blot` source-file CLI.

## Tradeoffs and remaining work

Direct native tail calls increase the size of the LLVM optimization problem. The
final optimized executable build took about seven minutes locally; this is a
development observation, not a controlled compiler-build benchmark. Debug
retains the simpler trampoline path. Source compilation speed and compiler
construction are separate measurements; the performance tables above exclude
construction.

This remains an intermediate architecture. Type IDs, expression nodes and most
compiler collections still use the source-derived tagged representation. A
future stage-level rewrite should move hot IR/type data into compact typed
arrays and stable IDs, reduce intermediate traversals, and retain only the state
invalidated by edits. The existing language/ABI and differential tests are the
constraints, not the old implementation's object layout.
