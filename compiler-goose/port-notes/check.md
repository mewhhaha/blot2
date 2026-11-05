# Check port writing record

All checker production modules assigned to this agent have full first writing
passes. The parent owns frozen_core_validation and its supporting modules.
No build, test, formatter, compiler, static verifier, or executable qualification
has run. Source writing coverage is not import closure or parity evidence.

Completed production writing passes (unverified):

associated_admission, check, capability_contract_core, capability_contract_source, capability_contracts, capability_flow, capability_invocations, capability_lifetimes, check_scheme_import, cleanup_contracts, closed_nominal_storage, collection_contracts, core, core_builder, diagnostic_code, diagnostic_location, dictionary_contracts, dictionary_owner, effect_authority, effect_evidence, effects, frozen_types, generative_core, generative_relocation, generative_schemes, numeric_proof_bodies, numeric_proof_contracts, numeric_proof_core, numeric_proof_headers, numeric_proof_terms, ordered_membership, package_core, package_contracts, package_evidence, package_portable, package_row_facts, parallel_lowering, parameter_patterns, primitive_operator, quantifier_goals, rank_equal, rank_portable, rank_walk, record_order, resolver_core, scheme_dependencies, scheme_equations, scheme_predicates, scheme_projection, simd_contracts, solver_worklist, staging_capture_rights, staging_origins, staging_snapshot, staging_core, staging_type_match, storage_core, storage_ops, storage_types, task_core, task_regions, task_types, typed_staging, types, usage_check, usage_core.

The three shared leaves effect_authority, effect_evidence, and solver_worklist
also contain the later pooled-owner conversions made by the backend/eval agents.
Those files remain under their current owners. Root integrations in check.goose
(ModuleOrigins.failure, producer name contexts, packet-owner release) are preserved.

Additional authored source helpers: check_factory, check_owners,
lifetime_report_pool, logical_scratch_budget, source_sort, type_store_snapshot.
The eval agent owns check_packet_owner and type_store_packet.

Current contracts:

- Error is blot_error::Error; success is Error.none. Copied fallible values
  return value,Error; fallible void returns Error. Defaultable copied optionals
  use Option<T>; borrowed optionals use typed nullable references.
- Types/Effects, parameter patterns, capability contracts, solver worklists,
  semantic evidence, projection caches, and retained checker outputs use actual
  generation-tagged typed reusable owners. Store descriptor copies share live
  table/scalar metadata; independent clones mint new mutable owner identities.
- TypeStore suspend/restore preserves all22 table/map/cache runs, raw dictionary
  slots, semantic IDs, epochs, counters, budgets, and logical owner identity.
  Snapshots own typed leases; restoration consumes a live lease. Snapshot clones
  preserve immutable identity while retaining independent physical runs.
- FrozenTypes Source/Patterns have an inactive first variant for absent fixed
  storage only. Every observation of inactive is invalid API use and aborts;
  active constructors choose store or frozen explicitly. No absent value grants
  a default graph or proof. Frozen graph headers and pooled Store descriptors
  are copied values, with immutable public slices.
- The complete checker includes SCC stabilization/scheduling, shared-scheme
  outcomes, all expression/control/request/resolver/task paths, source lifetime
  and capability authority, rollback-aware goal/equation solving, proof rows,
  final normalization/coverage, retained body receipts/replay, and output owners.
- PackageCore includes complete metadata, lexical, capture, storage, control,
  expression, goal, scheme, row, and source authority algorithms. Failed matches
  retain exact epoch-aware rollback; solver scratch uses fixed typed runs/maps.
- StagingCore includes complete lexical owners, source/foreign calls, request
  decisions, tasks, handler boundaries, latent effects and selected symbolic
  row witnesses, descriptor fields, and shape rules with original fuel limits.
- CoreBuilder lower/lowerWithOrigins publishes dependency_payload.Owned<Module>.
  Its owner retains every table, nested proof header, capability catalog and
  declaration-dependency table; recursive scratch uses fixed typed owners.
- Core Module/Types owner_id and derived package_payloads are private metadata.
  StampView reproduces original field order and omits them. Nonzero owner IDs
  plus exact original storage boundaries preserve pinned-source identity.
- Native enum codecs retain exact source ordinals and backing widths. Core
  block/match/loop become block_/match_/loop_; Types u32/f32 become
  unsigned32/floating32; SIMD Lane uses unsigned/floating. Native enum layout
  is never a wire format. Structural hash/equality use concrete enum hooks and
  deep owned slice content where Zig required it.
- CapabilityContractCore's private reconstruction retains the exact1MiB logical
  fixed-buffer ledger. Numeric proof analyses retain full unsigned proof,
  contradiction/SCC, guard, short-circuit and opaque-alias algorithms. Scheme
  snapshot retention releases typed runs on replacement/truncate/disposal.
- Lifetime reports own all13 immutable typed output families and semantic
  snapshots through a generation lease. Its adapters now use pooled evidence
  .items slices and canonical frozen-validator ModuleRef catalogs.
- ParallelLowering uses the eval agent's actual copied-process executor and
  owned result packets. Separate processes permit ordinary metadata pools;
  no Goose thread_fn reaches non-flat mutable metadata globals.

Goose construction uses ordinary overloaded free functions for UFCS, explicit
constructor default tails, scoped nullable reference narrowing, reference rebinding
with .=, and native match arms. Source-writing migrations keep pre-write journals
under build/goose-port/. Recoverable allocation/runtime contracts and complete
cross-module lifetime/API alignment remain writing/integration responsibilities.

Native test-only *_tests.zig remain in the pinned Zig oracle. They are not omitted
production work and have not been executed as Goose tests.
