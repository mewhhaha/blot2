# Iterator state qualification

Complete generic iterator qualification remains open. The first checkpoint,
`cb3ebec`, removes eligible scalar-only local objects. Generic adapters and
packed List cursors still require separate qualification.

## Scalar local state

Scalar replacement accepts an ownership journal reference only when every
allocation in that copy/version group has an exact scalar layout. Reference,
erased and unknown fields retain heap storage. Calls, captures, returns,
incomplete initialization and unsupported control keep the ordinary fallback. No
source type or adapter name selects this optimization.

Each admitted snapshot receives independent field locals. Copies read all source
fields before writing destinations; demanded fields propagate backwards through
copies and loop carries. F32 fields retain their bits. Replaced objects use zero
as their private address. Their acyclic marker and anonymous journal slot are
removed; scope boundaries and carry-slot clearing retain their original order.
Demand-force markers still prevent replacement.

The companion callable change stores a single checked reference argument
directly in a named partial application's descriptor. Scalar/erased arguments
and later multiple-argument environments retain ordinary storage. Static
serialization, fresh/retained/restart emission and pointer-looking scalar laws
use the same selected layout rule. See
[tracing replacement](TRACING_REPLACEMENT.md).

## Qualified checkpoint

Zig 0.17.0; standard LLVM/Fast release; full native/OOM suite and **965**
guest/client tests pass, including both codegen tiers and all eight unchanged
allocation budgets. The analyzer checks 351 Zig files with zero findings. New
laws cover scalar snapshots, branch exits, nested activations, captured and
reference fallback, sync/JSPI suspension, rejection and subsequent recovery.

The implementation tree is `e8525b1d36c5c30bc81f971d59b296787a83f6cd`; compiler
source is `feefe32c716a268ece1c46171a44f8ad3cd6b6ed`. Executable SHA-256 is
`7c5c3068284f423f0bdd341b1b3b17dc2ee812591146a362b67c3b6a87b9cc2f`, with
identity `8a8562d7e77af1b050fa7cd2fac00e1fb9a64c260d889d42e7cab4fd956c501d`.
Ignored evidence and exact source/harness/report pins live under
`build/bench/iterators-047/`, especially `release/pins.json`.

The same 4,096-step record cursor drops 4,097 object allocations to zero after
journal warmup, and 12,293 slot reservations to 4,100. Both versions preserve
values and finish with zero roots, leases and live profiling payload at
shutdown. Thirty-one alternating warmed release pairs on CPU 7 measure 0.269 to
0.023 ms median guest CPU. This is a scalar record cursor, not a generic adapter
result. The range/map/take control still makes 57,350 allocations; its timing
does not establish adapter elimination.

Seven alternating compiler pairs across 13 public examples preserve diagnostics,
semantic work and per-binary determinism. CPU ratios span 0.9624–1.0321,
requested allocation deltas 0–9,441 bytes, peak deltas zero and teardown zero.
Four synthetic workloads preserve cross-compiler/fresh/retained/restart bytes
and compared counters. No general compiler gain is claimed.

Merged ordinary ownership controls remain flat at 128 KiB. Twenty-five
alternating pairs, discarding five, measure cycle CPU 16.064 to 13.868 ms
synchronously and 16.161 to 13.933 ms with JSPI. Other control ratios span
0.9848–1.0120. The callable implementation's isolated release measurements
remain separate in the tracing record; neither closes task 035's full removal
gate.

## Remaining work

Reference-bearing generic state needs equivalent owned roots, complete producer
exposure and measured benefits before admission. Packed List cursors need
independent private progress, bounded sequential leaf traversal and all-width
comparison with the reconstructed boxed reference. Published cursors, forks,
saved rows, cross-leaf rows, effects and reference fallbacks must remain exact.
Nothing is pushed and rejected/provisional artifacts remain preserved.

## Owning-field and packed cursor checkpoint

Compiler 6a57437 adds reusable roots for exact private reference fields and
bounded producer exposure, plus four-local checked packed List cursor families.
The [merged qualification](ITERATOR_CONSTANTS_QUALIFICATION.md) records actual
release counts, CPU/compiler costs, full native/973 guests and 355-file zero
analyzer. Array cursors lose 4097 objects; range/map/take loses 4096. Repeated
F32 all-width cursors qualify; U32 boxed tails and other tagged adapters remain
open. Late ownership rollback keeps ordinary source bodies and scalar-only reuse
exact. Projection and word-progress experiments remain separate.

## Resolved collection progress

An exact ordinary collection `iter`/`next` pair can now select direct List/Array
progress after monomorphic layouts are known. The bounded proof requires the
private generated cursor/step/rest loop shape and the exact pure cursor producer
bodies. Observable progress, forks, custom or effectful methods, packed rows and
exhausted proofs keep their original protocol. The immutable Core stays intact;
the resolved loop carries the selection. Its collection owner is published
before the cursor can be released. Producer-body reads conservatively regenerate
the containing artifact code job.

Private List walks allocate `(height + 2) * 4` bytes after checking the root
height, with one owned descriptor word and borrowed pending node bases. Scalar
path words are initialized before use; unused scalar capacity needs no clearing.

The Safe/noLLVM focused checkpoint in `build/bench/collection-047/` reduces a
4,096-element generic List fold from 8,228 to 36 objects and 115,632 to 17,340
payload bytes. The ten-adapter screen reduces three-element-window folding from
77,800 to 53,236 objects and 1,244,788 to 917,268 bytes; other adapter counts
stay equal. Results, zero roots/leases and the 4,096-byte reset journal match.
Fresh/retained artifact replay, complete OOM sweeps and immutable-Core laws
pass; both-tier guests cover joins, early exits, nested reentry, references,
floats, observable forks and effectful method controls. An existing snapshot
guest also fails on the current control with `ownership_unproved` in
`Cursor.next`; that production-admission gap remains separate. LLVM CPU/compiler
costs and the combined full gate remain required before qualification. Task 047
remains open.

## Empty cursor production admission

The existing snapshot failure above reduces to `[].iter.next`: its dead `Some`
branch still had an unknown element word. An exact empty literal plus the
ordinary pure cursor methods now selects the nullary empty constructor while
preserving receiver evaluation. Empty Array/List cases retain their unresolved
source types. Edited iter/next methods decline this selection, including methods
that return a value for an empty input. Fresh/retained output, complete OOM laws
and both codegen tiers pass. The original snapshot and partial-collection guests
now execute under complete checked ownership. This is a production-admission
repair; combined qualification remains required.

## Single-leaf traversal, 14 October 2026

