# Semantic allocation ownership

Task 011 is qualified. These changes reduce redundant capture preparation
without changing the immutable graph owners or claiming that the private
application allocation target is met.

## Allocation categories before changing publication

The top-level [memory tracker](src/memory.zig) measures successful backing
allocation requests, positive resize/remap growth, peak requested live storage
and teardown. Arena block capacity contributes to these totals. Solver/scratch
client requests inside a block are separate logical traffic; adding them to the
backing total would double count. Process RSS is another measurement.

Each exclusively leased heap-stable [Arena](src/region_arena.zig) now contains
separate solver and scratch adapters. `ClosureRegion` receives allocator
pointers to those stable fields, never to a returned-by-value region. Adapters
forward all four allocation operations unchanged, with no counter-driven
decisions or allocations. Their successful logical bytes/calls and individual
peak live bytes roll up at region release, before the pool resets or destroys
the owner. Every lease resets its meters; nested regions get separate adapters
and raw storage. The existing pool retention bound remains **64 MiB**. Logical
peaks are per owner, not the concurrent total or RSS.

Evidence import records the outer import's solver/scratch request deltas,
avoiding double counting recursively imported children. These are subsets of
arena client totals. Existing closed-evidence, closed-source and projection
reuse policies are unchanged. Open binders remain independently freshened and
chronological views remain region-owned.

Principal cloning meters operation-local copier buffers and owned array copies.
The destination durable type Store is a separate category and is deliberately
excluded from that buffer counter. Returned graphs store the original durable
allocator; no stack-adapter pointer escapes. Evaluator artifact snapshot cloning
uses `copySnapshotMeasured`, which wraps the existing read-only `copySnapshot`
API. Only owned slices escape and their caller frees through the same backing
allocator. Borrowed `snapshot()` does not copy the evaluator. Backend reporting
captures snapshot traffic after artifact pools have been copied.

Frozen capture preparation and child publication have separate byte counters.
Published bytes count the one durable child-span copy. Edge replacement bytes
are region scratch; they are not a second retained capture vector. Unclassified
frontend/backend allocation and durable Store growth remain visible in the
backing total. This instrumentation is a bounded attribution of explicit owner
seams, not a claim that every backing byte has been partitioned into disjoint
categories.

An instrumentation-only release probe, before removing copies, has compiler
SHA-256 `7b96a83dc3ba141cd92ade62a86a48e3f2dcf47a880be0f1cc4372a80a13f99e`. It
is investigative evidence rather than a qualified baseline. Its six public
workloads return zero live requested bytes. Logical requested bytes:

| Workload                      |    Solver |   Scratch | Principal copier buffers | Frozen temporary / published children |
| ----------------------------- | --------: | --------: | -----------------------: | ------------------------------------: |
| Scalar captures, 128 repeated |   345,632 |   229,012 |                    2,960 |                                 4 / 4 |
| Box captures, 128 repeated    |   369,860 |   336,348 |                    3,656 |                               12 / 12 |
| Shared aggregates, 128        | 1,037,996 | 1,042,912 |                        0 |                               16 / 16 |
| Nested lexical, 128           | 1,062,312 | 3,339,980 |                  571,752 |                               16 / 16 |
| Recursive diamond, 32         | 3,207,424 | 5,851,020 |                        0 |                                 0 / 0 |
| Callback captures, depth 8    | 3,540,656 | 1,962,412 |                        0 |                                 0 / 0 |

This establishes that scratch/graph preparation remains substantial and that
canonical reuse has already made repeated frozen capture vectors small. The
historical **321.2 MB** gdev total is from a different workload/revision; it
cannot be compared directly to these synthetic totals. The private snapshot is
absent.

## Removing redundant capture copies

Closure and aggregate collection previously duplicated the whole capture vector
with the Session allocator to protect a borrowed slice from recursive growth.
The collector now retains the source handle and count, and reacquires each child
by index before descending. Appending values/children preserves all handles and
original spans. No borrowed Session slice survives a recursive inquiry or buffer
growth. Aggregate child-type preparation belongs to the leased scratch arena;
constructing its solver type copies the prepared IDs into that solver's owner.
No region type ID is transferred to a durable value.

`ClosureRegion.freeze` previously duplicated every capture into a Session
temporary, patched it recursively, then copied it again into Session children.
It now prepares only `{ slot, current_value_handle }` replacements in region
scratch. Recursively frozen scopes retain their existing memo, so repeated child
scopes keep their aliases. The parent reserves values, evidence/record arrays,
children and optional closure/demand metadata before appending. After growth it
reacquires the original span, copies it once and applies prepared replacements.
Publication after reservation allocates nothing. Output physical order, record
layouts, solved mapping ownership and suspension creation/memo identity remain
unchanged.

