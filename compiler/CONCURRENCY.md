# Concurrency review and benchmark report

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
