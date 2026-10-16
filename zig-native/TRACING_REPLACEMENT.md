# Tracing replacement work

The current production candidate uses counted edges, leases and trial deletion;
incomplete ownership diagnoses instead of selecting a tracer. The final common
release/runtime performance gate remains open. Dated records below retain
earlier implementations, rejected candidates and their original limits.

The 15 October focused runtime screen rebuilds the pinned historical tracing
compiler `b8023659` against the same fixture and frozen std. Its Wasm exactly
matches the preserved artifact. Current cycle CPU is 13.30/13.19 ms versus
5.47/5.70 ms in sync/JSPI, while warmed memory is 128 KiB versus 16,320 KiB.
Scalar, Array and request controls also retain CPU gaps. Raw 25-pair rounds,
compiler/source/std/Wasm pins and mode checks are in
`build/bench/finish-program-20261014/ownership-vs-tracing/tracing-screen/`. This
is development guest evidence; task 035 and release qualification stay open. An
isolated 256 KiB collection cadence increased CPU 2.2–2.4% and doubled warmed
memory. It was rejected; `cycle-cadence/` retains its exact sources.

The integrated discovery/subtraction fusion removes one member edge sweep and
seven runtime source lines. Against the frozen current ownership compiler, 25
alternating pairs improve cycle CPU 2.41% sync / 3.54% JSPI with unchanged 128
KiB warmed memory; cost Wasm shrinks 12,156 to 11,966 bytes. Both modes remain
`[2,2,0]`. Exact graph counters, duplicate/self/back/cross edges, lease and
alias roots, underflow traps and resource retirement remain qualified. Nine root
native laws and 23 guest laws pass; the integrated compiler emits byte-identical
cost Wasm to the measured candidate. Pins and raw rounds are in
`build/bench/finish-program-20261014/cycle-edge-fusion/` and its referenced
immutable private evidence. This is a small runtime improvement; the tracing
comparison and final full gate remain open.

Task 035 is in progress. Tracing remains for uncovered and partial routes; this
record qualifies a development checkpoint, not final removal. The incoming
implementation is qualified `dd6a66a`, with source tree
`a70662ea5a3efa27e8ce3c4c03ad2b7484bb2ae3`.

Checked indirect-call result annotations preserve scalar/reference facts before
machine lowering, using the existing 32-bit ownership operand. They emit no
instructions and add no Emitter/header fields. Source callees retire their own
owners; scalar results acquire no caller owner. Functions that cannot acquire or
publish owners borrow caller roots and omit their frame and empty loop scopes.
Allocations, allocating helpers, owning/unknown results, imports,
force/publication scopes, entry and startup boundaries remain conservative.
Optimizer interpretation v 4 preserves the existing signatures, imported names,
global facts, table references, roles, roots and owner-table geometry. Malformed
or orphan indirect annotations reject; a portable forged scalar fact plus an
omitted frame cannot override freshly emitted reference facts.

`root_enabled` retains bit 0 for journal enablement and adds bit 1 for complete
journal admission. Exact whole-module admission sets both. Raw helper exports
remain partial, and unadmitted graphs have the proof bit cleared even when an
input flag claims it. Both global initialization and immutable flag
serialization use this normalized mode; mutable guards remain symbolic. Complete
reset drains trial deletion and preserves the allocator/free lists and
persistent owners, without tracing an already retired invocation. Partial
fixture reset retains its previous tracing contract.

The isolated Safe/noLLVM checkpoint passes 23 focused native/OOM/portable laws,
58 executed ownership, memo, cycle, suspension and List row-boundary laws,
formatting, and 344 analyzer files with zero findings. No standalone full gate
or LLVM candidate build was run.

A provisional guest-Wasm screen compares qualified incoming Fast compiler
`build/bench/joint-002-034/blotc-candidate` with the Safe/noLLVM development
compiler SHA-256
`cd314f11eefd67b01481bf8c002aa59afb71deeb3ff509be3cd56086d1ff0bbf`. This is not
qualified native compiler CPU evidence. CPU 6 has 25 alternating pairs after
warm-up, with equal values and flat memory per workload.

| Guest batch               | Incoming CPU ms | Checkpoint CPU ms |  Change |
| ------------------------- | --------------: | ----------------: | ------: |
| Sync scalar, 10000 calls  |           5.082 |             3.539 | −30.36% |
| Sync Arrays, 2000 calls   |           4.777 |             4.493 |  −5.95% |
| Sync requests, 2000 calls |           8.310 |             7.892 |  −5.03% |
| Sync cycles, 20000 cycles |          35.322 |            36.536 |  +3.44% |
| JSPI scalar, 10000 calls  |          20.779 |            19.009 |  −8.52% |
| JSPI Arrays, 2000 calls   |           7.988 |             7.669 |  −3.99% |
| JSPI requests, 2000 calls |          11.491 |            10.991 |  −4.35% |
| JSPI cycles, 20000 cycles |          35.399 |            36.547 |  +3.24% |

Load averages span 0.87–1.00. The mixed program's Wasm decreases from 12533 to
12472 bytes. Programs, harnesses, logs and raw rounds remain in the isolated
`build/bench/tracing/` directory; final release comparisons and task 035's
relative tracing CPU/memory gates remain outstanding.

With the std directory configured, all 13 public examples compile. Seven use
complete journals. Monads/prelude still report unproven bodies and tags reports
initializer fallback; records/requests currently have counted rootless mode and
scalar has no arena. Those gaps require exact coverage or required diagnostics
before production tracing can disappear. The final memory gate includes the
nested 90-row workload with 8, 40 and 200 discarded 8192-word Arrays per inner
loop, preserving outer rows within one invocation; no memory or CPU budget is
weakened. The strong memo, suspension and cycle laws in
[SHARED_OWNERSHIP.md](SHARED_OWNERSHIP.md) remain mandatory.