An allocation failure while preparing children can leave valid unreachable child
headers in the Session, as before. It never overwrites original source headers,
spans, aliases or a partially installed parent memo. Completed canonical replay
retains its stricter whole-hit atomicity law: failed preparation changes
capacity only, and the same Session can retry. Durable closure
metadata/evidence/record layouts remain append-only and owned by the current
Session.

## Semantic validation

New native laws check nested solver/scratch ownership, lease reset and live
buffers; wide source captures and independent owned snapshots survive every
allocation failure, including after child preparation. Existing canonical hit
retry, nominal/alias, demand memo, nested region and portable import laws remain
required. The focused batch passes and the analyzer reports zero findings across
295 Zig files. A first full gate exposed const callers of `copySnapshot`;
separating the measured wrapper restores that API. The corrected full compiler
gate passes the full LLVM native suite and **618 guest/client tests**
(`allocation-full-gate-v2.log`); the analyzer has zero findings across 295 Zig
files (`allocation-analyzer-v4.log`).

Pinned task-008 comparison checks **620 cases / 1,240 invocations**, with
identical diagnostics and Wasm, **860 successful outputs** and **1,240 zero-live
teardown records**. Initial execution passes **58 guests / 3,436 calls**. Three
additional wide-capture workloads use balanced addition trees to stay within the
unchanged parser nesting limit. Their 16 distinct factories exercise width
8/32/128 without canonical equal-capture hits. Backing requested bytes are
826,737→827,377 / 1,270,284→1,267,852 / 2,879,879→2,865,159. Width 128 saves
14,720 bytes; width 8 exposes adapter overhead rather than a net allocation win.

## Isolated fresh qualification

The immutable baseline is `candidate-canonical/`, source milestone `daf9d70`:
compiler SHA-256
`73aafd1e53b68516178f6acb359cfc689239d009b20263472301c97654e0847a`, identity
`dc7184bf61fd9a6b587ea14302c0cdd1a42eef6eaf4cc7837f7d6034151113f8`. The
candidate `candidate-allocation/` has compiler
`571c1ccab004a8659553a20b10d5eb2e4b1ad9e680999a59156bc7b66af92c36`, identity
`3be94f26e4252ad0a710459aaa87ac25628bdba41ad034781cc13e56a808185d`, and
seven-file source-input manifest
`ba3728c7d06708969c7a8ed1a015a908c045ee127331daa3b2449f1d33f5bef7`. The manifest
hashes sorted compact JSON of path-to-SHA-256 entries for six changed Zig files
and the new executed-Wasm test. Older pins are unchanged.

`measure-allocation.py` checks **80 workloads / 15 alternating pairs / 2,400
fresh invocations**, persistence disabled, with child user+system CPU from
`getrusage(RUSAGE_CHILDREN)`. Every Wasm pair matches, logical work/backing
bytes are deterministic and each invocation returns zero live requested bytes.
CPU medians/ranges and requested bytes are baseline→candidate:

| Workload                                 | CPU median µs | Baseline / candidate CPU ranges µs | Backing requested bytes |
| ---------------------------------------- | ------------: | ---------------------------------- | ----------------------: |
| Wide captures 8, 16 distinct factories   |   1,918→1,803 | 1,499–2,139 / 1,520–2,185          |         826,737→827,377 |
| Wide captures 32, 16 distinct factories  |   2,439→2,372 | 1,910–3,320 / 1,963–3,032          |     1,270,284→1,267,852 |
| Wide captures 128, 16 distinct factories |   4,196→4,195 | 3,586–5,169 / 3,489–7,220          |     2,879,879→2,865,159 |
| Scalar captures 128, repeated equal      |   2,865→3,066 | 2,463–5,229 / 2,533–4,856          |     1,928,282→1,928,594 |
| Box captures 128, repeated equal         |   3,977→4,058 | 3,403–5,063 / 3,408–5,235          |     2,660,662→2,660,790 |
| Recursive diamond32                      | 20,827→20,725 | 18,581–26,201 / 17,815–31,527      |     8,478,427→8,488,139 |
| Callback captures depth 8                | 37,593→37,904 | 34,841–44,805 / 33,738–49,143      |     8,697,580→8,697,868 |

