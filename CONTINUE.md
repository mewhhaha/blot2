# Continue the owned-storage rewrite

## Current frontier

Compilation latency is the active priority: **subsecond Gdev compilation**. Do
not repeat the recorded 36-minute main build. Diagnostics default to a
five-second deadline and kill the compiler on timeout.

After sparse owner traversal, the optimized compiler still exceeds 30 seconds on
main. Its next late profile spends **46%** in substitution-map lookups: rollback
fills deleted hash slots while live load stays small. Retaining inactive keys
and counting active captures separately removes this exhaustion. Three rotated
isolated controls improve lookup-churn CPU **240.44 to 21.80 ms (11.03x)**; this
is not a whole-game latency claim. The candidate compiles 2,800 native laws,
passes 40 selected laws with full faults, 11 guests and zero Zig lint findings.
Next is optimized full-main timing. Source graph/copy-elision experiments remain
outside-tree drafts. See
[substitution-map evidence](zig-native/measurements/substitution-map-churn-2026-11-02.json).

The first current LLVM release compiler built successfully in five minutes (4
GiB build RSS). Actual main still exceeds its 30-second cap, but its frontend
finishes in **1.03 seconds**. Late emission spends over half its sampled CPU in
owner-inventory scans. Sparse root unions and allocation-free traversal now
replace those scans while preserving nested/unselected fields and diagnostic
order. All 2,799 laws compile; 39 selected laws pass full faults, 11 guests
pass, Zig lint is clean, and seven real renderer streams/Wasm remain identical.
The safe candidate still exceeds 30 seconds; optimized candidate timing is next.
See
[sparse-owner evidence](zig-native/measurements/sparse-owned-roots-2026-11-02.json).

The private source checker/lowerer now carries completed body authority into
emission. Its process-local receipts match the exact immutable prefix, fresh
entry and identity; decoded/precomputed/mixed/copied-entry paths reconstruct.
Bounds, Core and storage ownership checks remain. A late actual-main sample
removes source-proof reconstruction completely: 5,973 bodies are admitted from
the checked source pipeline. Source-body membership also uses a transactional
index instead of a repeated linear scan.

Indexed lexical substitutions replace repeated reverse searches and preserve
both identity and nonidentity shadow rules. Captures reuse immutable snapshots
until mutation. In separate six-second emission windows, progress rises from
1,985 expressions/37 functions to 18,484 expressions/740 functions; these are
different bounded samples, not a total-time ratio. Actual main still exceeds 30
seconds with the safe/noLLVM compiler. Next is one optimized LLVM compiler
build, then comparable full-game timing. The current checkpoint compiles 2,795
native laws, passes 35 selected laws with full faults, 11 guests and zero Zig
lint findings. The broader static family passes 167 laws/30 guests with one ECS
storage_unsupported reproduced on both preserved pre-candidates. The full gate
retains its known 48-pass/one List/chunk failure. See
[source and environment evidence](zig-native/measurements/source-completion-and-environments-2026-11-01.json).

Actual-main emission sampling found a **128-module bounds-cache cliff**: large
contexts repeatedly validated entire catalogs during source proofs. Bounds
receipts now own a scalable exact context and retain more than 128 results.
Unrelated goal headers are rejected before initializing/copying large witness
arrays, with the same proof-budget and proxy-validation behavior. The next
sample removes repeated bounds validation from the hot list and places 58% of
sampled emission CPU in source-body proofs. Both fixes still time out on actual
main at 30 seconds; no five-second or whole-game output claim is established.
The checked checkpoint passes 27 selected native laws, 28 full-fault laws, 11
guests, zero Zig lint findings and seven unchanged real kite streams. Three
alternating compiler pairs with the same actual renderer source improve backend
time **1.291 to 1.120 seconds (13.2%)** and total **5.257 to 5.074 seconds
(3.5%)**. All produce identical 261,953-byte Wasm and seven complete streams.
These are profiled renderer builds; main still exceeds its cap. The full gate
retains the known 48-pass/one List/chunk failure. See
[bounds and source-proof evidence](zig-native/measurements/bounds-and-source-proof-2026-11-01.json).
The earlier bounds-only receipt grants no source-body authority by itself.

