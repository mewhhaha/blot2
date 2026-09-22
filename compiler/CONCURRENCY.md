# Concurrency review and benchmark report

The [retained-memory diagnosis](MEMORY.md) identifies a native Bend 2.0.21
code-generation defect at two sites accounting for all observed leaked
allocations in the 200-edit workload. An isolated generated-C control reduces
eight-core RSS from about 177 to 71 MiB and restores the exact empty-session
allocation baseline after reset; no production repair has been applied yet.

## Stopping point and remaining priorities (2026-09-22)

This is a good stopping point for broad concurrency tuning. Keep the measured
wins and use representative projects to identify the next bottleneck; the
rejected experiments show that additional forks, parser workers, or native
output machinery do not reliably improve elapsed time. A general dynamic ready
queue would be a larger scheduler change without an established payoff here.

The highest-priority remaining issue is the [native allocation leak](MEMORY.md).
The pinned Bend 2.0.21 standalone reproducer was rerun during the commit review:
Scalar still loses **16 bytes per call**, while Pair loses none, with both one
and eight configured workers. Earlier whole-compiler accounting measured about
**545 KiB leaked per edit** in the retained Balanced workload; that exact
whole-compiler rate was not remeasured after the latest lookup changes. This
should be repaired before relying on long-lived incremental processes.

Some eager recursive lookup fallbacks remain in `operators.lookup`,
`source_types.lookup_variable`, `infer.lookup_label`, `globals.lookup`, and
`dependency.lookup`. These are candidates for a bounded follow-up, especially
with unusually large scopes, but their contribution to real workloads has not
been measured. They are not evidence that another broad optimization pass is
needed now. True dependency joins, shared constant-evaluation fuel, canonical
metadata and ordered publication also still limit scaling.

## Short-circuit name lookup (2026-09-22)

The next lever is avoiding work inside compiler tasks. `Bool.pick` eagerly
evaluates both result arguments in Bend. Four lookup functions placed recursive
searches in its fallback argument, so a hit still searched every remaining
binding. The generated JavaScript confirms the recursive call executes before
`Bool.pick`; all four old lookups also overflowed the host stack on a
10,000-binding scope with a matching first binding.

Wasm local lookup and constant-evaluator local, constant, and function lookup
now carry a found value into a tail-recursive match, following the existing
inference lookup pattern. They retain the first matching binding and the exact
missing-name diagnostic. No inference or constant-evaluation fuel rules change.
Four new regression tests cover shadowing, late hits, missing names and deep
scopes; four laws/proofs protect stopping after a hit. All **502 compiler
tests** pass with pinned Bend 2.0.21.

The starting worktree, including all preceding uncommitted changes, is saved in
`build/next-lever-baseline`; the selected lookup candidate is saved in
`build/next-lever-lookups`. The new `lexical_256` CPU workload has eight
exported functions with 256 consecutive local bindings each. Benchmarks use
production `clang -O3` builds, physical-core affinity, alternating paired
variants, separate fresh hosts and JS oracles, exact artifact comparisons, and
Wasm execution. Builds and tests finish before timed measurements. Desktop
applications remain active, so these are not isolated-machine measurements.

### Lookup measurements

Five paired samples per configuration; median milliseconds, **before → after**:

| Workload                       | One physical core | Eight physical cores | Eight-core change |
| :----------------------------- | ----------------: | -------------------: | ----------------: |
| Long lexical scopes, clean     |   284.69 → 249.50 |      155.16 → 118.93 |            −23.4% |
| Long lexical scopes, warm edit |     51.21 → 46.88 |        59.93 → 56.04 |             −6.5% |
| Balanced 64, clean             |   408.55 → 394.55 |      120.91 → 118.98 |             −1.6% |
| Balanced 64, warm edit         |     52.27 → 52.27 |        29.94 → 29.76 |             −0.6% |
| Reader 64, clean               |     40.82 → 40.69 |        34.63 → 35.23 |             +1.8% |
| Reader 64, warm edit           |     11.51 → 11.06 |        13.84 → 13.86 |             +0.1% |
| Chain 64, warm edit            |       7.50 → 5.96 |        12.04 → 12.48 |             +3.7% |

The long-scope clean sample ranges do not overlap: **278.49–290.36 →
239.00–252.27 ms** at one core, and **154.16–158.06 → 118.18–120.74 ms** at
eight cores. The one-core clean improvement is **12.4%**. The eight-core warm
ranges are **57.73–60.86 → 54.79–56.67 ms**. The same clean fixture improves in
JavaScript from **806.36 → 717.87 ms** (11.0%).

The ordinary controls have overlapping ranges; the Chain eight-core median is
3.7% slower, so this is not a universal speedup. Long-scope warm edits also
remain slower with eight workers than with one. The gain comes from removing
unnecessary searches inside tasks, not from adding concurrency or removing real
dependency joins. Measurements cover one and eight physical cores.

[Clean build measurements](../build/next-lever-lookups-clean.json),
[warm edit measurements](../build/next-lever-lookups-warm.json),
[compiler tests](../build/next-lever-lookups-tests.log),
[proof check](../build/next-lever-lookups-proof.log).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/lookups-clean.json build/next-lever-baseline,. 5 1,8 lexical_256,balanced_64,reader_64 full
deno run --allow-all compiler/cpu_scaling_bench.ts build/lookups-warm.json build/next-lever-baseline,. 5 1,8 lexical_256,balanced_64,reader_64,chain_64 incremental
```

### Rejected direct native byte writer

A fresh diagnostic trace of the starting compiler measured a Balanced warm edit
at eight cores with **6.61 ms wall / 7.02 ms CPU** in packing, versus **4.88 /
15.44 ms** in inference. A prototype moved byte validation into the native
response-buffer writer, removed packed-word allocation, withheld the whole frame
until validation succeeded, and retained the previous session on failure. It
passed byte-for-byte comparison with the pure encoder for 27 padding, size,
invalid-byte, length-mismatch and recovery cases at one and eight workers, plus
the existing native output tests.

The first three-pair warm run suggested an 8.8% Balanced improvement at eight
cores. Five-pair confirmation did not reproduce it: Balanced **30.72 → 30.34
ms**, Reader **13.14 → 13.18 ms**, and shared-frontier diamonds **28.59 → 28.85
ms**, with overlapping ranges. Clean controls were mixed as well. The additional
native code was rejected and fully restored to the starting version. The
prototype and its regression fixture remain in `build/next-lever-direct`.

[Starting phase traces](../build/next-lever-events/),
[initial direct-writer warm run](../build/next-lever-direct-warm.json),
[confirmation](../build/next-lever-direct-confirm.json),
[clean controls](../build/next-lever-direct-clean.json),
[old-lookup stack-overflow reproduction](../build/next-lever-lookup-reproduction.log).

## Further concurrency experiments (2026-09-22)

Baseline: the entire preceding worktree, including its uncommitted changes, was
saved in `build/concurrency-exhaustive-baseline`. The selected compiler is saved
in `build/concurrency-selected`. Builds and measurements use pinned Bend 2.0.21
and production `clang -O3`. The installed `bend` reports 2.0.24, so builds used
the existing 2.0.21 binary under `build/bend-2.0.21-8imodn/bend/bin`.

### Retained changes

- **Independent module bodies.** Source-module scopes, imports and fixities are
  prepared in dependency order. Bodies then lower in weighted Bend batches with
  a 512-node grain. Imported name catalogs do not require completed bodies.
  Ordered collection preserves the earlier module's diagnostic, including when
  its body fails before a later module's scope preparation fails. Empty and
  single-module projects bypass batching. A new law/proof protects first-error
  collection; native tests cover one, two, four and eight workers.
- **Independent SCC passes.** Value-dependency and nominal-type SCC discovery
  fork when both graphs contain at least 32 nodes. Small graphs stay sequential.
  Both results are consumed in the original diagnostic order. Recursive groups,
  transitive summary dependencies, and inference joins retain their semantics.
- **Bounded file reads.** The project loader reads up to four imported files
  concurrently, deduplicating canonical URLs. Parsing, cycle detection and
  module publication retain depth-first order. Prefetched failures remain values
  until their original position is reached, and outstanding reads drain before
  the frontend is disposed. A deferred-read test proves overlap and the
  four-read limit without relying on timing.

### Selected measurements

Ryzen 7 7800X3D, physical CPU affinity, paired variants with alternating order,
complete artifact equality and Wasm execution outside timing. No build, test or
second benchmark ran during these measurements; desktop applications remained
active. These are not isolated-machine measurements.

The project driver starts a fresh native process for each configuration, with
two warmups, but retains its host across samples. Projects are parsed before
timing; compilation includes normalization, transport, checking, emission and
response decoding. The module fixtures contain eight imported modules, either
one 256-step body each or sixteen 96-term functions each. The raw-source CPU
driver uses separate fresh hosts and JS-oracle processes, and includes parsing
in its full-build times. Its new `nominal_256` fixture contains 256 nominal
types, chains of sixteen payload dependencies, and 256 annotated functions.

Median milliseconds, **before → after**:

| Workload                                         | Samples | One physical core | Eight physical cores | Eight-core change |
| :----------------------------------------------- | ------: | ----------------: | -------------------: | ----------------: |
| Eight large module bodies                        |       5 |   177.80 → 181.10 |      195.77 → 158.53 |            −19.0% |
| Eight wide modules                               |       3 | 1068.04 → 1068.47 |      280.02 → 268.04 |             −4.3% |
| Nominal 256, raw-source clean build              |       5 |    95.27 → 101.66 |        80.82 → 62.07 |            −23.2% |
| Balanced 64, raw-source clean build              |       5 |   417.61 → 408.05 |      121.40 → 122.53 |             +0.9% |
| Reader 64, raw-source clean build                |       5 |     39.80 → 38.10 |        35.23 → 35.26 |             +0.1% |
| Shared-frontier diamonds, raw-source clean build |       5 |   159.56 → 161.56 |      105.21 → 105.84 |             +0.6% |

Eight-core ranges do not overlap for the target cases: large module bodies
**194.85–201.71 → 154.59–169.37 ms**, wide modules **279.46–289.83 →
265.28–274.72 ms**, and Nominal 256 **77.05–87.15 → 60.16–64.44 ms**. The
single-core nominal median regresses **6.7%**, with overlapping ranges
(**88.41–109.96 → 88.75–115.41 ms**). Large module bodies regress **1.9%** on
one core. These tradeoffs remain; the changes favor substantial multicore work.
The ordinary clean-build controls have overlapping ranges. Measurements cover
one and eight cores, not a new two-through-seven-core sweep.

[Module measurements, one core](../build/concurrency-selected-modules-1.json),
[eight cores](../build/concurrency-selected-modules-8.json);
[wide modules, one core](../build/concurrency-selected-wide-1.json),
[eight cores](../build/concurrency-selected-wide-8.json);
[fresh-host clean controls](../build/concurrency-selected-clean.json).

Warm-edit controls also checked `nominal_256`, `balanced_64`, `reader_64`,
`chain_64`, and `shared_frontier_diamonds_8`. The initial three-pair run had a
noisy one-core Balanced median (**40.40 → 49.91 ms**). A five-pair repeat
reversed that result (**55.67 → 49.84 ms**, ranges **44.45–57.76 → 43.40–60.07
ms**), so neither run establishes a reliable change there. The repeated nominal
one-core warm median was **34.23 → 34.71 ms**. A separate five-pair Reader
eight-core repeat measured **13.27 → 13.40 ms**, also with overlapping ranges.
These warm controls establish no consistent additional speedup or regression;
the clean-build single-core tradeoffs above remain.
[Initial warm controls](../build/concurrency-selected-warm.json),
[one-core repeats](../build/concurrency-selected-warm-control.json),
[Reader repeat](../build/concurrency-selected-reader-control.json).

```sh
# Build with the repository's pinned Bend before benchmarking.
taskset -c 0,1,2,3,4,5,6,7 deno run --allow-all compiler/project_concurrency_bench.ts build/projects.json build/concurrency-exhaustive-baseline,. modules 5 8
# Use taskset -c 0 and threads=1 for the matching one-core control.
# wide_modules selects the already-parallel per-module control.
deno run --allow-all compiler/cpu_scaling_bench.ts build/nominals.json build/concurrency-exhaustive-baseline,. 5 1,8 nominal_256 full
```

### Other candidates tried

All rejected sources and binaries remain in the named local snapshots. The
figures below describe combined experiments where several changes were tested
together; they do not establish an isolated speedup or cost for every component.

| Candidate                                                                                                 | Result                                                                                                                                                                                                                                                                                                                                                                                            |
| :-------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Parallel canonical-table normalization, reachability indexes/filtering, and analysis/byte-packing overlap | The combined coarse-fork candidate regressed Balanced warm edits at eight cores **29.40 → 36.48 ms**. Not retained. [Report](../build/concurrency-coarse-forks.json), snapshot `build/concurrency-coarse-forks`.                                                                                                                                                                                  |
| Parallel exact planning-key sections plus sized output groups                                             | Balanced warm edits regressed **33.35 → 35.78 ms**, diamonds **30.23 → 36.12 ms**, at eight cores. Aggregate size checks and serial error fallback preserved key semantics, but no performance win was established. [Report](../build/concurrency-sized-groups.json), snapshot `build/concurrency-sized-groups`.                                                                                  |
| Preserve sized output groups, traverse directly, and pack by byte weight with serial keys                 | Balanced warm edits were essentially unchanged at eight cores, **29.57 → 29.46 ms**; small controls were mixed. The extra representation was not retained. [Report](../build/concurrency-direct-groups.json), snapshot `build/concurrency-direct-groups`.                                                                                                                                         |
| Validate bytes in Bend, then copy raw chunks in native transport                                          | Passed all 498 compiler tests, but warm and clean controls remained mixed. Balanced clean one-core compilation regressed **397.32 → 421.85 ms** while eight-core time stayed flat. Original output/transport implementation restored. [Warm report](../build/concurrency-byte-transport.json), [clean report](../build/concurrency-byte-clean.json), snapshot `build/concurrency-byte-transport`. |
| Parse large sibling modules in workers                                                                    | Exact CST and failure/lifetime checks passed. A pinned five-pair load test, including worker startup and materialized-CST transfer, regressed **1446.40 → 1629.24 ms** for eight large modules. Removed; code and replay script are preserved in `build/concurrency-direct-groups`. [Report](../build/concurrency-project-loader-pinned.json).                                                    |

A separate SCC microbenchmark on two 257-node chains checked complete component
lists after every sample. For 100 iterations, serial/parallel execution measured
**367/344 ms at one worker** and **456/255 ms at eight workers**. This is a
phase-only result; it does not explain all of the end-to-end nominal speedup.
[Probe source](../build/concurrency-scc-probe.bend),
[one-worker result](../build/concurrency-scc-1.txt),
[eight-worker result](../build/concurrency-scc-8.txt).

### Verification and limits

The selected source passes **498 compiler tests**, the proof gate including the
new module-ordering law, native ownership checks, TypeScript checks, and
formatting checks. The original output representation, transport, cache-key
encoding, reachability traversal, and parser-worker policy remain in place. The
existing retained-memory issue is outside this change.

This evaluates the identified concurrency candidates; it does not prove a global
optimum. Real dependency joins, recursive inference components, fuel-accounted
constant evaluation, canonical metadata, ordered publication, and serial
transport/assembly still limit scaling. A general dynamic ready queue and
parallel inference inside a single recursive component were not introduced.

## Chunked native output (2026-09-21)

Baseline: the complete preceding worktree saved in
`build/cpu-before-chunked-output-VZNk3h`, including selective nominal caching,
parallel relocation, and shared-frontier scheduling. Both variants use pinned
Bend 2.0.21. This pass does not repair the upstream retained-memory defect.

### Selected one-pass implementation: warm edits

Five interleaved fresh-process samples, two warmups per sample, host/child
pinned to one or eight physical Ryzen 7 7800X3D cores. Production binaries are
built with `clang -O3`; startup and artifact validation are outside the timing.
No other compiler build, test, or benchmark ran concurrently, but desktop
applications remained active. Cores two through seven were not remeasured.

Median milliseconds, **before → after**:

| Workload                   | Native, one core | Native, eight cores |
| :------------------------- | ---------------: | ------------------: |
| Balanced 64                |    43.87 → 41.08 |       33.17 → 31.15 |
| Reader 64                  |    11.15 → 11.49 |       14.13 → 13.49 |
| Shared-frontier diamonds 8 |    33.60 → 32.99 |       28.85 → 27.71 |
| Chain 64                   |      5.91 → 5.73 |       12.35 → 12.59 |

Balanced improves **6.4% at one core and 6.1% at eight**, with nonoverlapping
sample ranges: **42.99–44.59 → 40.73–42.24 ms**, and **32.85–33.85 → 30.27–31.65
ms**. Its one-to-eight-core speedup remains approximately **1.32×**; this is a
latency improvement, not a multicore-scaling breakthrough. Shared-frontier
diamonds improve **3.9%** at eight cores. Reader's one-core median regresses
**3.1%**, and Chain's eight-core median regresses **2.0%**; both have
overlapping ranges. Reader also contains a 21.40 ms candidate outlier. No claim
is made that all small workloads improve.
[Selected warm-edit measurements](../build/cpu-output-grouped.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-output-grouped.json build/cpu-before-chunked-output-VZNk3h,. 5 1,8 balanced_64,reader_64,shared_frontier_diamonds_8,chain_64 incremental
```