Private walks now use the existing span locals directly when the List root is a
leaf. An explicit source root spans the traversal; carry roots are reserved
outside that scope so carried children survive its exits. Taller trees retain
their bounded path storage. Traversal preparation also initializes the arena
before emitting imported consuming callees, fixing a baseline null-arena crash.

The Safe/noLLVM development screen at 4,096 rows with three-element windows
reduces objects 53,236→49,142 and requested payload 917,268→884,516 bytes. The
result remains 25,147,395; roots/leases return to zero and warmed memory stays
131,072 bytes. Thirty-one alternating warmed batches of eight calls measure
6.054→5.767 ms (ratio 0.9526). An 8,192-element tree control measures ratio
0.9765 with unchanged memory. These are focused guest measurements, not release
compiler or complete adapter qualification.

The native carry/replay/allocation-failure law passes in 9.57 s. Both codegen
tiers preserve source/compiled/checkpoint bytes, carried reference children
under allocation pressure, synchronous/JSPI effects and flat warmed memory.
Existing import/edit/failure/revert controls pass. Immutable patch SHA-256 is
`9662f78178e6ca89c7f442a72251e63cc2d9d74ab1e200f50d202f1345e87b7e`; binary/Wasm
pins and raw measurements are in
`/var/tmp/blot2-continue-1791939463/window-inspection/`. The combined LLVM gate
remains required; remaining window state keeps task 047 open.

## Immediate collection steps, 15 October 2026

An exact pure ordinary Array/List cursor producer with one immediately adjacent
two-field constructor pattern can emit its original has/value/advance operations
without the transient pair or Some cell. Receiver evaluation stays at its
original bind, once. Bound reference fields retain their ordinary owning roles;
the immutable successor cursor remains an ordinary allocation. Exact producer
body reads participate in retained admission. Saved/captured steps, other uses,
unknown/effectful or dictionary-bearing methods, opaque constructor families and
packed rows keep the ordinary path.

Root 3 native laws, complete emission allocation failures, 5 executed guest
groups, TypeScript and 111 affected zero-finding analyzer files pass. Controls
cover constructor/predicate changes, escaping steps, immutable replay,
source/archive producer edits, checkpoint, reference pressure, forks and ordered
suspended receiver effects. The private Windows screen changes 41→39 allocation
sites, 56→52 publications and 18412→17846B Wasm. Seven tiny wall pairs suggest a
local gain; they do not qualify CPU, compiler overhead or the all-width packed
gate. Root ordinary Cost stays byte-identical. Exact source/compiler pins and
logs: `build/bench/complete-program-20261015/immediate-collection-step/`.

## Local cursor successor families, 15 October 2026

An exact lexical family of ordinary Array/List cursors can retain its four
progress fields in locals. Actual return/product/record/constructor escapes
materialize an ordinary immutable typed header. The collection remains rooted;
breaks and backedges copy all fields, preserving old forks. Calls, captures,
merges, unknown producers and packed rows decline. Existing whole-loop lowering
owns its families independently.

Root 3 native laws with complete emission allocation failures, 11 executed
groups, TypeScript and 111 affected zero-finding analyzer files pass. Controls
include returned snapshots, reference pressure, nested progress, suspended
failures, source/archive edits and checkpoint restart. The private fork screen
removes 2 allocation sites, keeps 7 publications and changes 7086→7053B Wasm.
Tiny wall samples do not qualify CPU or compiler cost. Ordinary Cost stays
byte-identical. Exact source/compiler pins and logs:
`build/bench/complete-program-20261015/local-cursor-successors/`.

The representative packed width1 comparison remains slower than boxed/task 002
references. Diagnostic existing-counter exports preserve every code section and
identify per-row retain/release and root-journal work, with only 64 allocated
bytes per 16384-row cursor traversal. The width1 output is byte-identical
before/after this successor delta. No all-width or task 047 completion is
claimed. Raw rounds, section parity and diagnostic-only source pins are under
`/var/tmp/blot2-collection-successor-20261015/build/bench/task047-final-preparation-20261015/`.

## Empty scalar lexical frames, 15 October 2026

Fresh executable control flow proves an inner scalar frame has no allocating,
publishing or unknown action and one exact opening on every path to its closes.
Calls, imports, writes, reference exits and resource drains decline. Public
invocation frames remain; each removed close preserves its conditional collector
boundary. Changed cleanup-drain presence now invalidates optimizer reuse, fixing
a separate stale-body case caught by a native add/remove-drain mutant.

Root 3 native laws with complete allocation failures, 29 executed groups and 266
affected zero-finding analyzer files pass. The root width1 output is byte-exact
with the timed private candidate. For 16384 U32 record rows, 31 paired samples
of 16 traversals measure fold process CPU 0.133625→0.0105 ms. Cursor
code/counters remain unchanged. Ordinary Cost is exact 11958B. These results
establish the local fold cause and fix; all-width cursor/adapter and compiler
qualification stay open. Exact source, raw measurements and pins:
`build/bench/complete-program-20261015/empty-lexical-row-frames/`.

## Persistent cursor publications, 15 October 2026

Fresh typed RuntimeIR now proves when a real persistent slot already owns an
exact local copy for its entire lexical lifetime. A dominating reservation and
strong store must cover every reachable path. Rebinding, bypassed
initialization, closed owners, calls, writes, resource operations and exhausted
analysis decline. Only duplicate row publication disappears; real slots, closes,
traps and safe points remain. No pointer comparison or persisted owner hint
supplies authority.

Three root native laws with complete allocation failures and four selected guest
groups pass, alongside shared 402/455-file zero-finding analyzer coverage. The
root Array output is byte-identical to the timed candidate. For 16384 U32 Array
rows, retain/release traffic falls 16385 to 1 with zero allocation traffic and
unchanged shutdown roots. Thirty-one balanced pairs measure cursor process CPU
0.27275 to 0.10575 ms sync and 0.2848125 to 0.106 ms JSPI. Fold controls are
unchanged. This is a finite Array result; the List leaf-cache helper and
obsolete forever-loop tracing packet remain conservative fallbacks.
Compiler-cost, all-width/adapter and final task qualification remain open. Pins
and raw evidence:
`build/bench/complete-program-20261015/persistent-cursor-borrows/`.

Twenty balanced compiler pairs now quantify the tradeoff: ordinary retained
edits 28.75 to 29.0625 ms CPU (+1.09%), finite Array 36.875 to 37.8125 ms
(+2.53%). Each sample averages 32 real edits; all process CPU values are
positive and before/candidate outputs are exact. Fresh 50/50 and 60/60 ms
medians are limited by the 10 ms clock and do not prove zero overhead. One 60 s
cap preserved 43 of 80 samples; one continuation collected only the missing 37.
Exact paired records, cross-slot sensitivity and the read-only 949-instruction
List helper attribution are frozen in
`/var/tmp/blot2-cursor-owner-20261015/build/bench/persistent-cursor-borrows-followup-final-20261015/`.
The original List and broad task 047 performance gates remain open.

