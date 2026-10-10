# Typed reuse queries

This is the approved design for task 014 and the implementation contract for
[015](../tasks/015-migrate-refinement-queries.md)–[020](../tasks/020-persist-complete-semantic-artifacts.md).
It specifies a migration; the common table and portable query records are not
implemented by this document. Existing receipts and validation gates remain the
production proof boundaries until their replacement passes parity.

## Claims and owners

One table shares indexing, dependency recording, limits and transactions. Its
query kinds retain distinct validity judgments. A semantic interface does not
certify a function body, executable fragment or evaluated value. A source
certificate certifies its exact validation context, never semantic reuse.

The proposed tagged representation is `QueryKey { kind, schema, payload }`, with
`QueryValue` tagged by the same kind. A typed `Handle(kind)` identifies an
immutable complete record within its owning table; it is not a ValueId, solver
variable, pointer or portable identity. Each record owns its canonical key,
result representation, ordered dependencies, replay publications and diagnostic
provenance. The table owns bucket vectors and record storage. Candidate builders
own scratch and unpublished data. Published revisions hold leases on immutable
records; their indexes and revision-specific validation states remain separate.

| Query kind        | Complete key                                                                                                                                                            | Owned result and validity claim                                                                                                                               |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Refinement        | body or closure code identity; expected shape; complete ordered type/row seeds; mode; exact semantic options, depth and applicable resource limits                      | Solved type/row evidence and selected source targets, with complete refinement observations; a selected semantic judgment                                     |
| Specialization    | task-008 canonical code/evidence/capture graph; expected evidence; selected/inferred/entry mode; exact options, depth and limits                                        | Rooted output reconstruction plan, immutable metadata/evidence graph and complete receipt; a selected closure judgment around the current inputs              |
| Principal         | source declaration/code identity; explicit open-residual versus complete-proof submode; type/row binder structure; exact options; complete observed principal input set | Owned source-normalized open principal/residual graph or complete evidence result, distinguished by claim submode; empty and nonempty results remain distinct |
| Source validation | canonical project settings/aliases; ordered producer identities, namespace/catalog image; source/import outcomes and foreign bounds                                     | Owned checked context image, dependency certificate and module/source pairing; source admission only                                                          |
| Executable        | normalized function input/instructions; signatures, imports, globals, tier and representation policy; code/capture identities and transitive lifetime summaries         | Owned executable operation/optimization graph and relocation/lifetime metadata; executable behavior and machine representation                                |

Evaluated values are a separate operational claim. Session slots, chronological
views, validated calls, demand memos and plain-nominal facts remain owned by the
live Session. A future evaluated-value query needs its own complete value
inputs, effect/staging proof and rooted owned output graph. It cannot use a
principal or source-validation handle as its result certificate. Created demand
identity and once-per-creation sharing survive every migration.

Within one immutable Core/Session owner, stable code IDs and interned evidence
IDs may be local key terms. Cross-owner keys require canonical producer paths,
checked source pairing, owned evidence/code graphs and canonical graph ordinals.
Record storage preserves physical field order; semantic evidence preserves field
names and nominal identities. Capture traversal preserves scalar bits, nested
code/mappings, ordered slots and alias partitions. Complete settings include
modes and limits that affect admission or diagnostics. Unknown dependencies,
open region binders and unsupported mutable/generative inputs decline sharing.
No numeric ID is assumed to mean the same producer after reordering imports. An
open residual graph is an instantiable source template, not a completed selected
proof. The Principal claim submode is part of key/value/dependency tags; no
complete-proof adapter accepts an open-residual result. Current observed
principal input sets retain their scalar/plain/call rules, rather than being
replaced by an assumed complete live-value graph.

## API and exact indexing

The implementation will expose the following operations, with typed adapters
rather than a callback that may invent a validity judgment:

- `begin(kind, request, candidate_epoch, limits) -> Builder`: create a private
  recording inquiry with an owned key and the current owner/validation context.
- `read(builder, dependency)`: append an observed fact and its typed claim.
  `stage(builder, publication)` records ordered facts to publish on successful
  replay; neither operation publishes an incomplete result.
- `lookup(kind, key, current_context) -> Hit | Miss | Declined`: select a
  bucket, compare full keys, validate dependencies through that kind's gate and
  prepare import/reconstruction. A hash match alone never returns a Hit.
