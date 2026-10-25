# CT112 completed selected results, 25 October 2026

CT112 preserves completed closure proofs across validated selected-query replay,
including solved captures and their remapping through canonical session reuse.
It fixes a missing reuse boundary without changing syntax. This is one bounded
completed-result family; the five architectural recommendations and the
sub-second ordinary-edit target remain incomplete.

The frozen candidate passes full correctness qualification: 2,586 exhaustive
native laws, 1,660 release guests, 48 smoke tests and 57 tooling checks. The
selected development check also passes with zero Zig lint findings. CT110 remains installed;
CT111 and CT112 are uncommitted and have not been pushed or installed.

## Candidate and scope

- Source base: `e56375d18f32b0aef300fb4b80b9a3c0f2c1632d` plus CT111 and CT112.
- Candidate: `build/bench/ct112/candidate-2-blotc`.
- Release SHA-256:
  `8b08627a14f7e3f8f48d715af056321d42428fd7f3fd5456f6e91963e8ab27c5`.
- Compiler identity SHA-256:
  `5cce04ac87fe880e5db7129b4b51513398bd7f776f8771a3110f67b7f5e4a81b`.
- Immediate baseline: CT111 candidate 8, SHA-256
  `efb953d79cf6952841e28a20d48570f2ee324a0811f475e8999131f81cb70adf`.

The candidate uses 1,004 pinned compiler/test/client/tool inputs in
`build/bench/ct112/qualification-work/blot2`, with frozen sibling fixtures.
Concurrent changes to `backend/owned_arrays.zig`,
`backend/owned_arrays_tests.zig` and `tests/owned_array_execution.test.ts` are
preserved in the shared checkout and excluded from the candidate. Qualification
does not cover those changes or a later combined source.

## Implemented boundary

A validated query now restores both `input + expected -> selected` and
`selected + expected -> selected`, as fresh specialization already does. A
native receipt also owns the exact closure results frozen by its fully solved
region. Replay validates their graphs and evidence, reserves all publication
storage, then publishes their completed keys with the outer graph. Canonical
session replay remaps the receipt's captured IDs with the returned graph.

Typed views and imported values alone gain no completion authority. Existing
source, capture, effect, depth, option, alias and negative memo observations
remain required. The portable schema is unchanged and omits nested completion
claims, so restart rechecks those closures. This does not provide a general
elaborated-body artifact or the development generic ABI.

## Correctness

The final isolated `static-sharing` development check passes in 29.09 s:
complete 2,586-law native compilation, 120 sampled native laws, 68 guests,
formatting/types and zero Zig lint findings. It overlaps release construction,
so its duration is not a quiet compiler-build measurement. All 2,586 native laws
also pass with sampled allocation failures in 30.82 s. Sampled execution is not
exhaustive qualification.

The release guest preflight passes all 1,660 tests in 36.11 s, including unchanged
allocation budgets. Its first attempt stopped because a test helper could not
write Zig's cache; rerunning with cache access passes. Earlier development
failures and fixture repairs remain in the evidence. No assertion, budget or
eligibility gate was weakened.

New laws cover nonempty completed capture graphs, allocation-failure publication
atomicity, old-owner destruction, changed expectations, canonical remapping under
forced collisions, and zero additional inference when consuming proved results.
Executed-Wasm coverage exercises both codegen tiers through unrelated edits,
changed callback bodies, type rejection, recovery and reversion.

Full gate `run-9263f29d9030a6fb` passes in 723.99 s:

| Check | Result |
| --- | --- |
| Native, Safe/noLLVM, exhaustive allocation failures | 2,586 passed; 635.97 s |
| Release executed-Wasm/client/formatter guests | 1,660 passed; 39.74 s |
| Development smoke | 48 passed |
| Gate tooling | 57 passed |

The native runner itself reports 635.76 s; 635.97 s includes its gate phase
wrapper. All four shards complete. The full gate validates the exact inventory
and pins raw native evidence in its resume journal; those evidence hashes also
verify afterward. The source snapshot still matches all 1,004 pins, and the
release produced by the gate matches the measured executable hash. Native-only
reports deliberately leave `qualifies_release` false; the successful full gate
with smoke, tooling and release guests is the qualification result.

## Performance screen

Three alternating unprofiled release pairs use the unchanged 554-file gdev
snapshot, optimized tier, four codegen workers, default semantic-worker policy,
200-million inference budget and disabled disk cache. All strict Wasm hashes,
independent fresh controls and input pins pass. The fresh CPU guard passes with
ratio 1.044 against limit 1.050. No build or test runs concurrently with timings
or the separate profile. Every sample is retained.

