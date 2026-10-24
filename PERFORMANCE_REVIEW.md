# Performance hills toward sub-second edits

The [CT106 qualification](zig-native/CT106_QUALIFICATION.md) records **19.1%
less first-literal-edit CPU** against CT105 in seven alternating release pairs,
with identical Wasm. First-literal wall median falls from 3.62 to **2.91 s**;
fresh CPU improves 2.4%, body CPU is effectively unchanged and literal-revert
CPU rises 3.5%. These are shared-host observations. Body-edit, two-second and
sub-second targets remain open.

Exact frontend correspondence now checks one module on the first edit instead
of 22. Bounded operation indexes/certificates, lexical links and import scratch
remove repeated work. The report includes 200 distinct edits, allocator/CPU
attribution, exhaustive qualification and rejected experiments. All 86 review
suggestions have a [disposition](COMPILER_CT106_WORK.md); conditional alternatives
and unfinished architectural work are explicit.

## Historical post-CT105 review — 24 October 2026

The [new 86-suggestion review](COMPILER_REVIEW_CT105.md) covers algorithms,
memory, CPU execution, reuse, parallelism, output and compiler build time on
unchanged `a0645de`. It includes fresh phase/stack measurements, a 40-build
memory cycle, a frontend graph-size probe and six ranked experiments. The
installed compiler still matches the qualified release. The earlier audit
below describes the preceding binary and retains its original measurements.

## CT105 implementation and qualification — 24 October 2026

[CT105](zig-native/CT105_QUALIFICATION.md) implements the supported scope-scan,
row-certificate, interner fast-path, evidence-sort, worklist, cache and
allocator fixes. Exact frontend indexes replace quadratic correspondence
searches; principal observations now own anonymous/module dependencies. Seven
alternating release pairs against `5cfb411` show 13.3% less fresh-game CPU,
12.9% less body-edit CPU and 3.3% less first-literal CPU, with unchanged Wasm
and full qualification. The literal 10% target misses. Fresh/body solver live
peaks grow about 9.88 MB; the report includes complete allocation and RSS
evidence.

The first-edit comparison now reaches a graph-stage decline with binding/catalog
budget remaining. This does not establish a semantic mismatch: see the new
review's graph-size probe and remaining decline-reason ambiguity. Four body
regions still rebuild on exact source-image/identity
differences. Literal-revert inference is 1.259 s and the non-inference floor is
still about 1.34 s in the matched profile. Sub-second edits require further
work. All 50 audit observations have an explicit disposition in the
qualification record; hardware/retention/parallelism hypotheses are not reported
as fixed bugs. The audit below describes the preceding installed binary and
remains the historical diagnostic baseline.

## Current CPU, memory and algorithm audit — 24 October 2026

**Prioritize eliminating repeated inference work, then row normalization and
worklist scans.** The installed compiler still executes tens of billions of
instructions for an ordinary edit, mostly on one thread. Allocation churn is
large, but this run does not show swapping or establish memory bandwidth as the
limiting resource. First-edit frontend checking is a separate, substantial cost.
Even eliminating inference entirely would leave roughly 1.34 seconds in the
later-literal profile, so sub-second builds also need cheaper reuse and
emission.

