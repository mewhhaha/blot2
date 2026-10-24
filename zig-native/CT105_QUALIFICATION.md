# CT105: solver scan, normalization and catalog costs

The final release is qualified and installed. Seven alternating comparisons,
unseen/fresh/restart controls and the exhaustive compiler gate pass.
The baseline is qualified `5cfb4117a1749dd487205652ea5645af1164afaf`, native
SHA-256 `0185500e446d59d6e813de8cecb3318bcc5983632043eb0129b8a64bad45ee9f`.

## Paired release measurements

Seven alternating unprofiled pairs compare the final ReleaseFast/LLVM compiler
against the qualified baseline above. Both use the frozen 554-file gdev/Ink/std
snapshot (189 game modules), optimized codegen, four workers, a 200-million
inference budget and disabled restart persistence. Every output matches the
previous strict Wasm pins. The manifest SHA-256 is
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`.
Final native SHA-256:
`0eadf4bb1a0cc7448f59156091a7287e2456aedfd4b31452197a0a3437a1da78`.

| Workload / phase | Baseline wall median | Candidate wall median | Baseline CPU median | Candidate CPU median | Median paired CPU change |
| --- | ---: | ---: | ---: | ---: | ---: |
| game / Fresh | 9.879 s | 8.333 s | 9.870 s | 8.440 s | -13.3% |
| game / No-op | 0.019 s | 0.019 s | 0.010 s | 0.020 s | +0.0% |
| game / First literal edit | 4.291 s | 4.163 s | 4.540 s | 4.420 s | -3.3% |
| game / Literal revert | 3.149 s | 3.102 s | 3.410 s | 3.370 s | -4.1% |
| game / Body edit | 6.286 s | 5.418 s | 6.490 s | 5.650 s | -12.9% |
| devtools / Fresh | 0.773 s | 0.751 s | 0.810 s | 0.800 s | -1.2% |

CPU changes are medians of candidate/baseline ratios within each pair, not
ratios of the separate medians. Process CPU includes workers and has 10 ms
resolution; no-op CPU is too small for a useful percentage. Build wall time
excludes process startup/project opening. The host ran unrelated builds during
the early pairs; raw ranges and ordering are preserved. These are shared-host
observations, not a quiet-host latency guarantee.
For scale, baseline/candidate fresh wall ranges are 9.12–22.20 / 7.93–20.35 s;
first-literal ranges are 4.24–35.14 / 4.07–9.06 s; body ranges are 6.13–12.36 /
5.32–13.91 s. `pair-ranges.json` and raw samples retain both CPU and wall ranges.
No early pair is discarded because of host load.

The body-edit 10% CPU target and both fresh-workload regression guards pass.
The literal-edit 10% target **misses** (3.3% lower paired CPU). Retain the measured
fresh/body benefit without declaring the combined edit hill complete. Neither
the two-second nor sub-second ordinary-edit target is met. Comparisons with
older checkpoints must keep their original baselines; do not multiply gains.

## Implementation

- Lexical type-variable sharing follows per-scope insertion-order links. It
  preserves the original collection boundary while avoiding whole-region scans.
  Existing row-variable imports return before repeating immutable validation.
- Solver queues retain a pending bit mask. Broad wakeups combine machine words
  instead of examining every completed constraint; take order is unchanged.
- Canonical evidence rows check an already-sorted exact hit before copying and
  sorting. Misses still copy borrowed input before growing owned label storage;
  operation multiplicity remains observable.
- Positive operation-row certificates use a four-byte dense sidecar per row,
  with a four-slot fallback during infallible type construction. Physical epochs,
  generations, rollback, recycled IDs and depth limits keep their existing gates.
  Root mismatches and primitive equality avoid graph-walk scratch when no
  projection accounting is active. The original walker is a differential oracle.
- Epoch-cache updates search before growing. Failed body-recipe plans retain
  their attempted bound; larger bounds retry and smaller limits still decline.
- Backend workers share the synchronized session heap directly, including an
  atomic profiling wrapper. Unknown allocators retain the outer mutex.
- Principal observations own anonymous/local source-module dependencies.
  Proven foreign type-only scopes retain exact semantic-catalog admission.
  Archive version seven owns and validates the new observations. These proofs
  grant no value or executable-body reuse; optional memo outputs still require
  their own verified inputs.
- Frontend correspondence indexes public binding identities, original imported
  producers, nominals, constructors, contracts and implementations. Duplicate
  unnamed imports can preserve already-matching local slots; named ambiguity,
  changed producers and moved duplicate slots decline. Full graph, capability,
  scheme, association and contract checks still run before publication.

New work counters attribute row requests, certificate hits, argument visits,
mutations, interner candidates and avoided lexical scans. Bounded diagnostics
report exact principal-source failures and the first frontend comparison stage.
See [client statistics](PROJECT_CLIENT.md) and [ownership](CONTRACT.md).

## Where the work went

A separate profiled pair uses the same final executables and output controls.
These clocks are single observations, not seven-pair CPU estimates; inference
is nested within backend time and must not be added to it.

| Phase | Baseline inference | Candidate inference | Baseline checking | Candidate checking |
| --- | ---: | ---: | ---: | ---: |
| Fresh | 5.760 s | 4.648 s | 1.393 s | 1.250 s |
| First literal edit | 1.413 s | 1.295 s | 0.778 s | 0.768 s |
| Literal revert | 1.393 s | 1.259 s | 0.060 s | 0.059 s |
| Body edit | 4.051 s | 3.356 s | 0.060 s | 0.059 s |

The instrumented pre-dense-cache diagnostic (`diagnostic-3`) visited 201.03
million operation arguments fresh, 65.93 million on literal revert and 176.48
million on the body edit. The final compiler visits 76.31 / 35.99 / 58.58 million:
62.0% / 45.4% / 66.8% less work, meeting the fresh/later-literal work targets.
That diagnostic includes earlier fixes and instrumentation; subsequent catalog
refinements are also in the final compiler. It is not the unmodified baseline
executable; use the seven pairs for whole-change performance claims.
Observed row mutations are zero for these samples. Interner chains remain
substantial: 90.45 million fresh candidates and 9.81 million on literal revert.

Per-scope lexical links visit 41,904 fresh type variables where the previous
region-wide scan would inspect 127,432,687 entries. Body figures are 35,326
versus 127,329,217. These counters cover type-variable sharing only, not the
remaining row-variable-map scan. The four body principal rebuilds and the
literal query/constraint counts are unchanged.

The dense cache trades solver-local memory for fewer repeated visits. In the
profiled pair, solver allocation requests increase by 78.12 MB fresh, 44.57 MB
on literal revert and 65.27 MB on the body edit. Maximum region solver live
bytes increase from 185.37 to 195.25 MB for fresh/body work, and 11.29 to 11.97 MB
for literal revert. These nested logical requests must not be added to backing
allocator requests. Whole-backend requested bytes instead decrease from
2,757.53 to 2,632.61 MB fresh, 1,836.98 to 1,787.11 MB on literal revert and
2,508.19 to 2,482.17 MB on the body edit. This is a combined-change measurement,
not allocation attribution to one patch.

Median lifetime peak RSS across the seven pairs is 472.9 → 482.8 MiB fresh,
740.5 → 707.4 MiB after the first literal and 748.6 → 755.0 MiB after the body
edit. Retained peaks include earlier phases; they are not per-edit live memory.
The cache remains four bytes per solver row, dies with the solver and preserves
all epoch/generation checks. It is not an unbounded cross-revision cache.

Frontend correspondence now gets past binding and nominal catalog lookup with
60,950 of 65,536 comparisons remaining, then declines at graph correspondence
for unit 42 (3,655 bindings). The first edit still checks 22 modules; later
revisions check one. Three body principals decline on module 42's input image;
the fourth fails named source 42:35 identity admission. Completeness and faster
lookup alone do not prove those dependencies reusable.

## Unseen edits and retained memory

A complete eight-revision sequence checks three distinct literal edits, three
body edits and the original source again. Baseline and candidate outputs agree;
every changed source also matches a separate fresh candidate compilation.
This sequence is profiled and is not a latency distribution. The separate
restart-cache pair preserves exact outputs and reuse: the game restart build
request takes 26.8 ms baseline and 23.3 ms candidate in that one observation.

An unprofiled candidate memory sequence repeats all eight pinned revisions,
sampling `/proc` every 100 ms with boundary RSS/PSS, faults and thread scheduler
CPU. Later unseen literals take 2.600 / 2.640 s and the three body edits take
4.734 / 5.534 / 4.982 s. These are independent observations under lighter host
load, not replacements for the seven-pair medians.

Post-edit RSS ranges from 418.3 to 480.2 MiB; PSS closely follows it. Lifetime
high water reaches 760.8 MiB. Each edit takes 160,506–245,337 minor faults, with
zero major faults and zero swap. The largest thread accounts for 89.3–95.1% of
observed edit CPU; scheduler accounting covers approximately all process CPU
(with tick/sampling error). Runqueue wait is 19–68 ms per edit in this sequence.
Eight revisions do not establish leak freedom or a long-session retention bound.
These measurements do not demonstrate a bandwidth or lock-contention bottleneck.

## Hardware-counter controls

Two PMU sequences use opposite baseline/candidate ordering. All outputs match
and all six generic hardware events run for 100% of enabled time, with no
multiplex scaling. The scope is one dominant compiler thread in user space:
workers, kernel fault handling and other threads are excluded. These are two
diagnostic sequences, not seven paired hardware samples.

First-literal retired instructions fall 5.8–6.4%; later literals fall 6.5–8.0%;
the body edit falls about 17.8% in both orders. The first sequence's later
literal counts are 36.87 → 34.26 billion and 36.84 → 34.30 billion; body counts
are 74.36 → 61.15 billion. This independently supports reduced instruction work.

Cycles do not fall proportionally. Literal candidate/baseline cycle ratios span
1.004–1.346, and generic later-literal cache-miss ratios span 1.055–1.727. Body
cycle ratios are 0.934–0.958. Reverse-order host load rises from 10.9 to 41.4,
then ends at 35.7; wall timings vary severely. Preserve these adverse counters:
the data do not establish improved cache locality or explain all cycle changes.
A quiet matched run with cache-level/working-set attribution is still needed
before expanding cache retention or claiming a hardware-efficiency gain. Generic
cache events do not identify an AMD cache level, DRAM bandwidth or latency.
Use the seven unprofiled pairs for the whole-change CPU claim.

## Open boundaries

The frozen workload still rebuilds four principal regions after the body edit.
Completing source observations exposes the remaining consumed-module-image and
source-identity differences; it does not justify skipping their work.

Frontend indexing removes quadratic budget exhaustion. The first edit still
fails the subsequent graph correspondence check and performs the broader
frontend check. This remains an open hill. Lookup, emission, remaining inference
and sub-second ordinary edits also remain open. The earlier audit's hypotheses
about bandwidth, heap contention, arena trimming and more parallelism are not
established defects and have not been used to weaken correctness gates.

## Disposition of the 50 audit observations

Observation numbers refer to the dated audit in
[PERFORMANCE_REVIEW.md](../PERFORMANCE_REVIEW.md). Several observations describe
costs or hypotheses rather than established implementation defects. The table
keeps those distinctions explicit; this batch does not claim to close all 50.

| Observations | Result and remaining work |
| --- | --- |
| 1–8 | Repeat whole-build CPU/wall, phase, thread and hardware measurements; preserve small-project control. Serial inference and host variability remain. |
| 9–10, 39 | Add row/certificate/interner counters and dense positive row certificates. Compare avoided argument work against additional allocation and RSS. Other cache policies remain unchanged. |
| 11 | Avoid graph-walk setup for exact root negatives and primitive equality. Candidate-chain indexing beyond the existing identity/instance/arity key remains open. |
| 12 | Exact sorted-row hits avoid repeated copy/sort; borrowed misses and duplicate labels retain ownership and semantics. |
| 13 | Preserve chronological version/rollback behavior. Chain-length and cursor attribution remain open. |
| 14 | Broad wakeups merge pending machine words instead of scanning every entry. No-progress attempts and watch fanout still need attribution. |
| 15–16 | Frontier bounds and graph watch discovery remain unchanged; no evidence yet justifies larger limits or retained watch state. |
| 17 | Per-scope type-variable links remove region-wide lexical scans. Row-variable-map scans and quantified-variable membership remain separate costs. |
| 18 | Preserve occurs checks; repeated equivalent root/version work is not established. |
| 19 | Own anonymous/module observations and record exact decline reasons. Four body regions still rebuild: three module-image differences and one named-source identity difference. |
| 20–24 | Result, call, value and executable inputs remain distinct. Residual query duplication and successful-replay validation need narrower attribution. |
| 25 | Cache immutable failed recipe bounds; retry larger bounds and preserve smaller-limit declines. |
| 26–27 | Preserve session ownership and imported-graph validation. Cross-revision recipe retention and validated-owner certificates remain hypotheses. |
| 28–31 | Repeat allocation/current RSS/PSS/fault evidence. Cumulative requests, live memory, lifetime peaks and page faults remain distinct quantities. |
| 32–33 | Keep slab lifetime and the heap's inner synchronization; occupancy and contention have not been established as bottlenecks. |
| 34 | Known synchronized heaps and atomic counting wrappers bypass the redundant outer worker allocator mutex. Unknown allocators remain protected. |
| 35–38 | Arena bins, retention cap and compact node layout remain unchanged. Capacity/fragmentation/reuse-distance attribution is still needed. |
| 40 | Preserve exact mutation, cursor, depth, physical epoch and generation checks. No speculative invalidation relaxation. |
| 41 | Existing resolution-cache keys update before the growth threshold; new keys still grow with normal OOM handling. |
| 42–43 | Metadata copies and structural reuse lookup remain open costs. |
| 44–45 | Preserve immutable backend job ownership. Extra inference parallelism, clone retention and worker scheduling changes need their own evidence. |
| 46–47 | Output encoding/transport remains a hill; cheap input validation remains intact. |
| 48–49 | Add logical normalization/scan work and bounded source/frontend diagnostics. Repeat user-thread generic PMU measurements; do not claim phase-local bandwidth, cache-level latency or complete owner live-memory attribution. |
| 50 | Repeat the affected development cycle and full gate. Retain Safe/noLLVM, complete inventory compilation and runtime selection. No paired compiler-build improvement claim. |

The first-edit frontend finding spans observations 2, 4 and 28: indexed
correspondence removes quadratic budget exhaustion, then reaches a graph-stage
decline. The [subsequent review](../COMPILER_REVIEW_CT105.md) clarifies that this
does not establish a semantic mismatch. Its debugger probe rules out the graph
size cap for the observed case, while the exact declining branch remains
unknown. Both this decline and the four body rebuilds remain in the next
measurement queue.

## Verification and installation

`deno task test:compiler --native-shards 4 --phase-seconds 1800
--budget-seconds 2400 --timings-dir build/bench/ct105/gate` passes in **674.30 s**:

- **2,555 native laws**, complete inventory, four isolated shards, exhaustive
  allocation-failure mode, zero failures and zero reported leaks. Native
  execution takes 625.86 s. Compilation uses Zig 0.17.0 Safe/noLLVM; the final
  release uses ReleaseFast/LLVM. Exact inventory, shard completion and raw
  timing records are pinned in the gate journal.
- **1,654 guest checks**, **48 smoke checks** and **57 tooling checks**, all pass.
- **Zero Zig lint findings** on all 518 source files plus the build file in the
  final development run. The analyzer is the local cached frontend with its
  existing matching backend, selected through `ZIG_ANALYZER`.
- Strict frozen fresh/edit/revert/restart Wasm pins, the complete unseen-edit
  sequence with independent fresh controls, and the eight-revision memory
  sequence all pass. Source, baseline, candidate and manifest pins remain exact.

Before the full gate, the final static-sharing development cycle passes in
**21.28 s**: compiler construction 3.31 s, complete native compilation 5.91 s,
52 selected native laws with sampled faults in 0.77 s, 54 selected guest checks
and local analysis. Additional affected laws run through runtime selection.
These are individual development/build observations, not p95 or paired build
improvements. The first partial unseen sequence was cancelled to correct the
controller's gate shard count/time allowance; its complete rerun passes. No
cancelled sequence or sampled check substitutes for qualification.

The staged CLI and native compiler then pass outside-repository format,
format-check, source-check and build controls. Their Wasm bytes match, instantiate
without imports and return **29** for the list example. Both binaries are
atomically installed at `~/.local/bin/blot` and `~/.local/bin/blotc`, preserving
rollback copies. PATH, the same installed smoke controls, exact Wasm and the
bundled language guide pass. Installed SHA-256:

- Native: `0eadf4bb1a0cc7448f59156091a7287e2456aedfd4b31452197a0a3437a1da78`
- CLI: `17143ff85c0c767e2f2ad61166a7939211614094321ef94f17625b46f89f19c4`

Local records are `build/bench/ct105/qualification-summary.json`,
`build/bench/ct105/final-pins.json` and `build/install/ct105/installed.json`.
The [evidence archive](measurements/ct105-2026-10-24.tar.gz) and
[SHA-256 sidecar](measurements/ct105-2026-10-24.tar.gz.sha256) preserve the
hypothesis, commands, complete raw pairs, diagnostic counter trials, both PMU
orders, memory/source/binary pins, exact source patch, development/full-gate
logs and installation records. `SHA256SUMS` covers every archive payload.
Private workload source, compiler binaries, generated Wasm and build caches are
excluded. Reproducing the private gdev workload requires the matching frozen
manifest; the archive does not pretend to contain that source.