## Follow-up subtraction

Resolver values are scalar zero representations in both serialization and
runtime resolver dispatch. Compile-time closure captures likewise store zero;
their semantic evidence remains in the code key. A simple local match arm that
reconstructs the same immutable variant and unchanged payload now shares the
original cell. Its existing checked descriptor carries the erased payload's
exact role, including when another nominal parameter changes. This is selected
in body preparation, without an Emitter field or ownership guess.

Whole-module root admission now remains distinct from frame demand. Closed
allocation-free graphs have complete admission and no empty function frames;
startup still receives its conservative journal boundary. All 13 public examples
compile: 12 have complete admission and scalar has no arena. Raw helper exports
and unknown/partial routes retain their conservative contract.

Checked scalar fields in mixed objects keep their original stores. Only a known
in-bounds word from an exact mask or checked scalar annotation qualifies;
reference and unknown/dynamic offsets retain typed publication. The write list
shrinks without new metadata. Complete journals skip the legacy collecting-loop
packet and activation-floor scan; scope closure retains independent trial
deletion safe points.

The follow-up Safe/noLLVM compiler SHA-256 is
`e64395b22d216f53a9ba2b154b6de355ea6f4a50bd32ecb29298062af789812c`. Its
mixed-program Wasm is 12220 bytes, SHA-256
`d022c2f105c259eaf214dcf102301ee180812f32131e2741f86335c32d7eec90`. Focused
checks pass 23 native/OOM/portable laws, 32 executed laws and 344 analyzer files
with zero findings. The nested 90-row law runs 8, 40 and 200 discarded 8192-word
Arrays per inner loop: outer rows remain correct, at least 90 × count Arrays
retire before invocation exit, committed memory stays within one 64 KiB page of
warmed 8, and roots/leases return to zero. This executes with the normalized
complete guard disabling the legacy collection route.

A three-way guest-Wasm screen uses CPU 6, load averages 0.43–0.51, 25
alternating rounds with five discarded rounds, equal values and flat warmed
memory. Incoming is qualified
`c0959e9a375b2ba8d2a2263278417fb917b434e733c9a13f80af1d372e80b060`; the older
host-tracing executable is qualified
`b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`. The
candidate uses development preparation; these are guest-code measurements, not
final native compiler CPU qualification.

| Guest batch               | Tracing CPU ms | Incoming CPU ms | Follow-up CPU ms |
| ------------------------- | -------------: | --------------: | ---------------: |
| Sync scalar, 10000 calls  |          2.601 |           4.956 |            3.637 |
| Sync Arrays, 2000 calls   |          3.772 |           4.534 |            4.192 |
| Sync requests, 2000 calls |          5.617 |           8.371 |            7.731 |
| Sync cycles, 20000 cycles |          6.115 |          36.245 |           34.657 |
| JSPI scalar, 10000 calls  |         17.040 |          19.483 |           19.046 |
| JSPI Arrays, 2000 calls   |          7.170 |           8.127 |            7.728 |
| JSPI requests, 2000 calls |          8.777 |          13.427 |           10.989 |
| JSPI cycles, 20000 cycles |          6.157 |          36.283 |           34.721 |

The tracing CPU gate fails, especially the approximately 5.65× cycle cost and
39.8% scalar sync cost. Task 035 remains open. Raw rounds, exact compiler/Wasm
pins and harnesses are in `build/bench/tracing/coverage-cost/`; historical
checkpoint rounds remain separate. Remaining work includes pruning normalized
immutable branches before encoding, complete wide-layout/scope coverage,
required diagnostics for genuinely unsupported ownership contracts, physical
tracing removal and final release CPU/compiler/memory qualification.

## Integrated qualified milestone (12 October 2026)

Implementation `46bf8b9`, LLVM Fast release
`47021c966f75fbb6063b9de52d476fe944a8aa16dc6bc47aeae66cfbf4dd9095`, passes the
full native suite, 914 guest/client laws, eight unchanged budgets and the
348-file zero-findings analyzer. Scalar-result annotation, complete/rootless
admission, known scalar stores and unchanged-variant reuse are included.

Frame demand is a distinct portable/retained optimization input. An unrelated
new owning producer changes it while complete admission remains true; an
unchanged reference-returning function must acquire its frame. Fresh, retained
and portable bytes agree. Removing only the Matcher comparison reproduces a byte
mismatch. `needs_roots` fits existing Capture/Snapshot padding; no Emitter field
is added. Combined interpretation v 6 retains associated type and checked
indirect-result meaning. Invalid no-roots/needs-roots shapes reject.

The nested 90-row memory law passes at 8/40/200 discarded 8192-word Arrays per
inner loop, preserving live outer rows and bounding memory without legacy
tracing for the complete graph. Public monads/prelude remove one checked
allocation-role run each through immutable variant reuse. Exact combined
measurements and remaining CPU/coverage/removal gates are in
[FRONTEND_OWNERSHIP_QUALIFICATION](FRONTEND_OWNERSHIP_QUALIFICATION.md). Task
035 remains active; later flag, slot and journal experiments are separate.

## Symbolic flag lowering

Complete immutable admission now lowers private ownership guards at final Wasm
encoding, after every optimized body has passed its field proof. Retained and
portable bodies keep symbolic globals: adding an unproven dynamic allocation can
change module admission without changing an unchanged body's root-frame demand.
A native law exercises that change through both reuse routes and requires fresh
byte equality.

Selected controls become blocks with the original result type and branch depth.
Raw, partial and mutable contracts preserve their tracer helpers. A complete
module rejects any surviving direct or symbolic table reference to a tracer; its
unused tracer bodies trap. This removes active tracing code from admitted Wasm,
while retained compiler artifacts and partial contracts still contain the legacy
implementation. Physical removal and complete source coverage remain open.

