# Specialization and principal query migration

Task 016 implements and qualifies the common tables described below. The local
milestone revision will be filled in after committing the qualified sources. The
common ownership/index primitives were qualified for refinement in
[REFINEMENT_QUERIES.md](REFINEMENT_QUERIES.md).

## Claims and owners

`selected_query.Table` owns completed retained specialization judgments in the
artifact Context. Its key contains the closure's unit, identity, origin and
applied count, owner-local input/expected IDs, exact Options and depth. Its
dependency record is the complete observation/replay receipt; its result names
the selected value in that Context's pinned evaluator snapshot. Completion
checks every duplicated key/result field against the receipt. An incomplete
successful observation remains a private operational receipt, not a published
table result. The Session's temporary observation list still records attempted
and incomplete inquiries for instrumentation and capture.

The retained lookup uses the common oldest-first position index. The separate
source buckets and their position vectors are removed; lazy graph inspection
plans stay private to the current import lease. Every old source/input/expected,
capture/alias/scalar/nominal, typed-view, call and plain-data check remains
before the original staged graph import and atomic evaluator publication. The
bare selected ID grants no admission outside its owning snapshot. Cross-revision
answers are materialized into current owners, with translated observations.

`canonical_specialization.Cache.table` owns Session-local selected, inferred and
entry judgments under distinct modes. Full canonical capture words preserve
values, interfaces, aliases, nominal creation and source identity; expected
evidence, exact Options and depth remain required. Result arrays are an owned
local replay recipe, not a portable evaluated-value cache. Oldest-first lookup
preserves the former per-hash vector priority and tests full equality after
fingerprint filtering, including forced collisions. Reconstruction still maps
all current inputs and reserves every evaluator/fact/memo destination before
publication. The separate hash/vector cache is removed.

`principal_query.Table` owns source-inferred type/row results in the Context.
Its target/Options key, optional projected observation dependencies and result
stay separate from selected judgments. A successful empty type/row result is
complete; missing projected observations still permits the original exact-source
proof path. Recording declines any nonempty selected-implementation list. First
source proof per target remains the publication policy, and retained lookup
preserves the original first-target/options behavior. Exact-source,
projected-empty, nonempty primitive and paired-graph import gates remain
distinct. Only matching dynamic dependencies may carry projected
inputs/publications into the new revision. The old principal proof list is
replaced by owned records and the common position index.

The portable archive Reader now builds a lease-local principal table lazily,
after the exact ordered source/catalog image and identity namespace match.
Records own copied dynamic inputs and name encoded answers by ordinal in the
immutable decoded Archive. The Reader pins that owner outside the query key; the
ordinal is checked against its proof count. It names an encoded candidate whose
result still needs current-owner import and validation. Oldest-first indexed
lookup preserves wire order, including duplicate proofs. The original
target/Options/input checks, type/row graph import, nominal memo validation,
translated closed-call proofs and atomic publication remain required. Successful
imports become new owner-local evidence, then enter the Context's principal
table through normal recording. The version-2 wire projection and archive key
remain unchanged; query-table serialization belongs to task 019.

Lazy index construction is private and transactional. OOM releases all partial
records and permits retry on the same Reader. Saturation retains only the
bounded prefix and declines omitted candidates to ordinary inference. There is
no secondary linear proof scan. Reader storage and inspected bucket positions
are reported separately from persisted semantic hits.

## Local principal templates

Two Session-local tables explicitly distinguish `source_description` from
`open_residual`. The former owns immutable described source graphs and residual
body actions; the latter owns proven normalized open residual templates. Their
keys include target, source-interface/deferred-member flags, full Options and
the explicit source claim. The cache binds its Session and immutable units owner
outside canonical key data before any lookup. Each graph has its own copied type
Store and source binder/row imports; importing always freshens binders into the
receiving solver. No active Region, solver variable or caller-selected evidence
becomes a template key/result.

