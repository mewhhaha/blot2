# Evaluator writing frontier

Source-only checkpoint. No Goose or Zig build, compiler invocation, test,
formatter, check, or other verification was run for these ports. Written code
is not a qualification result.

## Production passes written

The following modules contain their production algorithms and data contracts,
not just declarations:

- body_recipe: complete source visit orders, bounded planning, decline caches,
  callable traversal and ordinary/reference replay walkers.
- closed_evidence_import: semantic-to-inference copying, lexical binder frames,
  quantified obligations, scoped operations and owner-local memoization.
- closed_local_value: finite closed initializer/data-shape proof and dependencies.
- closed_source_types: recursive closedness facts and rollback/epoch invalidation.
- eval_collection_growth: persistent spans, two-ended geometric growth and branches.
- eval_indexed_builder: finite private construction proof and bounded edit plans.
- eval_ragged_count: complete read-only scalar/borrowed-handle counting interpreter.
- eval_values: immutable values, closure/record metadata, snapshots and exact
  collision-checked record-shape indexing.
- evidence_import_cache: owner/generation/physical/depth cache activation.
- evidence_projection: lexical projection equality with bound-depth shifting.
- given_equations: bounded symbolic equivalence normalization and effect copying.
- implementation_rows: complete invocation-local witness and handler reconstruction,
  fresh solver ownership, typed normalized/frozen graph copying, certified
  closing, equation solving and shared projection-budget accounting.
- selected_query: complete typed selected-proof records and publication adapter.
- implementation_evidence: complete implementation selection, projection,
  prerequisite/fact proofs, nominal fields, invocation facts, trace, rollback,
  unrestricted associated-type proof and snapshots.
- implementation_patterns: fresh instantiation, rigid/nonrigid matching and overlap.
- implementation_predicates: primitive facts and invocation-row classification.
- implementation_trace: bounded candidate/step records and truncation.
- instance_arguments: ordered exact identity interning and independent owned copies.
- lexical_capture_inputs: complete canonical graph traversal, aliases, cycle and
  budget boundaries, typing copies and key-cache ownership.
- parallel_allocator: typed reusable-pool operations with ticket locking.
- plain_catalog: positive bounded immutable catalog proof.
- pool_leases: every source Field has a concrete typed reusable slice pool,
  allocation/copy/conversion/share/free functions, generation-checked lease
  references, actual last-reference free_slice and metadata reuse.
- purity_type_key: frozen UTF-8 counted TypeKey grammar and canonical row names.
- region_arena: real reusable byte blocks/bins, remapping, reset, lease pooling,
  retained-capacity policy and costs; typed compiler tables remain lexical owners.
- scheme_membership: small linear lists, bounded sorted indexes and source identity.
- scope_components: complete bounded reachability, ancestor discovery and SCC merge.
- semantic_evidence_import: complete graph/row/label import between independent owners.
- semantic_handles: distinct fixed wrappers for each numeric authority domain.
- semantic_job_batch: copied packet execution, contained worker joining, slot
  outcomes, OOM/decline/cancellation handling and publication after join.
- semantic_parallel: independent-record ownership, retention, cloned cached
  answers and exact counter aggregation around the packet batch.
- source_owners: complete bounded declaration containment index and cache.
- type_evidence: complete semantic graph validation/interning, quantifier goals,
  exact hash collisions, scoped/associated projections, owned memo budgets,
  type/row matching with multiset backtracking and rollback, legacy prerequisites,
  abstractness, snapshots and cloning. Wire tags retain holes 18/19/22.

## Still unwritten

- canonical_specialization
- completed_specialization_query
- core_eval (14,608-line Zig source): public value/diagnostic/options metadata,
  caller-dependent source traversal, typed callback descriptors, Session fields,
  source catalog/field indexes and fresh/shared Session initialization written;
  main execution, queries, principal graphs and ClosureRegion still WIP
- implementation_admission
- selected_implementation_admission
- specialization (delegated to backend port agent)

These remain required. The evaluator is not complete until they are implemented
and integrated. No file-inventory count is a whole-evaluator completion claim.

## Ownership and integration contracts

All mutable multi-table contexts use typed caller-owned array references.
Identity-bearing owners have process-local owner_id values from fresh_owner_id;
view/borrow copies keep the identity, independent copies get a fresh one.
Frozen snapshots contain const slices. No compiler tables are byte-cast.

- Type evidence: init receives effects Store plus nodes/extra/next/buckets,
  projection_owners/projection_quantifiers, quantifier_goals/obligations owners.
  SnapshotTables is caller-owned; clone(source,destinationStore) copies into an
  independent already-initialized context. match is spelled match_.