The prototype passes 22 focused native laws, an additional late-admission replay
law, 32 executed guest laws and 345 analyzer files with zero findings. The prior
three-way CPU failure remains the measured baseline. A CPU 6 sample profile of
100 invocations of the same 20000-cycle workload attributes 15.3% to journal
pop, 8.5% to reserve and 7.9% to close, versus 4.6% to trial collection. The
next measured subtraction targets unused scalar result slots; sampling
attribution is not a performance qualification.

## Compact frame markers

A frame now reserves one 8-byte marker instead of a marker and a separate result
slot. Before retiring the callee suffix, close transfers or retains the returned
value into that marker. Its existing frame link names the caller. Close keeps an
owning marker and pops an empty one; borrowed results retain exactly as before.
This does not assume a borrowed result has another root. A 4096-byte journal
payload holds 511 records, with the first record at byte 8. The 32-byte object
header, typed masks and public ABI remain unchanged.

Journal pop and lease release also validate a live header once per ownership
transaction, then detach, decrement and drain without repeating that validation.
Public reference operations retain their checks. No Emitter or map fields grow.
The OOM page-boundary law derives capacity from the runtime, fails before a
marker can publish, and requires a no-growth retry after empty-suffix
retirement. Its guard now normalizes the page pointer before combining it with a
boolean. A separate executed law returns an owner across three retired journal
pages.

A profiling-only copy adds scalar helper counters without changing function
ordinals or heap layout. After subtracting a zero-iteration invocation, each
strong cycle still opens/closes 14 frames and allocates/destroys 16 objects.
Reservations and pops fall from 45 to 31. Existing dynamic RC counters remain 22
retains and 34 releases per cycle; helper entry counts include additional
static/null no-ops. Trial deletion runs 313 times across 20000 cycles.

The measured Safe/noLLVM executable is
`90bf0eb4f4fe1dbd3679c98f6965b690872940d7d2a831ea98c3d25f1bfce77b`; its
11556-byte mixed Wasm is
`4557db180c65d46ced3b8ef1ce4cc50cc836254b216ed61f3c5cdd8a6d0adfe6`. Focused
qualification passes 18 native/OOM/replay laws, 60 executed laws with all eight
unchanged allocation budgets, and the additional page-return law. The prior
transaction-only screen passed 281 native/OOM laws in five minutes; subsequent
filters were narrowed to keep iteration short.

CPU 6 qualification uses 25 alternating three-way rounds, five discarded rounds,
equal values, flat warmed memory and load averages 0.69–0.96. Flags is the
frozen flag-only prototype; tracing is the same historical qualified executable
above. These are guest-Wasm measurements prepared by a development compiler, not
final release compiler CPU qualification.

| Guest batch               | Tracing CPU ms | Flags CPU ms | Compact CPU ms |
| ------------------------- | -------------: | -----------: | -------------: |
| Sync scalar, 10000 calls  |          2.587 |        3.437 |          3.154 |
| Sync Arrays, 2000 calls   |          3.641 |        4.297 |          4.149 |
| Sync requests, 2000 calls |          5.659 |        7.569 |          7.370 |
| Sync cycles, 20000 cycles |          5.843 |       33.720 |         28.972 |
| JSPI scalar, 10000 calls  |         17.237 |       18.417 |         18.610 |
| JSPI Arrays, 2000 calls   |          7.064 |        7.745 |          7.552 |
| JSPI requests, 2000 calls |          8.704 |       12.903 |         10.510 |
| JSPI cycles, 20000 cycles |          5.919 |       33.735 |         28.956 |

The structural subtraction improves cycle CPU about 14.1% versus flag lowering,
but the tracing CPU gate still fails at approximately 4.9× for cycles and 30.2%
excess sync request CPU. Task 035 remains open. Historical scalar-slot and
borrowed-ancestor experiments remain separate under `build/bench/tracing/`; the
scalar-slot regression was rejected, and borrowed-result ownership omission is
not in this candidate. Physical tracing removal, wide ownership coverage and
final compiler/runtime CPU qualification remain required.

## Integrated flag and marker milestone

Implementation `2689ad5`, tree `92e09418…51fb6a`, passes the full native suite,
925 guest/client laws, eight unchanged budgets and 349 analyzer files/zero.
Standard Zig 0.17.0 LLVM/Fast release SHA256 `9ea894d4…8b21` is immutable under
`build/bench/joint-024-035-040/`. Its exact pins and mixed public compilation
costs are recorded with [040](ROW_FUSION.md). Compact-marker CPU measurements
above remain a separately pinned isolated comparison; they do not close the CPU
gate or qualify physical tracing removal. Partial/raw contracts continue to
retain ordinary helpers. A later null-environment closure descriptor slice is
separately frozen, not in this milestone. Task 035 remains open.

## Capture-free descriptors

A closure with no environment now uses the existing immutable static descriptor
and relocation path. Captured closures, demand cells and host invocation
identities retain their dynamic owners. This adds five production lines and no
fields, maps or header changes. The native law checks unchanged Core,
fresh/retained/checkpoint/replay bytes and every fresh/retained allocation
failure. Qualification passes 16 native laws, 56 executed laws, eight unchanged
allocation budgets and 345 analyzer files with zero findings.

The final Safe/noLLVM executable is
`511a78439d799f8debacf1517cf67587b2e73a8911be930214a9d2c1889133ad`. The measured
executable before the test-only addition is
`7384cbcddd826dfdb502537ddc1b4f9975583b2d44175eb6622572a6c6ef5a5b`. Both produce
the same 11409-byte mixed Wasm,
`6b299dbb2d9ffa3cc9c01fcf531f2960c271591724606fe46c62efcbc381e3da`.

CPU 6 qualification uses 25 alternating three-way rounds, five discarded rounds,
equal values, flat warmed memory and load averages 1.45–1.61. These are Wasm
guest measurements, not release compiler qualification.

