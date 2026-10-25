# CT111 architecture trial, 25 October 2026

The frozen CT111 snapshot passes correctness qualification. It implements the
approved optional `where { result "from" a b }` requirement and bounded
foundations for inferred interfaces, retained semantic queries and shared source
graphs. Existing inferred conversions remain valid. Completed elaborated bodies
and the expanded development generic ABI are still unimplemented; none of the
five recommendations is complete. See the
[implementation record](../COMPILER_CT111_WORK.md) for exact boundaries.

CT110 remains installed. CT111 is uncommitted and has not been pushed or
installed. Three earlier neutral/regressing screens prompted the decision to
stop widening interface shortcuts. The final repaired candidate also shows no
performance improvement.

## Exact candidate and scope

- Source base: `e56375d18f32b0aef300fb4b80b9a3c0f2c1632d` plus the archived patch.
- Candidate: `build/bench/ct111/candidate-8-blotc`.
- Release SHA-256:
  `efb953d79cf6952841e28a20d48570f2ee324a0811f475e8999131f81cb70adf`.
- Compiler identity SHA-256:
  `78dba19707c4f1dc77be0574b8d0c024892bc7fd3b32c818ffc4a4ab62467188`.
- Baseline CT110 SHA-256:
  `b0ebc5ecf07f962665fcc3cf879f5e955eb07f1341a0f2b5b8d783b963228dd2`.

All 1,004 pinned compiler/test/client/tool inputs match the frozen checkout at
`build/bench/ct111/qualification-work/blot2`. Frozen sibling fixtures prevent
unrelated live application edits from invalidating qualification. Concurrent
changes to `backend/owned_arrays.zig`, `backend/owned_arrays_tests.zig` and
`tests/owned_array_execution.test.ts` remain in the shared working tree and are
excluded from this candidate and its evidence. This gate does not qualify those
changes or any later combined source.

## Correctness

Full gate `run-fdcad0e5659ba973` passes in 761.66 s:

| Check | Result |
| --- | --- |
| Native, Zig Safe/noLLVM, exhaustive allocation failures | 2,584 passed; 676.47 s |
| Release executed-Wasm/client/formatter guests | 1,659 passed; 31.91 s |
| Development smoke | 48 passed |
| Gate tooling | 57 passed |

The gate-built release exactly matches the measured candidate's executable hash.
The selected development cycle also passes 113 native laws with sampled faults,
67 guests, formatting/types and zero Zig lint findings. It compiles the complete
2,584-law inventory. Its 37.89 s elapsed time overlaps release construction and
is not a quiet compiler-build timing comparison.

Failed runs remain in the evidence. Qualification found and repaired lost
parameter-annotation provenance and expansion of shared callee graphs. The
release allocation budget then caught 1,360 extra requested bytes on equal
inputs. Deduplicating requirement operands and using bounded stack scratch for
temporary membership lists removes 48,996 bytes and 377 allocator calls in that
fixture. No assertion or budget was relaxed.

The recent-failure preflight also attempted the release allocation budget using
Safe/noLLVM, whose allocation totals differ. Running the complete budget file
through the release guest gate cleared that failure through normal execution;
the subsequent full gate passed. Native resume evidence was never inserted or
altered manually.

## Final performance screen

Three alternating, unprofiled release pairs use the same 554-file frozen gdev
snapshot, optimized tier, four codegen workers, default semantic-worker policy,
200-million inference budget and disabled disk cache. Strict optimized Wasm
hashes and independent fresh controls all pass. Input manifests remain unchanged,
and the fresh CPU guard passes (paired ratio 1.015; limit 1.050). Profiled
diagnostics run separately after the timing samples. Every sample is retained.

| Phase | CT110 wall median | CT111 wall median | Paired CPU change |
| --- | ---: | ---: | ---: |
| Fresh game | 7.779 s | 7.900 s | +1.5% |
| Literal edit | 3.122 s | 3.151 s | +0.6% |
| Literal revert | 2.854 s | 2.851 s | 0.0% |
| Body edit | 5.229 s | 5.294 s | +1.5% |
| Body revert | 5.214 s | 5.283 s | +1.8% |
| Fresh devtools | 0.751 s | 0.768 s | +2.5% |

CPU changes are medians of within-pair ratios, not ratios of aggregate medians.
Peak RSS medians rise from 481.6 to 485.1 MiB fresh, 696.6 to 696.9 MiB for
literal edits, and 755.1 to 758.6 MiB for body edits. These three-pair shared-host
screens do not establish a performance gain. Passing the regression guard is
not meeting the ordinary-edit performance objective. The two-second and
sub-second goals remain open.

## Remaining cost in the final profile

All five profiled fresh/edit/revert outputs match the strict Wasm pins. Body
principal hits remain 17/20. The three rebuilt principal queries construct
3,388,263 nodes and take 2.487 s of inclusive wall time. The coordinating
backend thread attributes 3.886 s of exclusive CPU to inference, 0.413 s to
lookup, 0.283 s to evaluation and 0.213 s to constants. Inclusive principal time
is nested inside other work and must not be added to those exclusive CPU costs.

| Region stage | Literal edit regions | Body edit regions |
| --- | ---: | ---: |
| General | 707 | 5,313 |
| Specialization | 1,660 | 1,349 |
| Preparation | 0 | 0 |
| Lowering | 547 | 534 |
| Total | 2,914 | 7,196 |

Lowering still constructs 523,109 solver nodes on the body edit. Of those,
502,185 come from 331 `specializeRetainedInner` regions. The earlier candidate-3
reduction to 3,529 total body regions did not survive the repair that preserves
shared callee graphs and input-keyed jobs; it was not a sound performance win.
The final totals are only 20 regions below CT110 for either edit class.

Source-graph retention reuses 16 graphs on the body edit and publishes 26 graphs
with 147,984 payload bytes. Completed-interface proof admits one interface and
declines 189; its current-body checks still visit 1,010,999 proof positions.
These bounded foundations do not replace the missing completed semantic result.
Fragment lookup visits 299,191 bucket positions; static-value graph matching
separately visits 3,894,971 plan positions. Those are different operations.

The profiled body backend requests 2.326 GB across 2.403 million allocator calls.
Requested bytes measure cumulative allocation traffic, not simultaneously live
memory. The unprofiled body peak RSS median is 758.6 MiB. The next architectural
experiment needs to complete and retain one actual semantic function result,
then lower it without new general inference. Another expansion of interface
eligibility has not earned its complexity on this workload.

## Evidence

The [evidence archive](measurements/ct111-architecture-screen-2026-10-25.tar.gz)
contains 757 files (6,878,411 bytes), including source/binary pins, the exact
compiler patch, raw samples, profiles, all failed gates and final successful
native/guest logs. All 756 content hashes in its manifest verify. It excludes
compiler binaries, generated Wasm and private sibling sources.

Archive SHA-256:
`ecf726aff4c84c978ae1486feaf5bb78ef9d5ce960014e378ae4ecb9c3e0bb95`.

Primary records inside the archive are `build/bench/ct111/final-summary.json`,
`pairs-8/results.json`, `pairs-8/samples.jsonl`, `profile-8/`,
`full-gate-isolated/run-fdcad0e5659ba973/`, `source-pins.json`,
`shared-checkout-drift.json` and `compiler.patch` under the same CT111 prefix.
