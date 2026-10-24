# CT109 remaining compiler performance work

Active follow-up to the user's request to finish the remaining proposals in
[CT105](COMPILER_REVIEW_CT105.md). CT106's [ledger](COMPILER_CT106_WORK.md) is
the baseline, not a completion claim.

Baseline: commit `57418df2df0a5485c9f1e3a2d5ab259ee91aab22`, installed native
SHA-256 `7d7ea08313e865a633ec9be2acc0347bc1560490ce8caca82e96df1c5b2dba69`. The
baseline is preserved at `build/bench/ct109/baseline-blotc`. Keep the frozen
554-file workload and CT103 output hashes. Temporary files use
`build/bench/ct109/tmp`; `/tmp` is nearly full.

## Candidate 1, archived experiment

- #12/#18: operation-row probe, collision, stale-history, context and
  publication counts; composite probe, collision, changed-frontier, future-clock
  and admission counts. Policy ablations are still pending.
- #17: lazily allocated 16-slot free-variable summaries, at most 32 IDs per
  entry, admitted only after at least 16 distinct traversal nodes. Exact type
  and effect mutation clocks revoke writes, physical edits and rollback. No
  projection-fuel traversal is memoized. Returned slices retain their caller's
  ownership and original ordering.
- #27: region-local sorted membership summaries for immutable Core lists above
  16 entries, keyed by exact unit owner and list span. Up to 64 lists / 16,384
  IDs are retained; small lists and saturated admission keep linear lookup.
- #37: memoize the immutable source-admission portion of completed-query
  receipts in the existing bounded owner-pair plan table. Options, budgets,
  observed values, proofs and negative reads still validate on every query.
- #64: compact backend work queue, ordered by descending instruction count with
  deterministic ordinal ties. Results and failures publish in source order after
  all workers join.
- #66: retain the final optimized-body RC verdict under the optimizer's exact
  graph/summary correspondence plus exact arena, cohort and fixture-helper
  roles. Verdict reuse has separate counters; it does not skip module admission.
- #72: retain emitted function bodies in one bounded 8 MiB byte buffer. Reuse
  requires an unchanged physical body, function-index mapping, import/type/
  global/function counts, globals and lowering facts. Changed contexts encode
  again. Section order and complete module publication stay unchanged. These
  transient caches are deliberately absent from restart archives.

Development check `run-6081d42698577cc7` passes in 24.80 s, including full
native inventory compilation, the expanded sampled regression family, selected
guests, formatting/types and zero Zig lint findings. This is **not full
qualification**. An earlier run had one ownership-lint finding, fixed by
explicitly releasing the empty cache allocation before replacement. Another run
passed its phases but detected source edits during execution and is retained as
stale, not a pass.

Next: release cache/work counts and paired output/CPU/memory measurements;
operation-row ablation and composite-cache policy trial; stable declaration
origins and remaining partial/conditional proposals. Keep implementing before
the final isolated exhaustive gate, documentation, commit/push and installation.

## Candidate 2 and current work

Candidate 2 SHA-256:
`6e16f40b735cc60b2b7f02332aba36ccafe2b6f3523719de7ceff9a63930ec0a`. Its
fixed-source development check `run-7309c7b5d9514214` passed in 24.37 s.
`profile-2/results.json` passes all strict output hashes and input pins. The
single profiled pair is diagnostic evidence, not a performance qualification.

The optimizer's generic 4,096-record query limit could not seal the 8,550-body
game capture, disabling every optimizer reuse candidate. The optimizer now owns
a bounded 16,384-record / 8 MiB index budget; generic tables retain their
limits. Candidate 2 seals all 8,550 records, using 1,581,080 index-capacity
bytes. It reuses 1,711 optimized/encoded bodies on the first literal edit, 8,490
on the literal revert, 4,789 on the body edit and 8,510 on its revert. RC
verdict reuse has separate counters and exact role/context checks. Captured
encoded bytes remain bounded to 8 MiB and are absent from restart archives.

Owned declaration spellings establish unique origins within an already paired
unit at the same binding ordinal. Duplicate names and moved ordinals decline.
This admits call identity across byte movement; body and executable validity
remain separate. The four body-principal declines now pass identity and decline
on source unit 42 / binding 35. Current root adds owned diagnostic spelling and
source-point fields to identify that dependency before narrowing its proof.

The immutable portion of completed receipt validation is reused: first literal
has 271 source checks / 2,979 memo hits; body has 277 / 2,999. Dynamic
observations and query configuration still validate on every request.