| Guest batch               | Tracing CPU ms | Compact CPU ms | Static CPU ms |
| ------------------------- | -------------: | -------------: | ------------: |
| Sync scalar, 10000 calls  |          2.669 |          3.217 |         3.183 |
| Sync Arrays, 2000 calls   |          3.834 |          4.356 |         4.306 |
| Sync requests, 2000 calls |          5.676 |          7.333 |         7.140 |
| Sync cycles, 20000 cycles |          6.066 |         31.850 |        24.565 |
| JSPI scalar, 10000 calls  |         16.834 |         18.630 |        17.830 |
| JSPI Arrays, 2000 calls   |          7.352 |          7.704 |         7.640 |
| JSPI requests, 2000 calls |          8.992 |         10.623 |        10.542 |
| JSPI cycles, 20000 cycles |          5.816 |         31.856 |        24.586 |

Each strong cycle now allocates/destroys 12 objects instead of 16. Reservations
and pops fall from 31 to 27; opens/closes remain 14. Actual dynamic retains
remain 22 and releases fall from 34 to 30. Trial deletion runs 233 times per
20000 cycles. Cycle CPU falls about 22.8%, but still costs 4.05–4.23 times
tracing; sync request CPU remains 25.8% above tracing. Task 035 remains open.

## Direct result forwarding

A thin private wrapper can use the marker already published by its direct source
callee. Admission permits only argument loads/constants before one nonentry
source call whose checked result is a reference. The wrapper then returns that
exact result, optionally with the generated scalar-global guard that discards it
and returns zero. Helpers, indirect/import calls, mutations, independent owners
and scope directives decline. The callee has its own frame, or forwards through
the same proof to such a frame. It publishes at most one result marker in the
wrapper's caller. A dynamic discard explicitly pops that marker; static/zero
results have no marker. No ancestor-root assumption or borrowed-result ownership
omission is used. Traps before the call acquire no wrapper owners; suspension
keeps the original caller and callee owners.

The optimizer interpretation advances to v 8 with `forwarded-roots`. Native laws
check the rejection cases, unchanged inputs, every allocation failure,
retained/restarted byte equality and a changed callee entry fact that restores
the independent frame. The initial focused batch passes 18 native laws; the
final expanded forwarding/OOM/restart law passes with 16 tests. Execution passes
45 ownership/cycle/JSPI/callable laws and 51 request laws, all eight unchanged
allocation budgets, and 349 analyzer files with zero findings.

CPU 6 screening uses 25 alternating pairs, five discarded rounds, checked
values, flat warmed memory and load averages 1.59–1.78. Against the frozen
static-descriptor candidate, sync cycles fall from 24.925 to 22.430 ms and JSPI
cycles from 24.976 to 22.426 ms (10.0–10.2%). Other controls stay within about
1%. Each cycle still allocates/destroys 12 objects; opens/closes fall from 14 to
10, reservations/pops from 27 to 23, actual dynamic retains from 22 to 18 and
releases from 30 to 26. These are guest CPU screens, not final task 035
acceptance.

A requested single LLVM/Fast source pairing against qualified revision 2689 ad 5
measures fresh preparation at 6.53 versus 6.69 ms and retained edit at 3.07
versus 3.13 ms after two warm pairs. One measured pair cannot establish a CPU
result. The release compiler produces the same mixed Wasm as the larger guest
screen. Journal drain batching was separately rejected: it added 57 Wasm bytes,
improved cycles only 1.6%, and regressed sync scalar CPU 3.4%. Its raw evidence
stays separate. Physical tracing removal, wide ownership coverage and the
material remaining cycle/host CPU gate keep task 035 open.

## Paired guest State frames

A guest State installation now owns one 20-byte frame: read token, checked
value, strong outer link, guest-only kind tag 4, and write token. It replaces a
4-byte cell and two 16-byte frames: three 64-byte allocation classes become one.
The 32-byte header and collection geometry do not change. Lookup matches either
nominal token before forwarding outer; callback dispatch still excludes the
matched provider and every younger scope. Loads and typed stores address the
canonical frame base and its value at byte 4. Scalar/F32 fields never become
edges; reference values and the outer link remain strong, including ready-demand
cycles. No interior heap references, owner-token exceptions or Emitter fields
are added.

The evaluator keeps numeric cells and read/write frames. Its heads/cell IDs do
not escape into guest closures or artifacts. Generated guest frames have kinds
callback 0, request 3 or State 4, so the old guest read/write dispatch branches
are removed. Unexpected guest tags trap. The optimizer interpretation advances
to v 9 with `paired-state`; stale compiler artifacts cannot certify the old
layout. Raw/partial routes keep their existing ownership admission.

Qualification passes 17 focused native/OOM laws, 115 executed laws including all
eight unchanged allocation budgets, and 349 analyzer files with zero findings.
The new native law changes an ordinary source State value from Array to scalar,
requires fresh/retained/artifact/restarted equality and checks all retained
allocation failures without mutating Core. New executed laws require complete
ownership for forwarding aliases, two nested same-typed states, an interleaved
arbitrary provider, Array snapshots under pressure and pointer-looking U32/F32
values. Existing suspended/cancelled strong-ready-memo cycle laws remain intact.

The final Safe/noLLVM binary is
`f2847d6a6b4e6c483598f7a404199bc885bbf058a9c68881e34f28a6e776d2d0`. Its
11352-byte mixed Wasm is
`b973f6214f9e5a8cfe7a3d5f68903c5f468e9747a1543863f5bde07854419a94`. Per strong
cycle, allocations/destructions fall from 12 to 10, reservations/pops from 23 to
21 and actual dynamic retains/releases from 18/26 to 15/21. Frames remain 10.
The first prototype retained the old guest dispatch branches and improved cycle
CPU 14.3–14.6%; it is preserved separately.