- ProjectionResolver<R> holds a typed context reference, remaining budget and
  enabled flag. R.resolve(identity,member,args) returns (Id,Error). All projector
  and matcher entry points retain this authority explicitly.
- Implementation evidence: init(Tables) binds typed proof/argument/member/edge,
  active/provisional/mapping/row, memo and fact owners. Its Host must provide
  units, associated_remaining, evidenceStore, implementationRead,
  implementationLegacyPredicate and diagnosticIdentity. The last hook explicitly
  returns an absent identity for hosts without diagnostic rendering metadata.
- eval_values init(Tables,evidence,buffers) receives initialized evidence and
  persistent collection owners. Record shapes use hash buckets plus numeric
  links; findRecordShape/saveRecordShape compare exact field-name arrays.
- Lexical Inputs own runs in concrete typed reusable[] pools; deinit really
  returns every run. Cache keeps canonical words, not live handle authority.
- Pool leases expose alloc_FIELD/dupe_FIELD/converted_FIELD/free_FIELD for every
  original Field, e.g dupe_values and dupe_evidence_nodes. converted_FIELD<C,F>
  takes a compile-time converter. Leases contain generation-tagged indices.
- Purity Context<S> requires S.origin(identity,kind) -> (Identity,Error), and
  S.arguments(identity,kind,args) -> (owned IDs,Error). identity_bytes is a
  caller-owned stable byte table for composed diagnostic names.
- Scratch inference uses check.types.withStore callback ownership; semantic
  copying uses the principal_type_graph lexical owner helper agreed with root.

## Copied worker integration

Goose workers cannot receive Session/Core references. semantic_job_batch.run
requires a concrete packet Context with encode(request) and decode(reply), plus
its compile-time worker executor. The encoder must include every immutable
source/context fact read by that executor. The executor reconstructs a private
Session, returns a copied result packet and a cancellation flag, and never
publishes directly. semantic_parallel.run accepts the same packet adapter.

The source's shared-pointer work queue is represented by joined waves of at
most sixteen contained workers, each receiving a full copied request/context.
All successful outcomes survive sibling failures; pending work becomes cancelled.
This changes thread/scratch reuse costs; it has not been measured or qualified.

Goose reusable pools and generic worker support may exceed the current bootstrap
compiler's implementation. They are specified target-language features, and
are not replaced with unsafe allocator or compiler-oracle bridges.

Further source-writing after checkpoint f777675d: canonical_specialization now has
its complete production replay and cache pass. Core Session execution now includes
all expression dispatch, named and curried invocation, constructor and primitive
execution, capability escape checks, provider scopes, request loops and unwind,
resolver execution, staging, collections and SIMD, updates, patterns and loops,
implementation template/dictionary selection, structural evidence matching,
typed value publication and record member selection. The inference-facing Session
entry points, retained receipt queries, CallSummaries and ClosureRegion remain
under construction. No verification has run.

Suspended inference regions will transfer all typed solver and Scratch state to
an owned RegionSnapshot only at a real scheduler wait. Resumption preserves the
same logical region/solver owner IDs and chronological handles; physical borrow
caches must be invalidated when owners move. This preserves scheduling and fuel;
the snapshot copying cost remains unmeasured.

## Current source construction continuation

The core evaluator production writing pass now also includes field/member
selection and mismatch diagnostics; record updates; freezing retained capture
graphs; entry inference; the full principal graph description, normalization,
cycle/pay admission and replay algorithms; completed/checked/constant/public
header traversals; typed persistent FrozenCopy map frames; mandatory scheme
leaves; summary admission/expansion; and the serial SCC scheduler. Serial jobs
transfer exact RegionSnapshot ownership only when the selected work changes;
they keep the live region for consecutive solver steps. Restoring a snapshot
adds no semantic inference credit. Snapshot physical copying cost is unmeasured.

The serial scheduler and mutable graph readers retain their original ordering,
limits, rollback boundaries, missing-versus-declined query states and observer
publication decisions. The parallel component worker packet/codecs and several
Session inference/receipt/ragged entrypoints are still being written. The three
admission/query leaves listed above remain pending. No build, test, formatter,
compiler invocation or checker has run.

Source construction issues still requiring edits before this pass is complete:

- Goose has no `defer`; existing first-pass cleanup clauses in eval/parse must
  become explicit ordered cleanup along every control-flow exit.
- Goose specification 7.8 forbids nonfixed locals in a recursive call cycle.
  Recursive evaluator/graph/type owner wrappers need fixed typed pooled
  descriptors rather than lexical Grow/dictionary owners. Exact suspended
  solver snapshots are already separate ownership transfers.
