# Owned refinement queries

Task 015 migrates refinement records into
[semantic_query_table.zig](src/semantic_query_table.zig), the first adapter of
the [typed query design](QUERY_TABLE.md). The refinement adapter is implemented
and qualified below. Subsequent claim migrations remain separate tasks.

## Representation and ownership

The common `OwnedRecord(kind, Key, Dependencies, Result)` carries a compile-time
claim kind and schema, an owned key, owned dependency/replay graph and owned
result. A refinement key contains body/closure identity, expected shape,
complete ordered type/row seeds, exact semantic Options and depth. Dependencies
are the finished refinement observation Tape, including source reads, scalar
reads, positive/negative call and plain-data observations, and ordered replay
publications. The result contains solved evidence mappings; it is neither an
executable fragment nor an evaluated value.

The current `code_artifacts.Context.refinement_queries` owns records, index
buffers and all transferred slices. Numeric source, expected-shape and evidence
IDs stay scoped to that Context's Core, bridge and evidence snapshots. They do
not become portable identities. Live inference uses the same append-only
evidence owner until artifact capture completes; no active solver variable,
borrowed solver slice or chronological view escapes. Cross-revision lookup
imports selected mappings into the current evidence owner through the existing
paired importer and creates a separately owned current record.

`Builder.begin` takes an owned key. `read` takes the complete owned dependency
and ordered-publication set produced by the existing Tape; `stage` takes its
owned replay result. `complete` requires known, non-nested, solved observations,
one eligible region, no evaluation/value/child growth, empty selected targets
and no typed views. Key Options/depth must equal the observation context.
Unknown or incomplete inquiries remain private and are released by `abort`.
Completed candidates remain immutable through prepare and publication.

`Table.prepare` reserves record and index capacity. The refinement adapter also
reserves current call-proof and plain-fact maps before replay. Allocation
failure or capacity saturation installs no record or evaluator publication. A
prepared token binds one candidate, owning table and record position; another
publication invalidates it. The token is a capacity/ownership check, not a
semantic validity certificate. Typed source/input/fact gates remain
authoritative. `publish` installs the complete record and index links without
allocating. Abort releases every private owner; successful transfer leaves the
candidate empty.

Handles are typed by claim and restricted to their owning table. Lookups borrow
records only while the current/retained Context lease is live, and return copied
or imported results. This migration copies replay results between revisions; it
does not add record sharing, eviction or portable handles. Existing retained
revision/Context ownership protects the last-good table from failed candidates.
Specialization, principal, source-validation and executable adapters remain
tasks 016–018; serialization and complete persistence remain 019–020.

## Exact selection and validity

One common `PositionIndex` stores hash buckets and bidirectional record-position
links. It stores no pointer into a moving record array and never collapses
duplicate observations. Append order is explicit. Local lookup traverses
**newest first**, preserving the replaced `Memo` chains; retained lookup
traverses **oldest first**, preserving the former linear first-valid scan.
Completion scheduling cannot choose priority.

Refinement fingerprints use the source root as a conservative prefilter. Every
candidate still receives full key/fact checks; a fingerprint collision is never
a hit. Local checks compare root, expected shape ID, all ordered seeds, Options
and depth under the same immutable owner. They recheck scalar evidence, required
call reads/publications and plain-data facts. The existing owner-local monotone
completed-call rule is preserved: a previously absent call proof may now be
present only under that rule; required publications must already exist.

Retained checks retain the exact ordinary mode/depth, owner/allocator and source
pair. Source/root admission, transitive receipt versus refinement early cutoff,
full expected graph shape, imported type/row seeds, scalar evidence, exact call
presence, positive and negative plain observations, and imported result and
publication evidence all remain required. Ordered plain writes are simulated
while validating subsequent reads. No source-body change is admitted by type
equality alone, and unused source errors still run the ordinary checker.

The Generator's separate refinement hash buckets/next chain are removed. The
record list and both lookup directions now belong to the common Context table.
The task-013 immutable compiler remains the differential comparison oracle.

## Bounds and measurements

Defaults admit at most **4,096 complete records**, **16 MiB of owned payload
slices**, **2 MiB of retained record/index capacity**, and **4,096 inspected
bucket positions per lookup**. Existing semantic Options and graph-comparison
depth/work limits remain separate authoritative bounds. Saturation declines
optional reuse and continues ordinary checking.

Payload bytes count exact key/dependency/result slices. `capacity_bytes`
measures actual raw record-vector, link-vector and hash-map allocations,
including spare capacity. A short operation-local allocator checks the capacity
ceiling on every successful allocation/resize/remap; neither vector nor map
retains its pointer. Failure can leave reserved capacity, which remains counted
and bounded. Backing OOM still propagates as OOM; an explicit capacity refusal
becomes an optional cache decline. Reallocation must fit while its old buffer
remains live, so a capacity ceiling may cause an earlier conservative decline.
No RSS or global compiler allocation target is implied.

