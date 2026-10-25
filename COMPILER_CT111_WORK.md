# CT111 architectural implementation

User-authorized scope: the five recommendations in
`COMPILER_ARCHITECTURE_REVIEW.md`. Preserve existing syntax and behavior;
consult the user before a change requires source-language migration. CT110 is
the installed baseline. The preceding review/documentation changes are
preserved.

## Authorized program

1. Complete semantic interfaces: retain inferred and written requirements, prove
   eligibility, and stop invalidation at an unchanged interface.
2. Completed semantic queries: retain immutable results with explicit body,
   interface, value, provider and capture dependencies.
3. Reusable elaborated bodies: settle semantic decisions before lowering; an
   admitted closed body must lower with zero new general inference regions.
4. Development generic execution: extend the parametric/dictionary path to avoid
   repeating semantic work for each concrete representation.
5. Shared immutable semantic graphs: share owned published results across
   revisions while keeping open substitutions private to each solver.

These numbers match `COMPILER_ARCHITECTURE_REVIEW.md`. Function-fragment lookup
is a supporting improvement, not a replacement for recommendation 5.

This implementation branch has stopped after three neutral/regressing screens;
all five recommendations remain incomplete. Candidate 8 passes correctness
qualification; its final screen also shows no speedup. CT110 remains installed.
No CT111 candidate is committed, pushed or installed. The user has explicitly
approved the optional `result "member" Input Output` requirement. Existing
inferred conversions remain valid. Other syntax changes still require
consultation. The new surface completes a missing written interface form; it is
not itself evidence of cheaper generic compilation.

## Initial code findings

- `ClosureRegion.importScheme` and `solveSchemeUse` currently import written
  leaves only. `checkedRequirements` explicitly rejects inferred leaves. Merely
  relaxing eligibility would silently omit constraints and is unsound.
- Existing principal inputs already distinguish local-body and checked-header
  dependencies. Preserve that distinction and the separate value/executable
  gates.
- Existing runtime dictionary owners cover contract predicates; this is not a
  universal dictionary ABI for every inferred associated operation.
- Explicit one-worker semantic mode differs from the omitted default. Use the
  omitted policy for baseline comparisons unless intentionally testing policy.

Evidence will be retained under `build/bench/ct111/`. The baseline compiler is
`build/bench/ct110/candidate-4-blotc`, SHA-256
`b0ebc5ecf07f962665fcc3cf879f5e955eb07f1341a0f2b5b8d783b963228dd2`.

## Current implementation checkpoint

- Complete inferred first-order interfaces are independently re-proved before
  use, import inferred residual requirements with fresh binders, and preserve
  checked-header versus executable-body dependencies. Inferred associated field
  selection and higher-order interfaces remain on the original path. Full
  refinement still collects bodies. Input-keyed jobs and shared residual graph
  edges retain priority over expanded interface imports. Native OOM laws and
  executed-Wasm edits, error/recovery and reverts pass.
- Source-owned immutable principal graphs can now survive a revision through
  bounded, individually reference-counted leases. Eligibility excludes mutable
  memo reads/writes, value observations, untracked reads, evaluated allocations
  and imported normalized child graphs. Gates require structural source/body
  correspondence; unused graphs are pruned on publication. The current large
  probe retains 31 graphs / 175,652 payload bytes after fresh compilation and
  reuses 16 on the literal edit. This is narrow source-graph retention, not a
  completed elaborated-body implementation.
- Checked source-body proofs can admit ordinary type nodes beyond 4,096 while
  preserving lexical-binder and binding-table bounds. Copyable sparse row facts
  admit high row IDs without allocating mutable shared state. Scheme equations
  keep large rigid IDs in a sparse overflow map. Package reader admission
  retains its previous limit. This has not expanded the large workload's
  interface coverage so far.
- Function-local optimized IR relocation already exists in CT110. The review
  incorrectly conflated it with the stricter encoded-byte reuse gate; that text
  is corrected. A new fragment lookup change indexes the translated source owner
  as well as the declaration, avoiding collisions across modules. The final
  screened profile visits 299,191 bucket positions; the separate static-value
  graph matcher still visits 3,894,971 plan positions. This has not established
  an end-to-end performance improvement.