The final CPU 6 screen uses 25 alternating three-way rounds with five discarded
rounds, checked values, flat warmed memory and load averages 1.40–1.87. These
are guest CPU screens prepared by a development compiler, not release compiler
CPU qualification.

| Guest batch               | Forward CPU ms | Paired State CPU ms |
| ------------------------- | -------------: | ------------------: |
| Sync scalar, 10000 calls  |          3.266 |               3.211 |
| Sync Arrays, 2000 calls   |          4.205 |               4.321 |
| Sync requests, 2000 calls |          7.293 |               7.263 |
| Sync cycles, 20000 cycles |         21.841 |              19.139 |
| JSPI scalar, 10000 calls  |         17.856 |              18.259 |
| JSPI Arrays, 2000 calls   |          7.264 |               7.481 |
| JSPI requests, 2000 calls |         10.365 |              10.449 |
| JSPI cycles, 20000 cycles |         21.889 |              19.157 |

Final cycle CPU improves 12.4–12.5% versus the frozen forwarder. Array controls
regress 2.7–3.0% and JSPI scalar 2.3% on this screen; these tails require final
release qualification. Cycles still cost roughly three times historical tracing.
Task 035 remains open for physical tracing removal, wide ownership coverage and
the final CPU/memory gates.

## Integrated descriptors, forwarding and State at `850793f`

All three frozen slices above are in `850793f`, jointly qualified with scoped
SIMD and guarded body receipts. Full native suite,936 guest/client tests, eight
unchanged budgets and 350 analyzer files/zero pass. Standard Zig 0.17.0
LLVM/Fast release `fa471c09…2387` produces the exact 11352-byte mixed Wasm
`b973f621…9a94` from the isolated final State screen. The 32-byte header,
collection geometry, typed reference roles and raw/partial admission stay
unchanged. The joint optimizer key includes both ownership and SIMD facts.

CPU 7 screening uses 25 alternating baseline/joint pairs, discards the first
five, checks values and flat warm memory. Baseline is qualified 2689 ad 5
(`9ea894d4`), so these merged costs include all three slices rather than only
State.

| Guest batch              | Baseline CPU ms | Joint CPU ms |  Ratio |
| ------------------------ | --------------: | -----------: | -----: |
| Sync scalar,10000 calls  |           3.215 |        3.102 |  .9649 |
| Sync Arrays,2000 calls   |           4.043 |        4.044 | 1.0002 |
| Sync requests,2000 calls |           7.054 |        6.898 |  .9780 |
| Sync cycles,20000 cycles |          28.536 |       18.432 |  .6459 |
| JSPI scalar,10000 calls  |          18.027 |       17.801 |  .9875 |
| JSPI Arrays,2000 calls   |           7.316 |        7.441 | 1.0171 |
| JSPI requests,2000 calls |          10.330 |       10.179 |  .9853 |
| JSPI cycles,20000 cycles |          28.567 |       18.425 |  .6450 |

Cycles improve about 35.5%; the JSPI Array control regresses 1.7%. These costs
do not close the historical tracing comparison. Task 035 remains active for
physical removal, complete coverage and its final CPU/memory gates. Exact raw
rounds and compiler/fixture/harness pins are in
`build/bench/joint-024-035-041/ownership/`; public/synthetic compiler costs are
recorded in [NUMERIC_SIMD](NUMERIC_SIMD.md). New conditional-frame work is
isolated and absent from this milestone.

## Integrated conditional and immutable storage at `4013b10`

Five ordinary ownership follow-ups are qualified with 045/046 at `4013b10`:

- Conditional activation opens a function's invocation frame before its first
  possible owning operation. A borrowed early reference return independently
  publishes its counted caller result. Unknown/import/indirect calls and
  unsupported control keep the ordinary frame.
- Payload-free nonopaque constructors serialize their exact immutable `[tag,0]`
  representation instead of allocating a cell per use. Tags and changed
  admission remain exact; source/data serialization is authoritative.
- Array concat/slice copies publish through the existing canonical-base
  `copy_words` helper. This repairs reference-edge admission without treating
  interior pointers as owners.
- A generalized local producer with one concrete checked use can prepare that
  private physical instance. Only quantified holes gain facts. Captures, merges,
  carries, multiple uses and unresolved instances decline; semantic
  generalization stays unchanged. The owned resolved Body carries the mapping
  through encoding, with no Emitter growth.
- Exact immutable source layouts suppress candidate enqueue using the existing
  no-cycle flag. All constructors in the emitting source unit are checked;
  foreign/unknown/mutable/callable payloads decline. Genuine trial closures
  still follow every typed edge, with unchanged counts/destructors/header.

The separately frozen inputs under `build/bench/tracing/` are
`conditional-roots.patch` (`cdd147e0`),`immutable-constructors.patch`
(`04006538`),`array-publication.patch` (`4231b1f5`),
`private-local-storage.patch` (`b12a88e7`) and `immutable-acyclic.patch`
(`1b4fcb36`). Isolated native/OOM, executable, allocation and cost screens are
preserved in their original trees. These do not replace merged qualification.

The Array publication fix changes the unchanged rolling cancellation fixture
from fallback `[1,0,7]` and growing heap to strict `[2,2,0]` and flat 128KiB.
Single-use private storage does the same for the original cyclic mapped-window
and persistent-update fixture. No source annotation rewrites hide either
failure. Both tiers retain results, zero roots/leases and bounded 4096→65536
streams/updates. Scalar immutable summary construction eliminates repeated
alive-graph trials, with linear actual release CPU. Cyclic values retain their
ordinary collector cost; see
[rolling qualification](ROLLING_SUMMARIES_QUALIFICATION.md).