- `complete(builder, owned_result) -> Candidate`: require solved obligations,
  complete observations and transferable ownership. Unknown/nested observation,
  quota exhaustion or speculative failure prevents completion.
- `prepare(candidate, current_context) -> Prepared`: revalidate inputs and
  reserve every destination graph, map, fact, index and optional receipt
  capacity.
- `publish(prepared) -> Handle(kind)`: atomically install the immutable result
  and ordered publications without allocation. `abort` releases candidate data.
- `retain(handle)` / `release(handle)`: manage explicit immutable-owner leases;
  eviction releases only unleased records and their index entries.

Fingerprints select buckets for keys, dependencies and results. Exact equality
compares the complete canonical representation, including kind/schema, graph
shape, binder/alias relationships, effects, modes and options. Equality never
compares native padding or an allocator address. Deliberately equal fingerprints
for unequal scalar bits, nominal producers or aliases must remain misses.
Fingerprint equality cannot replace full byte/graph comparison on restart.

Buckets store record positions, not pointers into growing arrays. Candidate
order is explicit and stable: the adapter supplies the legacy first-match order,
with newest-first local refinement chains and each portable index's existing
traversal order. Completion time never supplies that order. Duplicate keys with
different observations remain independently admissible candidates. Migration
does not silently collapse their proofs or change which valid result is tried
first. Equivalent duplicates may share an immutable value only after exact
result and publication equality, with deterministic source-order tie breaking.

## Dependencies and early cutoff

A dependency is a tagged owned observation with producer identity, claim kind,
exact expected input/result representation and any chronology/owner bounds:

| Dependency            | Recorded facts                                                                                                  |
| --------------------- | --------------------------------------------------------------------------------------------------------------- |
| Source/body           | exact current declaration or body pairing, plus source diagnostics that must still run                          |
| Interface             | complete canonical type/effect/principal graph; body identity is not implied                                    |
| Capture/value         | rooted current graph, scalar bits, storage and alias/generative identity where supported                        |
| Namespace/catalog     | ordered imports, resolution successes and failures, declaration/category identities and bounds                  |
| Dynamic semantic fact | scalar slot evidence/state; call-proof presence; typed-view presence; plain-nominal absence/presence/value      |
| Executable/lifetime   | exact instructions and called code identity; machine inputs and transitive allocation/escape/lifetime summaries |
| Query result          | typed producer handle with an owned exact result image; revision number alone is not a validity proof           |

Positive and negative observations are explicit. Absence of a plain-nominal fact
is different from a present false fact. Replay validates reads and stages the
same ordered writes. A now-present call proof may be admitted by an existing
local refinement rule only when that rule proves monotone completed-call growth
cannot change the result and all required publications are present. That
exception is typed and owner-local; it does not apply to arbitrary absence facts
or portable selected-value observations. Principal empty-result admission keeps
its current stricter gate until separately qualified.

A dependency change marks consumers for revalidation. Recompute the producer in
private storage; if its typed canonical result and required publications are
exactly equal, consumers that read only that claim may stop invalidation at this
edge. This is early cutoff. Consumers of its body, evaluated value or executable
claim still invalidate when those inputs change. Type equality is never a
shortcut around checking unused source, effects or current implementation
bodies. When a complete dependency set cannot be reconstructed, use ordinary
checking. No graph-wide dirty bitmap or broad namespace hash becomes a semantic
certificate.

Results, dependencies and publications are bounded by explicit `Limits` for
record count, key/result/dependency bytes, graph nodes/edges, traversal depth,
lookup work and retained capacity. Admission charges attempted work, including
declines. Eviction and saturation fall back to ordinary checking. The migrated
implementation must choose and measure defaults; this specification does not
claim a new memory target has been met. Logical arena requests, backing
requested bytes, durable retained capacity and process RSS remain separate
measurements.

## Transactions, cycles and diagnostics

Builders are private to a worker or inquiry. Every key/result graph owns all
transferred data; local type variables and chronological views never escape an
active solver. Import freshens open binders per inquiry. Immutable closed graphs
may be shared only through their owner's lease. A prepared replay validates the
exact read set immediately before publication under the current revision epoch.
Epoch change, cancellation or a conflicting fact discards/revalidates the
candidate. Allocation failure during preparation publishes nothing; capacity may
grow, and the same live Session must be able to retry. Failure after creating
private child candidates leaves them owned and releasable, never visible as a
completed parent proof.

