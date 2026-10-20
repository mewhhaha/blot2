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

A direct `let #Some (value, rest) = cursor.next` now uses the existing exact
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
`d9e1812fa29ec43355b578dc9ea6c1d728ab021b340e806583c3e5f57021c691`. Main remains
unchanged; Window and broader generic state are still open.
