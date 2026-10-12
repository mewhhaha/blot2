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