| Phase | CT111 wall median | CT112 wall median | Paired CPU change |
| --- | ---: | ---: | ---: |
| Fresh game | 6.792 s | 7.323 s | +4.4% |
| Literal edit | 3.170 s | 2.863 s | -2.4% |
| Literal revert | 2.841 s | 2.657 s | -5.7% |
| Body edit | 5.266 s | 4.754 s | -9.5% |
| Body revert | 5.118 s | 4.610 s | -6.5% |
| Fresh devtools | 0.662 s | 0.656 s | -1.4% |

CPU changes are medians of within-pair ratios. Body-edit pair changes range from
-11.5% to +2.2%; body-revert changes range from -11.7% to +10.5%. Fresh game CPU
rises in all three pairs. Peak RSS stays essentially flat: fresh 485.6 to 483.6
MiB, literal 695.9 to 696.6 MiB, body 758.1 to 758.9 MiB.

These are screening observations, not an established 9.5% compiler improvement.
The deterministic work reduction below is much smaller than the timing changes,
and the separately timed CT111 profile also ran slower across unchanged work.
Do not assume the timing variation is caused by this patch or combine these pairs with the
earlier CT110-to-CT111 comparison. The candidate is not promoted locally.

## What remains expensive

| Region stage | CT111 literal | CT112 literal | CT111 body | CT112 body |
| --- | ---: | ---: | ---: | ---: |
| General | 707 | 707 | 5,313 | 5,313 |
| Specialization | 1,660 | 1,660 | 1,349 | 1,351 |
| Preparation | 0 | 0 | 0 | 0 |
| Lowering | 547 | 538 | 534 | 527 |
| Total | 2,914 | 2,905 | 7,196 | 7,191 |

Replay restores 183 completed closure claims on a literal edit and 193 on a
body edit. Most did not trigger repeated inference before this patch. Net solver
nodes fall by only 1,628 and 750 respectively. Fresh counts are unchanged. Body
principal hits remain 17/20; the three misses still construct 3,388,263 nodes.

The current body profile attributes 3.327 s of exclusive coordinating-thread CPU
to inference, 0.349 s to lookup, 0.230 s to evaluation and 0.180 s to constants.
The three principal queries take 2.150 s of inclusive wall time; this is nested
work and must not be added to the exclusive CPU figures.

Body code-evidence solving still opens 1,106 regions and constructs 1,504,629
nodes. Static closure serialization still opens 326 specialization regions and
constructs 501,435 nodes during lowering. Fragment lookup visits 299,191 bucket
positions; static graph matching separately visits 3,894,971 plan positions.
Backend allocation traffic remains 2.326 GB across 2.403 million requests;
cumulative requested bytes are not peak resident memory.

The specialization service already caches complete refinement mappings: the body
edit makes 11,782 requests, serves 9,408 locally and 1,087 across revisions, then
solves the remaining 1,287 (1,106 named bodies and 181 captured closures). This is
not an uncached subsystem. Its cache excludes instance mappings, explicit captures,
custom projections and nested receipt recording; publication also declines
queries that used physical holes. Candidate-level rejection counts are not a
request-level explanation of the 1,287 remaining solves.

The next measurement should classify those remaining requests by admission,
exact key, observed dependency and completion status before adding another cache.
`solveEvidenceOwnedCode` bypasses the constant recorder for borrowed code
expectations/projections, but the surrounding refinement service covers a bounded
family independently. Extending the completed-body boundary must build on that
service, own missing projection/capture inputs and retain more than type/row
mapping results. It must not weaken validation or confuse representation identity
with semantic identity. Further widening the completed-closure cache is not
supported by this screen.

## Evidence

The [evidence archive](measurements/ct112-completed-results-2026-10-25.tar.gz)
contains 219 files (2,343,227 bytes), including source/binary pins, the exact patch
against the source base and the nine-file CT112 delta against CT111, every timing
sample, five strict-output profiles, selected and broad sampled checks, failed
attempts, release guests and the final exhaustive gate with raw shard evidence.
The manifest verifies every archived payload. Private gdev source and executable
binaries are excluded.

Archive SHA-256:
`11cc56e8e867d29604815c6fe7dc2608494e4b619bbea9f45b62f2681dc25590`.

Local reproduction and intermediate evidence remain under `build/bench/ct112/`.
No commit, push or installation is included in this checkpoint.