The merged tree is `3688e1965213b06e36a1ad5118ab1c6f1c1de54b`, compiler source
`48f7bf8cd3219535013dd8eb96b28e0c67702bcd`. Standard Zig 0.17.0 LLVM/Fast
release SHA-256
`44af80a95af5de58c521a7d520c5d8c6ea993e09aae1c06e9031f3d5dbd9ec2b` passes full
native/OOM,961 guest/client tests, all eight unchanged budgets and 351 analyzer
files/zero. Private arena helper roles derive through the existing
`Arena.function_fields` catalog and remap through executable artifacts;
optimizer v 12 retains the numeric-scope/row-product domain alongside ownership
facts.

Twenty-five CPU 7 alternating merged/qualified `850793f` pairs discard the first
five and check results/flat warm storage in sync and JSPI modes. The mixed Wasm
grows 11352→11650 bytes; both manifests remain `[2,2,0]`.

| Guest batch              | Baseline CPU ms | Merged CPU ms |  Ratio |
| ------------------------ | --------------: | ------------: | -----: |
| Sync scalar,10000 calls  |           3.197 |         3.227 | 1.0094 |
| Sync Arrays,2000 calls   |           4.074 |         4.106 | 1.0079 |
| Sync requests,2000 calls |           6.989 |         7.055 | 1.0094 |
| Sync cycles,20000 cycles |          18.870 |        16.406 |  .8694 |
| JSPI scalar,10000 calls  |          18.122 |        17.284 |  .9538 |
| JSPI Arrays,2000 calls   |           7.295 |         7.338 | 1.0060 |
| JSPI requests,2000 calls |          10.141 |        10.153 | 1.0012 |
| JSPI cycles,20000 cycles |          18.719 |        16.319 |  .8718 |

Merged cycles improve about 13% versus `850793f`; the other control costs are
recorded above. Public compiler CPU ratios 0.9945–1.0234 and zero peak deltas
establish no general compiler gain. Four synthetic workloads preserve exact
fresh/retained/restart output. Exact pins/raw rounds are in
`build/bench/joint-024-035-045-046/`.

Task 035 remains open for physical tracing removal, general admission and the
historical tracing CPU gate. A later frame-retirement batching experiment was
rejected for neutral cycle CPU and a scalar regression. Further direct named
reference-environment subtraction is isolated and absent from this milestone.

### Direct named reference environments

A named partial application with exactly one checked reference argument stores
that canonical reference directly in its descriptor. The redundant environment
cell disappears. Static serialized captures and a later transition to an
ordinary multi-argument environment follow the same layout proof. Scalar U32/F32
bits, erased layouts and other arities retain their boxes. No Emitter, header,
ABI or instruction fields are added; optimizer interpretation v13 distinguishes
the new representation.

The unchanged strong cycle now allocates seven objects rather than eight, opens
four frames rather than five and reserves fifteen slots rather than seventeen.
Its typed retains/releases fall from eleven/fifteen to ten/fourteen. A callable
retirement law checks zero remaining roots/leases, flat warm memory, positive
destruction and exact acyclic retain/release balance, independently of the
number of surviving boxes. The strengthened law passes the old control too.

Focused development checks pass 21 native laws, another 16-law exact
serialization/replay/changed-role/OOM batch, and 77 executed laws including all
eight unchanged compiler budgets. The final LLVM/Fast build additionally passes
43 callable, cycle, suspension and budget laws. Both codegen tiers and sync/JSPI
invocations preserve pointer-looking scalar bits, persistent aliases, static
captures and later curry stages. Analyzer results and exact pins accompany the
frozen patch; the parent owns its mandatory combined full gate.

The standard LLVM/Fast candidate is SHA-256
`2e90a2329c62e72de8bbe5efe7daa50c60487fb9faeb4ebcca2f44e337a050cd`. The
qualified 4013b10 control is
`44af80a95af5de58c521a7d520c5d8c6ea993e09aae1c06e9031f3d5dbd9ec2b`. Both compile
the same ordinary source and std tree. Thirty-one warm alternating pairs on CPU
7 check exact values and flat 131072-byte memory; load averages span 0.72–0.74.

| Guest batch               | Control CPU ms | Direct CPU ms | Change |
| ------------------------- | -------------: | ------------: | -----: |
| Sync scalar, 5000 calls   |          1.548 |         1.557 |  +0.6% |
| Sync Arrays, 1000 calls   |          2.051 |         2.047 |  −0.2% |
| Sync requests, 1000 calls |          3.615 |         3.518 |  −2.7% |
| Sync cycles, 20000 cycles |         15.790 |        13.432 | −14.9% |
| JSPI scalar, 5000 calls   |          8.931 |         8.829 |  −1.1% |
| JSPI Arrays, 1000 calls   |          3.895 |         3.889 |  −0.2% |
| JSPI requests, 1000 calls |          5.021 |         5.094 |  +1.5% |
| JSPI cycles, 20000 cycles |         15.804 |        13.292 | −15.9% |

Seven alternating fresh compiler pairs measure 8.769 to 8.790 ms CPU (+0.2%) and
13.322 to 13.578 ms wall (+1.9%). Requested bytes grow 28, peak falls 225,
allocation count falls three and code instances stay at twelve. The mixed Wasm
grows 11650 to 11666 bytes. Removing its cycle workload produces byte-identical
control artifacts. Historical Safe/noLLVM measurements and rejected batching
prototypes remain separate. This removes a measured ownership cost; it does not
qualify task 035's final relative tracing CPU gate or remove fallback tracing
from uncovered shapes.

### Integrated callable and scalar checkpoint

Local implementation `cb3ebec` integrates the direct environment with
scalar-only local replacement. Full native/OOM, 965 guest/client laws, eight
unchanged budgets and 351 analyzer files/zero pass on the standard LLVM/Fast
release. Merged cycle CPU falls about 13.7%; scalar/Array/request controls
remain within roughly 1.5%. Exact pins and the separate merged costs are in
[iterator state qualification](ITERATOR_STATE.md). Physical tracing removal,
whole-module coverage and the historical relative CPU gate remain open.

