# Evaluator source construction

This is an incomplete, unverified source-writing checkpoint. No Goose or Zig
compiler, build, test, formatter, checker, runtime, benchmark, or qualification
was run. Production algorithms being present does not establish Goose validity,
whole-engine equivalence, allocation-failure parity, or measured performance.
The Zig compiler remains the frozen oracle and is untouched.

## Production passes

All original eval production modules have a first algorithm pass, including
core_eval's entire pre-test production implementation and legacy task semantics.
The seven parse production modules likewise have full first passes. The eval
modules are:

- body_recipe, canonical_specialization, closed_evidence_import,
  closed_local_value, closed_source_types, completed_specialization_query;
- core_eval, eval_collection_growth, eval_indexed_builder, eval_ragged_count,
  eval_values, evidence_import_cache, evidence_projection, given_equations;
- implementation_admission, implementation_evidence, implementation_patterns,
  implementation_predicates, implementation_rows, implementation_trace,
  instance_arguments, lexical_capture_inputs;
- parallel_allocator, plain_catalog, pool_leases, purity_type_key, region_arena,
  scheme_membership, scope_components, selected_implementation_admission,
  selected_query, semantic_evidence_import, semantic_handles, semantic_job_batch,
  semantic_parallel, source_owners, specialization, type_evidence.

Specialization is owned by the backend task. The root task owns source_owners,
body_recipe and lexical_capture_inputs ownership conversions. All modules remain
subject to the outstanding source integration work below.

Core covers scalar/SIMD/collection evaluation, closures and patterns, all
provider/request/capability and legacy task execution, staging, associated
selection, diagnostics, principal graphs, inference, scheme requirements,
retained specializations and receipts, serial SCC scheduling, actual-wait
suspension, and joined copied-worker component publication. Suspension transfers
one logical solver instance; it preserves ordered tables, raw map slots/counts,
queue clocks/frontiers, solver IDs, quotas, caches and counters, rather than
restarting inference or copying on every solver step.

Shared additions are fully production-written at their current construction
frontier: support/evidence_packet, eval/worker_packet, eval/component_worker and
reuse/independent_worker. Both copied-worker boundaries encode full immutable
Core catalogs and evidence, rebuild worker-local owners and whole-context
validation/Gates, preserve scalar seeds and certificates, join all children
before decoding/publication, and distinguish OOM from bounded declines. Received
queue messages are copied to fixed typed reply runs before recursive decoding.
No live reference, solver authority or process-local pool handle is serialized.

reuse/dependency_closure and dependency_core_inputs have full production passes:
all fresh/moved/copied/mixed/shared/library freeze lanes, exact import and source
checks, source/payload key framing, closure/public validation, bounded foreign
owner propagation, padded final-context validation and live descriptor receipts.
Payloads use the root-owned dependency_payload Owner; relocation receives that
explicit mutation authority. Public freeze methods take a typed lowering
executor and return Owned<FrozenDependency>; snapshots adopt that owner.

## Ownership and APIs

Identity-bearing stores have process-local owner_id values. Borrowed descriptor
copies preserve identity; independent mutable owners receive fresh identity.
Private IDs and derived tables are excluded from wire images.

Evidence, effect evidence, values, collection growth and implementation proof
stores now use concrete typed reusable capacity runs and generation-checked
metadata. init/initPooled creates an owner; deinit physically returns its runs
and metadata. Values, proofs and providers expose initPooledRef for a durable
canonical descriptor. Evidence clone preserves source ordinal/probe layout in
an independent owner; prepared publication transfers capacity runs and logical
identity. Snapshot/View data remains immutable.

core_eval.initOwnedSession(units,allocation_owner) returns a durable nullable
Session handle; deinitOwnedSession releases its entire owner set. Session,
SessionTables, persistent contexts, caches, call-summary maps/jobs/stacks,
retained receipts, providers and implementation proofs live in global typed
metadata. Retry reset clears semantic contents and retains the outer owner
capability. allocation_owner is the stable nonzero compiler/session heap
identity across retries and old/current sharing, not a fresh identity per region.
withSession/withSharedSession, withRegion/withResumedRegion and withPrincipalGraph
pass callback context references only as direct arguments; wrapper records do
not retain cycle-local context references.

Buffer length/mutation uses .len and methods; indexing, iteration and borrowed
slice arguments use .items. Body recipes use recipes.at(index). Pooled mapping
and row descriptors share mutable global headers and expose .items. Frames copy
these fixed descriptors and use stable invocation IDs. closedNodeSlots and
attemptClosedNodeSlots accept the backend's typed dictionary slots.

Recursive collection/matcher/projector scratch uses typed fixed buffers/maps,
with per-function global headers wherever a visitor retains the header reference.
Temporary table contents and metadata are physically released on each exit.
Principal Copier budget counters live in shared global typed headers; callback
contexts retain copied Store descriptors and copy outer result records back when
necessary. CodeProjection has an inactive default plus physical/owned/static
payloads by value; stored fields use Option<CodeProjection>.

purity_type_key.initContext(types,source) owns only its own generated identity
runs. Context copies the fixed source/store descriptors; deinit does not destroy
the source adapter. Key/pack/nominal helpers return owned const byte runs with
release(key); recursive accumulation uses geometric pooled buffers. UTF-8 count,
TypeKey grammar, sorting and fuel rules remain source-shaped.

Parser Tree and symbol Pool now own durable typed pooled storage. Symbol
read_only/missing_name flags remain descriptor-local, preserving worker flag
isolation while borrowing the same immutable data. Recursive grammar and
source-operator scratch use typed reusable buffers; read-only observers accept
const owners. Source symbol hashing uses shared oracle-shaped Wyhash.

## Remaining construction and qualification

- Complete retained observer lifetimes: Tape/MemberTrace/Observation and recorder
  descriptor references stored in Session must root at durable typed metadata,
  including specialization refineFresh and nested principal/constant recording.
- Finish the recursive callback/reference and temporary-owner integration pass;
  the completed-interface ModuleRef work list and worker adapter boundaries need
  their final concrete owner alignment. Immutable slices must not outlive a
  growing table unless backed by retained immutable runs or a live store handle.
- Align root-written retained/project-check/snapshot/format APIs and partial
  Prepared transfer APIs with dependency_closure's explicit Owner contracts.
  CoreBuilder has agreed to return Owned<Core.Module>; parallel Input carries
  fixed Tree/Checked values. Driver wiring and native packet adapters remain.
- Finish nominal enum/codecs, .items observations and source/public API alignment
  across all port owners. Inactive frozen/projection variants must abort on
  observation and never constitute successful proof or graph admission.
- Source semantic limits and logical cleanup are written; physical native OOM
  translation/fault parity is unqualified. Typed pool and snapshot costs are
  unmeasured. Region profiling preserves inference scopes, inclusive census and
  heavy-source attribution, with explicit Goose call-site metadata.
- Sorting comparison order can affect budget exhaustion. Matching Zig's pinned
  stdlib comparator schedule with Goose's sort remains a qualification boundary;
  source algorithm inventory alone does not prove that boundary.

Verification is still explicitly deferred until all source writing is complete.
