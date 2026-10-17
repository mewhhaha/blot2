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