This is a diagnostic refresh on unchanged
`5cfb4117a1749dd487205652ea5645af1164afaf`, not a new optimization comparison or
compiler qualification. At audit time, all `zig-native/src/**/*.zig` bytes
matched the qualified integration source. Installed ReleaseFast/LLVM compiler
SHA-256: `0185500e446d59d6e813de8cecb3318bcc5983632043eb0129b8a64bad45ee9f`. The
same 554-file frozen gdev/Ink/stdlib workload and settings are preserved;
manifest SHA-256:
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`. There are
189 compiled game modules, optimized codegen, four codegen workers and a
200-million inference budget. Restart-cache persistence is disabled in the edit
sequences. No compiler implementation changed for this audit.

### Current measurements

Three alternating pairs use the **same binary**, profiling off/on. The wall and
CPU columns below are unprofiled medians. Check and inference columns are
separately measured profiled medians; they must not be subtracted from the
unprofiled wall to manufacture a precise remainder. Inference is a nested
backend clock, not an extra top-level phase.

| Build                               |    Wall | Process CPU | Frontend check |     Inference |
| ----------------------------------- | ------: | ----------: | -------------: | ------------: |
| Fresh game                          | 7.902 s |     8.130 s |        1.202 s |       5.564 s |
| First literal edit after population | 3.666 s |     3.920 s |        0.784 s |       1.398 s |
| Literal revert in the same session  | 2.709 s |     2.970 s |        0.059 s |       1.366 s |
| Body edit after the literal pair    | 5.461 s |     5.710 s |        0.059 s |       4.076 s |
| Body revert                         | 5.392 s |     5.640 s |  about 0.059 s |   about 4.1 s |
| Unchanged game                      | 0.016 s |     0.010 s |           zero |          zero |
| Fresh devtools                      | 0.654 s |     0.690 s |        0.260 s | about 0.155 s |

Profiling changes median game CPU by -1.6% to +1.3% across the substantive build
classes in this small screen. That bounds observed overhead/noise here; it is
not proof of zero instrumentation overhead. These quieter timings do not
supersede the historical paired CPU improvement percentages with a new speedup.
They are not p95s, process-startup-inclusive CLI timings, or guaranteed
latencies.

An independent, unprofiled eight-revision sequence checks population, three
previously unseen literal values, three body variants and exact source
restoration against the earlier fresh-controlled Wasm hashes. Its later literals
take 2.727 / 2.872 s; body variants take 5.610 / 6.588 / 5.803 s, and final
restoration 6.833 s. Edit order, previous retained state and the actual body
matter. All benchmark comparisons preserve recorded Wasm hashes and unchanged
inputs.

The new CPU-weighted GDB profiles cover 99.52% / 99.55% / 99.78% of process CPU
for fresh / literal edit+revert / body edit+revert, with 730 / 576 / 1,094
complete sampling intervals and no missing/truncated stacks. The edit profiles
include first-edit checking, so the archive also splits edit and revert. These
are single sampling runs; percentages are approximate, and optimized inline
attribution can move work between adjacent functions. Directory attribution is
code ownership: `check/` also implements the solver used inside backend
inference.

| Self CPU function                       | Fresh | Literal pair | Body pair |
| --------------------------------------- | ----: | -----------: | --------: |
| `types.Store.closedHeight`              | 5.20% |        4.41% |     6.06% |
| `types.Store.resolveOperationArguments` | 5.05% |        4.21% |     5.62% |
| `types.Store.internResolvedOperation`   | 4.52% |        0.48% |     0.52% |
| `types.Store.resolveNode`               | 2.98% |        1.90% |     3.03% |
| `effects.Store.resolve`                 | 2.63% |        1.04% |     2.94% |
| `solver_worklist.Queue.enqueue`         | 1.15% |        0.60% |     2.14% |
| `solver_worklist.Queue.wakeAll`         | 0.98% |        0.41% |     1.55% |

Inclusive clocks overlap: `resolveOperationRow` owns 10.64% of the
literal-revert sample and 19.59% of the body-revert sample; `bodyEvidenceMode`
owns 24.05% and 60.40%. Do not add those percentages to each other or to their
self rows.

### How the machine and compiler are organized

The host has one Ryzen 7 7800X3D socket, eight cores / sixteen logical CPUs, 32
KiB L1 data cache and 1 MiB L2 per core, and 96 MiB shared L3; one NUMA node.
Linux reports about 93.4 GiB RAM. Deno 2.9.7 runs the client; the native Zig
compiler does the semantic work. No affinity, governor or machine settings were
changed. This is a shared host, not an isolated benchmark machine.

The pipeline is source loading → flat syntax and symbol tables → chronological
type/effect checking → owned typed Core → evaluation, inference and
specialization → reusable function fragments → optimization and Wasm assembly →
transactional publication. Revisions retain checked modules, proofs, values and
executable artifacts under separate ownership and admission rules. Each
compilation still constructs a new evaluation Session and private inference
regions. A successful principal-result hit therefore does not imply a fully
incremental build.

Types use compact 16-byte nodes and integer indices into contiguous arrays;
child lists, substitutions, effect rows, operations and evidence live in
separate stores. Resolution combines dense indexing, chronological version
chains, recursive graph walks and hash caches. This is already much better
structured than allocating an individual object for every type. Its temporal
substitution semantics mean ordinary union-find path compression is not a
drop-in replacement.

Each inference region uses reusable bump storage. The retained server uses a
process-wide small-allocation heap with size-class free lists and a spin lock;
large allocations map/unmap pages directly. Parallel backend workers have
private arenas, but share their backing allocator and join before publication.
Semantic inference workers are not enabled in these ordinary builds.

The memory sequence samples `/proc` every 100 ms, with boundary RSS/PSS
snapshots and per-thread scheduler accounting. Boundary RSS after population is
372.6 MiB; after later edits it is 415.7–479.9 MiB. Lifetime high-water RSS
reaches 749.8 MiB. Those are different measurements. One thread owns 90.5–96.6%
of observed CPU; thread/process accounting agrees within tick/boundary precision
(99.8–100.2%). Runqueue wait totals only 19–44 ms per build in this sequence. No
compiler swap or major page faults occur, but edits incur 154,405–240,373 minor
faults.

A separate `perf_event_open` probe and four-edit experiment record user-space
hardware events on the busiest compiler thread, after unmeasured population. All
six events ran for 100% of their enabled intervals, without multiplex scaling.
They exclude other compiler threads, kernel work and Deno. Instructions/cycles
are hardware events; generic cache events are **not** a verified AMD-specific
L1/L2/LLC miss taxonomy or DRAM traffic measurement.

| Edit               |  Instructions |        Cycles | Instructions/cycle | Branch misses / branches | Generic cache misses / 1,000 instructions |
| ------------------ | ------------: | ------------: | -----------------: | -----------------------: | ----------------------------------------: |
| First literal      | 48.87 billion | 18.20 billion |               2.69 |                    0.89% |                                      1.48 |
| Second literal     | 36.88 billion | 16.63 billion |               2.22 |                    0.89% |                                      2.01 |
| Third literal      | 36.88 billion | 12.36 billion |               2.98 |                    0.83% |                                      1.32 |
| First body variant | 74.37 billion | 25.72 billion |               2.89 |                    0.74% |                                      1.17 |

The later literal instruction counts differ by about 0.005%, but their cycle
counts differ by 34.5% relative to the smaller count. This is evidence that work
count and execution cost vary independently; it does not identify the cause of
the slower interval. Whole-process kernel time is 0.20–0.36 s in these edits. No
claim that Blot is exclusively compute-bound, bandwidth-bound or branch-bound
follows from these aggregate counters.

### Fifty observations and their next measurements

**M** = directly measured here; **C** = confirmed in current source; **H** = an
optimization hypothesis whose benefit is unmeasured. These are observations, not
fifty proven bugs. Source links identify the implementations; all numeric claims
above and below come from the archived current audit unless marked historical.

#### Critical path and CPU

1. **M — Inference is still the largest target.** It takes 5.56 s fresh, 1.37 s
   on literal revert and 4.08 s on the body edit. Track unique query inputs and
   work per query before trying to speed up every individual primitive.
2. **M — The first edit expands frontend work.** It validates 22 modules and
   elaborates 763 bodies; the later edits validate one and elaborate 164. The
   module cutoff reports one changed interface on the first edit. Trace that
   exact comparison and cache population rather than calling all 6.55 million
   check allocations necessary. See
   [retained revisions](zig-native/src/reuse/retained_revision.zig).
3. **M — Unchanged-input reuse already works.** Game no-op median is 16 ms, with
   no checking or backend work. Startup/input plumbing alone cannot explain
   multi-second source edits.
4. **M/H — Inference alone cannot reach one second.** The profiled literal
   revert takes 2.711 s, including 1.366 s inference: approximately 1.345 s
   remains even under the unrealistic assumption of free inference. Reuse,
   preparation, optimization and emission need a second track.
5. **M — Most CPU is on one thread.** The memory series shows 90.5–96.6% on the
   dominant thread despite four codegen workers. More codegen workers do not
   address most of the present critical path.
6. **M — Instruction volume is substantial.** Later literals execute 36.9
   billion instructions on that thread; the tested body edit executes 74.4
   billion. Reducing duplicate visits offers a direct way to cut that volume.
7. **M — CPU efficiency varies even at nearly fixed work.** Two literal edits
   have nearly identical instruction counts but 12.36 versus 16.63 billion
   cycles. Record instructions alongside paired CPU and wall measurements;
   investigate cache/placement/host effects without attributing this difference
   to a compiler change.
8. **M — Small projects have a different balance.** Fresh devtools is already
   about 0.65 s, with checking around 0.26 s and inference around 0.155 s.
   Preserve this control when an optimization adds cache or scheduler overhead.

#### Resolution and solver algorithms

9. **M/C — Closed-type certificate checks are hot.** `closedHeight` is a small
   guarded node read, yet accounts for 4.4–6.1% self CPU. Count its calls by
   caller and cache outcome; a hot load is not by itself proof of a hardware
   cache miss. See [type storage](zig-native/src/check/types.zig).
10. **M/C — Operation arguments are repeatedly inspected.**
    `resolveOperationArguments` checks every operation argument for closedness
    before resolving open arguments. Separate labels visited, arguments visited,
    unchanged results and true mutations; the unchanged work is the useful
    target.
11. **M/C/H — Operation interning has candidate-chain cost.**
    `internResolvedOperation` narrows by identity/instance/arity, then compares
    argument graphs along a chain; it is 4.52% self CPU fresh. Measure chain
    lengths and comparisons. A stable argument discriminator may help, but must
    respect mutable symbolic arguments and oldest-equal selection.
12. **M/C/H — Evidence rows sort again before lookup.**
    [internRowWithFormal](zig-native/src/check/effect_evidence.zig) copies,
    validates, sorts and hashes its input even if the canonical row already
    exists. Sorting callers account for 2.76% of literal-revert CPU. Measure
    already-sorted inputs and row sizes; an exact sorted-input path is
    plausible. Preserve duplicate labels: their multiplicity is semantic.
13. **C/H — Version lookup can still traverse chains.** Type/effect replacement
    lookup scans chronological versions. Effects already have safe empty-prefix
    shortcuts, so proposing ordinary path compression would repeat completed
    work and risk rollback semantics. Measure chain-length distributions and
    cursor patterns before adding an index.
14. **M/C — Broad worklist wakeups are visible.** `enqueue` plus `wakeAll`
    account for 3.68% self CPU in the body pair. Rollback, fallback and broad
    dependency watches can schedule extra attempts. Count wake reason,
    already-ready entries and attempts that make no progress. See
    [solver worklists](zig-native/src/check/solver_worklist.zig).
15. **C/H — Bounded dependency discovery falls back to global watches.** The
    frontier has 64 keys, a 256-node stack and a 1,024-visit bound. Large graphs
    become `any_write` subscribers. Count overflow versus explicit broad watches
    and the resulting wake fanout before changing these limits.
16. **C/H — Watch discovery revisits graphs.** The frontier walk has no visited
    node set; shared children may be traversed repeatedly, and each unsuccessful
    constraint attempt reconstructs its watches. Measure unique nodes versus
    visits and watch changes before adding a bounded memo or scratch bitmap.
17. **M/C/H — Lexical sharing scans beyond its scope.**
    [shareLexical](zig-native/src/eval/core_eval.zig) scans the whole region
    variable array and row-variable map, filters by scope, then does linear
    membership tests against quantified variables. It is 1.74% self CPU in the
    body pair. Count scanned/matched entries; per-scope indices could remove the
    repeated region-wide component without changing inference.
18. **M/C — Occurs checks are frequent, but not proved redundant.** There are
    508,730 steps on literal revert and 1,338,479 on the body edit. Attribute
    these to roots and repeated graph versions. Any memo must retain cycle
    detection, mutation and depth behavior; removing the checks is not an
    optimization.

#### Reuse and semantic architecture

19. **M — Four body principal regions still rebuild.** The largest three collect
    1.83 / 0.94 / 0.61 million solver nodes and 33,828 / 20,233 / 13,953 scopes.
    Four projected image admissions decline. Record the exact consumed source
    declaration/namespace comparison responsible for each miss; unchanged result
    signatures do not prove unchanged semantic inputs.
20. **M — Complete principal hits leave thousands of regions.** Literal edits
    hit all 20 principal results, yet still create 2,934 inference regions
    (2,422 on revert), about 104–106 thousand scopes and about 95 thousand
    constraint visits. Attribute these residual entry/closure queries and their
    exact inputs. Principal hit rate alone is an incomplete progress metric.
21. **M/H — Selected-query lookup has significant candidate filtering.** The
    first literal stack run has 508 lookups, 3,250 enumerated candidates and 151
    reuses. Count rejected candidates by key field and retained bytes; an index
    improvement may help more cheaply than widening semantic admission.
22. **M/H — Canonical-specialization hit rate is low here.** The first literal
    has 3 hits in 360 queries; revert has 1 in 350. Determine whether these are
    mostly unique requests or equivalent requests with different encodings
    before investing in a bigger cache. See
    [Session caches](zig-native/src/eval/core_eval.zig).
23. **C — Proof, value and executable reuse have different inputs.** Closed
    signatures, captures, selected members, effects and source observations are
    not interchangeable cache keys. Keep ownership translation and exact
    admission while making records smaller or queries less repetitive.
24. **C — Body recipes cache traversal, not solved inference.** A recipe avoids
    rediscovering Core visit order, but replay still imports types, creates
    constraints and solves in a private scope. Track actions avoided separately
    from recipe hits. See [body recipes](zig-native/src/eval/body_recipe.zig).
25. **C/H — Failed recipe plans can repeat.** A plan that exceeds the
    4,096-entry limit is freed without a negative cache record. The same body
    can pay that failed walk again. Count repeated declines for identical body
    and bound; memoize only if this actually recurs, preserving smaller-limit
    behavior.
26. **C/H — Many caches live for one compilation.** Body recipes, closed-source
    facts and specialization caches are rebuilt with the evaluation Session.
    Measure how much immutable information is reconstructed after an edit. A
    retained cache needs a stable owner and bounded lifetime, not raw old IDs.
27. **M/C — Successful reuse still validates graphs.** Frozen-Core validation
    appears in the literal CPU sample, and validation takes about 27 ms on later
    edits, 50 ms first edit. Measure exact repeat validation by owner/version;
    immutable validated-owner certificates may avoid work, but validation is not
    optional for newly imported or changed graphs.

#### Allocation and memory lifetime

28. **M — Allocation traffic is much larger than resident memory.** Backend
    requests are 1,752 MiB on literal revert and 2,394 MiB on the body edit;
    fresh game requests 2,630 MiB. These are cumulative allocation/growth bytes,
    not simultaneously live memory or DRAM bytes. Find the largest callers and
    sizes.
29. **M — Solver and scratch accounting expose another layer of churn.** Literal
    revert requests 693 MB solver + 291 MB scratch; body requests 1,329 MB + 611
    MB. The maximum region solver live bytes rise from 11.3 MB to 185.4 MB.
    These logical counters sit inside arena allocations: do not add them to the
    backing allocator's requested bytes or sum separate maxima into a process
    peak.
30. **M — RSS high water overstates current retained memory.** Current
    post-build RSS is roughly 416–480 MiB after edits, while lifetime high water
    approaches 750 MiB. The eight revisions do not show monotonically growing
    current RSS, but they are too short to establish leak freedom or a
    long-session bound.
31. **M/H — Page churn deserves attribution.** Each edit takes 154–240 thousand
    minor faults, zero major faults and zero swap in the memory sequence. Page
    allocation/remapping/first-touch is a candidate; this is not evidence of
    disk paging. Add mapping counts and per-phase user/system CPU.
32. **C — Small-heap slabs remain mapped.**
    [session_heap](zig-native/src/runtime/session_heap.zig) uses shared
    size-class free lists and never unmaps its small slabs. This intentionally
    reuses memory across revisions. Measure per-class live/free/slab occupancy
    to separate reusable capacity, fragmentation and semantic retention before
    adding trimming.
33. **C/H — Small allocations have a global spin lock.** Every small allocation
    and free uses one heap mutex; mapping a new slab also occurs under it.
    Measure contention and spin time. Most work is currently serial, so a global
    lock in source does not establish lock contention as the bottleneck.
34. **C/H — Parallel jobs add an outer allocator lock.**
    [LockedAllocator](zig-native/src/eval/parallel_allocator.zig) does not
    classify the session heap as directly shareable, so worker backing
    allocations use an additional mutex. The inner heap already synchronizes its
    lists. Measure outer-lock time and review wrappers before bypassing it;
    private arenas limit how often workers reach this boundary.
35. **C/H — Size classes and large arena bins can overreserve.** Heap classes
    and [region arena](zig-native/src/eval/region_arena.zig) large blocks round
    sizes upward, and large-bin reuse requires an exact bin. Record requested
    versus capacity bytes, reuse and copies near boundaries; logical allocated
    bytes do not reveal this padding.
36. **C/H — Region reuse has a 64 MiB retention cliff.** The pool retains one
    available arena, discards arenas over 64 MiB and cannot lend an arena still
    in use. Record discarded capacity, active leases and newly mapped bytes
    around the large body regions before raising the cap and increasing RSS.
37. **C/M — Bump frees and growing containers create lifetime amplification.**
    Non-last small arena frees do not reclaim space until reset. Reallocation
    can leave old capacity behind. Copy/zero primitives account for about
    3.3–6.4% self CPU across the split profiles; callers include Session
    initialization, evidence interning, collection and worklist frontiers.
    Attribute bytes and old-buffer lifetime before scattering reserves or larger
    scratch buffers.

#### Representation and cache policy

38. **C/H — Dense type nodes are already compact.** Nodes remain 16 bytes with
    closedness metadata in padding. A 185 MB live solver is larger than shared
    L3, but its active working set may be much smaller. Measure hot arrays and
    reuse distance before changing layout, splitting fields or compressing IDs.
39. **C/H — Tiny caches have unmeasured collision costs.** Closed-row
    certificates have four direct-mapped slots, operation normalization has 64,
    and composite resolution certificates have 16 entries with eight frontier
    dependencies. Add hit/miss/collision/decline counters and key cardinality;
    capacity alone cannot fix an epoch mismatch or unsupported dependency.
40. **C/H — Conservative epoch invalidation can erase useful work.** The
    operation cache requires exact type/effect mutation epochs, cursor, depth
    and limit. Physical rollback also invalidates graph certificates. Count
    invalidation causes and unchanged dependency frontiers before trying finer
    validity rules.
41. **C/H — Resolution-cache growth may allocate on an update.**
    [epoch_resolution_cache](zig-native/src/reuse/epoch_resolution_cache.zig)
    checks its 75% growth threshold before searching for an existing key. At the
    threshold, updating a key can therefore grow the table unnecessarily. Count
    this case; the direct optimization is worthwhile only if it occurs
    materially.
42. **M — Retained metadata copies remain measurable traffic.** The literal edit
    records 7.59 MB snapshot copies and 10.48 MB copied metadata versus 0.40 MB
    shared metadata. Attribute ownership reasons field by field; these counts
    are far smaller than total backend traffic and are not the first target.
43. **M/C — Reuse admission costs more than fragment replay.** Later literals
    spend about 361 ms in lookup and 56 ms in replay. Structural anchor matching
    appears in the CPU profile; constants take another roughly 172 ms under a
    separate scoped clock. Measure repeated anchors/graphs and decline reasons;
    keep exact comparisons after hashes and do not sum overlapping clocks.

#### Backend, measurements and compiler development

44. **C/M — Parallelism starts after much semantic work.**
    [runtime_parallel](zig-native/src/backend/runtime_parallel.zig) optimizes
    completed immutable functions and optionally plans reference counts. It uses
    a dynamic atomic job index and a minimum-work threshold. Semantic component
    job counters are zero in these builds. More inference parallelism requires
    dependency-ready jobs and publication ownership, not just a worker flag.
45. **M/C/H — Backend workers still copy and optimize some bodies.** SROA is
    1.60% self CPU in the literal pair. Workers optimize in private arenas,
    clone outputs and may analyze reference counts even for reused bodies.
    Measure optimized/reused instructions, clone bytes, worker imbalance and
    joins before increasing parallelism or retaining more optimized state.
46. **M/C — Assembly and output work remain on changed builds.** Assembly is
    roughly 177–187 ms in representative samples. The game Wasm is about 5.23
    MB; publication and client transport return a complete byte buffer. Separate
    encoding, relocation, output duplication and transport before pursuing
    patches or incremental linking. No-op output reuse is already cheap.
47. **M — Inputs are still visited on every revision, but cheaply.** The
    retained attempt reports 189 canonical/source reads and 1,416 resolutions.
    Input and asset phases total around 10 ms on edits. Preserve snapshot
    correctness; optimize this after second-scale work, not before it.
48. **M/C — Allocation profiling lacks ownership and net live memory.** Current
    phase counts record requested bytes and allocation calls; their RSS growth
    comes from lifetime high water. Nested backend clocks overlap. Add logical
    live/peak bytes by owner, arena backing capacity and per-phase CPU before
    treating the phase report as a heap or CPU profile.
49. **M/H — Hardware counters still need localization.** We now have trustworthy
    event availability and unscaled aggregate user-thread counts. We still lack
    phase/call-site instructions, verified cache-level events, memory latency,
    bandwidth, TLB misses and stall attribution. Collect those only for a
    bounded hypothesis; generic cache misses do not justify a wholesale
    data-layout rewrite.
50. **M historical — Compiler development has a different critical path.** The
    last qualified development cycle took 26.05 s (3.59 s compiler build, 6.90 s
    native-suite compilation); the final full gate took 623.68 s and release
    build 191.29 s. These were not rerun for this analysis. Preserve Safe/noLLVM
    builds and runtime test selection; attribute exhaustive test execution and
    the next necessary LLVM release independently. See
    [build hills](BUILD_HILLS.md).

### Recommended next experiments

| Order | Bounded experiment                     | Measurement needed before changing behavior                                                                                         | Success signal                                                                             |
| ----- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 1     | Remove repeated semantic work          | First exact source-admission mismatch for four body regions; top residual query keys and equivalent inputs after all principal hits | Fewer regions/scopes/nodes and retired instructions, with exact fresh/error parity         |
| 2     | Reduce row/interner/worklist work      | Operation-chain lengths; label/argument visits; cache miss reasons; frontier overflow; wake fanout and no-progress attempts         | At least 10% edit CPU reduction in a paired experiment, without larger unbounded retention |
| 3     | Fix first-edit frontend expansion      | Which interface/storage comparison changes; 22-module versus 1-module allocation attribution                                        | 25% fewer check allocations and 20% less checking time; later edits remain fast            |
| 4     | Reduce allocation and scope-scan churn | `shareLexical` scanned/matched counts; arena discard/bin statistics; heap class occupancy, mapping and sampled lock time            | Fewer bytes, faults or instructions with measured whole-build benefit and bounded RSS      |
| 5     | Lower the remaining literal floor      | Lookup candidate/anchor repeats; optimization clone bytes; assembly, output copies and worker time                                  | Faster non-inference path, with separate CPU/wall and unchanged-output controls            |

Start with opt-in counters accumulated per region and bounded top-K summaries,
not a log entry on every type visit. Add cache-hit reasons and useful-work
ratios before expanding cache capacities. Trace only the first exact mismatch
per missed principal result. A short long-session memory run with new edits is
still needed before changing retention limits. CPU counter reads should be at
phase/region boundaries, with profiling overhead checked again.

Keep seven alternating release pairs for an optimization decision, a frozen
manifest, both literal and body edits, several unseen edits, and devtools as a
control. Record CPU, instructions, wall and current/peak RSS separately.
Preserve fresh-output parity and semantic rejection/recovery tests; the required
full native/guest gate and zero Zig lint still apply to compiler changes. Stop
an approach after two bounded misses and retain its negative evidence.

### Evidence and scope

Raw evidence and diagnostic scripts are in
[`performance-audit-2026-10-24.tar.gz`](zig-native/measurements/performance-audit-2026-10-24.tar.gz).
Its
[SHA-256 sidecar](zig-native/measurements/performance-audit-2026-10-24.tar.gz.sha256)
pins 53 files in a 1,330,861-byte archive. The archive includes pins, commands,
host metadata, phase samples, raw GDB stacks, per-build CPU attribution,
eight-revision memory/thread samples, hardware-counter samples, output hashes
and analysis scripts. It excludes workload source, compiler binaries and
generated Wasm. Local working output is
`build/bench/performance-audit-20261024/`.

The fresh/retained benchmark checks byte-identical Wasm against recorded
controls. The memory and PMU sequences check every output against the earlier
CT103 unseen edit series, which also checked fresh compilations. No new compiler
source or semantic tests were added, and no qualification claim is made from
these measurements. Historical comparisons below retain their original pins and
scope.

## CT103/CT104 qualification summary

Historical outcome, 24 October 2026:
[CT103/CT104 implements all four selected changes](zig-native/CT103_QUALIFICATION.md).
Seven alternating pairs against exact `5412320` reduce literal-edit CPU by
24.8%, body-edit CPU by 4.2% and fresh-game CPU by 6.1%; devtools is essentially
unchanged. Literal reuse rises from 18 to all 20 principal results, with one
nonempty result and 4,400 completed-summary publications. Body reuse rises from
15 to 16, leaving four fresh regions. Source, dynamic-input, ownership and
bounded importer checks remain in force. Portable archives still require the
complete source image; only retained reuse admits exact consumed declarations.

The combined cache/reuse measurement meets the literal 20% target but misses the
body 20% target. The 64-slot row-cache simulation covered 12.55% of label
visits; that is diagnostic evidence, not an isolated CPU speedup for the cache.
Shared-host body wall median worsens (10.86 → 12.46 s), so report CPU and wall
separately. The profiled pair also crosses a large load change; its body phase
ratio is not evidence of a 54% causal speedup.

The next measured bottlenecks are the four body-edit regions and inference
outside principal replay. The three largest body regions still collect about
1.83 million, 0.94 million and 0.61 million nodes; their inputs are recorded
now, but they still fail the source-admission checks. Literal builds have no
fresh principal regions, yet ordinary entry/closure queries still revisit tens
of thousands of nodes. Reusing principal results alone does not eliminate that
later work. A clean sequence of three unseen literal and three unseen body edits
matches both compilers and fresh controls. Later literals take 2.96–3.18 s
total, including 1.48–1.51 s inference and 63–67 ms frontend checking. Body
edits take 6.20–7.62 s, including 4.57–6.47 s inference. These are single
profiled observations, not a latency distribution. First-edit checking still
costs about 0.9 s; CT100 needs its own allocation attribution. Keep constants
deferred until their measured share justifies the work.

Next, trace which exact declarations invalidate the largest body regions and
which summary/body queries repeat after all principal hits. Bound an experiment
before widening admission; require changed-callee/type/effect errors, recovery,
owner translation, full allocation failures and byte-identical fresh controls.
Keep the body 20%, four/two-second and sub-second targets open. Do not combine
ratios from different historical intervals into a claimed cumulative gain.

The final installed build includes the concurrent `faf3f78` callback/diagnostic
commit and the portable-summary output fix, with its own complete qualification
and strict output screen. Performance percentages above belong to the pinned
`5412320` comparison.

## Historical CT102 analysis

[CT102 is qualified](zig-native/CT102_QUALIFICATION.md). Seven alternating pairs
show **25.1% less retained literal-edit CPU** against CT97. The first saved call
proof rejection was a depth bound (128), with 999,809 work units still available;
the proposed shared-graph work-budget fix was therefore removed. Keeping the
independently admitted empty result while omitting unsupported optional memo
outputs removes the largest rebuilt literal-inference region. The original
source, input, type/depth and executable checks stay in force.

The single matched phase comparison measures literal inference at 5.22 → 3.20 s
and backend time at 6.77 → 4.76 s. Two large principal regions remain (0.955 and
0.493 s), and other inference work remains too. The body edit still runs the
three large regions and takes about 5.13 s in inference. Its image has changed;
CT102 provides no new body-source admission. The six projected decline counters
now distinguish unsupported results, missing recordings, changed inputs/images,
wrong owners and failed import preparation.

Prioritize CT103's remaining principal result/input boundary and CT104's residual
inference profile for ordinary iteration. A nonempty result needs owned type/row
translation; a region that consumes earlier call proofs needs an exact recorded
input key. Neither can be inferred safe merely from unchanged surface types.
Keep changed-type/effect/catalog failures and ordinary fresh checking as oracles.

Frontend checking needs a separate first-edit investigation: the first literal
edit takes 0.918 s and 6,553,820 allocations, while subsequent revert/body checks
take about 0.07 s. A separate diagnostic sequence of three unseen literal values
confirms 74 / 70 ms checking on its second/third edits, with 156,683 allocations.
Those rebuilds take 4.98 / 4.67 s wall, including 3.33 / 3.12 s inference, and
match both the baseline and fresh edited outputs exactly. This single profiled
sequence establishes the distinction for that body, not a latency distribution
or general body-edit claim. Constants (0.217 s), lookup (0.420 s) and replay
(0.068 s) are smaller measured costs; these scoped clocks must not be added to
overlapping inference/region clocks.

A CPU-weighted candidate profile of one literal edit and revert covers 99.69%
of process CPU across 1,364 complete intervals, with no missing or truncated
stacks. `resolveOperationRow` and `closedHeight` account for 7.04% and 6.00% self
CPU. `ClosureRegion.bodyEvidenceMode` accounts for 40.14% inclusive CPU; inclusive
rows overlap. Count repeated queries and attribute their callers before choosing
a bounded type/row cache. The unweighted report includes idle worker stacks;
use the archived `cpu-report.json` for this attribution.

Sub-second ordinary edits are not achieved. Candidate literal/body wall medians
are 5.93 / 6.83 s in the seven-pair run, with broad shared-host ranges. The
completed full gate and raw measurements are linked above. The dated reviews
below explain earlier decisions and are historical evidence.

Follow-up, 24 October 2026:
[CT97 and the reuse/scratch changes are qualified](zig-native/CT97_QUALIFICATION.md).
Seven alternating release pairs reduce fresh game CPU by **32.5%** against CT96;
median build wall falls from **13.60 to 8.68 s**, with identical Wasm. Inference
falls 9.93 → 6.23 s under matching instrumentation. The executable index
saturated at 4,096 records; its separate bounded capacity restores thousands of
hits. Literal/body edits use 40.7% / 43.1% less CPU and take 7.63 / 6.56 s
median wall. The 50% edit-CPU and four-second wall targets remain open. The
three slow laws now execute 37,930 exhaustive scenarios. Their timing target
remains open. Next, attribute the three large principal-region rebuilds and the
remaining frontend allocations. Keep exact source/input/replay checks;
executable index capacity is no longer the observed blocker. The dated analysis
below preserves the evidence that selected these experiments.

Review of `c5b9ad1`, 23 October 2026. **Start with CT97's effect-row traversal,
then CT98's retained executable reuse.** For compiler iteration, prioritize
BT4's allocation-heavy backend sweeps. Ordinary compiler edits already build in
about 3.4 s; the full native test run takes 665 s.

This review adds caller attribution, source inspection and a new diagnostic run
of the three slowest exhaustive laws. It implements no further optimization. The
[CT96 qualification](zig-native/CT96_QUALIFICATION.md) remains the throughput
baseline: seven alternating release pairs, game median **12.25 s CPU / 12.16 s
wall**, devtools **0.70 s CPU / 0.68 s wall**, and identical Wasm. Retained edit
figures below are one screening pair, not a statistically established speedup.

| Priority | Hill                            | First experiment                                                                                                                                                              | Acceptance target                                                                                                              |
| -------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| 1        | CT97: effect-row traversal      | Count replacement hops, cache misses/bypasses and repeated row/cursor queries in the largest inference regions; choose a bounded traversal or cache change from those counts. | At least 10% less whole-build CPU and 25% less inference wall against CT96, measured separately with matching instrumentation. |
| 2        | CT98: retained executable reuse | Count each rejection before the existing backend candidate counter, including incomplete indexes, origin, blocked jobs, argument matching and dependencies.                   | Literal/body edit CPU down at least 50%; then edit wall below 4 s.                                                             |
| 3        | BT4: exhaustive test work       | Profile allocations and backend phases in the two deep-path emission fixtures; reduce real compiler allocation/work without dropping fault coverage.                          | Halve the combined top-three law cost and measure at least 5% less whole-gate wall time.                                       |
| 4        | CT100: frontend allocation      | Attribute the 7.65 million check allocations after CT97, which may affect both frontend and backend.                                                                          | At least 25% fewer check allocations and 20% less check wall, without whole-build CPU regression.                              |

These are acceptance thresholds, not forecast gains. Preserve the
[compile queue](COMPILE_HILLS.md) and [build queue](BUILD_HILLS.md) identifiers.
After two bounded candidates miss a hill's whole-build target, record the
negative result and move to the next measured cost.

## CT97: the expensive getter is already inlined

Two post-CT96 CPU profiles cover 1,011 complete intervals and 99.29% of process
CPU, with no missing or truncated stacks in those intervals:

| Self attribution                  | Combined sampled CPU | Range across two runs |
| --------------------------------- | -------------------: | --------------------: |
| `effects.Store.node`              |               15.88% |          15.66–16.11% |
| `effects.Store.replacement`       |               11.55% |          11.54–11.56% |
| `types.Store.resolveOperationRow` |                5.10% |            4.87–5.32% |
| `types.Store.closedHeight`        |                4.69% |            4.06–5.34% |

Every sampled `node` and `replacement` leaf is an inline frame. The qualified
release also has no standalone symbol for either function. Adding `inline`
therefore has no demonstrated call overhead to remove.

All sampled `node` self CPU comes from `resolveUncached`: **99.08%** is at the
load of a replacement row, and 0.92% at the initial root load. All sampled
`replacement` self CPU is in that same resolution loop. In both cases the next
outer caller is `types.Store.resolveOperationRow`. Approximately 73% of
replacement self CPU is under the zero-cursor cache-miss path; 27% is under the
cache-bypass path. These percentages weight sampled CPU, not query counts or
cache hit rates. They do not establish cache-line misses or long version chains.

The largest recorded region, `game.blot` offset 18479, has 33,828 scopes and
1,832,134 solver nodes. Its lifetime is 5.23 / 5.43 s in the two profiles,
beside 10.36 / 10.62 s of total inference phase time. The next regions are
offsets 9040 (1.16 / 1.19 s) and 18633 (0.54 / 0.53 s). Region lifetimes are
inclusive; do not add them to phase clocks or sampled CPU. This identifies where
to collect the next counters without claiming that the stack samples belong to
one region.

The [effect store](zig-native/src/check/effects.zig) gives two distinct
hypotheses:

1. `replacement(variable, at)` starts at the variable's first version and finds
   the first write whose position is **at least** the requested cursor. Count
   versions visited per lookup, successful/missing lookups and last-version
   rejections. If misses repeatedly walk old versions, try a constant-time
   last-position rejection; if successful searches dominate long histories,
   investigate a bounded successor index.
2. `resolve` caches only zero-cursor queries and invalidates on mutations. Count
   row-chain length, repeated `(root, cursor)` queries and invalidations by
   region. If repeated chain walks dominate, investigate bounded memoization
   with an explicit chronology/epoch key before changing row representation.

Use opt-in aggregate counters and bounded histograms, with no clock read or
allocation per lookup. Do not mistake a high self sample at a load for proof of
either hypothesis. Preserve the first-successor semantics, advancing cursors,
rollback, recycled IDs, saturated epochs, independent effect rows and work
budgets. A conventional latest-preceding-version lookup would be incorrect.

Halving the combined 27.43% self cost suggests about **13.7%** total CPU
headroom if the rest stays fixed. That is a prioritization estimate, not a
prediction. Even removing all of that cost would leave roughly **8.89 s** from a
12.25 s baseline, so CT101's below-8 s goal requires additional improvements.
These estimates cannot be added to overlapping inference or constant clocks.

## CT98: semantic reuse works; executable admission needs a rejection trace

The candidate's literal edit takes 11.51 s CPU / 11.36 s wall; the body edit
takes 10.90 s CPU / 10.76 s wall. Both report one fresh module, 188 cached
modules, zero backend candidates and fresh emission of 4,266 named functions
plus 1,424 closures. No-op and cached restart remain about 19 and 26 ms wall.

However, the literal edit also reports **17 principal hits, 145 reused
specialization queries, seven constant receipts and one shared semantic gate**.
Rebuilding the dependency seed does not by itself suppress the previous backend
owner: [retained_revision.zig](zig-native/src/reuse/retained_revision.zig) still
passes it when settings match.

The `candidates` increment in
[artifact_fragment.State.find](zig-native/src/reuse/artifact_fragment.zig)
occurs only after checking enabled state, complete query index, fingerprint
bucket, translated origin, blocked job, argument match, inline bodies and static
reads. Thus zero candidates does **not** establish an empty offer or a hash
miss. The present evidence cannot name the first blocking check.

Add a bounded reason counter at each of those checks and the earlier
sealed-emission/pool gate in
[CompileRun.prepareReuse](zig-native/src/backend/core_backend.zig). Record
aggregate old query/job counts and incomplete-publication reasons too. Compare
population, edit, revert and restart before changing admission. Preserve exact
body/value/namespace checks and fail-closed publication. Validate the recovered
reuse with seven unprofiled edit pairs and fresh-output controls; semantic hits
alone do not satisfy this hill.

## BT4: target backend allocation, not another round of fixture hoisting

The successful CT96 gate executes 2,539 exhaustive native laws in 664.89 s
(665.13 s including the enclosing native phase). Its four shards contain 627.92,
664.68, 659.37 and 623.08 s of individual test wall time. Holding those costs
fixed, perfect balancing would take at least 643.76 s: only **3.18%** less
native wall. That model ignores changing contention and scheduling overhead.

The existing `-Doom-profile=true` mode was built from the isolated qualified
source with Zig 0.17.0, Safe/noLLVM. Runtime selection ran the following three
laws concurrently, with **full** allocation faults. All passed, without leaks or
logged errors. These instrumented times have different load from the gate and
must not be used as a before/after comparison.

| Law                       | Qualified gate wall | Sweeps | Discovered allocation positions | Scenario runs | New profiled sweep wall sum |
| ------------------------- | ------------------: | -----: | ------------------------------: | ------------: | --------------------------: |
| Generic typed paths       |             87.35 s |      5 |                           9,694 |         9,699 |                     99.21 s |
| Retained State callables  |             80.51 s |      8 |                          12,324 |        12,332 |                     94.75 s |
| Request backend ownership |             73.92 s |     20 |                          22,023 |        22,043 |                     84.30 s |

Each sweep includes one successful discovery run and one attempt per discovered
allocation position: **44,074 scenario runs** overall. Normal full-gate
`discovered_allocations=0` counters are unpopulated in this mode; they do not
mean the tests allocated nothing. The separate sweep profiler supplies the
counts above.

The two deep-path emission fixtures account for **81.11 s, about 82%** of the
path law's profiled sweep time. They discover 2,783 and 3,097 allocation
positions. Its evaluator sweep takes only 0.12 s and its explicit frontend sweep
9.77 s. In the State law, `local-initializer-effects.blot` accounts for 27.11 s
and 2,365 positions. The request law spreads work over 20 fixtures;
`f32-foreign-nested.blot` is the largest at 11.80 s and 1,862 positions.

The [path](zig-native/src/backend/structural_record_tests.zig),
[State](zig-native/src/reuse/retained_capture_tests.zig) and
[request](zig-native/src/backend/request_backend_tests.zig) tests already lower
their backend inputs outside the emission fault sweeps. The path test also
already separates its ordinary full matrix from smaller ownership fixtures.
Moving that setup again cannot recover these costs.

Profile one successful backend attempt for each deep path, then count scratch
growth, copied graphs and repeated analysis before proposing a representation
change. Fewer real allocations can reduce both compiler work and the number of
required fault attempts; every allocation in the new implementation must still
be injected. Keep the private-call boundary, effect-bearing captures,
type-changing storage, frozen-Core checks and the explicit frontend sweep. Do
not skip indices, reduce assertions or introduce artificial allocator batching
merely to shorten the tests.

The three laws sum to 241.78 s of shard work. Even eliminating them entirely
would leave a fixed-cost ideal four-shard floor of 583.32 s. BT4's eventual 480
s target therefore needs broader reductions after this first experiment. Keep
ordinary caching: prior three-cycle measurements show no useful real-edit gain
from `-fincremental`. Collect 20 real development cycles before making a p95
claim; the measured 4.64 s warm and 14.54 s edited checks are individual
observations.

## Lower priorities and validation

CT100 remains measurable: frontend checking requests 1,076,452,150 bytes in
7,651,848 allocations in each new profile and takes 1.29 / 1.32 s under
sampling. Requested bytes are cumulative, not live memory; whole-build peak RSS
is about 476 MiB in the unprofiled release pairs. Attribute those allocations
after CT97 to avoid overlapping claims.

CT99 stays deferred: constant preparation is about 0.33 s, below its 10%
eligibility threshold. Assembly is about 0.20 s, so additional codegen workers
are a low priority. BT5's actual LLVM release build takes 204 s and overlaps the
much longer native gate; collect its detailed time report on the next necessary
release rather than rebuilding merely to chase the gate's noncritical path.

For accepted compiler changes, retain exact Wasm, fresh/edit/revert/restart
controls, both game and devtools, seven alternating unprofiled pairs, at most 5%
CPU regression on unaffected workloads, the full compiler gate and zero Zig
lint. Profiled timing selects work; unprofiled timing accepts speedups. No new
compiler source changed for this review, so the existing full qualification was
not repeated. The new three-law diagnostic run completed all 33 full sweeps.

## Evidence and reproduction

The [derived report](zig-native/measurements/post-ct96-review-2026-10-23.json)
pins every consumed input and reconciles the caller totals with the original CPU
report and the complete native inventory. Its inputs are the existing
[CT96 archive](zig-native/measurements/ct96-spawn-scan-2026-10-23.tar.gz) and
the new
[sweep evidence](zig-native/measurements/post-ct96-oom-2026-10-23.tar.gz), which
includes commands, Zig version, profiler binary hash and raw logs. No private
application source or compiler executable is included.

The new sweep archive's SHA-256 is
`65d989ea5bfd02a0490f6204f4180664d02a62ce8765e3c8b1625b9750d68e73`.

Extract each archive into its own directory, verify its `SHA256SUMS`, then run:

```sh
python3 scripts/bench/review_performance.py CT96_DIRECTORY OOM_DIRECTORY report.json
```

The [review script](scripts/bench/review_performance.py) needs only Python's
standard library and the archived evidence. It checks 1,011 sampling intervals,
the exact 2,539-law inventory, successful full-fault results and each sweep's
allocation/run counts before writing the report.