Complete local descriptions may still have `source_complete=false` or untracked
outer observations. Their typed claim is a source template, not a completed
semantic proof. Existing dependency propagation marks enclosing receipts or
principal observations unknown when such a graph cannot justify them. These
templates cannot cross a Session/units owner or enter the portable archive.
Unsupported descriptions remain bounded private source-work memos; they do not
occupy successful table slots or become persisted failure proofs. Classification
and live component/SCC/job/header/lexical maps stay Session machinery.

Source dependencies and ordered plain-fact observations/publications are owned
by each template record. Lookup checks exact owner/key and simulates prior
writes while checking later reads, without publishing facts. A first absent read
that conflicts with a now-present fact conservatively misses, including a memo
computed during its own description. Ordinary checking can derive a new
description from the current facts. A hit grants no evaluated value, call proof
or completed principal scheme.

Each lookup has a separate 4,096-inspection budget covering bucket candidates,
dependency reads and any prior-write scans. Inspection counters include declined
work. Budget exhaustion declines optional reuse. If a transitive template cannot
be observed under current bounds, outer observation capture becomes unknown;
ordinary checking remains authoritative.

## Bounds, transactions and measurement

Each shared table uses the qualified defaults: 4,096 records, 16 MiB payload, 2
MiB actual record/index buffer capacity and at most 4,096 bucket positions per
lookup. Existing semantic graph, source and Session work quotas remain required.
Private unsupported-description work memos are separately bounded by record
count. These are per-owner bounds, not a global RSS or compiler allocation
target.

A stable allocator embedded in each heap-owned local principal graph measures
all its retained allocations, including Store buffers, spare capacity and
interning/cache storage. Its destruction releases both contents and graph
header. A temporary copying meter wraps that stable owner for existing logical
traffic counters; no temporary allocator escapes. Template payload charges the
whole graph/header plus independently owned dependency vectors. Capacity
reservation remains operation-local and publication remains allocation-free.

The compiler reports table storage and local-template lookup work separately
from semantic work counters. The retained measurement driver records both
per-compilation ephemeral tables and the actual selected/principal/refinement
tables held by the committed revision. Reused-output no-ops have zero
compilation work counters but still hold the committed records; their allocator
deltas and retained table snapshots distinguish these cases.

## Qualification on 10 October 2026

The final focused production batch passes 248
query/principal/callback/canonical/ source-template/checkpoint tests. New
targeted laws cover foreign Session/claim/flag/Options misses, forced
collisions, duplicate graph candidates, absence/false/true changes, ordered
reads/writes, budget exhaustion and every allocation failure with retry.
Principal publication also rejects selected answers and preserves the first
source proof. Portable Reader laws verify oldest valid duplicate priority,
optional saturation and clean retry at every lazy-index allocation failure. The
checkpoint sweeps cover decoding, index construction, import, replay and
teardown. The pinned analyzer reports zero findings across 300 Zig files.

The new executed-Wasm law exercises imported same-type/different-value scalar,
aggregate, nominal, aliased and nested captures under serial/default and worker
policies, with producer relocation, unused-source failure/recovery and
checkpoint restart. The final frozen-source `deno task test:compiler` gate
passes the full LLVM native suite and all 623 guest/client tests.
`deno task lint:zig` has zero findings across 300 files, and
`deno task package:check` passes.

The immutable task-015 baseline is `candidate-refinement-query-v2`: binary
`cc8257fafaebaaa6c421b167220cb635db3062b8da3dd6e00064335801888526` and identity
`6fe193c0a27c3445398769693281c87eb93c805311828df957b86731b3dab368`. The task-016
`candidate-specialization-principal` binary is
`1e6bbc8e4c951c0b2b9388f3edcc51730158a281e80a99bb4f79ef81cea580da`, identity
`cc2684845fd95500767e26465b0f47edc11e4f76792eb36336484d321080bd04`, and complete
413-file Zig/guest-input map is
`f89c5cd1b6b1433d58d5107ec0a20c310276aa1734fa73e22d4d5687bd6b7066` (SHA-256 of
sorted compact JSON). Its source revision will be recorded after the qualified
local commit. Neither preceding qualified pin is overwritten.

