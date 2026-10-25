# CT113 refinement census and bounded cache

The user requested implementation of the next CT112 target: classify the 1,287
remaining body-edit refinement solves and address avoidable work. CT111/CT112
and concurrent array work are preserved. No syntax change is included.

## Implemented candidate

- Profile-only request census: 32 exact flag groups, explicit overflow, and the
  eight heaviest requests by specialization solver nodes. No per-request
  allocation. Flags never certify reuse.
- Separate missing-positive and now-present-negative call proof rejection
  counts, plus publication-decline reasons.
- Independent proof attempts report private regions/nodes and rejection reasons.
  Workers accumulate locally and the coordinator joins results; shared evaluator
  counters are never mutated by workers.
- Refinement Context limit increases from 4,096 to 8,192 records and from 2 to 8
  MiB of record/index buffers. Payload remains capped at 16 MiB; lookup remains
  capped at 4,096 positions. Source, shape, scalar, call and plain-fact guards
  are unchanged. Small tables still allocate on demand.

The selected static-sharing development family now includes the census law,
common-table collision/capacity/allocation laws, and existing refinement and
independent-proof laws. The frozen cycle passes 130 sampled native laws and 68
executed guests, complete compilation of the 2,587-law inventory, formatting,
types and zero Zig analyzer findings in 28.16 s. It overlapped a diagnostic
workload, so it is not a compiler-build performance comparison. The frozen
candidate also passes the full gate: 2,587 exhaustive native laws, 1,660 release
guests, 48 smoke tests and 57 tooling checks. The release screen is complete
below.

## Diagnostic findings and rejected trials

Safe/noLLVM profiles use the fixed 554-file gdev snapshot and strict CT103 Wasm
pins. They are diagnostic work counts, not release timings. All completed
profile outputs match their byte pins.

The baseline body edit requests 11,782 refinements: 9,408 local hits, 1,087
retained hits, and 1,287 fresh solves (1,106 named, 181 closure). Of those fresh
requests, 813 reach a call-presence mismatch after a candidate passes source,
shape and seed checks; they account for 1,345,784 specialization nodes.
Candidate flags can include other rejected candidates, so these are request
groups, not exclusive individual-candidate causes. Explicit captures account for
128 requests / 79,627 nodes; physical holes 35 / 60,214; multiple-region
observations 24 / 78,917.

The call mismatch is overwhelmingly missing required positive proofs. Accepting
additional completed proofs under unchanged transitive sources saves one literal
region and no body regions. That trial is removed from the final candidate.

An independent recheck trial restores only four extra body hits, while total
body inference regions rise from 7,191 to 7,477. A follow-up census of the
literal edit shows 259 failed probes: 243 return no proof and 16 use multiple
regions. Private probes consume 325 regions / 5,177 nodes. The isolated checker
generally cannot reconstruct these certificates. Refinement-triggered rechecks,
attempt maps, publication staging and their trial-specific tests are removed.
Failed trial sources and measurements remain in the evidence directory. Existing
executable-query independent checks retain their original admission rules.

The fresh-build census finds a separate bounded-cache problem: 4,096 records
fill before 7,838 later publication attempts, accounting for 1,902,076 nodes.
Raising the refinement limit removes all saturation on this workload, saves
4,513 fresh regions (18,381 → 13,868), and removes 550,625 specialization nodes
(3,409,429 → 2,858,804). Records rise to 7,421. Payload plus record/index
storage rises from 5,309,616 to 10,365,152 bytes; this is cache accounting, not
RSS.

The first literal edit gains 476 retained refinement hits (583 → 1,059), with
regions 2,905 → 2,428 and specialization nodes 1,691,374 → 1,649,661. The final
release screen finds a fresh-build improvement but essentially unchanged edit
latency. These observations do not establish a body-edit speedup or sub-second
compilation.

## Release screen

Three alternating pairs compare CT112 `8b08627a14f7` with CT113 `7643273aebdf`.
Both use LLVM ReleaseFast, optimized output, four codegen workers, ordinary
serial semantics (the semantic-worker option is omitted), a 200-million
inference budget, no disk cache, and identical frozen sources. No build or test
workload runs alongside the unprofiled comparison. All 60 recorded samples,
independent fresh controls, exact Wasm pins, input hashes and CPU guards pass.

| gdev scenario      | CT112 wall median | CT113 wall median | Median paired CPU change |
| ------------------ | ----------------: | ----------------: | -----------------------: |
| Fresh              |           7.546 s |           7.078 s |                   -5.21% |
| First literal edit |           3.008 s |           2.991 s |                   +0.32% |
| Body edit          |           5.172 s |           5.217 s |                   -0.96% |

Every fresh CPU pair improves (ratios 0.962, 0.948, 0.939). Edit differences are
small and do not establish an edit-time gain. Fresh peak RSS is 483.6 → 483.4
MiB; first-edit peak RSS is 697.1 → 701.5 MiB. The small devtools control
remains about 0.72 s with paired CPU +1.35%. This is a three-pair shared-host
screen, not a promise for arbitrary projects.

The separate final release profile reproduces the diagnostic work reductions.
Body work falls by only two regions (7,191 → 7,189) and 88 specialization nodes;
three principal misses still visit 3,388,263 nodes. Default executable-query
private proofs add 1,915 nodes on the body edit, now visible separately.

## Qualification retry

The first full run passes all 2,587 exhaustive native laws in 632.80 s, then
fails in guest temporary-directory cleanup (`ENOTEMPTY`) after the wide-task
fixture's compile and sync/async execution assertions pass. Its unused restart
cache leaves a detached writer. That fixture now sets `cacheDirectory: false`;
its semantic assertions and the dedicated cache tests are unchanged. The
regression preflight passes. The final full gate passes in 78.23 s with the
verified 632.80 s native phase resumed; all 1,660 release guests pass in 30.56
s. Raw failed-run logs are preserved. The audit checks 17 journal artifacts, all
1,004 source pins and 1,687 exhaustive allocation sweeps (zero sampled sweeps).
This is a fixture repair, not a compiler or output change.

## Evidence and remaining architecture

Work and frozen qualification tree: `build/bench/ct113/`. The three concurrent
array files retain HEAD contents there; the combined main tree is not covered by
isolated qualification. CT110 remains installed. No commit, push or installation
is part of this turn.

The dominant missing-proof family remains open. The next sound design needs
provenance for the completed proof, including its source and dynamic
dependencies, so it can replay the producing judgment without re-solving an
isolated body. Positive proof absence must not be silently accepted. Three
principal misses still account for 3,388,263 nodes and require the higher-level
interface/body work from the architecture program. This turn does not complete
all five parts.

The final [qualification report](zig-native/CT113_QUALIFICATION.md) pins the
187-file evidence archive and the source/binary audit. Every archived manifest
entry is verified. Documentation and README status reflect the qualified frozen
candidate; the combined concurrent array changes still need their own gate.
