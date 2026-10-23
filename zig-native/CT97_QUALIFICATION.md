# CT97, CT98 and BT4: row traversal, executable reuse and temporary allocation

24 October 2026. Seven alternating release pairs reduce fresh game CPU by
**32.5%** against CT96 and matching instrumented inference by **37.3%**, meeting
CT97's targets. Executable reuse is restored and backend allocation work is
reduced; CT98 and BT4 retain their remaining timing targets. The final isolated
candidate passes full compiler qualification. The separate uncommitted
text-capability repair is preserved outside this candidate.

## What changed

The largest inference store followed 402,273,418 replacement edges, with a
longest path of 5,864. In that store, version visits equal chain hops: the cost
was repeatedly walking selected paths rather than searching a variable's
history. Effect resolution now keeps followed row prefixes across appended
writes and rechecks their terminal open tails. Physical rollback revokes cached
row IDs. Empty-label paths between selected chronological writes acquire
shortcuts to later versions. Target birth stamps reject recycled slots after
suffix rollback; saturated epochs disable caching. Original label order and
multiplicity, cursor selection, independent rows, occurs checks and inference
limits remain intact.

The new differential law compares caching to a disabled-cache oracle through
appends, cursor gaps, duplicate labels, rollback, recycled destinations and
epoch saturation. It also injects every allocation failure. Existing chronology
and nonempty-label laws remain part of full qualification.

Retained executable admission was disabled by a complete-index requirement: the
game's capture filled the default 4,096 records and saturated before it could
seal. Executable indexes now have their own 16,384-record / 8 MiB capacity
limit. Generic semantic queries keep their 4,096-record / 2 MiB defaults; owned
payload and lookup-work limits do not change. All origin, argument, selected
input, static dependency and replay checks still apply. Unsealed or saturated
captures still decline. This restores executable reuse; it does not eliminate
inference in changed principal regions.

Allocation stacks in the slow exhaustive laws identified short temporary lists
and maps. Row/layout conversion, mapping export and certificate maps now try 512
bytes of local scratch; scalar replacement tries 2 KiB for analysis. Overflow
uses the original allocator. Interners copy temporary inputs, and exported
mappings and generated instructions retain their original owning allocator. A
wide-row ownership law crosses the scratch bound and preserves repeated labels
after the conversion returns.

## Measurement boundaries

The reference is qualified CT96 release
`fa75772f21cf9bce6a4c0cbfa60acef55bbd9a550a54336c426f9bee5a8fcb35`. Both
variants use the same frozen 554-file gdev/Ink/std/assets snapshot and
configured budgets. Fresh throughput, retained edit/revert/restart checks and
instrumented phase comparisons run separately, with no simultaneous compiler
build or native qualification jobs from this task. Linux CPU ticks include
exited worker threads. OS page caches are retained.

The host was shared with other compiler jobs. Fresh-run load changed from 6.7 to
7.7; retained-run load changed from 7.7 to 11.2. A separate observation reached
19.5. One baseline revert took 56.082 s wall versus 15.440 s CPU. That sample is
retained. The task ran no simultaneous build or test jobs during application
measurement. Alternating pairs and process CPU reduce some scheduling bias, but
these medians are not stable latency or p95 guarantees; the full raw ranges
remain in the archive.

## Final fresh release results

Each row contains seven alternating pairs. Paired ratios, rather than ratios of
independently chosen medians, determine CPU acceptance.

| Workload | CPU median, baseline → candidate | Wall median, baseline → candidate | Median paired CPU ratio |
| -------- | -------------------------------: | --------------------------------: | ----------------------: |
| game     |                 13.140 → 8.870 s |                  13.598 → 8.676 s |                 0.67504 |
| devtools |                  0.720 → 0.730 s |                   0.678 → 0.692 s |                 1.02817 |

Game paired CPU ratios span 0.55770–0.79604. Peak game RSS medians are 475.9 /
473.0 MiB. Devtools meets the unaffected-workload CPU guard of at most 5%
regression.

Candidate release SHA-256:

```text
73a9998009efc24e3d3516a689355a1be6cf90ccf880f3dc3ccee6aa22c0dff6
```

## Retained edit and restart results

Seven alternating pairs include population, no-op, trivia, literal and body
edits, every revert, and fresh processes using separately populated restart
caches. Fresh controls of each edited tree also match. Every successful Wasm
output is byte-identical across compilers and applicable fresh/retained/revert
and restart comparisons; all workload and compiler pins remain unchanged.

| Phase                  | CPU median, baseline → candidate | Candidate wall median (range) | Median paired CPU ratio |
| ---------------------- | -------------------------------: | ----------------------------: | ----------------------: |
| edit:literal_in_body   |                 13.860 → 7.450 s |        7.629 (6.878–12.876) s |                 0.59337 |
| revert:literal_in_body |                 11.090 → 6.630 s |         6.619 (5.781–7.739) s |                 0.55012 |
| edit:body_change       |                 11.200 → 6.520 s |        6.555 (5.935–10.257) s |                 0.56875 |
| revert:body_change     |                 11.270 → 6.350 s |         6.214 (5.732–6.902) s |                 0.56433 |
| noop                   |                  0.010 → 0.010 s |         0.018 (0.016–0.022) s |                       — |
| edit:trivia            |                  0.020 → 0.020 s |         0.019 (0.017–0.022) s |                       — |
| restart                |                  0.020 → 0.020 s |         0.025 (0.023–0.120) s |                       — |

