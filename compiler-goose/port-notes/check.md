# Check port writing record

Writing phase only. No builds, tests, formatter checks or compiler invocations
have run. Source/compiler qualification remains pending until the complete
port has been written.

Completed writing passes (unverified):

associated_admission, check, capability_contract_core, capability_contract_source, capability_contracts, capability_flow, capability_invocations, capability_lifetimes, check_scheme_import, cleanup_contracts, closed_nominal_storage, collection_contracts, core, core_builder, diagnostic_code, diagnostic_location, dictionary_contracts, dictionary_owner, effect_authority, effect_evidence, effects, frozen_types, generative_core, generative_relocation, generative_schemes, numeric_proof_bodies, numeric_proof_contracts, numeric_proof_core, numeric_proof_headers, numeric_proof_terms, ordered_membership, package_core, package_contracts, package_evidence, package_portable, package_row_facts, parallel_lowering, parameter_patterns, primitive_operator, quantifier_goals, rank_equal, rank_portable, rank_walk, record_order, resolver_core, scheme_dependencies, scheme_equations, scheme_predicates, scheme_projection, simd_contracts, solver_worklist, staging_capture_rights, staging_origins, staging_snapshot, staging_type_match, storage_core, storage_ops, storage_types, task_core, task_regions, task_types, typed_staging, types, usage_check, usage_core.

Currently being written: staging Core admission. The main checker and CoreBuilder have complete first writing passes. The parent owns frozen_core_validation; this agent owns the other remaining check modules.

Remaining production modules:

frozen_core_validation, staging_core.

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

Native test-only *_tests.zig modules remain in the pinned Zig oracle. Their absence from this production-module list does not discard their evidence or establish a Goose test pass.

- SchemeEquations Solver receives a complete scratch Store and SolverTables refs rigid_type_overflow, rigid_rows and shared_goals. withSolver supplies those lexical owners for a callback. Importer receives separate CheckSchemeImport Tables. Admission/Workspace receive typed tables; source row/definition snapshots have reusable pool leases released at disposal.
- SharedAuthority compares nonzero Context.owner_id plus original slice boundary identity, all lexical facts, ordered schemes and source flags. Context.initialize allocates its private owner identity once.
- CapabilityContract Store receives TermGrowShrink and WordGrowShrink; own/clone/select receive explicit typed output owners. Collection public slices are const. Canonical imports retain children-first DFS numbering independent of producer layout; digest retains source BLAKE3 version1 framing and field spellings.

Additional ownership helpers (written, unverified): type_store_snapshot and lifetime_report_pool.

- Lifetime reports own immutable semantic evidence snapshots and all13 typed output runs through a generation-tagged reusable pool lease; deinit releases every run. Callable parameters use a native closure/body selector and read exact catalog parameters, avoiding a borrowed scalar-to-slice cast. Full executable edge, cell, capture, invocation, resource and task analysis remains bounded and reports incomplete unknown edges without granting confinement.
- TypeStore suspend/restore and cloneSnapshot preserve all22 backing tables/maps/cache tables, exact dictionary slot layouts, Store/effect/cache scalar state, counters and owner_id. Suspend moves the logical owner, cloneSnapshot makes an independently owned immutable snapshot with the same logical identity, and restore consumes a live generation lease into fresh lexical backing.
- Writing-phase source construction corrections applied: native nullable references use scoped .= bindings, reference rebinding uses .=, native match arms use => and commas, payload reads use explicit variant locals. No compiler or verifier has been invoked.

- CapabilityContractSource Functions is a concrete borrowed checker Engine adapter; lookup calls its exact callbackFunction(source) reconstruction. No erased pointer or runtime callback. Full optional derivation rolls back Store marks on unavailable/error and independently validates portable binder scope before returning a result.

- NumericProofCore Plan retains a generation-tagged typed check run; every execution visit intersects admission, and optional reasoning errors revoke all check-elimination flags. Formal/header proof admission, executable guards, short-circuit predecessor intersections and exact opaque-reference aliases retain their source algorithms. Recursive scratch owner construction is being converted to fixed reusable-slice workspaces under Goose section 7.8 before verification.

- ParallelLowering preserves largest-first scheduling, bounded worker startup, prepare rollback, join-before-return and ordered take/discard through the root-owned typed copied-packet executor. The worker transport/owner codecs remain root integration work; the concurrency driver is not qualified.
- UsageCore includes the complete executable admission pass: snapshots/exit merges, physical capture discovery, nominal least fixed point, region identity admission, resource cleanup and earlier/future stage isolation. Its private walker uses fixed bounded tables.

Main checker now has a complete first production writing pass, split between check.goose, check_factory.goose and check_owners.goose. This includes global SCC stabilization and scheduling, exact shared-scheme memo outcomes, intrinsic/proof typing, expression/statement/request/resolver control flow, field rebinding, final normalization/coverage, complete retained-body receipts/replay and auxiliary remapping, public checker/source-validation entrypoints, and retained output ownership. Root body-cache/completion/auxiliary typed leaf dependencies are still being written; this is not import-closure or compiler qualification.