## Checked callback identities (13 October 2026)

Host callback wrappers store their descriptor's own base in the scalar
environment word as a borrowed identity. The exact adjacent store fact now
preserves alias liveness without treating this identity as an owning edge.
Unmarked, forged and interior identities decline. The focused native law passes
its complete 952-failure allocation sweep; existing host callback and retained
role laws execute with zero role conflicts.

This removes the captured project's callback role conflict, but its first
remaining unproven body still prevents whole-module admission. Physical tracing
removal and the historical runtime gate remain open. No release or full gate was
repeated for this isolated slice; combined qualification belongs to the parent
integration batch.

## Counted persistent field updates (13 October 2026)

Record, product and nominal field updates now carry their checked payload mask
through replacement allocation, copy and field publication. All-scalar payloads
keep their scalar allocation/copy/store path for local elimination. Every
constructor arm selects its own exact size/mask; nested paths preserve
persistent aliases and captured old values. Unknown typed masks retain checked
runtime publication and cannot license scalar lifetime shortening. Unannotated
raw storage and heterogeneous tails beyond the counted mask stay conservative.

The native dynamic-mask law passes its allocation-failure sweep, and the
executed law covers distinct constructor layouts, persistent aliases, captured
old values, F32 signed zero, both compilation tiers and fresh/edit/revert byte
equality with complete journal admission. Fifteen existing update, payload,
retained-record and role laws also pass. Captured body 585 is now covered; its
next unproven body is 864. Production tracing deletion and the historical CPU
acceptance remain open; no release/full gate was repeated for this slice.

## One typed initialization contract (13 October 2026)

Typed allocation now guarantees null reference storage in counted and partial
modes. Exact Array builders drop their duplicate clear. This removes dynamic
bulk initialization from the source ownership proof without granting a new
compiler fact or shortening owner lifetimes. A permanent dirty-block reuse law
executes both modes, all 21 shared runtime laws pass, and 12 Array/builder/
tracing-replacement laws pass. Iterator allocation counts retain the qualified
77,800-object window and zero-object strict/pipeline results. Captured body 864
is covered; body 894's scalar Array-header update remains a separate blocker.
Physical tracing deletion and historical runtime acceptance remain open.

## Checked scalar publication (13 October 2026)

Scalar Array headers and packed row lanes carry an adjacent physical scalar
store fact. It qualifies publication without granting alias or lifetime facts,
and preserves the original Wasm stores. Exact width/opcode/alignment checks,
known scalar ranges and rejection of known fresh-reference values constrain
admission. Unknown offsets in known mixed owning layouts still decline.

The 16-test focused native batch includes the complete allocation-failure law
for ten positive/negative store scenarios. Sixteen packed/revision/boundary/
tracing-replacement guest laws pass, including both tiers and fresh/edit/revert
byte parity. Dynamic slice/concat traversal now requires complete admission; its
unchanged 100-call pressure and flat-memory law passes. Analyzer is zero across
375 files. Optimizer interpretation is version 27.

The captured project remains partial because a 144-byte allocation has distinct
reference/scalar roles beyond the current mask's uniform tail (first mismatch at
word 33). Extended ownership bitmaps, physical tracing deletion and the
historical runtime gate remain outstanding. No release/full gate was repeated.

## Finite wide shapes (13 October 2026)

Wide payloads now use an exact immutable reference bitmap without enlarging the
32-byte header. Checked publications and copies interpret only reference words,
including sparse roles beyond the compact mask's uniform tail. Destruction and
trial deletion share that representation. Scalar and compact-mask payloads keep
their current representation. Different constructor layouts select both their
own physical size and shape for persistent field replacement.

The 93-unit captured project now has complete ownership `[2, 2, 0]` with 2,866
prepared functions and zero role conflicts. Executed laws cover 96-word sparse
layouts, pointer-shaped scalar bits, exact copy counts, self cycles, malformed
shape descriptors, persistent record/constructor updates, snapshots, captured
old values and F32 signed zero. Retained edits that move static data reproduce
fresh bytes in both tiers; their immutable bitmap-reader demand survives replay.
The native checked-publication and exact owned-replay law also passes its
allocation-failure sweep. Physical tracing deletion and historical CPU
acceptance remain open. Combined release qualification is deferred to the parent
integration batch.

## Deferred partial scanners (13 October 2026)

The allocator no longer generates legacy mark/collect/root-mark bodies into
source or retained artifacts. Complete emission needs no scanner materialization
and removes its legacy chain/cache writes at words 4 and 12. Remaining partial
contracts construct scanner bodies only after final admission, then release that
temporary ownership after assembly. Partial scanners are isolated in
`partial_tracing.zig`; empty signatures retain separate machine identities.

Permanent laws check empty source signatures/locals, exact removal of two
metadata stores, unchanged source during materialization, shifted function
identities, partial machine sharing and complete OOM cleanup. The executed law
pins metadata sentinels across repeated complete allocation/leave/reset and
executes the shared partial route. Existing partial runtime, cycles, memoized
state, host exchange, wide/retained and nested discarded-Array laws remain
valid. Partial production contracts and the historical performance gate still
keep physical deletion of the final fallback open. Release/full qualification
remains owned by the combined integration batch.

## Checked List literal publication (13 October 2026)

A source inventory of 101 real feature laws/103 builds found six partial builds
of the mixed role program. Its first unproven body constructed a nominal List
literal with raw stores into returned leaf addresses; late whole-module fallback
then masked the cause as `host_references` when Foreign callbacks were present.
Callbacks alone already had complete admission.