## Persistent descriptor snapshots, 15 October 2026

Cursor creation can share the existing List descriptor. A lazy runtime helper
freezes that descriptor and its current tree root using the runtime's actual
immutability and owner-token fields. Later writers use the existing
copy-on-write branch. Each cursor still owns independent progress/cache fields;
escaping and unknown cursors retain ordinary headers. The helper has a journal
role and an exact retained/replay mapping. No source method name or persisted
hint supplies snapshot authority.

On the current tracing-free owner compiler, the 4,096-row three-element Window
fold removes exactly 4,094 descriptor allocations: 49,143→45,049 allocator
requests and 888,612→757,604 requested payload bytes. Result 25,147,395, 131,072
committed bytes and zero ending roots/leases remain exact. These request totals
include one 4,096-byte journal request; the separately reported RC destruction
count is one lower. The outer-only fold stays exact. A separate 4-byte capture
per window remains, alongside the broader generic adapter state.

The unchanged ten-adapter corpus plus Array control has 176 passing structural
rows. All 62 record/tuple and U32/F32 row widths have exact fold/cursor outputs;
packed cursor calls remove one 64-byte block (32-byte payload), while direct
fold counters stay unchanged. Three native laws with complete allocation-failure
sweeps, 28 existing guests and a new both-tier
writer/reference/window/checkpoint law pass. Six changed Zig files have zero
analyzer findings. All eight original compile budgets pass unchanged; ordinary
Cost and two retained-value programs have exact twelve-phase byte/work records
and three cold allocation records.

These are development structural results. Compiler CPU, boxed/task-002 List
comparisons, broader state elimination and the final combined release/full gate
remain open. The older forever-loop tracing fallback mentioned above has already
been removed by Task 035; actual unconfined cycle collection remains intact.
Private source, failures and measurements are retained at
`/var/tmp/blot2-task047-final-owners-20261015/`.

## Direct constructor sinks, 15 October 2026

A direct `let $Some (value, rest) = cursor.next` now uses the existing exact
ordinary producer proof and closed private cursor-family analysis, just like an
immediately adjacent step binding. Both spellings preserve receiver evaluation,
field order, failure control and normal owning reference publications. Saved
steps, unknown/effectful producer bodies, opaque constructors, nested patterns
and packed rows retain their existing paths. No source name selects admission.

The Safe/noLLVM structural screen at 4,096 elements reduces a direct List cursor
walk from 8,228 to 35 allocations and 551,040 to 26,688 allocator block bytes.
Reading the first element of each three-element window drops 61,425 to 45,049
allocations; complete nested folding stays at 45,049. Values, 128 KiB memory,
zero roots/leases and independent snapshots remain exact. The remaining 4,094
four-byte reducer capture objects and general Window state remain open.

A new immutable-Core/fresh/replay law passes complete emission allocation
failures. The six existing producer/family laws and 23 executed guest controls
pass, including both tiers, reference pressure, forks, saved steps, early exits,
sync/JSPI receiver effects, rejection/recovery, archived producer edits and
checkpoint restart. All eight original compile budgets pass with restart caching
disabled. Default-cache diagnostic runs fail the same chain_generic budget in
both controls because cache setup allocates additional memory; those failures
are retained. Twelve fresh/unchanged/edit/revert byte/work records and three
whole cold allocation records match exactly. Three changed Zig files have zero
analyzer findings. Evidence is pinned under
`/var/tmp/blot2-task047-direct-pattern-20261015/`. No LLVM timing or full gate
is claimed by this focused checkpoint; task 047 remains open.

## Scalar closure snapshots (Task 047)

An anonymous closure with exactly one physical inert scalar capture carries the
captured word directly. The mode is part of the retained template and closure
key; portable imports recheck the complete capture layout. Closure descriptors
use the actual callee parameter role. Factories keep their boxed environment
ABI, and reference, erased, F32, nested-template and unknown layouts retain
their existing environment objects. Task moves skip only this proven scalar
word. The constructor and callback-fusion proofs require the same exact input,
header and target roles; pointer-looking scalar values remain scalars.

For 4,096 inputs the nested Window fold removes 4,094 four-byte environments:
45,049 to 40,955 allocator requests, 757,604 to 741,228 payload bytes and
2,891,264 to 2,629,248 rounded block bytes. The ten adapter and Array controls
retain their prior object counts except the one take-while scalar environment.
Independent cursor forks, saved cross-leaf windows, writers, early exits,
reference captures, destructor ordering and unconfined cycle controls remain
required. This subtraction does not eliminate the remaining Window descriptors.

A separate compiler subtraction borrows the immutable Outcome slice returned by
a direct activation-graph call. Only multi-target calls concatenate outcomes.
This removes an arena copy without changing flow states, guard checks, call
order or proof admission. Diagnostic paired reports preserve complete and
rejected graph results. Final common LLVM, boxed/task 002 CPU comparisons and
the full compiler gate remain pending; focused development results do not close
Task 047 or Task 035.

## Prior packed-cursor path diagnostic, 20 October 2026

The pinned prior `0f53…` artifact for 16-field U32 records and 16,384 rows has
Wasm SHA-256 `32e5bade5498225134c5ea27f065553d1bcbec458af9e7dcfd05ba5fde007451`.
A diagnostic copy adds counters to its existing List address function. After one
cursor warmup, a cursor pass before any measured fold and another after the fold
each make **1,093 address calls, all through the directory**, with zero root
searches or tree edges. The fold makes zero address calls. Every witness is
2,149,318,656 and agrees with the unmodified original Wasm.

This is a route count for one old artifact, not a current compiler, runtime CPU
or instruction-count qualification. It rules out repeated root search as the
explanation for this warmed case; any proposed private traversal path must be
measured against the actual directory path. Original/instrumented Wasm and WAT
hashes are in `build/bench/task047-prior-path-counts/results.json`, SHA-256
`0806c74edf4e413a782dd148f4a9ef829429abd34c5a941f2afb8a8e6d03927f`.

The qualified `4fda7c2` compiler reproduces this exact width-16 Wasm in the
current standard-library screen, so the route count also describes that current
artifact. The scope is still one artifact, with no runtime CPU claim from its
diagnostic counters.

### Shared traversal-path screen, rejected

The isolated shared-path candidate passes three new native laws plus their root
harness, complete allocation-failure/replay controls and eight guest groups.
These cover all supported widths, saved versions, forks, pressure and JSPI. Its
safe/no-LLVM compiler is
`8eadc35a59ea3c81f4e2d53dbbd958efaa6709e2c16c2b73217c5f207404583a`; focused pins
and binaries remain in `build/bench/task047-linear-focused/`.

