# Larger compilation experiments

Implementation follow-up: the direct index, borrowed free-variable and
closed-type kernels, equivalent-check coalescing, and incremental pending scan
are now integrated. See
[implementation and validation](TYPE_KERNEL_IMPLEMENTATION.md). The measurements
below describe the earlier isolated experiments.

This investigation starts from the verified retained-checking, membership-index
and flat-resolver compiler. Its saved native SHA-256 is
`7207b96597f57b55930717c203d84d47c8901c6f7234bacbbac670937da643e9`. The source
and generated outputs are frozen in `build/large-lever-study/baseline/`.
Experiments use separate trees.

The best measured prototype takes **1.224 s** for the fresh native compile call,
versus **1.461 s** in the same window (**16.2% faster**). Startup + project
loading + compile is **1.303 s**, versus **1.549 s**. This prototype combines
the direct index loop, borrowed free-variable collection, closed-type resolution
and equivalent-check coalescing. It preserves reclamation; it was isolated at
the time of this study. The 100–200 ms target remains far away.

## Current cost distribution

A fresh native trace of the baseline compiling the complete 16-module gdev
application records these coarse boundary-to-boundary CPU intervals:

| Interval                                      | Native CPU |
| --------------------------------------------- | ---------: |
| Decode, lowering and initial template graph   |      61 ms |
| Initial source shape checking                 |      99 ms |
| Shared specialization preparation             |     245 ms |
| Remaining specialization                      |     460 ms |
| Final planning, checking and export selection |     463 ms |
| Constant evaluation                           |      39 ms |
| Wasm preparation, emission and response       |      85 ms |

The traced and adjacent control requests both used 1,450 ms of native CPU and
produced the same 192,168-byte Wasm. These are coarse diagnostic intervals, not
independent function self times or an uncontended speed comparison. Frontend
loading and process startup are outside the intervals. Scripts and raw events
are in `build/large-lever-study/`.

Specialization accounts for about 705 ms, and final planning/checking another
463 ms. Even removing both would leave substantial work; the 100–200 ms full
source-to-Wasm goal also needs a smaller frontend/output cost.

## Parallel work

The full cold application has 844 singleton checking groups, 821 prepared
functions and 1,244 code entries. Its 13 dependency-level widths are
438/173/98/57/31/17/12/7/4/2/1/1/3. The scheduler contracts the graph into 754
chains and 28 regions; the largest region contains 727 chains. An
expression-cost proxy totals 380,168 with a longest weighted path of 15,896.
This shows available graph parallelism; it is not a time-weighted speedup
prediction.

A motion edit executes only one checking group and one code entry because the
others are cached. Those edit counts do not describe cold compilation.

Runtime counters confirm that one-worker compilation never enters the worker
pool (`pool_open=0`, `pool_turn=0`). Four-worker compilation opens it once and
turns it 18 times. A proposed synchronous one-worker pool optimization was
therefore rejected as unreachable on this workload.

## Measured native experiments

The following rows are separate quiet windows, each with five alternating pairs
of fresh native processes and fresh 16-module projects at one worker. One Deno
driver orchestrates each set; Deno's own launch/module-import time is outside
the recorded startup + load + compile sum. The filesystem is warm; no compiler
result cache is reused. All artifacts are exactly the same 192,168-byte Wasm,
SHA-256 `3acd6c59325af25370b39d7a5b6259ce7fd6314d944f2f3831f0ca1793c4cf9a`. The
compile column is the native compile call; startup and project loading are
additional. Percentages compare medians within the same window, and are not
additive.

| Candidate                                                | Baseline compile | Candidate compile | Change | Candidate CPU |
| -------------------------------------------------------- | ---------------: | ----------------: | -----: | ------------: |
| Sequential reference-count increments/decrements         |       1,466.2 ms |        1,440.4 ms |  −1.8% |      1,400 ms |
| Borrowed free-variable collection                        |       1,468.3 ms |        1,417.6 ms |  −3.5% |      1,380 ms |
| Borrowed free-variable collection + closed-type resolver |       1,478.8 ms |        1,414.7 ms |  −4.3% |      1,380 ms |
| Direct path-consuming String index lookup                |       1,466.5 ms |        1,333.4 ms |  −9.1% |      1,300 ms |
| Borrowed kernels including active substitutions          |       1,482.3 ms |        1,428.9 ms |  −3.6% |      1,390 ms |
| Direct index + all borrowed kernels                      |       1,477.9 ms |        1,293.5 ms | −12.5% |      1,250 ms |
| Direct index + free + closed resolver                    |       1,463.0 ms |        1,283.5 ms | −12.3% |      1,250 ms |
| Numeric specialization-choice index                      |       1,469.6 ms |        1,455.4 ms |  −1.0% |      1,420 ms |
| Equivalent-check coalescing + dependency levels          |       1,468.4 ms |        1,393.3 ms |  −5.1% |      1,350 ms |
| Combined: direct index + free + closed + coalescing      |       1,461.1 ms |        1,224.5 ms | −16.2% |      1,190 ms |