Strict comparison passes 626 public cases / 3,756 invocations / 433 successful
cases across baseline and default/1/2/4/8 candidate policies: ordered diagnostic
and Wasm-byte parity, no acceptance correction, and zero native teardown live
bytes. Executed differential guests pass 192 guests / 10,362 calls. Retained
qualification passes 27 workloads / 2,106 revision samples / 648 guests / 41,208
calls, plus 3 refinement workloads / 234 samples / 72 guests / 12,312 calls.
Edits, reverts, no-ops, fresh rebuilds, rejected candidates, recovery and
checkpoint restart preserve the qualified observations in every policy.

Two additional proof fixtures pass 156 six-policy revision samples, 48 executed
guests and 96 constant reads, with a retained principal hit on every edit and a
persisted principal hit on every restart. They distinguish empty results from
nonempty effect-row results. Native laws separately cover primitive/nonempty
type mappings and normalized open residuals; the public retained probes do not
expose positive open-residual table storage. CLI restart samples expose
persisted hits and allocator totals, but omit query-table storage; those CSV
fields are null.

The ignored evidence lives under `build/bench/cloud-principal-graphs/`:
`selected-query-full-gate-v3.log`, `selected-query-analyzer-v5.log`,
`selected-query-focused-v18.log`, `selected-query-package-check-v3.log`,
`specialization-principal-comparisons/`, `specialization-principal-retained/`,
`specialization-principal-specific-retained/`, and
`specialization-principal-proofs/`. Source code, durable specifications and
distributions are kept in version control.

## Fresh CPU and requested allocation

Eighty-six public workloads run 15 alternating baseline/candidate pairs, for
2,580 unprofiled fresh CLI processes with the optional restart cache disabled.
CPU is Linux child `getrusage(RUSAGE_CHILDREN)` user+system time. Wall time ends
immediately after subprocess completion, before JSON/Wasm parsing. Wasm bytes
match and every compiler reports zero teardown live bytes.

Geometric means of candidate/baseline workload medians are CPU **0.9943**, wall
**0.9966**, and requested bytes **1.0031**. These measurements support
near-neutral overall CPU, not a general speedup or allocation reduction. The
largest CPU ratio is the small refinement-8 control, 800→886 µs; callback-128
costs 8,541→9,014 µs and diamond-128 26,900→28,337 µs. The largest
requested-byte increase is scalar-8, 235,341→247,069 (+4.98%).

| Fresh public width/family | CPU µs old/new | Wall µs old/new | Requested bytes old/new |
| ------------------------- | -------------: | --------------: | ----------------------: |
| Capture 8                 |  1,743 / 1,752 |   1,941 / 1,948 |       835,409 / 828,977 |
| Capture 32                |  2,254 / 2,178 |   2,550 / 2,373 |   1,275,884 / 1,269,452 |
| Capture 128               |  3,840 / 3,866 |   4,069 / 4,146 |   2,873,191 / 2,866,759 |
| Jobs 128                  |  3,722 / 3,855 |   4,003 / 4,168 |   3,215,393 / 3,215,393 |
| Refinement 128            |  3,184 / 3,256 |   3,403 / 3,470 |   2,612,180 / 2,612,180 |

Full per-workload CPU/wall/requested/peak distributions and work/principal
counters are in
[the fresh CSV](qualification/specialization-principal-queries-fresh.csv).

## Retained owners, edits and restart