The current-std U32 record screen uses the qualified release as baseline, the
same optimized guest tier and one worker, CPU 2, 16,384 rows, 20 warmups and 31
alternating pairs of sixteen traversals. Executed witnesses pass, but cursor
sample medians regress:

| Width | Baseline ms / traversal | Candidate ms / traversal | Candidate / baseline |
| ----- | ----------------------: | -----------------------: | -------------------: |
| 1     |                0.688250 |                 2.026000 |             2.943698 |
| 3     |                0.382438 |                 1.070000 |             2.797843 |
| 16    |                0.465500 |                 1.315750 |             2.826531 |

The variant is rejected and remains outside main. Native compiler CPU is not
compared across its different host build modes. Results:
`build/bench/task047-linear-current-u32-screen/report.json`, SHA-256
`37a1d761aa61544c118101102b338b242f2bc99def4a1c3e0d1a67399e6bbd82`.

A first directory candidate also passes the focused correctness checks but
regresses cursor runtime 2.56–3.49×. Runtime counters show about one additional
retain/release per row in both rejected candidates, with zero cycle passes. The
existing persistent-slot proof correctly declines the holder's final
`Arena.recycle`: it can detach an original journal root. That helper must retain
its existing ownership classification.

### Scoped directory candidate, focused checks passed

The next directory candidate opens the cursor-carry root frame after
constructing the owning directory holder. The frame closes before the holder is
recycled; the existing proof can cover the complete loop without changing root
authority. Leaf crossings read the next directory leaf and its actual length.
Saved cursor versions keep their independent collection, index, leaf and base
fields. The bounded proof requires one creation, one loop carry and one direct
advance that supplies its backedge. Resets, additional carries and nested
advances decline.

The safe/no-LLVM compiler is
`ad19cf8961258d70c329c9de0583deedde30443c5796ac96ae076db8ff9373f6`. Five native
tests, complete OOM/replay checks, eight guest groups and the 124-file backend
analyzer pass. The tests include uneven sliced leaves, returned cursors,
pressure, snapshots, all widths, forks and JSPI. Artifacts and source pins are
in `build/bench/task047-directory-scoped-focused/`.

The same CPU-2/current-std protocol measures cursor ratios at widths 1/3/16:

| Scalar | Width 1 | Width 3 | Width 16 |
| ------ | ------: | ------: | -------: |
| U32    | 0.22284 | 0.25209 |  0.26691 |
| F32    | 0.25915 | 0.28364 |  0.75129 |

Actual work counters show three retains and four releases per traversal at both
U32 widths 1 and 16, plus one 48-byte rounded setup allocation. The baseline
performs 69 and 1,094 retain/release pairs respectively. All cycle counters stay
zero. The global List keeps its original one root and one lease; calls add
neither and warmed committed memory stays flat. These are runtime work counters,
not instruction counts. Reports remain in
`build/bench/task047-directory-scoped-current-{u32,f32}-screen/`.

Both historical-source LLVM reconstructions pass an actual common-std ABI,
result and warmed-memory smoke: 84 checks across boxed, task-002 and current.
These are newly rebuilt references, not the lost original binaries or timings.
The all-width comparison passes 186 width/type/shape pairs: 62 against each
reference on their common historical std and another 62 against the current
release on current std. Every executed witness agrees; no cursor median
regresses. Candidate/reference cursor ratios are:

| Reference and std               | Minimum |  Median | Maximum |
| ------------------------------- | ------: | ------: | ------: |
| Boxed, common historical std    | 0.31636 | 0.67376 | 0.90473 |
| Task 002, common historical std | 0.09933 | 0.13757 | 0.35757 |
| Current, current std            | 0.22899 | 0.32135 | 0.92292 |

The verified summary is `build/bench/task047-scoped-all-width-summary.json`,
SHA-256 `1a485353f9eab93ac9ba974377c18fa8e0cc1e9445e0ddef48099383604f82e1`.
Compiler inputs, standard sources, harnesses and all Wasm hashes remain pinned;
compiler teardown is zero. This qualifies the development candidate's guest
screen. Native compiler cost and final LLVM/full checks remain open. The earlier
62-case task-024/current comparison does not satisfy this historical gate.

An additional reference exit from inside the cursor loop passes both tiers. The
eleven-adapter diagnostic also passes executed results, roots/leases and flat
warmed memory at counts 0/2/3/4,096. Enumerate, zip and strict zip allocate
zero. A named partially applied fold still allocates per input in range, map,
filter and take chains. Nested three-element Window folding makes 65,518
allocator requests per 4,096 inputs; direct nested loops make 40,954. Those
counts include semantic buffers as well as remaining state. The scoped cursor
change leaves these adapter counts exact. Results:
`build/bench/task047-scoped-adapter-screen-v2/results.json`, SHA-256
`d9e1812fa29ec43355b578dc9ea6c1d728ab021b340e806583c3e5f57021c691`. The reviewed
candidate is now in main's working tree for combined qualification; the latest
committed compiler remains `4fda7c2`. Window and broader generic state are still
open.

## Evaluated fold calls and static scalar seeds, focused qualification

A fully saturated call through an immutable evaluated named closure can retain
its exact captured values while emitting the original source body. The bounded
plan keeps the original semantic type/effect mappings, refines the complete
source signature with the existing specializer, and checks each dynamic
argument's actual layout. Dynamic arguments execute once in their written order.
Partial, erased, universal, demand, factory, dictionary and exhausted plans keep
ordinary calls. Unrecorded live evaluator handles require fresh executable code.
Complete owned static reads/capture graphs keep the existing executable identity
rules; handles do not become portable identities. Cursor and root authority
rules stay unchanged.

The combined development compiler is
`f8711261195d3a139ff11b8e62c600adff240e2f266db3f656969348529f18d1`. At 4,096
inputs the same 100-call allocation observer measures rounded bytes per call:

| Adapter through a named fold | Qualified baseline | Candidate |
| ---------------------------- | -----------------: | --------: |
| Range                        |            983,136 |         0 |
| Map                          |          1,573,056 |         0 |
| Filter                       |          1,179,840 |         0 |
| Take                         |            786,624 |         0 |
| Take while                   |            885,120 |        48 |
| Nested Window fold           |          3,406,944 | 2,227,872 |

