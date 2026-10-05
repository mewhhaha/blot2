# Standard library API and performance audit

The October 2026 audit covers `std/prelude`, `std/array`, `std/list`,
`std/vector`, their compiler lowering, and the Deno compiler/guest boundary.
The changes remove avoidable demand objects, repeated collection copying and
vector intermediates. They preserve immutable values, callback order, numeric
behavior and fresh-versus-retained compilation parity.

## API behavior

Collection transformations keep their collection argument last for pipelines.
`List a` and `Array a` remain distinct. Lists support traversal and construction;
only arrays expose indexing, checked `get`/`set`, and trapping `at`/`replace`.
Conversions are explicit. Numeric arrays cross the guest ABI by copying, so
host mutation cannot alter retained guest values.

List `fold_left` now propagates reducer effects, matching the array fold.
The added list `any` and `all` propagate effects and stop at the first deciding
element. Empty inputs return false and true respectively without invoking the
callback. List `filter` retains effectful predicates and visits each element
once in order. Array construction and collection `map`/`generate` retain their
pure callback contracts.

`Result.unwrap_or_else` now matches the existing Maybe operation: its fallback
is deferred until failure. `unwrap_or` remains eager. `@demand` is the preferred
spelling for evaluating a deferred argument; `@force` remains an alias. A
successful demand is shared, whereas an ordinary callback runs each time it is
called. See the [demand design](../zig-native/DEMANDS.md) for the full contract
and remaining control-flow questions.

The public compiler API remains asynchronous. Keep a `createCompiler` instance
open across edits to retain work, and dispose it when finished. The reference
now documents `prelude: null`, directory aliases and source validation using the
Zig API. Guest lifetime, host exceptions and queued project requests remain
covered by their existing regression suites.

## Implementation changes

| Area | Change and cost boundary |
| --- | --- |
| `&&`, `||`, simple demand combinators | Known, fully applied bodies use branches and locals. Admission examines at most 48 expression nodes and never matches operator names. Repeated demands share a local result, reset per call. |
| `prefix_sums` | Recursive pair sums replace full-array doubling passes. Total work and intermediate array storage are linear, including constant evaluation. U32 wrapping behavior is unchanged. |
| `indices`, `filter`, `filter_map` | One runtime traversal collects into a private chunked list, followed by one array conversion. Predicates/transforms run once per input element. |
| Conditional list construction | Ownership flows through `if let` branches when no previous version remains live. Surviving aliases and closure captures still prevent mutation. |
| `list.append`, `list.prepend` | Direct wrappers and their aliases preserve the intrinsic's ownership optimization. A fully applied wrapper must use each of its two parameters exactly once as the intrinsic operands. Actual arguments still evaluate in written order. |
| Array `push`, `concat` | `push` uses the append primitive. `concat` avoids intermediate chunk arrays and checks length overflow before filling its result. Array append still copies. |
| Vector `lerp` | Vec2/Vec3 construct one result from scalar interpolation, preserving the existing F32 operation order. |
| `F32.tan` | Sine and cosine share one angle reduction. The documented finite domain and nonfinite behavior remain unchanged. |

Inlining records the consumed body's module in the caller's code artifact.
Retained compilation checks that dependency and carries it forward when code is
reused again. A changed callee body can therefore invalidate emitted callers
even when its function type is unchanged. Validation is currently conservative
at module granularity.

## Reproducing library measurements

The baseline is commit
`775d3707d27c5c5d64504206c6b3824a458d8929`. The paired harness pins both native
executables and all four standard-library files, checks guest results, and saves
every sample and compilation record:

```sh
deno run --allow-read --allow-write --allow-run scripts/bench_stdlib.ts \
  zig-native/zig-out/bin/blotc std build/stdlib-bench \
  /path/to/baseline/blotc /path/to/baseline/std
```

Use a separately built baseline; changing only library files would miss the
ownership and demand improvements. The executable's build identity rejects
incompatible dependency bundles.

Runtime samples include guest ABI copies. Each variant receives 1,000 warmups,
then 31 alternating samples of 16 calls. Inputs contain 8,193 elements or loop
iterations, except list append, which uses 1,025. Reported memory is committed
guest pages after repeated calls, not total allocated bytes or compiler RSS.
The harness's individual compilation records use a warm filesystem and are not
a cold compilation distribution.

The final run used Zig 0.17.0, Deno 2.9.7 and V8 15.0.245.2-rusty.
The current compiler identity was
`c827798cae5e6276badeaf83bc8abd341634741c29f5047855e62ea688508377`;
the baseline identity was
`2d8050d273b5baa98107c2a38d4144b92885bbe16d0e510e5b2b41b23968c850`.

| Runtime probe | Before ms | After ms | Guest memory before KiB | After KiB |
| --- | ---: | ---: | ---: | ---: |
| Inclusive prefix sums | 0.259 | 0.064 | 1,088 | 384 |
| Selected indices, including the input flag map | 0.564 | 0.054 | 1,280 | 320 |
| Array filter | 0.367 | 0.040 | 1,280 | 256 |
| Array filter_map | 0.502 | 0.065 | 1,600 | 512 |
| Array concat | 0.026 | 0.026 | 320 | 256 |
| Array flatten | 0.025 | 0.024 | 320 | 320 |
| Array push | 0.017 | 0.003 | 256 | 192 |
| List append loop, 1,025 elements | 2.184 | 0.008 | 5,312 | 128 |
| Vec3 interpolation loop | 0.369 | 0.193 | 3,200 | 2,176 |
| Result iteration loop | 0.172 | 0.184 | 128 | 128 |
| Array of F32 tangents | 0.115 | 0.093 | 256 | 256 |