An owner-requested full timing run now establishes **Gdev main exceeds five
minutes**, not seven seconds. The unprofiled `9361e10` build was aborted at
300.07 seconds, with about 2.25 GiB sampled resident memory and roughly one CPU
core after the frontend. It produced no current game artifact; exact completion
time and size remain unknown. A separate 30-second trace reaches the backend at
9.02 seconds and enters `owned.emit` at 9.43 seconds, still active at timeout.
That window is synchronous emission, including call admission/refinement,
expansion and inline outlining; codegen workers apply only to later assembly.
The long unprofiled run has no internal phase trace after that boundary. Target
full-game backend work before extrapolating tiny-export producer improvements.
See
[the full-game timing evidence](zig-native/measurements/full-gdev-timing-2026-11-01.json).

Ready checker jobs now start largest syntax units first, while preparation,
budgets, diagnostics and publication keep their original order. Three matched
unprofiled four-worker pairs improve total World-producer compilation **7.46 to
7.15 seconds (4.2%)**. Separate eight-worker pairs improve **7.00 to 6.89
seconds (1.5%)**. Retained entry-body edits take **0.50 seconds**, with
byte-identical reverts around **0.51 seconds**. These execute a tiny identity
export after checking all 240 producer modules; they do not initialize the World
or measure game hot reload. Do not compare these unprofiled controls directly
with earlier profiled phase totals.

Raw worker scaling measures 2/4/8 workers at 7.89/7.04/6.90 seconds; one worker
hits the ten-second cap. Keep the default four: eight consumes more CPU for a
small wall-time gain. Separate opt-in diagnostics observe only **16 ms summed
heap-lock wait** at four workers, versus 117 ms at eight. No allocator caches or
sharding are justified. Narrow dependency batches and uneven work constrain
parallelism; the slowest measured modules are robots, station, world_storage and
salt. Worker capacity/CPU and heap waits are diagnostic, overlapping sums.

Compiler `9361e10` compiles 2,790 native laws. The current family passes **24
selected native laws**, all with full allocation-failure mode, **11 guests** and
zero Zig lint findings. Seven original kite scenarios retain identical complete
streams and Wasm bytes. The required full gate remains **48 passed/one baseline
List/chunk storage_escape** at bytes 312..345. Actual unprofiled Gdev main now
exceeds the explicit **five-minute measurement**; total completion time, size,
frame and release qualification remain unknown/pending. See
[the concurrency and total-time evidence](zig-native/measurements/concurrency-and-total-time-2026-11-01.json).

Closure validation now computes whole-context spawn-contract presence once per
immutable batch. Three matched fresh World-producer pairs improve validation
**883 to 693 ms (21.5%)** and total compilation **7.69 to 7.41 seconds (3.7%)**.
Deleting temporary normalization-list copies saves **30,671 checker
allocations**; checking improves only **4.19 to 4.13 seconds (1.5%)**. Output is
the identical **2,935-byte** identity export. This checks all 240 producer
modules, not actual world initialization or whole-main performance. Shared
nominal preparation and application-normalization guards showed no meaningful
checker gain and were removed; their patch and executed witnesses are archived.
See
[the matched controls and rejected work](zig-native/measurements/checker-validation-reduction-2026-11-01.json).

The cursor-view adapter is **rejected and removed**. Fused covariance opening
and view-aware application/pending-use reads eliminate **28.4%** of
resolver-created nodes, with zero fallback across 445,342 view requests. Yet
three matched pairs regress checking **4.67 to 4.99 seconds (6.8%)** and total
compilation **8.25 to 8.78 seconds (6.3%)**. Admission and validation add about
2.22 million and 1.74 million visits; pooled live bytes barely change. All 29
selected native laws pass full allocation faults, 11 guests pass, and seven
original kite streams plus Wasm bytes remain identical. The patch, failed
intermediate checks and pinned comparisons are preserved in
[the rejected experiment](zig-native/measurements/rejected-cursor-reads-2026-11-01.json).
That experiment restored `4c9635bb`; do not extend its removed adapter.