Refinement statistics expose inspected index positions/local candidates, current
record count, retained payload/capacity bytes and saturation. These counters
report work and ownership; they grant no validity. Complete compiler backing
traffic and retained old/new revision overlap are measured separately.

## Qualification

The focused native batch currently passes **50 tests**, including collision
ordering, unknown/incomplete candidate refusal, record/payload/capacity bounds,
foreign handles, wrong-candidate/stale-token refusal, exact capacity accounting,
zero teardown, refinement/source-template facts and every replay allocation
failure with retry. Tests explicitly discover the common table and refinement
module laws in the production suite. The analyzer checks **298 Zig files with
zero findings**. The full LLVM native suite and **622 guest/client tests** pass;
the package build/API publication dry run also passes.

The new executed-Wasm law covers retained/fresh source edits, imported scalar
and nominal captures, dependency literal changes, producer/catalog relocation,
unused-source failure/correction and checkpoint restart under serial and worker
policies. Broad differential comparison already preserves ordered diagnostics
and Wasm for **626 cases / 3,756 invocations**, with zero tracked teardown;
six-policy retained qualification passes **2,106 revision samples and 648 guests
/ 41,208 original and edited calls**. The dedicated 8/32/128-wide fixtures add
**234 revision samples, 72 guests and 12,312 executed calls**. The broad corpus
also executes **192 guests / 10,362 calls**. All six policies (prior compiler,
serial default, explicit 1/2/4/8 workers) preserve diagnostic order and bytes.
Initial comparisons use the v1 compiler pin, which has the exact same
binary/identity as the final v2 pin; v2 corrects two TypeScript unit-call
arguments before the successful full gate. No comparison or failed-gate artifact
was overwritten.

## Release-to-release measurements

The immutable task-013 baseline is `candidate-worker-policy/`; the final
candidate is `candidate-refinement-query-v2/`, both under
`build/bench/cloud-principal-graphs/`. The baseline source revision is
`4c61f25635a157c3f8e729af9f712f275e9cabe6`; the candidate starts from
documentation closure `41cba81939cddecdfbfc92ff62ed18fe53e1c1da` and the exact
seven-file source map in
[the tracked pins](qualification/refinement-queries-pins.json). The candidate
milestone revision is recorded there after commit.

| Artifact                         | SHA-256                                                            |
| -------------------------------- | ------------------------------------------------------------------ |
| Baseline compiler                | `2c511afb7d3fa257f9538b534d93b175ec623e6e3656e1150ddb5ad3964679ee` |
| Baseline compiler identity       | `07583dbd69b791c698a0f877f1a3b4ae98918fca92a8c76654e997ed98c48f07` |
| Candidate compiler               | `cc8257fafaebaaa6c421b167220cb635db3062b8da3dd6e00064335801888526` |
| Candidate compiler identity      | `6fe193c0a27c3445398769693281c87eb93c805311828df957b86731b3dab368` |
| Candidate seven-file source map  | `5b6262c0602b61deee06b36bc5465663a4a4de78b42b69009b7a31a5ac32c7fb` |
| Baseline LLVM retained driver    | `0a01bf703b55392fc28f3191fb3a986e93bf92acc99823964b56a60b470f5d1d` |
| Candidate LLVM retained driver   | `ea76fc5dabdcb23f7c724d68a1bf92f302f7d444a0a1a0b17652c3fad3300ddc` |
| Identical retained driver source | `80aaaf020b77fb683fb6897bfc37f2927b23ccbe5c6c9a36a93dddf9a8481314` |

Fresh measurement runs **15 alternating pairs across 86 workloads**, or **2,580
fresh native compiler processes** with cache disabled and profiling absent.
Linux `getrusage(RUSAGE_CHILDREN)` measures child user+system CPU; wall stops
immediately when the process completes, before harness log writes/parsing.
Across workload medians, geometric candidate/baseline ratios are **1.0056 CPU**
and **1.0033 wall**. These host samples do not establish a speedup. Full sorted
15-sample CPU/wall/requested/peak distributions and stable semantic work
counters are in
[the 172-row fresh CSV](qualification/refinement-queries-fresh.csv). The public
CLI does not expose refinement statistics; its CSV field is `null`. The native
retained driver exposes the exact table counters separately.

| Fresh fixture  | CPU µs, old → new | Wall µs, old → new | Requested bytes, old → new |
| -------------- | ----------------- | ------------------ | -------------------------- |
| refinement-128 | 3164 → 3244       | 3379 → 3472        | 2,565,428 → 2,612,180      |
| refinement-32  | 1282 → 1368       | 1478 → 1626        | 711,914 → 731,082          |
| refinement-8   | 820 → 868         | 1025 → 1103        | 220,661 → 221,093          |