- Reusable elaborated bodies and the expanded development generic ABI are still
  pending. Existing resolved bodies contain Generator-specific representation,
  value and emitter state; existing dictionaries cover contract predicates, not
  arbitrary inferred dispatch/field/result-selection requirements.

The selected development pass in the isolated CT111-only checkout is
`build/bench/ct111/qualification-work/blot2/build/bench/check-dev/run-55eb93f13ab66f1b/results.json`
(37.89 s, concurrent with release construction): complete 2,584-law native
inventory compilation, 113 selected native laws with sampled allocation faults,
67 selected guests, formatting, types and zero Zig lint. The final exhaustive
gate also passes; see the qualification record below.

### Written result interfaces

`where { result "from" a b }` owns an ordinary result-dispatch requirement. The
output type selects the unary member; the input type supplies no fallback. An
optional invocation row works like other written operation requirements.
Contracts, aliases and local generic bindings use the same representation.
Checking preserves the covered invocation signature through Core lowering,
including its exact selected row when the caller has additional effects.

Native laws cover ownership, malformed clauses, coverage and allocation faults.
Executed Wasm covers pure/effectful conversions, ambient effects, wrong selected
signatures and missing destination members. Retained/fresh comparisons exercise
both tiers, inferred/written interfaces, body edits, errors, recovery and
reverts. No change to the prelude or sibling application sources is required.

### Source proof scope

Checked source-interface validation now follows reached global declarations,
including aliases, instead of re-proving every body in a foreign producer
module. The caller must already have validated immutable Core and dependency
bounds. Recursive declarations use their own headers as hypotheses; all reached
bodies must finish successfully. Failed nested claims roll back. This private
mode never certifies a serialized package, whose reader retains its original
module-level admission and limits.

This removes the accidental rejection solely because `walk_material`'s module
contains 21,566 type nodes and 5,837 effect rows. It does **not** yet make its
complete inferred interface provable: the latest Safe/noLLVM diagnostic build
still has 17/20 body principal hits. All five original/edit/revert Wasm hashes
match the strict frozen pins. See `build/bench/ct111/gdev-declarations/`.

## Candidate 1 screening measurement

This binary contains complete-interface work before graph retention and the
later proof/index changes. SHA-256:
`6c58edd732c338a5e0780d07d53176789e4417460f8c5106323ebdc52bdac2b3`. Three
alternating unprofiled release pairs pass strict Wasm pins, independent fresh
controls, unchanged input pins and the fresh CPU guard. Evidence:
`build/bench/ct111/pairs-1/results.json`.

| Game build   | CT110 wall | Candidate wall | CT110 CPU | Candidate CPU |
| ------------ | ---------: | -------------: | --------: | ------------: |
| Fresh        |    7.870 s |        7.646 s |   7.770 s |       7.610 s |
| Literal edit |    3.141 s |        3.180 s |   3.250 s |       3.240 s |
| Body edit    |    5.331 s |        5.227 s |   5.250 s |       5.190 s |
| Body revert  |    5.241 s |        4.894 s |   5.060 s |       4.730 s |

These are screening medians, not qualification or evidence of sub-second edits.
Fresh/body inference regions fall from 18,386/7,216 to 14,717/3,542, but body
principal reuse stays 17/20. Eliminating many small regions has not removed the
large inquiries; the modest latency gain matters more than the region count.
Fresh peak RSS rises from 481 to 493 MiB; body-edit peak RSS rises from 756 to
765 MiB in this screen. The new graph-retention memory is not in these numbers.

## Candidate 2 screening measurement

SHA-256 `4191fae80affee5e8c9c93dc6e9cd2845d4141ba226dda04a3f3ebe99d569497`.
Three alternating release pairs pass strict Wasm pins, independent fresh
controls, input pins and the fresh CPU guard. Evidence:
`build/bench/ct111/pairs-2/results.json`. This predates declaration-sized
proofs, sparse row facts and written result requirements.

| Game build   | CT110 wall | Candidate wall | CT110 CPU | Candidate CPU |
| ------------ | ---------: | -------------: | --------: | ------------: |
| Fresh        |    7.778 s |        7.893 s |   7.620 s |       7.730 s |
| Literal edit |    3.100 s |        3.122 s |   3.160 s |       3.180 s |
| Body edit    |    5.355 s |        5.255 s |   5.200 s |       5.140 s |
| Body revert  |    5.256 s |        5.215 s |   4.940 s |       4.890 s |