The selected source passes **494 compiler tests**, the proof and native
ownership build gates, entrypoint/build-script type checks, and formatting/diff
checks. New tests cover exact protocol bytes at one/eight cores, padding across
arbitrary chunk boundaries and grains, zero grain, invalid bytes, incorrect
byte-plan lengths, and response-size/error precedence. Existing tests cover
session rollback, mixed cache hits, examples, large arrays, and codegen at one,
two, four, and eight threads.

### Selected implementation: clean compilation

Three paired fresh-process samples with the same affinity, warmup, validation,
and desktop-noise caveats. Median milliseconds, **before → after**:

| Workload                   |    JS, one core | Native, one core | Native, eight cores |
| :------------------------- | --------------: | ---------------: | ------------------: |
| Balanced 64                | 909.58 → 910.07 |  429.78 → 389.39 |     125.52 → 126.20 |
| Reader 64                  | 171.05 → 167.80 |    47.52 → 48.66 |       37.25 → 36.26 |
| Shared-frontier diamonds 8 | 486.78 → 510.13 |  162.67 → 164.48 |     113.32 → 106.15 |

Shared-frontier diamonds improve **6.3%** at eight cores, with nonoverlapping
sample ranges (**110.03–122.18 → 103.46–108.68 ms**). Balanced's eight-core
median is effectively unchanged (**+0.5%**); its one-core median improves
**9.4%**, but the ranges overlap. Reader regresses **2.4%** at one core and
improves **2.7%** at eight. Shared-frontier diamonds regress **1.1%** at one
core. These are mixed results, not evidence of a universal clean-compilation
win.