The free-variable summary trial is **rejected** and removed from current root:
20,974 frontend type queries produced two hits; 20,845 row queries produced
none, with 21 publications. Inference made no such queries. Candidate 2's source
archive retains the prototype and its semantic/OOM law; query/visit counters
remain in production. These numbers do not justify the extra cache.

Current root adds a fixed 32-caller region census (with explicit overflow),
recording inclusive wall time, solver/scratch requested bytes and allocations.
Nested times overlap. Backend worker intervals count jobs/instructions and use
private counters published once per worker; they are wall time, not CPU time.
Scheme-membership preparation/hit/admission counters quantify the remaining
bounded index. A declaration-projection workspace reuses generation-tagged
visited tables and stack capacity across one module's declarations. Declined
scans, generation rollover and allocation failures have a regression law. The
exact projection comparison is unchanged.

`dev-6` passed native/guest phases but failed lint on a deprecated
source-location type. That spelling was fixed; subsequent
instrumentation/workspace edits still need their own fixed-source run. No CT109
full gate or installation is claimed.

## Cache policy ablations

Both release trials start from the archived Candidate 1 source; each changes
only its policy. They use three alternating unprofiled pairs, strict CT103
outputs, the frozen manifest, ordinary edits/reverts and devtools controls.

`row-ablation-pairs` completes with all output/input checks passing. Disabling
operation-row caching yields paired median CPU ratios of 0.941 fresh, 1.073
first literal, 1.074 literal revert, 1.001 body and 1.000 body revert.
Shared-host contention was severe (one fresh request took 225 s wall / 12.55 s
CPU), so the trial does **not** establish an ordinary-edit improvement. Keep the
production policy while preserving the probe/collision/history instrumentation.
The raw single-fresh CPU guard passes, but does not qualify the other edit
classes.

The same-capacity two-way composite-cache trial also passes all output/input
checks. Paired median CPU ratios are 1.025 fresh, 1.000 first literal, 0.994
literal revert, 0.941 body and 0.997 body revert; load fell from 19.1 to 8.5.
Fresh deterministic work changes only from 11,608 to 11,852 composite hits and
3,829,410 to 3,829,226 probes. This does not establish a useful ordinary-edit
benefit for paying a second slot check on millions of probes. Keep the original
16-slot direct map and the new diagnostics; the complete isolated prototype and
corrected patch remain archived.

The static-capture matcher now uses the existing `QueryScratch` protocol for
repeated static-key comparisons, instead of allocating/clearing full anchor,
position, candidate and inverse arrays for every key. Owner, generator, session,
gate and row-policy guards remain exact; sparse cleanup runs on failure too.
Static replay's existing fresh-output/alias/OOM law now asserts this path was
exercised. Backend statistics expose scratch calls, cleared positions and bytes.

## Candidate 4: positions, clocks and asset replies

The isolated release is
`d2d6e440c0d725f36faba5c396a1147975f1510c35500b0e97aaea753f1513a1`. Development
check `run-18eea4194b15cfbc` passed in 27.28 s. Every source input was pinned
before release and verified after building. The real sibling gdev checkout was
changing during earlier checks, so qualification now uses copied, frozen sibling
fixtures. A stale-input run is not counted as a pass.

Unique declaration origins now permit a uniform relative translation of
positions within an otherwise exact declaration graph. Captures, payloads, IDs,
types, graph edges and transitive observations remain exact; inconsistent
positions decline. This admits the unchanged `robot` declaration after an
earlier `floor` → `ceil` edit. The body edit now has 17 rather than 16 principal
hits. The remaining three declines name `walk_material` and `haul_all_observed`;
their ~2.27 s inclusive principal work is still present. This is not a claim
that moving positions explains all body-edit cost.

The 32-caller census attributes first-literal work mainly to
`solveEvidenceOwnedCodeInner` (~0.72 s / 1,420 regions), retained specialization
(~0.27 s), source interfaces (~0.18 s) and closure inference (~0.13 s), in the
Candidate 3 diagnostic pair. Nested wall clocks overlap. Candidate 4 adds
exclusive Linux coordinator thread CPU by backend work phase, plus independent
worker thread CPU. Backend workers finish within about 0.1 ms in the preceding
profile; that does not establish false sharing or cache/TLB contention. Original
source-validation owners now report their projection work separately from
zero-work retained leases: 165 scans / ~13,630 visits / 61,164 peak scratch
bytes on the body edit.

`profile-4` completed its compiler requests, but its report aggregation failed:
the old summarizer mistook the new `thread_cpu_us` object for a scalar wall
clock. The raw samples are retained as an **incomplete experiment**. The
summarizer now handles exclusive thread CPU separately; its 12 tooling tests
pass. Candidate 4's profiled slowdown is not an unprofiled performance result.

