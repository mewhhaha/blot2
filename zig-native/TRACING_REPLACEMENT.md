# Tracing replacement work

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
Optimizer interpretation v4 preserves the existing signatures, imported names,
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
is added. Combined interpretation v6 retains associated type and checked
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

Implementation`2689ad5`, tree`92e09418…51fb6a`, passes the full native suite,
925 guest/client laws, eight unchanged budgets and349 analyzer files/zero.
Standard Zig0.17.0 LLVM/Fast release SHA256`9ea894d4…8b21` is immutable under
`build/bench/joint-024-035-040/`. Its exact pins and mixed public compilation
costs are recorded with[040](ROW_FUSION.md). Compact-marker CPU measurements
above remain a separately pinned isolated comparison; they do not close the CPU
gate or qualify physical tracing removal. Partial/raw contracts continue to
retain ordinary helpers. A later null-environment closure descriptor slice is
separately frozen, not in this milestone. Task035 remains open.