Selected native one-to-eight-core clean speedups are **3.09×** for Balanced,
**1.34×** for Reader, and **1.55×** for shared-frontier diamonds. Native at
eight cores is **7.21×**, **4.63×**, and **4.81×** faster than JS, respectively;
backend differences contribute to those ratios as well as parallel execution.
[Selected clean measurements](../build/cpu-output-grouped-clean.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-output-grouped-clean.json build/cpu-before-chunked-output-VZNk3h,. 3 1,8 balanced_64,reader_64,shared_frontier_diamonds_8 full
```

### Baseline profile and rejected packing strategies

A fresh diagnostic trace of the selected baseline again identifies output
encoding as substantial serial work. One sampled Balanced warm edit at eight
cores measured **7.43 ms wall / 7.41 ms native CPU** in response encoding,
versus **4.98 / 14.73 ms** in inference and **2.66 / 4.46 ms** in linking. The
final native buffer copy measured about **0.09 ms**. These `clang -O2`
instrumented intervals are exploratory samples, not production `-O3` timings.
[Baseline trace run](../build/cpu-output-before-phases.json).

The first prototype retained the Wasm byte plan and packed independent groups,
but repeatedly split the chunk list with a 128-chunk grain and constructed a
validation result per byte. Balanced contains **48,881 bytes in 16,915 chunks**;
that policy creates many small tasks. Three paired warm-edit samples measured
Balanced at eight cores **32.57 → 33.05 ms**, Reader **13.39 → 13.81 ms**,
shared-frontier diamonds **28.56 → 28.97 ms**, and Chain **11.79 → 12.46 ms**.
The trace measured packing at **8.63 ms wall / 11.90 ms CPU**, worse than the
baseline's serial encoding despite doing some work concurrently. This version is
not retained; its source and binaries are saved in
`build/cpu-output-first-prototype-fdw2ox`.
[First prototype](../build/cpu-output-candidate.json),
[first prototype trace](../build/cpu-output-candidate-phases.json).

A second prototype used a 2,048-chunk grain, consuming partitions, and an
allocation-free per-byte validity flag. Five paired samples measured Balanced
**33.31 → 31.54 ms**, Reader **13.77 → 13.17 ms**, shared-frontier diamonds
**28.65 → 29.31 ms**, and Chain **12.21 → 12.62 ms**, all at eight cores. Its
packing trace still showed only **7.15 ms wall / 7.90 ms CPU**. It is preserved
in `build/cpu-output-coarse-prototype-koaMHz` for comparison with the one-pass
grouped implementation. [Coarse prototype](../build/cpu-output-coarse.json),
[coarse prototype trace](../build/cpu-output-coarse-phases.json).

### Output representation

The native path preserves `Wasm.BytePlan` through compilation and linking. It
groups the outer chunk list once into coarse 2,048-chunk tasks and uses the
existing balanced batch executor to pack bytes. Small inputs stay sequential;
one indivisible large chunk is not split. This estimates work by chunk count,
not exact byte weight, so unusually uneven chunks can still limit balance.

Each block carries its exact byte length. The native writer copies packed words
into one exactly sized buffer, removes intermediate block padding, and pads only
the complete response. It validates internal lengths before writing any frame
bytes. The pure encoder checks the response allowance and byte values before
publishing candidate session state. Oversized output retains the old encoder's
error ordering through an exceptional fallback; successful native output never
flattens the complete Wasm byte list. The JS API still returns the same flat
artifact, and the wire format remains protocol version 7.

### Selected profile and remaining limits

A sampled Balanced warm edit in the final diagnostic trace measured **1.87 ms
wall / 3.47 ms CPU** in linking, **0.09 / 0.09 ms** preparing the response
header, and **6.00 / 6.88 ms** from entering chunk packing to the native send.
The corresponding baseline intervals were **2.66 / 4.46 ms** in linking and
**7.43 / 7.41 ms** in response encoding. The final buffer copy remained about
**0.09 ms**. One-core final packing measured **6.43 / 6.40 ms**. These are
separate exploratory samples, not a controlled microbenchmark or a promise that
all the removed serial work became parallel work.
[Selected trace run](../build/cpu-output-grouped-phases.json).

The CPU/wall ratio in output preparation remains low. Chunk grouping, section
planning, analysis encoding, ordered result collection, and the native copy
still include serial work; coarse packing does not keep eight cores busy
throughout this interval. The observed improvement is primarily lower overall
latency, not materially better whole-compiler scaling. Canonical metadata,
reachability, true dependency joins, and single-miss warm edits remain limits.
No fully dependency-ready scheduler or persistent output-delta protocol was
introduced in this pass.

## Nominal summaries, parallel relocation, and shared frontiers (2026-09-21)

This pass compares against the complete preceding uncommitted state, frozen in
`build/cpu-before-metadata-link-SDA6qt`. Both production binaries use the pinned
Bend 2.0.21. No upstream memory repair or language change is included.

1. **Reuse nominal metadata selectively.** Sessions averaging at least 256
   cached lowering-work units per declaration retain nominal-usage summaries.
   Changed declarations refresh in 512-unit weighted batches. An exact
   type-catalog key invalidates summaries on constructor changes, including
   moving a constructor between existing types without renaming it. Small
   modules use direct analysis and discard retained summaries. Whole-module
   validation and original diagnostic ordering remain intact. Prelude scans,
   canonical keys, and reachability are not cached by this change.
2. **Parallelize relocation.** Independent function bodies resolve against one
   immutable symbol catalog in weighted batches. The 256-unit grain weights raw
   byte chunks at one unit and symbolic relocations at eight, without walking
   every byte just to estimate work. Ordered collection preserves the original
   body order and name/relocation/count error precedence. Final Wasm assembly
   and response encoding are still serial.
3. **Release shared frontiers.** A connected graph with multiple initial roots
   can split into independent regions after those roots complete. This is used
   only when pending chains span further frontiers. Already-independent regions
   retain their separate schedules, and a final single frontier keeps its
   efficient batch. Actual dependency joins and recursive groups remain intact.
   This extends static scheduling; it is not a general dependency-ready queue or
   work-stealing implementation.

### Profiling and the rejected scheduler candidate

A separate instrumented, `clang -O2` trace of a warm Balanced edit at eight
cores measured 5.29 ms wall / 16.08 ms native CPU in inference, versus 5.74 ms
wall / 5.73 ms CPU in dependency-plan preparation, 3.10 / 3.08 ms in linking,
and 7.88 / 7.84 ms in response encoding. These are exploratory single-sample
phase intervals, not isolated function microbenchmarks or production timings.
They show meaningful serial work outside inference; they do not prove that
barrier waiting dominates.
[Trace run](../build/cpu-metadata-before-phases.json).

The first scheduler candidate split even a final frontier into independent
regions. Three paired samples exposed a Reader regression: **11.12 → 22.33 ms**
at one core and **14.09 → 25.90 ms** at eight. A follow-up trace localized it to
inference: one-core native CPU rose from 2.43 to 12.61 ms; eight-core wall time
rose from 2.42 to 12.90 ms. Linking and encoding stayed nearly unchanged. The
final policy preserves the last frontier's batch instead of constructing many
tiny region executions. A planner regression test enforces that choice.
[Rejected candidate](../build/cpu-metadata-link-candidate.json),
[Reader baseline trace](../build/cpu-reader-before-phases.json),
[Reader candidate trace](../build/cpu-reader-candidate-phases.json).

The first combined metadata-cache candidate also regressed small bodies. Three
interleaved eight-core control samples compared the baseline, that candidate,
the changes without metadata caching, and the changes without parallel linking.
Reader measured **14.21 / 15.26 / 13.80 / 15.55 ms** respectively; Chain
measured **12.56 / 15.09 / 12.27 / 15.31 ms**. Disabling the metadata changes
removed the small-workload regression; disabling parallel linking did not.
Balanced still benefited from metadata reuse. A size-based gate using cached
lowering estimates, and a subsequent restoration of the uncached planner's
original traversal, did not remove the regression. A subsequent prelude-only
cache also reproduced it. Finally, removing just the prelude-cache wrapper from
the selective nominal-cache implementation eliminated the small-body regression
in a targeted control. The selected implementation therefore retains **selective
nominal caching, not prelude caching**. The controls isolate the problematic
change set, not a proven low-level allocator or code-generation mechanism. The
combined prototype is preserved in `build/cpu-nominal-cache-prototype-KFhk76`.
[Component controls](../build/cpu-metadata-link-controls.json),
[size-gate experiment](../build/cpu-nominal-policy-256.json),
[original-traversal experiment](../build/cpu-nominal-direct-control.json),
[rejected unconditional-summary measurements](../build/cpu-metadata-link-final.json).

Three interleaved eight-core samples compared baseline / parallel linking and
shared-frontier scheduling without metadata caching / the selected nominal-only
cache. Reader measured **13.64 / 13.66 / 13.93 ms**; Chain measured **12.08 /
12.24 / 12.00 ms**; Balanced measured **39.37 / 38.77 / 33.30 ms**. The selected
source is preserved in `build/cpu-nominals-without-prelude-k6O40E`. Reports with
earlier `final` filenames are rejected candidates, not the selected
implementation.
[Nominal-only control](../build/cpu-nominal-without-prelude-control.json),
[rejected prelude-only measurements](../build/cpu-frontier-link-final.json).

### Selected-build verification and measurement method

The selected native binary was compiled with pinned Bend 2.0.21 and `clang -O3`;
all 39 compiler Bend/C/JS input files were compared byte-for-byte with the
selected control before promoting its binary. JS artifacts were rebuilt from
that source. The proof/build gate passes, TypeScript entrypoints check, and the
full compiler suite passes **491 tests**. New coverage includes nominal
constructor moves, crossing the cache-policy threshold, failures and recovery,
ordered link errors, shared-root scheduling, and native/JS artifact parity.

Final measurements use five interleaved fresh-process samples for warm edits and
three for clean compilation, with two warmups per sample. The host and native
child share affinity to one or eight physical Ryzen 7 7800X3D cores. Artifact
checks and execution run outside the timed interval; native samples do not
import the JS compiler. Startup is excluded. No compiler build, test, or second
benchmark runs concurrently, but desktop applications remain active. This is not
an isolated-machine result. Cores two through seven are not remeasured in this
pass. The known retained-native memory issue is unchanged and is not subtracted
from the measurements.

### Selected-build warm edits

Median of the five sample medians, milliseconds **before → after**:

| Workload                   | Native, one core | Native, eight cores | Eight-core latency change |
| :------------------------- | ---------------: | ------------------: | ------------------------: |
| Balanced 64                |    53.52 → 53.35 |       44.89 → 37.27 |                    −17.0% |
| Reader 64                  |    13.62 → 13.51 |       15.44 → 14.92 |                     −3.4% |
| Diamonds 8                 |    38.04 → 37.82 |       33.55 → 31.13 |                     −7.2% |
| Shared-root diamonds 8     |    39.73 → 38.73 |       34.25 → 32.87 |                     −4.0% |
| Shared-frontier diamonds 8 |    38.35 → 33.70 |       39.68 → 28.41 |                    −28.4% |
| Clustered 64               |    17.80 → 16.96 |       20.17 → 17.44 |                    −13.5% |
| Chain 64                   |      6.02 → 5.92 |       12.11 → 12.68 |                     +4.7% |

Balanced's one-to-eight-core speedup rises from **1.19× to 1.43×**. This is
better, but still far from linear. Shared-frontier diamonds improve most at
eight cores, with nonoverlapping sample ranges (**38.53–46.26 → 27.34–30.56
ms**). Balanced also has nonoverlapping eight-core ranges (**44.38–47.24 →
36.77–38.00 ms**). Reader and Chain have overlapping ranges; Chain's median
regresses by 0.57 ms, and it remains much faster on one core. Small and serial
workloads do not become faster merely by enabling more threads. These are
combined change measurements, not an isolated speedup claim for every component.
[Selected warm-edit report](../build/cpu-concurrency-verified.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-concurrency-verified.json build/cpu-before-metadata-link-SDA6qt,. 5 1,8 balanced_64,reader_64,diamonds_8,shared_root_diamonds_8,shared_frontier_diamonds_8,clustered_64,chain_64 incremental
```

### Selected-build clean compilation

Median of three sample medians, milliseconds **before → after**:

| Workload                   |     JS, one core | Native, one core | Native, eight cores |
| :------------------------- | ---------------: | ---------------: | ------------------: |
| Balanced 64                | 1038.64 → 988.95 |  403.14 → 444.44 |     140.28 → 144.08 |
| Reader 64                  |  154.57 → 163.17 |    46.14 → 46.00 |       38.93 → 37.11 |
| Shared-frontier diamonds 8 |  489.60 → 485.36 |  184.61 → 152.91 |     124.74 → 110.14 |

Shared-frontier diamonds improve **11.7%** at eight cores; sample ranges do not
overlap (**123.39–125.32 → 108.95–115.89 ms**). Balanced regresses **10.2%** at
one core and **2.7%** at eight cores; Reader's eight-core median improves
**4.7%**. These latter comparisons have overlapping ranges. The selected changes
are not an across-the-board clean-compilation win, and the one-core Balanced
regression remains a limitation rather than a resolved issue.

On the selected build, native eight-core clean compilation is **6.86× faster
than JS** for Balanced, **4.40×** for Reader, and **4.41×** for shared-frontier
diamonds. Native one-to-eight-core scaling is **3.08×**, **1.24×**, and
**1.39×**, respectively. JS/native speed ratios include backend differences, not
just parallelism. Nominal-summary retention affects retained sessions, not this
stateless path; linking and scheduling changes affect both.
[Selected clean report](../build/cpu-concurrency-verified-clean.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-concurrency-verified-clean.json build/cpu-before-metadata-link-SDA6qt,. 3 1,8 balanced_64,reader_64,shared_frontier_diamonds_8 full
```

### Remaining limits

This is not maximum possible concurrency. Lexing, canonical-key preparation,
reachability, ordered publication, final Wasm assembly, and response encoding
still include serial work. Constants share a sequential fuel budget; recursive
groups and real dependency joins cannot simply be split. Shared-frontier release
is a bounded static scheduling improvement, not a fully dynamic ready queue.

## Lazy origins, codegen pipelining, and shared-root regions (2026-09-21)

This pass starts from the previously uncommitted worktree, frozen in
`build/cpu-before-serial-pipeline-gwXohO`. No allocator or upstream Bend repair
is included.

1. **Reduce serial host work.** Diagnostic origins retain immutable,
   declaration-local identity-to-token tables. At 8,192 total origin entries,
   the frontend switches from eager indexing to on-demand offset lookup, so a
   successful warm edit does not rebuild a map for every reused syntax node.
   Named-declaration offsets are also looked up only when needed. Saved
   diagnostics preserve the original revision, including after disposal.
2. **Pipeline codegen.** For jobs averaging at least 256 estimated work units,
   each worker serializes its key, selects a cache hit, and compiles its miss
   without waiting for other workers' keys. The existing 512-unit batch grain
   remains. Cheap jobs keep staged preparation and balanced miss checking.
   Ordered publication preserves first-error precedence, entry order, cache
   counts, eviction, and success-only cache publication.
3. **Release branches after a shared root.** The planner removes dependencies
   satisfied by the completed shared root from the remaining region graph.
   Independent branches can then advance through their own frontiers. Edges
   between unfinished branches still connect their regions; genuine joins and
   indivisible recursive groups remain. Clean and incremental paths share this
   planner, and retained sessions cache its result. This is a bounded extension
   of fork/join scheduling, not a general dependency-ready queue or work
   stealing.

### Rejected unconditional origin policy

Always using lazy origins reduced large-module latency but regressed short
Clustered sessions: the five-pair run measured **17.39 → 26.26 ms** at one core.
A separate control using the _same old native binary for both hosts_ reproduced
the regression, isolating it to the host change rather than native codegen. Two
longer 40-edit controls improved after warmup, but that does not excuse the
short-session regression. No claim is made that GC or JIT was its proven cause.
The final size-based policy retains eager small-origin indexing; a three-pair
targeted check measured **20.07 → 19.72 ms** for Clustered at one core and
**20.70 → 20.76 ms** at eight cores.

[Initial candidate](../build/cpu-serial-pipeline-candidate.json),
[seven-pair Clustered confirmation](../build/cpu-serial-pipeline-cluster-confirm.json),
[same-binary host control](../build/cpu-serial-host-control.json),
[unconditional five-pair measurements](../build/cpu-serial-pipeline-final.json),
[unconditional retained control](../build/cpu-serial-retained-control.json),
[small-origin policy check](../build/cpu-origin-policy.json).

### Clean compilation

Three interleaved fresh-process samples, two warmups, shared host/child affinity
on one/eight physical Ryzen 7 7800X3D cores. Every artifact matches the JS
oracle and executes. Startup and validation are excluded. No other test, build,
or benchmark ran concurrently, but desktop applications remained active; this is
not an isolated-machine measurement. The native changes are identical to the
final implementation; the later incremental-origin policy does not run on this
stateless path.

Median milliseconds, **before → after**:

| Workload               |    JS, one core | Native, one core | Native, eight cores |
| :--------------------- | --------------: | ---------------: | ------------------: |
| Balanced 64            | 845.59 → 862.09 |  416.46 → 385.40 |     129.33 → 130.86 |
| Reader 64              | 145.81 → 150.34 |    35.29 → 38.17 |       34.17 → 34.70 |
| Shared-root diamonds 8 | 472.39 → 438.37 |  156.75 → 141.20 |     111.66 → 101.35 |

Shared-root diamonds improve **9.2%** at eight cores. Balanced and Reader show
mixed changes with overlapping sample ranges; these results do not establish an
across-the-board clean-compilation improvement.
[Clean compilation report](../build/cpu-serial-pipeline-clean.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-serial-pipeline-clean.json build/cpu-before-serial-pipeline-gwXohO,. 3 1,8 balanced_64,reader_64,shared_root_diamonds_8 full
```

### Final warm-edit measurements

Five interleaved fresh-process samples per variant, two warmups, with the same
affinity and desktop caveats as the clean run. Timings include frontend,
transport, native compilation, and response decoding; process startup and
artifact validation are excluded. Each edit matches the clean JS Wasm and
function-signature oracle and executes; unchanged replies match the preceding
complete artifact. These are the final size-based origin policy, codegen
pipeline, and shared-root scheduler together, not isolated per-change effects.

Median milliseconds, **before → after**:

| Workload               | Native, one core | Native, eight cores |
| :--------------------- | ---------------: | ------------------: |
| Balanced 64            |    59.65 → 49.84 |       52.23 → 44.81 |
| Reader 64              |    13.24 → 12.58 |       14.73 → 14.86 |
| Diamonds 8             |    47.03 → 37.85 |       35.48 → 33.23 |
| Shared-root diamonds 8 |    54.88 → 38.35 |       46.55 → 34.38 |
| Clustered 64           |    21.72 → 21.89 |       21.23 → 21.73 |
| Chain 64               |      7.41 → 7.90 |       14.96 → 14.30 |

Eight-core edits improve **14.2%** for Balanced, **6.3%** for Diamonds, and
**26.1%** for shared-root diamonds. Small-workload results remain mixed:
Clustered is 0.8% slower at one core and 2.4% slower at eight, Reader is 0.9%
slower at eight, and Chain is 6.7% slower at one core in this run. The large
one-core Clustered regression from unconditional lazy origins is gone, but there
is no demonstrated universal speedup. Balanced's eight-core frontend median
drops **9.73 → 4.85 ms**; its end-to-end one-to-eight-core speedup is still only
**1.11×**, so lower latency does not imply linear core scaling.
[Final warm-edit report](../build/cpu-concurrency-final.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-concurrency-final.json build/cpu-before-serial-pipeline-gwXohO,. 5 1,8 balanced_64,reader_64,diamonds_8,shared_root_diamonds_8,clustered_64,chain_64 incremental
```

Two retained Clustered controls per variant alternate 40 edits after the first
two requests, reversing variant order on the second run and checking complete
artifact equality for every revision. Last-20 medians are **25.12–25.92 →
22.78–23.40 ms** at one core and **23.62–23.83 → 23.08–23.26 ms** at eight.
These longer sessions do not reproduce the short-run Clustered regression, but
are separate diagnostics, not replacements for the fresh-process table above.
[Final retained control](../build/cpu-concurrency-retained.json),
[control script](../build/serial-latency-control.ts).

```sh
deno run --allow-all build/serial-latency-control.ts build/cpu-concurrency-retained.json
```

### Verification and remaining limits

The final implementation passes **483 compiler tests**, including native/JS
artifact parity, one/eight-worker edits and rollback, cached/mixed/reordered
codegen results, key-versus-compilation failure ordering, shared-root aliases,
real downstream joins, unknown-dependency rejection, and large lazy diagnostic
tables retaining offsets across revisions and disposal. The Bend proof gate,
native ownership regression, native/JS builds, formatting, and diff checks pass.
Builds use the repository-pinned **Bend 2.0.21**, unpacked separately after
verifying the official release digest; the globally installed 2.0.24 was not
changed. Both benchmark variants use 2.0.21.

Serial lexing, nominal-usage analysis, prelude scans, reachability, canonical
key construction, ordered publication, linking, response encoding, and host
assembly still contain work. Const evaluation keeps its shared fuel budget.
Dependency chains and actual joins cannot be made independent by this change;
more general dependency-ready scheduling remains future work. One session still
owns an ordered request stream. Memory behavior was not repaired or subtracted
from these measurements, and only one/eight-core endpoints were remeasured.

## Cached scans and selective inference pipelining (2026-09-21)

This implements the next three work areas against the preceding uncommitted
state, frozen in `build/cpu-before-pipeline-T4Tqa8`. Comparisons in this section
use that baseline, not `ceb1444` or the older snapshots below.

1. **Reduce repeated work.** Reused lowered source declarations retain their
   dependency/lambda scans and scheduling cost estimates. Changed declarations
   recompute those summaries in their lowering worker. The cache has the same
   source, scope, fuel, eviction, and success-only publication rules as
   lowering. Whole-module validation still checks types, operations, names, and
   duplicate lambda identities every revision. Scan errors remain values until
   their original diagnostic phase; functions still precede constants.
2. **Overlap independent stages.** Within sufficiently substantial frontiers,
   each worker prepares a group's key and immediately checks its cache miss.
   Checking no longer waits for all other workers to finish key preparation.
   Workers read one immutable frontier snapshot, and ordered publication keeps
   cache counts, interface dependencies, and first-error selection unchanged.
3. **Improve scheduling.** Singleton chains bypass batch construction. Small
   frontiers and cheap jobs retain staged preparation followed by balanced miss
   checking. Broad frontiers pipeline only when average estimated group cost is
   at least 256 units. Cold pipelines use the existing 128-unit inference grain;
   sessions with prior caches use a 2,048-unit grain. Cached declaration costs
   also avoid repeated body walks when weighting chains and regions. Missing
   estimates fall back to the original traversal; cost never changes validation
   fuel, and recursive groups remain indivisible.

The threshold is based on workload estimates, not benchmark names. Reader's
frontiers average about 223 and 216 units per group; Balanced averages 5,232 and
Clustered 1,312. Source-group costs compose exactly for ordinary unsaturated
groups. Per-declaration saturation can overestimate a large recursive group,
which affects scheduling only.

### Candidates retained for comparison

Caching dependency scans alone produced modest one-core changes and little
eight-core benefit. An unconditional 512-grain pipeline improved Clustered
eight-core edits from 21.00 to 19.34 ms, but regressed Reader from 13.34 to
15.98 ms. Coarser warm batching and cost caching alone still regressed Reader
(13.35 to 15.27 ms). Neither unconditional pipeline is the final policy.
[Scan-only measurements](../build/cpu-cached-scans.json),
[512-grain candidate](../build/cpu-pipeline-candidate.json),
[cost-cache/coarse candidate](../build/cpu-pipeline-costs.json).

### Final paired incremental measurements

Five interleaved fresh-process samples, two warmups, shared host/child affinity
on one or eight physical cores of the Ryzen 7 7800X3D. No builds, tests, or
other benchmarks ran concurrently. Unity and browser applications remained
active, so this is not an isolated-machine result. Every artifact matches the
clean JS Wasm/signature oracle and executes; unchanged replies retain full
parity. Timings include the frontend and transport, but exclude process startup
and artifact validation.

Warm body-edit medians, milliseconds, **before → after**:

| Workload     | Native, one core | Native, eight cores |
| :----------- | ---------------: | ------------------: |
| Balanced 64  |    62.80 → 65.58 |       55.16 → 53.12 |
| Reader 64    |    14.09 → 14.07 |       15.06 → 15.38 |
| Diamonds 8   |    50.59 → 50.18 |       36.61 → 36.09 |
| Clustered 64 |    22.19 → 21.71 |       23.06 → 21.37 |
| Chain 64     |      6.95 → 7.02 |       14.45 → 14.52 |

Eight-core Balanced improves **3.7%** and Clustered **7.3%**. Reader's earlier
pipeline regression is reduced to **2.2%**, not turned into a demonstrated win.
Diamonds and Chain are approximately unchanged. One-core Balanced regresses
**4.4%** in this run; its samples span 61.46–68.20 ms before and 59.38–70.74 ms
after, so the busy-desktop control does not establish the size of that effect
confidently. These results are mixed, not an across-the-board improvement.

First session compilation at eight cores changes from 377.00 to 371.31 ms for
Balanced, 62.25 to 61.35 ms for Reader, 211.80 to 207.90 ms for Diamonds, 117.68
to 117.50 ms for Clustered, and 34.95 to 33.22 ms for Chain. Startup is
excluded. This pass samples the one/eight-core endpoints, not all intervening
core counts. [Final incremental report](../build/cpu-pipeline-final.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-pipeline-final.json build/cpu-before-pipeline-T4Tqa8,. 5 1,8 balanced_64,reader_64,diamonds_8,clustered_64,chain_64 incremental
```

### Clean-compilation guard

Three paired fresh-process samples with two warmups also checked stateless
compilation. These include shared planning refactors, but do not exercise the
retained-session pipeline. The same non-isolated desktop and parity checks
apply. Medians in milliseconds, **before → after**:

| Workload    |    JS, one core | Native, one core | Native, eight cores |
| :---------- | --------------: | ---------------: | ------------------: |
| Balanced 64 | 954.19 → 994.33 |  478.50 → 427.65 |     138.23 → 136.61 |
| Reader 64   | 165.08 → 179.93 |    40.54 → 42.26 |       39.87 → 39.73 |
| Diamonds 8  | 476.59 → 531.52 |  174.20 → 168.95 |     115.51 → 111.04 |

[Clean-compilation samples](../build/cpu-pipeline-clean.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-pipeline-clean.json build/cpu-before-pipeline-T4Tqa8,. 3 1,8 balanced_64,reader_64,diamonds_8 full
```

The apparent JS slowdowns prompted a separate five-pair confirmation, pinned to
CPU 0, alternating variant order, with two warmups and artifact parity. Balanced
measured **922.32 → 915.46 ms**, Reader **167.73 → 168.98 ms**, and Diamonds
**508.67 → 471.49 ms**. The earlier slowdowns did not reproduce; neither run
establishes a stable JS improvement or regression on this busy desktop.
[JS confirmation samples](../build/cpu-pipeline-js-confirm.json).

### Retained-session control

Two 200-edit runs per variant alternated Balanced 64 revisions in
baseline/new/new/baseline order, on eight pinned cores. Every full artifact for
each revision matched, as did Wasm hashes across variants. Timing includes the
public incremental API; validation and RSS sampling are outside timing, with no
forced GC.

Median latency after the first two requests improves from **75.32–76.49 ms** to
**71.90–72.44 ms**. Last-20-request medians are **76.40–79.41 ms** before and
**74.30–76.79 ms** after. The overall improvement is approximately 5%, but
long-lived sessions still run slower than fresh-process warm edits.

Native RSS starts near **46–47 MiB** and ends at **174.07–174.18 MiB** before
versus **176.96–178.80 MiB** after. Both continue to grow by roughly 54–56 MiB
between requests 100 and 200; the new cache/pipeline has not fixed this and has
a small additional residency cost. Host RSS at request 200 is 342–355 MiB before
and approximately 341 MiB after; ordinary GC variation prevents a strong
host-memory conclusion. No allocator change was made.
[Retained latency and memory samples](../build/incremental-pipeline-memory.json).

### Verification and remaining limits

Native and JS builds, the ownership gate, and `bend PROOF.bend` pass. The full
test suite passes **478 tests**. New tests cover cached/uncached dependency
planning equivalence, global and function-before-constant error precedence,
duplicate lambda identities across fragments, cached scheduling costs and
fallback, cost-based frontier routing, and staged/pipelined result equivalence.

Nominal-usage analysis, prelude scans, canonical key construction, reachability,
ordered publication, response encoding, and host assembly still contain serial
work. Real dependency joins and codegen planning barriers remain. This is
selective pipelining within the existing fork/join runtime, not work stealing or
a general dependency-ready queue, and it does not exhaust the remaining work.

## Parallel incremental cache preparation (2026-09-21)

This pass starts from the preceding uncommitted improvements, frozen in
`build/cpu-before-cache-phases-ckM7cZ`. That is a different baseline from
`ceb1444` and the historical comparisons below.

### Diagnosis and changes

Instrumented Balanced 64 warm body edits showed substantial serial cache work
even though only one group and one codegen entry missed their caches. Three
fresh-process samples after two warmups gave these median native phase times:

| Baseline phase                          | One core | Eight cores |
| :-------------------------------------- | -------: | ----------: |
| Inference/cache preparation and publish | 12.40 ms |    21.00 ms |
| Codegen key construction and selection  |  7.21 ms |     9.70 ms |
| Actual codegen for the miss             |  0.57 ms |     0.87 ms |

CPU time approximately equaled wall time in the cache phases. Parallel
projection, by contrast, used 4.09 ms of CPU in 1.68 ms wall time at eight
cores. These are instrumented diagnostic intervals, not production headline
timings. The multiworker runtime took longer on serial work; this does not
isolate atomic operations as the cause.
[Baseline phase summary](../build/cache-phase-events/summary.json).

Inference-key preparation and codegen-key serialization now use the existing
cost-balanced batch executor. Each inference task reads the same immutable
frontier snapshot. Results are consumed in source order, and publication still
requires a successful request. Canonical keys, dependency invalidation, resource
limits, and diagnostic precedence are unchanged. An earlier codegen failure
still wins over a later key-encoding failure.

Frontiers of four or fewer groups skip AST cost estimation and do not fork. An
initial version without this cutoff regressed eight-core Diamonds edits from
34.58 to 38.14 ms; the final version does not show a consistent Diamonds change.
The [initial measurements](../build/cpu-parallel-cache.json) are retained rather
than silently discarded. No allocator intervention was promoted.

### Paired production measurements

Five interleaved fresh-process samples per variant, two warmups, Ryzen 7
7800X3D, host and child sharing one/eight physical-core affinity. No builds,
tests, or other benchmarks ran concurrently, but the desktop was not isolated:
Unity and browser applications remained active. Startup and parity checks are
outside timing. Every incremental Wasm/signature result matches a clean JS
artifact and executes; unchanged replies match the preceding full artifact.

Warm body-edit medians, **before → after**:

| Workload    | Native, one core | Native, eight cores |
| :---------- | ---------------: | ------------------: |
| Balanced 64 |    57.15 → 57.15 |       77.68 → 53.13 |
| Reader 64   |    12.88 → 21.86 |       18.51 → 14.82 |
| Diamonds 8  |    45.09 → 45.20 |       35.97 → 36.72 |

Eight-core Balanced improves **31.6%** and Reader **19.9%**. Balanced's
one-to-eight-core edit speedup changes from **0.74× to 1.08×**: a reversal of
negative scaling, but still far from good eight-core utilization. Diamonds is
effectively unchanged. First session compilation at eight cores changes from
385.11 to 362.89 ms (Balanced), 61.68 to 59.60 ms (Reader), and 208.07 to 199.99
ms (Diamonds). These first-request numbers exclude native process startup.
[Final paired report](../build/cpu-parallel-cache-final.json).

A targeted eleven-sample follow-up confirms Reader's eight-core improvement
(16.94 → 13.64 ms) and no clear Diamonds change (32.82 → 32.49 ms). It also
repeats the one-core Reader short-run regression (12.16 → 23.99 ms), which must
not be hidden. [Follow-up samples](../build/cpu-parallel-cache-confirm.json).

A separate diagnostic of the same short benchmark, reading Linux `schedstat`
around native requests, caught baseline spikes with **10.56–14.85 ms waiting
runnable on the CPU**, while native CPU work stayed at **8.55–9.25 ms**. The new
variant used 8.78–8.97 ms of native CPU in that probe. In two longer 40-edit
runs per variant, one-core Reader medians were 11.18–11.20 ms before and
11.41–11.65 ms after. These diagnostics show substantial scheduling
interference, not proof that every production outlier has that cause. The
one-core Reader end-to-end effect remains uncertain; small scheduling/key
planning overhead is still present.
[Short-run scheduler probe](../build/reader-sample-probe.json),
[longer Reader probe](../build/reader-latency-probe.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-parallel-cache-final.json build/cpu-before-cache-phases-ckM7cZ,. 5 1,8 balanced_64,reader_64,diamonds_8 incremental
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-parallel-cache-confirm.json build/cpu-before-cache-phases-ckM7cZ,. 11 1,8 reader_64,diamonds_8 incremental
```

This pass changes the native incremental path. It does not remeasure stateless
JS/native clean compilation or all intermediate core counts; the historical
tables below are not measurements of this new incremental implementation.

### Real editing sessions expose larger retained-memory growth

Two 200-edit runs per variant, ordered baseline/new/new/baseline, alternated the
two Balanced 64 source revisions through the public incremental API on eight
pinned cores. Full artifacts for each revision were equal throughout, and Wasm
hashes matched across variants. Validation and RSS sampling are outside timing;
no forced GC ran.

Overall medians after the first two edits fell from **129.80–130.20 ms** to
**84.09–84.80 ms**. Last-20-edit medians were **129.45–150.22 ms** before and
**86.39–88.62 ms** after. This is a retained-session improvement, but latency
still exceeds the fresh-process warm measurements.

Native RSS rose from approximately **46 to 182 MiB** before and **47 to 175
MiB** after. Growth continued between edits 100 and 200, so neither variant
demonstrates a plateau. Host RSS at edit 200 ranged from 261–275 MiB before and
340–341 MiB after, with substantial GC-dependent variation during the runs. The
change has not demonstrated a host-memory improvement.
[Raw editing-session memory and latency](../build/incremental-memory-probe.json).

The earlier description of only "small residual" native growth applied to
repeated stateless/preencoded requests. It understates growth in actual
incremental editing sessions. These RSS observations do not distinguish live
cache retention from allocator residency; that requires further allocation
accounting. No claim of bounded long-lived session memory is justified yet.

### Verification and remaining limits

Native and JS targets build, including the native ownership regression gate. The
JS build also emits the pure native-session module for direct cache-planning
tests. All **473 compiler tests**, `bend PROOF.bend`, targeted TypeScript
checks, formatting, and diff whitespace checks pass. New tests cover uneven
batch equivalence, empty/small frontiers, failure eligibility, stable ordering,
and earlier-codegen-versus-later-key diagnostic precedence.

Dependency joins remain, as do serial planning, reachability, ordered cache
publication, response encoding, and parts of host assembly. Long-lived latency
and memory residency remain important unresolved problems. Parallelism is not
maximized, and additional forks alone will not address all of these limits.

## Follow-up to `ceb1444` (2026-09-21)

The preceding complete worktree was committed as `ceb1444`. This follow-up uses
the frozen `build/cpu-before-ceb1444-Ciqs7c` snapshot of that commit as its
baseline; it does not compare with the older controls below.

Implemented:

- Region partitioning uses union by rank and path compression instead of
  constructing a symmetric graph, running two SCC traversals, and re-sorting
  components. It preserves existing chain order, dependency closure, and
  source-position diagnostic selection. Self-links and already-compressed parent
  links do not rewrite the forest.
- Incremental edits reuse validated lex/layout fragments from the previous
  syntactically valid revision. Token fingerprints still allow CST reuse across
  trivia edits. Token-offset indexes are constructed only when a fragment needs
  parsing. The first edit warms this cache; ambiguous or rejected fragments use
  the whole-file parser for canonical diagnostics. Removed fragments are
  evicted, and failed edits do not publish partial caches.
- Compact encoding no longer copies each fragment's complete source-offset array
  through an obsolete range-encoding path. Dictionary packing and final
  source-origin assembly still have serial work.

### Final paired compilation control

Five fresh-process samples per configuration after two warmups, with baseline
and new variants interleaved and CPU affinity shared by host and child. Native
settings use one or eight physical cores; JS is single-core. The Ryzen 7 7800X3D
desktop was not otherwise isolated (Unity and browser applications were active),
but no builds, tests, or other benchmarks ran concurrently. Startup and parity
checks are excluded. Every clean artifact matches JS and executes; incremental
artifacts match clean Wasm and signatures, with unchanged-revision parity too.

Median milliseconds, **before → after**. Clean compilation:

| Workload    |    JS, one core | Native, one core | Native, eight cores |
| :---------- | --------------: | ---------------: | ------------------: |
| Reader 64   | 175.63 → 171.96 |    44.44 → 43.09 |       43.43 → 40.01 |
| Diamonds 8  | 551.36 → 493.36 |  180.73 → 178.47 |     115.71 → 109.79 |
| Balanced 64 | 998.18 → 958.13 |  459.28 → 460.95 |     138.94 → 137.36 |

Warm incremental body edits:

| Workload    | Native, one core | Native, eight cores |
| :---------- | ---------------: | ------------------: |
| Reader 64   |    17.87 → 13.19 |       21.10 → 18.55 |
| Diamonds 8  |   106.25 → 50.00 |       52.94 → 33.81 |
| Balanced 64 |   137.99 → 58.87 |      126.41 → 77.41 |

At eight cores, Reader clean compilation improves **7.9%** and Diamonds
**5.1%**; Balanced clean compilation is effectively unchanged. Warm edits
improve **12.1%, 36.1%, and 38.8%**, respectively. This is primarily less work,
not proof of better parallel scaling: Balanced clean one-to-eight-core speedup
is **3.36×**, and Reader/Balanced edits remain faster at one core than at eight.
This pass remeasures the one/eight-core endpoints, not every intervening core
count. Source and executable hashes and every sample are in the
[final paired report](../build/cpu-ceb1444-final.json).

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-ceb1444-final.json build/cpu-before-ceb1444-Ciqs7c,. 5 1,8 reader_64,diamonds_8,balanced_64 full,incremental
```

### Region-planner isolation

On the final planner, a one-core JS microbenchmark of the actual workload chain
graphs (20 warmups, 100 interleaved measurements per variant, identical
component membership checked every time) reduced Reader 64 partitioning from
**8.71 to 2.51 ms** and Diamonds 8 from **19.25 to 5.41 ms**, approximately
71–72%. Reader has 129 chains in one region; Diamonds has 200 chains in eight
regions. This isolates partitioning, not complete compilation or cold-JIT
behavior. [Raw partition probe](../build/region-planner-probe.json).

### Retained allocation: experiment rejected

A free-list locality prototype sorted only known-free blocks within each
existing lane/class/generation. Unlike the earlier global repacking experiment,
it preserved each list's membership and count, left live values and compiler
caches untouched, and unmapped its temporary scratch buffer. Maintenance ran
before sending the response, so request timings include its cost.

Two 200-request runs per executable, ordered
baseline/prototype/prototype/baseline, used identical preencoded Balanced 64
requests and eight pinned physical cores. Every decoded result matched. Overall
medians were noisy: baseline **74.57–84.82 ms**, prototype **77.94–78.70 ms**.
Late-session medians (last 20 requests) were consistently worse: baseline
**75.67–77.51 ms**, prototype **78.34–79.44 ms**. Final native RSS was
**47.53–47.64 MiB** versus **48.18–48.29 MiB**; both still stepped up by
approximately 2 MiB during the run. This does not demonstrate a
latency-and-memory win. The allocator prototype remains under ignored `build/`,
not in production. [Raw allocator comparison](../build/lane-sort-compare.json).

### Incremental frontend allocation probe

A separate one-core, frontend-only diagnostic alternated two Balanced 64
revisions for 102 preparations, in baseline/new/new/baseline order. Warm
frontend medians fell from **71.53–82.11 ms** to **7.65–8.01 ms**. Each warm
edit lexed **2,394 of 153,269 UTF-16 code units**, reusing the remaining
150,875, and parsed one of 64 declarations. These are frontend timings, not
total compile times.

Explicit GC ran outside timing at requests 0, 1, 2, 25, 50, and 100 to inspect
retained memory. Live JS heap at request 100 was approximately **54 MiB** in
both variants; host RSS was **482–574 MiB** before versus **297 MiB** after.
This diagnostic supports lower allocation churn, not a claim that ordinary
sessions use exactly these RSS values or that all host memory growth is solved.
[Raw frontend probe](../build/incremental-lex-probe.json).

### Verification and remaining limits

Both compiler targets rebuilt successfully, including the native constructor
ownership regression gate. `bend PROOF.bend`, all **470 compiler tests**,
`deno fmt --check`, and `git diff --check` pass. Tests cover region membership
on generated DAGs, source-order failures and rollback, native/JS artifacts, warm
fragment reuse, eviction, CRLF/reordering, and malformed-edit recovery.

This reduces serial work and scheduling overhead; it does not remove real
dependency joins or replace Bend's fork/join scheduler with a dynamic ready
queue. Source-boundary scans, origin remapping, dictionary packing, and final
assembly remain partly serial. The fragment cache has a first-edit warmup cost.
Native retained-process latency and residual RSS growth remain unresolved; no
allocator intervention was promoted. Small incremental requests can still be
slower at eight cores than at one. This is progress, not maximal parallelism.

## Raw-source workers, dependency regions, and executable examples (2026-09-21)

This pass uses `build/cpu-before-resolve-x13Mr9` as its baseline: the
immediately preceding uncommitted compact-frontend/queue-reset build, not
`2428902`.

Implemented:

- Large raw inputs use a conservative source-boundary scan, then lex, lay out,
  parse, and encode independently in the caller and up to three workers. The
  caller no longer lexes the complete input or transfers an offset array first.
  Rejected/ambiguous splits still use the canonical whole-file diagnostic.
- Final compact-word assembly uses bulk copies and rewrites only dictionary
  references. Byte order, source offsets, dictionary order, and fuel are
  unchanged.
- Independent dependency regions advance through their own frontiers. One
  region's join no longer blocks another region's ready successors. Regions are
  weakly connected components of the chain graph; real dependencies, SCCs, and
  joins within a region remain intact. Original job positions choose
  diagnostics; region-local cache deltas/counters publish only on successful
  requests. Plans with one frontier or one root bypass region partitioning.
- `examples/ecs.blot`, `syntax.blot`, and `host_capabilities.blot` are
  executable ports, not allowances for unsupported syntax. ECS storage, queries,
  insertion, system order, and immutable state threading are ordinary source
  functions. Host records stay inside the guest and use the current scalar
  callback ABI. `just study` runs the headless ECS demo, not the archived
  graphical sandbox.

### Paired controls

Five fresh-process samples after two warmups, medians in milliseconds, on the
Ryzen 7 7800X3D. The host and child share physical-core affinity. No build,
test, or second benchmark was run alongside these measurements. Other desktop
applications were active, including a CPU-active Unity editor; these are not
isolated-machine measurements. Every artifact is checked against JS and
executed. These measure compilation, not native versus JS execution of the ECS
simulation.

The frontend-only control (before adding regions) gives:

| Balanced 64, eight cores | Before |  After |
| :----------------------- | -----: | -----: |
| Full compilation         | 185.53 | 147.13 |
| Frontend                 |  93.25 |  57.85 |
| Dictionary/framing       |   6.35 |   2.55 |
| Native plus transport    |  84.22 |  84.06 |

End-to-end latency improves **20.7%**. Host RSS is effectively unchanged,
**526.22 → 525.52 MiB**: moving the lexer into each worker does not remove
isolate overhead. [Raw frontend control](../build/cpu-raw-frontend.json).

The initial region control gives **125.89 → 118.01 ms** for a clean eight-core
compile of eight staggered diamonds and **74.87 → 52.28 ms** for a body edit
(30.2% faster). Exactly one of 208 groups is rechecked on that edit; all other
interfaces are reused. One-core clean latency is **173.05 → 173.57 ms**. Reader
64 regressed **40.13 → 43.58 ms** at eight cores in this first control, which
motivated the single-root fast path. JS diamonds also regressed **467.63 →
503.92 ms**; this control does not establish a JS speedup, and cannot separate
planning overhead from desktop noise.
[Initial region controls](../build/cpu-regions.json).

The seven-sample Reader 64 repeat on the final build confirms the tradeoff:
**40.39 → 43.35 ms** native at eight cores (+7.3%) and **163.95 → 177.40 ms** JS
(+8.2%). This graph has 65 roots but one connected region, so the single-root
fast path cannot skip its partition analysis. It is an observed regression, not
a claimed fix. [Final Reader control](../build/cpu-single-root-control.json).

### Final build: one through eight cores

Balanced 64, three fresh-process samples per setting after two warmups, same
affinity and parity checks as above. JS remains single-core at **931.91 ms**.

| Native cores | Compile ms | Speedup vs native 1 | Speedup vs JS |
| -----------: | ---------: | ------------------: | ------------: |
|            1 |     425.42 |               1.00× |         2.19× |
|            2 |     294.95 |               1.44× |         3.16× |
|            3 |     227.86 |               1.87× |         4.09× |
|            4 |     187.62 |               2.27× |         4.97× |
|            5 |     175.03 |               2.43× |         5.32× |
|            6 |     160.84 |               2.64× |         5.79× |
|            7 |     155.19 |               2.74× |         6.01× |
|            8 |     147.75 |               2.88× |         6.31× |

One-to-eight-core efficiency is **36.0%**, not linear scaling. The report
records source/executable/JS hashes and every timing:
[final core scaling](../build/cpu-resolve-verified.json).

Reproduce without running builds or tests alongside the benchmarks:

```sh
deno task build:compiler:all
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-resolve-repeat.json . 3 1,2,3,4,5,6,7,8 balanced_64 full
```

### Retained native allocator investigation

An experimental free-list repacker orders known-free blocks by address without
moving live allocations. Over 100 pre-encoded Balanced 64 requests at eight
cores, late-request median latency improves **82.53 → 66.68 ms**. However,
native RSS worsens **46.09 → 59.21 MiB**. A variant using temporary mapped marks
and reclaiming completely free trailing heap pages still reaches **55.52 MiB**
at request 200. These experiments are **not in production**: they do not resolve
the memory tradeoff, and cached sessions would need further stress validation.
The measurements support allocator locality as a cause of retained latency; they
do not establish a leak-free long-term plateau.
[Latency probe](../build/repack-compare.json),
[tail-reclamation probe](../build/repack-trim-200.json).

The final production binary reaches **48.39 MiB at requests 100 and 200**, up
from **46.39 MiB at requests 10 and 50**. All 200 artifacts match. This retains
the previous queue-residency improvement, but does not remove the small later
growth. [Final native memory control](../build/native-memory-resolve.json).

### Verification and ECS execution

Both compiler targets build with stock Bend 2.0.21; `PROOF.bend` passes,
including the new single-frontier/single-root planning laws. **469 compiler
tests pass**, along with editor parsing/highlighting, six editor tests, seven
case-study source tests, formatting, and CLI type checks. The planner test
checks region membership and dependency closure on 256 generated DAGs. Native
tests exercise one/eight-core diamond compilation, source-order errors,
one-group cache misses, and rollback. All three ported examples compile through
raw-source and file-project APIs with JS/native artifact parity, then execute
via guest ABI 1.

`just study` succeeds. One run compiled the ECS source in **84.45 ms**,
including native compiler startup/shutdown but excluding the preceding compiler
rebuild. The guest then ran 100 ticks in **0.59 ms**, returning checksum 633;
component insertion and snapshot checks passed. These are single demo
observations, not warmed runtime benchmark medians, and do not compare JS with
native ECS execution.

### Remaining boundaries

This is not a general dependency-ready queue or work-stealing runtime. Shared
ancestors can put otherwise parallel branches in one region; their frontier
joins remain. The boundary scan, dictionary merge/framing, native protocol IO,
ordered final assembly, and fuel-accounted const evaluation still contain serial
work. Incremental lex/layout and already-parsed project loading retain their
existing paths. Retained-native latency and small residual RSS growth are still
unresolved; no allocator restart, cache eviction, or unsafe heap reset is hidden
in these changes. The examples do not add language features,
composite/persistent host state, or the archived GUI.

## Compact frontend and retained queue residency (2026-09-21)

This follow-up compares against the **immediately preceding uncommitted build**
(`build/cpu-before-host-tyPht3`), not commit `2428902`. Bend remains stock
2.0.21; the queue cleanup is in this repository's version-pinned native IO
effect.

Raw-source native compilation now encodes Baba's compact tree directly into
protocol words. It no longer materializes an object CST and Bend lists just to
walk them again for encoding. Parser workers perform this encoding themselves
and transfer packed buffers. The caller handles one share alongside at most
three isolates, overlapping initialization with useful parsing. Protocol 7
bytes, dictionary order, source offsets, diagnostics and lowering fuel are
unchanged. Already-parsed projects and incremental parsing retain their existing
paths.

### Compilation speed and host memory

Three fresh-process samples after two warmups, medians in milliseconds; AMD
Ryzen 7 7800X3D, physical cores 0–7. Host and native child share the stated CPU
affinity. Before/after configurations are interleaved; no build, test or second
benchmark ran alongside them. This is a shared desktop, not an isolated machine.
These are source-to-Wasm compiler latencies, not execution speeds of the Wasm.

| Cores | Balanced 64 before | Balanced 64 after |
| ----: | -----------------: | ----------------: |
|     1 |             415.40 |            392.35 |
|     2 |             298.78 |            279.42 |
|     3 |             248.09 |            228.40 |
|     4 |             209.69 |            206.30 |
|     5 |             200.01 |            193.73 |
|     6 |             194.75 |            186.18 |
|     7 |             194.00 |            173.90 |
|     8 |             181.08 |            159.75 |

Balanced 64 is **11.8% faster at eight cores**, with **2.46×** one-to-eight-core
scaling (30.7% efficiency). Its unchanged single-core JS backend measures 922.93
ms: native is 2.35× faster on one core and 5.78× on eight. At eight cores,
first-compile latency including lazy worker startup falls **317.37 → 228.85 ms**
(27.9%). This excludes compiler construction and is not complete CLI startup.
Warm host RSS falls **574.71 → 514.04 MiB** (60.67 MiB); first-compile host RSS
falls **446.20 → 321.39 MiB**. Parser memory overhead is reduced, not
eliminated.

The reported encoding phase falls 24.03 → 7.55 ms, but its boundary changed:
per-chunk encoding is now included in frontend time (80.47 → 83.91 ms), and the
encoding phase covers dictionary merging/framing. Compare end-to-end latency,
not the encoding phase alone. Native plus transport is 75.27 → 72.55 ms; native
CPU is unchanged at a median 240 ms, with 10 ms counter resolution. No inference
algorithm changed in this pass.

[All 166 configurations, artifacts, affinity and build hashes](../build/cpu-compact-final.json).

Reader 8 and Staggered 64 at eight cores measure 5.04 → 4.73 ms and 57.13 →
55.10 ms. Small timings are noisy. A nine-sample repeat of the apparent
regressions at two, three, six and seven cores removes the larger regressions,
except Reader 8 at three cores: **5.20 → 5.54 ms (+6.6%, 0.34 ms)**. This small
cost remains an observed tradeoff; the change does not improve every workload.
[All 180 control configurations](../build/cpu-compact-control.json).

### Why native RSS grew

An allocator probe found approximately 1.3 KiB of live Bend heap state after
each stateless request, with a heap high-water mark near 22 MiB. Nevertheless
RSS increased about 1 MiB/request. Memory maps located that growth in the
runtime's reserved corpus. Bend's drained task queues retain advancing positions
in a slot-major layout, gradually touching more queue planes; this is queue
residency, not a growing cache of live compiler results.

The receive effect now verifies that CPU queues are empty, clears used slot
planes and resets their cursors after the worker pool has joined. Publication
bits must also be cleared: resetting cursors alone could consume stale tasks.
Compiler heap allocations and incremental session caches are untouched. This
cleanup is CPU-only and relies on the pinned Bend runtime layout.

In the paired 50-request control, eight-core native RSS grows **45.33 → 93.33
MiB before**, versus **44.03 → 46.03 MiB after** (requests 3–50). In a separate
200-request mapping test, the instrumented baseline reaches **174.07 MiB**; the
production fix reaches **48.09 MiB**. Every artifact matches. The maintained
`compiler/native_memory_bench.ts` reproduces the mapping/parity control.
[Baseline mappings](../build/heap-lifetime-before.json),
[fixed mappings](../build/native-memory-after.json).

A longer production run reaches **51.94 MiB after 1,000 requests**, with all
artifacts matching. RSS was 45.94 MiB at requests 10–100: small later residency
growth remains, but the old roughly 1 MiB/request queue-plane growth is removed.
This does not establish a strict long-term memory plateau.
[1,000-request mapping control](../build/native-memory-1000.json).

The retained-latency issue is **not** solved by fixing queue residency: at
request 50, the last-five median remains 82.99 ms versus a fresh warmed control
of 68.50 ms (1.21×). Before, these were 84.50/68.07 ms (1.24×). Memory and
latency are separate findings; finite retention tests do not prove bounded
memory for every program or session workload.

### Remaining concurrency limits

Whole-file lexing/layout and final dictionary merging/framing remain serial.
Request assembly still joins parser chunks. Inference advances independent
chains but retains fan-out/join frontiers, deterministic failure ordering, and
success-only cache publication. Those barriers are not removed here: a general
dependency-ready scheduler needs separate implementation and correctness tests.

### Verification

All **463 compiler tests pass**.

The native build runs `bend PROOF.bend` and constructor-ownership checks at one
and four threads. Protocol tests cover exact bytes, fuel and offsets at one,
two, four and eight frontend threads, concurrent requests, diagnostics,
disposal, startup failures and fatal encoding failures. Example-corpus tests
compare declaration diagnostic locations as well as request bytes. The corpus
also confirms existing parser rejections in `syntax.blot`, `ecs.blot`, and
`host_capabilities.blot`; this pass does not implement their unsupported syntax.
Type checking, formatting and diff whitespace checks pass. The measured JS
backend is unchanged; the rebuilt native executable SHA-256 is
`ae46c21596132e88cd0c1358d70bfabf354db9b228684266979b5b8ff0384a92`.

## Frontend, lowering and inference follow-up (2026-09-21)

This pass follows up on the three opportunities after commit `2428902`:
parallelize the frontend, reduce lowering's aggregate CPU cost, and let ready
inference work advance without unrelated level barriers. Comparisons below use a
frozen copy of **that commit**, not the older baseline in the historical
sections. The default remains one worker; Bend remains stock 2.0.21.

### Production compilation results

Balanced 64 is **26.0% faster at eight cores** than `2428902` (286.19 → 211.72
ms). Its one-core latency falls 7.4% (511.94 → 474.15 ms). Scaling from one to
eight cores is **2.24× end to end**, versus 1.79× in the paired baseline; native
plus transport scales **1.91×**. Relative to this build's single-core JS
compiler, native is **2.11× faster on one core and 4.72× on eight**.

Five fresh-process samples, each after two warmups; medians in milliseconds.
These are source-to-Wasm **compiler latencies**, not generated-program execution
times. JS runs on one physical core; native and its host share the indicated
number of physical cores. The 630 configurations pair both snapshots across
seven workloads and all core counts.

| Backend  | Balanced 64 | Uneven 64 | Clustered 64 | Chain 64 | Reader 8 | Reader 64 | Staggered 64 |
| -------- | ----------: | --------: | -----------: | -------: | -------: | --------: | -----------: |
| JS       |      999.25 |    302.65 |       302.49 |    88.37 |    42.11 |    167.64 |       257.24 |
| Native 1 |      474.15 |    107.61 |       110.98 |    25.58 |    10.71 |     52.76 |        99.11 |
| Native 2 |      359.99 |     98.30 |       109.95 |    24.23 |     6.41 |     53.85 |        91.20 |
| Native 3 |      297.64 |     89.16 |        92.83 |    19.25 |     6.56 |     45.89 |        78.19 |
| Native 4 |      252.38 |     84.41 |        85.30 |    17.67 |     6.07 |     45.43 |        70.41 |
| Native 5 |      252.18 |     78.63 |        84.21 |    18.18 |     5.80 |     45.36 |        68.59 |
| Native 6 |      241.70 |     78.13 |        78.59 |    17.85 |     5.47 |     43.18 |        67.96 |
| Native 7 |      217.92 |     77.56 |        75.22 |    17.93 |     5.24 |     41.57 |        64.91 |
| Native 8 |      211.72 |     77.59 |        74.94 |    16.91 |     5.17 |     43.01 |        65.56 |

Balanced 64 scaling details; efficiency is speedup divided by core count:

| Cores | Before (ms) | After (ms) | Native + transport (ms) | Full speedup | Full efficiency |
| ----: | ----------: | ---------: | ----------------------: | -----------: | --------------: |
|     1 |      511.94 |     474.15 |                  180.31 |        1.00× |          100.0% |
|     2 |      424.15 |     359.99 |                  157.56 |        1.32× |           65.9% |
|     3 |      356.89 |     297.64 |                  145.86 |        1.59× |           53.1% |
|     4 |      330.68 |     252.38 |                  113.09 |        1.88× |           47.0% |
|     5 |      326.46 |     252.18 |                  113.01 |        1.88× |           37.6% |
|     6 |      314.89 |     241.70 |                  100.20 |        1.96× |           32.7% |
|     7 |      306.63 |     217.92 |                   99.43 |        2.18× |           31.1% |
|     8 |      286.19 |     211.72 |                   94.40 |        2.24× |           28.0% |

Staggered 64 places one expensive declaration at a different depth in each of
eight independent eight-declaration chains. It exposes the old per-level
barriers and is below the parser-pool threshold. Eight-core compilation falls
**22.7%**, from 84.81 to 65.56 ms. A single dependency chain cannot gain that
inference parallelism; its eight-core before/after latency is essentially flat
(16.86 → 16.91 ms).

At eight cores the Balanced 64 frontend falls from 162.30 to **92.28 ms**.
Encoding is 19.12 → 25.45 ms and native plus transport 103.99 → 94.40 ms;
component medians need not sum to the total. Native aggregate CPU falls from 360
to 280 ms, while host CPU rises from 260 to 340 ms (10 ms counter resolution).
End-to-end latency improves without a corresponding reduction in combined
host/native CPU.

There are material memory and cold-start costs. Eight-core host RSS rises from
**319.92 to 568.97 MiB** (about 249 MiB); native RSS stays near 45–46 MiB. The
first large compile, after compiler construction but including lazy worker
startup, takes **357.57 ms versus 332.14 ms** before (7.7% slower). This is not
a complete cold CLI startup measurement. One-core first-compile latency improves
from 593.32 to 561.72 ms. Warm throughput and first-use latency must not be
conflated.

[Final production samples, affinity and exact build hashes](../build/cpu-followup-final.json).
The machine was shared with active desktop work, including a busy Unity process;
no unrelated process was paused. Before/after configurations were interleaved,
and no build/test/other benchmark ran alongside these samples. Absolute times
differ from the earlier diagnostic sweeps; comparisons use the paired baseline,
not historical numbers from a quieter run.

### Incremental compilation

Body-edit medians from five fresh-process samples after two warmups, including
the existing incremental frontend. Each edit changes one declaration; this is
not a many-cache-miss lowering benchmark. All cache counts and artifact checks
pass. The parser worker pool does not run on this path.

| Workload     | Cores | Before (ms) | After (ms) | Latency reduction |
| ------------ | ----: | ----------: | ---------: | ----------------: |
| Balanced 64  |     1 |      151.81 |     159.32 |             −4.9% |
| Balanced 64  |     8 |      135.10 |     132.25 |              2.1% |
| Uneven 64    |     1 |       35.66 |      37.60 |             −5.4% |
| Uneven 64    |     8 |       40.93 |      40.69 |              0.6% |
| Clustered 64 |     1 |       33.89 |      39.22 |            −15.7% |
| Clustered 64 |     8 |       38.82 |      40.75 |             −5.0% |
| Chain 64     |     1 |        7.65 |       7.47 |              2.4% |
| Chain 64     |     8 |       14.62 |      14.38 |              1.6% |
| Reader 8     |     1 |        5.60 |       5.70 |             −1.8% |
| Reader 8     |     8 |        3.62 |       3.57 |              1.4% |
| Reader 64    |     1 |       16.65 |      17.60 |             −5.7% |
| Reader 64    |     8 |       21.63 |      21.23 |              1.8% |
| Staggered 64 |     1 |       30.85 |      21.78 |             29.4% |
| Staggered 64 |     8 |       28.03 |      24.46 |             12.7% |

[Final incremental samples](../build/cpu-followup-final-incremental.json). The
one-core arithmetic edit measurements are noisy: for example, Clustered 64's new
`parsed_ms` ranges from 12.33 to 33.07 ms, versus 12.39 to 16.46 ms before. The
observed slowdown is largely in the host frontend, not a changed number of
inferred groups. This does not by itself identify JIT, GC or desktop scheduling
as the cause.

### Regression controls

The full sweep contains four >5% median increases: Clustered 64 at two cores
(14.2%), Chain 64 at two/seven cores (5.6%/7.2%), and Reader 64 at two cores
(5.6%). An eleven-sample repeat does **not** reproduce those thresholds:

| Full compilation repeat | Cores | Before (ms) | After (ms) | Change in latency |
| ----------------------- | ----: | ----------: | ---------: | ----------------: |
| Clustered 64            |     2 |      109.02 |     101.47 |             −6.9% |
| Chain 64                |     2 |       27.33 |      25.27 |             −7.5% |
| Chain 64                |     7 |       16.81 |      17.07 |             +1.5% |
| Reader 64               |     2 |       52.63 |      53.16 |             +1.0% |

The three >5% body-edit increases were also repeated, with nine samples at one
core. Uneven 64 measures 35.29 → 36.89 ms (+4.6%); Clustered 64, 54.36 → 38.52
ms (−29.2%); Reader 64, 17.37 → 18.03 ms (+3.8%). The arithmetic results are
visibly unstable across sweeps; the repeat does not establish a large edit
speedup for Clustered 64 either. No >5% full-build/body-edit regression was
reproduced in these controls, but they are not an isolated-machine latency
guarantee. Unchanged-cache and cold-start costs are reported separately.
[Full-build repeat](../build/cpu-followup-full-control.json),
[body-edit repeat](../build/cpu-followup-edit-control.json).

### Retained native process

Fifty identical preencoded requests, excluding frontend/encoding, with fresh
two-warmup controls beside requests 10, 30 and 50. Times below are native plus
transport. The parser pool is not used in this control.

| Version | Cores | Last five median (ms) | Fresh at 50 (ms) | Retained / fresh | RSS at 3 (MiB) | RSS at 50 (MiB) |
| ------- | ----: | --------------------: | ---------------: | ---------------: | -------------: | --------------: |
| Before  |     1 |                215.12 |           207.32 |            1.04× |          34.64 |           34.64 |
| After   |     1 |                186.23 |           170.97 |            1.09× |          35.70 |           35.70 |
| Before  |     8 |                110.01 |            96.48 |            1.14× |          45.35 |           93.35 |
| After   |     8 |                 95.21 |            82.98 |            1.15× |          46.07 |           94.07 |

The final build is faster in absolute time, but eight-core retained latency is
still **14.7% above its fresh control**, and native RSS still grows **48 MiB**.
One run just under the earlier 15% threshold does not establish that the
previously unstable retained-process gate is resolved. Fifty requests do not
establish a memory plateau. This pass does not fix that runtime lifetime issue,
and no recycling hides it.
[Retained-process samples](../build/cpu-followup-final-reuse.json).

### Implemented scope

1. **Parallel raw-source parsing.** Native clean builds lazily retain a Baba
   worker pool capped by `threads`. Large sources split at validated top-level
   boundaries, with approximately 4,096 tokens per worker; inputs below 8,192
   tokens stay local. Workers transfer compact typed arrays, avoiding the cost
   of cloning object CSTs. The host materializes ordered CSTs with original
   Unicode/line-ending offsets. Rejected or ambiguous splits fall back to the
   canonical whole-file parser for diagnostic parity. Unexpected worker failures
   propagate and terminate the pool. Disposal rejects active/queued work. JS,
   already-parsed projects and incremental parsing retain their existing paths.
2. **Cheaper lowering classification.** Dispatch by the first character of a
   node's kind before exact comparisons, replacing 33 eager full-name
   comparisons with at most four. All labels and unknown-label rejection remain
   unchanged. A separate borrowed-CST accessor experiment did not reduce
   eight-worker CPU cost and was reverted.
3. **Chain-aware inference.** Contract only edges whose child depends on one
   parent SCC and whose parent has one consumer. Each SCC still checks and
   generalizes separately, but independent chains can progress without a join
   after every declaration. Both clean and incremental checking use weighted,
   bounded fork/join batches. Cache deltas/counters are local to each branch;
   publication remains success-only and the earliest original diagnostic wins.
   The existing dependency-plan cache now retains the schedule too, avoiding
   reconstruction after body-only edits. Its key already includes declaration
   order, dependency edges and nominal type dependencies.

The third change is **not a general dependency-ready queue**: fan-outs and joins
remain frontier boundaries, and Bend still assigns bounded fork/join lanes.
Whole-file lexing/layout, CST materialization and request encoding are still
serial. This is measurable progress on all three areas, not maximum parallelism.

### Lowering work and schedule-cache control

Separate five-sample diagnostic builds show the classifier reduces lowering's
CPU work, rather than merely redistributing it. These instrumented numbers are
not production headline timings. The follow-up trace predates the final
incremental schedule-cache change; its clean compilation path is unchanged.

| Balanced 64 lowering | Before wall (ms) | After wall (ms) | Before process CPU (ms) | After process CPU (ms) |
| -------------------- | ---------------: | --------------: | ----------------------: | ---------------------: |
| 1 worker             |            75.53 |           39.18 |                   73.96 |                  38.96 |
| 8 workers            |            30.74 |           18.21 |                  175.38 |                  94.25 |

Eight-worker lowering CPU falls **46.3%**, but remains about **2.4×** the
one-worker CPU cost. Parallel CPU amplification remains despite less total work.
Dependency planning still takes 3.38 ms at one worker versus 9.32 ms at eight in
this trace. Further work should measure that shared/serial cost and parallel CST
materialization/encoding before adding finer forks.
[Baseline phases](../build/cpu-before-cst-phases-summary.json),
[follow-up phases](../build/cpu-followup-phases-summary.json).

A separate five-sample Staggered 64 trace isolates inference, including its
schedule/prepare/execute stages. The baseline stages are summed per request
before taking the median, not added as independent medians:

| Staggered 64 inference | Before wall (ms) | After wall (ms) | Before process CPU (ms) | After process CPU (ms) |
| ---------------------- | ---------------: | --------------: | ----------------------: | ---------------------: |
| 1 worker               |            11.50 |           12.68 |                   10.94 |                  11.54 |
| 8 workers              |            23.25 |            6.40 |                   27.27 |                  28.06 |

The chain scheduler removes **72.5% of eight-worker inference wall time** with
roughly the same aggregate CPU work. It increases one-worker inference overhead;
the full compilation results include that cost. This isolates useful overlap
from the separate lowering improvement. As above, these are instrumented clean
builds, and the after trace uses the pre-schedule-cache snapshot.
[Before inference trace](../build/cpu-followup-staggered-before-phases-summary.json),
[after inference trace](../build/cpu-followup-staggered-after-phases-summary.json).

Rebuilding the chain plan on every incremental request initially regressed
Reader 64 edits. A nine-sample, three-way control at eight workers measures:

| Reader 64 body edit | Median (ms) |
| ------------------- | ----------: |
| Baseline `2428902`  |       18.86 |
| Uncached schedule   |       19.78 |
| Cached schedule     |       18.84 |

Caching removes that measured regression. It does not resolve the separate,
sub-millisecond unchanged-result timing gate: the same control measures 0.305 ms
before and 0.366 ms after. That host-only artifact-copy path is unchanged; its
relative increase remains an open measurement, not a claimed pass.
[Schedule-cache control and all three build hashes](../build/cpu-followup-cache-control.json).

### Correctness verification

The final build passes the Bend proof/ownership gates, TypeScript checks and all
**461 compiler tests**. Added coverage includes complete parser CST/offset/node
count parity; canonical diagnostics; concurrent requests and disposal;
worker-construction failure cleanup; all 33 lowering labels and prefix
collisions; 256 randomized chain-plan DAGs; SCC aliases, joins and fan-outs;
earliest-error ordering; native one/eight-worker artifact parity; incremental
reuse counters, failure rollback, dependency rewiring and declaration
reordering. The benchmark also executes emitted Wasm and checks artifact parity
outside timing. Formatting and whitespace checks pass.

### Reproduction and build identity

Ryzen 7 7800X3D, physical cores 0–7 (one logical CPU per core), Deno 2.9.6,
clang 22.1.8, stock Bend 2.0.21. Sources omit the prelude. This does not
benchmark the ECS specimen or `just study`. The final native SHA-256 starts
`8fab49da69e70b065f696d1bad5e701e8`; the baseline starts
`2550e81663b669f1f65b7e6f65ddcdea`. Full hashes, source fingerprints and Wasm
hashes are retained in each raw report. Raw reports and frozen snapshots are
local ignored `build/` artifacts; the tables above remain in the repository.

```sh
deno task build:compiler:all
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-followup-final.json .,build/cpu-before-2428902-ZjWvP7 5 1,2,3,4,5,6,7,8 balanced_64,uneven_64,clustered_64,chain_64,reader_8,reader_64,staggered_64 full
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-followup-final-incremental.json .,build/cpu-before-2428902-ZjWvP7 5 1,8 balanced_64,uneven_64,clustered_64,chain_64,reader_8,reader_64,staggered_64 incremental
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-followup-final-reuse.json .,build/cpu-before-2428902-ZjWvP7 1 1,8 balanced_64 reuse
```

Run each measurement serially, without builds/tests or other benchmark runs.
Preserve the baseline executable, JS compiler, frontend, protocol, parser
artifacts and sources together before rebuilding the current tree. Use the
separate phase-instrumentation instructions in [README.md](README.md) for
diagnostics, never for production timing claims.

## CPU scaling implementation (2026-09-20)

This pass implements the repository-only CPU plan on stock Bend 2.0.21. The
comparison baseline is the saved worktree at the start of this pass, including
the two earlier follow-ups below, **not** pristine `f55334d`. No toolchain fork,
process recycling, CUDA work, native frontend rewrite or ready-task scheduler is
included. The default remains one native worker.

### Production results

Balanced 64 full compilation is **20.1% faster at eight workers** than the saved
baseline (360.15 → 287.84 ms), exceeding the plan's 15% target. One-worker
latency falls 14.5% (551.66 → 471.77 ms). Relative to JS, native is 2.07× faster
at one worker and 3.40× faster at eight. This is not an eightfold multicore
gain: one-to-eight scaling is **1.64× end to end** and **2.13× for native plus
transport**. Serial host work and native scheduling/ownership costs still
matter.

Full compilation medians in milliseconds, nine fresh-process samples after two
warmups per configuration. JS uses one physical core; native uses the indicated
number. These are compiler latencies, not execution times of the generated Wasm.

| Backend  | Balanced 64 | Uneven 64 | Clustered 64 | Chain 64 | Reader 8 | Reader 64 |
| -------- | ----------: | --------: | -----------: | -------: | -------: | --------: |
| JS       |      978.85 |    333.46 |       329.69 |    79.52 |    32.68 |    174.74 |
| Native 1 |      471.77 |    119.35 |       115.73 |    16.51 |    10.28 |     42.28 |
| Native 2 |      382.95 |     96.58 |        96.17 |    18.42 |     7.08 |     41.67 |
| Native 3 |      320.29 |     85.39 |        83.04 |    15.98 |     6.67 |     41.44 |
| Native 4 |      300.28 |     75.53 |        77.98 |    16.14 |     6.41 |     39.16 |
| Native 5 |      296.01 |     76.67 |        74.36 |    16.15 |     5.98 |     39.29 |
| Native 6 |      299.29 |     76.87 |        73.59 |    15.88 |     6.25 |     37.44 |
| Native 7 |      292.25 |     71.80 |        72.64 |    15.53 |     6.13 |     35.75 |
| Native 8 |      287.84 |     71.14 |        70.42 |    16.10 |     6.40 |     36.69 |

Balanced 64 scaling, with speedup measured against this version's one-worker
latency and efficiency equal to speedup divided by worker count:

| Cores | Full before (ms) | Full after (ms) | Native + transport (ms) | Full speedup | Full efficiency | Native speedup | Native efficiency |
| ----: | ---------------: | --------------: | ----------------------: | -----------: | --------------: | -------------: | ----------------: |
|     1 |           551.66 |          471.77 |                  189.55 |        1.00× |          100.0% |          1.00× |            100.0% |
|     2 |           483.35 |          382.95 |                  141.86 |        1.23× |           61.6% |          1.34× |             66.8% |
|     3 |           418.42 |          320.29 |                  118.62 |        1.47× |           49.1% |          1.60× |             53.3% |
|     4 |           382.46 |          300.28 |                  104.52 |        1.57× |           39.3% |          1.81× |             45.3% |
|     5 |           380.41 |          296.01 |                  101.98 |        1.59× |           31.9% |          1.86× |             37.2% |
|     6 |           360.68 |          299.29 |                  100.41 |        1.58× |           26.3% |          1.89× |             31.5% |
|     7 |           359.25 |          292.25 |                   97.29 |        1.61× |           23.1% |          1.95× |             27.8% |
|     8 |           360.15 |          287.84 |                   89.06 |        1.64× |           20.5% |          2.13× |             26.6% |

Clustered 64 improves from 96.49 to 70.42 ms at eight workers (27.0% lower
latency), and Uneven 64 from 91.27 to 71.14 ms (22.1%). The dependency chain has
almost no multicore benefit. More workers also do not reliably help tiny jobs;
the default therefore remains one worker.

Body-edit compilation medians, including the frontend and the complete native
incremental request. Each edit changes one declaration; this does not benchmark
parallel lowering of many simultaneous cache misses.

| Workload     | Workers | Before (ms) | After (ms) | Latency reduction |
| ------------ | ------: | ----------: | ---------: | ----------------: |
| Balanced 64  |       1 |      201.79 |     201.66 |              0.1% |
| Balanced 64  |       8 |      140.12 |     117.54 |             16.1% |
| Uneven 64    |       1 |       43.89 |      43.97 |             −0.2% |
| Uneven 64    |       8 |       43.52 |      39.27 |              9.8% |
| Clustered 64 |       1 |       43.09 |      37.35 |             13.3% |
| Clustered 64 |       8 |       43.63 |      38.75 |             11.2% |
| Chain 64     |       1 |       10.12 |       9.93 |              1.9% |
| Chain 64     |       8 |       14.09 |      13.68 |              2.9% |
| Reader 8     |       1 |        3.94 |       3.96 |             −0.3% |
| Reader 8     |       8 |        3.58 |       3.29 |              8.3% |
| Reader 64    |       1 |       17.93 |      16.92 |              5.6% |
| Reader 64    |       8 |       22.06 |      20.71 |              6.1% |

There is no greater-than-5% full-build or body-edit median regression among the
48 native workload/core combinations in this sweep. Unchanged-cache calls take
roughly 0.07–0.34 ms; some exceed that relative threshold and are discussed with
the repeated controls below rather than silently counted as a pass.

The Balanced 64 request shrinks from 5,908,316 to 1,820,024 bytes (69.2%). Fresh
warmed native RSS falls from 92.74 to 35.33 MiB at one worker and from 115.15 to
45.75 MiB at eight. Native CPU medians are 250 → 180 ms at one worker and 320 →
320 ms at eight (10 ms counter resolution). Lower wall time does not imply
proportionately less aggregate CPU work.

The measured host frontend is still 179.90 ms at eight workers, encoding 18.86
ms, native plus transport 89.06 ms and decoding 1.44 ms. Component medians need
not add to the total median. The frontend component does not improve in this
full sweep despite removing a CST copy; host JIT/GC work can move between timed
components, so the end-to-end result is the acceptance measure.

[Raw production samples and build hashes](../build/cpu-scaling-final.json)
contain all 1,840 completed configurations, including the retained controls.

### Retained-process and regression gates

Fifty identical preencoded requests, excluding frontend and encoding. The final
five retained native-plus-transport times are compared with a fresh process's
third request at the end of the run. RSS is sampled after requests 3 and 50.

| Version | Workers | Last five median (ms) | Fresh control (ms) | Retained / fresh | RSS at 3 (MiB) | RSS at 50 (MiB) |
| ------- | ------: | --------------------: | -----------------: | ---------------: | -------------: | --------------: |
| Before  |       1 |                624.25 |             247.42 |            2.52× |          92.90 |           92.90 |
| Before  |       8 |                754.54 |             156.91 |            4.81× |         115.35 |          163.35 |
| After   |       1 |                195.55 |             183.97 |            1.06× |          35.43 |           35.43 |
| After   |       8 |                100.55 |              88.02 |            1.14× |          45.66 |           93.66 |

Two independent repeats at eight workers give 101.59/88.49 ms (14.8% slower) and
102.28/86.52 ms (18.2% slower). Thus the 15% retained-process target is **not
consistently met**, despite removing most of the previous slowdown. One-worker
repeats are 8.7% slower and 11.1% faster than their fresh controls; the latter
fresh control was itself slower at 218.34 ms. These short controls are noisy,
not evidence of a retained-process speedup. Eight-worker RSS still grows by 48
MiB in all three runs. Fifty requests do not establish a memory plateau or
eliminate the possibility of longer-term growth. No recycling hides this
behavior. [First repeat](../build/cpu-reuse-repeat-1.json),
[second repeat](../build/cpu-reuse-repeat-2.json).

A separate nine-sample incremental repeat at one/eight workers covers Clustered
64, Chain 64, Reader 8 and Reader 64. Clustered 64's one-worker unchanged call
remains about 0.13 → 0.16 ms (22% slower); Reader 8 also shows a small repeated
cache-hit increase. A further 21-sample Reader 8 check measures about 0.07 ms in
both versions, but still 5.7% slower relatively. The unchanged-result path in
`native_incremental.ts` is byte-identical across snapshots, makes no IPC, and
clones the retained artifact. These results do not identify a changed algorithm
as the cause; they also do not justify declaring the strict relative regression
gate passed. The cause remains unisolated.

The first repeat's Reader 8 one-worker body-edit result is 8.6% slower (3.75 →
4.08 ms), unlike the original sweep. The 21-sample repeat reverses that result
(4.29 → 4.11 ms, 4.3% faster), so a greater-than-5% body-edit regression is not
reproducible here. [Incremental repeat](../build/cpu-cache-repeat.json),
[21-sample small-workload repeat](../build/cpu-small-repeat.json).

Acceptance status: the balanced eight-worker improvement target and artifact
parity pass. Full-build/body-edit measurements show no reproducible >5%
regression in the checks above. The retained-eight-worker and strict
unchanged-cache relative-latency gates remain open; concurrency is improved, not
maximized.

### Implemented changes

- Native requests now enter Bend through an affine contiguous `Array<U32>` and
  an explicit valid length. Every read checks that length before indexing; Bend
  array indexes wrap, so the allocation's power-of-two size is not a bound
  check. The temporary linked list with one cell per request word is gone.
- Protocol 7 adds a per-request first-seen dictionary for CST kind, field and
  text strings. It keeps little-endian framing, opcodes 0–6, 48-bit Nats,
  Unicode scalar validation and the 16M-word frame limit. Host and executable
  must be rebuilt together. Response-error fallback headers are covered by a
  proof too.
- Diagnostic formatting is deferred until after request scanning fails. Static
  CST-header labels keep the hot word/header/tree scanner on stock Bend's flat
  execution path; a cold string-formatting branch had prevented that
  optimization.
- Raw-source offsets are added while materializing the CST, avoiding a complete
  shifted-tree copy. Project-owned CSTs remain immutable and local diagnostic
  offsets remain correct for Unicode and all supported line endings.
- Dependency-reference and ordinary reachability walks are flat. Siblings keep
  their own structural-depth fuel, reachability keeps its original per-work
  allowance, and error/result order is unchanged.
- Clean and incremental cache-miss lowering share bounded CST-node cost
  estimates and ordered cost-balanced partitions. A whole batch of at most four
  declarations bypasses estimation. Larger plans stop at one declaration or at
  leaves with at most four declarations and 512 estimated nodes. Refining the
  old unconditional four-declaration leaf avoids hiding wide forks when heavy
  declarations cluster. No declaration is split; existing diagnostic priorities
  and success-only cache publication are preserved.

### Measurement contract

The maintained Linux driver is [cpu_scaling_bench.ts](cpu_scaling_bench.ts),
available as `just bench-cpu`; phase instrumentation lives separately in
[cpu_scaling_trace.ts](cpu_scaling_trace.ts). Both use
[shared workloads](benchmark_workloads.ts), including the new Clustered 64 case.
See [reproduction commands](README.md#apis-and-incremental-compilation).

The production sweep interleaves snapshot pairs and rotates/reverses
configuration order, using nine samples after two warmups. Each sample has a
fresh host/native process. JS oracles are compiled and executed in separate
processes, then deserialized before timing; native hosts never load the JS
compiler. This avoids allowing reference-generation JIT/GC work to overlap a
native sample. `taskset` pins each configuration to one logical CPU from each of
1–8 distinct physical cores (CPUs 0–7 on this Ryzen 7 7800X3D). JS is pinned to
one core. The host and native child share the selected affinity; the full-build
scaling therefore also includes host GC/scheduling effects, not just Bend
workers. Cores are not isolated from the shared desktop. The visible cgroup
ancestry has no CPU quota. Deno is 2.9.6 and clang is 22.1.8.

Full times include the frontend, encoding, native transport/work and response
decoding; startup, verification, Wasm execution and CPU/RSS reads are excluded.
The native interval is still native **plus transport**, not pure compute. Native
CPU ticks exclude the host and have 10 ms resolution. Phase traces use separate
wall/process-CPU clocks and are never substituted for production timings.

Every complete clean artifact equals its snapshot's JS reference, and source
Wasm hashes agree across snapshots. Incremental body edits match clean Wasm and
signatures; session-local closure identities/offsets are intentionally retained.
Unchanged calls equal the previous complete session artifact. Emitted Wasm is
executed outside timing. Fixtures omit the prelude and measure compiler work,
not the unsupported ECS specimen or `just study`.

Retained-process checks send 50 identical preencoded requests at one/eight
workers, with fresh two-warmup controls beside requests 10, 30 and 50. The
comparison uses the final five retained requests against the fresh control at
50; it is distinct from the fresh-process full-build sweep. Compiler/source
hashes, affinity, process IDs, CPU ticks, RSS and raw samples are recorded.

### Current native phase costs and remaining limits

Separate diagnostic build, three fresh samples after two warmups, medians in
milliseconds for Balanced 64. These are not production headline timings and
medians of separate phases need not sum to the median request. The inference
interval includes publication/assembly until the next phase boundary;
reachability includes catalog setup until projection starts.

| Phase                           | 1 worker wall | 8 workers wall | 8 workers process CPU |
| ------------------------------- | ------------: | -------------: | --------------------: |
| Request buffer materialization  |          0.21 |           0.25 |                  0.24 |
| Request decoding                |          5.85 |           6.41 |                  6.39 |
| Lowering and its planning       |         76.97 |          30.61 |                189.27 |
| Dependency planning             |          3.58 |           9.26 |                  9.17 |
| Inference preparation           |          0.77 |           0.83 |                  0.83 |
| Inference execution/publication |         58.51 |          14.48 |                 74.17 |
| Reachability/catalog            |          2.42 |           3.63 |                  3.62 |
| Runtime projection              |          3.06 |           1.67 |                  3.96 |
| Instruction generation          |         32.58 |           8.41 |                 38.30 |
| Linking                         |          4.73 |           5.05 |                  5.01 |
| Response encoding               |          4.47 |           4.83 |                  4.84 |

Inference and codegen scale 4.04× and 3.87×; lowering scales 2.51×. Parallel
lowering's CPU cost is substantially higher than its one-worker cost (about 189
versus 74 ms). Cost estimation, shared-string/reference-count traffic and
runtime scheduling remain candidates for that overhead; no hardware-counter
measurements isolate their individual contributions. Cost-balanced partitions do
not make all costs disappear. Clustered 64 lowering takes 17.67/8.89 ms at
one/eight workers in the same diagnostic sweep.

Native process CPU/wall time averages about 3.7–4.0 occupied cores across the
eight-worker native interval. The four sections containing forks account for
only about 19% of full eight-worker elapsed time in this diagnostic run. Even
eliminating those sections entirely could remove only that share if the other
costs stayed fixed. The host frontend is therefore a larger next target than
simply adding more native forks; this is not a fitted claim of ideal scaling.

Dependency planning still executes roughly one core's work and costs more in the
multiworker runtime. Flattening reference collection does not flatten the entire
graph/SCC pipeline. Host parsing/materialization/encoding, graph planning,
linking and response encoding still surround the parallel stages. Whole-level
inference barriers remain, as do indivisible functions/SCCs and the
intentionally shared constant-evaluation fuel budget. There is no basis for
claiming maximum parallelism or linear eight-core speedup.

All 36 native request traces are complete. Logging finishes before the response
payload is written, avoiding a disposal race that lost a final trace in the
initial diagnostic tool. The final `send` interval therefore excludes payload
writing and log-file IO.
[Raw diagnostic samples](../build/cpu-phases-isolated.json) and
[phase summaries](../build/cpu-phases-isolated-summary.json).

### Verification and reproduction

`deno task test:compiler` passes: **453 tests, zero failures**, including the
Bend proof check, native ownership regression checks at one/four workers,
native/JS builds, maintained-tool typechecks and compiler tests. Added coverage
checks dictionary/frame limits, all truncated request prefixes/opcodes, invalid
Unicode and dictionary IDs, protocol-error response versions, offset/diagnostic
parity, structural fuel and ordered cost-balanced lowering. The final benchmark
and repeats also check artifacts outside every timed request. The phase driver
records all 36 expected native request traces.

The production comparison can be rerun against the saved local baseline with:

```sh
deno run --allow-all compiler/cpu_scaling_bench.ts build/cpu-scaling-rerun.json .,build/cpu-baseline 9 1,2,3,4,5,6,7,8 balanced_64,uneven_64,clustered_64,chain_64,reader_8,reader_64 full,incremental,reuse
```

Use `just bench-cpu` to rebuild and measure only the current version, or the
snapshot/diagnostic recipes in [README.md](README.md). Raw samples and the saved
baseline live in ignored local `build/`; the tables above retain the result in
the repository. No toolchain changes, CUDA benchmarks, ECS execution claims or
automatic worker-count changes are part of this pass.

## Earlier investigations (historical)

Reviewed on 2026-09-20 against `f55334d`. The compiler exposes real parallel
work, but its concurrency is **not maximized**. More worker threads do not make
the full pipeline uniformly faster.

## First follow-up: layout and incremental lowering

Two measured targets were changed: indexed layout line starts and parallel
incremental lowering of cache misses. Neither changes source-language semantics,
the protocol, diagnostic priority, or the one-thread API default. The benchmark
runners also accept every worker count from 1 through 8.

### Paired frontend comparison

Both old (`f55334d`) and new frontend implementations ran in the same Deno
process, alternating their order. Seven samples after two warmups parsed the
same functions with 64 let bindings each; complete CSTs and source offsets were
compared outside timing. This measures layout, parsing and materialization, not
just the replaced lookup.

| Functions | Before (ms) | After (ms) | Speedup |
| --------- | ----------: | ---------: | ------: |
| 8         |       15.31 |      13.06 |   1.17× |
| 64        |      204.59 |     130.49 |   1.57× |
| 128       |      693.86 |     286.26 |   2.42× |

The larger gain as the source grows is consistent with removing the repeated
prefix scans. This benefits both the JS and native compiler frontends; it is not
a multicore gain. [Raw paired samples](../build/review-layout-comparison.json).

### Paired incremental comparison

The saved `f55334d` native executable and the new executable used the **same
improved frontend**, alternating execution order in retained sessions. Every
sample changed one addition in all 64 independent 64-binding functions;
restoring the original source, artifact checks, cache-counter checks and Wasm
execution were outside timing. Seven samples after two warmups include the
frontend, transport and all native work, not only lowering.

| Workers | Before (ms) | After (ms) | Speedup |
| ------- | ----------: | ---------: | ------: |
| 1       |      513.07 |     516.08 |   0.99× |
| 2       |      545.75 |     492.26 |   1.11× |
| 4       |      512.29 |     423.17 |   1.21× |
| 8       |      509.33 |     434.83 |   1.17× |

The measured reduction is 17.4% at four workers and 14.6% at eight. One worker
changes by less than 1%; eight workers are not the optimum for this fixture.
Single-body edits still have only one lowering task, and cache hits never enter
the parallel tree.
[Raw paired samples and executable
hashes](../build/review-incremental-comparison.json).

## Second follow-up: projection and request encoding

Wasm runtime projection now uses the same cost-balanced partitioner as
instruction generation. A bounded, flat core-expression walk estimates work;
nested lambda bodies are separate entries and are not counted twice. Sequential
leaves, ordered joins and a 512-unit preparation grain preserve first-entry
error priority and avoid forks for the 64-tiny-entry fixture. Catalog creation,
reachability and relocation are still serial.

The host encoder in this earlier pass copied already validated string words from
earlier in the same request buffer. Offsets survive buffer growth; nothing is
cached across requests. This is not wire compression: protocol version 6, frame
bytes, Unicode validation and the 16M-word limit are unchanged.

### Paired encoding comparison

Alternating old/new encoders in one Deno process, fifteen samples after three
warmups. CST preparation and byte-for-byte verification are outside timing. Each
function has 64 let bindings.

| Functions | Before (ms) | After (ms) | Reduction |
| --------- | ----------: | ---------: | --------: |
| 8         |        2.65 |       2.18 |     17.7% |
| 64        |       26.24 |      21.44 |     18.3% |
| 128       |       58.97 |      49.32 |     16.4% |

[Raw encoding samples](../build/concurrency-round2-encoding.json).

### Paired native comparison

The saved first-follow-up executable and the new executable received identical
pre-encoded requests, alternating order. Nine samples after two warmups include
transport and the complete native pipeline, but exclude frontend work, request
encoding, response decoding and correctness checks. Every complete artifact
matches JS and every export executes outside timing.

| Workers | 8 functions before | 8 functions after | 64 functions before | 64 functions after |
| ------- | -----------------: | ----------------: | ------------------: | -----------------: |
| 1       |           31.38 ms |          31.79 ms |           293.17 ms |          298.43 ms |
| 2       |           28.84 ms |          29.24 ms |           260.80 ms |          260.32 ms |
| 4       |           26.66 ms |          27.64 ms |           198.39 ms |          199.32 ms |
| 8       |           25.39 ms |          26.84 ms |           190.23 ms |          177.78 ms |

The large eight-worker request takes 6.5% less time. This is not a uniform win:
its one-worker time increases 1.8%, and the eight-function case pays up to 1.45
ms for planning/fork overhead. The encoder improvement above is measured
separately and is not included in these intervals.
[Raw paired samples and executable hashes](../build/concurrency-round2-preparation-flat.json).

### Matched end-to-end check

Because the separate full sweeps drifted, a final comparison alternated the old
encoder/executable and new encoder/executable in one host process. The unchanged
frontend is included, along with encoding, transport, all native work and
response decoding. Fifteen samples after two warmups compile Balanced 64;
complete artifact checks and Wasm execution remain outside timing.

| Workers | Before (ms) | After (ms) | Change in elapsed time |
| ------- | ----------: | ---------: | ---------------------: |
| 1       |      480.67 |     483.79 |                  +0.6% |
| 8       |      385.61 |     375.57 |                  −2.6% |

The net gain is modest and concentrated at eight workers; the one-worker
measurement does not improve. These matched results support the combined change
on this fixture, not a universal speedup or linear scaling.
[Raw end-to-end pairs](../build/concurrency-round2-end-to-end.json).

### Isolated projection scaling

The grain runner now supports `prepare`, alongside `check` and `codegen`. The
112-configuration preparation sweep covers tiny/uneven jobs, all eight worker
counts and seven cutoffs. Median milliseconds per batch of 64 functions with
alternating eight/64-binding bodies, three samples of 64 iterations, at the
production cutoff of 512:

| Backend  | Projection |
| -------- | ---------: |
| JS       |      1.510 |
| Native 1 |      0.484 |
| Native 2 |      0.516 |
| Native 3 |      0.469 |
| Native 4 |      0.406 |
| Native 5 |      0.406 |
| Native 6 |      0.328 |
| Native 7 |      0.344 |
| Native 8 |      0.344 |

One-to-eight-worker scaling is 1.41× for this small phase; eight workers are
4.39× faster than JS. Results are checked against each backend's complete
ordered serial reference outside timing. Native millisecond timer resolution
limits precision; this is not an end-to-end speedup.
[Raw preparation sweep](../build/concurrency-round2-prepare-grains-flat.json).

### Rejected experiments

An outer decoder rewrite intended to reduce cursor sharing regressed the large
eight-worker native interval from 174.15 to 219.71 ms in its own paired run. It
was reverted; stronger truncation/diagnostic tests were retained.
[Rejected decoder measurements](../build/concurrency-round2-decoder-comparison.json).
The initial projection estimator used `F.children`, whose non-tail calls
prevented a flat traversal; its large eight-worker result was essentially
unchanged. The retained estimator uses explicit work states instead.

### Second-follow-up full compilation: JS and native 1–8 workers

Same fixtures, machine and timing boundaries as the first-follow-up table below:
seven samples after two warmups, milliseconds including the frontend and
transport. All 40 source/Wasm hash pairs match the prior reports, complete
native artifacts match JS, and incremental edits and emitted Wasm execute
correctly.

| Backend             | Reader 8 | Reader 64 | Uneven 64 | Balanced 64 | Chain 64 |
| ------------------- | -------: | --------: | --------: | ----------: | -------: |
| JS, single-threaded |    17.24 |     91.95 |    180.76 |      730.10 |    29.60 |
| Native 1            |     4.58 |     33.50 |     96.25 |      456.76 |    10.09 |
| Native 2            |     4.95 |     39.88 |    102.82 |      424.77 |    14.07 |
| Native 3            |     4.73 |     37.58 |     91.25 |      377.45 |    13.83 |
| Native 4            |     4.50 |     37.00 |     86.87 |      351.13 |    13.75 |
| Native 5            |     4.19 |     38.88 |     85.64 |      339.57 |    13.63 |
| Native 6            |     4.28 |     36.59 |     85.47 |      345.23 |    14.01 |
| Native 7            |     4.41 |     36.52 |     85.67 |      349.29 |    13.24 |
| Native 8            |     4.24 |     37.84 |     84.32 |      347.80 |    13.19 |

Balanced 64 is 2.10× faster than JS with eight native workers, and 1.31× faster
than one native worker. Five workers were the fastest observed configuration in
this sweep. The eight-worker time is higher than the earlier 325.89 ms, while JS
also rises from 677.14 to 730.10 ms. These separate shared-desktop sweeps do not
establish an overall latency improvement; the alternating paired comparisons are
the evidence for individual changes. Worker counts are not dedicated/pinned
cores. [Full raw report](../build/concurrency-round2-final.json).

## First follow-up: full compilation, every thread count from 1 through 8

Stock Bend 2.0.21, Deno 2.9.6, clang 22.1.8, Linux, Ryzen 7 7800X3D: eight
physical cores and 16 logical CPUs. Counts below are native worker threads, not
dedicated/pinned cores. Configurations ran sequentially on a shared desktop;
small/non-monotonic differences are not conclusive evidence of scheduler
defects. JS runs on one thread; changing the native worker count does not give
JS additional workers.

Median milliseconds, seven samples after two warmups. Includes layout/parsing,
protocol encoding/transport, compiler work and artifact decoding. Excludes
bootstrap, startup, verification and Wasm execution. Every complete native
artifact matches JS; edits match clean builds and emitted Wasm executes. All 40
source/Wasm hash pairs also match the baseline.

| Backend             | Reader 8 | Reader 64 | Uneven 64 | Balanced 64 | Chain 64 |
| ------------------- | -------: | --------: | --------: | ----------: | -------: |
| JS, single-threaded |    18.03 |     87.83 |    176.78 |      677.14 |    27.77 |
| Native 1            |     4.70 |     33.68 |     96.09 |      432.17 |    10.05 |
| Native 2            |     6.12 |     38.97 |     93.50 |      388.80 |    14.47 |
| Native 3            |     4.63 |     38.47 |     88.53 |      366.27 |    13.86 |
| Native 4            |     4.42 |     37.23 |     84.75 |      341.41 |    14.36 |
| Native 5            |     4.41 |     36.11 |     85.33 |      342.77 |    13.63 |
| Native 6            |     4.45 |     36.26 |     81.52 |      348.88 |    13.57 |
| Native 7            |     4.49 |     35.37 |     84.34 |      339.69 |    13.47 |
| Native 8            |     4.52 |     36.75 |     81.45 |      325.89 |    13.50 |

Balanced 64 has 64 independent arithmetic functions with 64 let bindings each;
Uneven 64 has eight such functions and 56 with eight bindings. Reader fixtures
use independent effectful functions and scoped providers. Chain 64 is a serial
dependency chain. All omit the prelude. These are compiler fixtures, **not an
ECS or runnable game**. The ECS specimen still uses unimplemented features, and
`just study` still reports that the sandbox backend was retired.

Balanced 64 is now 2.08× faster than JS at eight workers, and 1.33× faster than
one native worker. Its eight-worker median fell from 437.42 to 325.89 ms
(25.5%); JS fell from 806.33 to 677.14 ms (16.0%). These complete-pipeline runs
were taken before/after, not interleaved: use the paired comparisons above to
attribute improvements to individual changes. Clean compilation uses the
existing parallel lowerer, so its gain is not evidence for the new incremental
lowerer.

Reader 64 and Chain 64 still favor one native worker. Keep the one-thread API
default for mixed/small work; opt into more workers for substantial independent
work. The compiler is faster, but it does not yet scale linearly end to end.
[Raw after-improvement samples](../build/concurrency-after-review.json).

## Review findings

| Area                     | Finding                                                                                                                                                                                                 | Disposition                                                                                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frontend layout          | Each indentation lookup searched backward separately for LF and CR. An absent terminator made repeated lookups quadratic. A CPU profile identified `lineIndent` as the largest individual hot function. | Replaced with a once-built line-start index and binary search; preserve LF, CRLF, CR, mixed endings and diagnostic origins.                               |
| Incremental lowering     | All declaration cache misses were lowered serially, including first builds and multi-body edits.                                                                                                        | Separate cache selection from execution, batch only misses, then publish ordered results transactionally.                                                 |
| Lowering balance         | Clean and incremental lowering split by declaration count, not estimated body cost.                                                                                                                     | Remaining opportunity for clustered expensive declarations. The current uniform/regularly spaced fixtures do not establish robustness against every skew. |
| Inference preparation    | Group extraction, dependency interface lookup, cost estimation and incremental cache-key construction remain serial.                                                                                    | Candidate for a measured parallel preparation stage.                                                                                                      |
| Dependency scheduling    | A whole dependency level finishes before the next begins.                                                                                                                                               | A ready-task scheduler could overlap independent chains, but must preserve deterministic failure priority and cache publication.                          |
| Wasm preparation/linking | Core projection and body relocation originally walked independent entries sequentially around parallel codegen.                                                                                         | Projection now uses cost-balanced forks. Reachability, catalog creation and body relocation remain opportunities.                                         |
| Const evaluation         | Definitions share a decreasing fuel budget.                                                                                                                                                             | Intentionally sequential under current semantics; blindly forking would change observable behavior.                                                       |
| Request concurrency      | One native session queues requests on one ordered stream.                                                                                                                                               | Intentional revision/response isolation. Separate-session throughput is a different benchmark from one-compilation latency.                               |

Inference/projection/codegen use cost-balanced trees, sequential leaves and up
to eight branches per fork. This suits Bend 2.0.21's 16-lane CPU work chunks.
Grain cutoffs are 128/512/512. The review sweep found no justification for
indiscriminate forking: smaller grains help some large batches but add overhead
to tiny work.

Relevant source paths: `declaration_batches` in [lower.bend](lower.bend),
`prepare_tasks`/`check_frontiers` in
[check_scheduler.bend](check_scheduler.bend),
`prepare_groups`/`evaluate_constants` in
[native_session.bend](native_session.bend), `prepare_jobs`/`link_bodies` in
[wasm.bend](wasm.bend), and the revision queue in
[native_incremental.ts](native_incremental.ts).

## Baseline: full compilation, every thread count from 1 through 8

The `f55334d` baseline used the same machine, workload sources, seven samples,
two warmups, timing boundaries and correctness checks as the after-improvement
table above. Median milliseconds:

| Backend             | Reader 8 | Reader 64 | Uneven 64 | Balanced 64 | Chain 64 |
| ------------------- | -------: | --------: | --------: | ----------: | -------: |
| JS, single-threaded |    16.81 |     91.97 |    181.23 |      806.33 |    28.03 |
| Native 1            |     4.93 |     34.99 |    104.35 |      539.66 |    10.26 |
| Native 2            |     5.01 |     41.02 |    101.33 |      507.34 |    14.70 |
| Native 3            |     4.69 |     38.63 |     98.44 |      458.49 |    14.24 |
| Native 4            |     4.39 |     39.07 |     92.87 |      452.32 |    13.99 |
| Native 5            |     4.45 |     40.20 |     92.52 |      451.20 |    13.66 |
| Native 6            |     4.46 |     38.21 |     88.54 |      455.05 |    13.84 |
| Native 7            |     4.96 |     38.20 |     91.31 |      458.23 |    13.84 |
| Native 8            |     4.46 |     38.96 |     88.67 |      437.42 |    13.65 |

Balanced 64 was 1.84× faster than JS at eight threads, but only 1.23× faster
than one native thread.

In a separate host-instrumented run, eight-thread Balanced 64 spent a median
253.77 ms in frontend preparation, request encoding and response decoding: a
median 56% of each sample's elapsed time. The request contains 5,908,316 bytes
and 75,590 CST nodes. These additional-timestamp samples are separate from the
full-build table and must not be combined arithmetically with it.

## Baseline: isolated parallel phases

Median milliseconds per 64-job batch, alternating eight/64-binding bodies, three
samples of 32 iterations. Production grains: inference 128, codegen 512. No
frontend, transport or linking. Each backend matches its complete ordered serial
reference outside timing; full-build parity is checked separately.

| Backend  | Inference | Codegen |
| -------- | --------: | ------: |
| JS       |    54.649 |  10.439 |
| Native 1 |    16.938 |   2.281 |
| Native 2 |     9.500 |   1.656 |
| Native 3 |     7.094 |   1.281 |
| Native 4 |     4.875 |   0.906 |
| Native 5 |     4.688 |   0.906 |
| Native 6 |     5.281 |   0.906 |
| Native 7 |     5.281 |   0.813 |
| Native 8 |     3.906 |   0.875 |

Native one-to-eight-thread gains are 4.34× for inference and 2.61× for codegen.
Eight-thread gains over JS are 13.99× and 11.93×. Native millisecond clock
resolution quantizes the small codegen intervals; zero tiny-job measurements
mean below timer resolution, not zero work. These phase gains are not whole
compiler speedups. These inference/codegen numbers are historical, not a rerun
after the preparation partitioner was generalized. The new preparation sweep is
reported separately above.

The 224-configuration sweep includes tiny/uneven jobs, both phases, all eight
thread counts, and cutoffs serial/0/128/512/1024/2048/8192. Complete raw reports
with samples and compiler hashes are generated locally and ignored by Git:

- [Full-build baseline](../build/review-native-1-through-8.json)
- [Grain sweep](../build/review-grains-1-through-8.json)
- [Host interval baseline](../build/review-host-phases.json)

The checked-in runners now support all eight thread counts, so temporary runner
copies are no longer necessary:

```sh
just bench-native 7 build/concurrency-round2-final.json 1,2,3,4,5,6,7,8 2
just bench-grains 32 3
just bench-grains 64 3 prepare
```

## Verification and next targets

The follow-up passes `bend PROOF.bend`, `deno task build:compiler:all`, the
native ownership regression at one/four workers, all 448 compiler tests,
explicit benchmark/test type checks, repository formatting and
`git diff --check`. New regressions cover newline variants and exact layout
error origins, and incremental lowering at one/two/four/eight workers: full
artifact equality, execution, mixed hits/misses, first-source failure priority
and rollback after failure. The first-error join is also recorded in `LAWS.bend`
and proved in `PROOF.bend`.

The second follow-up adds projection planning/output/error tests, expands native
cache parity/execution checks to clustered expensive functions at
one/two/four/eight workers, and covers every truncated prefix of all seven
protocol operations. Encoder tests cover repeated supplementary Unicode, buffer
growth, exact stateless/session frames and the size limit when copying cached
string blocks. Projection's first-error join and exact Nat cursor consumption
are also proved.

Next targets are remaining host parsing, native request decoding, serial
inference preparation, reachability/catalog preparation and relocation. A fresh
pre-second-follow-up host run measured about 125 ms parsing, 27 ms encoding and
175 ms native/transport at eight workers; these are separate instrumented
intervals, not the final full-build table. The original baseline host percentage
above is not a current percentage. Weighted lowering needs a clustered-cost
fixture before changing its splitter; dependency-ready scheduling needs
deterministic error and publication tests before replacing level barriers. There
is no measured basis here for promising eightfold end-to-end scaling or making
eight workers the default.