The asset path writes the existing Wasm and asset slices sequentially through
one framed reply, after all lengths and metadata pass validation. Commits retain
the owners through the final flush. `assets-4` passes five alternating pairs, 40
requests, independent asset SHA-256 checks and executed Wasm results on every
request. For two 8 MiB assets, median fresh compiler HWM drops 48.99 → 32.07
MiB; source-edit HWM drops 69.32 → 51.24 MiB. Median client latency is about 67
→ 66 ms. The experiment excludes client RSS and process startup; CPU tick
resolution is too coarse to claim a large CPU improvement. Source, compiler and
asset pins are recorded. The native segmented-frame law also rejects size limits
and sum overflow before writing anything.

## Candidate 5: checked interfaces and import attribution

A principal read made by the existing checked-scheme branch now records a
separate interface observation when both binding and body schemes have no
obligations. Its admission proves the unique callable origin, exact binding and
body schemes, closed rows, function/runtime flags and semantic catalogs. Actual
body reads still require exact local-body admission. This observation grants no
executable or evaluated-value authority. Interface observations own their
storage, count toward the recorder bound, survive cloning and use principal
archive key v8. Duplicate and invalid portable interface reads are rejected;
portable byte accounting now includes module observations too.

Native laws check current-output parity, changed staged bodies, reverts,
stronger body dependencies, source ownership and allocation failure. An
executed-Wasm law checks both tiers, add/subtract body edits, divide-by-zero
errors and recovery against fresh compilers. The earlier body-dependency law was
strengthened to explicitly record a body read; it had previously relied on the
checked-scheme branch's overly broad observation.

Direct captures with unsupported canonical replay kinds now decline before
constructing the complete capture key. The existing pending-demand identity and
memo-state law proves that this saves key construction while preserving ordinary
evaluation and lexical-key behavior. Import census counters separately report
semantic/row memo hits, new nodes and copied child/argument words for principal,
completed-query and executable-fragment import owners. Existing maps already
deduplicate repeated imports inside one owner; no cross-owner map sharing is
inferred from equal numeric IDs.

The held-out corpus now adds 32- and 64-variable generic schemes, because gdev
uses only small membership lists and cannot qualify the large-list index.
Static-capture scratch also has zero gdev calls; its semantic/OOM regression
exercises the path, but no gdev speedup is attributed to it.

Development check `run-6bf04e026243dfa8` passes in 47.68 s, with 2,572 native
laws compiled, 92 selected laws executed with sampled allocation failures,
guests, format/types and zero Zig lint findings. Candidate 5 release and
performance measurements are pending. Full exhaustive qualification, final
documentation, commit/push and replacement of the installed CT106 compiler
remain pending.

## Candidate 6: avoid repeated semantic memo hashing

Candidate 5 native SHA-256 is
`f506d94207f0bdc893359e7314ad4d718ea9fe42d6ffc003d3c0e5b687398bab`. Its game
samples preserve strict output but still have 17/20 body principal hits: the
narrow obligation-free interface proof does not remove the remaining three gdev
body dependencies. Do not weaken those observations to force reuse. The combined
`profile-5` experiment is **failed**, because the initial curried wide-generic
fixtures exceed both compilers' complexity limit. The raw game samples remain
diagnostic data, not a completed performance qualification.

The new import census changes the attribution: on the first literal,
executable-fragment imports make 4,006,913 semantic queries with 4,006,179 memo
hits, 734 new nodes and 2,363 copied child words. Principal imports make 67,752
queries / 52,947 hits / 14,805 new nodes; completed-query imports make 71,199 /
67,794 / 3,405. The dominant fragment path is repeated hash lookup, not repeated
graph copying. Cross-owner deduplication is therefore not the first remedy.

Candidate 6 adds a 256-entry (2 KiB) direct cache of exact positive default-role
semantic mappings inside the already bound importer. Every slot retains the full
old ID and translated result; collisions fall through to the authoritative map.
Owner-specific mapping records never enter it. No new source/destination owner
admission is inferred. Existing namespace relocation and complete import OOM
laws now exercise hits, forced same-slot collisions, disabled-cache parity and
rejection of another generator before a hot lookup. New counters distinguish hot
hits from all memo hits. No per-query allocations are added.

The first two revised generic shapes compiled but did not call lexical sharing;
those samples are not evidence for the membership index. The final public
fixture uses a local generic record function inside staged inference.
`quantified-5-lexical` passes fresh/edit/revert output controls at widths 32/64.
Each fresh candidate makes 12 preparations: eight small, two publications and
two hits, retaining 64/128 indexed IDs. These tiny cases qualify path coverage,
not an end-to-end speedup. Their latencies are below useful CPU-tick resolution.

