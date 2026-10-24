# CT109: bounded backend reuse and narrower source observations

The complete compiler gate passes on Candidate 10. Seven final release pairs
and held-out execution controls also pass.
The final 200-distinct-edit memory series and local installation checks pass.

The [86-proposal ledger](../COMPILER_CT109_LEDGER.md) records the outcome of
every proposal. All eight previously marked “Remaining” have implementations or
measured trials. Partial and conditional architectures remain explicit; this
is not a claim that a shared IR, unified query graph or resumable inference has
been implemented. [The work record](../COMPILER_CT109_WORK.md) preserves each
candidate, rejected experiment and failed qualification run.

## Candidate and comparison controls

Baseline commit: `57418df2df0a5485c9f1e3a2d5ab259ee91aab22` (CT106).
Baseline native SHA-256:
`7d7ea08313e865a633ec9be2acc0347bc1560490ce8caca82e96df1c5b2dba69`.
Candidate 10 native SHA-256:
`6b9ed919a48f4d98b7faaedee3ac25cd87e931601189eb1d1d4239fbd3842b1c`.
Compiler identity-file SHA-256:
`00dfbeee5d4c62ec9dff2d76f8a4b9f5a95b60d55dac4bdccae2e0fd794cdbe0`.

The 554-file frozen gdev/Ink/stdlib manifest remains
`d54b0078ea7c8f94fae131e19f7ea46699891d6aba14b61803386595e9704146`:
189 game modules, optimized codegen, four backend workers, a 200-million
inference budget, profiling off and persistent restart cache disabled.
Performance measurements run without this task's compiler builds or test gate
in parallel. Unrelated host applications remain active. Strict Wasm pins and
independent fresh controls remain mandatory; no output difference is waived.

## Seven alternating release pairs

| Workload / phase | CT106 wall | CT109 wall | CT106 CPU | CT109 CPU | Paired CPU change |
| --- | ---: | ---: | ---: | ---: | ---: |
| game / fresh | 7.832 s | 7.840 s | 8.060 s | 8.050 s | +0.1% |
| game / edit:literal_in_body | 3.201 s | 3.261 s | 3.490 s | 3.480 s | -0.6% |
| game / revert:literal_in_body | 3.047 s | 2.950 s | 3.330 s | 2.920 s | -11.5% |
| game / edit:body_change | 5.410 s | 5.377 s | 5.650 s | 5.520 s | -2.5% |
| game / revert:body_change | 5.453 s | 5.310 s | 5.710 s | 5.270 s | -7.5% |
| devtools / fresh | 0.771 s | 0.781 s | 0.810 s | 0.810 s | -1.2% |

Changes are medians of within-pair CPU ratios. All seven pairs are retained;
all strict Wasm pins, retained/fresh controls, restoration and input checks pass.
Fresh-game and devtools CPU stay within the 5% guards. CPU includes all process
threads at 10 ms resolution; no-op and tiny-fixture ratios are not meaningful.
Host load moves from 3.95 to 2.99 on 16 logical CPUs. Wall excludes process and
project opening; these are shared-host observations, not quiet-host bounds.

First-literal CPU is effectively unchanged. Reverts improve, but the proposed
10% first-literal and 20% body targets are not met. Body wall falls only slightly.
Neither two-second nor sub-second ordinary edits are reached. The extra body
principal hit and large reuse counts do not imply a comparable end-to-end gain.

Candidate first-literal wall ranges 3.187–3.354 s; body wall ranges 5.341–5.641 s.
Median lifetime peak RSS is 481.36 → 480.94 MiB fresh, 688.01 → 696.07 MiB
after the first literal, and 754.12 → 754.55 MiB after the body edit. These
retained peaks include earlier requests, not just per-edit live storage. Full
ranges, paired order and raw samples are archived.

Three alternating pairs over 11 held-out cases pass exact fresh/edit/revert
outputs. All 44 original/edited Wasm executions across both compilers pass
independent result oracles. The cases cover wide records/effects, closures,
shared DAGs, multi-module changes, tiny inputs and the new lexical generic
schemes. Their CPU times are mostly below useful tick resolution; these are
correctness and regression controls, not separate speedup claims.

## Implemented boundaries

- Optimizer captures have their own 16,384-record / 8 MiB index-capacity limit.
  The generic 4,096-record limit had prevented all 8,550 game functions from
  sealing. Generic query limits remain unchanged. RC verdicts require exact
  optimized graph/summary and arena, cohort and fixture-helper correspondence;
  module-wide ownership admission still runs.