These results are modest/neutral, not a demonstrated large improvement. Peak RSS
is 494 MiB fresh, 663 MiB after the literal edit and 766 MiB after the body
edit, versus 481/696/753 MiB for this paired baseline.

The separate candidate-2 profile attributes its 3,528 body-edit regions to 1,639
general, 1,353 specialization and 536 lowering regions; preparation opens none.
The three missed principal queries still construct 3,399,484 solver nodes and
take 2.454 s inclusive. Coordinating-thread inference CPU is 3.698 s; fragment
lookup is 0.386 s. Region reduction has mostly removed small work. New profile
records now group region callers by stage, and fragment statistics publish
actual bucket positions. The older roughly four-million position count belongs
to static-value graph matching, not declaration bucket collisions.

## Candidate 3 screening and architectural decision

Candidate-3 screened binary SHA-256:
`6be424c9f69469c48179710a404344959c644378c945fd1b5216eb12ec2529fc`. This
includes declaration-sized source proof, sparse lexical row facts, stage profile
grouping and the user-approved written result requirement. Three alternating
unprofiled release pairs pass the frozen manifest, strict Wasm pins, independent
fresh controls and fresh CPU guard (paired median 0.997, limit 1.050). No
compiler build or test workload runs concurrently with these pairs.

| Game build     | CT110 wall | Candidate wall | CT110 CPU | Candidate CPU |
| -------------- | ---------: | -------------: | --------: | ------------: |
| Fresh          |    6.603 s |        6.587 s |   6.800 s |       6.780 s |
| Literal edit   |    2.749 s |        2.788 s |   2.960 s |       2.980 s |
| Literal revert |    2.518 s |        2.504 s |   2.480 s |       2.470 s |
| Body edit      |    4.594 s |        4.784 s |   4.720 s |       4.880 s |
| Body revert    |    4.475 s |        4.438 s |   4.450 s |       4.410 s |

All samples are retained, including a candidate body-edit outlier of 13.006 s
wall / 5.740 s CPU. These three-pair screens do not establish a compile-time
improvement: body-edit median CPU is 3.4% higher. The medians of within-pair CPU
changes are -0.3% fresh, +4.6% literal and +4.9% body. Do not compare medians
across candidate runs as though they were paired. Fresh RSS is 494.1 versus
481.0 MiB; literal 662.2 versus 695.1 MiB; body 764.3 versus 752.6 MiB. Those
are lifetime process peaks, not artifact payload sizes. Evidence:
`build/bench/ct111/pairs-3/results.json`.

The separate strict-output profile passes all five phases. Body-edit inference
has 3,529 regions: 1,642 general, 1,352 specialization, zero preparation and 535
lowering. The three principal queries still build 3,399,653 solver nodes and
take 2.177 s inclusive in this profile. Coordinating-thread inference CPU is
3.352 s; fragment lookup is 0.389 s. Lowering's main source is
`specializeRetainedInner` (331 regions / 502,191 nodes); its subsidiary summary
work adds 204 regions. Inclusive clocks overlap and must not be added to
exclusive phase clocks. Fragment source buckets visit 299,191 positions, while
static-value matching independently visits 3,894,971 plan positions.

Across three implementation screens, eliminating many small regions has not
removed the large computations. Stop extending this shortcut branch; it has not
met the performance objective. Preserve the tested implementation and evidence
for review, and keep CT110 installed. Recommendations 1, 2 and 5 have bounded
foundations; none is a universal new interface/query architecture. The completed
elaborated-body boundary (3) and expanded development generic ABI (4) remain
unimplemented. Written result syntax is a prerequisite, not their completion.

The next implementation must give a selected body owned semantic decisions (call
targets, rows, captures and staging dependencies) that survive a revision.
Admission must prove those inputs before lowering, and an admitted closed body
must open zero inference regions. Start with a restricted first-order family and
measure coverage on the three missed principals. Extending the existing
Generator-local plan without removing its physical/value handles would not
satisfy that boundary. Generic dictionary expansion needs the same completed
interface and explicit representation/effect adapters; changing the development
flag alone cannot provide it.