Development check `run-362d34de7fd9d56` passes in 14.50 s, including 93 selected
native laws, selected guests and zero lint. The preceding run executed all laws
successfully but rejected a duplicate selection entry; it remains incomplete.
Candidate 6 also includes diagnostic-only requirement counts and an interface-
observation flag on source declines. Its pinned LLVM release is building; full
native compilation/exhaustive execution and release qualification remain
pending. Installed CT106 is unchanged.

## Candidate 7: exact allocation cap and final checks

Candidate 6 release SHA-256 is
`5733cac406ce59d927598f801923427e282c485d51367c14ea21536785aedf52`. `profile-6` completes with exact Wasm and input pins.
On the first literal, its semantic hot cache serves 4,005,352 of 4,006,913
fragment queries, 63,787 of 71,199 completed-query queries, and 21,989 of
67,752 principal queries. New-node counts are unchanged. The one profiled pair
does **not** establish a CPU benefit: first literal is 3.80 → 4.01 s CPU and
body is 5.78 → 6.43 s. Unprofiled pairs decide whether to retain this trial.

The encoded-body payload limit previously allowed geometric capacity growth
beyond 8 MiB. Candidate 7 caps the allocated capacity as well as payload length.
A boundary law fills the buffer to its limit and proves an additional write
leaves both the retained span and length unchanged.

Development check `run-a3e6e4ecb45e053a` passes in 26.39 s, including the
94-law selected family. The preceding `run-cedf5f086f159b32` passes in 25.95 s
on Candidate 6 sources: an incorrect scratch-copy path prevented the capacity
fix from being included, so that run is not evidence for the capacity fix.
Candidate 7 pins 527 inputs before the release build. Final release pairs,
held-out executions, distinct-edit memory and exhaustive qualification are
still pending.

The remaining body declines in `profile-6` are full consumed-source reads, not
failed interface observations: `walk_material` has two binding/body requirements
and `haul_all_observed` has seven. The narrow obligation-free interface proof
cannot admit them. Reusing those results requires exact requirement/proof
observations or a more substantial incremental inference design; removing the
source check would be unsound.

## Candidate 8: reject the import hot-cache trial

`hot-cache-pairs` passes three alternating unprofiled pairs and all strict
outputs. Paired median CPU ratios (cache / no cache) are 0.9616 fresh, 0.9878
first literal, 0.9823 literal revert, 1.0496 body and 1.0291 body revert.
Devtools is 0.9744. Host variation is substantial. Avoiding four million map
lookups does not establish a useful ordinary-edit improvement and body CPU
worsens about 5%. The extra cache, toggle and hit counter are removed. The
import work census and exact-generator memo regression remain. Candidate 6
source/binaries preserve the trial.

Candidate 8 retains Candidate 7's allocation-cap fix and all other work. Its
527 input pins match the working tree and isolated qualification checkout.
The exhaustive gate now builds the final LLVM release and compiles every native
law with Safe/noLLVM; final performance and memory qualification follow.

The first exhaustive gate (`run-cea4d7fad4ff44d5`) **fails** the existing
anonymous-module observation law before its OOM sweep. The extended fixture
records three distinct reads (body, module, interface) but retained its old
`max_reads = 2`; the recorder correctly marks its source observations incomplete.
The fixture now admits exactly three, checks duplicate reads at that bound, owns
all three cloned slices, then rejects a fourth distinct read. Production
admission is unchanged. This law is also added to `static-sharing` so development
selection covers the interface ownership extension. All sibling native groups
and the incomplete LLVM release were cancelled by the gate; none counts as a
pass. Candidate 9 records the test/selection fix before fresh qualification.

The corrected mixed-observation law passes its complete allocation-failure sweep
when selected from the installed native binary. Development check
`run-8be9b38b3430d06a` passes in 23.06 s with 95 selected native laws. The
unrelated scalar-read fixture's original two-read bound is restored too (it had
been accidentally increased during the earlier edit). The second exhaustive
gate uses new evidence under `ct109-final-gate-2`; failed evidence is preserved.

## Candidate 10: remove redundant per-region counter baselines

Candidate 9 LLVM native SHA-256:
`d462ffc590f45d8291e764f4f6ce828f54bc1c76efd1bcb57f8eedd97006476a`;
identity-file SHA-256:
`fb008bd7a0dbde637953f770c7d141ca889cd29bc7f699506a2590df80a216c4`.
The second exhaustive native run passes all 2,573 laws in 629.43 s, but the
**overall gate fails** during guests: the 64-link generic chain requests
8,994,657 bytes, above its existing 8,963,842-byte limit. No budget is raised.

