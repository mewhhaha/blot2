# CT102: keep admitted principal results when optional call proofs decline

Qualified on 24 October 2026: **25.1% less retained literal-edit CPU** in seven
alternating release pairs, exact Wasm, and the full compiler gate passed.
Candidate literal/body wall medians are **5.93 / 6.83 s** on this shared host.
Sub-second ordinary edits remain open.

## Change and correctness boundary

A retained literal edit had an empty principal result whose source image and
recorded dynamic inputs still matched. Importing its optional call memo outputs
stopped at publication 8,627 of 12,387: a type reached depth 128 with 999,809
work units still available. The entire result was then discarded and its large
inference region rebuilt. The first diagnostic hypothesis, repeated shared-graph
validation exhausting the work budget, was disproved. Its height-cache prototype
was removed without changing any validation limits.

The candidate translates each memo output independently. A declined output stays
absent and its next use performs ordinary checking. Successfully translated
outputs are compacted into owned storage, then published with the existing
reserve-before-publication rule. Only those outputs enter the next capture.
The already-admitted empty result can be reused. Source image, recorded inputs,
nonempty-result admission, type/depth bounds and executable/value checks remain
in force. There is no application migration or workload-budget change.

The diagnostic game run now reuses 18 of 20 principal queries, including the
largest formerly rebuilt region. It publishes 12,134 translated call proofs and
omits 253. Two principal regions still rebuild: one returns nonempty facts and
one has no complete recorded input key. The literal output matches the existing
frozen-workload hash. These Safe/noLLVM runs identify behavior; their timings are
not release performance comparisons.

`stats.principals` now separates projected owner/result/unrecorded/input/image/
import declines from omitted call memo outputs. See
[PROJECT_CLIENT.md](PROJECT_CLIENT.md) and [CONTRACT.md](CONTRACT.md).

## Regression coverage

The new native law checks mixed accepted/declined memo outputs and the all-declined
case, including shrinking owned storage to zero. Exhaustive allocation-failure
execution must leave the old capture intact and release every failed candidate.
The executed-Wasm regression uses a linear-size value deeper than the importer's
128-level bound but within ordinary inference's 256-level bound. Both codegen
tiers compare retained and fresh bytes across literal edits, divide-by-zero,
recovery and another edit, and execute the expected answers. Its first edit
replays 126 proofs and omits six; subsequent captures contain only translated
proofs. Existing projected-input and nominal/publication laws remain selected.

The complete native inventory and the expanded static-sharing development family
pass in 35.36 s, including the new executed-Wasm test and zero Zig lint findings.
This sampled development run is not full qualification.

## Measurement protocol

Baseline: committed CT97 release from `1aa132e`, installed before this work,
SHA-256 `73a9998009efc24e3d3516a689355a1be6cf90ccf880f3dc3ccee6aa22c0dff6`.
Candidate source: `build/bench/ct102/candidate-src`, based on `b346008` plus
only this change and its tests/development selections. Concurrent text-capability
and guest-runtime changes are excluded and preserved in the working tree.

The same 554-file frozen gdev/Ink/std/asset corpus and original `pen.json`
settings are used, including the 200,000,000 inference budget. Default optimized
codegen is retained. Seven alternating unprofiled fresh pairs cover game and
devtools; seven retained pairs cover no-op, trivia, literal/body edits, reverts,
fresh edited controls and process restarts. A separate instrumented pair
attributes remaining work. Every accepted output must be byte-identical to its
baseline/fresh counterpart and the pinned original output when applicable.

Predeclared target: at least 10% less paired literal-edit CPU, with no more than
5% unaffected fresh/body CPU regression. Sub-second ordinary edits are the user
priority and remain an aspirational latency target until measured. CPU, wall and
RSS are reported separately; shared-host observations are not latency guarantees.

## Release results