The median of all workload CPU ratios is **1.00023**: no general CPU speedup is
claimed. Scalar128 rises about 7% in this batch with overlapping ranges. The
measurement adapters add bounded owner overhead; existing canonical reuse means
many controls have little remaining capture-copy traffic. The wide workloads
keep 69 regions and zero canonical hits each. Their one durable child copy is
512 / 2,048 / 8,192 bytes; frozen temporary vectors and replacement edges are
zero. Width128's net saving is **14,720 bytes** and width32's is **2,432
bytes**; width8 adds **640 bytes**. Dominant solver/scratch and principal Store
traffic remains optimization work. The largest recorded candidate region in this
batch is 41,374 µs in the callback depth-8 control, not a universal bound. Host
load start/end is 0.727/0.906 on four CPUs; shared-host load and caches are
uncontrolled.

## Retained and restart qualification

The seven-pair retained harness covers **76 workloads / 6,384 phase samples**.
Fresh, retained and restart Wasm hashes match for each compiler, with no
unexpected diagnostic or byte differences between compilers. Edited execution
passes **90 guests / 10,500 calls**; folded constant reads are separate from
those calls. Host load starts at 0.504 and ends at 0.620 on four CPUs.

The retained server CPU uses `/proc` accounting at 10 ms resolution.
Wide8/32/128 fresh medians are 6→7 / 7→7 / 9→9 ms; restart medians are 6→6 / 7→7
/ 9→8 ms. Wide128 edit/revert reaches 10→10 ms, while no-op is below accounting
resolution. Diamond32 population/edit/revert are 20→20 ms. These results do not
establish a CPU improvement. Server samples report RSS, not requested allocator
peaks.

A separate native driver measures retained requested bytes directly around
`Session.prepareRevisionWithSources`, commit and candidate cleanup. It uses the
production `std.heap.smp_allocator` through `memory.TrackedAllocator`; fixture
strings, JSON reporting and process overhead are outside that tracker. Initial
empty-Session allocation precedes the population delta. Each attempt's peak is
reset to its starting retained live bytes, so it includes overlapping old and
candidate owners. It is an absolute requested live peak, not an incremental peak
or RSS. Baseline sources are archived from `daf9d70`; candidate sources match
the pinned compiler source manifest. Both ignored drivers are built with Zig
0.17.0 `zig build-exe .../allocation_memory_probe.zig -fno-llvm -Ofast`. Their
timings are not used as production CLI CPU evidence.

Four workloads cover width32/128 with 16 exported factories and a second pair
with a real imported dependency. The dependency pair exports only `call_0` to
its entry module; unused source is still checked. Edits change factory-zero's
seed from 1 to 3 and back. Seven alternating pairs, each with 21 rounds of
population-or-no-op/edit/revert/no-op, produce **4,704 revision samples**. Every
row has identical Wasm between compilers; the initial output also matches each
fresh/cache/restart production CLI result. All 56 driver processes release to
zero live bytes. Retained live bytes plateau separately in each phase for rounds
1–20. Median backing bytes, allocation calls and requested live peaks are
baseline→candidate; population is round zero and other rows are rounds 1–20:

| Workload      | Phase      |     Requested bytes | Allocation calls |     Peak live bytes | Retained live bytes |
| ------------- | ---------- | ------------------: | ---------------: | ------------------: | ------------------: |
| wide32        | population | 1,720,192→1,717,880 |      3,117→3,085 |     619,248→619,344 |     376,400→376,400 |
| wide32        | edit       | 1,821,848→1,819,792 |      3,437→3,407 | 1,004,948→1,005,044 |     376,396→376,396 |
| wide32        | revert     | 1,822,876→1,820,564 |      3,447→3,415 | 1,009,284→1,009,380 |     376,448→376,448 |
| wide32        | noop       |       20,516→20,636 |            19→19 |     396,034→396,154 |     376,448→376,448 |
| wide128       | population | 3,576,843→3,562,243 |      3,501→3,469 | 1,206,715→1,206,811 |     655,940→655,940 |
| wide128       | edit       | 3,821,087→3,807,511 |      3,847→3,817 | 1,865,583→1,865,679 |     655,936→655,936 |
| wide128       | revert     | 3,819,763→3,805,163 |      3,855→3,823 | 1,879,519→1,879,615 |     655,988→655,988 |
| wide128       | noop       |       36,544→36,664 |            19→19 |     691,598→691,718 |     655,988→655,988 |
| dependency32  | population | 1,150,207→1,150,599 |      1,823→1,821 |     307,188→307,188 |     217,496→217,496 |
| dependency32  | edit       | 1,148,848→1,149,240 |      1,947→1,945 |     524,628→524,628 |     217,592→217,592 |
| dependency32  | revert     | 1,148,848→1,149,240 |      1,947→1,945 |     524,628→524,628 |     217,592→217,592 |
| dependency32  | noop       |       18,957→19,077 |            38→38 |     234,400→234,520 |     217,592→217,592 |
| dependency128 | population | 2,380,450→2,380,074 |      2,215→2,213 |     741,662→741,662 |     354,332→354,332 |
| dependency128 | edit       | 2,373,213→2,372,837 |      2,241→2,239 | 1,095,938→1,095,938 |     354,428→354,428 |
| dependency128 | revert     | 2,373,213→2,372,837 |      2,241→2,239 | 1,095,938→1,095,938 |     354,428→354,428 |
| dependency128 | noop       |       29,229→29,349 |            38→38 |     381,500→381,620 |     354,428→354,428 |