Literal edits reuse 3,297 named functions and 1,238 closures; body edits reuse
3,195 named functions and 1,214 closures. The baseline reused none. These are
combined row/cache/scratch improvements, not an isolated estimate of
index-capacity savings. The 50% CPU and four-second wall targets remain open.
No-op/trivia/restart CPU is too close to the 10 ms process-clock resolution for
a meaningful percentage claim.

## Separate phase comparison

Three alternating pairs enable identical phase/allocation instrumentation on
both releases. These clocks are for attribution, not the throughput acceptance
above. Backend work clocks may nest; do not sum them as exclusive phases.

| Game phase | Baseline median | Candidate median |
| ---------- | --------------: | ---------------: |
| inference  |         9.933 s |          6.227 s |
| constants  |         0.312 s |          0.307 s |
| layouts    |         0.061 s |          0.060 s |
| evaluation |         0.206 s |          0.207 s |

The candidate frontend check takes 1.284 s, with 7,651,883 allocations
requesting 1,074,988,618 cumulative bytes. This is the next CT100 attribution
baseline; cumulative requests are not live memory.

## Full qualification and compiler iteration

The isolated full gate passes **2,540 native laws** with exhaustive allocation
failures, **1,648 guest/client checks**, 48 smoke checks and 57 tooling checks.
Exact inventory, all four shards, completion records, leaks and logged errors
are verified. The final source has zero Zig analyzer findings. The new row law
and the wide scratch-overflow ownership boundary both run under full faults.

The full gate takes 634.83 s; native execution takes 584.26 s. The previous CT96
gate took 761.75 / 665.13 s in another interval. These are observations, not a
paired whole-gate speedup. The already-built release is cached in this gate;
actual LLVM release construction takes 196.47 s. BT5’s 150 s release-build
target remains open.

Both affected Safe/noLLVM development checks pass: static sharing in 16.10 s and
types/effects in 3.94 s, compiling the complete 2,540-law inventory before
runtime selection and sampled faults. They run 28 / 13 native laws respectively.
These are individual development-cycle observations, not p95 measurements.

A separate single-pair screen executes the three slowest laws with the actual
qualified Safe/noLLVM native binaries, three independent processes per variant.
It retains all faults and has no application benchmark running concurrently. Its
raw `wait4` max-RSS values include the Python parent’s pre-exec fork peak after
binary hashing, so they are excluded from memory comparisons. Application RSS
above is measured directly from the compiler process.

| Combined three-law screen |     CT96 | Candidate |
| ------------------------- | -------: | --------: |
| Process CPU sum           | 244.65 s |  193.37 s |
| Per-law wall sum          | 247.23 s |  194.92 s |

Wall ratio 0.788; CPU ratio 0.790. This bounded screen does not establish a
repeated whole-gate improvement or close BT4. Stop further scratch-size tuning
after the two experiments; reprofile remaining allocation callers before another
change.

## Evidence and reproduction

The [evidence archive](measurements/ct97-rows-reuse-scratch-2026-10-24.tar.gz)
contains final candidate sources, binary/source/workload pins, all raw paired
samples, phase records, full gate/shard logs, native screen, allocation traces
and intermediate/incomplete attempts. Every payload has a SHA-256 entry. Private
application sources, binaries, caches and qualification keys are excluded.

Local evidence is `build/bench/ct97`, with BT4 diagnostics under
`build/bench/bt4`. `final-measurement-commands.json` records all exact
application commands; `final-gate-command.json` records full qualification. Use
Zig 0.17.0; native tests use Safe/noLLVM and application performance uses the
final LLVM release. The original frozen workload remains at
`build/bench/compile-cost-20261023`. The final release is
`build/bench/ct97/final-src/zig-native/zig-out/bin/blotc`. The qualified release
was installed as `~/.local/bin/blot` and `~/.local/bin/blotc` after publication
on 24 October 2026. The raw compiler matches the SHA-256 above; the CLI bundles
the same compiler and matching parser, guide and standard library. The CLI
passes external-directory formatting, checking and building. Both commands emit
identical Wasm, which executes the list example with result 29. Previous
executables and installation evidence are preserved under
`build/install/ct97-1aa132e/`.

## Bounded experiments and remaining targets

The first prefix-only/capacity release screen reduced game CPU by 17.4% in one
pair. The three-pair shortcut screen reduced it by 28.1%, with exact output.
These screens motivated the final candidate; final acceptance uses the seven
pairs above. Safe/noLLVM screens are development evidence only.

The first 128-byte scratch experiment saved about 6% of allocations; the initial
u32 list capacity alone needs 132 bytes. The second uses the sizes above.
Successful deep-path emission requests 2,208 allocations instead of 2,783; the
effect-bearing fixture requests 2,268 instead of 3,097. Across the three slowest
laws, all 33 exhaustive sweeps pass with 37,930 scenario runs instead of 44,074.
Every allocation in the new implementation is still fault-injected; no fixture,
boundary assertion or fault position is skipped. The diagnostic binary enables
frame pointers for allocation stacks, so its elapsed times are not comparable to
the earlier qualification binary.

CT98's 50% edit-CPU and four-second wall targets remain unmet in the seven-pair
results above. BT4 requires halving the three laws and at least 5% less
whole-gate wall; allocation counts alone cannot close either target. Further
work should follow new measurements, rather than repeat these two scratch-size
experiments.

Two intermediate development attempts failed because they used a missing
analyzer path; the successful rerun uses the pinned analyzer in `build/tools`.
An initial diagnostic failed to forward counters; a later one captured them,
then its retained edit was deliberately stopped. These are retained as
incomplete evidence, never counted as passes. Intermediate candidates were not
installed; only the final qualified release was installed after publication.