Seven alternating pairs meet the predeclared CPU targets. The paired median
candidate/baseline CPU ratio is **0.749086** for literal edits: **25.1% less CPU**.
The unaffected ratios are **1.000** for fresh game, **0.992063** for fresh
devtools and **0.994329** for body edits. These are medians of within-pair ratios;
they are not ratios of the two independent medians below.

| Scenario | Baseline CPU median | Candidate CPU median | Baseline wall median | Candidate wall median |
| --- | ---: | ---: | ---: | ---: |
| Fresh game (cold comparison) | 14.00 s | 14.04 s | 21.186 s | 19.956 s |
| Fresh devtools | 1.07 s | 1.13 s | 1.568 s | 1.582 s |
| Literal edit | 8.51 s | 6.15 s | 8.627 s | 5.930 s |
| Literal revert | 7.25 s | 5.04 s | 6.982 s | 4.813 s |
| Body edit | 7.97 s | 7.08 s | 11.185 s | 6.829 s |
| No-op | 20 ms | 20 ms | 25.15 ms | 19.99 ms |
| Cached process restart | 20 ms | 20 ms | 28.07 ms | 28.43 ms |

Shared-host load changes from 18.2 to 26.6 during the fresh comparison and 26.6
to 4.1 during the retained comparison. All samples are retained. Candidate literal
wall ranges **5.833–14.589 s**, body wall **6.774–14.114 s**. Literal paired CPU
ratios range **0.568182–0.777506**. Body-edit work is unchanged by this optimization;
its different independent wall medians do not establish a body speedup. Fresh
game peak RSS medians are 472.9 / 472.3 MiB; retained-process peak RSS is cumulative
across the preceding revisions and is not an isolated per-edit allocation count.
No-op/restart CPU ticks are too coarse for percentage claims.

Every accepted Wasm comparison passes: baseline/candidate, retained/fresh edited
controls, original/revert and process restart, with the original workload/output
pins intact. The candidate release SHA-256 is
`321d17443706884fdf5b80d7e181aa8975a39eee778a3f9f3f50a81aa533439a`.

## Remaining costs and the sub-second target

A separate single instrumented pair, under matching profiling settings, measures
literal inference at **5.221 → 3.195 s** and backend phase time at
**6.767 → 4.756 s**. The removed region took 2.146 s; the two remaining large
regions take 0.955 and 0.493 s in the candidate. Lookup is 0.420 s, replay 0.068 s,
constant preparation 0.217 s and evaluation 0.253 s. These clocks have different
scopes; do not add overlapping region and inference durations.

The first literal edit spends 0.918 s in checking and makes 6,553,820 checking
allocations. Subsequent revert/body revisions spend about 0.07 s in checking.
This distinction matters for ordinary iteration: first-edit preparation and
steady editing need separate measurements. Body edits still rebuild the three
large inference regions; their complete source input image has changed, and
this patch intentionally provides no new source admission rule.

A separate diagnostic series then applies three distinct literal values, followed
by a revert, in retained baseline/candidate sessions. Every revision matches the
other compiler and a fresh edited control; the revert restores the population
hash and the frozen inputs remain unchanged. The candidate observations are:

| Revision | Wall | CPU | Checking | Check allocations | Inference |
| --- | ---: | ---: | ---: | ---: | ---: |
| First unseen literal | 5.769 s | 6.040 s | 0.907 s | 6,553,820 | 3.129 s |
| Second unseen literal | 4.982 s | 5.160 s | 0.074 s | 156,683 | 3.328 s |
| Third unseen literal | 4.674 s | 4.940 s | 0.070 s | 156,683 | 3.123 s |
| Revert | 4.638 s | 4.940 s | 0.068 s | 156,683 | 3.089 s |

This is one profiled sequence, separate from the seven-pair throughput result.
It confirms the fast frontend path for two previously unseen literals in the
same body; it does not establish general body-edit latency or a distribution.
The first edit omits 253 call proofs; later captures omit none and continue to
replay 12,134 proofs. Two principal regions still require fresh inference.