- Stable Grow backing for immutable recipe/source-owner slices needs actual
  reusable slice leases for deinit/reset; clearing Grow-only owners is not a
  legal reset. Resetting all cache scalars must accompany the context rebuild.
- Worker Core images use `support/core_packet.goose`, namespace
  `blot_core_packet`, parent-owned. `encode(module,outputGrow)->Error`;
  `decode(bytes)->Owned,Error`; `Owned.module` borrows its own lease until
  `Owned.deinit()`. No Session references cross worker queues.

New caller-facing contexts: `CallSummaryTables` supplies all key/job/stack,
active-owner, eligibility/header, principal-decline and principal-key maps plus
`scope_components.Graph&`; `initCallSummaries(tables)` returns the fixed view.
`initRegionStorage(allocation_owner,source_owners,definitions,units)` takes a
stable nonzero compiler/session allocation identity. `SpecializationCaches`
contains the fixed per-cache contexts and typed validated-call/plain maps;
`RetainedRecords` borrows the two receipt Grow/shrink arrays.
`reset(session,tables,units)->Error` is written and retains these caller contexts;
cache backing/scalar cleanup alignment above remains outstanding.

The selected_implementation_admission production module is now written in full:
closed declaration reconstruction and snapshot reconstruction both recursively
compare every supplied proof/member/predicate/prerequisite against newly derived
authority, with shared budget and memo rules. `core(module,remaining)->Error`
and `snapshot(units,evidence,supplied,remaining)->Error` preserve the original
allocator-free source signatures. TypeEvidence.withStore and the new
ImplementationEvidence.withStore supply typed entry lifetimes. It has not been
verified. implementation_admission and completed_specialization_query remain
pending.

`withSession<C,F>(units,allocation_owner,context)->Error` is now source-written;
F(context,session) runs while every concrete owner remains in scope. The free
`evaluate` additionally receives a caller-owned diagnostic byte Grow array so
its result can retain detail after the Session scope closes. Retained closure
inference/specialization, receipt query/judgment, partial array members,
principal-evidence observation/fallback, startup coverage, RaggedFacts and the
counted ragged path are now source-written. Worker component codecs/execution
and the ownership/cleanup adaptations recorded above are still pending.

completed_specialization_query.goose now has the full production writing pass:
owner-paired source admission, cached multi-root inspection, exact input/member
matching, scalar/call/view/plain observations, independent proof recovery,
transaction preparation, whole graph materialization and retained receipt
relocation. `State` additionally takes caller `Tables` for independent records
and joined parallel batch buffers; allocation identity is numeric and nonzero.
Its copied-packet adapter calls the agreed parent-owned
`independent_call_proof::runParallel<State,G>` contract. `State.semantic` is the
fixed/defaultable pooled Importer supplied by the parent reuse port. This module
is source-written only, with those parent APIs still being written/aligned.

`withSharedSession<C,F>(parent,allocation_owner,context)->Error` now shares the
same typed factory as withSession and chooses exact initShared. Mutable tables
start empty; immutable offsets/field catalogs and catalog identity remain tied
to the parent. No compiler or verification call has run.

implementation_admission.goose now has the complete production writing pass:
associated declaration equations, mandatory contract prerequisites, private member
signature recipes, template body/reference reconstruction, head scope and
unrestricted associated-type checks, complete member/predicate ownership,
head-only overlap/orphan checks, exact public/Core/principal proof comparison and
original producer equivalence. Core and principal owners use explicit typed
overloads where their authorities differ. No evaluator production leaf is now
wholly unwritten. The core parallel component execution/packet path and recorded
cleanup/recursive ownership work remain unfinished; source presence is not a
claim of a build or qualification.

Shared copied-worker construction is now written in eval/worker_packet.goose:
bounded little-endian scalar/record helpers, full Core catalog ownership and
whole-catalog validation, runtime identity images, semantic evidence images,
exact source-order scalar seeds and independent certificate payloads. New
support/evidence_packet.goose owns typed generation-checked evidence snapshots.

Parent-assigned reuse/independent_worker.goose now supplies the full
`blot_reuse_independent_call_proof::runParallel<S,G>` adapter and copied worker
execution. It carries complete old/current Core and identity/evidence images,
old/current private certificates, options/depth/request and completed scalar
inputs; it validates complete local catalogs and rebuilds the local Gate before
calling acquire. Current scalar seed tables are constructed in source slot
order. Gate flags and addresses are never serialized. All children join before
coordinator result decoding/publication; only out_of_memory is classified as
out_of_memory, while bounded packet declines remain declines. Backend payloads
unused by independent semantic inquiry are absent from the reconstructed Pools;
Importer.initIndependentQuery must retain the agreed semantic-only contract.
Import reuse.independent_worker to register this namespace extension. This is
still source construction, without a compiler/check invocation.