- Encoded function bodies require the same physical ordinal, index mapping,
  globals and complete emission context. Both retained payload and allocated
  capacity are limited to 8 MiB. Full sections and complete output are still
  emitted; this is not a delta-output protocol or persistent restart format.
- Workers consume a compact heavy-first queue of actual optimizer/RC work.
  Deterministic ties, source-order publication and failure selection remain.
  Optional worker wall intervals and Linux thread CPU are separate measurements.
- Unique declaration names at matching binding ordinals establish identity;
  ambiguous or moved declarations decline. Uniform relative diagnostic positions
  permit an otherwise exact projection. IDs, graph edges, payloads, types and
  transitive dependencies remain authoritative. The body-edit profile reaches
  17/20 principal hits, from 16/20.
- Only existing checked-scheme reuse with no binding/body obligations records
  an interface observation. Its proof checks exact identity, schemes, rows,
  flags and catalogs. Actual body/value/executable reads retain their stronger
  dependencies. The owned key is portable format v8, with shared read bounds,
  duplicate handling, corruption rejection and OOM laws.
- Receipt source admission is memoized only within bounded immutable owner-pair
  plans. Dynamic budgets, configuration, values, negative reads and proof checks
  still run. Projection scratch uses generation-tagged arrays and a reused stack;
  static-capture matching uses existing sparse scratch with exact owner guards.
- Immutable lexical lists above 16 entries use owner/span-keyed sorted indexes,
  capped at 64 lists / 16,384 IDs. Tiny and oversized lists stay allocation-free;
  cache headers are allocated only on demand. Caller descriptors are static;
  fresh solver counters merge once without redundant saved zero baselines.
- Asset replies write borrowed segments after checking their combined length.
  The compiler and asset owners survive through flush. The framed wire format
  and error/commit ownership rules remain unchanged.

The final unprofiled release confirms the reuse paths (8,550 physical functions):

| Game request | Principal hits | Optimized bodies reused | RC verdicts reused | Encoded bodies reused |
| --- | ---: | ---: | ---: | ---: |
| first literal | 20/20 | 1,711 | 1,652 | 1,711 |
| literal revert | 20/20 | 8,490 | 8,431 | 8,490 |
| body edit | 17/20 | 4,789 | 4,730 | 4,789 |
| body revert | 17/20 | 8,510 | 8,451 | 8,510 |

Runtime helpers account for the RC-count difference. The retained optimizer
capture reports 40,005,609 owned/capacity bytes, including 1,581,080 query-index
capacity bytes, across these requests. This is one owner's accounting, not
process RSS or a claim that the whole compiler fits within that size. One
body optimizer match reaches its work bound and conservatively falls back.
These work counts explain coverage; the release-pair table supplies the actual
CPU and wall result.

## Attribution and rejected trials

The bounded 32-caller census measures regions, scopes, nodes, requested solver
and scratch bytes. Region wall time is inclusive and overlaps nested regions;
it must not be added to exclusive inference time. Linux thread CPU measures
exclusive phase work; unsupported platforms report no CPU clock. Source-validation
work is attributed to its original owner, separately from zero-work leases.

On the first literal in Candidate 5, executable fragment imports make
4,006,913 semantic queries, with 4,006,179 hits and only 734 new nodes. A 2 KiB
hot-cache trial avoided 4,005,352 map lookups but did not establish an ordinary-edit
benefit: three alternating unprofiled pairs show about 5% worse body CPU. The
extra cache was removed. This evidence does not support replacing all import
ownership merely to avoid millions of graph copies: those copies do not occur.

Three row-cache-off pairs regress first literal/revert CPU about 7%, so the
existing row cache stays. A same-capacity two-way composite-cache trial saves
only 184 probes out of 3.83 million and does not establish an ordinary-edit
benefit; the direct map stays. Free-variable summaries produce two hits from
20,974 type queries and zero from 20,845 row queries, so that trial is removed.
All trials preserve their source pins and raw outcomes.

The remaining body declines are actual consumed-source reads: `walk_material`
has two requirements and `haul_all_observed` has seven. They cannot be admitted
by the new obligation-free interface proof. Shared IR, precise incremental
constraint invalidation, internal cache/TLB attribution and private proof-log
parallelism remain separate unfinished designs. Two-second and sub-second
ordinary-edit targets remain open.

## Asset and wide-scheme controls

Five alternating Candidate 3/4 asset pairs cover 40 requests with two 8 MiB
assets, independent asset hashes, exact Wasm and executed answers before and
after edits. Fresh median lifetime HWM falls 48.99 → 32.07 MiB; edit HWM falls
69.32 → 51.24 MiB. Server wall medians are 66.78 → 65.66 ms fresh and
66.99 → 65.72 ms edit. CPU ticks are too coarse for a useful speedup claim;
these measurements exclude client memory and process opening.