The take-while remainder is one setup object. Enumerate, zip and strict zip stay
at zero. Window requests drop from 65,518 to 40,954; direct Window loops and
length-only consumers still make 40,954 requests. This subtraction exposes the
inner fold without eliminating the remaining Window state and buffers. The CPU-2
diagnostic measures a Window ratio of 0.7848; tiny zero-allocation scalar
timings do not establish precise speedup factors. The native compiler host is a
safe/no-LLVM build, so its CPU cost is not compared with the LLVM baseline here.
Report: `build/bench/task047-static-seed-adapter-screen/results.json`, SHA-256
`71dab8725e9ef1cb2d3cef50a26730bf4f194ada89090b9470dddb146e737b60`.

The broader reference test also found a baseline correctness bug. Ordinary
static `List U32` and `List F32` seeds used a reference-element descriptor.
Later leaf growth copied that classification and tried to retain numeric words.
Both baseline and pre-fix candidate fail fresh instances at 1,024 or more
elements; the retained raw report is
`build/bench/task047-reference-fold-repro/results.json`, SHA-256
`2ef859bd34f1e7fa02bcbedfd393a461228b56f4f37d8c387de04e8da1372296`. The scalar
seed fix selects the existing scalar descriptor from the element's known layout
role. Reference elements keep their reference descriptor. No pointer test or new
acyclic flag is involved.

Two new native laws pass complete fresh/retained OOM, replay, checkpoint,
capture-edit and immutable-Core checks. The corrected combined compiler passes
both-tier scalar/F32/reference tests through 4,096 elements, including
pointer-looking integers, real reference children under pressure, aliases,
effects and ordering. Twelve combined guest groups pass, including a strict
zero-allocation budget for optimized named range/map/filter/take folds,
all-width cursor snapshots, JSPI, Window pull order and outward exits. Focused
artifacts are in `build/bench/task047-static-seed-focused/`.

The implementation is working-tree work awaiting compiler cost and the complete
LLVM gate. The causal byte control passes below. Final combined all-width
comparisons and remaining Window/generic-state requirements still keep task 047
open.

The all-changes-off control now passes 14 fresh compilation observations across
game, devtools and five frozen test entries. Six successful pairs reproduce both
the qualified `1b05…` bytes and recorded hashes. Protocol keeps the same
expected `non_exhaustive_match` rejection; it is not an executed passing game
test. The control disables cursor-directory preparation and evaluated-call
admission, and restores the qualified scalar-seed serializer. Its safe/no-LLVM
compiler is `1b6acc26795fa7c9a3891f2348f6533d5eb16e52e44573276721d6a8b8708474`.
The prototype source was restored exactly afterward. Results:
`build/bench/task047-causal-control-parity/results.json`, SHA-256
`7e7d751f389f7b297b129ac30c1e59d6686a42dc838c4c67d381a1b80160dbca`. This is a
byte control across host build modes, with no native CPU comparison.

The working-tree retained variant keeps the existing owned static-read/capture
identity when complete, with fresh code for unrecorded values. Its strengthened
native law now proves positive named-body reuse as well as exact same-source,
captured-edit and checkpoint bytes through complete OOM. Both native batches,
twelve combined guest groups and all 512 source modules plus the analyzer
fixture pass. The immutable focused compiler is
`debc8a40dae9f2a3a089ad6146d9aad07bedcdad5c4c0a5cc7fb1a30583db6fb` in
`build/bench/task047-owned-static-focused/`.

Both cold LLVM builds pass. The compiler is
`cf00bb788518a6f28f38416fc75858e43ea82d1f53e06d412a6bac7c875b18a3`; its
provisional binary is preserved in
`build/bench/task047-owned-static-llvm-built/`. The native test executable is
`a7bd1805ef4cee2013125ac15edbff72fed1c2412f35d86f54cadcf59b0ff12b`. The cold
run, `run-88c1f7a9a8d65dfe`, was ended after the successful 77-minute native
compilation to give execution a fresh budget. Its verified compilation journal
and exact binary are preserved.

The next run, `run-89672d89ec4b6759`, passes 48 smoke tests, then stops when a
synthetic orchestration fixture's 30-second budget expires before its intended
guest-failure case. That fixture now allows 120 seconds for cold Deno startup
and module checking. All six focused recovery, invalidation, real deadline and
descendant-cancellation laws pass. Compiler and guest sources stay unchanged.
The complete gate, `run-5f526fff488d4497`, passes all 37 harness tests and
reuses verified compilation, then fails two native archive fixtures. Their
callback is now inlined, leaving no independently selected receipt; the semantic
encoder correctly omits the optional archive. A focused control with the
existing inlining switch disabled restores one complete receipt and passes the
snapshot-cost law. The archive fixture repair and a default-inlining
checkpoint/OOM control now pass all 16 archive laws plus their root harness.
They cover generated origins, staging, package and nominal recipes, edited and
failed sources, forged catalogs and receipts, member-authority omission and both
staged control-flow helpers through complete allocation-failure sweeps. Only the
test fixture disables inlining to retain an independent receipt; the
default-mode checkpoint still omits the absent optional owner and preserves
restart bytes. Focused evidence is preserved in
`build/bench/task047-semantic-archive-fixture-focused/`. The repaired
1,168-input manifest is
`9e945a90b7af0d400d7df3533a71341643c1654335945394ff30c32a7ad28707`. The failed
run's prior 1,168-input manifest is
`aef2c3f1fca6a5e85f05d5a10d8ef47cc5b98c86fb1845e982020caf5f8c764d`. No full
execution or release-cost pass is claimed yet.

A preflight audit found the same receipt assumption in the component query
tests. Its default-mode reproducer fails, and a dedicated private `emitQuery`
fixture retains a selectable callee without changing the existing proof,
diagnostic, fuel, quota, rollback or byte assertions. All 35 affected component
laws plus their root harness pass, including complete allocation-failure sweeps.
Evidence remains in `build/bench/task047-query-fixture-focused/`. The resulting
1,168-input manifest is
`f2f8a649ad24ae0e1266748efcd8b1e7eea7d5d991eed4c878845c1b159807c6`. The
default-mode checkpoint and executed-Wasm controls remain separate. Both
analyzers pass all 512 source files plus the fixture module at zero findings.
Full forced LLVM run `run-14b15bf8959adf0b` passes 48 smoke tests, 37 harness
tests and the release build, then stops at the native compilation budget:
7,200.44 seconds, exit 124, with empty compiler stderr. No native laws or guests
ran. The queued release measurements correctly refuse the missing successful
gate. Evidence remains in `build/bench/task047-native-compile-budget-stop/`. Run
`run-a534b7ef0e6f4916` retries the same frozen inputs with 21,600 seconds
overall and 14,400 per host phase. Forced native execution, the 14 GiB memory
guard and the separate compiler CPU acceptance limit of 1.05 stay unchanged. The
retry's native compilation passes in 3,315.78 seconds with a cache miss; its new
test binary is `b21b4a60…`. The complete native run reports 2,496 passes and
eight failures, with no skips, leaks or logged errors. Seven laws require
selected queries, and one requires a semantic checkpoint owner. Isolated
controls confirm that the new inlining removes the catalog fixture's queries;
adjusted fixtures restore the required queries and checkpoint owner. All seven
previously failing retained laws, their allocation-failure checks and 27 other
retained laws pass with larger synthetic identity bodies. All four module-token
laws pass; only the checkpoint law disables named inlining to require a selected
receipt. Existing assertions remain intact. One unchanged deliberately recursive
law hits the documented NoLLVM host-stack limitation; the full LLVM run
described below executes it successfully. Focused controls and exact source
restoration are preserved in `build/bench/task047-retained-query-diagnosis/` and
`build/bench/task047-retained-query-diagnosis-continuation/`.

