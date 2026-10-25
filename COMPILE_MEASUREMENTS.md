# Compile and compiler-build measurements

CT116 is correctness-qualified on its frozen candidate. Whole profiled frontend
falls from 1.600 to 1.036 s, checking from 1.214 to 0.649 s; fresh unprofiled
game wall time falls from 7.594 to 7.050 s in three alternating pairs. Ordinary
edit latency is not meaningfully improved. See
[the report](zig-native/CT116_QUALIFICATION.md). Independent module checking
defaults to four workers; retained edits keep their existing path. Canonical
imported graphs and repeated import preparation remain architectural targets.
The backend still dominates full builds. Eighteen public Blot/Rust
compile/runtime workloads and measured README tables expose substantial runtime
gaps in text and list pipelines; those need their own runtime profiles.

## CT115 module costs and parallelism model (25 October 2026)

Three instrumented release traces measure 1,296 ms of module-check CPU across
189 modules: 325 ms headers, 818 ms bodies and 153 ms other module work. These
are sums of per-module medians. `game.blot` takes 447 ms and selects 587,596 of
641,867 generic-requirement candidates (91.5%). Its builder composition is the
strongest lead for repeated generalization, pending finer attribution.

A separately verified topology probe records 1,604 edges. The critical chain
costs 797 ms; a ready-task model estimates checking at 896/798/797 ms for 2/4/8
workers. With other frontend costs, four workers estimate 1.238 s total. These
are optimistic models, not actual parallel compiler measurements. The
literal/body edits check one module and spend 133/139 ms in the frontend.

All seven release outputs and the topology output match strict Wasm pins.
Production source and installation are unchanged. See
[the detailed review and evidence](COMPILER_BIG_LEVERS.md) for source pins, CPU
attribution, counterfactual targets, SIMD limits and model assumptions.

## CT114 frontend implementation (25 October 2026)

The profiled fresh frontend median is 1.872 → 1.784 s; checking is 1.421 → 1.344
s. Checker allocation requests fall 27.0% and requested bytes 17.6%. Unprofiled
whole-build measurements do not establish a latency improvement. The final
candidate passes the frozen full compiler gate and strict fresh/edit/revert
output controls. These profiled clocks are separate from unprofiled whole-build
performance; allocation accounting itself has overhead. The frontend remains
above one second. See
[the exact-candidate report](zig-native/CT114_QUALIFICATION.md) for all paired
clocks, allocation counters, qualification scope and limitations, and
[the architecture review](COMPILER_FRONTEND_REVIEW.md) for the remaining work.
CT110 remains installed.

## Fresh frontend and Baba review (25 October 2026)

The initial CT114 investigation measured the unchanged CT113 release; the later
implementation is recorded in [the work log](COMPILER_CT114_WORK.md). The
existing CT113 phase profile separates these fresh gdev costs across 189 modules
and 239,697 syntax nodes:

| Phase                               | Profiled wall time |
| ----------------------------------- | -----------------: |
| Load source                         |               6 ms |
| Lex                                 |              23 ms |
| Parse                               |              13 ms |
| Check                               |           1,277 ms |
| Lower                               |             138 ms |
| Freeze                              |              82 ms |
| Validate                            |             112 ms |
| Assets, input bookkeeping and other |              26 ms |
| Total before backend                |           1,678 ms |

These are one instrumented build's exclusive phase times, not unprofiled
medians. Literal/body edit frontend totals are already 124/118 ms. Parsing and
lexing together account for 36 ms, about 2.2% of the fresh frontend. With the
other phases fixed, checking must fall to about 599 ms (53% less) for the whole
fresh frontend to fall below one second. This does not make the complete build
or ordinary edits sub-second; backend inference remains the larger cost.

Two new GDB runs sample the frozen CT113 binary against the same manifest.
Per-thread CPU deltas weight complete intervals inside each build, excluding
idle threads and four boundary intervals. Coverage is 16,046.5/16,100 CPU ms
(99.67%), with no missing or truncated stacks. Both Wasm outputs match the
existing strict fresh-game pin. The debugger changes timing: use these samples
for attribution, not latency comparisons. Restricting stacks to
`reuse.project_check` prevents backend uses of the same checker from entering
the frontend attribution.

