# Check port writing record

Writing phase only. No builds, tests, formatter checks or compiler invocations
have run. Source/compiler qualification remains pending until the complete
port has been written.

Completed writing passes (unverified):

associated_admission, check_scheme_import, closed_nominal_storage, collection_contracts, core, diagnostic_code, diagnostic_location, dictionary_owner, effect_authority, effect_evidence, effects, frozen_types, generative_schemes, numeric_proof_bodies, numeric_proof_contracts, numeric_proof_headers, numeric_proof_terms, ordered_membership, package_contracts, package_evidence, package_portable, package_row_facts, parameter_patterns, primitive_operator, quantifier_goals, rank_equal, rank_portable, rank_walk, record_order, resolver_core, scheme_dependencies, scheme_predicates, scheme_projection, simd_contracts, solver_worklist, staging_origins, staging_type_match, storage_core, storage_ops, storage_types, task_regions, task_types, typed_staging, types, usage_check.

Paused at a completed file boundary for the root source-only checkpoint.

Remaining production modules:

bottom_flow_tests, capability_contract_core, capability_contract_source, capability_contracts, capability_flow, capability_invocations, capability_lifetimes, capability_lifetimes_tests, check, check_alias_tests, check_contract_tests, check_effect_tests, check_hole_tests, check_loop_tests, check_monad_tests, check_nominal_tests, check_open_row_tests, check_pattern_tests, check_proof_tests, check_request_tests, check_result_tests, check_shared_scheme_tests, check_tests, check_where_tests, checked_core_freeze_tests, cleanup_contracts, closed_graph_tests, core_aggregate_tests, core_array_tests, core_builder, core_callable_tests, core_case_statement_tests, core_closure_tests, core_loop_tests, core_monad_tests, core_proof_tests, core_snapshot_tests, core_tests, core_update_tests, dictionary_contracts, effect_span_tests, effect_unification_tests, effects_tests, frozen_core_validation, frozen_core_validation_tests, generative_core, generative_relocation, nominal_argument_borrow_tests, numeric_phase_tests, numeric_proof_contracts_tests, numeric_proof_core, package_contracts_tests, package_core, package_sequence_tests, parallel_lowering, scheme_equations, scoped_effect_backend_tests, shaped_parameter_tests, solver_scratch_tests, source_order_tests, staging_capture_rights, staging_core, staging_snapshot, tag_tests, task_backend_tests, task_check_tests, task_core, typed_staging_tests, types_tests, unit_coverage_tests, universal_dictionary_tests, usage_backend_tests, usage_check_tests, usage_core.

These lists describe writing coverage only. A written module has not been
compiled, checked, executed or qualified. Root entry construction and cross-module
integration remain a writing responsibility.

Contracts:

- Error is `blot_error::Error`; success is `Error.none`. Fallible copied values
  return `(value, Error)`, fallible void returns `Error`.
- Copied optional fixed values use `blot_support::Option<T>`; borrowed lookup
  optionals remain nullable references. Parser-facing proof and staging lookup
  functions return `(value, bool)`.
- Mutable owners are lexical driver/caller arrays. Contexts contain typed
  `T[>..<]&` table references where rollback is required, with direct `.nodes`
  rather than Zig ArrayList `.nodes.items` access.
- Effects init is `(rows:RowGrowShrink&, labels:LabelGrowShrink&,
  variables:VariableGrowShrink&, versions:VersionGrowShrink&,
  resolved:dictionary<Id,Id>&)`. initWithOptions adds Options. Cache entries
  retain the followed prefix across append and revoke on physical epoch change.
- ParameterPatterns init receives `(nodes:NodeGrowShrink&, extra:u32GrowShrink&)`.
  OrderedMembership init receives a `dictionary<u32,bool>&`; RecordOrder Names
  init receives `dictionary<u32,const u8[:]> &`.
- NumericProofTerms init receives `(terms:TermGrowShrink&,
  index:dictionary<Term,Id>&)`. copyOwned additionally receives a caller-owned
  `Term[>..]&`. `importProof` replaces the source keyword-named `import` method.
  Source views retain an owner ID; import rejects overlapping source/destination
  storage and rolls back newly interned terms on every error.