The reference-count experiment preserves every ownership operation and release,
using ordinary counter updates only with one CPU worker and no GPU. The measured
gain is too small to explain the overall runtime. It remains an isolated native
prototype.

The free-variable kernel borrows a type tree under its retained root and builds
only the final ordered result. The closed-type resolver proves that
substitutions cannot affect the input before transferring that owned input
directly to the result. Both use bounded scans and preserve structural-fuel
behavior through fallback. Direct differential probes passed 6,468 free-variable
and 10,752 resolver comparisons, plus 48 compiler analyze/compile operations at
one/four workers. The closed-only resolver adds little beyond collection.

The index prototype replaces per-branch closure allocation and suffix
reconstruction with a native loop. It consumes each selected Map path with the
existing ownership operations, releases the unselected child, and borrows only
String suffixes under an owned root. The returned value is transferred from an
owned leaf. Startup + loading + compile improved from 1,555.8 to 1,412.3 ms. The
prototype also passed 48 compiler operations at one/four workers and a 521-name
Unicode/prefix test with persistent Map snapshots and nested payloads. A direct
source-level mutually recursive helper was rejected by Bend's termination rules;
the measured candidate is a generated-C experiment.

The active resolver additionally follows chronological value-substitution
versions and constructs a bounded set of changed type paths. It retains every
borrowed field before releasing its owner and falls back for unsupported cases.
Its standalone oracle passed 17,920 exact comparisons, with counters confirming
the new path was used. Each combined compiler variant passed 144 interleaved
analyze/compile/error/recovery operations at one/four workers. The isolated Bend
proof also passed. One RSS pair measured 48,848 KiB baseline versus 49,984 KiB
for the combined prototype. A direct comparison found only a 4.2 ms (0.33%)
median benefit from the active branch, with overlapping paired variation. The
simpler free + closed variant is used in the combined prototype. Its separate
direct baseline comparison gives the kernel-only result. Raw pairs are in
`compact-kernel/direct-borrow-closed-pairs.jsonl` and
`compact-kernel/closed-vs-active-pairs.jsonl`.

The numeric-choice experiment changes only specialization's
`Map<String, Choice>` to the existing `NatIndex<Choice>`, avoiding decimal key
construction. It passed the Bend proof, native ownership gates and 144 compiler
comparisons. Five paired fresh gdev compiles showed only a small median
reduction and variable paired differences; this is not a large lever. It does
not test interning all compiler names or compact type storage. Source and logs
are under `build/large-lever-study/numeric-choices/`, raw timings in
`build/large-lever-study/numeric-choices-pairs.jsonl`.

A further borrowed-Map prototype keeps the original Map root alive while walking
its nodes, retaining the leaf key/value only when they are already
reference-counted or trivial. Unsealed fields or bounded-scan limits fall back
to the path-consuming loop with its inputs unchanged. Independent ownership
review, 144 compiler comparisons, the 521-name persistent-snapshot oracle and a
forced bounded-scan fallback all passed at one/four workers. Five quiet pairs
against the direct + free + closed candidate measured 1,297.2 versus 1,285.7 ms
(0.89%), with essentially unchanged peak RSS. This is a small additional gain,
so the simpler candidate remains the recommendation. See `borrow_index.py` and
`borrow-index-head-to-head.jsonl` in the study folder.

Raw data and scripts are under `build/large-lever-study/`:
`serial-rc-pairs.jsonl`, `direct-index-pairs.jsonl`, `direct_index.py`, and
`compact-kernel/borrow-free[-resolve]-pairs.jsonl`.

## Concurrency findings

Increasing inference grain from 128 to 1,024 did not reliably improve native
compilation at one, two, four or eight workers (three alternating pairs each).
All 24 full artifacts and original/edit/error/recovery checks matched. The grain
change is rejected. The detailed report is
`build/large-lever-study/parallel-pipeline/REPORT.md`.

A four-worker trace found long intervals with very little overlap: a 597 ms pool
turn used about 595 ms CPU on one worker and less than 1 ms each on the other
three; a 327 ms turn was similarly concentrated. Idle ring scanning exists but
accounts for too little CPU to explain these long intervals.