| Operation                                               | Inclusive share of project-check CPU |
| ------------------------------------------------------- | -----------------------------------: |
| Check module bodies                                     |                                60.1% |
| Collect headers, including imports                      |                                28.1% |
| Construct generic schemes (`schemeInto`)                |                                27.1% |
| Gather pending scheme requirements (`schemeCandidates`) |                                23.9% |
| Import schemes (`importScheme`)                         |                                23.2% |
| Resolve type graphs                                     |                                29.8% |
| Find free type variables                                |                                16.3% |
| Find free effect-row variables                          |                                12.7% |
| Capture retained checked bodies                         |                                 8.0% |
| Allocation/free paths, including profiling accounting   |                                11.7% |

Rows overlap; do not add them. The phase counter records 7,636,643 allocation
requests and 1,078,511,978 requested bytes during checking. Requested bytes are
allocation traffic, not live memory. Neither allocation count nor sampled
allocator cost proves a memory-bandwidth bottleneck. No hardware-counter
measurement was made. Profile accounting also adds overhead.

The sibling Baba work uses cached immutable lexer tables, compact token records,
shared parser analysis, lazy token/cursor materialization and direct incremental
record transfers. Blot's TypeScript syntax tooling already uses Baba
(`compiler/syntax.ts`); the native compiler uses its own Zig lexer/parser.
Baba's `validate()` is syntax validation, not Blot's semantic/Core validation
phase. Its workload-specific speedups do not transfer directly to gdev.

The useful architectural transfer is sharing analysis and delaying copies.
Prioritize measuring scheme-candidate rescans and graph visits per owner, then
avoid recomputing unchanged free-variable sets under exact solver history.
Measure imported versus actually used interfaces before introducing lazy scheme
materialization or shared immutable interface graphs. Fresh quantified variables
must remain private to each importing solver; preserve diagnostics, coherence
checks, chronological cursors, rollback and allocation-failure laws.
Whole-project counters are needed: `stats.frontend` alone describes the entry,
whereas `attemptStats.fallback` exposes aggregate module/body counts. No parser
replacement or checker optimization is implemented by this investigation.

Raw evidence and reproduction scripts are in
`zig-native/measurements/ct114-frontend-review-2026-10-25.tar.gz`; the local run
directory is `build/bench/ct114/frontend-sampling`. It includes the phase
inputs, strict output pins, CPU summaries and sampled stacks. Run
`python3 summarize_frontend.py .` inside its `sampling` directory to regenerate
the scoped report. CT110 remains installed; existing CT113 qualification and the
concurrent array-work exclusions are unchanged.

Archive SHA-256:
`acb75abf7d20fce388954334d41352eb40fd4f57bebf16b156a360a3e7149d38`. All 16
archived member hashes and 559 sampling input pins were verified.

## CT113 release screen

The [CT113 release screen](zig-native/CT113_QUALIFICATION.md) measures a modest
fresh-build improvement: 7.546 → 7.078 s, median paired CPU -5.21%, with all
three fresh pairs improving. Literal edits are 3.008 → 2.991 s and body edits
5.172 → 5.217 s; their CPU differences are small and no edit-time improvement is
established. All 60 samples, strict Wasm pins, fresh controls and CPU guards
pass. The larger bounded cache saves 4,513 fresh regions and retains 4.82 MiB
more cache storage. First-edit peak RSS rises about 4.4 MiB. The frozen full
gate passes 2,587 exhaustive native laws, 1,660 release guests, 48 smoke tests
and 57 tooling checks; selected Zig lint has zero findings. CT110 remains
installed. The request census and failed proof-recovery trials are recorded with
the measurements.

The following CT112 figures describe the preceding experiment.

The [CT112 screen](zig-native/CT112_QUALIFICATION.md) preserves completed
selected-closure proofs across revision replay. Three pairs against CT111
measure literal/body wall medians of 2.863/4.754 s (paired CPU -2.4%/-9.5%), but
fresh CPU rises 4.4% and the deterministic reduction is only nine/five regions.
These screening timings do not establish a repeatable speedup. Peak RSS is
essentially unchanged. The frozen full gate passes 2,586 exhaustive native laws,
1,660 release guests, 48 smoke tests and 57 tooling checks in 723.99 s; selected
Zig lint has zero findings. CT110 remains installed.

The following CT111 figures describe the preceding experiment.