Filtering is about nine times faster in this probe, filter_map about eight,
prefix sums about four, and vector interpolation about two. The list builder
previously copied its growing contents on each library call; it now uses the
same exclusive chunk reuse as spread syntax. That particular cost change
accounts for its much larger gain. Concat and flatten have similar runtime.
Result iteration has byte-identical Wasm; its differing measured medians do
not indicate an implementation change.

The scalar Boolean probes shrink from 1,579 to 101 Wasm bytes, with two emitted
functions and no memory or function table. Explicit `if` remains 95 bytes.
Source and compiled-dependency builds produce identical output for all four
conjunction/disjunction probes. These module sizes include shared helper code;
they are not a per-operator byte cost in a larger application.

Raw samples, hashes, generated Wasm and full compilation records are retained
locally in `build/stdlib-review/paired/report.json` and
`build/stdlib-review/demands/`. Build artifacts are ignored by Git; the harness
above reproduces the comparison from the two source/compiler versions.

## Game compilation

Compilation uses one pinned gdev snapshot for both variants: 27 loaded source
files including the prelude, about 193 KB total. The source manifest is
`build/stdlib-review/gdev-snapshot/sources.json`, SHA-256
`57d4f3b36a270290472132339c59a9b29158fa04a35306f9b1e4d7ab88fc8a4c`.
Game sources continued changing during the audit; this comparison excludes the
later rock/grid additions exercised by the final integration tests.

| Compilation boundary | Before median ms | After median ms |
| --- | ---: | ---: |
| Fresh CLI, source dependencies | 350.8 | 348.6 |
| Fresh CLI, precompiled dependencies | 316.6 | 312.7 |
| First retained edit, source dependencies | 122.6 | 118.2 |
| Later retained edit, source dependencies | 117.7 | 122.6 |
| First retained edit, precompiled dependencies | 121.0 | 118.4 |
| Later retained edit, precompiled dependencies | 116.8 | 115.4 |

These results show similar compiler latency. Fresh source builds ranged from
345.0 to 354.2 ms after the changes; dependency builds ranged from 311.3 to
323.1 ms. Peak process RSS was about 44 MiB in both variants. Generated game
Wasm fell from 249,128 to 245,282 bytes.

Each cold lane has five alternating fresh process runs, including output writing
and teardown. Executable, Blot source and used bundle pages were evicted and
checked nonresident before launch; system libraries and filesystem metadata were
not controlled. Bundle creation is excluded and measured separately in its
compilation log. Full samples, CPU time and RSS are in
`build/stdlib-review/game-bench/report.json`.

Retained timings are public build-request round trips, measured in three
sessions per lane with warm filesystem caches. Every edited output is checked
against a fresh build. Process/session population is recorded separately, not
hidden in edit times. Adding Wasm validation, hashing and output writing gives
current edit medians of about 133–143 ms; no-op request medians are 1.3–1.7 ms
before those output costs. The 500 ms cold target is met on this snapshot;
**the under-100 ms incremental target is still unmet**. Full records are in
`build/stdlib-review/game-bench/incremental.json`.

## Verification

`deno task test:compiler` passes: native production tests, packaged compiler,
and all 460 guest/client tests. The new execution tests cover wrapping sums,
empty/chunk-boundary collections, alias snapshots, effects, early exits,
repeated demands, loop memo reset, F32 behavior and retained-body edits.
Storage bounds detect growing-copy regressions without timing assertions.

The current gdev integration suite passes all 58 tests. Its scene assertions
were updated concurrently for new render fixtures; no gdev source edits were
made by this audit. Zig Analyzer reports zero errors and 129 existing warnings,
with none in the new optimization files. Formatting, type checking for the
benchmark harness and `git diff --check` pass.

## Remaining costs

- Complex, partially applied, escaping and match-based demand functions still
  use runtime cells. This includes the Maybe/Result fallback helpers; their
  evaluation behavior is correct, but their storage is not yet eliminated.
- Ownership through arbitrary higher-order collection functions remains
  conservative. Shared list edits copy contents; contiguous array append also
  copies. General aggregate boxing and `Result.iterate` intermediates remain.
- The const evaluator stores immutable collection values. Staged append and
  update loops can still be quadratic, including large staged filters. The
  runtime ownership proof is not sufficient to mutate compiler-cached values.
  The prefix-sum rewrite avoids this problem without changing evaluator
  ownership.
- Demand inlining validates whole modules. Finer body dependencies could retain
  more emitted code after edits. Sub-100 ms incremental gdev compilation remains
  a separate compiler target.

The broad tests cover correctness; the paired probes cover representative
runtime costs. They do not establish that every standard-library operation is
optimal on every workload.