The two test fixtures are adopted in the 1,168-input manifest
`c6a7ced0c81fcf2abb9e2edd3fe2417798d3223658f2918b1bb866753814d390`. Forced LLVM
run `run-9b1ff45843040617` passes all 2,504 executed native laws, with zero
skips, failures, leaks or logged errors; its binary is `d67e04f1…`. All 48 smoke
and 37 harness checks pass. The guest phase stops at a canonical constructor
regression. A separate complete guest inventory reports 1,583 passes and five
failures: four local/imported constructor cases in sync/JSPI and a
persisted-owner fixture whose tiny factory no longer selects a query. Full
failed-run evidence and the complete inventory remain in
`build/bench/task047-canonical-constructor-guest-failure/` and
`build/bench/task047-c6a7-guest-inventory/`.

The constructor control passes all eight affected guest laws when only the new
named admission is disabled. Call-site instrumentation identifies optional
closure inference while serializing a captured generic constructor. Ordinary
callable templates already own its canonical source-arrow/payload adapter. The
repaired admission reads the captured value graph and declines constructors,
including those nested in aggregates or closures. It allocates nothing and is
bounded at 65,536 visits and depth 128; exhaustion keeps the ordinary path. It
changes no evaluator diagnostic, source scheme or semantic authority. A new
native law checks direct and nested captures through fresh/retained/checkpoint
allocation failures, replay and immutable Core. It and twelve targeted guest
groups pass, including the positive zero-allocation folds. The dependency-loaded
semantic-owner fixture keeps its original gate, byte, diagnostic and retry
assertions with a synthetic factory above the source-inlining budget. Controls
remain in `build/bench/task047-constructor-capture-guard-check/` and
`build/bench/task047-semantic-guest-fixture-check/`.

The repaired 1,168-input manifest is
`5479c48b90446845458b799647bd6e99fc283742787f25a6a05c812723b1c104`. Both
analyzers pass all 512 source files plus the fixture at zero findings. The new
LLVM release `0d9ae259…` passes all 1,588 guest/client checks in the complete
preflight. Forced full LLVM run `run-b7fcceb7d5946a70` passes all 2,505 native
laws, with zero skips, failures, leaks or logged errors; its binary is
`7d9f5921…`. Packaging passes, but the full guest phase stops on an uncaught
Deno client shutdown race. The child's exit is already known to Deno while the
client's status observer is pending, so the grace timer's kill throws
`TypeError`. The client now recognizes that specific already-terminated error.
A deterministic real-process control fails before the repair and passes after
it; all 89 focused transport, client and body-cache checks pass with the gate's
restricted environment permissions. The first broad-permission diagnostic had
enabled disk persistence and invalidated fresh-work assertions; it remains
preserved and supplies no qualification.

The new 1,168-input manifest is
`82150a7d7fcacc286671ecb8f0112bd9c3396994b1c4f9fda62006218f4790d9`.
Only the Deno client and its transport regression change from the previous
manifest; native compiler sources stay exact. Both analyzers pass again. All
1,589 LLVM guest/client checks pass in the complete preflight. Forced full run
`run-45256b95642aa16` then passes all 2,505 executed native laws, 1,589
guest/client checks and 37 harness checks. Native skips, failures, leaks and
logged errors are all zero. The compiler remains `0d9ae259…`; its immutable
release and source pins are in `build/bench/task047-owned-static-release/`.
The separate nested-constructor runtime control also passes all 2,000 sync/JSPI
calls; baseline and guarded guests are byte-identical. Evidence remains in
`build/bench/task047-client-shutdown-full-failure/`,
`build/bench/task047-constructor-capture-execution.json` and
`build/bench/task047-client-shutdown-preflight/`. Full correctness passes; the
final compiler CPU and runtime measurements remain unqualified.

The preselected seven-pair CPU identity control passes with paired median
0.985210. The fifteen-pair comparison against qualified `1b05518e…` fails:
paired median 1.059034 exceeds the unchanged 1.05 limit. Separate baseline and
candidate medians are 8,602.6 and 8,547.3 ms, but those do not replace the
paired criterion. The failed distributions and preselection are preserved in
`build/bench/task047-cpu-guard-failure/`. Final retained parity, width/adapter
and instruction qualification did not run after that failure.

A separate diagnostic Callgrind pair preserves the frozen inputs and each
compiler's recorded guest. Whole-process simulated instructions are
25,233,755,782 → 25,252,341,031 (ratio 1.000737); build-only requested bytes are
1,691,218,432 → 1,693,315,891 (ratio 1.001240). These measurements include
different scopes and do not waive the CPU guard. The operation-row resolver
accounts for about 8.6% of self instructions in both binaries, motivating the
already planned P1 prototype. Its three native/OOM controls and actual storage
size measurement pass. Reports are
in `build/bench/task047-cpu-guard-failure-native-instructions/`. Compiler-generated
symbol IDs differ between releases; the separate function-family report groups
those IDs for cost attribution and grants no semantic correspondence.

The P1 LLVM screen against the same current 047 source passes. Simulated
instructions fall from 25,252,371,070 to 24,267,174,854 (ratio 0.960986), while
requested build bytes rise from 1,693,315,891 to 1,693,364,323 (ratio 1.000029).
Both emit exactly the current game Wasm and preserve all eleven selected work
counters. Seven CPU identity pairs pass at median 0.946317; fifteen comparison
pairs pass at median 0.914069, with wide individual spreads. These are the
preselected P1 screen, not final combined qualification. Evidence remains in
`build/bench/p1-refreshed-047-native-instructions/` and
`build/bench/p1-refreshed-047-cpu-screen.json`.