The [final CT111 screen](zig-native/CT111_QUALIFICATION.md) passes correctness
qualification but establishes **no performance improvement**. Three alternating
release pairs measure fresh/literal/body medians of 7.900/3.151/5.294 s versus
CT110 7.779/3.122/5.229 s. Paired CPU rises 1.5%/0.6%/1.5%; peak RSS is
essentially flat to slightly higher. Exact outputs, independent fresh controls,
input pins and fresh CPU guards pass. These are shared-host screening results.

The final gate passes 2,584 exhaustive native laws, 1,659 release guests, 48
smoke and 57 tooling checks. Selected Zig lint has zero findings. The profiled
body edit still misses three principals and starts 534 lowering inference
regions. Stop extending inferred-interface shortcuts. Completed elaborated
bodies and the expanded development generic ABI remain unimplemented; none of
the five architectural recommendations is complete. CT110 remains installed.

The
[25 October architecture review](COMPILER_ARCHITECTURE_REVIEW.md#development-tier-and-semantic-worker-screen)
adds a 115-build screen of the unchanged CT110 release. Three alternating
default-policy rounds measure optimized/development literal medians of
2.637/2.504 s and body medians of 4.407/4.365 s. Both tiers retain the same
inference-region counts and principal misses. Separate explicit-component runs
do not establish a four-worker improvement. This screening evidence is distinct
from the seven-pair qualification below; input/output controls, clock scopes,
host-noise limitations and raw archive are linked from the review.

The [CT110 qualification](zig-native/CT110_QUALIFICATION.md) passes seven
alternating release pairs against CT109, exact outputs, fresh CPU guards and the
complete compiler gate. Paired CPU falls 2.9% fresh, 4.4% on literal edits and
3.0% on body edits. Wall medians are 7.335 / 3.034 / 5.035 s respectively.
Literal/body reverts improve 4.6% / 3.8%; devtools remains within its guard.

Sharing immutable effect lists and their proofs removes 86% of literal-edit
operation visits. Inference still opens 2,934 literal / 7,216 body regions, and
body principal hits stay 17/20. Peak RSS is effectively flat. The report
separates these work counts from latency, allocation requests and retained
memory. Two-second and sub-second ordinary edits remain open.

The final selected development cycle takes 25.54 s (99 native laws, 56 guests,
complete 2,576-law native compilation). Full qualification executes all native
laws with exhaustive faults, plus 1,656 guests, 48 smoke and 57 tooling tests;
final Zig lint has zero findings. A cache-writer cleanup race in a guest fixture
is fixed without changing compiler behavior or assertions. See the work record
for the failed run and exact verified native resume.

Historical CT109 qualification, 24 October 2026:

The [CT109 qualification](zig-native/CT109_QUALIFICATION.md) passes seven
alternating release pairs against CT106, exact outputs and the full compiler
gate. Paired CPU changes are first literal -0.6%, literal revert -11.5%, body
-2.5% and body revert -7.5%; fresh game/devtools remain within the 5% guards.
First-literal/body wall medians are 3.261/5.377 s. Reverts improve, while the
ordinary-edit, two-second and sub-second targets remain open.

The candidate passes 2,573 exhaustive native laws, 1,656 guests, 44 independent
held-out Wasm executions and 232 requests over 200 distinct edits. Post-session
RSS is 521 MiB. The [86-item ledger](COMPILER_CT109_LEDGER.md) records
implemented work, rejected experiments and still-open architectural designs. The
qualified CLI and native compiler are installed locally; raw evidence and limits
are linked from the qualification record.

Historical CT106 qualification, 24 October 2026:

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
suggestions have a [disposition](COMPILER_CT106_WORK.md); conditional
alternatives and unfinished architectural work are explicit.

Historical CT105 diagnostic review, 24 October 2026:
[post-CT105 CPU, memory, algorithm and architecture review](COMPILER_REVIEW_CT105.md).
Three profiling-off/on pairs of the same installed release measure unprofiled
wall medians of 6.878 s fresh, 3.786 s first literal, 2.580 s literal revert and
4.816 s body edit. CPU-weighted stacks, five eight-state memory cycles and a
targeted graph-size probe are archived with source/binary pins. All outputs
match strict existing hashes. This is a review of unchanged `a0645de`, not a new
optimization comparison, compiler build measurement or qualification.

Historical CT105 qualification, 24 October 2026:
[CT105 solver scans, normalization and catalog costs](zig-native/CT105_QUALIFICATION.md).
Seven alternating pairs against `5cfb411` show **13.3% less fresh-game CPU**,
**12.9% less body-edit CPU** and **3.3% less first-literal CPU**, with exact
Wasm and unaffected devtools. The 10% literal target misses; sub-second edits
remain open. Shared-host wall medians are 8.33 s fresh, 4.16 s first literal,
3.10 s literal revert and 5.42 s body edit. The report includes distributions,
source and binary pins, phase/work counters, memory costs, unseen/fresh/restart
controls and the full gate (674.30 s). Final native/CLI installation is
verified.

The matching profiled pair reduces fresh inference from 5.760 to 4.648 s and
body inference from 4.051 to 3.356 s; literal-revert inference remains 1.259 s.
Dense row certificates remove repeated arguments while adding solver-local
memory: largest region live bytes rise 185.37 → 195.25 MB. Current RSS, lifetime
peaks and logical allocation requests are reported separately. The 21.28 s
Safe/noLLVM development cycle includes 3.31 s compiler and 5.91 s full native
compilation. These are observations, not paired build gains or p95. Historical
numbers below preserve their original scope.

Pre-CT105 diagnostic refresh, 24 October 2026:
[CPU, memory and algorithm audit](PERFORMANCE_REVIEW.md#current-cpu-memory-and-algorithm-audit--24-october-2026).
The then-installed unchanged release measures 7.902 s fresh game, 3.666 s first
literal edit, 2.709 s literal revert and 5.461 s body edit in three unprofiled
pairs. A separate unseen-edit sequence has later literals at 2.727 / 2.872 s.
Inference remains 1.37 s for literal revert and 4.08 s for the body edit under
phase profiling. One thread owns 90–97% of CPU; later literal/body hardware
samples retire about 36.9 / 74.4 billion instructions on that thread. The review
records 50 observations, allocation/RSS evidence, remaining measurement gaps and
five next experiments. These are diagnostics of that baseline, not new speedup
percentages or a compiler qualification. The historical paired comparison below
keeps its original scope.

Historical qualification:
[CT103/CT104 inference reuse and row normalization](zig-native/CT103_QUALIFICATION.md).
Seven alternating pairs against `5412320` show **24.8% less literal-edit CPU**,
**4.2% less body-edit CPU**, and **6.1% less fresh-game CPU** with exact
outputs. Devtools is effectively unchanged. Literal/body wall medians are 7.60 /
12.46 s on the loaded shared host; the body wall median does not improve. The
body 20% and sub-second targets remain open. First-edit checking and previously
unseen later edits are reported separately. The final build also fixes portable
restart replay, includes `faf3f78` and passes a separate 2,551-law exhaustive
native gate, 1,654 guest checks, zero lint and exact frozen-output parity. That
integration check is not a new performance comparison. The matching CLI and
native compiler are installed.

Historical CT102 qualification:
[partial call-memo replay](zig-native/CT102_QUALIFICATION.md) showed 25.1% less
literal CPU against CT97. Earlier measurements below retain their original
baselines; their ratios are not cumulative current measurements.

Historical follow-up:
[CT97, executable reuse and temporary scratch](zig-native/CT97_QUALIFICATION.md).
Seven alternating release pairs reduce fresh game CPU by **32.5%** against CT96;
median build wall falls from **13.60 to 8.68 s**, with identical Wasm. The
original baseline and CT96 measurements below remain historical references; use
the latest qualification for current comparisons and remaining targets.

Follow-up: [CT96 is qualified](zig-native/CT96_QUALIFICATION.md). Computing
spawn contract presence once per compilation reduces fresh game CPU by 28.6% in
seven alternating release pairs (17.24 → 12.16 s median build wall), with
identical Wasm. The measurements below preserve the preceding baseline and its
original profiling evidence; use the follow-up record for the optimized
candidate. The [post-CT96 review](PERFORMANCE_REVIEW.md) updates the next hills
with caller attribution, retained-admission analysis and 33 new exhaustive sweep
profiles.

23 October 2026 baseline. This identified repeated whole-program scans in
`prepareSpawnApplication`, owning **27.6% of sampled CPU**, as the first
application-compile experiment. For compiler development, keep ordinary Zig
caching: real source edits build in about **3.4 seconds**, while `-fincremental`
makes unchanged builds much slower without a useful real-edit gain in this
screen.

The implementation queues are [compile-time hills](COMPILE_HILLS.md) CT95–CT101
and [compiler-build hills](BUILD_HILLS.md) BT1–BT5. That baseline checkpoint
added measurement tools and evidence; it did not implement those optimizations
or close the remaining [completion plan](FINISH_PLAN.md).

## Scope and reproducibility

All application measurements use the already qualified release at `63c931f`,
following the derive/budget commit `58e00c3`. Compiler SHA-256:

```text
fec30aece1dccd18f4709a06a96d70f42e9cd0682f843bc53fa8e3f99fa0ab31
```

The two benchmark variants use this **same executable**. The baseline has
profiling disabled; the candidate has it enabled. These pairs measure profiling
overhead, not an optimization or a comparison with a previous compiler.

Host: Ryzen 7 7800X3D, 16 logical CPUs, Linux 7.2.9, Zig 0.17.0, Deno 2.9.7. The
554-file snapshot freezes gdev, Ink, assets and the configured standard library.
Its unchanged `pen.json` selects a 200,000,000 inference budget and an explicit
text asset import. The benchmark now preserves these settings and rejects a
missing configured standard library. Inputs and compiler bytes are checked
before and after measurement. The historical 130-file manifest remains
unchanged; this workload has its own manifest and output pins.

Fresh means a new compiler process and project session for each sample. The
timed interval is the build request, excluding process start and project open;
OS page caches are not flushed. CPU is Linux process user plus system ticks,
including exited workers, with 10 ms resolution. Live-thread scheduler CPU is
retained separately. Peak RSS is the process high-water mark, so retained phases
cannot attribute it to just one edit. Phase clocks measure wall time, not CPU.

Raw reports, samples, input/output hashes, build logs and verification records
are preserved in
[the evidence archive](zig-native/measurements/compile-cost-2026-10-23.tar.gz).
Its `SHA256SUMS` covers each payload file. Private application sources, compiler
binaries and Zig caches are excluded. The local working evidence is under
`build/bench/compile-cost-20261023`; reproducing gdev needs the matching private
snapshot. The public `edit_suite` workload exercises the tooling without it.

## Compiling gdev

Three alternating ordinary/profiled pairs per entry:

| Entry / mode       | Median wall |      Wall range | Median CPU | Median peak RSS |
| ------------------ | ----------: | --------------: | ---------: | --------------: |
| Game, ordinary     |    16.292 s | 16.146–17.013 s |   16.430 s |       476.6 MiB |
| Game, profiled     |    17.469 s | 16.304–18.265 s |   17.240 s |       476.9 MiB |
| Devtools, ordinary |     0.924 s |   0.923–0.943 s |    0.960 s |       169.0 MiB |
| Devtools, profiled |     0.936 s |   0.936–1.024 s |    0.970 s |       164.8 MiB |

Median paired CPU overhead from phase profiling is **4.73%** for the game and
**2.11%** for devtools. Use unprofiled pairs for acceptance decisions. Three
pairs identify major costs; future speedup claims require the seven-pair gate.

Profiled game phase medians:

| Exclusive phase          |       Wall time |
| ------------------------ | --------------: |
| Backend                  |        15.944 s |
| Frontend checking        |         1.161 s |
| Lowering                 |         0.123 s |
| Validation               |         0.107 s |
| Freezing                 |         0.075 s |
| Lexing / parsing         | 0.022 / 0.013 s |
| Assets / loading / other |   about 0.029 s |

Each sample's exclusive clocks partition its profiled wall interval within
microsecond rounding. Separately calculated medians need not sum exactly. Within
the backend, the main child clocks are **9.642 s inference**, **5.077 s constant
preparation**, 0.206 s evaluation, 0.089 s layouts and 0.056 s specialization.
Assembly is only 0.181 s. These child clocks are already inside the backend
phase and must not be added to it. Region observations are inclusive and
overlapping. Raw clock keys end in `_us`; the `costs.*_wall_ms` summaries
convert their values to milliseconds while retaining the raw names.

The first profiled game sample requests 4,216 MiB cumulatively across 12.42
million allocations; this is allocation traffic, not resident memory. Frontend
checking alone accounts for roughly 1 GiB and 7.65 million allocations.
Inference records 18,386 regions and 237,669 scopes, with a largest region of
33,828 scopes. Large-region and allocation costs deserve their own follow-up
after the call-preparation scan is removed.

Two independently sampled game builds contain 1,370 complete GDB sampling
intervals. CPU-weighted stacks cover **99.47%** of their measured process CPU,
with no missing or truncated stacks inside those intervals. Boundary intervals
are excluded. Idle threads have zero weight; the older unweighted stack table is
only an inventory.

| Self CPU location                                | Sampled CPU | Interpretation                                                        |
| ------------------------------------------------ | ----------: | --------------------------------------------------------------------- |
| `backend_emission.Owner.prepareSpawnApplication` |      27.62% | Repeated scan over every unit's bindings at ordinary call preparation |
| `effects.Store.node`                             |      12.38% | Trivial load; inspect caller traversal and locality                   |
| `effects.Store.replacement`                      |       6.60% | Chronological version-chain traversal                                 |
| `types.Store.resolveOperationRow`                |       4.86% | Effect-row resolution                                                 |

The first hotspot is the loop at
[backend_emission.zig](zig-native/src/backend/backend_emission.zig#L7553). Of
its 9.276 CPU seconds across both sampled builds, 8.217 seconds occur under
`Generator.constant` and static-data preparation in the stack. Thus the broad
constant clock includes preparing runtime callables. Removing the scan and
reducing constants are not independent savings. CT96 should prepare immutable
capability-presence/index information once per generator, then preserve the
existing positive-path authority checks. Reprofile afterward.

### Retained edits

One ordinary/profiled pair screens retained game behavior, separately from the
fresh campaign. It is not a percentile or a stable speedup estimate. The
ordinary fresh control in this interval took 19.412 s; compare edits to that
interval, not directly to the earlier 16.292 s median.

| Ordinary retained action |              Wall |                                              CPU |
| ------------------------ | ----------------: | -----------------------------------------------: |
| Populate                 |          20.149 s |                                         19.930 s |
| No-op                    |           20.2 ms |                                            10 ms |
| Trivia edit / revert     |    20.8 / 17.8 ms | tick resolution is too coarse for precise ratios |
| Literal in body / revert | 18.383 / 17.280 s |                                18.590 / 17.490 s |
| Body change / revert     | 17.407 / 17.396 s |                                17.600 / 17.560 s |

Literal/body edits recheck one module but offer **zero backend candidates** and
rebuild **4,266 named functions and 1,424 closures**. CT98 should explain the
first retained-seed rejection before changing reuse admission. Every measured
edit matches its fresh control, and every revert restores the original output.
The two unchanged entry hashes are:

```text
game     5230712 bytes  7cdefcb761628a6043e04d3a515e85e77074914d3ba67d275ec1672e2a09d071
devtools 1107529 bytes  229a8b1833c5cf2505c6d325422082e4242cf0b9e6ee8426e233b46028de75c3
```

## Building and checking the compiler

Isolated source copies compare ordinary caching with `-fincremental`, always
Safe/noLLVM. Each mode has its own initially empty Zig global/local caches.
Three rounds use distinct leaf-constant, checker-diagnostic and native-fixture
edits, with exact source reverts. Both the compiler and complete native test
inventory are compiled for every cell. Modes run sequentially, not as
alternating pairs; small differences are inconclusive.

Median wall seconds across the three rounds:

| Change           | Ordinary compiler | Ordinary native compile | Incremental compiler | Incremental native compile |
| ---------------- | ----------------: | ----------------------: | -------------------: | -------------------------: |
| Unchanged        |             0.015 |                   0.016 |                2.986 |                      6.112 |
| Leaf edit        |             3.387 |                   5.511 |                3.487 |                      5.770 |
| Checker edit     |             3.456 |                   5.330 |                3.388 |                      6.211 |
| Test-only edit   |             0.015 |                   5.561 |                3.400 |                      5.817 |
| Leaf revert      |             0.319 |                   5.614 |                3.359 |                      5.993 |
| Checker revert   |             0.300 |                   5.442 |                3.430 |                      5.817 |
| Test-only revert |             0.016 |                   5.804 |                3.269 |                      5.804 |

Empty-cache build-system initialization (`zig build --help`) costs **56.099 s**
in ordinary mode and 69.107 s in incremental mode. Repeating it costs 10–11 ms.
After initialization, the first compiler artifact takes 5.014 / 6.079 s and the
native artifact 5.259 / 7.624 s. Do not attribute the entire empty-cache command
to compiling Blot's source. Stable writable caches are the immediate iteration
win; explicitly enabling incremental mode is not justified by this result.

The final report has all 92 measurement cells and zero failed build commands.
Compiler source identity and the 2,539-test inventory are restored after edits;
three budget regressions execute on each restored native binary. CPU, peak
single-process RSS, commands, Zig summaries and executable hashes remain in the
raw report. Two earlier controls stopped on an overly strict executable-byte
equality assertion. Rebuilt unstripped executables can differ even when source
identity/inventory match; their hashes remain visible. The second control was
resumed after correcting that assertion, with previous results preserved. These
runs are build measurements, not full behavioral qualification.

Two warm `check:dev --area type-effects` cycles pass in **4.715 and 4.640 s**.
Each compiles the complete 2,539-test inventory, executes 12 native laws with
sampled allocation failures and nine guest checks, then runs formatting, types
and local Zig analysis. The second run's breakdown is:

| Work                                  |                    Wall |
| ------------------------------------- | ----------------------: |
| Development compiler wrapper/build    |                 0.189 s |
| Native compile / inventory            |         0.016 / 0.011 s |
| Selected native execution             |                 0.734 s |
| Guest checks                          |                 1.539 s |
| Formatting / types / Zig lint         | 0.067 / 0.720 / 0.512 s |
| Input and executable identity checks  |                 0.835 s |
| Zig version / remaining orchestration |                 0.015 s |

Both cycles already had warm build caches; neither is an edited-cycle or p95
claim. They ran from the qualification snapshot with the current compiler source
and measurement scripts, using stable writable caches. The reports explicitly
leave full qualification pending. BT1's cache-hit target and BT3's warm target
are met on this host; edited end-to-end cycles remain to be measured.

The preceding
[qualified release gate](zig-native/ASSOCIATED_WORK_QUALIFICATION.md) takes
669.831 s overall. Native exhaustive execution takes **595.972 s**, while the
LLVM release build takes **194.378 s** and overlaps native work. They must not
be summed. Four native shards take 558.32, 595.75, 586.06 and 554.94 s; perfect
rebalancing would save only about 4% of the native interval. The three slowest
allocation-failure laws take 86.22, 82.46 and 72.14 s: generic-accessor staging,
retained State captures, and request-backend teardown respectively. BT4 targets
repeated setup/work inside those fixtures while preserving every fault case. Do
not weaken exhaustive qualification to improve a timing number.

## Running the measurements

Keep private snapshots and new pins under ignored `build/`. To repeat the
existing local comparison:

```sh
deno task bench:compile \
  --baseline build/bench/compile-cost-20261023/baseline/blotc \
  --candidate zig-native/zig-out/bin/blotc \
  --snapshot build/bench/compile-cost-20261023/snapshot \
  --manifest build/bench/compile-cost-20261023/manifest.json \
  --hashes build/bench/compile-cost-20261023/wasm.json \
  --workload game,devtools --runs 3 --no-retained --candidate-profile \
  --out build/bench/compile-cost-next
```

Use `--write-manifest --write-hashes` only to initialize deliberately new pins.
For a real optimization comparison, omit `--candidate-profile`, use seven pairs
and `--guard-cpu`, and separately measure retained scenarios. To sample CPU:

```sh
deno task profile:compile --blotc zig-native/zig-out/bin/blotc \
  --snapshot build/bench/compile-cost-20261023/snapshot \
  --manifest build/bench/compile-cost-20261023/manifest.json \
  --workload game --runs 2 --min-ms 15 --max-ms 30 \
  --out build/bench/compile-stacks-next
python3 scripts/bench/summarize_stacks.py build/bench/compile-stacks-next
zig version
deno task bench:compiler-build --out build/bench/compiler-iteration-next --runs 3
```

The build experiment requires Linux, Python 3.11+ and Zig 0.17.0. It edits only
its isolated copies. `--resume` is for interrupted measurements with unchanged
pins, not qualification reuse. For ordinary development on this host, set stable
writable cache paths from the repository root before running `check:dev`:

```sh
export ZIG_GLOBAL_CACHE_DIR="$PWD/build/task-regions-global"
export ZIG_LOCAL_CACHE_DIR="$PWD/build/task-regions-local"
zig version
deno task check:dev --area type-effects
```

The benchmark changes are checked by the tooling harness and a complete public
`edit_suite` fresh/edit/revert run. No compiler source changed in this
checkpoint; its existing full qualification remains the release evidence.