The wide lexical generic fixtures at widths 32/64 publish two membership
indexes and hit both, with eight small-list preparations. Earlier globally
generic fixtures made zero membership calls and are not evidence for that path.
These tiny fixtures establish coverage, not a measured gdev speedup: gdev lists
remain on the small linear path. Static-capture scratch likewise records no
calls on gdev.

## Qualification and regression repair

The first full gate fails an extended fixture recording three observation kinds
under its old two-read cap. The fixture is corrected to test duplicates exactly
at the three-read bound and a fourth distinct read declining; production
admission is unchanged.

The second gate passes all 2,573 exhaustive native laws, then fails the release
allocation guard for the 64-link generic chain: 8,994,657 bytes exceeds the
unchanged 8,963,842 limit. Candidate 10 removes 30,912 requested bytes from this
fixture through smaller per-region storage. All 11 release budget tests pass.
The same-path short probe is 8,962,911 bytes (the full guest path adds 834).
The remaining headroom is narrow; budgets were not raised. The qualified older
Safe/noLLVM development compiler also exceeds that release-only guard, so it
is not used as a development-mode selection without separate calibration.

The final full gate, `run-d644cc958a2cea54`, passes in 711.82 s:
2,573 native laws with exhaustive allocation-failure sweeps (651.07 s),
1,656 guests, 48 smoke tests and 57 tooling tests. The 1,672 completed OOM profiles record 812,228 scenario executions, including
ordinary and injected-failure runs. Two intentionally incomplete profiles verify
unexpected-error propagation in the sweep harness. Four native shards take
630–651 s. All native compilation uses Safe/noLLVM; complete inventory
compilation takes 8.63 s. The already built LLVM release is reused exactly.
Standalone native-runner metadata always marks `qualifies_release: false`;
the complete outer gate supplies qualification and reports no active phases.

Zig lint reports zero findings across 521 native source files and the build
file. The final pins cover 1,003 matching source, test, client and tool inputs
in the working tree and isolated checkout. The latter has frozen sibling test
fixtures, avoiding changes in the live neighboring project. Sampled development
checks remain separate: the last complete selected cycle takes 25.73 s, which
is not a paired compiler-build speedup claim.

## Distinct-edit memory

The final candidate passes 232 requests over 200 distinct literal edits, with
12 independently compiled fresh controls plus no-ops, errors, recovery and
restoration. Unsampled revisions do not have independent fresh controls.
Post-edit RSS is 475.29 MiB at edit 1, 488.00 MiB at edit 40 and 520.90 MiB at
edit 200. Idle/restored RSS is 520.91 MiB; lifetime HWM is 773.92 MiB. No swap
or major faults are reported. This is a process-memory experiment, not an
isolated latency comparison or a proof of indefinite memory bounds. Historical
CT106 RSS is not a paired memory baseline for this run.

VmData is 1,612,472 KiB after successful edits 10–150 and 1,659,952 KiB at edit 200, a late
46.37 MiB increase. Every distinct-edit build reports 40,005,609 retained optimizer bytes.
The unprofiled run does not attribute that process mapping growth to an owner;
physical allocator/copy attribution remains open in the ledger.

## Installation and archived evidence

The exact qualified native compiler is packaged and installed without another
Zig build. Both `~/.local/bin/blot` and `blotc` pass external-directory format,
check and build; CLI/native/staged Wasm match and execute with answer 29. The
bundled guide matches the source. The installed CLI SHA-256 is
`5e7b9ca4b6bb1c3fac1a45a0d69035a3af59584f475b493d7ab7900b35b44d58`;
the native hash matches Candidate 10 above. Installation and rollback proof is
`build/install/ct109/installed.json`, with prior binaries retained in
`build/install/ct109/previous-x1t645eq`.

[The evidence archive](measurements/ct109-2026-10-24.tar.gz) contains final and
failed gates, source/input/binary pins, ten candidate source snapshots, negative
trials, profiles, raw paired samples, memory controls and installation evidence.
It excludes compiler executables and private workload source. The archive has
an internal `SHA256SUMS` (all 743 entries verified) and an
[external checksum sidecar](measurements/ct109-2026-10-24.tar.gz.sha256).
Archive SHA-256:
`98ee5f576164d089e4d5d41c7d642eb70f98829e25ff8c0f5c40fec34c21cb5f`.