Queries have `absent`, `building`, `waiting`, `complete` and `declined` states.
A recursive edge to `building` does not return a provisional successful answer.
Known recursive semantic components use task 007's bounded joint collection and
all-member completion; no member publishes before all required obligations and
external dependencies are proved. An unsupported query cycle declines reuse and
runs the authoritative checker. Executable relocation cycles need their own
complete code/lifetime graph; they cannot borrow a semantic SCC's certificate.
Attempt/work/depth limits remain part of the authoritative failure boundary.

Workers return private complete candidates, with local import maps and allocated
storage. The coordinator validates/rebases them, reserves shared publication
space and commits in deterministic source order. It selects diagnostics in the
same order as sequential checking, independent of which worker finishes first. A
duplicate worker result does not multiply demand creation, fact publication or
side effects. Task 012/013 must qualify scheduling and policy separately; this
design does not enable parallel default behavior.

A failed candidate revision retains the last-good published revision and its
leases. Candidate errors carry owned source provenance and the original typed
category, spans and details. Miss/decline reasons are bounded instrumentation,
not replacement language diagnostics. Failed/incomplete semantic results are not
portable successful records. Revision-local failure memoization may avoid repeat
work only for the same exact inputs and must not suppress mandatory checking in
a later candidate. Cancellation and OOM are never durable semantic outcomes.

## Migration destinations

| Existing owner/index                                                                                                          | Destination and preserved boundary                                                                                                                                       |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `refinement_receipt.Record`, `Memo`, artifact refinement index                                                                | task 015 refinement adapter; current shape/seed/source/scalar/plain/call admission and first-match ordering                                                              |
| `specialization_receipt.Record`, `completed_specialization_query.State`                                                       | task 016 selected specialization adapter; current portable graph matching/importer, exact current captures and atomic replay                                             |
| `canonical_specialization.Cache`                                                                                              | task 016 Session-local specialization index/plan; local IDs stay local and mode/options remain exact                                                                     |
| `Session.specialized_closures`, `typed_views`, `validated_calls`                                                              | operational Session output/fact memos retained behind typed replay; proof reuse never returns stale captures                                                             |
| `principal_proofs`, `principal_inputs.Key`, `principal_archive.Reader`, `principal_evidence_reuse`                            | task 016 principal adapter; empty/nonempty and source/selected claims remain distinct                                                                                    |
| Session principal/source-normalized graphs, lexical summary and component jobs                                                | task 016 local principal adapters; lexical/component scheduling remains task-006/007 Session machinery with private open binders and component publication authoritative |
| `revision_inputs.Snapshot`, `dependency_certificate.Certificate`, frozen dependency/interface validation, `shared_query_gate` | task 017 source-validation adapter; exact options/bytes/import outcomes/context and same-owner lease checks                                                              |
| Artifact capture/replay, `optimized_bodies.Capture/Matcher`, code checkpoints                                                 | task 018 executable adapter; instruction/source/lifetime equality and relocation/representation gates                                                                    |
| Session value slots, demands and plain-nominal state                                                                          | Session operational state; no portable evaluated-value migration is authorized by interface validation                                                                   |
| Solver occurs/resolution caches, chronological substitutions and indexed constraint worklists                                 | active region internals; no query-table result contains their IDs or substitutes for their laws                                                                          |

Task 015 implements the common owned record/index/transaction primitives with
refinement first. Each following migration retains the old path as a comparison
oracle until native, executed-Wasm, retained edits, OOM and portable parity
pass, then removes its superseded index. Dual recording is bounded and does not
change production diagnostic order. Task 020 qualifies aggregate lookup work,
retained capacity, repeated revisions, failure recovery and
fresh/retained/restart output. Keep each claim-specific gate until its
replacement has the same proof, rather than removing gates because storage is
unified.

## Portable representation and compatibility

