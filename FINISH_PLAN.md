# Finish the current Blot program

**Current memory migration:** the owner subsequently chose a greenfield
data-stack model. Follow the [rewrite review](zig-native/STORAGE_REWRITE_REVIEW.md)
and [tasks 110–121](tasks/STORAGE_REWRITE.md). The counted-runtime/cancellation
direction and compatibility requirements below are historical; the new program
keeps isolated host workers and explicit copies and removes language tasks.
This does not mark unrelated compiler/performance work complete.

Prepared 23 October 2026 from current main `93bc8d4`, the preserved candidate in
`/workspace/blot2`, the task index, and GitHub issues #25–#27. This is an
execution plan; no implementation or qualification is claimed by its creation.

[The current issue triage](ISSUE_TRIAGE.md) covers the original eleven issues,
including the 25 October runtime reports #28–#36. The
[qualified runtime batch](zig-native/RUNTIME_BOUNDARIES_QUALIFICATION.md) fixes
#29/#30/#31/#34 with complete native/release-guest qualification and measured
kernel improvements. #28/#32/#33/#35/#36 are implemented and qualified in
[the completed runtime batch](zig-native/RUNTIME_MEMORY_QUALIFICATION.md). The
broader #25/#27 programs, including cold-start attribution and ordinary-edit
compilation latency, remain separate work.

## Remaining runtime issues: implementation plan, 26 October 2026

