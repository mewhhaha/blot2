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