Portable records go through [dependency_format.zig](src/dependency_format.zig),
inside the owned dependency/checkpoint envelope. The current format version is 1
with reflected schema and bounded decoding; this document does not change it.
Adding a query payload changes the schema. Use a deliberately versioned tagged
payload and update the envelope version when wire interpretation changes;
unknown versions/schema/kinds conservatively fall back to fresh compilation. No
implicit reinterpretation of an older receipt as a stronger query claim is
allowed. A transition reader may translate an old receipt only through its
existing gate, then produce a fully owned current record.

Encode stable producer/catalog identities, owned normalized source/evidence/code
and capture graphs, ordered typed dependencies/publications, modes/options and
applicable limits. Native IDs are translated to validated artifact ordinals;
local Session IDs, allocator pointers, hash-map state, solver history, borrowed
slices and `building` records are never serialized. Unsupported local plans are
omitted and simply recomputed after restart.

Decode enforces envelope length, integrity, schema/version, allocation and
traversal bounds before exposing a candidate. Validate every index, tag, graph
edge, ordinal, alias reference, namespace/catalog category and foreign bound.
Recompute fingerprints; persisted fingerprints are hints. Revalidate the exact
current source/settings/import context and claim-specific inputs before hit
publication. Truncation, mutation, inconsistent cycles, stale identities or
out-of-budget records yield conservative optional-cache fallback without partial
facts. Explicit user-requested imports preserve the current typed import error
contract; they do not silently become optional cache misses. Runtime/source
errors from fresh checking retain their ordinary diagnostics.
Compiler/library/options/representation identity prevents incompatible reuse.
Corrupt caches never replace the last-good revision or authorize unsafe code.

## Acceptance walks

| Change                                                                      | Required table behavior                                                                                                                                                                           |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Literal 20→21 in a captured constant, same U32 interface                    | Source/value observation changes; selected key or validation misses. Rebuild around 21. An interface-only dependent may cut off after exact interface comparison; code/constant consumers cannot. |
| Body `add x 1`→`add x 2`, unchanged U32→U32 type                            | Check the new body and its diagnostics. Principal-interface equality may stop only interface edges. Executable body edges invalidate; runtime calls must return the new value.                    |
| Two equal fresh captures, then one scalar bit changes                       | Equal canonical graphs may hit and reconstruct current handles. Changed bits miss even under a forced fingerprint collision.                                                                      |
| Shared Box pair→two equal separate Boxes, same type                         | Alias partition changes and selects a distinct key/decline. Nominal/provider/demand creation identities remain authoritative.                                                                     |
| Namespace alias/import target changes or a formerly missing import resolves | Re-read the ordered resolution outcome and producer identity. Source certificate misses despite identical numeric IDs or superficial interface hashes.                                            |
| Declaration/catalog reorders, signature superficially unchanged             | Validate bounds and stable source pairing, translate ordinals through the admitted importer, otherwise decline. Never resolve an external unit by blindly subtracting one.                        |
| Plain fact absent→present false, or call proof presence changes             | Apply the typed observation rule. Exact absence reads reject. The specifically proved local monotone-call exception retains its required publications; no general absence exception exists.       |
| One recursive member has an effect/type error                               | Publish no component member. Report the authoritative source-order error and leave the last-good revision usable.                                                                                 |
| Edit fails, then source reverts                                             | Discard failed candidate data and uncommitted publications. Reuse the last-good owned records only after exact restored-input validation; execute the recovered output.                           |
| Same fingerprints but unequal body/evidence/result                          | Full typed equality rejects or continues to the next candidate. No hash-only hit or early cutoff.                                                                                                 |
| OOM after private child preparation, before parent commit                   | All candidate owners release safely; published graph lengths/facts/memos stay valid. Retry the same Session or next revision successfully.                                                        |
| Restart with old schema, corrupted edge or exceeded bounds                  | Reject the cached candidate and compile fresh with ordinary diagnostics. No native handle or partial publication survives decoding.                                                               |

Review against [the language guide](../compiler/guide.md) and
[CONTRACT.md](CONTRACT.md) preserves mandatory source checking, chronological
ownership, alias/nominal identity, staging and demand creation. The
implementation acceptance suite must deliberately exercise all these walks,
first-match candidates, collision injection, deep/cyclic records, import OOM,
cancellation and stable source-order diagnostics. Private gdev remains
unavailable; this design makes no performance or implementation-completion claim
for tasks 015–020.