Eleven width/dependency/refinement workloads plus two proof fixtures run seven
alternating pairs. The 182 native driver processes perform 15,288 phases: 21
rounds of population/no-op, edit, revert and no-op. CPU is `RUSAGE_SELF` over
all process threads during prepare, digest, commit and candidate cleanup; source
setup and JSON serialization are excluded. The identical driver source is built
with LLVM Ofast for each implementation. Its exact
[source](qualification/semantic_query_probe.zig) is retained with the
distributions; install it in each pinned implementation's `zig-native/src`
before building with
`zig build-exe -fllvm -flld -Ofast -target x86_64-native -mcpu baseline`. Driver
binary hashes are baseline
`4b9c9abff2cb7cf52bf0171f381de5774c561db938e1b0985fa5ff1d933cc6c1` and candidate
`4c5d3a74cca4e6a349c47325fbacc83126bdbc2bc9db822b168a26fc7ccf99a4`. A further
546 CLI processes cover fresh compilation, cache population and restart. All
paired phase digests match, each steady phase retains a fixed live-byte plateau,
and all 182 drivers plus all CLI processes tear down to zero.

| Native steady phase         |  CPU µs old/new | Requested bytes old/new | Peak live bytes old/new |
| --------------------------- | --------------: | ----------------------: | ----------------------: |
| Capture 128 edit            |   3,357 / 3,383 |   3,815,839 / 3,810,311 |   1,881,079 / 1,876,735 |
| Dependency 128 edit         | 2,039.5 / 2,079 |   2,377,293 / 2,390,405 |   1,101,074 / 1,106,386 |
| Jobs 128 edit               | 3,245.5 / 3,266 |   3,853,188 / 3,853,908 |   1,284,823 / 1,284,823 |
| Empty principal edit        |        98 / 116 |         79,429 / 83,173 |         31,529 / 34,565 |
| Nonempty row principal edit |     119.5 / 114 |         80,637 / 84,381 |         35,837 / 41,885 |

Each proof fixture holds one principal record: payload 12 bytes for the empty
query's observed inputs, or 8 bytes for the nonempty row mapping. The common
record/index buffers use 3,360 bytes versus the old vector's 336, adding 3,024
held bytes. This bounded overhead is material on these small controls. Empty
principal restart CPU is 963→1,063 µs, row-principal restart 880→1,012 µs;
requested bytes are 74,767→80,521 and 75,293→81,035 respectively. These are
costs, not speedup evidence. Steady native edits record one principal hit; row
results require one graph import. Both proof fixtures retain their principal
records through reused-output no-ops, whose per-compilation counters and tables
are zero.

Across these public retained fixtures, selected tables peak at 16 records / 256
payload bytes / 5,792 buffer bytes. Local canonical replay reaches 16 records /
208,896 payload bytes / 9,144 buffer bytes. Local source descriptions reach 16
records / 30,080 payload bytes (including complete graph-owned allocation) /
3,000 buffer bytes; a population lookup inspects 17 positions. Principal records
and both local graph kinds have additional native owner/collision/budget/OOM
laws. No measured table saturates or exceeds its declared bounds. Private
decline memos remain excluded from successful table counts; their memory is
included in the enclosing allocator totals. Refinement tables remain separately
measured.

[The retained CSV](qualification/specialization-principal-queries-retained.csv)
contains all 182 workload/phase/policy rows and complete CPU/wall/requested/
allocation/peak/live distributions, per-compilation query counters/storage and
actual committed table snapshots.
[The pins](qualification/specialization-principal-queries-pins.json) include
both implementation manifests, complete driver sources, helper/report/ library
hashes, workload identities, scheduler and load observations for all three
batches. They preserve the original 11-workload and separate proof reports.

The host uses SCHED_OTHER, nice 0, affinity 0–4 and a four-CPU cgroup quota. No
batch adds cgroup throttling. One-minute loads are 0.703→0.815 (fresh),
0.417→0.614 (retained widths), and 0→0 (proof controls). Source inputs remain
frozen throughout qualification. The missing historical boxed binary/private
gdev snapshot still leaves task 002 and global performance qualification open;
this migration does not replace that baseline, implement eviction/sharing,
serialize local template handles, or authorize evaluated-value reuse.