The same immutable production CLI pins supply **168 additional invocations**:
seven alternating pairs for each of four workloads, with separate fresh,
cache-population and restart processes. All return zero live requested bytes;
only restart loads a checkpoint. Requested bytes/counts/peaks and child CPU
medians from `getrusage(RUSAGE_CHILDREN)` are:

| Workload      | Phase            |     Requested bytes | Allocation calls |     Peak live bytes |      CPU µs |
| ------------- | ---------------- | ------------------: | ---------------: | ------------------: | ----------: |
| wide32        | fresh            | 1,270,284→1,267,852 |      2,769→2,737 |     291,514→291,610 | 2,749→2,564 |
| wide32        | cache_population | 1,784,085→1,781,655 |      3,116→3,084 |     616,497→616,595 | 3,072→3,111 |
| wide32        | restart          | 1,861,327→1,858,897 |      3,334→3,302 |     639,659→639,757 | 3,139→2,932 |
| wide128       | fresh            | 2,879,879→2,865,159 |      3,152→3,120 |     676,698→676,698 | 4,289→4,754 |
| wide128       | cache_population | 3,668,610→3,653,892 |      3,501→3,469 | 1,198,641→1,198,739 | 4,883→5,282 |
| wide128       | restart          | 3,747,930→3,733,212 |      3,718→3,686 | 1,225,739→1,225,837 | 5,433→5,166 |
| dependency32  | fresh            |     694,043→694,219 |      1,206→1,204 |     274,576→274,576 | 1,790→1,897 |
| dependency32  | cache_population |     967,482→967,660 |      1,344→1,342 |     274,576→274,576 | 1,918→2,596 |
| dependency32  | restart          | 1,005,330→1,005,508 |      1,397→1,395 |     274,576→274,576 | 1,979→2,116 |
| dependency128 | fresh            | 1,578,196→1,577,604 |      1,392→1,390 |     685,273→685,273 | 2,824→2,944 |
| dependency128 | cache_population | 1,956,427→1,955,837 |      1,531→1,529 |     685,273→685,273 | 3,373→3,421 |
| dependency128 | restart          | 2,012,995→2,012,405 |      1,584→1,582 |     685,273→685,273 | 3,248→3,023 |

Host load starts at 0.112 and ends at 0.733 on four CPUs. These focused CPU
samples have shared-host noise and do not supersede the larger fresh batch. Wide
retained/restart allocation counts fall, but owner adapters add 120 bytes on
no-op and 96–98 bytes to some peaks. Dependency32's net requested bytes rise
slightly despite removing two allocation calls; dependency128 falls. There is no
blanket allocation, memory-peak or speedup claim. The plateau is evidence for
these repeated public revisions, not a universal Session-capacity bound.

The driver source SHA-256 is
`9df7147417f8f2e0e12d5e7e86c086990abcf49ff96df1157d01b9a20451fa2e`; baseline and
candidate executables are
`2841c233d9149d3897575288ad07a3440e8e30908e485185d67eb58588744ab6` and
`35f3f4a3d2fb910ff59b6bb1969604fe24ed6f054262d58d9789065ebb56c7f2`.
`measure-allocation-memory.py` orchestrates the batch and asserts per-phase
plateaus, exact hashes, reuse states, cache loading and teardown.

## Scope and evidence

Task 011's owner attribution and redundant capture-copy removal are qualified.
The private gdev snapshot is absent, and task 084 retains the under-100-MB and
application-wide performance gate. Solver/scratch and principal Store traffic
remain substantial. No private result is inferred from public synthetic data.

Raw evidence is under ignored `build/bench/cloud-principal-graphs/`:
`allocation-attribution/report.json` and `optimized.json`,
`allocation-comparisons/report.json` and `execution.json`,
`allocation-measurement/report.json`, `allocation-retained/results.json` and
`samples.jsonl`, `allocation-retained/execution.json`,
`allocation-memory/report.json` and the named focused/full/analyzer logs. These
tables preserve the findings independently of generated artifacts.