The phase-aligned trace locates substantial serial work before deferred
specialization and during final checking/export. The correct source census has
149 template-closure names, 91 generic templates and one shared-constant
candidate: gdev's `sandbox` builder. An earlier probe incorrectly passed an
object instead of JavaScript `false` to a generated Bend Bool argument,
truncating the closure to its 63 seeds; its zero-candidate result is discarded.
These traces identify where to inspect, not the self time of task-entry
functions: one task can execute many continuation functions before yielding.

Within `sandbox`, a further trace found about 210 ms in initial inference, 165
ms in repeated selection/scanning and 120 ms in final requirement
resolution/replacement. The selection loop invokes `specialization_pending` 237
times. This motivated two source-level candidates: fuse the coverage and
requirement scans, then retain unresolved requirements and inspect only newly
prepended definitions. Raw requirements must still be resolved against the
current substitutions every time they are considered. These diagnostic intervals
are instrumented observations, not speedup measurements.

The fused-scan candidate passed the Bend proof, native ownership checks and
original/edit/error/recovery comparisons at one/four/eight workers. Five quiet
pairs measured 1,467.0 versus 1,461.7 ms for the native request (0.36%); both
used 1,440 ms median native CPU. This is too small to address the target. The
request interval here excludes host preparation and encoding, unlike the
compile-call table above.

The incremental follow-up retains the old unresolved requirements, prepends
requirements from newly inferred definitions, and filters them against current
choices. It still resolves raw types against current substitutions and retains
the original need order and solver fuel. All successful selection paths were
reviewed for their immutable prior-definition suffix; a count regression or
short prefix falls back to the full scan. The final source passed the Bend
proof, native ownership checks at one/four workers, full gdev artifact checks at
one/four workers, and original/edit/error/recovery comparisons at one/four/eight
workers.

Five quiet alternating pairs measured **1,460.4 to 1,411.3 ms** native-request
median (**3.36%**), with native CPU falling from 1,440 to 1,390 ms. Peak RSS
rose from 48,940 to 49,976 KiB. The paired savings were 95.8, 42.6, 49.1, 37.7
and 52.0 ms; every artifact matched. This is a useful source-level candidate,
separately measured and **not included** in the headline combined prototype. Raw
results are `parallel-pipeline/delta-candidate/delta-baseline-pairs-1.json`.

A further five quiet pairs against fusion alone measured 1,459.1 versus 1,414.9
ms (3.03%), confirming that retaining unresolved requirements supplies the
useful gain. All ten artifacts matched in that comparison too. Raw data:
`parallel-pipeline/delta-candidate/fused-delta-pairs-1.json`.

## Temporary-object reclamation diagnostic

An isolated executable skips dead-term reclamation for one CPU worker, retaining
those objects until its fresh process exits. It still runs the complete compiler
and keeps the existing reference-count increments and ownership transfers. This
is a diagnostic, **not a usable session compiler or a proposed production
patch**.

Three alternating fresh pairs produced identical Wasm:

| Metric                  |   Baseline | Retain dead objects |
| ----------------------- | ---------: | ------------------: |
| Median native compile   | 1,471.5 ms |          1,094.9 ms |
| Median native CPU       |   1,440 ms |            1,060 ms |
| Median process peak RSS | 49,080 KiB |         658,188 KiB |

The 25.6% compile reduction costs 13.4 times the memory. This is evidence that
temporary object management deserves an architectural experiment. It does not
establish the speed of an actual arena or garbage collector: retained objects
also change allocation, sharing counts and memory locality. A useful design must
reclaim temporary inference storage and preserve exported types, diagnostics and
session caches across those boundaries. Raw measurements are
`build/large-lever-study/retention-pairs.jsonl`; the driver records Linux
`VmHWM` after each compile. A separate preliminary pair is not included in the
table.

## Reusing equivalent specializations

A complete post-specialization census found 152 redundant singleton checking
groups in 25 equivalence classes, covering 7,580 syntax nodes. A JavaScript
prototype reuses independently checked whole groups only after comparing their
complete bodies, imported interfaces and nominal declarations, renaming local
identities consistently and retaining each current function body. Its complete
checked module and emitted Wasm match exactly.

All duplicates within each class occupy the same dependency frontier. A cache of
already completed earlier frontiers therefore gets zero hits. Moreover, the
existing chain scheduler separates the equivalent jobs: only one three-job batch
reaches the candidate hook, with no reusable pair. The native experiment
therefore routes clone-heavy final plans through ordinary dependency levels,
coalesces equivalent tasks before executing each level, and publishes results in
the original order. The changed scheduling/setup cost must be included in its
timing. Its input census finds 152 matches across 13 levels; that census alone
is not evidence of actual native hits or a speedup.

