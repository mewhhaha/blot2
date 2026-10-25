# CT113 refinement cache and measurements

CT113 removes measured refinement-cache saturation and adds whole-request cost
measurements. The three-pair release screen improves fresh gdev compilation;
ordinary edit latency is essentially unchanged. The frozen candidate passes full
correctness qualification. CT110 remains installed.

## Change and scope

Refinement Contexts retain at most 8,192 complete records, with 8 MiB of
record/index buffers and the existing 16 MiB payload bound. The previous limit
was 4,096 records / 2 MiB of buffers. Lookup remains bounded at 4,096 candidate
positions. All semantic admission guards are unchanged.

A profile-only census attributes fresh requests and solver nodes to observed
admission, publication and candidate-rejection flags. It keeps 32 groups, an
explicit overflow total and eight heavy individual requests. Additional counters
separate missing from newly present call proofs and expose private independent
proof-check work. Worker counters merge after join without shared mutations. See
[the measurement contract](REFINEMENT_QUERIES.md#request-census-ct113).

The candidate is frozen CT112 plus this change. Concurrent changes in
`backend/owned_arrays.zig`, `backend/owned_arrays_tests.zig` and
`tests/owned_array_execution.test.ts` are excluded. Qualification of this frozen
candidate does not qualify the combined working tree. No new syntax is added.

## Release comparison

Three alternating pairs, 60 recorded samples, compare LLVM ReleaseFast binaries:
CT112 SHA-256 `8b08627a14f7e3f8f48d715af056321d42428fd7f3fd5456f6e91963e8ab27c5`
and CT113 `7643273aebdf572fded1f0dc1c4b354e26d89cd8316c5249067dd675c4dc47e5`.
CT113 identity digest is
`7aa35231373d59700abec993e9694909b5d616bb9b82372e6db6e0370ce79cb1`. The source
manifest pins 1,004 files against HEAD
`e56375d18f32b0aef300fb4b80b9a3c0f2c1632d`.

The 554-file frozen gdev workload has 189 game modules. Both compilers use
optimized output, four codegen workers, ordinary serial semantics (no explicit
semantic-worker option), a 200-million inference budget and no disk cache. No
build or test runs alongside the unprofiled comparison. Strict CT103 output
pins, baseline/candidate equality, independent fresh controls, input pins and
the CPU guard all pass.

| Scenario               | CT112 wall median | CT113 wall median | Median paired CPU change |
| ---------------------- | ----------------: | ----------------: | -----------------------: |
| Game fresh             |           7.546 s |           7.078 s |                   -5.21% |
| Literal edit           |           3.008 s |           2.991 s |                   +0.32% |
| Literal revert         |           2.757 s |           2.754 s |                   +0.37% |
| Body edit              |           5.172 s |           5.217 s |                   -0.96% |
| Body revert            |           5.099 s |           5.106 s |                   +0.40% |
| Devtools fresh control |           0.721 s |           0.718 s |                   +1.35% |

Fresh CPU improves in all three pairs (ratios 0.962, 0.948, 0.939). The edit
measurements do not establish a latency improvement. Peak RSS medians are 483.6
→ 483.4 MiB fresh, 697.1 → 701.5 MiB on the literal edit, and 759.4 → 761.7 MiB
on the body edit. This is a small shared-host screen; it does not predict
arbitrary projects or establish sub-second compilation.

The separate release profile explains the modest result:

| Work                                |     CT112 |     CT113 |
| ----------------------------------- | --------: | --------: |
| Fresh inference regions             |    18,381 |    13,868 |
| Fresh specialization nodes          | 3,409,429 | 2,858,804 |
| Fresh refinement records            |     4,096 |     7,421 |
| Fresh publication-capacity declines |     7,838 |         0 |
| First-edit inference regions        |     2,905 |     2,428 |
| First-edit retained refinement hits |       583 |     1,059 |
| Body-edit inference regions         |     7,191 |     7,189 |
| Body-edit specialization nodes      | 1,670,363 | 1,670,275 |

Fresh refinement payload plus record/index buffers grows from 5,309,616 to
10,365,152 bytes. This is about 4.82 MiB extra cache storage, not a global heap
or RSS prediction. Private independent checks already existed; their previously
unreported body work is now visible as another 1,915 nodes.

## Rejected approaches and remaining work

The initial body census identifies 813 fresh requests / 1,345,784 nodes that
encounter a call-proof mismatch after matching source, shape and seeds. This is
a request-level observation: other candidates can fail other checks.

An additional-proof trial saves one literal region and no body regions. An
independent-recheck trial saves only four additional body hits while total body
regions rise from 7,191 to 7,477. The later literal rejection census finds 243
attempts returning no proof and 16 using multiple regions. Both changes are
removed from the final code; trial sources and results remain in the archive.

The next architecture step needs the producing proof's complete dependency
record, rather than rerunning an isolated body or accepting a missing premise.
Explicit captures, physical holes, multiple-region results and the three large
principal misses also remain. Those principals still visit 3,388,263 nodes on a
body edit. All five architecture recommendations remain incomplete.

## Verification and evidence

The selected Safe/noLLVM cycle compiles all 2,587 native laws and passes 130
sampled laws, 68 executed guests, formatting/types and zero Zig lint findings in
28.16 s. It overlaps diagnostic work and is not a quiet build-time comparison.
The full gate passes all 2,587 exhaustive native laws, 1,660 release guests, 48
smoke tests and 57 tooling checks. Native execution completes in 632.80 s; the
successful resumed gate takes 78.23 s and release guests 30.56 s. The audit
verifies 17 journal artifacts, all source pins and 1,687 full allocation sweeps,
with zero sampled sweeps. These resumed timings are not fresh compiler-build
measurements. Raw data, source pins, failed trials and compiler patches are
under `build/bench/ct113/`; archive details follow below.

The first full attempt passes the exhaustive native phase (632.80 s), then a
guest cleanup fails with `ENOTEMPTY`: the wide-task fixture enables an unused
restart cache whose detached writer outlives the server. Its compilation and
sync/async execution assertions pass. The fixture now disables disk caching;
dedicated restart-cache coverage is unchanged. The successful full gate reuses
only verified native evidence; its regression preflight and complete guest suite
pass. Failed-run logs remain in the archive.

Final evidence:
[archive](measurements/ct113-refinement-cache-2026-10-25.tar.gz), 187 files /
1,732,762 bytes, SHA-256
`5367e8465b96b7128b127811006de6e3c1d0abf7af931bdd70909798cf3a8e2f`. Every
archived manifest entry is verified. The archive includes both full-gate
attempts, selected checks, all performance samples/profiles, source pins, a
complete patch against HEAD, the CT113 delta, and rejected trial sources.
Binaries and private gdev sources are excluded.