Two qualification findings constrain that future design. A stable interface must
retain parameter-annotation provenance even when the inferred arrow is
unchanged. Its dependency representation must also preserve shared callee edges:
flattening a diamond into a tree can increase work despite removing body visits.
Keep the existing graph-growth laws and exact closure invalidation cases as
acceptance checks for any replacement representation.

## Exhaustive qualification and parameter-provenance repair

The first exhaustive run (`run-ce70331c0d82f56f`) found a regression in the
existing law
`closure roots in an edited module follow their owner's exact
projection`.
Ignoring a referenced producer's body extent also overlooked the provenance of
its parameter annotations: deleting an annotation could preserve the checked
arrow while changing a closure's reusable boundary. The gate stopped the other
shards automatically; that run is not a pass.

Referenced declaration projections and checked-interface admission now compare
parameter binding/type identities, annotation provenance and function shape.
Absolute parameter locations and implementation extents remain independently
projected. No existing negative assertion was weakened. The affected 44-law
reuse-gate family passes separately with full allocation-failure execution, and
the existing regression is included in the selected development family.

The second full gate (`run-32554e61dd488ceb`) found an algorithmic regression in
`owned principal graphs preserve independent inferred uses and publish
atomically`.
Eager interface import expanded repeated callee requirements and bypassed shared
jobs/graphs: the fixture used 131 scopes versus 48 with ordinary collection. Its
semantic answers agreed, but the existing bounded-work law correctly rejected
the change. The sibling shards stopped automatically.

Completed interface admission now defers to input-keyed jobs, and the header
path preserves shared residual edges before importing an interface tree. The
same fixture uses 28 scopes after this repair. All three existing principal
graph/diamond laws pass without changing their assertions; they are now also
part of the selected development family. Candidate 4
(`499f2c4c4df8fa18944ac5ea4a46d0ceb15fd5b25cf6b08cdedc8c368fd142a2`) predates
this repair and is not qualified or benchmarked.

All 2,584 native laws also pass a broad sampled-allocation run after the second
repair (`build/bench/ct111/native-sampled/results.json`). That additional screen
was prompted by the existing graph laws missing from the selected family; it
does not replace exhaustive qualification. The repaired source must pass the
full gate again before final release screening. No commit, push or local
installation has occurred. Preserve both failed exhaustive runs as evidence.

The third run (`run-2bb7d8d6487c4d9c`) passes all 2,584 native laws with full
allocation failures in 658.81 s, but its qualification key is rejected because
the live sibling fixture `../gdev/src/salt.blot` changes during execution. The
1,004 pinned compiler/test/client/tool inputs are unchanged. This is not a
qualified gate, and its native evidence must not be manually inserted into the
resume journal.

Qualification now runs from `build/bench/ct111/qualification-work/blot2`, copied
from the exact pinned inputs, with CT110's frozen sibling fixtures. The fixture
manifest SHA-256 is
`57ba5d0fb8634bf2d199a4f89ccecc6f6768d98e8de67433247e08f480cda981`. The isolated
gate records evidence in `build/bench/ct111/full-gate-isolated/`. No live
sibling source is changed or used by this qualification.

The isolated run (`run-f63cacb682ca3a53`) passes all 2,584 exhaustive native
laws in 627.85 s. Release guests then find the tight `chain_generic N=64`
allocation budget exceeded by 1,263 bytes. Its limit remains 8,963,842 bytes. An
equal-input allocation profile locates the increase entirely in checking: 1,360
additional bytes and 18 allocations from tracking result requirements; backend
requested bytes and allocation counts are identical to CT110.

Compact profile descriptors and removal of a duplicate stage field do not reduce
measured allocation. Those experiments are discarded (candidate 6,
`20033e1b3d4878f4eb39d498515550828075504cc343fb16394a03e0548091f6`). Reordering
header eligibility also has no effect on this budget and is reverted. The actual
repair deduplicates exact repeated operands within a requirement and uses a
512-byte stack buffer, with heap fallback, for the temporary requirement
type/row membership lists. Published summary flags still use the owning type
store. The Safe probe drops from 9,046,083 to 8,997,087 requested bytes and from
27,068 to 26,691 allocations; this is allocation evidence, not a latency claim.
The budget is release-calibrated and cannot be applied to Safe/noLLVM binaries.