The user approved implementation of **all five** remaining runtime issues:
[#28](https://github.com/mewhhaha/blot2/issues/28),
[#32](https://github.com/mewhhaha/blot2/issues/32),
[#33](https://github.com/mewhhaha/blot2/issues/33),
[#35](https://github.com/mewhhaha/blot2/issues/35) and
[#36](https://github.com/mewhhaha/blot2/issues/36). All five are implemented and
qualified; see the completion checkpoint in CONTINUE.md and the measured
qualification report linked above. The plan below records the approved
implementation and acceptance criteria. The starting point is `fdfaa89` on main;
#29/#30/#31/#34 are fixed, pushed and closed. The older #25/#27 programs remain
separate. Completion of one batch does not cancel the remaining work here.

Recommended sequence: define #28's terminology and boundary; implement the small
attribution foundation for #36; implement #32 and #33; complete #36 and use it
to fix #35; finish #28's checked certificate. Packing and fusion do not depend
on completion of the profiler. The actual dependency is that #35 needs
attribution before changing cycle proofs or scheduling. #28's certificate must
consume the final proofs and helper behavior rather than invent a second
ownership analysis.

No language syntax change is proposed. The recommended policy is to preserve
current collecting behavior and add an optional strict compiler check. A change
to legal cycle, memo, cancellation or source syntax semantics requires a
separate concrete proposal to the user.

### 0. Pin the baseline and define the contract vocabulary

- Pin the release compiler, source, standard library, public fixtures, host and
  engine versions. The existing runtime-boundary result is a baseline, not a
  promise about the current gdev application.
- Rebuild and replay both frozen gdev scenes (maxed colony and 2,000 piles) with
  `fdfaa89`, preserving all-frame/final-save witnesses. The old 17–18% cycle
  share belongs to an earlier compiler and must be measured again after the four
  completed repairs. Keep shipping external-O3, raw Wasm and diagnostic variants
  separately identified.
- Extend the public controls with mixed tagged variants, escaping/saved values,
  record pipelines and a cycle reduction derived from the actual application.
  Keep a fixture containing real cycles as a required counterexample.
- Distinguish an acyclic value, an entry that creates no cycle candidates, and a
  program that executes no graph collector. None implies allocation-free,
  constant-time destruction or a general latency bound.

Primary sources: [runtime fixtures](benchmarks/runtime-boundaries/main.blot),
[measurement runner](scripts/bench/runtime_boundaries.ts),
[production audit](zig-native/TRACING_REPLACEMENT.md), and the frozen replay
configs/harness in `../gdev/performance/runtime/` and `.gdev/runtime-costs/`.

### 1. #36: preserve origins, then count surviving runtime work

Current `allocation_emission.zig` reads `Module.semantic_sites`, whose
coordinates refer to source-emission instruction positions. Optimizer passes
replace whole bodies, so those positions cannot identify final executed work.
The existing heap/copy observers are useful controls; they do not supply source
attribution.

Implementation:

1. Add optional origin records to the existing runtime IR/artifact path.
   Identify source sites by pinned source identity, UTF-8 span, operation kind
   and bounded inline-call context. Remap origins through inlining, scalar
   replacement, fusion, root lowering and function-index remapping. Deleted
   sites have no executed cost. Merged origins must remain explicit. Do not
   infer final sites by matching instruction offsets or runtime helper
   declaration order.
2. Preserve those records through retained optimized bodies, parallel assembly
   and portable artifacts. Version the affected cache/schema formats and verify
   imported provenance against the current source. IDs are deterministic for an
   exact pinned build; spans are not universal identities across source edits.
3. At final assembly, emit a hash-matched source/runtime-symbol sidecar. Add
   opt-in instrumentation after semantic optimizations. Normal release output
   has no instrumentation code or runtime tables. Retain `--explain-allocations`
   as static remarks; executed data must be separately named.
4. Start with allocation/retirement origins and cycle-candidate reasons so #35
   can obtain a reduction. Then cover all requested metrics: requested and
   rounded allocated bytes, current/peak live bytes, retired objects, copied
   bytes, retain/release counts, actual reuse/copy outcomes, candidate
   admission, passes/vertices/edges and reclaimed bytes.
5. Attribute runtime-helper work to both the responsible source operation and
   helper category. Keep allocation origin distinct from the later release or
   copy site. Use diagnostic-only object-origin bookkeeping that handles address
   reuse; do not attach an old allocation's origin to a reused address. Preserve
   attribution context across nesting, host reentry, traps and suspension.
6. Keep counters in guest memory rather than invoking a host callback per event.
   Use explicit overflow/omission reporting and a runtime/unknown bucket.
   Self-generated profiling traffic is separate. Reports reconcile each metric
   independently with its runtime total; an unexplained residual is a failure.
7. Bind every sidecar to the exact Wasm hash. If external `wasm-opt` changes
   indices/offsets, retain and verify debug names/mappings through that pipeline
   or reject the stale sidecar. Never apply raw-module offsets to shipping O3.

Code boundaries: `backend/allocation_emission.zig`, `backend/wasm.zig`,
`backend/runtime_ir.zig`, `backend/runtime_pipeline.zig`,
`backend/optimized_bodies.zig`, runtime allocation/RC/cycle/copy helpers,
compiler client/CLI options and `scripts/bench/` reporting.

Close #36 only when reports identify the #29/#34 source fixtures and #35's
actual application/reduction, cover helper work, separate live memory from
traffic and reconcile totals. Qualify deterministic fresh/restarted reports,
eliminated sites, imported/inlined bodies, address reuse, traps and JSPI.
Measure diagnostic runtime, memory and compile overhead separately. Score
performance only on uninstrumented release modules. The minimal foundation alone
does not close this issue.

### 2. #32: generalize the existing numeric row plan to bounded sums

`numeric_rows.Plan.visit` currently rejects a second nominal constructor. Its
storage tree assumes every payload is present. Packing, unpacking, direct
projection, constant serialization and host copying share that assumption.
Removing the rejection alone would read inactive payloads or construct invalid
objects.

Implementation:

1. Extend the existing numeric plan with discriminant nodes, guarded arms and
   explicit physical word positions. Use a tag plus storage sized for the
   largest arm, not the sum of every arm. Nested sums compose the same plan.
   Start with a proposed cap of four constructors and sixteen total physical
   words including tags; retain bounded depth/node/visit work and the ordinary
   fallback. Final bounds must be justified by measured code size and CPU.
2. Admit only closed reference-free payloads with checked nominal identities.
   Preserve the current restrictions on private/opaque/usage-qualified and
   unresolved shapes. Recursive or oversized representations decline; this does
   not box pointers inside an allegedly scalar row.
3. Pack only the active arm, preserve F32 bits as raw words and initialize
   inactive padding deterministically. Unpack only that arm when an ordinary
   owned value is required. Every array/list operation uses the same stride,
   bounds and overflow checks; tags never become owning pointers.
4. Update runtime pack/unpack, static constant serialization, list leaf
   geometry, host cleanup schemas/decoders and representation/cache versions
   together. Do not introduce a different hand-written variant layout in each
   consumer.
5. Extend destination construction and borrowed pattern-match/projection paths.
   A compact array that still boxes every generator result or every matched
   element does not meet this issue. Known nonescaping producers/readers should
   write/read tag and scalar lanes directly. Escaping or unknown consumers
   reconstruct an owned active value under the existing ABI.

Code boundaries: `backend/numeric_rows.zig`, `backend/backend_emission.zig`,
`backend/backend_static_data.zig`, `reuse/row_projection_uses.zig`,
`backend/host_cleanup_shapes.zig`, and `compiler/guest.ts`.

Close #32 when the 2,000-element optional numeric Array has no per-element heap
boxes in generation and scalar consumption. For an Array the target is final
array storage only; persistent Lists may still allocate their normal tree nodes.
Cover all-present, all-absent and mixed arms, different/nested payload shapes,
empty/unit arms, imported nominal identities, saved updates, slices/conversion,
leaf boundaries, invalid input/tag handling, inactive lanes and exact F32 bits.
Verify owned escaping values and callbacks in both tiers. Report padding/storage
cost, runtime, peak live bytes, Wasm size and compile cost against flat
controls.

### 3. #33: carry one destination through a proved collection pipeline

The existing `exact_builder.zig` recognizes rectangular append regions;
`ragged_builder.zig` handles separately proved count/fill cases. Row borrowing
removes scalar intermediates, but it does not connect the record/child-array,
map and flatten boundaries in the reported pipeline.

Implementation:

1. Add bounded producer/consumer analysis over checked Core and known forwarding
   bodies. Follow the generated record's selected field through map/flatten and
   prove intermediate collections and records have no other observations,
   captures, loop carries, returned aliases or deferred uses. Names such as
   `Command`, `map` or `flatten` confer no optimization authority.
2. Extend the existing builder plan to carry a final destination and offset
   through admitted producers. For the fixed 24-lane case, compute the checked
   total once, allocate one final Array and emit the original outer/inner
   traversal directly into it. Reuse existing overflow, root/cleanup and builder
   emission rather than creating a competing allocation pipeline.
3. Preserve callback evaluations and arithmetic order. Single-use or purity
   alone does not authorize moving traps, divergence or effects between eager
   stages. Prove the reordered stages total/non-trapping and effect-free, or
   preserve their original ordering; otherwise decline. Unused record fields
   with observable evaluation cannot silently disappear. Keep allocations and
   resource-failure behavior within the existing optimization contract.
4. Record every producer/consumer body and layout dependency used by the proof,
   including imports. Equal type signatures do not validate an edited body.
5. Keep the initial acceptance scope rectangular. Reuse the ragged count/fill
   path only when its existing count proof applies without executing callbacks
   twice. Irregular/effectful or observed pipelines retain normal storage. A
   later fold fusion may eliminate the final Array, but is not needed to close
   the reported one-storage case.

Code boundaries: `backend/exact_builder.zig`, `backend/ragged_builder.zig`,
`backend/function_facts.zig`, checked use/ownership analysis, existing builder
emission and executable dependency recording.

Close #33 when the reported pipeline retires only final output storage instead
of 6,005 objects and its work scales linearly with output size. Test zero/one/
large lengths, overflow, mixed/different lengths as decline controls, callback
and trap order, exact F32 operation order, saved intermediates and imported body
edit/revert/fresh parity. Measure native-host Wasm runtime (Wasmtime) and
browser Wasm runtime separately; Deno kernel timing alone does not satisfy both.

### 4. #35: reduce demonstrated cycle work without weakening ownership

`acyclic_layout.zig` already proves whole reachable plain-data shapes, including
all constructors of a nominal. It conservatively declines closures, State,
demands, providers and unknowns. `no_cycle` suppresses both candidate admission
and traversal; it is a strong lifetime claim. The scheduler already scales its
traffic threshold with surviving visited vertices.

Implementation:

1. Use #36 to rank candidate sources/layouts, failed proof reasons, rescan
   frequency, vertices/edges and reclaimed bytes in both pinned application
   scenes. Extract a standalone reduction with the same reason and scan shape.
   The previous closure-scratch case has zero scans and is not that reduction.
2. Try the narrowest demonstrated proof extension first. Candidates include an
   active immutable constructor whose unused alternatives carry functions, or a
   concrete closure whose captures are all lifetime-stably acyclic. A callable
   type or a graph that is acyclic right now is insufficient: State writes,
   demand memoization, mutable capture cells and future publication must not
   later introduce a cycle through an object marked `no_cycle`.
3. Feed proved instance facts through existing allocation/ownership paths,
   cloning and retained dependency records. Keep reference counting, strong
   fields and destruction intact. Unknown values retain trial deletion.
4. If profiling instead shows unavoidable live candidates being repeatedly
   revisited, evaluate scheduling as a separate change. Charge actual rescan
   work, respect external owner changes and preserve forced drains. Any change
   needs a stated bound on deferred cyclic garbage and long-running evidence;
   lowering the pass count by indefinitely retaining garbage is not progress.
5. Reprofile after packing/fusion, which can remove candidate graphs entirely.
   Attribute proof improvements and scheduling changes separately so a reduced
   workload is not credited to the collector algorithm.

Code boundaries: `backend/acyclic_layout.zig`, allocation/closure construction,
`runtime/cycles_runtime.zig`, shared RC/retirement and the exact typed edge
walks.

Close #35 only with fewer scans and lower uninstrumented CPU in both the
reduction and application replays, unchanged frame/save witnesses and bounded
long-run memory. Include real strong cycles, duplicate edges, State/demand memo
cycles, callbacks, startup/persistent owners, suspension/cancellation and forced
collection. Zero reclaimed bytes in the old profile never licenses disabling
collection. No numerical speedup is promised before attribution identifies the
cause.

### 5. #28: make collector-free behavior a checked program property

Define the policy first, implement the final certificate after the proofs above.
The guide currently describes counted ownership plus trial deletion; parts of
`CONTRACT.md` and historical runtime documents still describe a production
tracer. Correct current normative text and label historical sections clearly.

Recommended policy and implementation:

1. Keep legal cycle-forming programs and their existing collecting semantics.
   Add a proposed opt-in build check, for example `--require-collector-free`,
   with no new source annotation or restriction in ordinary builds.
2. Start certification at the complete module/arena boundary: all entrypoints,
   initialization, persistent roots, callees, callback targets and runtime/host
   helpers must be covered. An individually acyclic entry can still trigger a
   safe point on cycles created by another entry in the same arena. Per-entry
   claims must expose this precondition or require isolated arenas; they cannot
   silently imply a whole-heap guarantee.
3. Extend existing ownership/helper summaries with bounded transitive evidence
   and explicit unknown reasons. Handle recursive call components
   conservatively; do not replace their unknown edges with success. Incoming
   host values, indirect calls, demands, task transport and suspension need
   checked contracts or a precise decline. Reuse the same type/instance facts as
   runtime emission.
4. Publish a versioned certificate or diagnostic in the ownership metadata:
   covered roots, assumptions, compiler/source identity and a reason path to an
   unproved allocation/capture/callee/helper. Runtime zero-scan observations
   validate the implementation but are not a proof for every input.
5. Strict mode rejects an unproved program; ordinary mode retains collection.
   Remove unreachable collector helpers only when that full proof permits it. No
   weakening of memoized results, implicit scope conversions or hidden semantic
   change is permitted to obtain a certificate.

Close #28 when guide, contract and emitted metadata agree; certified ordinary
workloads execute no graph collector; negative cycle/unknown-callee examples
produce actionable diagnostics; and ordinary strong-memo/cancellation behavior
remains qualified. Explicitly document that collector-free can still allocate
and incur work proportional to a released acyclic graph's size.

### Qualification and publication

Implement the code and permanent regression laws before expensive final release
measurement. Use focused development checks while developing each boundary; then
freeze the combined candidate and run full correctness qualification before
scoring it. Do not call sampled development execution full qualification.

- Use Zig 0.17.0, Safe/noLLVM for development and native tests. Extend the
  explicit `numeric-aggregates` and ownership regression families as needed. Run
  the complete exhaustive `deno task test:compiler` gate and zero-finding
  `deno task lint:zig` before committing compiler changes.
- Use LLVM release compilers for alternating runtime and compilation pairs. Keep
  instrumentation, sampling, browser, native-host, external-O3 and raw-Wasm
  results separately named. Preserve startup/warmup/tiering controls and exact
  result/ownership witnesses. Never benchmark alongside builds or another run.
- Reuse the 28 public boundary cases, add the new positive/negative controls and
  measure scaling. Pin raw samples, Wasm, symbols, source and executable hashes.
  Track allocation traffic, live/peak bytes, committed capacity, copies, RC
  work, scans, CPU, wall time, code size and compiler memory separately.
- Run fresh and retained literal/body/revert/restart compilation against frozen
  gdev inputs. Keep exact within-compiler parity and intentional cross-compiler
  Wasm changes distinct. Use the existing 5% fresh CPU guard as an initial
  regression gate and explicitly assess edit CPU/RSS and code-size growth too.
- Update README, the guide, numeric/ownership documents, issue triage and this
  handoff. Preserve unrelated untracked build directories and private inputs.
- Commit and push qualified changes to main under the existing authorization.
  Close each issue only after its own criteria above pass and link its source,
  limitations and reproducible evidence. A profiling foundation, storage-only
  change or reduced synthetic case is not completion of its broader issue.

If a hypothesis produces no reduction in measured work, record the result and
move to the next measured cause instead of repeatedly raising limits or adding
caches. Stop for a concrete language-semantics decision or missing essential
replay input; keep the unfinished issue and next action explicit. Difficulty or
completion of the first batch alone is not a reason to abandon this program.

## Execution checkpoint, 24 October 2026

The [CT109 qualification](zig-native/CT109_QUALIFICATION.md) passes seven
alternating release pairs against CT106, exact outputs and the full compiler
gate. Paired CPU changes are first literal -0.6%, literal revert -11.5%, body
-2.5% and body revert -7.5%; fresh game/devtools remain within the 5% guards.
First-literal/body wall medians are 3.261/5.377 s. Reverts improve, while the
ordinary-edit, two-second and sub-second targets remain open.

The candidate passes 2,573 exhaustive native laws, 1,656 guests, 44 independent
held-out Wasm executions and 232 requests over 200 distinct edits. Post-session
RSS is 521 MiB. The [86-item ledger](COMPILER_CT109_LEDGER.md) records
implemented work, rejected experiments and still-open architectural designs. The
qualified CLI and native compiler are installed locally; raw evidence and limits
are linked from the qualification record.

The broader language and upstream-issue requirements below remain open; this
performance follow-up does not close unrelated completion work.

Historical CT106 checkpoint, 24 October 2026:

The [CT106 qualification](zig-native/CT106_QUALIFICATION.md) records **19.1%
less first-literal-edit CPU** against CT105 in seven alternating release pairs,
with identical Wasm. First-literal wall median falls from 3.62 to **2.91 s**;
fresh CPU improves 2.4%, body CPU is effectively unchanged and literal-revert
CPU rises 3.5%. These are shared-host observations. Body-edit, two-second and
sub-second targets remain open.

Exact frontend correspondence now checks one module on the first edit instead
of 22. Bounded operation indexes/certificates, lexical links and import scratch
remove repeated work. The report includes 200 distinct edits, allocator/CPU
attribution, exhaustive qualification and rejected experiments. All 86 review
suggestions have a [disposition](COMPILER_CT106_WORK.md); conditional
alternatives and unfinished architectural work are explicit.

Full qualification passes 2,564 exhaustive native laws and 1,655 guest checks.
The broader completion requirements below remain open; this performance pass
does not close unrelated language or upstream-issue work.

Historical CT103/CT104 checkpoint, 24 October 2026:
[the four inference changes are qualified](zig-native/CT103_QUALIFICATION.md).
Nonempty principal results, exact call/recursive-summary observations, consumed
source declarations and bounded operation-row normalization are implemented.
Seven alternating pairs against `5412320` show **24.8% less literal-edit CPU**,
**4.2% less body-edit CPU** and **6.1% less fresh-game CPU**, with
byte-identical fresh/edit/revert/restart outputs. Devtools stays effectively
unchanged. Literal/body wall medians are 7.60 / 12.46 s on the loaded shared
host; the body wall median does not improve. These CPU gains are medians of
within-pair ratios.

Literal edits reuse all 20 principal results; body edits reuse 16, leaving four
fresh regions. Three unseen literal edits and three unseen body edits match
fresh controls. Later literal edits take 2.96–3.18 s in that single diagnostic
sequence, including about 1.5 s inference. The 20% body-CPU target, both edit
classes below four/two seconds, and sub-second editing remain open. Continue
with the remaining body-region dependencies and residual inference in
[the current queue](COMPILE_HILLS.md); keep first-edit frontend work separate.

The measured candidate passes 2,548 exhaustive native laws; its guest suite
catches a lost restart-reuse optimization, fixed by omitting unsupported
optional summary outputs while keeping all required-input checks. Main also
advanced to `faf3f78` during measurement; the final combined release separately
passes 2,551 exhaustive native laws, 1,654 guest checks, 48 smoke checks and 57
tooling checks, with zero Zig lint findings and exact frozen-workload output
parity against the measured candidate. Its full gate takes 623.68 s. Performance
percentages belong to the pinned comparison; they do not attribute gains to the
later callback/diagnostic changes or portable-output fix. The measured expanded
development cycle takes 26.05 s with a 3.59 s compiler build and 6.90 s complete
native compilation; these are individual observations, not p95 estimates.

The combined CLI and compiler are installed at `~/.local/bin/blot` and `blotc`.
Both resolve through PATH; outside-repository format/check/build, matched Wasm,
the list example result 29 and the bundled guide pass. Native SHA-256:
`0185500e446d59d6e813de8cecb3318bcc5983632043eb0129b8a64bad45ee9f`. Installation
and rollback backups are recorded in `build/install/ct103/installed.json`.
Preserve unrelated untracked `zig-native/build/` and `zig-out-modern/`. The
dated checkpoints below are historical; do not rerun completed hills.

The preceding CT97 batch: seven alternating release pairs reduce fresh game CPU
by **32.5%** against CT96; median build wall falls from **13.60 to 8.68 s**,
with identical Wasm. Literal/body edits use 40.7% / 43.1% less CPU and take 7.63
/ 6.56 s median wall. The 50% edit-CPU and four-second wall targets remain open.
The [new qualification](zig-native/CT97_QUALIFICATION.md) closes CT97 and
records restored executable reuse and fewer real backend allocations. CT98, BT4
and the broader completion plan remain open; follow the updated hill tables
below.

The [CT96 optimization](zig-native/CT96_QUALIFICATION.md) removes repeated
whole-program spawn-contract scans during emission. Seven alternating release
pairs show 28.6% less game CPU and 29.0% less devtools CPU with identical Wasm.
The isolated compiler passes full qualification; the remaining inference,
retained-reuse and absolute performance targets below stay open. The
[post-CT96 review](PERFORMANCE_REVIEW.md) narrows CT97 to repeated row
traversal, CT98 to executable-admission diagnostics and BT4 to allocations in
the slow backend sweeps. It adds evidence, without closing those hills.

The baseline [compile/build measurements](COMPILE_MEASUREMENTS.md) established
the remaining performance work against compiler `63c931f`. Follow
[CT95–CT101](COMPILE_HILLS.md) for application compilation and
[BT1–BT5](BUILD_HILLS.md) for compiler iteration. CT96 addressed the repeated
spawn-capability scan; the earlier task-086 constant-work decision remains
separate because these clocks include nested preparation.

The subsequent
[associated-work repair](zig-native/ASSOCIATED_WORK_QUALIFICATION.md) restores
compilation of the unchanged frozen gdev game, honors configured budgets and
corrects exhaustion diagnostics. Its full gate and fresh release measurements
are recorded separately. This repair and the preceding derive work do not close
any additional milestone below.

The owner reconfirmed the full remaining plan and asked to implement before
final verification. The task-surface continuation from `87ba3f6` in
`/home/mewhhaha/src/blot2` is now qualified. The former `/workspace` paths below
describe historical integration work; both existing stashes remain preserved.
The new slice covers checker-selected spark groups, universally quantified
ordinary scope callbacks, and runtime collect-all. Direct relays, currying,
identity forwarding and renamed imports execute in both tiers and sync/JSPI.
Tuple collection works through direct generic receive helpers, aliases and
imports, preserving partial-result ownership. Exact explicit spawn helpers work
through aliases, renamed imports and stored partial calls, with capture checks
at the completed call.

The [full qualification](zig-native/TASK_SURFACE_QUALIFICATION.md) passes 2,536
exhaustive native tests, 1,645 guest/client tests, 48 smoke checks, 54 harness
checks and 15 preflight regressions. Zig lint reports zero findings. The release
CLI and native compiler are installed locally, and the README, language guide
and implementation contracts describe this slice. Arbitrary higher-order spawn
forwarding and implicit caller-region propagation still require further
signature evidence. The entire completion plan remains open.

The [compact symbolic instruction journal](zig-native/SYMBOLIC_JOURNAL.md)
passes the full compiler gate and strict seven-pair application comparison. It
reduces temporary allocation in emission; it does not close the remaining
performance targets. The scope/spawn/tuple slice is qualified above; the
remaining task-region and channel lifecycle work is still unfinished.

Milestone 1 is integrated and passes the complete compiler gate. Issue 26's
bounded numeric layout repair passes both-tier runtime, allocation, immutable
snapshot, host-copy and fresh/retained/restart checks. The
[qualification record](zig-native/NUMERIC_QUALIFICATION.md) includes the
measured compiler tradeoffs and rejected broad-inlining variants. Milestones 2
and 3 still have the explicit remaining iterator and performance requirements
below; issue 25's later language/runtime milestones are not complete.

Task 086 is complete as not needed on the measured workload: its conservative
constant-work estimate is 14.9% of later-edit CPU, below the 20% gate. Larger
backend/inference work remains, and the eleven other task records stay open.

Published commits: Blot `4091cb2` closes issue 26 after complete qualification.
Pen `b2f06cf` reuses its validated module cache during scene discovery: warm
export falls from 3.440 to 0.169 seconds and 2,471 to 105 MiB maximum RSS, with
complete bundle and cache-recovery equality. Issue 27's later-edit,
bounded-session and remaining compiler targets are still open.

## Scope and starting state

The outcome is one integrated, qualified main branch covering the remaining
`CONTINUE.md` work and issue #25. Issues #26 and #27 overlap the existing
representation and performance program and share its measurements.

- The task index has twelve open tasks: 047, 081, 082, 084, 086, 093, 100–104,
  and 999.
- `/workspace/blot2` is at `607618a`, 23 commits behind main. It contains 25
  modified tracked files and three untracked source/test files. Preserve this
  candidate and its evidence before integration; do not reset it.
- The clean `/workspace/.issue25-next` checkout is at main `93bc8d4`. Commit
  `e3e7463` qualified task receive helpers and the F32 return repair: 2,510
  exhaustive native tests, 1,633 guest/client checks, and zero lint findings.
  These results qualify that commit, not the separate dirty candidate.
- The recreated gdev snapshot and older candidate evidence are present under
  `/workspace/blot2/build/bench`. Verify the recorded manifest before using
  them. The lost original snapshot is not a prerequisite; its recreation was
  already authorized.
- At plan creation, issue #25 supported single task receives and sparks in a
  literal task scope, plus ordinary receive helpers through aliases/imports. The
  execution checkpoint above records the subsequent scope/spawn wrapper and
  tuple collection work. Generic caller-region propagation, selection, streams,
  scoped exits, purity certification, and CPU worker transport remain open.

Existing decisions stand: `return` exits the function, `break value` finishes
the nearest `do`, and unsupported returns across generated continuations give
explicit diagnostics. The new surface remains `*(call)`, `|source|`, `|(a, b)|`,
and `|a, b|`. Scope, task, channel, and control helpers use ordinary calls and
checked contracts. Do not introduce new block keywords or recognize prelude
function names as magic.

## Ordered milestones

### 1. Recover and integrate the existing candidate

1. Save a recoverable local checkpoint of the tracked diff, all three untracked
   files, and an evidence manifest. Record the source and executable hashes.
2. Compare its changes with the intervening main commits. Classify each as still
   needed, already superseded, or a rejected experiment. Carry forward the
   needed changes into a fresh worktree based on current main.
3. Group the live changes by behavior: iterator/evaluated-call optimization,
   constant/static-sharing correctness, and client process shutdown. Resolve
   overlapping backend and type-store edits using the current contracts.
4. Run the affected native and executed-Wasm laws, including the positive
   static-closure reuse law, second-edit/rollback controls, alias changes,
   immutable snapshots, and fresh/edit/revert equality.
5. Qualify the integrated candidate and its compiler/runtime costs against
   current main, then commit and push the accepted changes.

**Exit:** a clean integrated branch with reproducible evidence; no useful work
or benchmark provenance exists only in the old dirty checkout.

### 2. Finish iterator and representation work

Complete task 047's remaining Window/reducer/ownership cases and the final
all-width cursor comparison. Preserve independent forks, pull order, early
termination, saved snapshots, and the fallback for escaping or unknown state.

Use the recorded rejected Window counterfactual as a constraint: it reduced
allocation but slowed the measured cases by roughly 10–27%. Investigate the
remaining ownership/lifetime cost with a narrowly falsifiable experiment; do not
repeat the same cost-guard bypass. A rejected optimization stays rejected. An
unfulfilled task requirement stays open unless the owner changes the
requirement.

Qualify issue #26's nested numeric records versus sixteen-scalar records on
current main, across calls, callbacks, imports, arrays, and retained snapshots.
If there is no remaining gap, close it with that evidence. If there is a gap,
implement and measure the smallest internal layout/calling-convention repair;
preserve nominal types, public ABI, wire order, and floating-point operations.
Treat its allocation-free-boundary investigation as a separate explicit result,
not an implication of pre-optimization allocation remarks.

**Exit:** 047's accepted requirements are satisfied, and #26 has a measured
resolution or a clearly identified remaining acceptance row.

### 3. Establish one performance baseline and finish the measured gaps

Use task 084's workload preparation as the common baseline for 086, 093,
100–104, and issue #27. This avoids separate competing benchmark campaigns.

1. Verify the recreated source manifest, pin assets for host startup tests, and
   pin compiler, library, options, cache state, and machine conditions.
2. Measure fresh compilation, population, no-op, first and later literal edits,
   private helper edits, exported type/import changes, generic specialization
   changes, restart, and failed-edit/recovery separately.
3. Attribute compilation, constant evaluation/serialization, Wasm loading/JIT,
   assets, and overlapping processes. Separate cumulative requested bytes,
   peak/live requested bytes, process RSS, and guest capacity/live memory.
   Account for telemetry overhead and unattributed memory.
4. Resolve task 086's gate with at least seven paired retained measurements:
   quantify unaffected constant work, C. Continue broader receipt work only if C
   is at least 20% of edit CPU or the largest attributed phase. Otherwise close
   086 as not needed under its existing acceptance rule.
5. Use the attribution to finish 093 and attack 100–104. Extend the existing
   reuse/cache owners; retain their exact identity and publication checks.
   Measure bounded cache growth, eviction, corrupted checkpoint rejection, and
   long edit-session recovery for #27.

| Task | Required performance result                           |
| ---- | ----------------------------------------------------- |
| 100  | Fresh compilation approximately 500 ms CPU            |
| 101  | Retained literal edit below 30 ms CPU                 |
| 102  | General retained body edit below 100 ms CPU           |
| 103  | Every inference region below 50 ms CPU                |
| 104  | Cumulative requested compiler allocation below 100 MB |

A measured miss with good attribution is useful progress, but it does not close
these performance gaps. Preserve negative and inconclusive results. The
historical application RSS near 5 GiB in #27 is not evidence that the compiler
alone owns that memory and is not the same metric as task 104.

**Exit:** the measurement gate for 086 is resolved, 093 is accounted for, the
five target rows pass, and #27's attribution, memory bounds, and recovery
requirements are qualified.

The older named follow-ups must be reconciled explicitly, not lost in the task
index. Use this routing when auditing them:

| Existing follow-up                                                                                             | Work destination                                                                                    |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| CT28: development tier for `pen dev`'s own Blot session                                                        | Verify during milestone 1; implement the scoped option forwarding if still missing                  |
| P1 closed-row certificates; P2 robot-pickup obligations; P3 `played` constructor memo; P4 namespace comparison | Measure and rank in milestone 3; accept or reject each proposed optimization with evidence          |
| CT10/11/22/26/29: IDs, interfaces, repeat optimization, body reuse, rejected populations                       | Milestone 3's edit/dependency/serialization work                                                    |
| CT51 and CT56: parametric summaries and solver storage lifetime                                                | Milestone 3's inference-region and memory targets                                                   |
| CT44/87/88: compiler checking/inference parallelism                                                            | Milestone 3 only if attribution supports it; this is separate from guest CPU workers in milestone 9 |
| R4, deferred borrowed-array cases, v128 closure boxing                                                         | Milestone 2's representation/callback matrix                                                        |
| Remaining frame retains, collection-copy and acyclic-flag cases                                                | Milestones 2–3's runtime ownership and memory measurements                                          |
| Restart checkpoint cost and retained-cache growth                                                              | Milestone 3 and issue #27                                                                           |

First check whether newer main commits already resolved each old note. An
optimization hypothesis can be rejected on evidence; an outstanding accepted
requirement must be completed or remain visibly open.

### 4. Move issue #25's region inference into checking

Treat the previous architectural blocker as implementation work with a bounded
first milestone:

1. Preserve spark/receive intent in syntax until checking. Move group selection
   out of the parser's literal-`@task.scope` rule.
2. Define generative region and once/capture-transfer contracts for scope and
   spawn. Infer the required region for a helper that sparks work; preserve it
   through calls, currying, aliases, imports, and higher-order wrappers.
3. Validate the contracts against source/Core bodies and at frozen/imported
   boundaries. Keep exact region identities and existing no-escape rules.
4. Preserve callable/argument evaluation at the parent spark site and execution
   of only the invocation in the child.

**Exit:** ordinary `scope`/`spawn` wrappers and a helper that sparks into its
caller's group execute correctly through imports. Missing groups, expired
groups, forged contracts, duplicate consumption, and cross-region captures
reject. Nested scopes select their own group. Scope exit still drains children.
No new user decision is needed for this milestone.

### 5. Finish task receives and tuple collection

Implement type-directed receiver operations and preserve collect-all versus
select-one syntax through formatting and Core. A tuple held in a binding or
passed through `await` must behave like a literal tuple of receivers. A task
whose payload is a tuple returns that payload without recursive receiving.

Establish all collection dependencies together and retain partial results until
completion or cleanup. Do not lower this contract to unrelated destructive
blocking receives. Qualify exact return values, application errors as data,
single execution, capture snapshots, cancellation/failure order, nested
dependencies, and cleanup. Keep existing demand behavior.

**Exit:** task-only collect-all works through direct and imported helpers in
both tiers and sync/JSPI, with partial-result ownership and failure laws. Stream
collection and selection complete in milestone 7.

### 6. Implement typed scoped exits

Implement the checked `control.scope` primitive and ordinary wrapper. Its exit
capability carries a fresh target and result type, can pass through helpers, and
may survive suspension in the same logical task. Calling it unwinds to that
target and cleans up scopes, children, and resources crossed by the exit.

**Exit:** nested and recursive targets remain distinct; expired targets,
escaping capabilities, and use from another task reject. Deep parser exits,
host-call settlement, and cancellation/drain behavior execute correctly.

### 7. Implement bounded streams and selection

Add checked channel creation, send, receive, and close operations with ordinary
source wrappers and constructors. Implement FIFO, capacity zero rendezvous,
bounded buffering, backpressure, endpoint versioning, and exactly-once message
transfer/drop. Sender close drains queued items; receiver close returns blocked
senders' unsent values. Cleanup and cancellation wake affected tasks.

Add select-one without consuming losing endpoints. Specify readiness ties,
closure, cancellation, and fairness in the durable contract; use written-order
tie resolution for simultaneous readiness and test starvation behavior. Retain
the scheduling-choice effect. Extend collect-all to one event per stream.

**Exit:** the issue's complete producer/consumer and collector examples run,
including capacity one, renamed/imported constructors, early close, blocked
send, partial collection, consumer failure, and cancellation races.

### 8. Certify the restricted pure subset

Keep effect freedom, deterministic results, total/non-trapping execution, and
permission to move/drop/speculate as separate facts. Start with finite acyclic
task graphs and checked finite batches/restricted pipelines. Unknown progress or
unsupported effects keep the conservative behavior.

Validate and preserve proof facts across helpers and imports. Enumerate small
adversarial schedules and compare values, required bit patterns, ownership,
cleanup, and failure/termination behavior. First-ready selection, external
mutation/clocks, unqualified host callbacks, schedule-sensitive failure, and
unproved channel progress must not silently become pure.

**Exit:** accepted programs have explicit checked evidence, and all required
counterexamples reject or retain their effects.

### 9. Add checked workers and measured scheduling optimizations

Define a separate transport boundary for worker-safe data and effects. Reject
raw guest pointers, invalid loans, and unsupported host capabilities. Bound
worker and queue resources and preserve cancellation and result ownership.

Prioritize task/queue elimination, stage fusion, and small-job chunking, then
worker execution. Compare direct sequential, cooperative, fused/static, and
worker implementations on the same inputs and permitted traces. Measure the game
snapshot/calculation/fixed-order-commit workload, a bounded pipeline, and deep
parser exits. Include tiny jobs and memory pressure.

Record replay hashes, p50/p95/p99 runtime, compile cost, code size, task/queue
counts, transferred bytes, allocations, and peak live memory. Publish missing
proof reasons and reject regressions. The issue's more speculative monotonic
data, algorithm portfolio, GPU, and distributed ideas are hypotheses for later
work; they do not expand this completion plan into promises of implementation.

**Exit:** checked CPU parallelism is real, the required optimizations are
qualified, and issue #25's acceptance matrix is complete before closing it.

### 10. Final integrated qualification and cleanup

Maintain docs and analyzer checks at each milestone, then close 081 and 082
against the final integrated source. Use 084 first to establish the common
workload/baseline, and finally to audit the completed program; this avoids
treating its documentation/measurement dependencies as a circular stop.

Reconcile old `CONTINUE.md` “remaining” notes with current code and tests so
already completed issues are not reopened by stale prose. Run the full
semantic/ownership, sync/JSPI, source/import/archive, retained/restart/recovery,
editor, packaging, analyzer, and performance gates on the combined candidate.
Move essential contracts and evidence into durable documents.

Only then execute task 999: audit every completion row, remove `tasks/` and the
old `PLAN.md`, repair references, and inspect the deletion. Its recorded
local-only cleanup note is superseded by the user's standing instruction to push
the finished work to main; push only after the final deletion audit. Keep this
plan and durable status independent of the temporary task directory.

**Exit:** no accepted work is silently deferred, all issue/task closure claims
have evidence, and the final checkout and main branch are accounted for.

## Execution and turnaround rules

- Use Zig 0.17.0 with `-Dllvm=false` for development and native test
  compilation. Use LLVM for the release compiler and release measurements.
- Use the 300-second `check:dev` cycle while editing; add the affected laws to
  its explicit family. Select tests from the already-built native inventory
  instead of compiling separate executables for each filter.
- Run one heavy job at a time under the shared memory/lock wrapper. Avoid
  queuing another build behind it; do read-only review and documentation while
  waiting. Keep unrelated code edits out of a qualification run.
- Run the full required gate before each coherent compiler milestone commit,
  then push under the standing authorization. The last recorded full gate took
  about eleven minutes; five minutes is the development feedback budget, not a
  promise for exhaustive release qualification.
- Reuse a successful gate only while its relevant inputs remain unchanged. Do
  not rerun compiler tests for documentation-only edits.
- At each milestone publish the commit, acceptance rows, test/evidence paths,
  measured result, and next bounded step. Stop for a real unresolved design
  choice or repeated failure with no new hypothesis; an anticipated refactor
  alone is not a reason to stop.

The first implementation action is milestone 1: preserve and reconcile the
existing candidate against main before introducing more language/runtime work.