The initial cache was adopted into the working tree for full qualification. It adds
128 bytes to `types.Store` (800 → 928), with no row or effect-store layout
change. The new frozen manifest is
`78ffcee39d5797770df6f7959611ca62f8286342233fa510f3a376325a380c1f`.
Both analyzers, all 1,589 guests and the forced complete LLVM gate with the new
native law are required. The subsequent final CPU comparison against qualified
`1b05518e…` uses seven identity and 31 comparison pairs, fixed before any P1 CPU
observation, at the unchanged 1.05 limit. Previous releases and the failed
fifteen-pair 047 campaign remain unchanged. Final parity, runtime and instruction
qualification remain open.

That first P1 LLVM guest preflight passes 1,588 of 1,589 checks. The sole failure
is `chain_generic N=64`: requested bytes 8,506,471 exceed its unchanged 8,505,963
budget by 508 bytes. The full native gate and final CPU/runtime campaigns do
not run. The binary, source and complete logs remain in
`build/bench/task047-p1-preflight-failure/`; the budget is unchanged.

The working tree now uses eight compact entries and the existing shared
physical-epoch guard. Both updates to that shared epoch invalidate the closed
generation first, so an unsynchronized physical edit declines and a refreshed
generation cannot revive an old entry. Saturation still disables certificates.
Actual `Store` size is 800 → 864 bytes, with row and effect-store layouts
unchanged. All three focused native/OOM controls pass again. Matched development
builds preserve bytes and selected work counters at N=32/64/128 and reduce N=64
requested bytes by 4,832. Development and LLVM release allocator totals differ;
that diagnostic does not qualify the release budget. The new LLVM guest
preflight passes 1,588 checks and fails the same budget: 8,507,451 requested
bytes exceed 8,505,963 by 1,488. Matched LLVM controls reproduce this result;
allocation attribution remains open. Its instruction screen and complete gate
have not run. The frozen source manifest
is `a8c468ceaabeae2e503fb38c2e213da0a37f6624ed4e2a6b3fdae1b9ac8cf38b`.
The complete failure evidence remains in
`build/bench/task047-p1-packed-preflight-failure/`.

Exact allocation traces now account for all requested bytes and all 27,302
allocations in each of the three LLVM controls, with identical Wasm. The first
cache adds 12,240 bytes; the smaller one adds 13,220. The extra requests come
from the `CallSummaries` region pool and two checker Store copies. The smaller
pool block can grow in place from 49,464 to 52,304 bytes, which also increases
its next block. A pinned model of Arena/SMP/page growth reproduces every observed
allocation and successful growth in all three controls. It predicts 3,060 extra
bytes for four entries; the separate LLVM control below confirms that prediction.
Raw evidence and the model are in `build/bench/p1-budget-allocator-trace-v3/`.

The four-entry successor is now in the working tree for qualification. It changes
only the fixed cache capacity; all existing proof guards and ordinary miss
fallbacks remain. Three native/OOM controls pass again. Actual Store size is
800 → 832 in Safe and 664 → 696 in Fast/LLVM. The old 800-byte baseline was a
Safe measurement; the absolute sizes differ by build mode. Row and effect-store
layouts remain unchanged within each mode. Its source manifest is
`bb0c82137ef2bdf87710ea1ffed627a8f33c52f2d095c2b051730bc3834cffab`.
Both analyzers and all 1,589 LLVM guests pass. The separate twelve-observation
LLVM control at N=32/64/128 preserves bytes and selected work in all four hosts.
N=64 requests 8,497,291 bytes, exactly 3,060 above the control and 8,672 below
the unchanged budget. This confirms the model's prediction. The compiler is
`ed48b8c1…`; its guest preflight and immutable binary are in
`build/bench/task047-p1-four-preflight/` and
`build/bench/task047-p1-four-preflight-release/`. The preselected instruction
payoff screen also passes: whole-process simulated instructions fall from
25,252,368,116 to 24,299,854,307 (ratio 0.962280), while requested build bytes
change from 1,693,315,891 to 1,693,327,999 (ratio 1.00000715). Both compilers
produce identical game Wasm and eleven selected work counters; allocation count
stays 4,967,704. The exact source pins pass before and after. Reanalysis of
those raw profiles accounts for every self instruction: `closedNodeHeight`
saves 590,056,856 and `resolveOperationRow` saves 346,928,736. The grouped
function report is cost attribution, not a semantic identity proof. Evidence
remains in `build/bench/p1-four-entry-native-instructions/`. This one-pair
instruction screen does not establish the compiler CPU guard. The complete forced LLVM
gate `run-d9cd966e277337fc` passes **2,506 executed native laws, 1,589
guest/client checks and 37 harness checks**, with zero native skips, failures,
leaks or logged errors. Wall time is 2,387.497 s. Release `ed48b8c1…`, native
suite `dd3c59f8…`, the exact manifest and report pins are preserved in
`build/bench/task047-p1-four-owned-static-release/`.

Guest files use concurrency one. The first four-file full run passed all native
laws but stopped on the LSP completion's unchanged 250 ms wall deadline. All
eight LSP tests then pass in isolation, all 1,589 guests pass with one file at a
time, and the new complete forced gate above passes. No production deadline or
test assertion changed. The failed run is preserved in
`build/bench/task047-p1-four-lsp-deadline-full-failure/`; the scheduling diagnosis
is in `build/bench/task047-p1-four-lsp-deadline-diagnosis/`.

The next 74-sample control, with fourteen independent fresh-edited builds, fails
with sixteen within-binary game parity errors: four edits differ from fresh
builds, and their reverts differ from the original fresh build, for both the
pre-P1 and four-entry compilers. Every phase still matches between those two
compilers. These failures are preserved in
`build/bench/task047-p1-four-retained-parity-failure/`; they are not covered by
the declared cross-compiler output differences. The seven-phase LLVM probe
confirms the last-qualified compiler passes and the candidate fails. A matched
Safe/NoLLVM control disabling only evaluated named calls restores exact
last-qualified bytes in all seven phases. Section inspection finds an extra
24 bytes of static data after an edit/revert; serializer provenance is under
investigation. These are causal diagnostics in
`build/bench/task047-retained-byte-diagnosis/`, not an accepted feature removal.
Final compiler CPU, parity and runtime qualification have not run.

The read-only serializer/replay trace then identifies the exact correspondence:
the old nominal value 29166 maps to current value 28400, its layout maps to 2488,
and replay copies its record and wrapper at addresses 56176 and 56192. A rebuilt
caller serializes that same current value/layout again at 56200 and 56216.
Seeding the already-proved cache entry in a private control removes the entire
24-byte difference and preserves all seven fresh/edit/revert hashes. This
diagnostic does not cover missing layout proofs or conflicting replay aliases.