The remaining core parallel SCC path is now production-written, with full
component selection/SCC eligibility, deterministic sorting and budget split,
joined copied worker execution, counter aggregation, independent-source checks,
private semantic import and whole-component publication. New
component_worker.goose carries all Core/evidence inputs, exact lexical typing
and scalar seeds, recreates the private Session and exports every completed
member in the original order. Semantic component IO presence is explicit
`Session.semantic_io_enabled` (default false); native caller policy enables it.

Caller-owned evidence tables use prepareCommit/commit for the original staged
store swap: all destination capacity is touched before publication, then exact
ordered runs and dictionary slots/counts are copied with the logical staged
owner transferred. No stage references escape. This preserves semantic IDs and
publication boundaries; the extra physical copy cost is unmeasured. A later
fixed pooled Store descriptor can transfer these same runs directly. Full
source writing is still not a build or semantic qualification; recursive-owner
and cleanup work recorded above remains pending.

The source construction pass now includes concrete pooled evidence owners. `type_evidence.Store` and `effect_evidence.Store` hold fixed descriptors into generation-checked reusable metadata slots; each typed table owns a separately reusable capacity run. `init()` creates a new owner; descriptor copies borrow that owner, `clone` creates an independent owner with identical ordinals and raw hash slots, and `deinit` physically releases capacity and metadata. Immutable snapshots and views retain their original slice contracts. Publication transfers prepared table capacities rather than copying through a second allocation stage. Table length/mutation access remains `.len`/methods; indexing, iteration and borrowed slice arguments use `.items`.

`PooledMappings`, `PooledRows`, pooled closed/semantic importers, and the projection cache now supply fixed shared metadata for recursive callbacks. The ordinary and pooled evidence-store callback factories share that implementation. Native and pooled evidence matching overloads retain matching budgets, rollback frontiers and memo publication. `implementation_patterns.instantiateInto` fills caller-provided variable and row runs in the original allocation/substitution order. `implementation_rows.reconstruct` accepts both native and pooled mapping descriptors.

Evaluator frames now carry pooled value/mapping descriptors by value, with stable invocation IDs for frame identity checks. `closedNodeSlots` and `attemptClosedNodeSlots` accept the backend's typed dictionary slot slices and preserve closed-node failure/diagnostic behavior. Their evaluation paths own no lexical Grow arrays or dictionaries across expression recursion. Other evaluator scratch ownership remains in progress: region/solver owner factories, nested principal graph readers, callback resolver references, and several temporary collection buffers still require the complete recursive ownership pass. The check-side native TypeStore factory is a shared remaining boundary, flagged to its owner.

Region profiling is now source-written: inference phase entry/restoration, heavy-region source locations, inclusive caller census, and preserved timing state through actual scheduler suspension. Goose call-site function/line metadata is passed explicitly because Goose has no Zig `@src()` intrinsic. Its timing cost and the physical snapshot/capacity changes remain unmeasured.

No compiler, build, test, formatter, checker, or runtime verification has run. These are written production passes and outstanding construction requirements, not qualification results.

Further fixed ownership construction now covers the solver worklist queues (all table headers, free-link state, counts, generation/clock observations and statistics), scope-components graph, evidence-import cache, closed-source caches/facts, scheme membership cache, region scratch arrays/maps, collector tables and rank-evidence stacks. Raw dictionary slot/count transfer remains explicit for every suspended table. The active region record and Worklists are reusable typed metadata slots. Region metadata receives a copied solver descriptor; the check-side TypeStore backing-owner conversion remains a shared prerequisite. Session lifetime/backing owners and retained callback resolver contexts still need the complete recursive ownership pass, so these changes do not establish whole-engine Goose validity.

Completed-query candidate proof/plain tables and temporary roots/publication/request buffers are also pooled now. The copied independent worker still receives the full validated packet boundary. Its parent candidate releases private proofs and staged receipt state on every result, and restores caller parallel-table frontiers after joining.

Parser integration now uses the durable pooled Tree supplied by the root task, and a durable pooled symbol Pool. The symbol flags `read_only`/`missing_name` remain on each descriptor, preserving a worker's independent flag state while it borrows the same immutable storage. Grammar recursion and source-operator traversal temporaries use typed reusable buffers; validator locals use a global metadata header. The outer parser fixity table stays within the nonrecursive entry scope. Private Wyhash duplication was removed in favor of the shared oracle-shaped byte-stream implementation.