Exact reference literals now reuse checked collection publication with the
actual current leaf base. Scalar literals carry the existing scalar-store fact;
unknown layouts remain conservative and packed rows keep their current stores.
The mixed program, with and without Foreign callbacks, now has complete
admission. Permanent coverage pins fresh/edit/revert ownership and bytes, 260
shared child references over multiple leaves, conversion snapshots, persistent
Array edits, captured old values, signed F32 zero and bounded repeated
invocations in both tiers. A native source-emission law exercises every
allocation failure. The optional machine-code-sharing route and any uncovered
production contracts still need admission repair before final legacy scanner
deletion; historical performance and combined release qualification remain open.

## Prepared machine sharing (13 October 2026)

Machine sharing no longer forces otherwise complete source graphs into partial
admission. Every source function receives independent ownership preparation and
retains its own exact output before machine bodies are compared. Different
checked roles can produce different publication/cleanup code even when their raw
instructions match; sharing now observes those consequences. Public identities
and indirect table slots remain distinct. Parallel preparation no longer
consults a premature sharing map.

Native laws cover conflicting scalar/reference payload masks, complete
admission, separated retained duplicates, exact source immutability and complete
allocation failure cleanup. Shared mixed source preserves fresh/edit/revert byte
equality, complete ownership and sync/JSPI callbacks; complete metadata
sentinels remain unchanged with either emission mode. Final shared count
describes omitted machine output separately from source optimized/reused work.
Uncovered source contracts and the historical performance gate still keep task
035 open.

## Checked production assembly (13 October 2026)

Production source emission and artifact replay now select an assembly
instantiation with no reachable legacy scanner generator. Incomplete ownership
returns an owned emission diagnostic rather than selecting partial scanning. The
deliberately raw Module fixtures retain their private partial contract.

The remaining request cancellations carried erased, unused completion types. A
bounded Core bottom proof supplies a physical scalar cancellation result only
for an exact action with no normal result. Its consumer may fill that erased
completion slot; retained factories remain free to specialize independently at
U32 and F32. Normal returns, outward control, loops, partial calls and exhausted
proofs supply no such fact. Function creation records the role in the artifact
journal; no frozen source or source type is mutated.

Bottom aggregate, Array/List and constructor operands now end emission after
their checked Never value. The eager prefix still executes; dead construction
and its unresolved field roles disappear. Existing bottom-flow laws cover those
prefixes and generic captured callees. New laws cover production rejection,
source immutability, fresh/retained/replay parity, complete OOM cleanup, and
retained request cancellation in both execution tiers.

This is a focused implementation checkpoint. Combined release/native/guest
qualification, new checked/unchecked List helper variants, and the historical
performance comparison remain integration obligations; task 035 is not yet
claimed complete.

## Bounded cohort runtime prerequisite (15 October 2026)

`cohort_runtime.install` appends helpers only to a private admitted assembly
view. Ordinary Source artifacts, arena registration and RC/cycle bodies are
unchanged. One leased owner keeps a bounded member list; each member holds one
real counted pin in addition to its ordinary journal lease. Retirement first
validates the whole group, marks the complete set dead, consumes pins and uses
the existing dead-set destructor. Live outgoing references keep ordinary
ownership.

The compiler must independently prove exact membership, internal stores,
incoming calls and owner journal lifetime. Allocation order alone cannot prove
that moved result roots retire before the owner. Candidate collector enqueue and
discovery must both exclude grouped objects. Partial ownership, escaped retains,
malformed lists, excessive membership and premature retirement trap.

Three native laws include full OOM cleanup. Ten direct Wasm protocol groups
cover cycles, outgoing children, bad protocols, journal page growth, trap unwind
and repeated bounded memory. The direct fixture's mutable ownership switch is
not Source admission evidence. This checkpoint enables no production rewrite and
claims no historical performance win. Task035 remains open; the runtime
candidate and final qualification remain separate.

## Owned emission coordinates (15 October 2026)

Compiler emission now retains typed call/allocation coordinates with owned Core
unit, expression, body root, type-mapping evidence and row context. Artifact
replay relocates functions; retained import reconstructs semantic owners before
publishing coordinates. Diagnostic spans provide no authority. These receipts do
not independently establish dispatch, lifetime, cohort membership or RC
permission; a consumer must rederive those relationships from immutable Core.

The root receipt law passes complete replay/import allocation failures and
malformed-coordinate controls. Twenty-two selected executed groups and the
full453-file zero-finding analyzer pass. Ordinary Cost remains byte-identical
at11958B. Private25-pair controls measure wall geomean0.999058 over
ordinary/Cost fresh/retained cases; CPU instrumentation was invalid and supplies
no CPU gate. Exact source images, pins and root logs are in
`build/bench/complete-program-20261015/semantic-emission/`. The production
intersection/consumer and historical ownership performance gates remain open.

## Rejected closed-activation consumer, 15 October 2026

The private semantic/Core-to-runtime intersection and late assembly consumer
pass focused lifecycle and retained/portable execution controls. They remain
unpromoted. Thirty balanced CPU7 rounds preserve exact values and128KiB warmed
memory but cycle CPU remains flat against the current compiler:median ratios
0.99955sync and1.00105JSPI. Historical total median geomean1.28443 and cycle
p951.64304/1.61003 fail the required gates. Removing measured cycle walks alone
replaces their cost with per-member pins and group-list validation.

Immutable source/patch/compiler pins, raw rounds, profiling samples and the
rejection are preserved in
`/var/tmp/blot2-closed-activation-cohort-evidence-20261015/`. Its production
hook is absent from the root. Runtime prerequisites and tracing metadata remain;
no ownership performance or full-program completion is claimed.

The subsequent nested-callable reuse repair checks each callable-layout record
against its own checked job rather than its enclosing caller. Semantic-site
admission and immutable lifetime checks remain unchanged. Root complete-OOM,
26executed groups and112affected analyzer files pass; ordinary Cost and captured
project bytes remain exact. Captured retained reuse recovers489fragments. This
compiler-work repair supplies no new ownership permission or tracing-removal
evidence. See `build/bench/complete-program-20261015/nested-callable-reuse/`.