A same-path baseline/candidate CLI probe attributes 42,078 additional requested
bytes: 256 checking, 4,420 lowering, 37,402 backend. Profiling on/off yields
identical requested bytes. The installed CT106 baseline was already near the
guard (8,951,745 bytes in that shorter-path probe).

Every ClosureRegion creates a fresh type Store; only its backing arena is
pooled. Its saved normalization and occurs baselines are therefore always zero.
Removing that redundant 256-byte copy preserves exact work accounting while
reducing the retained region-pool node size. The release-only generic-chain budget cannot be added unchanged to the
Safe/noLLVM development selection: the old qualified development compiler
already requests 9,033,617 bytes in the same short-path probe. Development run
22 fails that mistaken selection, which is removed; the original release guard
stays unchanged.

Membership indexes now allocate their map header only for eligible large lists;
small or oversized lists pay one nullable pointer. Their work counters belong
to the Session instead of every region. Caller descriptors are static constants
shared by regions and the 32-entry census, including copied result snapshots.
Neither change removes attribution or lowers a cache/census limit.

After the lazy cache and region caller-pointer changes, the Safe/noLLVM probe
requests 9,044,783 bytes, 30,912 fewer than Candidate 9's inferred development
cost. Development run `run-8990fc8873fbe3ac` passes in 25.73 s with 95 selected
native laws, selected guests and zero lint. Candidate 10 additionally shares
static caller descriptors inside census entries. Its pinned LLVM release,
unchanged allocation budgets and full requalification are pending.

Candidate 10 LLVM native SHA-256:
`6b9ed919a48f4d98b7faaedee3ac25cd87e931601189eb1d1d4239fbd3842b1c`;
identity-file SHA-256:
`00dfbeee5d4c62ec9dff2d76f8a4b9f5a95b60d55dac4bdccae2e0fd794cdbe0`.
All 11 unchanged release compile-budget laws pass. The short probe requests
8,962,911 bytes; the full guest path adds 834, leaving 97 bytes under the
existing generic-chain limit. This narrow headroom is recorded, not hidden by
a new budget. Census JSON still reports caller names and exact counter fields.
Zero lint findings remain across 521 native source files plus the build file.
The full gate is `run-d644cc958a2cea54` under `ct109-final-gate-3`; 1,003 source,
test, client and tool inputs match the root and isolated checkout byte-for-byte.
The earlier source archives remain distinct from these final qualification pins.

The complete third gate passes in 711.82 s: 2,573 exhaustive native laws
(651.07 s execution), 1,656 guests, 48 smoke tests and 57 tooling tests. Native
compilation uses Safe/noLLVM (8.63 s); the already pinned LLVM release is cached.
Raw standalone native-runner evidence reports `qualifies_release: false` by
design: only the complete gate, including release/guest stages, qualifies the
compiler. The outer gate reports success with no active phases. Seven final
alternating release pairs, held-out executions and 200-distinct-edit memory
qualification now run sequentially, with no task-owned builds in parallel.

The seven final alternating pairs pass strict outputs and the fresh-game/devtools
CPU guards. Paired CPU changes: fresh +0.1%, first literal -0.6%, literal revert
-11.5%, body -2.5%, body revert -7.5%, devtools -1.2%. First-literal wall median
is 3.201 → 3.261 s; body is 5.410 → 5.377 s. This does not meet the ordinary-edit
acceptance targets. Three held-out pairs over 11 cases and all 44 independent
Wasm executions pass. The final 200-distinct-edit memory series is running.

Final memory qualification passes: 232 requests, 200 distinct edits and 12
sampled fresh controls, including no-ops, errors, recovery and restoration.
Post-edit RSS grows from 475.29 MiB at edit 1 to 520.90 MiB at edit 200; idle
RSS is 520.91 MiB and lifetime HWM is 773.92 MiB. No swap or major faults are
reported. Unsampled revisions lack independent fresh controls, and this does
not prove indefinite retention is bounded. All final source pins still match.
Packaging and local installation follow without rebuilding the qualified native
binary.

The qualified CLI and native compiler are installed at `~/.local/bin/blot` and
`blotc`. External format/check/build, exact CLI/native/staged Wasm, answer 29 and
bundled guide all pass. Previous binaries are retained at
`build/install/ct109/previous-x1t645eq`; installation proof is
`build/install/ct109/installed.json`. No additional Zig build was used to package
the qualified native binary. The final evidence archive accompanies this change.