The native candidate now builds and produces identical full-project Wasm in all
ten samples of five alternating pairs. Median compile-call time fell from
1,468.4 to 1,393.3 ms (5.1%); native CPU from 1,430 to 1,350 ms. Median
startup + loading + compile was 1,560.3 versus 1,474.9 ms. Peak RSS rose from
48,792 to 50,432 KiB. These figures include all input comparisons, replay
conversion and changed scheduling; they do not isolate reuse from the switch to
dependency levels. The Bend proof and native ownership build gates passed.
Independent review found no correctness blocker in dependency order, exact
imports/catalogs, failure handling or follower certificates. Targeted probes
confirmed that the generic batch path keeps different operation catalogs
separate, and that a failed representative rechecks its followers and returns
failures in original order. The failure probe is a smoke check, not a complete
diagnostic-field differential. Raw timings: `specialization/paired.jsonl`.

## Combined native prototype

Applying the direct index, free-variable and closed-resolver kernels to the
coalescer's guarded C gives the headline result: five quiet alternating fresh
pairs, **1,461.1 to 1,224.5 ms** compile-call median. Native CPU fell from 1,430
to 1,190 ms, and peak RSS rose from 48,952 to 50,624 KiB (3.4%). All ten
artifacts are identical. Paired wall reductions were 293.3, 239.6, 244.1, 241.4
and 227.7 ms. The changes overlap, so their individual percentages must not be
added.

The combined executable also passed 144 interleaved analyze/compile/error/
recovery comparisons at one/four workers, plus full gdev artifact comparisons at
one/four workers. Incremental-session original/edit artifacts, type-mismatch
diagnostic fields and post-failure recovery also matched the JavaScript oracle
at one/four/eight workers. The source candidate had already passed the Bend
proof and native ownership gates; the C kernels retain their shape/version
guards. No production source or executable was replaced. Reproduction assets:

- `build/large-lever-study/combine_kernels.py`
- `build/large-lever-study/specialization/blotc-guarded.c`
- `build/large-lever-study/coalescer-direct-free-closed.c`
- `build/large-lever-study/blotc-coalescer-direct-free-closed`
- `build/large-lever-study/coalescer-kernels-pairs.jsonl`

The combined executable SHA-256 is
`ce87c2d2283cb5273e49a46f606e9c61dafc313e9f78627f8c2bc04ca993596f`.

## Outcome

Carry forward the direct index loop, bounded free/closed type kernels,
equivalent-check coalescing and incremental pending-constraint cache. The first
three have a measured combined executable; the pending cache remains a separate
candidate. Their percentages cannot be added. The active-substitution kernel,
further borrowed Map loop, numeric choice keys and grain adjustment do not offer
enough additional benefit to be the next priority. The no-reclamation binary
remains solely a diagnostic.

All 57 shared Bend source hashes and the installed native executable still match
the baseline snapshot, and gdev remains clean. Only the report was added to the
shared source tree during this investigation. Candidate code, native
executables, raw measurements and detailed agent reports are kept under
`build/large-lever-study/`; none is enabled in the shared compiler.

## Architectural direction supported by the experiments

The following is a proposed next design, not a measured speed prediction:

1. Give each independent inference task an owned temporary store with compact
   type/variable IDs. Reclaim the store in bulk after copying its exported
   interfaces and diagnostics. Persistent session caches must own the results
   they retain. The dead-object diagnostic motivates this test; it does not
   validate the design or its memory bound.
2. Compile a generic body into reusable constraints and operation requirements
   once. Instantiate that representation at each use, retaining the selected
   implementation evidence needed by specialization. Named generic calls must
   carry transitive requirements; retaining only a function signature is
   insufficient for gdev's abstractions.
3. Make specialization consume that evidence, with local validation of the
   transformed typed body. This targets the approximately 705 ms specialization
   interval as well as repeated final checks. A signature-only clone cache is
   unsound because equal signatures can select different implementations.
4. Parallelize the resulting independent tasks with separate temporary stores
   and deterministic result/error publication. The current wide dependency graph
   does not expose all the heavy serial work to workers.

The next decisive vertical slice should cover the complete `sandbox`
specialization path through `monomorph.infer_required` and `solve`, including
generic calls and their transitive member/effect requirements. Replace its
temporary type/constraint representation directly; interning expanded trees
afterward still pays for their construction. Compare the owned store with the
existing solver including conversion, freezing, reclamation and error recovery.
Preserve chronological substitution behavior, occurs checks, row identities and
deterministic failures; a conventional union-find substitution is not
automatically equivalent to the current resolver. A small identity-function
microbenchmark or a signature-only cache would not settle this design.

The language should keep polymorphism, structural products, nominal identities,
effect rows, associated dispatch, compile-time evaluation and local inference.
These experiments support changing their representation and compilation
strategy; they do not show that any of those features must be removed to make
compilation faster. The 100–200 ms full-compilation target remains unachieved.