Final release construction and selected checks are repeated. Full release guest
execution precedes another exhaustive gate to catch budget failures before
paying the native sweep cost. No test budget or assertion is relaxed.

Concurrent edits appeared in `backend/owned_arrays.zig` and its tests during
verification. Preserve them in the working tree. They were briefly copied into
the isolated checkout before being identified, so candidate 7 is a combined
diagnostic build only. Final CT111 qualification and performance measurement
exclude those two edits and retain their original pinned contents. Do not claim
that a CT111-only gate qualifies the concurrent array work.

The repaired release probe (candidate 7) passes the unchanged generic-chain
budget. Candidate 8 is the CT111-only snapshot, SHA-256
`efb953d79cf6952841e28a20d48570f2ee324a0811f475e8999131f81cb70adf`. Its
equal-path release probe requests 8,915,215 bytes and 26,692 allocations, 48,996
bytes / 377 calls fewer than candidate 5; solver work counts are unchanged. All
1,659 release guests pass in the preflight (`run-66de99f2cb472891`, 39.63 s
guest execution). All 2,584 native laws pass the additional sampled screen. The
final exhaustive gate is repeated with frozen inputs. Its successful log is
`build/bench/ct111/full-gate-isolated-final.log`. Final unprofiled paired
measurement follows that execution; results are recorded below.

The first final-gate attempt (`run-1989df8514402394`) stops before native
execution: the automatic recent-failure preflight reruns the release-calibrated
allocation budget against Safe/noLLVM. It reports 8,997,981 bytes versus the
8,963,842-byte release limit. The complete release budget file passes through
the guest gate in the same journal directory, clearing its recent-failure entry
through normal successful execution. No journal evidence is injected and no
budget is relaxed. Preserve `full-gate-preflight-mismatch.log` and
`budget-release-recheck.log`; the subsequent full gate starts normally.

The concurrent array work also now touches
`zig-native/tests/owned_array_execution.test.ts`. All 1,004 source pins still
match the frozen CT111 checkout; the three shared-checkout differences are
recorded in `build/bench/ct111/shared-checkout-drift.json`. They remain outside
this qualification and performance comparison.

## Final correctness qualification

The frozen CT111-only candidate 8 passes the complete compiler gate
(`run-fdcad0e5659ba973`) in 761.66 s: 2,584 native laws with exhaustive
allocation failures, 1,659 release guests, 48 smoke tests and 57 tooling checks.
Native execution takes 676.47 s; release guest execution takes 31.91 s. The
gate-built release SHA-256 exactly matches candidate 8. Native evidence is
verified against the frozen source, fixtures, toolchain, inventory and binary.
The selected development check also reports zero Zig lint findings.

This qualifies the bounded implementation's correctness, not completion of
recommendations 1–5 or a performance improvement. The concurrent array work is
excluded. The final three-pair performance screen follows this gate without
overlapping test/build work; profiled diagnostics are collected separately.

## Final candidate 8 screen and decision

Three alternating unprofiled release pairs pass strict Wasm pins, independent
fresh controls, unchanged input manifests and the fresh CPU guard. Fresh,
literal and body wall medians are 7.900 / 3.151 / 5.294 s versus paired CT110
7.779 / 3.122 / 5.229 s. Median within-pair CPU changes are +1.5%, +0.6% and
+1.5%. The final repaired candidate establishes no performance improvement. Peak
RSS is essentially flat to slightly higher. Keep CT110 installed.

The final profile has 2,914 literal and 7,196 body inference regions, only 20
fewer than CT110 in either case. The earlier candidate-3 body-region reduction
did not survive the repair that preserves shared callee graphs and input-keyed
jobs. Three principal misses still build 3,388,263 nodes; body lowering opens
534 inference regions and constructs another 523,109 nodes. Inference consumes
3.886 s of exclusive coordinating-thread CPU in that diagnostic profile.
Inclusive principal wall time is 2.487 s and overlaps other measured work.

The [qualification report](zig-native/CT111_QUALIFICATION.md) contains the full
timing table, memory and stage attribution, source scope and evidence archive.
Stop this shortcut branch as allowed by the user. Recommendations 1, 2 and 5
have bounded foundations; 3 and 4 are unimplemented. None is complete. No CT111
commit, push or local installation has occurred.