Across all 86 fresh workloads, requested traffic increases at most **4.10%**;
some capture cases decrease slightly. The migration makes no global compiler
allocation reduction claim.

Retained measurement runs **seven alternating pairs across 11 workloads**, 154
LLVM native driver invocations × 21 rounds × population/no-op, edit, revert and
no-op, totaling **12,936 native phases**. Another **462 CLI samples** cover
fresh build, cache population and process restart. Each driver measures
`getrusage(RUSAGE_SELF)` across prepare, output digest, commit and candidate
teardown; all process threads are included. Fixture loading, Session creation
and JSON formatting are excluded. Peak/live backing bytes include the retained
old revision and the candidate while both are live. All initial/edited/reverted
bytes match the baseline; retained bytes plateau after the first round and all
154 driver teardowns report zero live bytes.

[The 154-row retained CSV](qualification/refinement-queries-retained.csv)
contains complete CPU/wall/traffic/peak/live distributions and native refinement
snapshots. Reused-output no-op phases report zero compilation/query counters;
they perform no new semantic queries. Per-phase CPU/allocation deltas measure
the no-op itself. The pin manifest contains
all entry/edit/dependency fixture hashes, both complete driver source maps,
library hashes, scheduler settings and measurement-helper/report hashes.

| Retained fixture / phase   | CPU µs, old → new | Retained live bytes, old → new | Peak overlap bytes, old → new |
| -------------------------- | ----------------- | ------------------------------ | ----------------------------- |
| refinement8 / population   | 878 → 916         | 64,459 → 68,051                | 88,239 → 91,167               |
| refinement8 / edit         | 253 → 261         | 53,075 → 59,219                | 132,999 → 144,983             |
| refinement8 / noop         | 17 → 17           | 53,075 → 59,219                | 63,887 → 70,271               |
| refinement32 / population  | 1447 → 1749       | 205,703 → 218,655              | 257,409 → 268,545             |
| refinement32 / edit        | 709.5 → 716.5     | 190,359 → 196,503              | 436,453 → 448,437             |
| refinement32 / noop        | 22 → 23           | 190,359 → 196,503              | 205,485 → 211,869             |
| refinement128 / population | 3763 → 3830       | 777,400 → 835,184              | 954,773 → 1,005,109           |
| refinement128 / edit       | 2643.5 → 2685     | 719,912 → 726,056              | 1,623,910 → 1,635,894         |
| refinement128 / noop       | 44 → 44           | 719,912 → 726,056              | 752,689 → 759,073             |

Population of refinement widths 8/32/128 retains 10/34/130 complete records,
464/1,424/5,264 payload bytes and 6,952/27,736/110,872 actual buffer bytes.
Their local lookups inspect 8/32/128 positions for 8/32/128 local hits. Each
steady edit/revert inspects two retained positions, hits one and declines the
changed source candidate; the current table has two records, 144 payload bytes
and 6,816 capacity bytes. All baseline hit/decline choices and semantic work
counts are preserved. Across all 11 retained fixtures the largest recorded
storage snapshot is 130 records, 10,256 payload bytes and 110,872 buffer bytes;
no measured workload saturates the table. Deliberate saturation/collision/budget
laws separately exercise conservative fallback at the configured ceilings.

Both batches run `SCHED_OTHER`, nice 0, affinity CPUs 0–4 and cgroup quota
`400000 100000` (four CPU capacity). No new cgroup throttling occurs. Fresh
one-minute host load moves 0.309→0.650; retained load 0.332→0.480.
Distributions, small control overhead, capacity slack and live-revision overlap
remain visible; this is qualification of bounded migration, not default-worker
enablement.

## Commands and remaining scope

With Zig **0.17.0**, qualified commands are `deno task test:compiler`,
`deno task lint:zig` and `deno task package:check`. The focused native batch
uses `zig test zig-native/src/production_suite.zig -fno-llvm -Osafe` with
filters `owned query`, `refinement`, and `source template`; the dedicated
executed-Wasm law uses the normal Deno guest permissions and pinned release
compiler. Local raw logs are `query-table-full-gate-v2.log`,
`query-table-analyzer-v2.log`, `query-table-package-check-v2.log`,
`query-table-focus-v6.log`, `query-table-fresh-measurement-v1.log`, and
`query-table-memory-measurement-v1.log` beneath the evidence directory. Root's
ignored comparison, execution, retained qualification and measurement helpers
are preserved there alongside immutable pins. Essential distributions and input
identity are tracked outside `tasks/`.

Only refinement storage and indexing migrate here. No wire-format revision,
portable query handle, eviction/sharing mechanism or additional principal,
selected-specialization, source-validation or executable adapter is claimed.
Tasks 016–020 own those migrations. Private gdev and the historical boxed
compiler remain absent; tasks 002/084 retain their external qualification gates.
