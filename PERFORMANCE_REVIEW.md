# Performance hills toward sub-second edits

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