Sub-second ordinary edits are **not achieved**. Prioritize the remaining
inference and its exact input/result reuse boundaries. Frontend allocation is a
separate first-edit/fresh-build target; it is already a small part of these later
literal edits.

A candidate-only GDB sample of one literal edit and revert covers 1,364 complete
intervals and 99.69% of process CPU, with no missing or truncated stacks in those
intervals. CPU-weighted self attribution puts `resolveOperationRow` at 7.04% and
`closedHeight` at 6.00%. The innermost compiler directory is checking for 48.90%
and evaluation for 22.17% of sampled CPU; these include backend inference, not
just the frontend phase. `ClosureRegion.bodyEvidenceMode` accounts for 40.14%
inclusive CPU. Inclusive rows overlap. This is diagnostic attribution, not a
throughput comparison; the unweighted stack inventory includes idle workers and
must not be read as CPU percentages. All sampled outputs match their original
and edited pins. Count repeated type/row queries and their callers before
choosing a bounded cache or changing inference reuse.

## Full qualification

The isolated final candidate passes **2,541 native laws** with exhaustive
allocation failures, **1,649 guest tests**, **48 smoke tests**, and **57 tooling
tests**. Native execution takes 768.23 s across four isolated shards; the complete
gate takes 819.00 s. The inventory, unique completed laws, fault mode, zero leaks
and zero logged errors are verified from the raw shard evidence. The new partial
publication ownership law passes its exhaustive sweeps in 0.182 s. Zig lint has
zero findings on the exact candidate sources.

The actual LLVM release build takes 254.61 s; the expanded Safe/noLLVM development
cycle takes 35.36 s (2.57 s compiler build, 15.50 s complete native compilation,
0.91 s sampled native execution). All native test compilation uses Safe/noLLVM.
The full gate reuses the already built release and native executables. These are
individual observations under this host load, not paired improvements to compiler
construction or qualification; no compiler-build hill closes from this batch.

## Local installation

The qualified native release and self-contained CLI are installed as
`~/.local/bin/blotc` and `~/.local/bin/blot`. The native binary has the candidate
hash above; CLI SHA-256 is
`8e21477ee14eb042aecf203fadb74678bcb27f7098833801dbb4580a1937b478`.
The package uses the isolated candidate's compiler, parser, guide and standard
library. All 1,528 tracked snapshot files checked against the base commit and
qualified changes match, excluding the ownership-documentation update.

Both commands resolve through `PATH`. Outside the repository, formatting,
format checking, source checking and building pass; installed CLI/native Wasm
matches the staged output and executes the list example with answer 29 and no
host imports. The bundled guide matches the candidate. Previous executables are
preserved in `build/install/ct102/previous-c09h2grz`; installation and smoke
records are in `build/install/ct102/installed.json` and the evidence archive.

## Evidence archive

[Raw CT102 evidence](measurements/ct102-principal-replay-2026-10-24.tar.gz)
contains 175 files, 1,816,494 compressed bytes, SHA-256
`89686373cff1575b7c1f7706bfa758898f57290aaa10734159c6ea7930a96575`.
Its internal `SHA256SUMS` verifies every payload file. It includes source and
binary pins, the four changed compiler/test/selection inputs, benchmark samples
and reports, complete gate/shard logs, development checks, profiling stacks,
the unseen-edit sequence and installation evidence. Private application sources,
binaries and caches are omitted; raw qualification cache keys are replaced by
hashes. The candidate can be reconstructed from base `b346008` plus the four
files under `candidate-source/`.

`partial-dev.log` and its `run-4ecbf13c3fc8a028` report describe the accepted
development candidate. The earlier `candidate-dev.log` and declined height-cache
patch preserve the disproved experiment; they are not qualification evidence for
a shipped height-cache change. Trace v1 was stopped after the diagnostic result;
later traces and the final measurement/gate runs completed. All throughput and
installation claims above refer to the pinned final candidate.