- Recursive checker environments, associated normalization maps, projection caches, predicate buffers and usage memo facts now use fixed typed reusable descriptors with explicit release. The pooled UsageCheck memo retains catalog/epoch invalidation and the source work charges; it does not bypass nominal inspection.
- CapabilityContractCore derives the frozen-validator reconstruction under the exact private 1MiB logical FixedBufferAllocator ledger. The ledger tracks Zig0.17 ArrayList growth, alignment and last-allocation remapping for terms, words and callable origins, while semantic buffers remain typed Goose owners. This is source construction, not allocator-fault qualification.
- SourceSort contains the complete Zig0.17 pdqContext algorithm for implementation ordering, including heap fallback, insertion paths, pivot choice and block partitioning. Comparison work/fuel is retained.
- EffectEvidence fixed pooled Store conversion is now written by the eval agent so recursive evidence callbacks do not retain lexical Grow owners. Immutable snapshot and exact dictionary-slot cloning contracts remain required.


- FrozenTypes Source/Patterns now start with a payload-free inactive variant solely for inert absent storage in copied Option records. Every observer aborts on inactive as invalid internal API use; active constructors explicitly choose store/frozen, and no empty/default graph or proof is returned. Exhaustive matches in sibling consumers must cover inactive with the same invalid-use abort. Native variant layout is not a wire format.

- CapabilityContracts.Store now has concrete pooled term/word metadata, generation-checked ownership and explicit deinit. Empty descriptors are inert; first mutation or initPooled activates storage. Immutable Recipe/Collection/View slices are unchanged. Recursive capability prototypes no longer require lexical native Grow owners.
- Main checker source lifetime inference retains constructor captures, projected/unknown footprints, public retained-formal recipes, input callback instantiation, dictionary rank goals and trusted State-store depth rules. Generic RankWalk collectors now use fixed typed scratch, including quantifier goal copies. TypeStore now has a concrete pooled boundary for recursive implementation-row reconstruction.

- Main checker additional writing covers task scopes and concrete transfer/host/overlap checks, scoped effect residual ownership, provider/State handlers, exact runner equations, source projections and suspended self-method requirements, case-arm version joins, existential dictionary selection, resource cleanup/loans, contextual higher rank lambdas, proof-header admission and type annotation traversal. These remain source-only first passes.
- LegacyProof now copies its fixed descriptor into evidence resolvers while projection remaining/observed counters refer to generation-checked typed pooled budget metadata; the header is released when the whole proof call returns.

Pooled Types/Effects ownership is now written. Store copies share generation-tagged global table headers, raw map slots/counts and all scalar counters/epochs; initPooled/withStore own real typed reusable backing. Exact StoreSnapshot transfer restores every mutable table and cache, preserving logical owner identity. FrozenTypes.Source.store now stores the fixed descriptor by value. These changes have not been verified.

- ParameterPatterns.Store now has concrete pooled node/word owners; FrozenTypes.Patterns.store carries that fixed descriptor by value.
- Checked and SourceValidation own generation-tagged typed output runs, including nested proof headers and proof-body/capability catalogs. SourceValidation transfer releases all unretained body tables. Factory scratch remains lexical and outside inference recursion; numeric rejection takes a separate unchecked source-validation entry to avoid an owner-factory recursion cycle.
- SchemeCopier memo maps are concrete fixed typed pooled maps, and associated admission now initializes/deinitializes the parent-owned pooled principal graph copiers. Remaining recursive scratch conversions and logical allocator-fault hooks are source integration work, not completed verification.

CoreBuilder now publishes `dependency_payload.Owned<Core.Module>` from `lower` and `lowerWithOrigins`. Every table, nested proof-header slice, selected capability catalog, and declaration-dependency table is retained by that owner; recursive scratch uses fixed pooled buffers. Its full production lowering algorithms are written, still unverified.

PackageCore writing currently includes the source-proof cache, exact metadata closure search, admission entry points, body/scheme/row ownership, principal mappings, rollback-aware goal matching, shared prerequisite expansion, and closed goal reconstruction through native line2302. Its remaining lexical expression/storage walkers and all StagingCore algorithms are still being written. SchemeEquations now uses concrete fixed owning buffer/map descriptors in Admission, Workspace, and Solver; caller factories use `initPooledAdmission`/`initPooledWorkspace`. Module snapshot records copy fixed headers and compare nonzero owner IDs plus exact headers. No verification has run.

PackageCore now has its complete production first writing pass, including all lexical/capture/storage/control/expression checks. Cache publication remains transactional, failed matching retains exact epoch-aware rollback, and solver scratch uses fixed typed runs/maps. `write_check_constructor_defaults.py` writes explicit Goose `..` constructor defaults in this agent-owned check files only; it excludes root frozen validators and the three leaves owned by other agents. No compiler, build, test, formatter, or static verifier has run.