- TypeStore init receives `Tables`, the effects context, epoch cache context and
  composite cache context; initWithOptions adds Options. Tables contains owner
  references for nodes, extra, variables, versions, operations, operation_links,
  quantifier_goals, quantifier_obligations, occurs_seen, closed_row_index and
  closed_operation_index, and typed map references variable_views,
  associated_equations, projection_resolutions and operation_chains. Prepared
  substitution additionally borrows caller-owned `dictionary<Id,u32>` maps for
  leaves and row_leaves. Reporter callbacks are static typed `.report` methods.
- NumericProofHeaders clone/lower receive `OwnedTables` references for
  value_slots, proof_slots, values, operands and requirements. Signature and
  contract validators perform the full finite unsigned proof analysis,
  complement dual graph, SCC contradiction check and source work accounting.
- EffectAuthority Handle is a numeric u32 with static zero. Its append-only
  Owner table never recycles an activation identity during a live Store.
- Core Tag source alternatives block, match and loop become block_, match_ and
  loop_. Types Tag u32/f32 become unsigned32/floating32; SIMD Lane uses
  unsigned/floating. Explicit codecs retain source ordinals. No host enum image
  is a wire encoding.
- Core Module and Types have `owner_id:u64`. Module adds a derived
  `package_payloads:Id[:]` table aligned with nodes: each entry is node.a. This
  provides a safe borrowed singleton for package_pack children where Zig used
  a pointer cast into a scalar field. Builders must fill it; it grants no proof
  authority.
- Owner IDs and derived package_payloads must be excluded from serialized
  schemas and structural stamps. They are private context metadata.
- Scalar float bit reinterpretation uses root-owned native host primitives;
  compiled source stages remain Goose. Native Goose's physical reclamation and
  recoverable allocator behavior require the recorded runtime boundary work.

Remaining production modules are still being written. These first-pass bodies
have not established complete check subsystem coverage or executable parity.

Latest constructor and ownership additions:

- EffectEvidence Snapshot and FrozenGraph/PatternGraph public slices are const.
- TypeStore `withStore<C,F>(context)->Error` and
  `withStoreValue<C,F,R>(context)->R,Error` construct complete lexical scratch
  owners, invoke the callback, then dispose the context before returning.
- SolverWorklist init receives Tables refs entries/ready/pending/links/heads.
  Its complete bounded frontier preserves overflow fallback, source order,
  epoch and future-clock invalidation, external watches and free-link reuse.
- SchemeDependency Cache init receives only EntryGrowShrink and a Queue.
  Snapshot backing now uses concrete reusable[] u32 runs and reusable metadata
  slots with generation-tagged handles. Failure, replacement, truncation and
  disposal release the owned snapshot runs. The earlier append-only retention
  implementation was removed during writing.
- Package projection callbacks have concrete typed owners: PackProjection and
  SchemeProjection Resolver. Nullable typed references and static validate
  methods replace function pointers; no untyped context or compiler bridge.
- Core StampView and TypesStampView reproduce original serialized field order
  while omitting derived owner IDs and package_payloads recursively.

- SchemeImport Copier init receives Source, destination Store and Tables containing private_scopes/mapping/row_variables/rows/labels dictionaries. withCopier supplies lexical maps for callback scope. Every copied operation, row, binder, private scope, identity and source qualification retains its source algorithm.
- Associated admission uses lexical withStore and two independently mapped FrozenCopy contexts; copied formal correspondence, row parameter equality and projection work accounting remain exact.

- UsageCheck Memo init receives safe dictionary and nominal fact grow/shrink owner references. Its complete source walker receives lexical state storage, merges every exit/case/loop, restores moved closure captures and loan regions, and keeps task read/write views separate from consumption.
- ClosedNominalStorage reconstructs the greatest fixed point and opaque physical roles in a bounded local catalog; construction independently substitutes exact family formals and checks complete payload shape.