The implemented repair instead makes an executable job fresh when it directly
materializes a new static value outside a constant job. Graph equality alone
does not recreate the serializer's sharing table. Constant jobs keep their
existing path: replay serializes the current admitted graph before the caller
continues. Scalar captures and calls that never materialize static data keep
executable reuse; evaluated-call lowering and the zero-allocation folds remain
enabled. No cache authority or alias comparison is widened.

A public two-module Array repro adds twelve bytes after edit/revert before the
repair. The repair restores exact fresh bytes and still reuses unaffected
queries. Two native laws cover fresh/edit/revert bytes, positive scalar
evaluated-call reuse, candidate discard and every allocation-failure point
without changing retained source owners. Three guest checks cover both tiers,
capture edits and execution, including the unchanged zero-adapter-allocation
fold requirement. All pass in the focused Safe/NoLLVM run. An analyzer
preflight caught two deprecated test-fixture allocator calls; those aliases
were replaced with the supported API and both full analyzers now report zero.
The new complete LLVM gate on manifest `50ad681b…` finishes with 2,507 native
passes and one failure in the existing law requiring executable reuse of static
captured value graphs. There are zero skips, leaks or logged errors. Both builds
and 37 harness checks pass; the gate stops before guests. Total wall time is
98.12 minutes, including 47.50-minute native compilation overlapping the
36.46-minute release build, then 47.92-minute native execution. This fallback
is unqualified despite the focused controls. Preserve the law and review a
more precise repair. The owner requested a pause for scope/tool-efficiency
review; all three queued follow-ups are canceled. The current failure is saved
in `build/bench/task047-static-sharing-v2-native-failure/`. The planned
162-sample parity screen, seven-identity/31-comparison CPU guard and final
runtime qualification have not started. Evidence remains under
`build/bench/task047-retained-byte-diagnosis/` and
`build/bench/task047-static-materialization-focused/`.

After the owner review, development always uses Zig's native backend without
LLVM; final release builds and qualification use LLVM. The precise successor
restores copied data's serialization bindings only after exact current value
graphs and imported physical layouts match. Cache hits, conflicting aliases,
missing proofs and mixed fresh aggregate children decline before data is
copied. A serializer-derived capture-free closure first undergoes ordinary
current specialization; its complete resulting graph must match before its
binding is restored. This publishes no solved principal receipt from an erased
field. The existing positive closure law now passes, extended through a second
retained edit and complete allocation-failure/source-immutability sweeps.

All eleven affected native laws pass, as do the extra caller-ordering/OOM and
alias-edit cases, all three both-tier guests and both full analyzers. The seven
game population/no-op/trivia/revert/literal-edit/revert/fresh-literal phases
restore exact original fresh bytes. The repaired Safe/noLLVM compiler build
takes 49.22 s; an unchanged rebuild takes 0.43 s. These are development checks,
not final LLVM or CPU qualification. Frozen evidence is in
`build/bench/task047-static-sharing-precise-development/` and
`build/bench/task047-static-sharing-precise-preflight/`.

The Window call-site diagnostic now passes all 21 operation/count cases. Its
separate instrumented copy agrees with both an independent raw allocator counter
and the original guest's allocation telemetry. At 4,096 inputs the physical
sites total 40,954 requests. Source admission traces show that `Windows.next`
(cost 55, depth 1) and its inner `Range.next` (cost 19, depth 2) are already
inlined in the fold. Both diagnostic guests are byte-identical to the
provisional LLVM guest. Reports remain in
`build/bench/task047-window-sites-prequalification/`,
`build/bench/task047-window-inline-diagnostic/` and
`build/bench/task047-window-prequalification-summary.json`.

The ownership-pass diagnostic also preserves exact guest bytes. Its 2,614 trace
lines show that the children-mode result is rejected by the existing cost guard:
the fold's outer loop removes three allocation sites but adds 16 root
publications, and the inner loop removes two but adds 10. Direct nested loops
remove two outer sites with the same publication increase. The compiler keeps
its conservative fallback. Existing `pruneFieldRoots` already removes
publications covered by zero, static or initial function-owned values; further
alias or control-flow precision needs its own proof. Both diagnostic source
files were restored exactly. See `build/bench/task047-window-sroa-diagnostic/`
and `build/bench/task047-window-sroa-summary.json`. These are allocation and
admission observations; final qualification and the remaining optimization are
still required.

An optional same-Safe-host retained-cost diagnostic was stopped after seven
partial observations because each host build was too slow for a useful proxy.
Its `incomplete.json` is preserved in
`build/bench/task047-owned-static-retained-dev-screen/`; it supplies no CPU
guard or speedup claim. The final LLVM compiler-cost and retained-output
campaign remains required.


### Window cost counterfactual, 21 October 2026

The private cost-guard counterfactual passes all 88 optimized-tier semantic and
allocation rows. Its LLVM baseline is the correctness-qualified `ed48b8c1…`;
the diagnostic host uses Safe/NoLLVM and changes no ownership admission. Main
sources stay unchanged and both temporary prototype files are restored exactly.
The first attempt failed to compile its instrumentation and produced no runtime
measurements; the corrected v2 data below remains a diagnostic, not an adopted
optimization or whole-task qualification.

At 4,096 inputs, all three Window forms reduce physical allocation requests from
40,954 to 32,764 and rounded allocation traffic from 2,227,872 to 1,834,752 bytes
per call. Committed memory stays at 128 KiB. Retains increase by 73,702 and
releases by 65,512 per call; fewer allocations alone do not settle the tradeoff.

| Window form | Baseline guest CPU, median ms | Counterfactual, median ms | Ratio |
| --- | ---: | ---: | ---: |
| Fold of window contents | 6.49800 | 7.17850 | 1.105 |
| Nested loops | 5.75325 | 6.62050 | 1.151 |
| Fold of window lengths | 5.02500 | 6.36525 | 1.267 |

These are ratios of medians from 21 alternating guest CPU pairs per form, four
calls per sample after eight warmups. Individual samples have wide outliers;
this is a rejection screen, not a significance or native compiler CPU claim.
The existing cost guard remains unchanged.

Exact syntactic telemetry leaves outer/inner loop publication counts at 23/16
after the established root-borrow pass, versus 7/6 before scalarization. Even
with zero directly counted final allocation sites, those counts do not clear
the unchanged rule. Intervening vector/reduction passes mean equal loop counts
alone do not prove correspondence. No late lookahead or ownership relaxation is
justified by this data. Root-borrow decline attribution and any narrower lifetime
proof remain unimplemented. Raw source/binary/Wasm pins, 100-call allocation
observations, all CPU samples and per-pass counts remain in
`build/bench/task047-p1-four-window-preflight-counterfactual-v2/`.
