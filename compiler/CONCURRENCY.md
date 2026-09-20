# Concurrency review and benchmark report

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