The earlier completed-Core validation receipt independently removes repeated
producer validation while preserving backend bounds and fresh-entry checks. Its
separate matched controls improved 8.63 to 7.78 seconds; do not combine medians
from different runs. See
[receipt evidence](zig-native/measurements/completed-core-validation-2026-11-01.json).

Receipt authority belongs to the immutable Snapshot and exact owner/symbol
prefix. The one complete producer pass uses a padded future-entry context;
`forbidden_owner` excludes future references while retaining owner-loop budget
charges. All context caches include that restriction. Unmatched/mixed inputs and
entries activating global spawn/input-invocation checks keep ordinary
validation. Source and Core trace IDs now have separate namespaces, with bounded
per-module completed clocks; source ordinals must never be attributed using Core
names.

The previous `4c9635bb` checkpoint compiles 2,785 native laws. Its type-effects
cycle passes 17 selected native laws, nine guests and zero Zig lint findings in
22.13 seconds; the same 17 native laws pass full allocation-failure mode in 3.07
seconds. Seven original kite draw-stream scenarios pass, with both producer Wasm
binaries and complete streams byte-identical to their pinned reference. The
required full gate stops after 3.10 seconds at **48 passed/one baseline
List/chunk storage_escape** at bytes 312..345, reproduced with the preserved
baseline compiler. Full qualification, whole-main/frame and release measurements
remain pending.

The broader automatic copy/append planner is also **rejected and removed**.
Original owned copies at eight sites shrink 26.5%, while production-scale plain
emit at sixteen sites shrinks 17.6%; both miss the unchanged 20% latency/30%
whole-module size gate. Their operation plans, native laws and actual stream
results are archived in
[copy-plan evidence](zig-native/measurements/rejected-owned-copy-plans-2026-11-01.json).
The nominal World/host interface rewrite is likewise removed: three pairs
regress total/checking latency. See
[nominal evidence](zig-native/measurements/rejected-nominal-world-2026-11-01.json).

The small opaque draw-batch prototype is **unqualified and archived**. Its
positive lifecycle case, three privacy laws, payload escape and three
live-borrow clear laws pass. Builder/Batch escape forms and even the matched
valid initialized-slot control hit unsupported storage layouts, so reference
streams and performance were never run. Public flat spans or owner stamps do not
preserve truncate/regrow safety. No renderer API migration or safety cut landed.
See
[prototype evidence](zig-native/measurements/unqualified-draw-batches-2026-11-01.json).

The first cursor-aware-unification step is **rejected and removed**. Reusing
completed parent normalization for unchanged queued children passes four new
native law groups, including full allocation faults, but three World-producer
pairs improve checking only **4.62 to 4.45 seconds (3.7%)**, below the 20% gate.
Total compilation is 8.42/8.24 seconds with identical tiny Wasm. This does not
falsify the larger cursor-view representation; it rejects the smaller worklist
receipt. See
[the archived experiment](zig-native/measurements/rejected-completed-unification-2026-11-01.json).

A bounded CPU profile now observes roughly **6%** of identified checking CPU
under unification and **25%** under normalization spread across application,
finish and obligation paths. These are approximate overlapping sample cohorts,
not phase clocks or upper bounds. The repaired sampler stops at the real Linux
thread entry instead of unwinding thousands of unknown tail frames; 79 complete
intervals cover 85.5% of process CPU with zero frame-limit truncation. The
producer completes inside its ten-second diagnostic cap. See
[CPU attribution and Astra's next experiment](zig-native/measurements/normalization-cpu-attribution-2026-11-01.json).

Focused validation sampling now identifies about **40%** of closure-validation
CPU in bounds/integrity checks, **20%** in task-context validation (the repeated
whole-context spawn-contract scan), **13%** in cycles and **10%** in principal
interfaces. These are diagnostic sample shares, not exact wall-time splits. Type
checking remains the first priority: normalization and fresh-build body cache
capture are the largest identified costs. See
[the checker/validation cost map](zig-native/measurements/checker-validation-costs-2026-11-01.json).

Astra's next discriminator requires a solver/validation-contract replacement.
Unification would consume `(id, cursor)` children directly and materialize at
variable binding/publication. Remove normalize-before-compare and duplicate
whole-root validation; give depth/work limits an explicit construction, binding
or publication boundary. Preserve histories, occurs checks, exact effects and
rollback. If the required validation behavior still demands preliminary full
walks, stop this direction: the adapter already measured that tradeoff. This
larger experiment keeps the **20% checking improvement** gate and does not
justify deleting history or language features. It is not implemented.

The engine-boundary batch adds opt-in `profileTrace` diagnostics, surviving
cancellation with exclusive phase checkpoints, module names, balanced
declaration regions, worker CPU/join intervals, backend stages and seven
optimizer-pass instruction/timing sums. Build IDs isolate retained revisions;
bounded active and slow-region lists survive tail eviction. Three rotated
controls measure **0.97% trace overhead on Matrix6 and 2.85% on the render
producer**, with byte-identical output. Profiling remains outside executable
identity. Compiler `e4af8647` compiles 2,777 native laws, passes six profiler
laws and both aggregate-reader guests. The required gate stops at 48 passed/one
known List/chunk owner-escape failure; full qualification remains pending. See
[engine evidence](zig-native/measurements/engine-boundary-experiments-2026-11-01.json).

The attempted completed readonly leaf plan is **rejected and removed**. Original
ECS readers activate three plans but save only 18 bytes, with effectively flat
compilation. Matrix6 activates none. Existing sharing already supplies one
reader definition; wrapping that work is not a general call/storage plan. The
archived patch and executed witnesses retain the experiment. The broader
copy/append family was subsequently measured and rejected as recorded above.

The explicit-interface experiments are also rejected: direct matrix composition
leaves checking flat; four render callback input annotations save about 4%,
below the 20% threshold. No source annotations or language feature cuts landed.
The larger nominal owner/access boundary was subsequently measured and rejected
as recorded above; no interface expansion remains installed.

`kites.draw` now appends directly to the caller draw pool, removing its
temporary owner/freeze/copy. Seven original production scenarios produce
bit-identical full draw/vector streams on `9b0f6b05`, including sentinel
prefixes and borrowed extras. Output falls **262,967 to 261,953 bytes**. The one
traced integration pair finishes in 6.83/6.39 seconds under an explicit
ten-second cap; it is not a latency benchmark. Ordinary diagnostics stay at five
seconds. Actual main still exceeds that cap, with no current whole-game Wasm or
new PNG. See
[stream evidence](zig-native/measurements/kites-destination-streams-2026-11-01.json).
Installed Pen checks are not qualification: its config parser rejects the
existing `tools` key and its code generator marks nine unchanged files stale;
the matching checkout executable needs its Steam shared-library path.

Completed ground callee prerequisites now share proofs within one equation
inquiry. A nominal depth-ten/eight-call graph that exhausted the unchanged work
budget now completes with **80 expansions and 80 hits**. Requested field
equations still follow their original proof path, and temporary solver
identities never enter receipts.

Covariance and normalization now preserve shared type graphs instead of copying
binary trees. Closing uses its existing exact context memo for source stores
too. The depth-sixteen source probe falls from roughly **3.5 seconds to 0.1
second**, with **858,720 to 6,750 type nodes** and identical **2,935-byte
Wasm**. The deeper case now completes below 0.2 seconds instead of exceeding
five seconds.
[Pinned evidence](zig-native/measurements/proof-and-type-sharing-2026-11-01.json)
keeps intermediate failures, matched pairs, real-workload controls and compiler
identities separate. A smaller Gdev fixture still has a modest latency
regression; the final invariant-leaf shortcut reduces that overhead.

Whole Gdev remains unfinished. The current candidate exceeds five-second main
diagnostics in both optimized and development modes with four optimizer workers;
there is no current whole-game size or fresh frame. Roughly **1 MB** remains the
owner's expectation. The historical frame-qualified main took 2,188 seconds and
produced 47.4 MB, mostly code. Release builds and release performance remain
pending.

The first type-structure architecture experiment is measured and **rejected**.
Copy-on-change during nonempty substitution passed its semantic laws but reduced
actual render/matrix/settings type-node creation by less than 0.25%; checker
time remained flat. Its larger production patch is archived, not installed.
Fourteen diagnostic counters now separate inclusive node growth and traversal
entries for import, substitution, resolution and covariance. The real render
producer creates 9,427 nodes under resolution versus 1,757 under substitution;
these are counts, not CPU shares. Variable views equal new binders in all three
producers, so historical-view canonicalization has no measured opportunity. Do
not add that optimization or a fresh cache. A deeper type representation change
needs to identify which changed children/rows force normalization copies. See
[the rejected experiment and attribution](zig-native/measurements/type-structure-experiment-2026-11-01.json).

Literal closures now share exact typed definitions across parent generators.
Captures and arguments travel as ordinary parameters; plain aggregate results
use caller-owned scratch. The actual returned-closure Mat4 probe at eight sites
shrinks **21,826 to 19,206 bytes**, with matched median **279 to 255 ms**. One
site grows **403 bytes** from call/scratch overhead. Native laws require one
closure definition reused inside two shared callback-reader parents.

Plain inline keys now omit only constructor refinements erased by that ABI.
Actual Ink easing over nine constructor states drops **10 to 2 definitions**,
**76 to 68 functions** and **9,132 to 8,300 bytes**; compilation time is flat.
Descriptor-reader/writer ownership and initialization facts remain exact.
Qualified/goaled closures and pending array destinations retain conservative
fallbacks. Six prior Ink controls are byte-identical, and Gdev language entries
execute unchanged. See
[typed-call evidence](zig-native/measurements/typed-call-sharing-2026-11-01.json).

Ink/Gdev source rewrites are authorized. The checked direct-destination kite
slice is recorded above. Robot accessory and crystal draw arrays have the same
pattern; preserve draw order and qualify their actual original streams before
changing them.

A final LLVM/fast compiler build hit its **90-second cap** without installing a
new binary; the previous release hash remains unchanged and was not used for new
performance claims. See
[the attempt](zig-native/measurements/typed-call-release-attempt-2026-11-01.json).
A separate `fast`/noLLVM development build finishes in about **5 seconds**,
passes six focused guests and executes all original language assertions with the
same 25,651-byte output. Main still exceeds five seconds. This alternate
configuration has narrower coverage than the reviewed safe compiler and is not
an LLVM release result. See
[the native-fast diagnostic](zig-native/measurements/native-fast-diagnostic-2026-11-01.json).
Neither attempt changes Pen settings or publishes a running environment.

Closed-row certificate paths now hash lazily, preserving exact receipt bytes,
multiplicity and work limits. Native sparse paths require **2 hashes rather than
1,026**, and target-free paths require none. Real producer checking improves
modestly; the smaller language fixture is effectively unchanged. See the
[receipt evidence](zig-native/measurements/receipt-path-hashing-2026-11-01.json).

Closed array locals now omit provably empty generalization, preserving contract,
method, explicit and generative paths. In the actual render-producer probe this
removes 659 generalizations and reduces candidate scans from 359,768 to 50,653.
Three matched pairs improve **882 to 642 ms**, with checking **509 to 258 ms**
and identical tiny-entry output. This is producer checking, not whole-game
emission. See the
[array-local evidence](zig-native/measurements/closed-array-locals-2026-11-01.json).

Plain aggregate readers now share definitions and exact admission receipts.
Actual Ink `transform.matrix` reader DAGs at depth six improve **669 to 375
ms**, **26,185 to 14,266 bytes**, and **96,094 to 4,140 admission visits**.
Result keys bind semantic and physical layout; every caller owns its shape and
scratch. Variant/borrow results keep their existing paths. The Gdev language
control is roughly flat in latency but grows **273 bytes (1.07%)**. See
[aggregate-reader evidence](zig-native/measurements/aggregate-reader-sharing-2026-11-01.json).

Selected-address loads now avoid whole-row scalarization for plain, stable
indexed rows. Actual `render.Settings` with eight blur writes shrinks **18,299
to 7,131 bytes**; marginal write cost falls **1,427 to 89 bytes**. Source-work
charges, bounds checks, alias writes, RHS `self` and post-RHS address validation
remain intact. Matrix control outputs are byte-identical; overall compilation
latency is roughly flat. See
[selected-field evidence](zig-native/measurements/selected-field-loads-2026-11-01.json).

Owned assembly now honors development/optimized tiers, optimizer workers, IO,
profiling and physical machine-code sharing. Its omitted stats previously
reported zero functions even though optimized passes ran. All six Ink controls
remain byte-identical across the old default and all four tier/worker pairs;
three rotated repetitions show roughly flat latency with variance. The matrix
control reports 58 functions and 58 parallel jobs with four workers. Defaults
stay optimized/serial/unshared; complete execution policy already belongs to
retained output identity. See
[owned assembly evidence](zig-native/measurements/owned-assembly-options-2026-11-01.json).

A three-second debugger sample catches actual main in source checking:
`Engine.instantiate -> Store.openCovariant -> memo insertion`, while three
frontend workers wait. This is one observed phase, not a CPU percentage or full
latency measurement. A short follow-up captures two root publications, too few
to rank hot paths. Measure unchanged substitution copies on a completed producer
before changing row opening; preserve fresh rows and exact callback
requirements. See
[the bounded checking sample](zig-native/measurements/gdev-checking-sample-2026-11-01.json).

Variant-bearing descriptor helpers remain a separate hypothesis. The real Robot
presentation path carries `Maybe Robot`, and original `robot_flight.blot` also
exceeds five seconds. `stableDescriptorShape` rejects variants for descriptor
reader/writer schemas, but the separate inline-call path already admits plain
variant values. Measure actual misses before widening that guard. Outline bank
slot reuse is secondary: historical globals are huge, but code bodies account
for most of the 47.4 MB. Do not repeat unchanged main diagnostics or reorder
optimization around outlining without new evidence.

The declaration-demand manifest is **diagnostic only**, with exhaustive source
checking unchanged. It now follows existing lazy initializer semantics instead
of seeding every non-function and attributed declaration. On identical sources,
main demand falls **5,277 to 4,241 of 5,957 declarations**, but retains
**82.6%** of original function-body bytes. Tiny-entry retention falls **77.2% to
2.1%**; actor falls **80.1% to 9.8%**. All three inventory pairs have zero
fallbacks and matching module-source digests. Planning takes about 165/25/47 ms
respectively in these single pairs, not compile-speed measurements. See
[the corrected demand inventory](zig-native/measurements/lazy-declaration-demand-2026-11-01.json).
The earlier
[over-rooted inventory](zig-native/measurements/declaration-demand-inventory-2026-11-01.json)
remains pinned historical evidence. Main still retains 98.5% of its previously
selected original body bytes; blanket initializer roots do not explain its
latency. Generated assets are included: 264 loaded modules on main. Unchecked
source names must never become completed typed interfaces.

Earlier descriptor, nominal and scalar call-sharing results remain in their
linked records under `zig-native/measurements/`. Those changes reduce synthetic
Wasm growth; they do not establish a current whole-game result.

This is a greenfield project. Breaking changes are welcome; remove superseded
APIs and implementations. Preserve useful behavior, assertions, deterministic
math, original workloads and independent references. Read `AGENTS.md`,
`compiler/guide.md`, `zig-native/CONTRACT.md` and `tasks/STORAGE_REWRITE.md`.

Actual Gdev main passed one headless native Pen frame on the last
frame-qualified compiler `52e04df6` and matching host. All six checks pass. The
inspected 640×480 startup image and guest trace match the original frame byte
for byte.
[Current exact identities and result](tasks/storage-handoff-evidence/2026-10-31-migrated-frame.json)
reuse
[the identical existing PNG](tasks/storage-handoff-evidence/2026-10-31-first-frame.png).
The earlier e6 compiler's
[first-frame record](tasks/storage-handoff-evidence/2026-10-31-first-frame.json)
remains historical evidence. Broader gameplay, browser, recovery and release
qualification remain open.

The active source/API migration covers the full Ink/Gdev inventories, fixtures,
generators and active documentation. Current language uses `func`, explicit
`return`, curried `->`, `$Constructor`, primitive booleans, `and`/`or` and
`#[...]` arrays. Grammar-rejection fixtures, foreign shader syntax and
historical captures intentionally retain their own text. Generated sources must
come from generator inputs, never manual output patches.

## Checked compiler fixes

The last frame-qualified compiler is the reviewed contract-method candidate, SHA
`52e04df6262c1572f07e9f16d474019a77dbdfbfd5fc1c042ea8fa3cb3242004`. Older exact
candidates may be absent locally; portable evidence qualifies its named
candidate rather than every later revision.

- [Imported opaque layouts](tasks/storage-handoff-evidence/2026-10-31-opaque-layouts.json)
  use exact closed producer metadata while preserving public opacity.
- Loop refinements, literal SIMD forwarding, proven-empty nested rows and
  impossible pattern fallbacks have executed regression coverage in the linked
  records under `tasks/storage-handoff-evidence/`. Original hauling and full
  packet fixtures now run without dummy rows or altered algorithms.
- [Lexical schemes](tasks/storage-handoff-evidence/2026-10-31-lexical-schemes.json)
  use bounded immutable lists, avoiding sparse temporary-fact saturation.
- [Indexed mutation](tasks/storage-handoff-evidence/2026-10-31-indexed-fields.json)
  preserves original owner and selected-field equations, including two indices.
- [Callback values](tasks/storage-handoff-evidence/2026-10-31-callback-values.json)
  align source/Core recipe classification while keeping invocation and no-store
  checks strict. All six original Gdev restore tests and both rejection tests
  pass. The latest native inventory compiles 2,730 tests; 435/436 affected laws
  pass with the same independently reproduced associated-partial baseline
  failure. All 61 affected guest tests pass.

[Contract methods](tasks/storage-handoff-evidence/2026-10-31-contract-methods.json)
now select exact visible implementations with full signature/effect evidence and
context-sensitive reusable calls. Original Gdev language tests and Ink
custom-codec persistence, including all 260 truncated inputs, pass on the final
candidate. Actual main now passes the recorded native frame on this binary.

Astra xhigh reviewed the semantic and performance boundaries. The earlier
typed-call compiler `fca4f6a1` compiles **2,776 native tests**. All five focused
typed-call laws pass in full fault mode, including allocation failures;
**434/435** broader sampled laws pass with the independently reproduced
associated-partial baseline failure. All **68 affected guests** pass, including
mixed aggregate/callback schemas, descriptor aliases, read replay, both tiers,
sync/JSPI and retained edits. Original Gdev language entries pass six entries/11
assertions per mode; the same 25,651-byte output remains. Zig lint has zero
findings across 572 files.

Body-reuse/text tests now pass **33/33**. Earlier 17/16 unrestricted runs
forwarded `HOME`, enabling disk-cache contamination between retained and
supposedly fresh clients. The body-reuse harness now explicitly disables
persistence. Those old figures were not compiler semantic regressions. The stale
five-character `true` span assertion is also corrected; all 42 protocol tests
pass.

The required full gate currently stops at **48 passed, one failed** in smoke.
The remaining list/chunk loop owner-escape failure is independently reproduced
on preserved `0faa0cbb`; it is not a passing gate. Release, full-native and
broader integration qualification remain pending.

## Remaining execution work

Source checks are distinct from emitting original exports and running
assertions. The `52e04df6` Ink inventory passes all 325 files: 322 valid files
and three intended semantic rejections, with matching end-of-run source digest.
Gdev's `52e04df6` inventory also passes all 441 current files:438 valid files
and three intended rejections. Both complete audits have matching end-of-run
source digests. Exact records and reproduction commands are in
[the migration evidence](tasks/storage-handoff-evidence/2026-10-31-source-migration.json).

All 68 original prepared-physics comparisons now pass on `9902355f`, including
all three modes at2,048 fixed bodies, with named source/proxy owners and
unchanged limits. All nine adapter entries pass 71 cases per mode. On
`52e04df6`, all six Gdev language/Format entries, six restore entries, both
restore traps and actor presentation's66 checks pass. The parser's typed leaves
execute, while its complete original module reaches the checked layout budget.
Full affordance, salt-clicks and remaining original-export qualification stay
open. Preserve original workloads and assertions while resolving those gaps.

Ordinary legacy backend retirement is still unfinished (task 120). Some pure
programs still emit ABI 3; do not fake ABI 8 with unused owners or claim that
the whole rewrite is complete. Task 121 covers final behavior and measurements.
Release/performance claims require the qualified release compiler.

## Integration and checks

Use the existing sibling checkouts. Build with Zig 0.17.0, checking
`zig version` first, and `-Dllvm=false` for development/native tests. Use
coherent affected batches and the required full gate as documented in
`AGENTS.md`.

Run actual Gdev main through native Pen, including its real imports and assets:

```sh
python3 scripts/storage_handoff/run_pen.py --launch
```

The default command recompiles every run. To retry rendering an already checked
actual main, use its exact artifact hash (the current record above identifies
this build):

```sh
python3 scripts/storage_handoff/run_pen.py --launch --compiled-main ../gdev/.pen/runtime/game.wasm --expected-wasm-sha256 63a4ae23b2ff61198b0d02ad47c2cd1342a524f33f16becc0a193ec2374fef0c
```

This copies the unchanged Wasm and starting scene into a fresh bundle, retaining
the original assets/text/locales/presets and all six host checks. It uses Pen's
standard raw-Wasm loader. Explicit Vulkan driver settings are respected; the
runner can also find the optional onboarding Mesa sysroot. No source compilation
or optimization runs in this mode. Rebuild after semantic changes rather than
reusing an older artifact.

Require every runner check and inspect the PNG. For a compile-only diagnosis:

```sh
deno run --no-config --no-lock -A scripts/storage_handoff/build_gdev.ts --compiler zig-native/zig-out-dev/bin/blotc --timeout-ms 5000 > /tmp/gdev-main.log 2>&1
python3 scripts/storage_handoff/report.py /tmp/gdev-main.log
```

Use `--entry tests/language_compatibility.blot` for the small real fixture and
`--profile` for completed-build phase attribution. The diagnostic accepts at
most 30 seconds. Only an explicitly requested full timing measurement may use
`--measure-total --timeout-ms 300000`; the default remains five seconds, and
timeouts remain incomplete. Do not use this long allowance for iteration. Defer
the Pen frame driver's regular application pipeline until bounded compilation is
fast enough. The older PNG does not qualify a later compiler.

The reusable frontend inventory checks unused declarations through overlays:

```sh
deno run --no-config --no-lock -A scripts/migration_audit.ts --project ../gdev --expectations ../gdev/tests/migration_expectations.json --report /tmp/gdev-audit.json
```

It does not emit original exports or execute their assertions. Its project
source digest excludes external library snapshots; rerun after dependencies
settle. Keep large outputs ignored and commit concise portable evidence.

## Frozen contracts

- ABI 8, session 2, Gdev saved framing 26 and packet order remain fixed.
- Gdev storage: 2 MiB temporary, 256 KiB persistent, 2 MiB transport, 4,096
  owners. Reply budget: 64 MiB including assets.
- Production expansion: 500,000 expressions per physical function; layout work:
  100,000. Engine bounds: 7,654,321 body bytes, 50,000 parameters/locals and
  1,000,000 globals. Do not raise these limits to pass fixtures.
- Named owners are independent. Access records alias live pools. Borrowed views
  remain invocation-local; copy retained history and host/worker packets.
  Preserve callback effects and explicit checkpoint/restore. Renderer rejection
  is not rollback. Language tasks are retired; copied-packet workers remain.
- Gdev FrameAccess has 165 fields and four explicitly pure storage callbacks.
  Preserve exact generic field types and real latent callback effects.

Continuously commit coherent checked batches to each `main` and verify remote
hashes. Preserve unrelated work. Environment publication requires a separate
explicit request. Older checkpoint narratives remain in pinned Git history and
portable evidence, rather than duplicate continuation documents.
