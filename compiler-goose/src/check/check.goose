// Source inference. Tables borrow explicit compilation owners.
namespace blot_check_check;
import check.core;
import backend.collection_ops;
import backend.loop_targets;
import backend.opaque_storage;
import backend.simd_intrinsics;
import check.capability_flow;
import check.check_packet_owner;
import check.check_scheme_import;
import check.effects;
import check.frozen_types;
import check.ordered_membership;
import check.parameter_patterns;
import check.scheme_dependencies;
import check.solver_worklist;
import check.source_sort;
import check.storage_ops;
import check.storage_types;
import check.given_equations;
import check.purity_type_key;
import check.trait_patterns;
import check.typed_staging;
import check.types;
import inference_limits;
import parse.ast;
import parse.source_operators;
import parse.symbols;
import reuse.completion_names;
import reuse.completion_probe;
import reuse.dispatch_explanation;
import reuse.global_references;
import reuse.hole_diagnostics;
import reuse.module_visibility;
import reuse.principal_interface;
import reuse.project_check_factory;
import reuse.purity_diagnostics;
import reuse.type_display;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
import support.zigmap;
import support.structural_adapters;
import work_counters;

import reuse.project_check;
import support.structural;
import support.native;
import .check_owners;
import .check_factory;
import std;
import dictionary;

struct EditorMarker {
    span: blot_parse_ast::Span,
    kind: blot_reuse_completion_probe::Kind,
    prefix: const u8[:] = ""
}
enum EditorName_kind { value, function, type_, constructor, field, member, module }
struct EditorName {
    name: blot_parse_symbols::Symbol,
    kind: EditorName_kind,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..},
    distance: u32 = 0,
    identity: Identity = Identity { unit: 0, decl: 0 , ..},
    external: blot_support::Option<ExternalTarget>   = blot_support::none<ExternalTarget>(),
    ambiguous: bool = false,
    receiver: bool = false
}
struct EditorCapture {
    names: EditorName[:] = default<EditorName[:]>(),
    kind: blot_reuse_completion_probe::Kind,
    node: blot_parse_ast::Id,
    scope: blot_check_types::List,
    visible: blot_check_types::List = blot_check_types::List {..},
    visible_names: blot_check_types::List = blot_check_types::List {..},
    scope_names: blot_check_types::List = blot_check_types::List {..},
    type_scope: blot_check_types::List = blot_check_types::List {..},
    truncated: bool = false,
    owner: BindingId,
    receiver: blot_check_types::Id = 0,
    namespace_: blot_parse_symbols::Symbol = 0,
    context: blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>   = blot_support::none<blot_reuse_hole_diagnostics::Snapshot>()
}
struct ModuleOptions {
    retained_core: const blot_check_core::Module? = null,
    skip_root: const bool[:] = default<const bool[:]>(),
    editor: blot_support::Option<EditorMarker>   = blot_support::none<EditorMarker>(),
    purity_origins: ModuleOrigins = ModuleOrigins {..},
    builtin_catalog: bool = false,
    is_std: bool = false,
    prelude_unit: u32 = 0,
    max_inference_transitions: blot_support::Option<i64>   = blot_support::none<i64>(),
    associated_remaining: i64? = null,
    producer_capabilities: blot_support::Option<ProducerCapabilities>   = blot_support::none<ProducerCapabilities>(),
    producer_storage: blot_support::Option<ProducerStorage>   = blot_support::none<ProducerStorage>()
}
struct AliasGlobalStats {
    attempts: i64 = 0,
    admitted: i64 = 0,
    declined: i64 = 0,
    frames: i64 = 0,
    peak_frames: i64 = 0
}
enum GlobalTrace_kind { begun, finished }
struct GlobalTrace {
    kind: GlobalTrace_kind,
    binding: BindingId,
    counter: u32,
    index: u32,
    low: u32,
    active: i64,
    current: BindingId,
    owner: blot_parse_ast::Id,
    ambient: blot_check_effects::Id,
    pending_start: i64,
    type_nodes: i64,
    type_versions: i64,
    row_versions: i64,
    type_env: i64,
    row_env: i64,
    computation_annotations: i64
}
enum ReflectionKind { of, descriptor, count, has, same }
struct Reflection {
    node: blot_parse_ast::Id,
    kind: ReflectionKind,
    left: blot_parse_ast::Id = 0,
    right: blot_parse_ast::Id = 0,
    binding: BindingId = 0,
    row: blot_check_effects::Id = 0,
    label: blot_check_effects::Label = 0
}
enum OperationUse_call { value, state_read, state_write }
struct OperationUse {
    node: blot_parse_ast::Id,
    template: u32,
    arguments: blot_check_types::List,
    signature: blot_check_types::Id,
    instance: Identity = Identity { unit: 0, decl: 0 , ..},
    capability: blot_parse_ast::Id = 0,
    capability_binding: BindingId = 0,
    call: OperationUse_call = OperationUse_call.value,
    operand: blot_parse_ast::Id = 0
}
struct AssociatedKey {
    identity: Identity,
    operator: blot_check_types::Operator
}
struct AssociatedMember {
    identity: Identity,
    member: blot_parse_symbols::Symbol
}
// An associated entry copied from an imported catalog, keyed by its producer.
struct ImportedAssociated {identity:Identity,member:blot_parse_symbols::Symbol,target:ExternalTarget}
fn hash(key:ImportedAssociated)->u64 {return ::hash_combine(::hash_combine(::hash_combine(::hash(key.identity.unit),::hash(key.identity.decl)),::hash(key.member)),::hash_combine(::hash(key.target.unit),::hash(key.target.binding)));}
// An imported associated member keeps this in `Associated.binding` until its
// first lookup copies the scheme: the bit, then its `associated_pending` slot.
let pending_associated:u32=0x80000000;
fn hash(key:AssociatedMember)->u64 {return ::hash_combine(::hash_combine(::hash(key.identity.unit),::hash(key.identity.decl)),::hash(key.member));}
fn hash(key:AssociatedKey)->u64 {return ::hash_combine(::hash_combine(::hash(key.identity.unit),::hash(key.identity.decl)),::hash(blot_check_types::operatorCode(key.operator)));}
fn hash(key:ClosedRow)->u64 {return ::hash_combine(::hash(key.owner),::hash(key.variable));}
struct EffectMember {
    family: u32,
    member: blot_parse_symbols::Symbol
}
fn hash(key:EffectMember)->u64 {return ::hash_combine(::hash(key.family),::hash(key.member));}
struct Rebinding {
    root: BindingId = 0,
    self_binding: BindingId = 0,
    path: blot_check_types::List = blot_check_types::List {..}
}
struct Projection {
    nominal: Identity,
    field: blot_parse_symbols::Symbol,
    variants: blot_check_types::List
}
enum ImportedCatalog_kind { catalog, nominal, constructor, effect_family, contract, implementation }
struct ImportedCatalog {
    producer: blot_support::Option<LiveProducer> = blot_support::none<LiveProducer>(),
    frozen: blot_support::Option<FrozenProducer> = blot_support::none<FrozenProducer>(),
    namespace_: blot_parse_symbols::Symbol = 0,
    name: blot_parse_symbols::Symbol = 0,
    kind: ImportedCatalog_kind,
    index: u32,
    origin: blot_parse_ast::Id
}
struct SourceCatalog {
    producer: DeclarationCatalog,
    declarations: const SourceDeclaration[:],
    namespace_: blot_parse_symbols::Symbol = 0,
    name: blot_parse_symbols::Symbol = 0,
    kind: ImportedCatalog_kind,
    index: u32,
    origin: blot_parse_ast::Id
}
struct SchemeSummary {
    flat_size: u32 = 0,
    public_variables: blot_check_types::List = blot_check_types::List {..},
    public_rows: blot_check_types::List = blot_check_types::List {..},
    public_inputs: blot_check_types::List = blot_check_types::List {..},
    public_outputs: blot_check_types::List = blot_check_types::List {..},
    only_result_selected: bool = false,
    requirement_variables: blot_check_types::List = blot_check_types::List {..},
    requirement_rows: blot_check_types::List = blot_check_types::List {..},
    has_explicit: bool = false,
    shareable: bool = false
}
struct Binding {
    read: bool = false,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    operation_ref: u32 = 0,
    private: bool = false,
    name: blot_parse_symbols::Symbol,
    declaration: blot_parse_ast::Id,
    owner: blot_parse_ast::Id,
    kind: Kind,
    named_function: bool = false,
    ty: blot_check_types::Id,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..},
    external: blot_support::Option<ExternalTarget>   = blot_support::none<ExternalTarget>(),
    predecessor: BindingId = 0,
    summary: SchemeSummary = SchemeSummary {..}
}
struct SchemeInterface {
    summary: blot_support::Option<SchemeSummary>   = blot_support::none<SchemeSummary>(),
    producer_binding: BindingId = 0,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    named_function: bool = false,
    types: blot_check_frozen_types::Source,
    scheme: blot_check_types::Scheme,
    obligations: const blot_check_types::Obligation[:],
    callees: Callees = Callees.none
}
struct LiveCallees {types:blot_check_frozen_types::Source,bindings:const Binding[:],obligations:const blot_check_types::Obligation[:]}
struct LiveProducer {catalog:DeclarationCatalog,callees:LiveCallees}
struct FrozenCallees {graph:blot_check_frozen_types::Graph,bindings:const blot_reuse_principal_interface::Binding[:],obligations:const blot_check_types::Obligation[:],summaries:const SchemeSummary[:]=default<const SchemeSummary[:]>()}
struct FrozenProducer {catalog:DeclarationCatalog,callees:FrozenCallees}
enum Callees { none, live { value: LiveCallees }, frozen { value: FrozenCallees } }
struct ImportedBinding {
    name: blot_parse_symbols::Symbol = 0,
    namespace_: blot_parse_symbols::Symbol = 0,
    member: blot_parse_symbols::Symbol = 0,
    target: ExternalTarget,
    interface: SchemeInterface,
    origin: blot_parse_ast::Id,
    expose: bool = true
}
// One invocation owns the grow-only metadata arena outside fixed-size Engine.
struct ImportArena {records:ImportedBinding[>..]}
struct SourceHeader {
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    name: blot_parse_symbols::Symbol = 0,
    namespace_: blot_parse_symbols::Symbol = 0,
    member: blot_parse_symbols::Symbol = 0,
    target: ExternalTarget,
    named_function: bool = false,
    origin: blot_parse_ast::Id,
    expose: bool = true
}
struct SourceDeclaration {
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    private: bool = false,
    name: blot_parse_symbols::Symbol,
    declaration: blot_parse_ast::Id,
    kind: Kind,
    named_function: bool,
    external: blot_support::Option<ExternalTarget>
}
struct ProducerCapability {
    parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..}
}
struct DeclarationCatalog {
    types: blot_check_frozen_types::Source,
    parameter_patterns: blot_check_frozen_types::Patterns,
    nominals: const Nominal[:],
    constructors: const Constructor[:],
    effect_families: const EffectFamily[:],
    effect_templates: const EffectTemplate[:],
    associated: const Associated[:],
    unit: u32,
    contracts: const Contract[:] = default<const Contract[:]>(),
    contract_predicates: const blot_check_types::Obligation[:] = default<const blot_check_types::Obligation[:]>(),
    contract_members: const ContractMember[:] = default<const ContractMember[:]>(),
    implementations: const Implementation[:] = default<const Implementation[:]>(),
    implementation_predicates: const blot_check_types::Obligation[:] = default<const blot_check_types::Obligation[:]>(),
    implementation_members: const ImplementationMember[:] = default<const ImplementationMember[:]>()
}
struct ProviderBlock {
    node: blot_parse_ast::Id,
    provider: blot_parse_ast::Id,
    body_result: blot_check_types::Id,
    result: blot_check_types::Id,
    body_effects: blot_check_effects::Id,
    outer_effects: blot_check_effects::Id
}
enum EffectRunnerKind { run, reader, writer }
struct EffectRunner {
    node: blot_parse_ast::Id,
    kind: EffectRunnerKind,
    read_token: blot_check_types::Id = 0,
    write_token: blot_check_types::Id = 0,
    initial: blot_parse_ast::Id = 0,
    witness: blot_parse_ast::Id = 0,
    implementation: blot_parse_ast::Id = 0,
    action: blot_parse_ast::Id,
    state_type: blot_check_types::Id,
    body_result: blot_check_types::Id,
    result: blot_check_types::Id,
    implementation_type: blot_check_types::Id = 0,
    action_type: blot_check_types::Id,
    body_effects: blot_check_effects::Id,
    outer_effects: blot_check_effects::Id
}
struct LoopCarry {
    node: blot_parse_ast::Id,
    incoming: BindingId,
    iteration: BindingId,
    backedge: BindingId,
    outgoing: BindingId
}
struct LoopExit {
    node: blot_parse_ast::Id,
    loop_: blot_parse_ast::Id,
    bindings: blot_check_types::List
}
struct StatementArm {
    node: blot_parse_ast::Id
}
struct ClosedRow {
    owner: BindingId,
    variable: u32
}
struct Merge {
    node: blot_parse_ast::Id,
    result: BindingId,
    then_binding: BindingId,
    else_binding: BindingId
}
enum Code { function_return_required, task_escape, task_handle_consumed, task_capture_transfer, task_capability_shared, task_regions_overlap, task_host_contract, task_budget, invalid_proof_operand, proof_scope_escape, proof_runtime_use, proof_mismatch, contradictory_proof, proof_analysis_limit, effect_identity_scope, capability_escape, capability_analysis_limit, undetermined_implementation, orphan_implementation, overlapping_implementation, incompatible_implementation, recursive_evidence, missing_type_member, associated_arity, recursive_associated_type, associated_limit, missing_implementation, private_access, private_identity_escape, unbound_alias_row, recursive_contract, contract_arity, recursive_type_alias, typed_hole, effect_member, integer_range, float_range, float_literal, module_loader_required, intrinsic_arity, requests_scope, yield_scope, request_loop_scope, request_loop_body, request_loop_range, request_binding, request_completion, request_clause_fallthrough, request_completion_fallthrough, duplicate_request_handler, request_case_scope, unknown_value, syntax, duplicate_name, unknown_name, type_mismatch, infinite_type, effect_mismatch, infinite_effect, const_effect, initializer_effect, let_effect, sealed_effect, effect_arity, effect_family, unknown_effect, invalid_effect_annotation, invalid_constraint, higher_rank_constraint, missing_predicate, ambiguous_qualified, annotation_kind_mismatch, unsupported_polymorphic_effect_label, operation_signature, type_arity, operation_target, invalid_state_provider, unsupported, unsupported_attribute, recursive_tag, function_target, open_effect_descriptor, unsupported_expression, unsupported_type, ambiguous_operator, ambiguous_associated, missing_associated, ambiguous_member, missing_member, type_constructor_required, invalid_provider, resolver_required, literal_required, call_arity, break_scope, continue_scope, invalid_return, unreachable_statement, invalid_operator, return_outside_block, return_outside_function, return_across_continuation, unknown_rebinding, dead_rebinding, case_arm_return, nesting_limit, unknown_constructor, constructor_marker, type_parameter, type_argument, duplicate_type_parameter, duplicate_type_field, unknown_field, duplicate_field, missing_field, non_exhaustive_match, refutable_pattern, constructor_arity, unknown_product_shape, product_index, product_index_literal, pattern_arity, pattern_bindings, value_pattern_type, non_exiting_fallback, unknown_operator, operator_associativity, operator_header_order, operator_precedence, duplicate_operator, unsupported_prefix, unknown_intrinsic, alternative_bindings, duplicate_pattern_binding, duplicate_record_field, unknown_record_field, record_constructor, missing_record_field, unknown_modifier, guard_fallthrough, product_arity, inference_budget, skolem_escape, rank_mismatch, package_expected, package_witness_mismatch, package_escape, abstract_representation_access, use_after_move, duplicate_owner, borrow_conflict, borrow_escape, once_reused, multiplicity_unknown, cleanup_not_safe, usage_evidence_mismatch, usage_analysis_limit, code_shape_mismatch, stage_unavailable, cross_stage_authority, descriptor_private, generated_binding_escape, staging_budget, own_parameter, spark_generator, spark_effectful, spark_capture, kernel_type, kernel_callable, kernel_effectful, std_only_intrinsic, entry_type }
struct TagOrigin {
    span: blot_parse_ast::Span,
    attribute: blot_parse_ast::Id
}
struct Computation {
    node: blot_parse_ast::Id,
    action: blot_parse_ast::Id,
    ty: blot_check_types::Id,
    action_type: blot_check_types::Id
}
struct CoveredRequirement {
    scope: blot_parse_ast::Id,
    value: blot_check_types::Obligation
}
struct Checked {
    owner:CheckedOwner=CheckedOwner{..},
    function_exit_lambdas: blot_parse_ast::Id[:] = default<blot_parse_ast::Id[:]>(),
    editor: blot_support::Option<EditorCapture>   = blot_support::none<EditorCapture>(),
    iterator_bodies: blot_parse_ast::Id[:] = default<blot_parse_ast::Id[:]>(),
    initializer_rejected: bool = false,
    computations: Computation[:] = default<Computation[:]>(),
    reflections: Reflection[:] = default<Reflection[:]>(),
    tag_origins: TagOrigin[:] = default<TagOrigin[:]>(),
    effect_runners: EffectRunner[:] = default<EffectRunner[:]>(),
    effect_runner_ids: u32[:] = default<u32[:]>(),
    provider_blocks: ProviderBlock[:] = default<ProviderBlock[:]>(),
    provider_block_ids: u32[:] = default<u32[:]>(),
    body_closed_rows: ClosedRow[:] = default<ClosedRow[:]>(),
    lambda_closed_rows: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    dispatch_signatures: blot_check_types::Id[:] = default<blot_check_types::Id[:]>(),
    covered_requirements: CoveredRequirement[:] = default<CoveredRequirement[:]>(),
    effect_families: EffectFamily[:] = default<EffectFamily[:]>(),
    effect_templates: EffectTemplate[:] = default<EffectTemplate[:]>(),
    operation_uses: OperationUse[:] = default<OperationUse[:]>(),
    operation_refs: u32[:] = default<u32[:]>(),
    types: blot_check_types::Store,
    parameter_patterns: blot_check_parameter_patterns::Store,
    expr_types: blot_check_types::Id[:],
    resolved: BindingId[:],
    bindings: Binding[:],
    merges: Merge[:],
    obligations: blot_check_types::Obligation[:],
    diagnostics: Diagnostic[:],
    body_elaborations: i64,
    imported_schemes: i64 = 0,
    counters: Counters = Counters {..},
    unit: u32 = 1,
    associated: Associated[:] = default<Associated[:]>(),
    nominals: Nominal[:] = default<Nominal[:]>(),
    contracts: Contract[:] = default<Contract[:]>(),
    contract_predicates: blot_check_types::Obligation[:] = default<blot_check_types::Obligation[:]>(),
    contract_members: ContractMember[:] = default<ContractMember[:]>(),
    implementations: Implementation[:] = default<Implementation[:]>(),
    implementation_predicates: blot_check_types::Obligation[:] = default<blot_check_types::Obligation[:]>(),
    implementation_members: ImplementationMember[:] = default<ImplementationMember[:]>(),
    member_templates: blot_reuse_principal_interface::MemberTemplate[:] = default<blot_reuse_principal_interface::MemberTemplate[:]>(),
    constructors: Constructor[:] = default<Constructor[:]>(),
    constructor_resolved: u32[:] = default<u32[:]>(),
    projections: u32[:] = default<u32[:]>(),
    access_paths: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    access_nodes: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    access_types: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    projection_resolved: u32[:] = default<u32[:]>(),
    projection_catalog: Projection[:] = default<Projection[:]>(),
    rebindings: Rebinding[:] = default<Rebinding[:]>(),
    loop_carries: LoopCarry[:] = default<LoopCarry[:]>(),
    loop_ranges: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    loop_exits: LoopExit[:] = default<LoopExit[:]>(),
    statement_arms: StatementArm[:] = default<StatementArm[:]>()
}
struct Entry {
    name: blot_parse_symbols::Symbol,
    binding: BindingId
}
struct Counters {
    obligations_appended: u64 = 0,
    pending_peak: u64 = 0,
    instantiations: u64 = 0,
    shared_uses: u64 = 0,
    use_expansions: u64 = 0,
    memo_hits: u64 = 0,
    memo_misses: u64 = 0,
    memo_declined: u64 = 0,
    inference_steps: u64 = 0,
    associated_steps: u64 = 0,
    projection_memo_hits: u64 = 0
}
struct CalleeOutcome {
    types: blot_check_types::Id[:],
    rows: blot_check_effects::Id[:]
}
enum State { pending, active, complete }
struct Global {
    state: State = State.pending,
    index: u32 = 0,
    low: u32 = 0,
    on_stack: bool = false
}
struct PendingRange {start:i64=0,end:i64=0}
struct PendingObligation {
    metadata: u32 = 0,
    value: blot_check_types::Obligation,
    owner: BindingId,
    scope: blot_parse_ast::Id = 0,
    origin: u32 = 0,
    wait_target: BindingId = 0,
    declared: bool = false,
    covered: bool = false,
    local_scheme: bool = false,
    direct: bool = false,
    method_member: bool = false,
    suspended: bool = false,
    solved: bool = false,
    expansion: u32 = 0,
    // The name is a field for sure: an update goes through it.
    field_only: bool = false
}
struct Qualification {
    scope: blot_parse_ast::Id,
    owner: BindingId,
    clauses: blot_check_types::List,
    value: blot_parse_ast::Id,
    checked: bool = false
}
struct QualificationUse {
    scope: blot_parse_ast::Id,
    owner: BindingId,
    target: BindingId,
    source: blot_parse_ast::Id
}
struct ForwardedRequirement {
    use: i64,
    value: blot_check_types::Obligation
}
fn hash(key:ForwardedRequirement)->u64 {
    let value=key.value;var result=::hash(key.use);
    result=::hash_combine(result,::hash(value.ty));result=::hash_combine(result,::hash(blot_check_types::obligationKindCode(value.kind)));
    result=::hash_combine(result,::hash(value.source));result=::hash_combine(result,::hash(value.name));
    result=::hash_combine(result,::hash(value.result));result=::hash_combine(result,::hash(value.other));result=::hash_combine(result,::hash(value.signature));
    result=::hash_combine(result,::hash(blot_check_types::operatorCode(value.operator)));
    result=::hash_combine(result,::hash(value.identity.unit));result=::hash_combine(result,::hash(value.identity.decl));result=::hash_combine(result,::hash(value.explicit));
    result=::hash_combine(result,::hash(value.qualification_span.present));
    if value.qualification_span.present {result=::hash_combine(result,::hash(value.qualification_span.value.start));result=::hash_combine(result,::hash(value.qualification_span.value.end));}
    return ::hash_combine(result,::hash(value.qualification_unit));
}
struct SelectedGlobal {
    binding: BindingId,
    owner: BindingId,
    diagnostic_at: i64
}
struct LoopFrame {
    node: blot_parse_ast::Id,
    carries: const Entry[:],
    iterations: const BindingId[:],
    exits: i64 = 0
}
struct Flow {
    ty: blot_check_types::Id = blot_check_types::unit,
    exits: bool = false,
    returns: bool = false,
    breaks: bool = false
}
struct Qualified {
    namespace_: blot_parse_symbols::Symbol,
    member: blot_parse_symbols::Symbol
}
fn hash(key:Qualified)->u64 {return ::hash_combine(::hash(key.namespace_),::hash(key.member));}
struct QualifiedResolution {
    namespace_: blot_parse_symbols::Symbol,
    binding: BindingId
}
struct CatalogIndex {
    effect_family_names: dictionary<Qualified,u32>&,
    effect_family_identities: dictionary<Identity,u32>&,
    effect_members: dictionary<EffectMember,u32>&,
    effect_operation_names: dictionary<Qualified,u32>&,
    effect_template_identities: dictionary<Identity,u32>&,
    qualified_symbols: dictionary<blot_parse_symbols::Symbol,QualifiedResolution>&,
    contract_names: dictionary<Qualified,u32>&,
    implementation_names: dictionary<Qualified,u32>&,
    contract_identities: dictionary<Identity,u32>&,
    nominal_identities: dictionary<Identity,u32>&,
    producer_nominal_indices: dictionary<Identity,u32>&,
    constructor_identities: dictionary<Identity,u32>&,
    nominal_names: dictionary<Qualified,u32>&,
    constructor_names: dictionary<Qualified,u32>&,
    associated_ops: dictionary<AssociatedKey,u32>&,
    associated_members: dictionary<AssociatedMember,u32>&,
    qualified: dictionary<Qualified,BindingId>&,
    external_targets: dictionary<ExternalTarget,BindingId>&,
    globals: dictionary<blot_parse_symbols::Symbol,BindingId>&
}
struct ArmCapture {
    block_: blot_parse_ast::Id,
    versions_start: i64,
    versions_len: i64,
    carrying: bool = false
}
struct Engine {
    completed_projection_steps:i64=0,completed_projection_limit:i64=0,completed_projection_exhausted:bool=false,
    import_callees: u32[>..<]&,
    import_variables: u32[>..<]&,
    import_tables: blot_check_check_scheme_import::Tables,
    order_entries: OrderEntry[>..<]&,
    name_bytes: u8[>..<]&,
    diagnostic_bytes: u8[>..<]&,
    expected_bytes: u8[>..<]&,
    actual_bytes: u8[>..<]&,
    header_diagnostics: Diagnostic[>..]&,
    frontend_work: blot_work_counters::Frontend = blot_work_counters::Frontend {..},
    catalogs: CatalogIndex,
    editor_marker: blot_support::Option<EditorMarker>   = blot_support::none<EditorMarker>(),
    editor_capture: blot_support::Option<EditorCapture>   = blot_support::none<EditorCapture>(),
    active_aliases: dictionary<u32,bool>&,
    holes: Engine_holes[>..<]&,
    execution: PrivateExecution = PrivateExecution {..},
    inference_limit: i64 = 1000000,
    inference_transitions: i64 = 0,
    budget_exhaustion: BudgetExhaustion? = null,
    root_global: BindingId = 0,
    finishing_group: const BindingId[:] = default<const BindingId[:]>(),
    dependency_owner: blot_support::Option<BindingId>   = blot_support::none<BindingId>(),
    exact_argument_types: bool = false,
    computations: Computation[>..<]&,
    reflections: Reflection[>..<]&,
    case_pattern_source: blot_parse_ast::Id = 0,
    let_pattern_source: blot_parse_ast::Id = 0,
    tag_origins: TagOrigin[:] = default<TagOrigin[:]>(),
    scoped_parameter: blot_parse_ast::Id = 0,
    scoped_parameter_type: blot_check_types::Id = 0,
    expected_lambda_source: blot_parse_ast::Id = 0,
    // The type syntax that may be `own T`: a function type's parameter.
    own_position: blot_parse_ast::Id = 0,
    expected_lambda_type: blot_check_types::Id = 0,
    storage_frames: Engine_storage_frames[>..<]&,
    effect_runners: EffectRunner[>..<]&,
    effect_runner_ids: u32[:] = default<u32[:]>(),
    provider_blocks: ProviderBlock[>..<]&,
    provider_block_ids: u32[:] = default<u32[:]>(),
    body_closed_rows: ClosedRow[>..<]&,
    covered_requirements: CoveredRequirement[>..<]&,
    closed_row_keys: dictionary<ClosedRow,bool>&,
    row_sources: dictionary<u32,blot_parse_ast::Id>&,
    purity_origins: ModuleOrigins = ModuleOrigins {..},
    initializer_rejected: bool = false,
    lambda_closed_rows: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    dispatch_signatures: blot_check_types::Id[:] = default<blot_check_types::Id[:]>(),
    effect_families: EffectFamily[>..]&,
    effect_templates: EffectTemplate[>..]&,
    operation_uses: OperationUse[>..<]&,
    operation_refs: u32[:] = default<u32[:]>(),
    tree: const blot_parse_ast::Tree&,
    pool: blot_parse_symbols::Pool&,
    types: blot_check_types::Store,
    parameter_patterns: blot_check_parameter_patterns::Store,
    expr_types: blot_check_types::Id[:],
    resolved: BindingId[:],
    bindings: Binding[>..]&,
    imported_values: dictionary<ExternalTarget,u32>&,
    import_arena: ImportArena&,
    imported_globals: dictionary<blot_parse_symbols::Symbol,ExternalTarget>&,
    imported_qualified: dictionary<Qualified,ExternalTarget>&,
    merges: Merge[>..<]&,
    obligations: blot_check_types::Obligation[>..<]&,
    pending: PendingObligation[>..<]&,
    pending_ranges: PendingRange[>..<]&,
    pending_queue: blot_check_solver_worklist::Queue = blot_check_solver_worklist::Queue {..},
    scheme_dependencies: blot_check_scheme_dependencies::Cache&,
    counters: Counters = Counters {..},
    callee_memo: dictionary<const u8[:],CalleeOutcome>&,
    mark_depth: u32 = 0,
    dispatch_side: blot_reuse_dispatch_explanation::Side = blot_reuse_dispatch_explanation::Side.left,
    expansion_serial: u32 = 0,
    expansion_depth: u32 = 0,
    qualification_scope: blot_parse_ast::Id = 0,
    local_qualification_scope: blot_parse_ast::Id = 0,
    local_requirements_start: i64 = 0,
    qualifications: Qualification[>..<]&,
    qualification_uses: QualificationUse[>..<]&,
    forwarded_requirements: dictionary<ForwardedRequirement,bool>&,
    staged_global_diagnostics: dictionary<BindingId,Diagnostic[:]>&,
    selected_globals: SelectedGlobal[>..<]&,
    global_driver: bool = false,
    declared_obligations: blot_check_types::Obligation[>..<]&,
    predicate_origins: blot_parse_ast::Span[>..<]&,
    computed_variables: blot_check_types::Id[>..<]&,
    computed_rows: u32[>..<]&,
    diagnostics: Diagnostic[>..<]&,
    global_states: dictionary<BindingId,Global>&,
    active: BindingId[>..<]&,
    env: Entry[>..<]&,
    function_body: blot_parse_ast::Id = 0,
    function_exit_allowed: bool = false,
    function_exit_target: blot_check_types::Id = 0,
    function_result_expected: blot_check_types::Id = 0,
    function_exit_lambdas: blot_parse_ast::Id[>..<]&,
    statement_case: blot_parse_ast::Id = 0,
    arm_capture: blot_support::Option<ArmCapture> = blot_support::none<ArmCapture>(),
    arm_block: blot_parse_ast::Id = 0,
    arm_nested_return: blot_parse_ast::Id = 0,
    current: BindingId = 0,
    // Set for the one field projection an update or a store path makes next.
    field_path: bool = false,
    pending_start: i64 = 0,
    owner: blot_parse_ast::Id = 0,
    return_target: blot_check_types::Id = 0,
    ambient: blot_check_effects::Id = 0,
    counter: u32 = 0,
    depth: i64 = 0,
    permitted_intrinsic: blot_parse_ast::Id = 0,
    closed_type_variables: bool = false,
    implicit_row_parameters: bool = false,
    body_elaborations: i64 = 0,
    self_name: blot_parse_symbols::Symbol,
    unit: u32 = 1,
    builtin_catalog: bool = false,
    is_std: bool = false,
    spark_env_floor: i64 = -1,
    source_validation: bool = false,
    producer_capabilities: blot_support::Option<ProducerCapabilities>   = blot_support::none<ProducerCapabilities>(),
    producer_storage: blot_support::Option<ProducerStorage>   = blot_support::none<ProducerStorage>(),
    source_annotation_failed: bool = false,
    source_header_diagnostics_start:i64=0,source_header_diagnostics_count:i64=0,
    prelude_unit: u32 = 0,
    nominals: Nominal[>..]&,
    contracts: Contract[>..]&,
    contract_predicates: blot_check_types::Obligation[>..]&,
    contract_members: ContractMember[>..]&,
    implementations: Implementation[>..]&,
    implementation_predicates: blot_check_types::Obligation[>..]&,
    implementation_members: ImplementationMember[>..]&,
    member_templates: blot_reuse_principal_interface::MemberTemplate[>..<]&,
    checking_implementation: blot_support::Option<u32>   = blot_support::none<u32>(),
    implementation_bindings: dictionary<BindingId,u32>&,
    implementation_member_sources: dictionary<u32,blot_parse_ast::Id>&,
    implementation_member_states: dictionary<u32,Engine_implementation_member_states_state>&,
    active_evidence: Engine_active_evidence[>..<]&,
    implementation_order: u32[>..<]&,
    provisional_equations: Engine_provisional_equations[>..<]&,
    member_sources: dictionary<u32,blot_parse_ast::Id>&,
    member_states: dictionary<u32,Engine_member_states_state>&,
    associated_depth: i64 = 0,
    defer_associated: bool = false,
    has_associated_types: bool = false,
    contract_states: dictionary<u32,Engine_contract_states_state>&,
    contract_depth: i64 = 0,
    constructors: Constructor[>..]&,
    imported_constructor_heights: u8[>..]&,
    type_env: TypeEnvironment = TypeEnvironment {..},
    row_env: RowEnvironment = RowEnvironment {..},
    computation_annotations: blot_check_types::Id[>..<]&,
    annotation_binding: blot_parse_ast::Id = 0,
    inherited_types: i64 = 0,
    inherited_rows: i64 = 0,
    constructor_resolved: u32[:] = default<u32[:]>(),
    projections: u32[:] = default<u32[:]>(),
    access_paths: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    access_nodes: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    access_types: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    projection_resolved: u32[:] = default<u32[:]>(),
    projection_catalog: Projection[>..<]&,
    rebindings: Rebinding[:] = default<Rebinding[:]>(),
    loop_carries: LoopCarry[>..<]&,
    iterator_bodies: blot_parse_ast::Id[:] = default<blot_parse_ast::Id[:]>(),
    loop_ranges: blot_check_types::List[:] = default<blot_check_types::List[:]>(),
    loop_exits: LoopExit[>..<]&,
    statement_arms: StatementArm[>..<]&,
    loop_stack: LoopFrame[>..<]&,
    cases: blot_parse_ast::Id[>..<]&,
    associated: Associated[>..<]&,
    // Producers of the imported associated members no lookup has needed yet.
    associated_pending: ExternalTarget[>..<]&,
    // Zig walks imported_globals and catalogs.globals in the slot order of
    // its hash maps, and the order decides which scheme is imported first.
    // These tables keep the same keys in Zig's layout for those walks.
    zig_orders: u32[>..]&,
    imported_global_order: blot_support_zigmap::Map = blot_support_zigmap::Map{..},
    global_order: blot_support_zigmap::Map = blot_support_zigmap::Map{..}
}
type SchemeCopier=blot_check_check_scheme_import::Copier;
type BindingId = u32;
type Identity = blot_check_types::NominalIdentity;
type Nominal = blot_reuse_principal_interface::Nominal;
type Contract = blot_reuse_principal_interface::Contract;
type ContractMember = blot_reuse_principal_interface::ContractMember;
type Implementation = blot_reuse_principal_interface::Implementation;
type ImplementationMember = blot_reuse_principal_interface::ImplementationMember;
type Constructor = blot_reuse_principal_interface::Constructor;
type Associated = blot_reuse_principal_interface::Associated;
type EffectFamily = blot_reuse_principal_interface::EffectFamily;
type EffectTemplate = blot_reuse_principal_interface::EffectTemplate;
type Kind = blot_reuse_principal_interface::Kind;
type ExternalTarget = blot_reuse_principal_interface::ExternalTarget;
type PurityWitness = blot_reuse_purity_diagnostics::Witness;
fn reflectionKindCode(value: ReflectionKind) -> u32 { match value { of => {return 0;}, descriptor => {return 1;}, count => {return 2;}, has => {return 3;}, same => {return 4;}, } }
fn reflectionKindFromCode(code: u32) -> ReflectionKind,bool { match code { 0 => {return ReflectionKind.of,true;}, 1 => {return ReflectionKind.descriptor,true;}, 2 => {return ReflectionKind.count,true;}, 3 => {return ReflectionKind.has,true;}, 4 => {return ReflectionKind.same,true;}, _ => {return ReflectionKind.of,false;}, } }
fn blot_structural::equal(left: blot_check_check::ReflectionKind,right: blot_check_check::ReflectionKind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::ReflectionKind,sink:S&) {blot_structural::hash(sink,blot_check_check::reflectionKindCode(value));}
// Source identity and producer lookups are explicit immutable catalogs.
struct ModuleOrigin {unit:u32,name:const u8[:],source_available:bool=true}
struct ModuleOrigins {entries:const ModuleOrigin[:]=default<const ModuleOrigin[:]>(),has_source_available:bool=false,has_lookup:bool=false,failure:blot_error::Error=blot_error::Error.none}
fn name(self_:ModuleOrigins,unit:u32,current_unit:u32)->const u8[:],blot_error::Error {if self_.failure!=blot_error::Error.none {return default<const u8[:]>(),self_.failure;}for entry in self_.entries {if entry.unit==unit {return entry.name,blot_error::Error.none;}}if self_.has_lookup || self_.entries.len!=0 || unit!=current_unit {return default<const u8[:]>(),blot_error::Error.source_identity_unavailable;}return "main",blot_error::Error.none;}
fn sourceAvailable(self_:ModuleOrigins,unit:u32)->bool {for entry in self_.entries {if entry.unit==unit {return entry.source_available;}}return false;}
struct TraceSink {events:GlobalTrace[>..<]&}
fn observe(self_:TraceSink&,value:GlobalTrace) {self_.events.push(value);}
struct PrivateExecution {parallel_min_nodes:i64=4096,scheme_dependency_reuse:bool=true,indexed_scheme_membership:bool=true,closed_array_locals:bool=true,eager_scheme_summaries:bool=false,imported_summary_reuse:bool=true,alias_globals:bool=false,schedule_globals:bool=true,stats:AliasGlobalStats?=null,observe:TraceSink?=null}
struct ProducerCapabilityEntry {target:ExternalTarget,value:ProducerCapability}
// `interface` says the context can give the scheme a producer itself
// published for a target. With it, a module imports a member another
// module's catalog forwards without reading that module's copy, so the copy
// need not exist.
struct ProducerCapabilities {entries:const ProducerCapabilityEntry[:]=default<const ProducerCapabilityEntry[:]>(),context:blot_reuse_project_check::BodyNameContext=blot_reuse_project_check::BodyNameContext{..},interface:bool=false}
fn published(self_:ProducerCapabilities,target:ExternalTarget)->blot_support::Option<SchemeInterface> {if !self_.interface {return blot_support::none<SchemeInterface>();}let engine .= self_.context.borrow();if !engine {return blot_support::none<SchemeInterface>();}return engine.producerInterface(target);}
fn lookup(self_:ProducerCapabilities,target:ExternalTarget)->blot_support::Option<ProducerCapability> {if self_.context.engine!=null {let engine .= self_.context.borrow();if !engine {return blot_support::none<ProducerCapability>();}return engine.producerCapability(target);}for entry in self_.entries {if entry.target==target {return blot_support::some(entry.value);}}return blot_support::none<ProducerCapability>();}
struct ProducerStorageEntry {identity:Identity,value:blot_backend_opaque_storage::Storage}
struct ProducerStorage {entries:const ProducerStorageEntry[:]=default<const ProducerStorageEntry[:]>(),context:blot_reuse_project_check::BodyNameContext=blot_reuse_project_check::BodyNameContext{..}}
fn lookup(self_:ProducerStorage,identity:Identity)->blot_support::Option<blot_backend_opaque_storage::Storage> {if self_.context.engine!=null {let engine .= self_.context.borrow();if !engine {return blot_support::none<blot_backend_opaque_storage::Storage>();}return engine.producerStorage(identity);}for entry in self_.entries {if entry.identity==identity {return blot_support::some(entry.value);}}return blot_support::none<blot_backend_opaque_storage::Storage>();}

struct Engine_holes {  node: blot_parse_ast::Id, scope: blot_check_types::List, owner: BindingId  }
struct Engine_storage_frames {  read: blot_check_effects::Label, write: blot_check_effects::Label = 0, depth: i64  }
struct Engine_active_evidence {  contract: Identity, arguments: blot_check_types::List  }
struct Engine_provisional_equations {  declaration: u32, arguments: blot_check_types::List, variables: const blot_check_types::Id[:], rows: const blot_check_effects::Id[:]  }
struct Engine_type_env {  name: blot_parse_symbols::Symbol, ty: blot_check_types::Id  }
struct Engine_row_env {  name: blot_parse_symbols::Symbol, row: blot_check_effects::Id  }
enum Engine_implementation_member_states_state {  visiting, ready  }
enum Engine_member_states_state {  visiting, ready  }
enum Engine_contract_states_state {  visiting, ready  }
enum TypeApplication {missing_array,missing_nominal,extra}
enum DiagnosticContextKind {callee,argument,left_operand,right_operand}
struct DiagnosticContext {kind:DiagnosticContextKind,span:blot_parse_ast::Span}
struct Diagnostic {
    origin_unit:u32=0,code:Code,span:blot_parse_ast::Span,node:u32,
    type_application:blot_support::Option<TypeApplication>   = blot_support::none<TypeApplication>(),symbol:u32=0,implicit_type_witness:bool=false,
    source_terminator:blot_parse_source_operators::Terminator=blot_parse_source_operators::terminator_none,
    numeric_literal:blot_support::Option<blot_parse_ast::NumericFault>   = blot_support::none<blot_parse_ast::NumericFault>(),
    purity:blot_support::Option<PurityWitness>   = blot_support::none<PurityWitness>(),
    detail:blot_support::Option<const u8[:]>   = blot_support::none<const u8[:]>(),
    hole:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>   = blot_support::none<blot_reuse_hole_diagnostics::Snapshot>(),
    explanation:blot_support::Option<blot_reuse_dispatch_explanation::Explanation>   = blot_support::none<blot_reuse_dispatch_explanation::Explanation>(),
    contexts:DiagnosticContext[2]=[DiagnosticContext{DiagnosticContextKind.callee,blot_parse_ast::Span{0,0, ..}, ..},DiagnosticContext{DiagnosticContextKind.argument,blot_parse_ast::Span{0,0, ..}, ..}],context_len:u8=0
}
struct BudgetExhaustion {associated:bool=false,associated_limit:i64=0,exhausted:bool=false,name:u32=0,node:u32=0,span:blot_parse_ast::Span=blot_parse_ast::Span{0,0, ..}}
struct SourceValidation {
    owner:CheckedOwner=CheckedOwner{..},
    types:blot_check_types::Store,parameter_patterns:blot_check_parameter_patterns::Store,declarations:SourceDeclaration[:],resolved:u32[:],nominals:Nominal[:],contracts:Contract[:],contract_predicates:blot_check_types::Obligation[:],contract_members:ContractMember[:],implementations:Implementation[:],implementation_predicates:blot_check_types::Obligation[:],implementation_members:ImplementationMember[:],member_templates:blot_reuse_principal_interface::MemberTemplate[:],constructors:Constructor[:],effect_families:EffectFamily[:],effect_templates:EffectTemplate[:],associated:Associated[:],diagnostics:Diagnostic[:],unit:u32
}

fn message(self_:Diagnostic)->const u8[:] {
    if self_.detail.present {return self_.detail.value;}
    if self_.type_application.present {match self_.type_application.value {missing_array=>{return "Array requires one element type";},missing_nominal=>{return "partially applied type constructor requires another argument";},extra=>{return "type does not accept another argument; currying must be explicit in its declaration";},}}
    match self_.code {
        task_escape => {return "A task handle, group or loan outlives its task scope";},
        task_handle_consumed => {return "The task handle was already joined, cancelled or moved";},
        task_capture_transfer => {return "Task captures require an owning transfer or checked immutable sharing";},
        task_capability_shared => {return "A task capture shares a writable or scoped capability";},
        task_regions_overlap => {return "Task regions need one owner version and proved disjoint ranges";},
        task_host_contract => {return "Task host execution requires an explicit concurrent capability contract";},
        task_budget => {return "Task analysis exceeds its bounded state budget";},
        invalid_proof_operand => {return "A proof operand must name a preceding value of the required kind";},
        proof_scope_escape => {return "The proof refers to a value outside its complete contract";},
        proof_runtime_use => {return "An erased proof cannot be used as an ordinary runtime value";},
        proof_mismatch => {return "The witness does not establish this exact value proposition";},
        contradictory_proof => {return "The required proof contract contains contradictory facts";},
        proof_analysis_limit => {return "The required proof contract exceeds the analysis limit";},
        skolem_escape => {return "A rigid type escapes its quantified scope";},
        rank_mismatch => {return "The value does not satisfy the quantified annotation";},
        use_after_move => {return "This owning binding version was already moved";},
        duplicate_owner => {return "An affine owner cannot be copied";},
        borrow_conflict => {return "This owner has a conflicting live loan";},
        borrow_escape => {return "This loan outlives its owner scope";},
        once_reused => {return "This once callable may already have been invoked or moved";},
        multiplicity_unknown => {return "This callable has no checked affine invocation contract";},
        cleanup_not_safe => {return "Cleanup needs a finite non-suspending adapter contract";},
        usage_evidence_mismatch => {return "Usage evidence does not match the checked value";},
        usage_analysis_limit => {return "Usage analysis exceeds its bounded state budget";},
        package_expected => {return "An explicit existential package type is required";},
        package_witness_mismatch => {return "Package witnesses and opened binders must match the existential declaration";},
        package_escape => {return "An opened package identity escapes its lexical scope";},
        abstract_representation_access => {return "Reflection cannot inspect an abstract type witness";},
        code_shape_mismatch => {return "The value does not have the required typed code or descriptor shape";},
        stage_unavailable => {return "The value is unavailable at this stage; use explicit lift or splice";},
        cross_stage_authority => {return "The value carries authority that cannot cross a stage boundary";},
        descriptor_private => {return "The descriptor cannot expose this abstract or private shape";},
        generated_binding_escape => {return "A generated binding escapes its checked scope";},
        staging_budget => {return "Typed staging exceeds the analysis budget";},
        own_parameter => {return "`own` marks a parameter of a function or a lambda, the parameter of a function type, or an argument given away at a call; it is not a name, a contract member, an implementation member and a member an operator stands for cannot take one yet, and no other type can be `own`";},
        unbound_alias_row => {return "A data or effect declaration must carry an open alias row in an explicit type parameter";},
        undetermined_implementation => {return "The implementation head does not determine every declared parameter";},
        orphan_implementation => {return "The implementation producer owns neither the contract nor its anchor nominal";},
        overlapping_implementation => {return "Visible implementation heads have a common instantiation";},
        incompatible_implementation => {return "The matching implementation cannot satisfy its prerequisites";},
        recursive_evidence => {return "Implementation prerequisites repeat an active application";},
        missing_type_member => {return "The contract has no associated type member with this name";},
        associated_arity => {return "An associated projection requires the contract's complete argument shapes";},
        recursive_associated_type => {return "Associated type equations cannot recurse";},
        associated_limit => {return "Associated type normalization exceeded its work or depth limit";},
        missing_implementation => {return "This contract application requires an explicit implementation";},
        recursive_contract => {return "Contracts cannot include themselves recursively";},
        contract_arity => {return "A contract requires its declared type argument shapes";},
        recursive_type_alias => {return "Type aliases cannot refer to themselves recursively";},
        typed_hole => {return "Unfilled expression; expected";},
        effect_identity_scope => {return "A scoped effect requires a direct callback with one family annotation";},
        capability_escape => {return "A scoped capability or unknown authority footprint cannot cross its owner boundary";},
        capability_analysis_limit => {return "Scoped capability analysis exceeded its bound";},
        effect_member => {return "effect family requires an operation member";},
        integer_range => {return "integer literal exceeds U32 (4294967295)";},
        float_range => {return "floating-point literal exceeds finite F32 range";},
        float_literal => {return "invalid F32 literal";},
        duplicate_type_parameter => {return "Duplicate type parameter";},
        duplicate_type_field => {if self_.symbol != 0 {return "duplicate type argument field";}return "Duplicate type argument field";},
        type_parameter => {return "A type parameter pattern binds lowercase names";},
        type_argument => {return "A type argument must match its parameter pattern";},
        intrinsic_arity => {return "Invalid request intrinsic arity";},
        requests_scope => {return "@requests is only available as a request loop input";},
        yield_scope => {return "yield requires an operation clause in a request loop";},
        request_loop_scope => {return "A request loop requires an enclosing do block";},
        request_loop_body => {return "A request loop requires one effect/complete case";},
        request_loop_range => {return "A request loop cannot have a range endpoint";},
        request_binding => {return "The request case must match the loop binding";},
        request_completion => {return "A request loop requires exactly one complete clause";},
        request_clause_fallthrough => {return "An operation clause must reply or exit on each path";},
        request_completion_fallthrough => {return "A completion clause must return or break";},
        duplicate_request_handler => {return "An operation can have only one request clause";},
        request_case_scope => {return "Request cases require a request loop";},
        record_constructor => {return "named fields require a declared record constructor";},
        missing_record_field => {return "missing record field";},
        unknown_modifier => {return "only `io` may declare an entry point (`io name (...) => ...`, `io const`, or `io let`)";},
        guard_fallthrough => {return "let-else fallback must exit its enclosing do block";},
        product_arity => {return "cannot unify products with different element counts";},
        unknown_value => {if self_.implicit_type_witness {return "unknown value: Type";}return "unknown value";},
        unknown_operator => {return "operator has no source fixity declaration";},
        operator_associativity => {return "operators at equal precedence need compatible associativity or explicit parentheses";},
        operator_header_order => {return "operator declarations must precede values and data declarations";},
        operator_precedence => {return "operator precedence must be between 0 and 255";},
        duplicate_operator => {return "duplicate operator fixity declaration";},
        unsupported_prefix => {return "only F32 prefix negation (-) is supported";},
        unknown_intrinsic => {return "unknown compiler intrinsic";},
        product_index_literal => {return "product projection requires a literal zero-based index";},
        syntax => {return "Invalid syntax prevents semantic checking";},
        duplicate_name => {return "duplicate value or constructor declaration";},
        unknown_name => {return "Unknown value name";},
        type_mismatch => {return "Types do not match";},
        infinite_type => {return "A type contains itself";},
        effect_mismatch => {return "Effect rows do not match";},
        infinite_effect => {return "An effect row contains itself";},
        const_effect => {return "A constant initializer must be pure";},
        initializer_effect => {return "A runtime initializer must be pure";},
        let_effect => {return "A let or rebinding initializer must be pure";},
        sealed_effect => {return "Foreign is a compiler effect label, not a callable or providable operation";},
        effect_arity => {return "An effect operation has the wrong number of type arguments";},
        effect_family => {return "Read and write operations must belong to the same declared effect family";},
        unknown_effect => {return "Effect rows require Foreign or a declared effect operation or family";},
        invalid_effect_annotation => {return "A latent effect row annotates a function arrow";},
        invalid_constraint => {return "A where predicate has the wrong kind or argument shape";},
        higher_rank_constraint => {return "Parameter annotations cannot contain where clauses";},
        missing_predicate => {return "inferred requirement is absent from the explicit where clause";},
        ambiguous_qualified => {return "Qualified evidence still has unconstrained type or effect variables";},
        annotation_kind_mismatch => {return "One annotation name cannot be both a type and an effect-row variable";},
        unsupported_polymorphic_effect_label => {return "Open rows currently require concrete effect operation labels";},
        operation_signature => {return "An operation declaration specifies a unary parameter and result without an outer effect row";},
        type_arity => {return "A type application has the wrong number of arguments";},
        operation_target => {return "Expected the name of a declared effect operation";},
        invalid_state_provider => {return "State read and write must be distinct operations";},
        module_loader_required => {return "compile a source project to resolve file imports";},
        unsupported => {return "This semantic form is not implemented in the native compiler";},
        unsupported_attribute => {return "Tags are allowed only on const and let declarations";},
        function_target => {return "Effect reflection requires a statically named top-level function";},
        open_effect_descriptor => {return "Effect reflection requires a closed checked effect row";},
        recursive_tag => {return "A tagged declaration cannot refer to its own bound name";},
        unsupported_expression => {return "This expression is not implemented in the executable core";},
        unsupported_type => {return "This annotation type is not implemented in the native compiler";},
        ambiguous_operator => {return "Numeric operation has no admitted U32 or F32 evidence";},
        ambiguous_associated => {return "The expected result type does not identify an associated implementation";},
        missing_associated => {return "No compatible associated implementation exists";},
        ambiguous_member => {return "A field and associated function share this name";},
        missing_member => {return "This receiver has no associated member with this name";},
        type_constructor_required => {return "Monad requires a nominal type constructor value";},
        invalid_provider => {return "Do requires an effect provider or monad resolver";},
        resolver_required => {return "Break $ requires a monad resolver";},
        literal_required => {return "This compiler primitive requires a literal string argument";},
        call_arity => {return "This compiler primitive requires its exact literal and operand arguments";},
        break_scope => {return "Break requires an enclosing loop in this function";},
        continue_scope => {return "Continue requires an enclosing loop in this function";},
        function_return_required => {return "Every path through a function do block must return explicitly";},
        invalid_return => {return "Control cannot cross an enclosing computation boundary";},
        unreachable_statement => {if self_.source_terminator==blot_parse_source_operators::terminator_return {return "statement after return in the same suite";}if self_.source_terminator==blot_parse_source_operators::terminator_break {return "statement after break in the same suite";}if self_.source_terminator==blot_parse_source_operators::terminator_continue {return "statement after continue in the same suite";}return "A statement follows an unconditional return, break, or continue";},
        invalid_operator => {return "This operator is not declared or supported";},
        return_outside_block => {return "Break with a value requires an enclosing do block in this function";},
        return_outside_function => {return "Return requires an enclosing function; use break with a value to finish a do block";},
        return_across_continuation => {return "Return cannot cross a monadic continuation or a nested request callback; finish that do block with break value instead";},
        unknown_rebinding => {if self_.symbol != 0 {return ":= requires an existing local binding";}return "Rebinding requires an existing lexical name";},
        dead_rebinding => {return "This := inside a nested do: block is never read and leaves the enclosing binding unchanged; rebind it with if/else or a statement case, or assign a case expression";},
        case_arm_return => {return "This break would leave only its case arm and skip the rebinding the arm carries out; break directly in the arm's do: block or restructure with if/else";},
        nesting_limit => {return "Semantic nesting exceeds the compiler limit";},
        inference_budget => {return "Type inference exceeded this module's work budget";},
        constructor_marker => {return "Record constructors require # before the name";},
        private_access => {return "Private declaration or opaque representation is unavailable here";},
        private_identity_escape => {return "Public signature exposes a private declaration";},
        unknown_constructor => {if self_.symbol != 0 {return "unknown record constructor";}return "Unknown data constructor";},
        unknown_field => {return "This value has no such named field";},
        duplicate_field => {return "A field was supplied more than once";},
        missing_field => {return "A required record field is missing";},
        non_exhaustive_match => {return "Case patterns do not cover every possible value";},
        refutable_pattern => {return "A refutable let pattern requires an exiting else branch";},
        constructor_arity => {return "Constructor payload does not match its declared arity";},
        unknown_product_shape => {return "projection requires a known product arity; annotate the parameter with a product type";},
        product_index => {return "product projection index is outside its fixed arity";},
        pattern_arity => {return "Pattern shape does not match the scrutinee shape";},
        alternative_bindings => {return "alternative patterns must bind the same names";},
        duplicate_pattern_binding => {return "a pattern cannot bind the same name more than once";},
        duplicate_record_field => {return "record field is supplied more than once";},
        unknown_record_field => {return "record has no field named";},
        pattern_bindings => {return "Pattern alternatives must bind the same names";},
        value_pattern_type => {return "Value patterns require U32 or Bool";},
        non_exiting_fallback => {return "A refutable let failure branch must exit";},
        spark_generator => {return "A spark requires an irrefutable pattern";},
        spark_effectful => {return "A spark body must be pure (! {})";},
        spark_capture => {return "A spark body cannot rebind an outer local variable";},
        kernel_type => {return "A #kernel or #process declaration requires a valid Kernel or Process type matching its callables";},
        kernel_callable => {return "#kernel and #process targets must name top-level functions of the exact required arity";},
        kernel_effectful => {return "#kernel and #process functions must be pure (! {})";},
        std_only_intrinsic => {return "@flat intrinsics are internal to the standard library";},
        entry_type => {return "Invalid entry point or test boundary type";},
    }
}
fn sourceDeclaration(binding:Binding)->SourceDeclaration {return SourceDeclaration{binding.capability_parameters,binding.private,binding.name,binding.declaration,binding.kind,binding.named_function,binding.external, ..};}
fn declarationCatalog(producer)->DeclarationCatalog {return DeclarationCatalog {types:borrowedTypeSource(blot_check_types::canonical(producer.types.lease,producer.types.owner_generation)),parameter_patterns:borrowedPatternSource(producer.parameter_patterns),nominals:producer.nominals,constructors:producer.constructors,effect_families:producer.effect_families,effect_templates:producer.effect_templates,associated:producer.associated,unit:producer.unit,contracts:producer.contracts,contract_predicates:producer.contract_predicates,contract_members:producer.contract_members,implementations:producer.implementations,implementation_predicates:producer.implementation_predicates,implementation_members:producer.implementation_members, ..};}
// Producer readers expose immutable metadata and leased live-store observations.
fn liveCallees(producer:const Checked&)->LiveCallees {return LiveCallees{types:borrowedTypeSource(producer.types),bindings:producer.bindings,obligations:producer.obligations};}
fn liveProducer(producer:const Checked&)->LiveProducer {return LiveProducer{catalog:declarationCatalog(producer),callees:liveCallees(producer)};}
// Frozen readers retain fixed immutable views, never the producer's owner header.
fn frozenCallees(producer:blot_reuse_principal_interface::Interface,summaries:const SchemeSummary[:]=default<const SchemeSummary[:]>())->FrozenCallees {return FrozenCallees{graph:producer.graph,bindings:producer.bindings,obligations:producer.obligations,summaries:summaries};}
fn frozenProducer(producer:blot_reuse_principal_interface::Interface,summaries:const SchemeSummary[:]=default<const SchemeSummary[:]>())->FrozenProducer {return FrozenProducer{catalog:DeclarationCatalog{types:frozenTypeSource(producer.graph),parameter_patterns:frozenPatternSource(producer.patterns),nominals:producer.nominals,constructors:producer.constructors,effect_families:producer.effect_families,effect_templates:producer.effect_templates,associated:producer.associated,unit:producer.unit,contracts:producer.contracts,contract_predicates:producer.contract_predicates,contract_members:producer.contract_members,implementations:producer.implementations,implementation_predicates:producer.implementation_predicates,implementation_members:producer.implementation_members, ..},callees:frozenCallees(producer,summaries)};}
fn importedSummary(owner:FrozenCallees,binding:u32)->blot_support::Option<SchemeSummary> {
    if binding>=owner.summaries.len || !owner.summaries[binding].shareable {return blot_support::none<SchemeSummary>();}
    return blot_support::some(owner.summaries[binding]);
}
fn catalog(self_:ImportedCatalog)->DeclarationCatalog {
    let owner=self_.frozen;if owner.present {return owner.value.catalog;}
    let producer=self_.producer;assert(producer.present);return producer.value.catalog;
}
fn bindingCount(self_:ImportedCatalog)->i64 {let owner=self_.frozen;if owner.present {return owner.value.callees.bindings.len;}let producer=self_.producer;assert(producer.present);return producer.value.callees.bindings.len;}
fn declaration(self_:ImportedCatalog,id:u32)->SourceDeclaration {let frozen=self_.frozen;if frozen.present {let owner=frozen.value.callees;let value=owner.bindings[id];return SourceDeclaration {capability_parameters:value.capability_parameters,private:value.private,name:value.name,declaration:0,kind:value.kind,named_function:value.named_function,external:value.external, ..};}let producer=self_.producer;assert(producer.present);return sourceDeclaration(producer.value.callees.bindings[id]);}
fn interface(self_:ImportedCatalog,id:u32)->SchemeInterface {let frozen=self_.frozen;if frozen.present {let owner=frozen.value.callees;let value=owner.bindings[id]; return SchemeInterface{ summary:importedSummary(owner,id), producer_binding:id, capability_parameters:value.capability_parameters, named_function:value.named_function, types:frozenTypeSource(owner.graph), scheme:value.scheme, obligations:owner.obligations, callees:Callees.frozen{owner, ..}, .. };}
    let optional=self_.producer;assert(optional.present);let producer=optional.value.callees;let value=producer.bindings[id];var summary=blot_support::none<SchemeSummary>();if value.summary.shareable {summary=blot_support::some(value.summary);}return SchemeInterface{summary:summary,producer_binding:id,capability_parameters:value.capability_parameters,named_function:value.named_function,types:producer.types,scheme:value.scheme,obligations:producer.obligations,callees:Callees.live{producer, ..}, ..};
}
fn interface(self_:Callees,binding:u32)->blot_support::Option<SchemeInterface> {match self_ {
    none=>{return blot_support::none<SchemeInterface>();},
    live selected=>{let owner=selected.value;if binding==0 || binding>=owner.bindings.len {return blot_support::none<SchemeInterface>();}let value=owner.bindings[binding];var summary=blot_support::none<SchemeSummary>();if value.summary.shareable {summary=blot_support::some(value.summary);}return blot_support::some(SchemeInterface{ summary:summary, producer_binding:binding, capability_parameters:value.capability_parameters, named_function:value.named_function, types:owner.types, scheme:value.scheme, obligations:owner.obligations, callees:self_, .. });},
    frozen selected=>{let owner=selected.value;if binding==0 || binding>=owner.bindings.len {return blot_support::none<SchemeInterface>();}let value=owner.bindings[binding];return blot_support::some(SchemeInterface{ summary:importedSummary(owner,binding), producer_binding:binding, capability_parameters:value.capability_parameters, named_function:value.named_function, types:frozenTypeSource(owner.graph), scheme:value.scheme, obligations:owner.obligations, callees:self_, .. });},
}}
fn tagOrigin(origins:const TagOrigin[:],span:blot_parse_ast::Span)->u32 {var low:i64=0;var high=origins.len;while low<high {let middle=low+(high-low)/2;if origins[middle].span.start<=span.start {low=middle+1;}else {high=middle;}}if low==0 {return 0;}let candidate=origins[low-1];if span.end<=candidate.span.end {return candidate.attribute;}return 0;}
fn reflection(self_:const Checked&,id:u32)->blot_support::Option<Reflection> {var low:i64=0;var high=self_.reflections.len;while low<high {let middle=low+(high-low)/2;if self_.reflections[middle].node<id {low=middle+1;}else {high=middle;}}if low<self_.reflections.len && self_.reflections[low].node==id {return blot_support::some(self_.reflections[low]);}return blot_support::none<Reflection>();}
fn diagnosticSpan(self_:const Checked&,tree:const blot_parse_ast::Tree&,source:u32)->blot_parse_ast::Span {let span=tree.span(source);let origin=tagOrigin(self_.tag_origins,span);if origin==0 {return span;}return tree.span(origin);}
fn add(self_:Counters&,other:Counters) {self_.obligations_appended+=other.obligations_appended;self_.pending_peak=max(self_.pending_peak,other.pending_peak);self_.instantiations+=other.instantiations;self_.shared_uses+=other.shared_uses;self_.use_expansions+=other.use_expansions;self_.memo_hits+=other.memo_hits;self_.memo_misses+=other.memo_misses;self_.memo_declined+=other.memo_declined;self_.inference_steps+=other.inference_steps;self_.associated_steps+=other.associated_steps;self_.projection_memo_hits+=other.projection_memo_hits;}
fn prepareQualifiedName(pool:blot_parse_symbols::Pool&,namespace_:u32,owner:u32,member:u32)->blot_error::Error {if owner==0 || member==0 {return blot_error::Error.none;}var text:u8[>..<]=[];if namespace_!=0 {text.append(pool.get(namespace_));text.push('.' as u8);}text.append(pool.get(owner));text.push('.' as u8);text.append(pool.get(member));let symbol,err=pool.intern(text);return err;}
fn prepareGeneratedNames(pool:blot_parse_symbols::Pool&,tree:const blot_parse_ast::Tree&,catalogs:const ImportedCatalog[:])->blot_error::Error {let result,err=pool.intern("result");if err!=blot_error::Error.none {return err;}let effects,err=pool.intern("effects");if err!=blot_error::Error.none {return err;}let ast_walk_1_count=tree.roots.items.len;for ast_walk_1_index in 0..ast_walk_1_count {let root=tree.roots.items[ast_walk_1_index];let node=tree.node(root);if node.tag==blot_parse_ast::tag_contract_decl {let ast_walk_3_source=node.b;let ast_walk_3_count=tree.children(ast_walk_3_source).len;for ast_walk_3_index in 0..ast_walk_3_count {let member=tree.children(ast_walk_3_source)[ast_walk_3_index];let err=prepareQualifiedName(pool,0,node.a,tree.node(member).a);if err!=blot_error::Error.none {return err;}}}else if node.tag==blot_parse_ast::tag_value_decl {let decl=tree.value_decl(root);if !decl.runtime && decl.annotation!=0 && lastDot(pool.get(decl.name)).present {var body=decl.body;while body!=0 && tree.node(body).tag==blot_parse_ast::tag_group {body=tree.node(body).a;}if body!=0 && tree.node(body).tag==blot_parse_ast::tag_record && tree.node(body).a==0 {let fcount=tree.children(body).len;for fi in 0..fcount {let field=tree.children(body)[fi];let err=prepareQualifiedName(pool,0,decl.name,tree.node(field).a);if err!=blot_error::Error.none {return err;}}}}}}
    for imported in catalogs {if imported.kind!=ImportedCatalog_kind.contract {continue;}let producer=imported.catalog();let contract=producer.contracts[imported.index];for member in producer.contract_members[contract.members.start..contract.members.start+contract.members.len] {if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {let err=prepareQualifiedName(pool,imported.namespace_,imported.name,member.name);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;
}
fn collectModuleHeaders(self_:Engine&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],allow_imports:bool)->blot_error::Error {
    let tree .= self_.tree;let pool .= self_.pool;let unit=self_.unit;let err=self_.dataHeaders();if err!=blot_error::Error.none {return err;}let err=self_.contractHeaders();if err!=blot_error::Error.none {return err;}
    let ast_walk_4_count=tree.roots.items.len;for ast_walk_4_index in 0..ast_walk_4_count {let id=tree.roots.items[ast_walk_4_index];let tag=tree.node(id).tag;if tag==blot_parse_ast::tag_data_decl || tag==blot_parse_ast::tag_type_alias_decl || tag==blot_parse_ast::tag_contract_decl || tag==blot_parse_ast::tag_effect_decl || tag==blot_parse_ast::tag_effect_type_decl {continue;}if allow_imports && (tag==blot_parse_ast::tag_import_decl || tag==blot_parse_ast::tag_export_decl) {continue;}
        if tag==blot_parse_ast::tag_entry_kernel_decl {
            let declaration=tree.entry_kernel_decl(id);
            if self_.hasGlobal(declaration.name) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}
            let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}
            let binding,err=self_.addBinding(Binding{ private:false, name:declaration.name, declaration:id, owner:id, kind:blot_reuse_principal_interface::Kind.global, named_function:false, ty:fresh, .. });if err!=blot_error::Error.none {return err;}
            self_.catalogs.globals.insert(declaration.name,binding);blot_support_zigmap::put(self_.zig_orders,self_.global_order,declaration.name,0);self_.global_states.insert(binding,Global{..});self_.resolved[id]=binding;
            if declaration.stateless {
                let fn_fresh,ferr=self_.types.fresh();if ferr!=blot_error::Error.none {return ferr;}
                let fn_binding,berr=self_.addBinding(Binding{ private:true, name:0, declaration:id, owner:id, kind:blot_reuse_principal_interface::Kind.global, named_function:true, ty:fn_fresh, .. });if berr!=blot_error::Error.none {return berr;}
                self_.global_states.insert(fn_binding,Global{state:State.complete, ..});
                self_.resolved[declaration.first]=fn_binding;
            }
            continue;
        }
        if tag==blot_parse_ast::tag_entry_process_decl {
            let declaration=tree.entry_process_decl(id);
            if self_.hasGlobal(declaration.name) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}
            let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}
            let binding,err=self_.addBinding(Binding{ private:false, name:declaration.name, declaration:id, owner:id, kind:blot_reuse_principal_interface::Kind.global, named_function:false, ty:fresh, .. });if err!=blot_error::Error.none {return err;}
            self_.catalogs.globals.insert(declaration.name,binding);blot_support_zigmap::put(self_.zig_orders,self_.global_order,declaration.name,0);self_.global_states.insert(binding,Global{..});self_.resolved[id]=binding;
            continue;
        }
        if tag!=blot_parse_ast::tag_value_decl {let err=self_.diagnostic(Code.unsupported,id);if err!=blot_error::Error.none {return err;}continue;}let declaration=tree.value_decl(id);if self_.hasGlobal(declaration.name) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}
        let named=tree.node(declaration.body).tag==blot_parse_ast::tag_lambda && declaration.attributes.len==0;let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}let binding,err=self_.addBinding(Binding{ private:blot_parse_ast::declaration_traits(tree,id).private, name:declaration.name, declaration:id, owner:id, kind:blot_reuse_principal_interface::Kind.global, named_function:named, ty:fresh, .. });if err!=blot_error::Error.none {return err;}self_.catalogs.globals.insert(declaration.name,binding);blot_support_zigmap::put(self_.zig_orders,self_.global_order,declaration.name,0);self_.global_states.insert(binding,Global{..});self_.resolved[id]=binding;
    }
    // Catalogs repeat the members they import; each copy is recorded once.
    var imported_associated:dictionary<ImportedAssociated,bool> = dictionary<ImportedAssociated,bool>{};
    for imported in catalogs {let err=self_.importCatalog(imported,imported_associated);if err!=blot_error::Error.none {return err;}}for imported in source_catalogs {let err=self_.importCatalog(imported,imported_associated);if err!=blot_error::Error.none {return err;}}
    for imported in imports {var err=blot_error::Error.none;if self_.source_validation {err=self_.importHeader(SourceHeader{ capability_parameters:imported.interface.capability_parameters, name:imported.name, namespace_:imported.namespace_, member:imported.member, target:imported.target, named_function:imported.interface.named_function, origin:imported.origin, expose:imported.expose, .. });}else {err=self_.importBinding(imported);}if err!=blot_error::Error.none {return err;}}
    for imported in headers {let err=self_.importHeader(imported);if err!=blot_error::Error.none {return err;}}let err=self_.effectHeaders();if err!=blot_error::Error.none {return err;}
    {let err=self_.ownParameterHeaders();if err!=blot_error::Error.none {return err;}}
    let err=self_.dataBodies();if err!=blot_error::Error.none {return err;}self_.prepareOpaqueStorage();for index in 0..self_.contracts.len {let err=self_.resolveContract(index as u32);if err!=blot_error::Error.none {return err;}}
    let contract_member_count=self_.contract_members.len;for index in 0..contract_member_count {let member=self_.contract_members[index];if member.contract.unit!=unit || member.root==0 {continue;}let source:u32={let scalar_lookup_1 .= self_.member_sources.get(index as u32);assert(scalar_lookup_1!=null);let scalar_value_1:u32=scalar_lookup_1;scalar_value_1};let normalized,err=self_.normalizeAssociated(member.root,source,false);if err!=blot_error::Error.none {return err;}let err=self_.validateMemberRequirements(index as u32);if err!=blot_error::Error.none {return err;}if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {if self_.types.node(self_.types.head(normalized,0)).tag!=blot_check_types::Tag.function {let err=self_.diagnostic(Code.annotation_kind_mismatch,source);if err!=blot_error::Error.none {return err;}}else {self_.contract_members[index].root=normalized;}}}
    let ast_walk_5_count=tree.roots.items.len;for ast_walk_5_index in 0..ast_walk_5_count {let id=tree.roots.items[ast_walk_5_index];if tree.node(id).tag!=blot_parse_ast::tag_value_decl {continue;}let text=pool.get(tree.value_decl(id).name);var dot=blot_support::none<i64>();for character,index in text {if character=='.' as u8 {dot=blot_support::some(index);}}if !dot.present {continue;}let path=self_.textCatalogKey(text[..dot.value]);if !path.present {continue;}let contract_index:u32={let scalar_lookup_2 .= self_.catalogs.contract_names.get(path.value);if !scalar_lookup_2 {continue;}let scalar_value_2:u32=scalar_lookup_2;scalar_value_2};let member_name,present=pool.lookup(text[dot.value+1..]);if !present {continue;}if self_.memberIndex(self_.contracts[contract_index],member_name).present {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}}}
    let err=self_.implementationHeaders();if err!=blot_error::Error.none {return err;}let err=self_.implementationCoherence();if err!=blot_error::Error.none {return err;}let err=self_.implementationBodies();if err!=blot_error::Error.none {return err;}let err=self_.memberTemplates();if err!=blot_error::Error.none {return err;}let err=self_.indexAssociated();if err!=blot_error::Error.none {return err;}
    let ast_walk_6_count=tree.roots.items.len;for ast_walk_6_index in 0..ast_walk_6_count {let id=tree.roots.items[ast_walk_6_index];if tree.node(id).tag==blot_parse_ast::tag_value_decl {let key=self_.qualifiedKey(tree.value_decl(id).name);if key.present && self_.hasQualified(key.value) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;
}
fn sourceIssueCode(value:u32)->Code {match value {
    blot_parse_source_operators::c_own_name=>{return Code.own_parameter;},
    blot_parse_source_operators::c_effect_member=>{return Code.effect_member;},blot_parse_source_operators::c_constructor_marker=>{return Code.constructor_marker;},blot_parse_source_operators::c_integer_range=>{return Code.integer_range;},blot_parse_source_operators::c_float_range=>{return Code.float_range;},blot_parse_source_operators::c_float_literal=>{return Code.float_literal;},
    blot_parse_source_operators::c_duplicate_name=>{return Code.duplicate_name;},blot_parse_source_operators::c_alternative_bindings=>{return Code.alternative_bindings;},blot_parse_source_operators::c_duplicate_pattern_binding=>{return Code.duplicate_pattern_binding;},blot_parse_source_operators::c_duplicate_record_field=>{return Code.duplicate_record_field;},blot_parse_source_operators::c_unknown_record_field=>{return Code.unknown_record_field;},blot_parse_source_operators::c_record_constructor=>{return Code.record_constructor;},blot_parse_source_operators::c_missing_record_field=>{return Code.missing_record_field;},blot_parse_source_operators::c_unknown_modifier=>{return Code.unknown_modifier;},blot_parse_source_operators::c_unknown_operator=>{return Code.unknown_operator;},blot_parse_source_operators::c_unknown_value=>{return Code.unknown_value;},blot_parse_source_operators::c_unknown_rebinding=>{return Code.unknown_rebinding;},blot_parse_source_operators::c_unreachable_statement=>{return Code.unreachable_statement;},
    blot_parse_source_operators::c_operator_associativity=>{return Code.operator_associativity;},blot_parse_source_operators::c_operator_header_order=>{return Code.operator_header_order;},blot_parse_source_operators::c_operator_precedence=>{return Code.operator_precedence;},blot_parse_source_operators::c_duplicate_operator=>{return Code.duplicate_operator;},blot_parse_source_operators::c_unsupported_prefix=>{return Code.unsupported_prefix;},blot_parse_source_operators::c_unknown_intrinsic=>{return Code.unknown_intrinsic;},blot_parse_source_operators::c_unsupported_expression=>{return Code.unsupported_expression;},blot_parse_source_operators::c_private_access=>{return Code.private_access;},blot_parse_source_operators::c_unknown_constructor=>{return Code.unknown_constructor;},blot_parse_source_operators::c_sealed_effect=>{return Code.sealed_effect;},blot_parse_source_operators::c_call_arity=>{return Code.call_arity;},blot_parse_source_operators::c_requests_scope=>{return Code.requests_scope;},blot_parse_source_operators::c_yield_scope=>{return Code.yield_scope;},blot_parse_source_operators::c_break_scope=>{return Code.break_scope;},blot_parse_source_operators::c_continue_scope=>{return Code.continue_scope;},blot_parse_source_operators::c_literal_required=>{return Code.literal_required;},blot_parse_source_operators::c_product_index_literal=>{return Code.product_index_literal;},blot_parse_source_operators::c_nesting_limit=>{return Code.nesting_limit;},
    _=>{return Code.unsupported;},
}}
fn validateModuleBodies(self_:Engine&,skip_root:const bool[:]=default<const bool[:]>())->blot_error::Error {
    let tree .= self_.tree;let pool .= self_.pool;let unit=self_.unit;if self_.source_validation {let start=self_.header_diagnostics.len;let count=self_.diagnostics.len;
        for index in 0..count {let diagnostic=self_.diagnostics[index];self_.header_diagnostics.push(canonicalDiagnostic(diagnostic));}
        self_.source_header_diagnostics_start=start;self_.source_header_diagnostics_count=count;self_.diagnostics.clear();}
    var source_issue=blot_parse_source_operators::Issue{..};var has_issue=false;
    if tree.diagnostics.len==0 {let issue,present,err=blot_parse_source_operators::validate(tree,pool,self_,skip_root);if err!=blot_error::Error.none {return err;}source_issue=issue;has_issue=present;}
    if has_issue {deinitDiagnosticPayloads(self_.diagnostics);self_.diagnostics.clear();var numeric=blot_support::none<blot_parse_ast::NumericFault>();       if source_issue.has_numeric_literal {numeric=blot_support::some(source_issue.numeric_literal);}              let __field_order_37_code: blot_check_check::Code = sourceIssueCode(source_issue.code); let __field_order_38_node: u32 = source_issue.node; let __field_order_39_span: blot_parse_ast::Span = blot_parse_ast::Span{source_issue.point,source_issue.point, ..}; let __field_order_40_symbol: u32 = source_issue.symbol; let __field_order_41_implicit_type_witness: bool = source_issue.implicit_type_witness; let __field_order_42_source_terminator: blot_parse_source_operators::Terminator = source_issue.terminator; let __field_order_43_numeric_literal: blot_support::Option<blot_parse_ast::NumericFault> = numeric; var detail=blot_support::none<const u8[:]>(); if __field_order_37_code==Code.unknown_value && !__field_order_41_implicit_type_witness && __field_order_40_symbol!=0 {detail=self_.unknownSymbolDetail(__field_order_40_symbol);} self_.diagnostics.push(Diagnostic{ code: __field_order_37_code, span: __field_order_39_span, node: __field_order_38_node, symbol: __field_order_40_symbol, implicit_type_witness: __field_order_41_implicit_type_witness, source_terminator: __field_order_42_source_terminator, numeric_literal: __field_order_43_numeric_literal, detail: detail, .. });}
    if !self_.source_validation && tree.diagnostics.len==0 && !has_issue {
        let ast_walk_8_count=tree.roots.items.len;for ast_walk_8_index in 0..ast_walk_8_count {if skip_root.len!=0 && skip_root[ast_walk_8_index] {continue;}let id=tree.roots.items[ast_walk_8_index];let rtag=tree.node(id).tag;if (rtag==blot_parse_ast::tag_value_decl || rtag==blot_parse_ast::tag_entry_kernel_decl || rtag==blot_parse_ast::tag_entry_process_decl) && self_.resolved[id]!=0 {self_.root_global=self_.resolved[id];let err=self_.inferGlobal(self_.resolved[id]);if err!=blot_error::Error.none {return err;}}}
        if skip_root.len==0 {for declaration in self_.implementations {if declaration.identity.unit!=unit {continue;}for member in self_.implementation_members[declaration.members.start..declaration.members.start+declaration.members.len] {if member.kind!=blot_reuse_principal_interface::ImplementationMemberKind.value {continue;}self_.root_global=member.target.binding;let err=self_.inferGlobal(member.target.binding);if err!=blot_error::Error.none {return err;}}}}self_.root_global=0;
        let err=self_.finish();if err!=blot_error::Error.none {return err;}let err=self_.finishReflection();if err!=blot_error::Error.none {return err;}let err=self_.finishHoles();if err!=blot_error::Error.none {return err;}
        if self_.diagnostics.len==0 {let err=self_.validateVisibility();if err!=blot_error::Error.none {return err;}}
    }return blot_error::Error.none;
}
fn firstDot(text:const u8[:])->blot_support::Option<i64> {for value,index in text {if value=='.' as u8 {return blot_support::some(index);}}return blot_support::none<i64>();}
fn lastDot(text:const u8[:])->blot_support::Option<i64> {var index=text.len;while index!=0 {index-=1;if text[index]=='.' as u8 {return blot_support::some(index);}}return blot_support::none<i64>();}
fn qualifiedKey(self_:const Engine&,name:u32)->blot_support::Option<Qualified> {let text=self_.pool.get(name);let separator=firstDot(text);if !separator.present {return blot_support::none<Qualified>();}let namespace_,ns_present=self_.pool.lookup(text[..separator.value]);if !ns_present {return blot_support::none<Qualified>();}let member,present=self_.pool.lookup(text[separator.value+1..]);if !present {return blot_support::none<Qualified>();}return blot_support::some(Qualified{namespace_,member, ..});}
fn qualifiedBinding(self_:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let found .= self_.catalogs.qualified_symbols.get(name);if found {return blot_support::some(found.binding),blot_error::Error.none;}let key=self_.qualifiedKey(name);if !key.present {return blot_support::none<u32>(),blot_error::Error.none;}let binding,err=self_.qualifiedImportBinding(key.value);if err!=blot_error::Error.none || !binding.present {return binding,err;}self_.catalogs.qualified_symbols.insert(name,QualifiedResolution{key.value.namespace_,binding.value, ..});return binding,blot_error::Error.none;}
fn globalBinding(self_:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let text=self_.pool.get(name);let separator=firstDot(text);if separator.present {let root,present=self_.pool.lookup(text[..separator.value]);if present && self_.lookup(root).present {return blot_support::none<u32>(),blot_error::Error.none;}}return self_.catalogBinding(name);}
fn catalogBinding(self_:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let scalar_lookup_3 .= self_.catalogs.globals.get(name);if scalar_lookup_3 {let binding:u32=scalar_lookup_3;return blot_support::some(binding),blot_error::Error.none;}let target .= self_.imported_globals.get(name);if target {return self_.importedBinding(target);}return self_.qualifiedBinding(name);}
fn sourceDuplicateName(self_:const Engine&)->blot_support::Option<u32> {if self_.source_validation {for constructor in self_.constructors[1..] {if constructor.identity.unit!=self_.unit {continue;}let scalar_lookup_4 .= self_.catalogs.globals.get(constructor.name);if scalar_lookup_4 {let binding:u32=scalar_lookup_4;let declaration=self_.bindings[binding].declaration;let nom=self_.nominals[constructor.nominal];let ctor_ast=self_.tree.children(self_.tree.node(nom.declaration).b)[constructor.tag];if self_.tree.span(declaration).start<self_.tree.span(ctor_ast).start {return blot_support::some(declaration);}return blot_support::some(ctor_ast);}let target .= self_.imported_globals.get(constructor.name);if target {let found .= self_.imported_values.get(target);assert(found!=null);let index:u32=found;let imported=self_.import_arena.records[index];return blot_support::some(imported.origin);}}}
    var diagnostic_count=self_.diagnostics.len;if self_.source_validation {diagnostic_count=self_.source_header_diagnostics_count;}for diagnostic_index in 0..diagnostic_count {let issue=sourceDiagnosticAt(self_,diagnostic_index);if issue.code!=Code.duplicate_name || self_.tree.node(issue.node).tag!=blot_parse_ast::tag_value_decl {continue;}let name=self_.tree.value_decl(issue.node).name;let scalar_lookup_5 .= self_.catalogs.globals.get(name);if scalar_lookup_5 {let binding:u32=scalar_lookup_5;return blot_support::some(self_.bindings[binding].declaration);}let target .= self_.imported_globals.get(name);if target {let found .= self_.imported_values.get(target);assert(found!=null);let index:u32=found;let imported=self_.import_arena.records[index];return blot_support::some(imported.origin);}}return blot_support::none<u32>();
}
fn sourceTypeApplication(self_:const Engine&,symbol:u32)->bool {let scalar_lookup_6 .= self_.catalogs.nominal_names.get(self_.catalogKey(symbol));if scalar_lookup_6 {let nominal:u32=scalar_lookup_6;return self_.nominals[nominal].patterns.len!=0;}let template=self_.catalogOperationTemplate(symbol);if template.present {return self_.effect_families[self_.effect_templates[template.value].family].patterns.len!=0;}return false;}
fn sourceNonCallableEffect(self_:const Engine&,symbol:u32)->bool {let scalar_lookup_7 .= self_.catalogs.effect_family_names.get(self_.catalogKey(symbol));if scalar_lookup_7 {let family:u32=scalar_lookup_7;return !self_.effect_families[family].callable;}if self_.hasGlobal(symbol) || self_.hasQualified(self_.catalogKey(symbol)) || self_.catalogOperationTemplate(symbol).present {return false;}let text=self_.pool.get(symbol);var prefix_end=text.len;
    while true {let separator=lastDot(text[..prefix_end]);if !separator.present {break;}prefix_end=separator.value;let prefix=text[..prefix_end];let dot=firstDot(prefix);var namespace_:u32=0;var member:u32=0;if dot.present {let ns,present=self_.pool.lookup(prefix[..dot.value]);if !present {continue;}namespace_=ns;let value,present=self_.pool.lookup(prefix[dot.value+1..]);if !present {continue;}member=value;}else {let value,present=self_.pool.lookup(prefix);if !present {continue;}member=value;}let scalar_lookup_8 .= self_.catalogs.effect_family_names.get(Qualified{namespace_,member, ..});if scalar_lookup_8 {let family:u32=scalar_lookup_8;return !self_.effect_families[family].callable;}}
    return false;
}
fn sourceParameterMatches(self_:Engine&,param_pattern:u32,argument:u32)->bool,blot_error::Error {let point=self_.types.mark();let diagnostic_count=self_.diagnostics.len;let type_names=self_.type_env.items.len;let row_names=self_.row_env.items.len;self_.mark_depth+=1;let converted,err=self_.parameterArgument(param_pattern,argument,false,0);let result=self_.diagnostics.len==diagnostic_count;self_.mark_depth-=1;self_.types.rollback(point);deinitDiagnosticPayloads(self_.diagnostics[diagnostic_count..]);self_.diagnostics.resize(diagnostic_count);self_.type_env.resize(type_names);self_.row_env.resize(row_names);return result,err;}
fn sourceArgumentIsType(self_:Engine&,original:u32,argument:u32)->bool,blot_error::Error {var head=original;var consumed:i64=0;while true {let node=self_.tree.node(head);if node.tag==blot_parse_ast::tag_group {head=node.a;}else if node.tag==blot_parse_ast::tag_apply {consumed+=1;head=node.a;}else {break;}}let node=self_.tree.node(head);if node.tag!=blot_parse_ast::tag_name {return false,blot_error::Error.none;}let template=self_.catalogOperationTemplate(node.a);if !template.present {return false,blot_error::Error.none;}let patterns=self_.effect_families[self_.effect_templates[template.value].family].patterns;if consumed>=patterns.len {return false,blot_error::Error.none;}let param_pattern=self_.parameter_patterns.list(patterns)[consumed];let possible,err=self_.possibleParameterArgument(param_pattern,argument,true,0);if err!=blot_error::Error.none || !possible {return possible,err;}return self_.sourceParameterMatches(param_pattern,argument);}
fn sourcePrivateConstructor(self_:const Engine&,symbol:u32)->bool {let nominal:u32={let scalar_lookup_9 .= self_.catalogs.nominal_names.get(self_.catalogKey(symbol));if !scalar_lookup_9 {return false;}let scalar_value_9:u32=scalar_lookup_9;scalar_value_9};return self_.nominals[nominal].is_opaque && self_.nominals[nominal].identity.unit!=self_.unit;}
fn sourceConstructorExists(self_:const Engine&,symbol:u32)->bool {return self_.catalogs.constructor_names.contains(self_.catalogKey(symbol));}
fn sourceRecordFieldExists(self_:const Engine&,symbol:u32,field:u32)->blot_support::Option<bool> {let constructor:u32={let scalar_lookup_10 .= self_.catalogs.constructor_names.get(self_.catalogKey(symbol));if !scalar_lookup_10 {return blot_support::none<bool>();}let scalar_value_10:u32=scalar_lookup_10;scalar_value_10};let definition=self_.constructors[constructor];if !definition.declared_record {return blot_support::none<bool>();}if definition.payload==0 {return blot_support::some(false);}let record=self_.types.node(definition.payload);if record.tag!=blot_check_types::Tag.record {return blot_support::none<bool>();}for index in 0..record.b {if self_.types.recordField(record,index).name==field {return blot_support::some(true);}}return blot_support::some(false);}
fn sourceRecordTarget(self_:Engine&,symbol:u32)->u32,blot_error::Error {let scalar_lookup_11 .= self_.catalogs.constructor_names.get(self_.catalogKey(symbol));if scalar_lookup_11 {let constructor:u32=scalar_lookup_11;let definition=self_.constructors[constructor];if definition.declared_record || (self_.nominals[definition.nominal].is_opaque && self_.types.node(definition.payload).tag==blot_check_types::Tag.record) {return blot_parse_source_operators::record_target_record,blot_error::Error.none;}return blot_parse_source_operators::record_target_other,blot_error::Error.none;}let value=self_.hasCatalogBinding(symbol) || self_.catalogOperationTemplate(symbol).present || self_.catalogs.effect_family_names.contains(self_.catalogKey(symbol));if value {return blot_parse_source_operators::record_target_other,blot_error::Error.none;}return blot_parse_source_operators::record_target_missing,blot_error::Error.none;}
fn sourceMissingRecordField(self_:const Engine&,symbol:u32,fields:const u32[:])->blot_support::Option<u32> {let constructor:u32={let scalar_lookup_12 .= self_.catalogs.constructor_names.get(self_.catalogKey(symbol));if !scalar_lookup_12 {return blot_support::none<u32>();}let scalar_value_12:u32=scalar_lookup_12;scalar_value_12};let payload=self_.constructors[constructor].payload;if payload==0 {return blot_support::none<u32>();}let record=self_.types.node(payload);if record.tag!=blot_check_types::Tag.record {return blot_support::none<u32>();}for index in 0..record.b {let field=self_.types.recordField(record,index).name;var supplied=false;for id in fields {if self_.tree.node(id).a==field {supplied=true;break;}}if !supplied && self_.constructorFieldDefault(constructor,field)==0 {return blot_support::some(field);}}return blot_support::none<u32>();}
fn sourceIntrinsicArity(self_:const Engine&,symbol:u32)->blot_support::Option<i64> {return exactIntrinsicArity(self_.pool.get(symbol));}
fn sourceIntrinsicKnown(self_:const Engine&,symbol:u32)->bool {return intrinsicArity(self_.pool.get(symbol)).present;}
fn sourceSymbolicDeclared(self_:const Engine&,symbol:u32)->bool {let text=self_.pool.get(symbol);return text=="|>" || symbolOperator(text)!=blot_check_types::Operator.none;}
fn sourceOperatorTargetExists(self_:Engine&,name:u32)->bool,blot_error::Error {if self_.hasCatalogBinding(name) {return true,blot_error::Error.none;}let key=self_.catalogKey(name);return self_.catalogs.constructor_names.contains(key) || self_.catalogOperationTemplate(name).present,blot_error::Error.none;}
fn sourceQualifiedExists(self_:const Engine&,namespace_:u32,member:u32)->bool {let key=Qualified{namespace_,member, ..};return self_.hasQualified(key) || self_.catalogs.nominal_names.contains(key) || self_.catalogs.effect_family_names.contains(key) || self_.catalogs.effect_operation_names.contains(key);}
fn sourceValueExists(self_:Engine&,name:u32)->bool,blot_error::Error {let exists,err=self_.sourceOperatorTargetExists(name);if err!=blot_error::Error.none || exists {return exists,err;}let key=self_.catalogKey(name);if self_.catalogs.nominal_names.contains(key) || self_.catalogs.effect_family_names.contains(key) {return true,blot_error::Error.none;}let text=self_.pool.get(name);let separator=firstDot(text);var root=name;if separator.present {let value,present=self_.pool.lookup(text[..separator.value]);if !present {return false,blot_error::Error.none;}root=value;}if root!=name {let suffix=text[self_.pool.get(root).len+1..];let dot=firstDot(suffix);var end=suffix.len;if dot.present {end=dot.value;}let member,present=self_.pool.lookup(suffix[..end]);if present && self_.hasQualified(Qualified{root,member, ..}) {return true,blot_error::Error.none;}}
    if root!=name {let exists,err=self_.sourceOperatorTargetExists(root);if err!=blot_error::Error.none || exists {return exists,err;}}return self_.catalogs.nominal_names.contains(Qualified{0,root, ..}) || self_.catalogs.effect_family_names.contains(Qualified{0,root, ..}),blot_error::Error.none;
}
struct SourceAnnotationScope {types:i64,rows:i64,computations:i64,binding:u32,inherited_types:i64,inherited_rows:i64}
struct SourceImplementationScope {implementation:blot_support::Option<u32>,closed:bool,implicit_rows:bool}
fn sourceLiteralPoint(self_:const Engine&,id:u32)->u32 {let span=self_.tree.span(id);let attribute=tagOrigin(self_.tag_origins,span);if attribute==0 {return span.start;}return self_.tree.span(attribute).start;}
fn sourceAnnotationsStopped(self_:const Engine&)->bool {return self_.source_annotation_failed;}
fn sourceControlValidation(self_:const Engine&)->bool {return self_.source_validation;}
// Header diagnostics stay in their lexical owner; readers carry only indices.
fn sourceDiagnosticAt(self_:const Engine&,index:i64)->Diagnostic {if self_.source_validation {assert(index>=0 && index<self_.source_header_diagnostics_count);return self_.header_diagnostics[self_.source_header_diagnostics_start+index];}return self_.diagnostics[index];}
fn sourceDeclarationHeader(self_:Engine&,id:u32)->blot_error::Error {if !self_.source_validation || self_.source_annotation_failed {return blot_error::Error.none;}let span=self_.tree.span(id);let diagnostic_count=self_.source_header_diagnostics_count;for diagnostic_index in 0..diagnostic_count {let diagnostic=sourceDiagnosticAt(self_,diagnostic_index);let node_span=self_.tree.span(diagnostic.node);if node_span.start<span.start || node_span.end>span.end {continue;}self_.diagnostics.push(canonicalDiagnostic(diagnostic));self_.source_annotation_failed=true;return blot_error::Error.none;}return blot_error::Error.none;}
fn sourceImplementationStart(self_:Engine&,id:u32)->SourceImplementationScope,blot_error::Error {let saved=SourceImplementationScope{self_.checking_implementation,self_.closed_type_variables,self_.implicit_row_parameters, ..};if !self_.source_validation {return saved,blot_error::Error.none;}let index:u32={let scalar_lookup_13 .= self_.catalogs.implementation_names.get(Qualified{0,self_.tree.node(id).a, ..});if !scalar_lookup_13 {return saved,blot_error::Error.none;}let scalar_value_13:u32=scalar_lookup_13;scalar_value_13};let err=self_.implementationScope(self_.implementations[index]);if err!=blot_error::Error.none {return saved,err;}self_.checking_implementation=blot_support::some(index);self_.closed_type_variables=true;self_.implicit_row_parameters=false;return saved,blot_error::Error.none;}
fn sourceImplementationEnd(self_:Engine&,saved:SourceImplementationScope) {if !self_.source_validation {return;}self_.type_env.clear();self_.row_env.clear();self_.checking_implementation=saved.implementation;self_.closed_type_variables=saved.closed;self_.implicit_row_parameters=saved.implicit_rows;}
fn sourceBindingStart(self_:Engine&,id:u32)->SourceAnnotationScope,blot_error::Error {let saved=SourceAnnotationScope{self_.type_env.items.len,self_.row_env.items.len,self_.computation_annotations.len,self_.annotation_binding,self_.inherited_types,self_.inherited_rows, ..};if !self_.source_validation {return saved,blot_error::Error.none;}let before=self_.diagnostics.len;self_.annotation_binding=0;if self_.tree.node(id).tag==blot_parse_ast::tag_let_stmt {self_.annotation_binding=id;}self_.inherited_types=saved.types;self_.inherited_rows=saved.rows;
    if self_.tree.node(id).tag==blot_parse_ast::tag_value_decl {let declaration=self_.tree.value_decl(id);for source in [declaration.annotation,declaration.where_node,declaration.body] {let err=self_.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return saved,err;}}let syntax_source_1=declaration.attributes;let syntax_count_1=self_.tree.list(syntax_source_1).len;for syntax_index_1 in 0..syntax_count_1 {let attribute=self_.tree.list(syntax_source_1)[syntax_index_1];let err=self_.collectAnnotationNames(self_.tree.node(attribute).a,0);if err!=blot_error::Error.none {return saved,err;}}}
    else if self_.tree.node(id).tag==blot_parse_ast::tag_entry_kernel_decl {let declaration=self_.tree.entry_kernel_decl(id);var sources:u32[3]=[declaration.annotation,0,0];if declaration.stateless {sources[1]=declaration.first;sources[2]=declaration.second;}for source in sources {let err=self_.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return saved,err;}}}
    else if self_.tree.node(id).tag==blot_parse_ast::tag_entry_process_decl {let declaration=self_.tree.entry_process_decl(id);let err=self_.collectAnnotationNames(declaration.annotation,0);if err!=blot_error::Error.none {return saved,err;}}
    else {let binding=self_.tree.binding(id);for source in [binding.annotation,binding.where_node,binding.value,binding.fallback] {let err=self_.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return saved,err;}}}self_.source_annotation_failed=self_.source_annotation_failed || self_.diagnostics.len!=before;return saved,blot_error::Error.none;
}
fn sourceBindingAnnotation(self_:Engine&,id:u32)->blot_error::Error {if !self_.source_validation || self_.source_annotation_failed {return blot_error::Error.none;}let before=self_.diagnostics.len;var annotation:u32=0;if self_.tree.node(id).tag==blot_parse_ast::tag_value_decl {annotation=self_.tree.value_decl(id).annotation;}else if self_.tree.node(id).tag==blot_parse_ast::tag_entry_kernel_decl {annotation=self_.tree.entry_kernel_decl(id).annotation;}else if self_.tree.node(id).tag==blot_parse_ast::tag_entry_process_decl {annotation=self_.tree.entry_process_decl(id).annotation;}else {annotation=self_.tree.binding(id).annotation;}if annotation!=0 {let value,err=self_.annotation(annotation);if err!=blot_error::Error.none {return err;}}self_.source_annotation_failed=self_.diagnostics.len!=before;return blot_error::Error.none;}
fn sourceBindingFinish(self_:Engine&,id:u32)->blot_error::Error {if !self_.source_validation || self_.source_annotation_failed {return blot_error::Error.none;}let before=self_.diagnostics.len;var err=blot_error::Error.none;if self_.tree.node(id).tag==blot_parse_ast::tag_value_decl {let declaration=self_.tree.value_decl(id);err=self_.beginQualification(id,declaration.where_node,declaration.annotation,declaration.body);}else if self_.tree.node(id).tag==blot_parse_ast::tag_entry_kernel_decl || self_.tree.node(id).tag==blot_parse_ast::tag_entry_process_decl {err=blot_error::Error.none;}else {let binding=self_.tree.binding(id);err=self_.beginQualification(id,binding.where_node,binding.annotation,binding.value);}if err!=blot_error::Error.none {return err;}self_.source_annotation_failed=self_.diagnostics.len!=before;return blot_error::Error.none;}
fn sourceBindingEnd(self_:Engine&,saved:SourceAnnotationScope) {if !self_.source_validation {return;}self_.type_env.resize(saved.types);self_.row_env.resize(saved.rows);self_.computation_annotations.resize(saved.computations);self_.annotation_binding=saved.binding;self_.inherited_types=saved.inherited_types;self_.inherited_rows=saved.inherited_rows;}
fn sourceExpressionAnnotations(self_:Engine&,id:u32)->blot_error::Error {if !self_.source_validation || self_.source_annotation_failed {return blot_error::Error.none;}let before=self_.diagnostics.len;let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_lambda {let parameter=self_.tree.parameter(node.a);if parameter.where_node!=0 {let err=self_.diagnostic(Code.higher_rank_constraint,parameter.where_node);if err!=blot_error::Error.none {return err;}}if parameter.annotation!=0 {let value,err=self_.annotation(parameter.annotation);if err!=blot_error::Error.none {return err;}}if node.c!=0 {let value,err=self_.annotation(node.c);if err!=blot_error::Error.none {return err;}}}else if node.tag==blot_parse_ast::tag_use_stmt && node.c!=0 {let value,err=self_.annotation(node.c);if err!=blot_error::Error.none {return err;}}self_.source_annotation_failed=self_.diagnostics.len!=before;return blot_error::Error.none;}
fn producerCapability(self_:const Engine&,target:ExternalTarget)->blot_support::Option<ProducerCapability> {if !self_.producer_capabilities.present {return blot_support::none<ProducerCapability>();}return self_.producer_capabilities.value.lookup(target);}
fn producerInterface(self_:const Engine&,target:ExternalTarget)->blot_support::Option<SchemeInterface> {if !self_.producer_capabilities.present {return blot_support::none<SchemeInterface>();}return self_.producer_capabilities.value.published(target);}
// Imported associated members are copied on first lookup only when every
// module that imports this one's catalog can reach their producers.
fn defersAssociated(self_:const Engine&)->bool {if !self_.producer_capabilities.present {return false;}return self_.producer_capabilities.value.interface && !self_.source_validation && !self_.editor_marker.present;}
// The binding of an associated member. The first lookup of an imported
// member copies its scheme.
fn associatedBinding(self_:Engine&,index:u32)->u32,blot_error::Error {let binding=self_.associated[index].binding;if (binding&pending_associated)==0 {return binding,blot_error::Error.none;}let imported,err=self_.importedBinding(self_.associated_pending[binding&~pending_associated]);if err!=blot_error::Error.none {return 0,err;}if !imported.present {return 0,blot_error::Error.type_limit;}self_.associated[index].binding=imported.value;return imported.value,blot_error::Error.none;}
// Gives each imported associated member that no lookup needed a binding
// naming its producer. The published catalog forwards the member through it;
// an importing module reads the scheme from the producer.
fn publishPendingAssociated(self_:Engine&)->blot_error::Error {
 for index in 0..self_.associated.len {let binding=self_.associated[index].binding;if (binding&pending_associated)==0 {continue;}let target=self_.associated_pending[binding&~pending_associated];
  let known .= self_.catalogs.external_targets.get(target);if known {let existing:u32=known;self_.associated[index].binding=existing;continue;}
  let found .= self_.imported_values.get(target);if !found {return blot_error::Error.type_limit;}let record:u32=found;let imported=self_.import_arena.records[record];
  let forwarded,err=self_.addBinding(Binding{name:0,declaration:imported.origin,owner:imported.origin,kind:blot_reuse_principal_interface::Kind.external,ty:blot_check_types::unit,capability_parameters:imported.interface.capability_parameters,named_function:imported.interface.named_function,external:blot_support::some(target), ..});if err!=blot_error::Error.none {return err;}self_.associated[index].binding=forwarded;}
 self_.associated_pending.clear();return blot_error::Error.none;
}
fn importHeader(self_:Engine&,imported:SourceHeader)->blot_error::Error {assert(self_.source_validation);let key=Qualified{imported.namespace_,imported.member, ..};if imported.expose && ((imported.namespace_==0 && self_.hasGlobal(imported.name)) || (imported.namespace_!=0 && self_.hasQualified(key))) {return self_.diagnostic(Code.duplicate_name,imported.origin);}let scalar_lookup_14 .= self_.catalogs.external_targets.get(imported.target);var binding:u32=0;if scalar_lookup_14 {let existing:u32=scalar_lookup_14;binding=existing;}else {var name=imported.name;if imported.namespace_!=0 {name=imported.member;}let ty,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}let fresh,err=self_.addBinding(Binding{ capability_parameters:imported.capability_parameters, name:name, declaration:imported.origin, owner:imported.origin, kind:blot_reuse_principal_interface::Kind.external, named_function:imported.named_function, ty:ty, external:blot_support::some(imported.target), .. });if err!=blot_error::Error.none {return err;}self_.catalogs.external_targets.insert(imported.target,fresh);binding=fresh;}if !imported.expose {return blot_error::Error.none;}if imported.namespace_==0 {self_.catalogs.globals.insert(imported.name,binding);blot_support_zigmap::put(self_.zig_orders,self_.global_order,imported.name,0);}else {self_.catalogs.qualified.insert(key,binding);}return blot_error::Error.none;}
fn hasGlobal(self_:const Engine&,name:u32)->bool {return self_.catalogs.globals.contains(name) || self_.imported_globals.contains(name);}
fn hasQualified(self_:const Engine&,key:Qualified)->bool {return self_.catalogs.qualified.contains(key) || self_.imported_qualified.contains(key);}
fn hasCatalogBinding(self_:const Engine&,name:u32)->bool {return self_.hasGlobal(name) || self_.hasQualified(self_.catalogKey(name));}
fn importedBinding(self_:Engine&,target:ExternalTarget)->blot_support::Option<u32>,blot_error::Error {let scalar_lookup_15 .= self_.catalogs.external_targets.get(target);if scalar_lookup_15 {let binding:u32=scalar_lookup_15;return blot_support::some(binding),blot_error::Error.none;}let found .= self_.imported_values.get(target);if !found {return blot_support::none<u32>(),blot_error::Error.none;}let index:u32=found;let imported=self_.import_arena.records[index];var name=imported.name;if imported.namespace_!=0 {name=imported.member;}return self_.importScheme(imported.interface,target,name,imported.origin,0);}
fn qualifiedImportBinding(self_:Engine&,key:Qualified)->blot_support::Option<u32>,blot_error::Error {let scalar_lookup_16 .= self_.catalogs.qualified.get(key);if scalar_lookup_16 {let binding:u32=scalar_lookup_16;return blot_support::some(binding),blot_error::Error.none;}let target .= self_.imported_qualified.get(key);if !target {return blot_support::none<u32>(),blot_error::Error.none;}return self_.importedBinding(target);}
// Explicit parser context adapters retain all source authority hooks.
fn source_duplicate_name(self_:const Engine&)->u32,bool {let value=self_.sourceDuplicateName();return value.value,value.present;}
fn source_operator_target_exists(self_:Engine&,name:u32)->bool,blot_error::Error {return self_.sourceOperatorTargetExists(name);}
fn source_value_exists(self_:Engine&,name:u32)->bool,blot_error::Error {return self_.sourceValueExists(name);}
fn source_record_target(self_:Engine&,name:u32)->u32,blot_error::Error {return self_.sourceRecordTarget(name);}
fn source_argument_is_type(self_:Engine&,source:u32,argument:u32)->bool,blot_error::Error {return self_.sourceArgumentIsType(source,argument);}
fn source_declaration_header(self_:Engine&,source:u32)->blot_error::Error {return self_.sourceDeclarationHeader(source);}
fn source_binding_annotation(self_:Engine&,source:u32)->blot_error::Error {return self_.sourceBindingAnnotation(source);}
fn source_binding_finish(self_:Engine&,source:u32)->blot_error::Error {return self_.sourceBindingFinish(source);}
fn source_expression_annotations(self_:Engine&,source:u32)->blot_error::Error {return self_.sourceExpressionAnnotations(source);}
fn source_binding_start(self_:Engine&,source:u32)->SourceAnnotationScope,blot_error::Error {return self_.sourceBindingStart(source);}
fn source_binding_end(self_:Engine&,scope:SourceAnnotationScope) {self_.sourceBindingEnd(scope);}
fn source_implementation_start(self_:Engine&,source:u32)->SourceImplementationScope,blot_error::Error {return self_.sourceImplementationStart(source);}
fn source_implementation_end(self_:Engine&,scope:SourceImplementationScope) {self_.sourceImplementationEnd(scope);}
fn source_annotations_stopped(self_:const Engine&)->bool {return self_.sourceAnnotationsStopped();}
fn source_control_validation(self_:const Engine&)->bool {return self_.sourceControlValidation();}
fn source_literal_point(self_:const Engine&,source:u32)->u32 {return self_.sourceLiteralPoint(source);}
fn source_editor_probe(self_:const Engine&,source:u32)->bool {return self_.sourceEditorProbe(source);}
fn source_private_constructor(self_:const Engine&,name:u32)->bool {return self_.sourcePrivateConstructor(name);}
fn source_type_application(self_:const Engine&,name:u32)->bool {return self_.sourceTypeApplication(name);}
fn source_record_field_exists(self_:const Engine&,name:u32,field:u32)->bool,bool {let value=self_.sourceRecordFieldExists(name,field);return value.value,value.present;}
fn source_missing_record_field(self_:const Engine&,name:u32,fields:const u32[:])->u32,bool {let value=self_.sourceMissingRecordField(name,fields);return value.value,value.present;}
fn source_symbolic_declared(self_:const Engine&,name:u32)->bool {return self_.sourceSymbolicDeclared(name);}
fn source_intrinsic_known(self_:const Engine&,name:u32)->bool {return self_.sourceIntrinsicKnown(name);}
fn source_intrinsic_arity(self_:const Engine&,name:u32)->i64,bool {let value=self_.sourceIntrinsicArity(name);return value.value,value.present;}
fn source_non_callable_effect(self_:const Engine&,name:u32)->bool {return self_.sourceNonCallableEffect(name);}
fn source_qualified_exists(self_:const Engine&,namespace_:u32,member:u32)->bool {return self_.sourceQualifiedExists(namespace_,member);}
fn source_constructor_exists(self_:const Engine&,name:u32)->bool {return self_.sourceConstructorExists(name);}

fn editorName_kindCode(value:EditorName_kind)->u32 {match value {value=>{return 0;},function=>{return 1;},type_=>{return 2;},constructor=>{return 3;},field=>{return 4;},member=>{return 5;},module=>{return 6;},}}
fn editorName_kindFromCode(code:u32)->EditorName_kind,blot_error::Error {match code {0=>{return EditorName_kind.value,blot_error::Error.none;},1=>{return EditorName_kind.function,blot_error::Error.none;},2=>{return EditorName_kind.type_,blot_error::Error.none;},3=>{return EditorName_kind.constructor,blot_error::Error.none;},4=>{return EditorName_kind.field,blot_error::Error.none;},5=>{return EditorName_kind.member,blot_error::Error.none;},6=>{return EditorName_kind.module,blot_error::Error.none;},_=>{return EditorName_kind.value,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::EditorName_kind,right:blot_check_check::EditorName_kind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::EditorName_kind,sink:S&) {blot_structural::hash(sink,blot_check_check::editorName_kindCode(value) as! u8);}
fn globalTrace_kindCode(value:GlobalTrace_kind)->u32 {match value {begun=>{return 0;},finished=>{return 1;},}}
fn globalTrace_kindFromCode(code:u32)->GlobalTrace_kind,blot_error::Error {match code {0=>{return GlobalTrace_kind.begun,blot_error::Error.none;},1=>{return GlobalTrace_kind.finished,blot_error::Error.none;},_=>{return GlobalTrace_kind.begun,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::GlobalTrace_kind,right:blot_check_check::GlobalTrace_kind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::GlobalTrace_kind,sink:S&) {blot_structural::hash(sink,blot_check_check::globalTrace_kindCode(value) as! u8);}
fn operationUse_callCode(value:OperationUse_call)->u32 {match value {value=>{return 0;},state_read=>{return 1;},state_write=>{return 2;},}}
fn operationUse_callFromCode(code:u32)->OperationUse_call,blot_error::Error {match code {0=>{return OperationUse_call.value,blot_error::Error.none;},1=>{return OperationUse_call.state_read,blot_error::Error.none;},2=>{return OperationUse_call.state_write,blot_error::Error.none;},_=>{return OperationUse_call.value,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::OperationUse_call,right:blot_check_check::OperationUse_call)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::OperationUse_call,sink:S&) {blot_structural::hash(sink,blot_check_check::operationUse_callCode(value) as! u8);}
fn importedCatalog_kindCode(value:ImportedCatalog_kind)->u32 {match value {catalog=>{return 0;},nominal=>{return 1;},constructor=>{return 2;},effect_family=>{return 3;},contract=>{return 4;},implementation=>{return 5;},}}
fn importedCatalog_kindFromCode(code:u32)->ImportedCatalog_kind,blot_error::Error {match code {0=>{return ImportedCatalog_kind.catalog,blot_error::Error.none;},1=>{return ImportedCatalog_kind.nominal,blot_error::Error.none;},2=>{return ImportedCatalog_kind.constructor,blot_error::Error.none;},3=>{return ImportedCatalog_kind.effect_family,blot_error::Error.none;},4=>{return ImportedCatalog_kind.contract,blot_error::Error.none;},5=>{return ImportedCatalog_kind.implementation,blot_error::Error.none;},_=>{return ImportedCatalog_kind.catalog,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::ImportedCatalog_kind,right:blot_check_check::ImportedCatalog_kind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::ImportedCatalog_kind,sink:S&) {blot_structural::hash(sink,blot_check_check::importedCatalog_kindCode(value) as! u8);}
fn effectRunnerKindCode(value:EffectRunnerKind)->u32 {match value {run=>{return 0;},reader=>{return 1;},writer=>{return 2;},}}
fn effectRunnerKindFromCode(code:u32)->EffectRunnerKind,blot_error::Error {match code {0=>{return EffectRunnerKind.run,blot_error::Error.none;},1=>{return EffectRunnerKind.reader,blot_error::Error.none;},2=>{return EffectRunnerKind.writer,blot_error::Error.none;},_=>{return EffectRunnerKind.run,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::EffectRunnerKind,right:blot_check_check::EffectRunnerKind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::EffectRunnerKind,sink:S&) {blot_structural::hash(sink,blot_check_check::effectRunnerKindCode(value) as! u8);}
fn codeCode(value:Code)->u32 {match value {function_return_required=>{return 0;},task_escape=>{return 1;},task_handle_consumed=>{return 2;},task_capture_transfer=>{return 3;},task_capability_shared=>{return 4;},task_regions_overlap=>{return 5;},task_host_contract=>{return 6;},task_budget=>{return 7;},invalid_proof_operand=>{return 8;},proof_scope_escape=>{return 9;},proof_runtime_use=>{return 10;},proof_mismatch=>{return 11;},contradictory_proof=>{return 12;},proof_analysis_limit=>{return 13;},effect_identity_scope=>{return 14;},capability_escape=>{return 15;},capability_analysis_limit=>{return 16;},undetermined_implementation=>{return 17;},orphan_implementation=>{return 18;},overlapping_implementation=>{return 19;},incompatible_implementation=>{return 20;},recursive_evidence=>{return 21;},missing_type_member=>{return 22;},associated_arity=>{return 23;},recursive_associated_type=>{return 24;},associated_limit=>{return 25;},missing_implementation=>{return 26;},private_access=>{return 27;},private_identity_escape=>{return 28;},unbound_alias_row=>{return 29;},recursive_contract=>{return 30;},contract_arity=>{return 31;},recursive_type_alias=>{return 32;},typed_hole=>{return 33;},effect_member=>{return 34;},integer_range=>{return 35;},float_range=>{return 36;},float_literal=>{return 37;},module_loader_required=>{return 38;},intrinsic_arity=>{return 39;},requests_scope=>{return 40;},yield_scope=>{return 41;},request_loop_scope=>{return 42;},request_loop_body=>{return 43;},request_loop_range=>{return 44;},request_binding=>{return 45;},request_completion=>{return 46;},request_clause_fallthrough=>{return 47;},request_completion_fallthrough=>{return 48;},duplicate_request_handler=>{return 49;},request_case_scope=>{return 50;},unknown_value=>{return 51;},syntax=>{return 52;},duplicate_name=>{return 53;},unknown_name=>{return 54;},type_mismatch=>{return 55;},infinite_type=>{return 56;},effect_mismatch=>{return 57;},infinite_effect=>{return 58;},const_effect=>{return 59;},initializer_effect=>{return 60;},let_effect=>{return 61;},sealed_effect=>{return 62;},effect_arity=>{return 63;},effect_family=>{return 64;},unknown_effect=>{return 65;},invalid_effect_annotation=>{return 66;},invalid_constraint=>{return 67;},higher_rank_constraint=>{return 68;},missing_predicate=>{return 69;},ambiguous_qualified=>{return 70;},annotation_kind_mismatch=>{return 71;},unsupported_polymorphic_effect_label=>{return 72;},operation_signature=>{return 73;},type_arity=>{return 74;},operation_target=>{return 75;},invalid_state_provider=>{return 76;},unsupported=>{return 77;},unsupported_attribute=>{return 78;},recursive_tag=>{return 79;},function_target=>{return 80;},open_effect_descriptor=>{return 81;},unsupported_expression=>{return 82;},unsupported_type=>{return 83;},ambiguous_operator=>{return 84;},ambiguous_associated=>{return 85;},missing_associated=>{return 86;},ambiguous_member=>{return 87;},missing_member=>{return 88;},type_constructor_required=>{return 89;},invalid_provider=>{return 90;},resolver_required=>{return 91;},literal_required=>{return 92;},call_arity=>{return 93;},break_scope=>{return 94;},continue_scope=>{return 95;},invalid_return=>{return 96;},unreachable_statement=>{return 97;},invalid_operator=>{return 98;},return_outside_block=>{return 99;},return_outside_function=>{return 100;},return_across_continuation=>{return 101;},unknown_rebinding=>{return 102;},dead_rebinding=>{return 103;},case_arm_return=>{return 104;},nesting_limit=>{return 105;},unknown_constructor=>{return 106;},constructor_marker=>{return 107;},type_parameter=>{return 108;},type_argument=>{return 109;},duplicate_type_parameter=>{return 110;},duplicate_type_field=>{return 111;},unknown_field=>{return 112;},duplicate_field=>{return 113;},missing_field=>{return 114;},non_exhaustive_match=>{return 115;},refutable_pattern=>{return 116;},constructor_arity=>{return 117;},unknown_product_shape=>{return 118;},product_index=>{return 119;},product_index_literal=>{return 120;},pattern_arity=>{return 121;},pattern_bindings=>{return 122;},value_pattern_type=>{return 123;},non_exiting_fallback=>{return 124;},unknown_operator=>{return 125;},operator_associativity=>{return 126;},operator_header_order=>{return 127;},operator_precedence=>{return 128;},duplicate_operator=>{return 129;},unsupported_prefix=>{return 130;},unknown_intrinsic=>{return 131;},alternative_bindings=>{return 132;},duplicate_pattern_binding=>{return 133;},duplicate_record_field=>{return 134;},unknown_record_field=>{return 135;},record_constructor=>{return 136;},missing_record_field=>{return 137;},unknown_modifier=>{return 138;},guard_fallthrough=>{return 139;},product_arity=>{return 140;},inference_budget=>{return 141;},skolem_escape=>{return 142;},rank_mismatch=>{return 143;},package_expected=>{return 144;},package_witness_mismatch=>{return 145;},package_escape=>{return 146;},abstract_representation_access=>{return 147;},use_after_move=>{return 148;},duplicate_owner=>{return 149;},borrow_conflict=>{return 150;},borrow_escape=>{return 151;},once_reused=>{return 152;},multiplicity_unknown=>{return 153;},cleanup_not_safe=>{return 154;},usage_evidence_mismatch=>{return 155;},usage_analysis_limit=>{return 156;},code_shape_mismatch=>{return 157;},stage_unavailable=>{return 158;},cross_stage_authority=>{return 159;},descriptor_private=>{return 160;},generated_binding_escape=>{return 161;},staging_budget=>{return 162;},own_parameter=>{return 163;},spark_generator=>{return 164;},spark_effectful=>{return 165;},spark_capture=>{return 166;},kernel_type=>{return 167;},kernel_callable=>{return 168;},kernel_effectful=>{return 169;},std_only_intrinsic=>{return 170;},entry_type=>{return 171;},}}
fn codeFromCode(code:u32)->Code,blot_error::Error {match code {0=>{return Code.function_return_required,blot_error::Error.none;},1=>{return Code.task_escape,blot_error::Error.none;},2=>{return Code.task_handle_consumed,blot_error::Error.none;},3=>{return Code.task_capture_transfer,blot_error::Error.none;},4=>{return Code.task_capability_shared,blot_error::Error.none;},5=>{return Code.task_regions_overlap,blot_error::Error.none;},6=>{return Code.task_host_contract,blot_error::Error.none;},7=>{return Code.task_budget,blot_error::Error.none;},8=>{return Code.invalid_proof_operand,blot_error::Error.none;},9=>{return Code.proof_scope_escape,blot_error::Error.none;},10=>{return Code.proof_runtime_use,blot_error::Error.none;},11=>{return Code.proof_mismatch,blot_error::Error.none;},12=>{return Code.contradictory_proof,blot_error::Error.none;},13=>{return Code.proof_analysis_limit,blot_error::Error.none;},14=>{return Code.effect_identity_scope,blot_error::Error.none;},15=>{return Code.capability_escape,blot_error::Error.none;},16=>{return Code.capability_analysis_limit,blot_error::Error.none;},17=>{return Code.undetermined_implementation,blot_error::Error.none;},18=>{return Code.orphan_implementation,blot_error::Error.none;},19=>{return Code.overlapping_implementation,blot_error::Error.none;},20=>{return Code.incompatible_implementation,blot_error::Error.none;},21=>{return Code.recursive_evidence,blot_error::Error.none;},22=>{return Code.missing_type_member,blot_error::Error.none;},23=>{return Code.associated_arity,blot_error::Error.none;},24=>{return Code.recursive_associated_type,blot_error::Error.none;},25=>{return Code.associated_limit,blot_error::Error.none;},26=>{return Code.missing_implementation,blot_error::Error.none;},27=>{return Code.private_access,blot_error::Error.none;},28=>{return Code.private_identity_escape,blot_error::Error.none;},29=>{return Code.unbound_alias_row,blot_error::Error.none;},30=>{return Code.recursive_contract,blot_error::Error.none;},31=>{return Code.contract_arity,blot_error::Error.none;},32=>{return Code.recursive_type_alias,blot_error::Error.none;},33=>{return Code.typed_hole,blot_error::Error.none;},34=>{return Code.effect_member,blot_error::Error.none;},35=>{return Code.integer_range,blot_error::Error.none;},36=>{return Code.float_range,blot_error::Error.none;},37=>{return Code.float_literal,blot_error::Error.none;},38=>{return Code.module_loader_required,blot_error::Error.none;},39=>{return Code.intrinsic_arity,blot_error::Error.none;},40=>{return Code.requests_scope,blot_error::Error.none;},41=>{return Code.yield_scope,blot_error::Error.none;},42=>{return Code.request_loop_scope,blot_error::Error.none;},43=>{return Code.request_loop_body,blot_error::Error.none;},44=>{return Code.request_loop_range,blot_error::Error.none;},45=>{return Code.request_binding,blot_error::Error.none;},46=>{return Code.request_completion,blot_error::Error.none;},47=>{return Code.request_clause_fallthrough,blot_error::Error.none;},48=>{return Code.request_completion_fallthrough,blot_error::Error.none;},49=>{return Code.duplicate_request_handler,blot_error::Error.none;},50=>{return Code.request_case_scope,blot_error::Error.none;},51=>{return Code.unknown_value,blot_error::Error.none;},52=>{return Code.syntax,blot_error::Error.none;},53=>{return Code.duplicate_name,blot_error::Error.none;},54=>{return Code.unknown_name,blot_error::Error.none;},55=>{return Code.type_mismatch,blot_error::Error.none;},56=>{return Code.infinite_type,blot_error::Error.none;},57=>{return Code.effect_mismatch,blot_error::Error.none;},58=>{return Code.infinite_effect,blot_error::Error.none;},59=>{return Code.const_effect,blot_error::Error.none;},60=>{return Code.initializer_effect,blot_error::Error.none;},61=>{return Code.let_effect,blot_error::Error.none;},62=>{return Code.sealed_effect,blot_error::Error.none;},63=>{return Code.effect_arity,blot_error::Error.none;},64=>{return Code.effect_family,blot_error::Error.none;},65=>{return Code.unknown_effect,blot_error::Error.none;},66=>{return Code.invalid_effect_annotation,blot_error::Error.none;},67=>{return Code.invalid_constraint,blot_error::Error.none;},68=>{return Code.higher_rank_constraint,blot_error::Error.none;},69=>{return Code.missing_predicate,blot_error::Error.none;},70=>{return Code.ambiguous_qualified,blot_error::Error.none;},71=>{return Code.annotation_kind_mismatch,blot_error::Error.none;},72=>{return Code.unsupported_polymorphic_effect_label,blot_error::Error.none;},73=>{return Code.operation_signature,blot_error::Error.none;},74=>{return Code.type_arity,blot_error::Error.none;},75=>{return Code.operation_target,blot_error::Error.none;},76=>{return Code.invalid_state_provider,blot_error::Error.none;},77=>{return Code.unsupported,blot_error::Error.none;},78=>{return Code.unsupported_attribute,blot_error::Error.none;},79=>{return Code.recursive_tag,blot_error::Error.none;},80=>{return Code.function_target,blot_error::Error.none;},81=>{return Code.open_effect_descriptor,blot_error::Error.none;},82=>{return Code.unsupported_expression,blot_error::Error.none;},83=>{return Code.unsupported_type,blot_error::Error.none;},84=>{return Code.ambiguous_operator,blot_error::Error.none;},85=>{return Code.ambiguous_associated,blot_error::Error.none;},86=>{return Code.missing_associated,blot_error::Error.none;},87=>{return Code.ambiguous_member,blot_error::Error.none;},88=>{return Code.missing_member,blot_error::Error.none;},89=>{return Code.type_constructor_required,blot_error::Error.none;},90=>{return Code.invalid_provider,blot_error::Error.none;},91=>{return Code.resolver_required,blot_error::Error.none;},92=>{return Code.literal_required,blot_error::Error.none;},93=>{return Code.call_arity,blot_error::Error.none;},94=>{return Code.break_scope,blot_error::Error.none;},95=>{return Code.continue_scope,blot_error::Error.none;},96=>{return Code.invalid_return,blot_error::Error.none;},97=>{return Code.unreachable_statement,blot_error::Error.none;},98=>{return Code.invalid_operator,blot_error::Error.none;},99=>{return Code.return_outside_block,blot_error::Error.none;},100=>{return Code.return_outside_function,blot_error::Error.none;},101=>{return Code.return_across_continuation,blot_error::Error.none;},102=>{return Code.unknown_rebinding,blot_error::Error.none;},103=>{return Code.dead_rebinding,blot_error::Error.none;},104=>{return Code.case_arm_return,blot_error::Error.none;},105=>{return Code.nesting_limit,blot_error::Error.none;},106=>{return Code.unknown_constructor,blot_error::Error.none;},107=>{return Code.constructor_marker,blot_error::Error.none;},108=>{return Code.type_parameter,blot_error::Error.none;},109=>{return Code.type_argument,blot_error::Error.none;},110=>{return Code.duplicate_type_parameter,blot_error::Error.none;},111=>{return Code.duplicate_type_field,blot_error::Error.none;},112=>{return Code.unknown_field,blot_error::Error.none;},113=>{return Code.duplicate_field,blot_error::Error.none;},114=>{return Code.missing_field,blot_error::Error.none;},115=>{return Code.non_exhaustive_match,blot_error::Error.none;},116=>{return Code.refutable_pattern,blot_error::Error.none;},117=>{return Code.constructor_arity,blot_error::Error.none;},118=>{return Code.unknown_product_shape,blot_error::Error.none;},119=>{return Code.product_index,blot_error::Error.none;},120=>{return Code.product_index_literal,blot_error::Error.none;},121=>{return Code.pattern_arity,blot_error::Error.none;},122=>{return Code.pattern_bindings,blot_error::Error.none;},123=>{return Code.value_pattern_type,blot_error::Error.none;},124=>{return Code.non_exiting_fallback,blot_error::Error.none;},125=>{return Code.unknown_operator,blot_error::Error.none;},126=>{return Code.operator_associativity,blot_error::Error.none;},127=>{return Code.operator_header_order,blot_error::Error.none;},128=>{return Code.operator_precedence,blot_error::Error.none;},129=>{return Code.duplicate_operator,blot_error::Error.none;},130=>{return Code.unsupported_prefix,blot_error::Error.none;},131=>{return Code.unknown_intrinsic,blot_error::Error.none;},132=>{return Code.alternative_bindings,blot_error::Error.none;},133=>{return Code.duplicate_pattern_binding,blot_error::Error.none;},134=>{return Code.duplicate_record_field,blot_error::Error.none;},135=>{return Code.unknown_record_field,blot_error::Error.none;},136=>{return Code.record_constructor,blot_error::Error.none;},137=>{return Code.missing_record_field,blot_error::Error.none;},138=>{return Code.unknown_modifier,blot_error::Error.none;},139=>{return Code.guard_fallthrough,blot_error::Error.none;},140=>{return Code.product_arity,blot_error::Error.none;},141=>{return Code.inference_budget,blot_error::Error.none;},142=>{return Code.skolem_escape,blot_error::Error.none;},143=>{return Code.rank_mismatch,blot_error::Error.none;},144=>{return Code.package_expected,blot_error::Error.none;},145=>{return Code.package_witness_mismatch,blot_error::Error.none;},146=>{return Code.package_escape,blot_error::Error.none;},147=>{return Code.abstract_representation_access,blot_error::Error.none;},148=>{return Code.use_after_move,blot_error::Error.none;},149=>{return Code.duplicate_owner,blot_error::Error.none;},150=>{return Code.borrow_conflict,blot_error::Error.none;},151=>{return Code.borrow_escape,blot_error::Error.none;},152=>{return Code.once_reused,blot_error::Error.none;},153=>{return Code.multiplicity_unknown,blot_error::Error.none;},154=>{return Code.cleanup_not_safe,blot_error::Error.none;},155=>{return Code.usage_evidence_mismatch,blot_error::Error.none;},156=>{return Code.usage_analysis_limit,blot_error::Error.none;},157=>{return Code.code_shape_mismatch,blot_error::Error.none;},158=>{return Code.stage_unavailable,blot_error::Error.none;},159=>{return Code.cross_stage_authority,blot_error::Error.none;},160=>{return Code.descriptor_private,blot_error::Error.none;},161=>{return Code.generated_binding_escape,blot_error::Error.none;},162=>{return Code.staging_budget,blot_error::Error.none;},163=>{return Code.own_parameter,blot_error::Error.none;},164=>{return Code.spark_generator,blot_error::Error.none;},165=>{return Code.spark_effectful,blot_error::Error.none;},166=>{return Code.spark_capture,blot_error::Error.none;},167=>{return Code.kernel_type,blot_error::Error.none;},168=>{return Code.kernel_callable,blot_error::Error.none;},169=>{return Code.kernel_effectful,blot_error::Error.none;},170=>{return Code.std_only_intrinsic,blot_error::Error.none;},171=>{return Code.entry_type,blot_error::Error.none;},_=>{return Code.function_return_required,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Code,right:blot_check_check::Code)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::Code,sink:S&) {blot_structural::hash(sink,blot_check_check::codeCode(value) as! u8);}
fn stateCode(value:State)->u32 {match value {pending=>{return 0;},active=>{return 1;},complete=>{return 2;},}}
fn stateFromCode(code:u32)->State,blot_error::Error {match code {0=>{return State.pending,blot_error::Error.none;},1=>{return State.active,blot_error::Error.none;},2=>{return State.complete,blot_error::Error.none;},_=>{return State.pending,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::State,right:blot_check_check::State)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::State,sink:S&) {blot_structural::hash(sink,blot_check_check::stateCode(value) as! u8);}
fn engine_implementation_member_states_stateCode(value:Engine_implementation_member_states_state)->u32 {match value {visiting=>{return 0;},ready=>{return 1;},}}
fn engine_implementation_member_states_stateFromCode(code:u32)->Engine_implementation_member_states_state,blot_error::Error {match code {0=>{return Engine_implementation_member_states_state.visiting,blot_error::Error.none;},1=>{return Engine_implementation_member_states_state.ready,blot_error::Error.none;},_=>{return Engine_implementation_member_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_implementation_member_states_state,right:blot_check_check::Engine_implementation_member_states_state)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::Engine_implementation_member_states_state,sink:S&) {blot_structural::hash(sink,blot_check_check::engine_implementation_member_states_stateCode(value) as! u8);}
fn engine_member_states_stateCode(value:Engine_member_states_state)->u32 {match value {visiting=>{return 0;},ready=>{return 1;},}}
fn engine_member_states_stateFromCode(code:u32)->Engine_member_states_state,blot_error::Error {match code {0=>{return Engine_member_states_state.visiting,blot_error::Error.none;},1=>{return Engine_member_states_state.ready,blot_error::Error.none;},_=>{return Engine_member_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_member_states_state,right:blot_check_check::Engine_member_states_state)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::Engine_member_states_state,sink:S&) {blot_structural::hash(sink,blot_check_check::engine_member_states_stateCode(value) as! u8);}
fn engine_contract_states_stateCode(value:Engine_contract_states_state)->u32 {match value {visiting=>{return 0;},ready=>{return 1;},}}
fn engine_contract_states_stateFromCode(code:u32)->Engine_contract_states_state,blot_error::Error {match code {0=>{return Engine_contract_states_state.visiting,blot_error::Error.none;},1=>{return Engine_contract_states_state.ready,blot_error::Error.none;},_=>{return Engine_contract_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_contract_states_state,right:blot_check_check::Engine_contract_states_state)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::Engine_contract_states_state,sink:S&) {blot_structural::hash(sink,blot_check_check::engine_contract_states_stateCode(value) as! u8);}
fn typeApplicationCode(value:TypeApplication)->u32 {match value {missing_array=>{return 0;},missing_nominal=>{return 1;},extra=>{return 2;},}}
fn typeApplicationFromCode(code:u32)->TypeApplication,blot_error::Error {match code {0=>{return TypeApplication.missing_array,blot_error::Error.none;},1=>{return TypeApplication.missing_nominal,blot_error::Error.none;},2=>{return TypeApplication.extra,blot_error::Error.none;},_=>{return TypeApplication.missing_array,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::TypeApplication,right:blot_check_check::TypeApplication)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::TypeApplication,sink:S&) {blot_structural::hash(sink,blot_check_check::typeApplicationCode(value) as! u8);}
fn diagnosticContextKindCode(value:DiagnosticContextKind)->u32 {match value {callee=>{return 0;},argument=>{return 1;},left_operand=>{return 2;},right_operand=>{return 3;},}}
fn diagnosticContextKindFromCode(code:u32)->DiagnosticContextKind,blot_error::Error {match code {0=>{return DiagnosticContextKind.callee,blot_error::Error.none;},1=>{return DiagnosticContextKind.argument,blot_error::Error.none;},2=>{return DiagnosticContextKind.left_operand,blot_error::Error.none;},3=>{return DiagnosticContextKind.right_operand,blot_error::Error.none;},_=>{return DiagnosticContextKind.callee,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::DiagnosticContextKind,right:blot_check_check::DiagnosticContextKind)->bool {return left==right;}
fn blot_check_check::blotStructuralHash<S>(value:blot_check_check::DiagnosticContextKind,sink:S&) {blot_structural::hash(sink,blot_check_check::diagnosticContextKindCode(value) as! u8);}
fn importBinding(self_:Engine&,imported:ImportedBinding)->blot_error::Error {let key=Qualified{imported.namespace_,imported.member, ..};if imported.expose && ((imported.namespace_==0 && self_.hasGlobal(imported.name)) || (imported.namespace_!=0 && self_.hasQualified(key))) {return self_.diagnostic(Code.duplicate_name,imported.origin);}self_.frontend_work.import_requests+=1;if !self_.imported_values.contains(imported.target) {let index=self_.import_arena.records.len as u32;self_.import_arena.records.push(imported);self_.imported_values.insert(imported.target,index);}if !imported.expose {return blot_error::Error.none;}if imported.namespace_==0 {self_.imported_globals.insert(imported.name,imported.target);blot_support_zigmap::put(self_.zig_orders,self_.imported_global_order,imported.name,0);}else {self_.imported_qualified.insert(key,imported.target);}return blot_error::Error.none;}
recursive fn importScheme(self_:Engine&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,depth:i64)->blot_support::Option<u32>,blot_error::Error {let callee_mark=self_.import_callees.len;let variable_mark=self_.import_variables.len;let result,err=importSchemeBody(self_,interface,target,name,origin,depth,callee_mark,variable_mark);self_.import_callees.resize(callee_mark);self_.import_variables.resize(variable_mark);return result,err;}
recursive fn importSchemeBody(self_:Engine&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,depth:i64,callee_mark:i64,variable_mark:i64)->blot_support::Option<u32>,blot_error::Error {
    self_.frontend_work.import_requests+=1;let scalar_lookup_17 .= self_.catalogs.external_targets.get(target);if scalar_lookup_17 {let existing:u32=scalar_lookup_17;return blot_support::some(existing),blot_error::Error.none;}self_.frontend_work.imported_schemes+=1;let range=interface.scheme.obligations;let constraints=interface.obligations[range.start..range.start+range.len];
    for constraint in constraints {if constraint.kind!=blot_check_types::ObligationKind.callee_use {continue;}let callee_interface=interface.callees.interface(constraint.identity.decl);if !callee_interface.present || depth>=256 {let err=self_.diagnostic(Code.nesting_limit,origin);return blot_support::none<u32>(),err;}let callee,err=self_.importScheme(callee_interface.value,ExternalTarget{target.unit,constraint.identity.decl, ..},0,origin,depth+1);if err!=blot_error::Error.none || !callee.present {return callee,err;}self_.import_callees.push(callee.value);}
    var copier=blot_check_check_scheme_import::init(interface.types,self_.types,self_.import_tables);let result,err=importSchemeCopied(self_,copier,interface,target,name,origin,callee_mark,variable_mark);copier.reset();return result,err;
}
fn importSchemeCopied(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,callee_mark:i64,variable_mark:i64)->blot_support::Option<u32>,blot_error::Error {
    for old in copier.source.list(interface.scheme.variables) {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}copier.mapping.insert(copier.source.head(old,0),fresh);self_.import_variables.push(fresh);}
    let row_variables,err=copier.quantifiedRows(interface.scheme.row_variables);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let closed_rows,err=copier.quantifiedRows(interface.scheme.closed_rows);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=copier.copy(interface.scheme.root,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let start=self_.obligations.len as u32;var shared:i64=0;let range=interface.scheme.obligations;
    for constraint in interface.obligations[range.start..range.start+range.len] {var value=constraint;value.source=origin;if constraint.kind==blot_check_types::ObligationKind.callee_use {value.identity=Identity{self_.unit,self_.import_callees[callee_mark+shared], ..};shared+=1;}let ty,err=copier.copy(constraint.ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.ty=ty;if constraint.result!=0 {let copied,err=copier.copy(constraint.result,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.result=copied;}if constraint.other!=0 {let copied,err=copier.copy(constraint.other,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.other=copied;}if constraint.signature!=0 {let copied,err=copier.copy(constraint.signature,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.signature=copied;}self_.obligations.push(value);}
    let variables,err=self_.types.saveList(self_.import_variables[variable_mark..]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let principal=blot_check_types::Scheme{ root:root, variables:variables, row_variables:row_variables, closed_rows:closed_rows, obligations:blot_check_types::List{start,(self_.obligations.len-start) as u32, ..}, .. };
    let binding,err=self_.addBinding(Binding{ capability_parameters:interface.capability_parameters, name:name, declaration:origin, owner:origin, kind:blot_reuse_principal_interface::Kind.external, named_function:interface.named_function, ty:root, scheme:principal, external:blot_support::some(target), .. });if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}
    if self_.execution.imported_summary_reuse && interface.summary.present {let summary,err=self_.relocateSummary(copier,interface.summary.value);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.bindings[binding].summary=summary;self_.frontend_work.imported_summary_reuses+=1;}else {let summary,err=self_.summarize(principal);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.bindings[binding].summary=summary;}
    self_.catalogs.external_targets.insert(target,binding);return blot_support::some(binding),blot_error::Error.none;
}
fn relocateSummary(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,source:SchemeSummary)->SchemeSummary,blot_error::Error {var result=source;let start=self_.import_variables.len;for variable in copier.source.list(source.public_variables) {let copied,err=copier.copy(variable,0);if err!=blot_error::Error.none {self_.import_variables.resize(start);return result,err;}self_.import_variables.push(copied);}let variables,err=self_.types.saveList(self_.import_variables[start..]);self_.import_variables.resize(start);if err!=blot_error::Error.none {return result,err;}result.public_variables=variables;let rows,err=copier.relocatedRows(copier.source.list(source.public_rows));if err!=blot_error::Error.none {return result,err;}result.public_rows=rows;
    let inputs,err=self_.types.saveList(copier.source.list(source.public_inputs));if err!=blot_error::Error.none {return result,err;}result.public_inputs=inputs;let outputs,err=self_.types.saveList(copier.source.list(source.public_outputs));if err!=blot_error::Error.none {return result,err;}result.public_outputs=outputs;let requirements,err=self_.types.saveList(copier.source.list(source.requirement_variables));if err!=blot_error::Error.none {return result,err;}result.requirement_variables=requirements;let row_requirements,err=self_.types.saveList(copier.source.list(source.requirement_rows));if err!=blot_error::Error.none {return result,err;}result.requirement_rows=row_requirements;return result,blot_error::Error.none;
}
// Bounds are conservative after a speculative truncation. Every append widens
// its owner's range, including when a rolled-back slot gets a different owner.
fn pushPending(self_:Engine&,value:PendingObligation) {
    let index=self_.pending.len;
    let owner=value.owner;
    if owner>=self_.pending_ranges.len {self_.pending_ranges.resize((owner as i64)+1,PendingRange{..});}
    let range:PendingRange& =self_.pending_ranges[owner];
    if range.end==0 {range.start=index;}else {range.start=min(range.start,index);}
    range.end=max(range.end,index+1);
    self_.pending.push(value);
}
fn pendingRange(self_:const Engine&,group:const u32[:])->PendingRange {
    let count=self_.pending.len;
    var start=count;
    var end:i64=0;
    for owner in group {
        if owner>=self_.pending_ranges.len {continue;}
        let range=self_.pending_ranges[owner];
        if range.end==0 {continue;}
        start=min(start,range.start);
        end=max(end,range.end);
    }
    if start>=end {return PendingRange{count,count};}
    return PendingRange{start,min(end,count)};
}
fn appendPending(self_:Engine&,item:PendingObligation)->blot_error::Error {self_.scheme_dependencies.truncate(self_.pending.len);var value=item;value.scope=self_.qualification_scope;value.method_member=value.method_member || (value.value.kind==blot_check_types::ObligationKind.receiver && !value.value.explicit);self_.pushPending(value);self_.counters.obligations_appended+=1;self_.counters.pending_peak=max(self_.counters.pending_peak,self_.pending.len as u64);return blot_error::Error.none;}
// Exact owned diagnostic bytes are tracked by their typed slice boundaries.
struct DetailRun {bytes:const u8[:]=default<const u8[:]>(),live:bool=false}
reusable[] var diagnostic_text:u8[>..];
var diagnostic_runs:DetailRun[>..<];
fn ownDiagnosticText(text:const u8[:])->const u8[:] {let bytes=diagnostic_text.alloc_slice(text.len);for byte,index in text {bytes[index]=byte;}var index:i64=0;while index<diagnostic_runs.len && diagnostic_runs[index].live {index+=1;}if index==diagnostic_runs.len {diagnostic_runs.push(DetailRun{..});}diagnostic_runs[index]=DetailRun{bytes,true, ..};return bytes;}
fn freeDiagnosticText(text:const u8[:]) {for &run in diagnostic_runs {if run.live && blot_support::same_slice_identity(run.bytes,text) {diagnostic_text.free_slice(run.bytes);run.bytes=default<const u8[:]>();run.live=false;return;}}}
fn decimal(out:u8[>..<]&,value:u32) {var digits:u8[10]=[0;10];var remaining=value;var count:i64=0;while true {digits[count]=('0' as u8)+(remaining%10) as u8;count+=1;remaining/=10;if remaining==0 {break;}}while count!=0 {count-=1;out.push(digits[count]);}}
fn usageConflict(self_:Engine&,code:Code,id:u32,first:u32,declaration:u32)->blot_error::Error {let err=self_.diagnostic(code,id);if err!=blot_error::Error.none {return err;}let index=self_.diagnostics.len-1;var buf:u8[>..<]=[];buf.append(self_.diagnostics[index].message());buf.append("; first conflicting use at byte ");decimal(buf,self_.tree.span(first).start);buf.append(", owner declared at byte ");decimal(buf,self_.tree.span(declaration).start);self_.diagnostics[index].detail=blot_support::some<const u8[:]>(ownDiagnosticText(buf));return blot_error::Error.none;}
fn usageDiagnostic(self_:Engine&,code:Code,id:u32)->blot_error::Error {return self_.diagnostic(code,id);}
fn diagnostic(self_:Engine&,code:Code,id:u32)->blot_error::Error {
    let origin=tagOrigin(self_.tag_origins,self_.tree.span(id));var source=id;if origin!=0 {source=origin;}var span=self_.tree.span(source);
    if origin==0 && self_.tree.node(id).tag==blot_parse_ast::tag_binary && (code==Code.type_mismatch || code==Code.effect_mismatch || code==Code.infinite_type || code==Code.infinite_effect) {let point=blot_parse_source_operators::origin(self_.tree,id);span=blot_parse_ast::Span{point,point, ..};}
    self_.diagnostics.push(Diagnostic{code:code,span:span,node:source, ..});if origin==0 && (code==Code.type_mismatch || code==Code.effect_mismatch || code==Code.missing_associated) {let issue .= self_.diagnostics[self_.diagnostics.len-1];let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_apply {issue.contexts=[DiagnosticContext{DiagnosticContextKind.callee,self_.tree.span(node.a), ..},DiagnosticContext{DiagnosticContextKind.argument,self_.tree.span(node.b), ..}];issue.context_len=2;}else if node.tag==blot_parse_ast::tag_binary {issue.contexts=[DiagnosticContext{DiagnosticContextKind.left_operand,self_.tree.span(node.b), ..},DiagnosticContext{DiagnosticContextKind.right_operand,self_.tree.span(node.c), ..}];issue.context_len=2;}}
    return blot_error::Error.none;
}
recursive fn constrain(self_:Engine&,a:u32,b:u32,id:u32)->blot_error::Error {var left=a;var right=b;if self_.implementations.len!=0 && self_.types.has_projections {let normalized,err=self_.normalizeAssociated(left,id,false);if err!=blot_error::Error.none {return err;}left=normalized;let normalized,err=self_.normalizeAssociated(right,id,false);if err!=blot_error::Error.none {return err;}right=normalized;}if self_.has_associated_types && self_.qualifications.len!=0 {let rewritten,err=self_.rewriteGiven(left,0);if err!=blot_error::Error.none {return err;}left=rewritten;let rewritten,err=self_.rewriteGiven(right,0);if err!=blot_error::Error.none {return err;}right=rewritten;}return self_.constrainRaw(left,right,id);}
recursive fn constrainRaw(self_:Engine&,left:u32,right:u32,id:u32)->blot_error::Error {let err=self_.constrainEquationRoot(left,right,id);match err {
    none=>{return blot_error::Error.none;},out_of_memory=>{return err;},infinite_type=>{return self_.diagnostic(Code.infinite_type,id);},infinite_effect=>{return self_.diagnostic(Code.infinite_effect,id);},type_limit=>{return self_.diagnostic(Code.nesting_limit,id);},
    type_mismatch,effect_mismatch=>{var code=Code.effect_mismatch;if err==blot_error::Error.type_mismatch {code=Code.type_mismatch;}let error=self_.diagnostic(code,id);if error!=blot_error::Error.none {return error;}let application=self_.tree.node(id).tag==blot_parse_ast::tag_apply;let first=self_.types.node(self_.types.head(left,0));let second=self_.types.node(self_.types.head(right,0));var exp_buf:u8[>..<]=[];var act_buf:u8[>..<]=[];var arguments=application && first.tag==blot_check_types::Tag.function && second.tag==blot_check_types::Tag.function;
        if arguments {let error=blot_reuse_type_display::append(self_,exp_buf,first.a);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::append(self_,act_buf,second.a);if error!=blot_error::Error.none {return error;}if exp_buf==act_buf {arguments=false;}}
        if !arguments {exp_buf.clear();act_buf.clear();let error=blot_reuse_type_display::append(self_,exp_buf,left);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::append(self_,act_buf,right);if error!=blot_error::Error.none {return error;}}
        var diag_buf:u8[>..<]=[];var prefix="Effect rows do not match; ";if err==blot_error::Error.type_mismatch {prefix="Types do not match; ";}let error=blot_reuse_type_display::text(self_,diag_buf,prefix);if error!=blot_error::Error.none {return error;}var expected="one side: ";if arguments {expected="expected argument: ";}let error=blot_reuse_type_display::text(self_,diag_buf,expected);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::text(self_,diag_buf,exp_buf);if error!=blot_error::Error.none {return error;}var actual="; other side: ";if arguments {actual="; actual argument: ";}let error=blot_reuse_type_display::text(self_,diag_buf,actual);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::text(self_,diag_buf,act_buf);if error!=blot_error::Error.none {return error;}self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText(diag_buf));return blot_error::Error.none;
    },_=>{return err;},
}}
type EquationPairs=blot_support_pooled_map::Map<u64,bool>;
reusable[] var equation_pair_slots:dictionary_slot<u64,bool>[>..];
reusable[] var equation_type_ids:u32[>..];
reusable[] var equation_values:blot_check_types::Obligation[>..];
// Recursive proof scratch carries scalar ranges; read each predicate by value.
// The range owns its allocation until freePredicates, including nested proofs.
struct PredicateRun { start:i64=0, len:i64=0 }
fn allocPredicates(length:i64)->PredicateRun {
    if length==0 { return PredicateRun{..}; }
    let values=equation_values.alloc_slice(length);
    return PredicateRun{start:equation_values.index_of(values[0]),len:length,..};
}
fn predicateAt(run:PredicateRun,index:i64)->blot_check_types::Obligation {
    assert(index>=0 && index<run.len); return equation_values[run.start+index];
}
fn setPredicate(run:PredicateRun,index:i64,value:blot_check_types::Obligation) {
    assert(index>=0 && index<run.len); equation_values[run.start+index]=value;
}
fn freePredicates(run:PredicateRun) {
    if run.len!=0 { equation_values.free_slice(equation_values[run.start..run.start+run.len]); }
}

// Arm capture keeps a scalar receipt for its live equation-owned run.
fn armVersions(capture:ArmCapture)->BindingId[:] {if capture.versions_len==0 {return default<BindingId[:]>();}return equation_type_ids[capture.versions_start..capture.versions_start+capture.versions_len];}
reusable[] var given_equation_values:blot_check_given_equations::Equation[>..];
recursive fn constrainEquationRoot(self_:Engine&,left:u32,right:u32,source:u32)->blot_error::Error {if self_.implementations.len==0 || !self_.types.has_projections {return self_.types.unify(left,right);}var pairs=EquationPairs{..};let err=self_.constrainEquation(left,right,source,0,pairs);blot_support_pooled_map::deinit(pairs,equation_pair_slots);return err;}
recursive fn constrainEquation(self_:Engine&,left:u32,right:u32,source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {let first=self_.types.head(left,0);let second=self_.types.head(right,0);if first==second {return blot_error::Error.none;}let key=((first as u64)<<32)|second;if blot_support_pooled_map::contains(pairs,key) {return blot_error::Error.none;}let err=self_.constrainEquationPair(left,right,source,depth,pairs);if err!=blot_error::Error.none {return err;}blot_support_pooled_map::insert(pairs,key,true,equation_pair_slots);return blot_error::Error.none;}
recursive fn constrainEquationPair(self_:Engine&,left:u32,right:u32,source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {
    if self_.implementations.len==0 || !self_.types.has_projections {return self_.types.unify(left,right);}if depth>=256 {return blot_error::Error.type_limit;}let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none {return err;}if !allowed {return blot_error::Error.type_limit;}let first=self_.types.node(self_.types.head(left,0));let second=self_.types.node(self_.types.head(right,0));
    if first.tag==blot_check_types::Tag.function && second.tag==blot_check_types::Tag.function {let err=self_.constrainEquation(first.a,second.a,source,depth+1,pairs);if err!=blot_error::Error.none {return err;}let err=self_.constrainEquation(first.b,second.b,source,depth+1,pairs);if err!=blot_error::Error.none {return err;}return self_.types.unifyEffects(first.c,second.c);}
    if first.tag==second.tag {match first.tag {
        array,list,cursor=>{return self_.constrainEquation(first.a,second.a,source,depth+1,pairs);},
        product=>{if first.b!=second.b {return blot_error::Error.type_mismatch;}let old=equation_type_ids.alloc_slice(first.b);let actuals=equation_type_ids.alloc_slice(second.b);let type_span_1=checkedTypeList(self_.types,blot_check_types::List{first.a,first.b, ..});for index in 0..(type_span_1.len as i64) {let value=self_.types.list(type_span_1)[index];old[index]=value;}let type_span_2=checkedTypeList(self_.types,blot_check_types::List{second.a,second.b, ..});for index in 0..(type_span_2.len as i64) {let value=self_.types.list(type_span_2)[index];actuals[index]=value;}let err=constrainProduct(self_,old,actuals,source,depth,pairs);equation_type_ids.free_slice(actuals);equation_type_ids.free_slice(old);return err;},_=>{},
    }}
    var before,err=self_.normalizeAssociated(left,source,false);if err!=blot_error::Error.none {return err;}var after,err=self_.normalizeAssociated(right,source,false);if err!=blot_error::Error.none {return err;}if self_.qualifications.len!=0 {let rewritten,err=self_.rewriteGiven(before,0);if err!=blot_error::Error.none {return err;}before=rewritten;let rewritten,err=self_.rewriteGiven(after,0);if err!=blot_error::Error.none {return err;}after=rewritten;}return self_.types.unify(before,after);
}
recursive fn constrainProduct(self_:Engine&,old:const u32[:],actuals:const u32[:],source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {for before,index in old {let err=self_.constrainEquation(before,actuals[index],source,depth+1,pairs);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn rewriteGiven(self_:Engine&,root:u32,depth:i64)->u32,blot_error::Error {if depth>=256 {return 0,blot_error::Error.type_limit;}var capacity:i64=0;for boundary in self_.qualifications {if boundary.owner==self_.current {capacity+=boundary.clauses.len;}}let equations=given_equation_values.alloc_slice(capacity);let result,err=rewriteGivenBody(self_,root,equations);given_equation_values.free_slice(equations);return result,err;}
fn rewriteGivenBody(self_:Engine&,root:u32,equations:blot_check_given_equations::Equation[:])->u32,blot_error::Error {var count:i64=0;for boundary in self_.qualifications {if boundary.owner!=self_.current {continue;}for equation in self_.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {if equation.kind!=blot_check_types::ObligationKind.type_eq {continue;}let err=self_.types.chargeProjection();if err!=blot_error::Error.none {return 0,err;}equations[count]=blot_check_given_equations::Equation{equation.ty,equation.result, ..};count+=1;}}var rewrite=blot_check_given_equations::Rewrite{store:self_.types,equations:equations[..count], ..};return rewrite.normalize(root);}
fn constrainEffects(self_:Engine&,left:u32,right:u32,source:u32)->blot_error::Error {let err=self_.types.unifyEffects(left,right);if err==blot_error::Error.effect_mismatch {return self_.diagnostic(Code.effect_mismatch,source);}if err==blot_error::Error.infinite_effect {return self_.diagnostic(Code.infinite_effect,source);}return err;}
fn invocation(self_:Engine&,parameter:u32,result:u32)->u32,blot_error::Error {return self_.types.functionWithEffects(parameter,result,self_.ambient);}
fn invocationBinary(self_:Engine&,left:u32,right:u32,result:u32)->u32,blot_error::Error {let inner,err=self_.invocation(right,result);if err!=blot_error::Error.none {return 0,err;}return self_.invocation(left,inner);}
recursive fn pureExpression(self_:Engine&,id:u32,required:u32)->u32,blot_error::Error {let saved=self_.ambient;let ambient,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}self_.ambient=ambient;let result,err=pureExpressionBody(self_,id,required);self_.ambient=saved;return result,err;}
recursive fn pureExpressionBody(self_:Engine&,id:u32,required:u32)->u32,blot_error::Error {var result:u32=0;if required!=0 {let value,err=self_.contextualLambda(id,required);if err!=blot_error::Error.none {return 0,err;}result=value;}else {let value,err=self_.expression(id);if err!=blot_error::Error.none {return 0,err;}result=value;}let err=self_.types.unifyEffects(self_.ambient,0);if err==blot_error::Error.effect_mismatch {let error=self_.diagnostic(Code.let_effect,id);return result,error;}if err==blot_error::Error.infinite_effect {let error=self_.diagnostic(Code.infinite_effect,id);return result,error;}return result,err;}
fn recordClosedRows(self_:Engine&,owner:u32,rows:blot_check_types::List)->blot_error::Error {for ordinal in 0..rows.len {let variable:u32=self_.types.list(rows)[ordinal];let key=ClosedRow{owner,variable, ..};if !self_.closed_row_keys.contains(key) {self_.closed_row_keys.insert(key,true);self_.body_closed_rows.push(key);}}return blot_error::Error.none;}
fn certifyLambda(self_:Engine&,source:u32,raw_type:u32,parent_row:u32)->blot_error::Error {let result,err=self_.certifiedLambdaType(source,raw_type,parent_row);return err;}
fn certifiedLambdaType(self_:Engine&,source:u32,raw_type:u32,parent_row:u32)->u32,blot_error::Error {let resolved,err=self_.types.resolve(raw_type,0);if err!=blot_error::Error.none {return 0,err;}let function=self_.types.node(resolved);let tail=self_.types.row(function.c).tail;var variable:u32=0;match tail {variable payload=>{variable=payload.value;},_=>{return raw_type,blot_error::Error.none;},}
    var protected:u32[>..<]=[];let environment,err=self_.environmentRows();if err!=blot_error::Error.none {return 0,err;}protected.append(environment);equation_type_ids.free_slice(environment);let parent,err=self_.types.effects.freeVariables(parent_row);if err!=blot_error::Error.none {return 0,blot_check_types::effectError(err);}for variable in parent {if !inList(protected,variable) {protected.push(variable);}}
    for pending in self_.pending[self_.pending_start..] {if pending.solved || pending.owner!=self_.current {continue;}for part in [pending.value.ty,pending.value.other,pending.value.result,pending.value.signature] {if part==0 {continue;}let free,err=self_.types.freeRowVariables(part);if err!=blot_error::Error.none {return 0,err;}for variable in free {if !inList(protected,variable) {protected.push(variable);}}}}
    let root,err=self_.types.resolve(raw_type,0);if err!=blot_error::Error.none {return 0,err;}let decision,err=self_.types.closeCovariantCertified(root,[variable],protected);if err!=blot_error::Error.none {return 0,err;}if decision.closed_rows.len==0 {return decision.root,blot_error::Error.none;}self_.row_sources.insert(variable,source);let err=self_.recordClosedRows(self_.current,decision.closed_rows);return decision.root,err;
}
fn addBinding(self_:Engine&,value:Binding)->u32,blot_error::Error {let id=self_.bindings.len as u32;self_.bindings.push(value);return id,blot_error::Error.none;}
fn lookup(self_:const Engine&,name:u32)->blot_support::Option<u32> {var index=self_.env.len;while index!=0 {index-=1;if self_.env[index].name==name {return blot_support::some(self_.env[index].binding);}}return blot_support::none<u32>();}
fn inList(values:const u32[:],wanted:u32)->bool {for value in values {if value==wanted {return true;}}return false;}
fn catalogKey(self_:const Engine&,name:u32)->Qualified {let qualified=self_.qualifiedKey(name);if qualified.present {return qualified.value;}return Qualified{0,name, ..};}
fn memberOperator(name:const u8[:])->blot_check_types::Operator {if name=="add" {return blot_check_types::Operator.add;}if name=="sub" {return blot_check_types::Operator.sub;}if name=="mul" {return blot_check_types::Operator.mul;}if name=="div" {return blot_check_types::Operator.div;}if name=="rem" {return blot_check_types::Operator.rem;}if name=="eq" {return blot_check_types::Operator.equal;}if name=="ne" {return blot_check_types::Operator.not_equal;}if name=="lt" {return blot_check_types::Operator.less;}if name=="le" {return blot_check_types::Operator.less_equal;}if name=="gt" {return blot_check_types::Operator.greater;}if name=="ge" {return blot_check_types::Operator.greater_equal;}if name=="bit_and" {return blot_check_types::Operator.bit_and;}if name=="bit_or" {return blot_check_types::Operator.bit_or;}if name=="bit_xor" {return blot_check_types::Operator.bit_xor;}if name=="shl" {return blot_check_types::Operator.shift_left;}if name=="shr" {return blot_check_types::Operator.shift_right;}return blot_check_types::Operator.none;}
fn symbolOperator(name:const u8[:])->blot_check_types::Operator {if name=="+" {return blot_check_types::Operator.add;}if name=="-" {return blot_check_types::Operator.sub;}if name=="*" {return blot_check_types::Operator.mul;}if name=="/" {return blot_check_types::Operator.div;}if name=="%" {return blot_check_types::Operator.rem;}if name=="==" {return blot_check_types::Operator.equal;}if name=="!=" {return blot_check_types::Operator.not_equal;}if name=="<" {return blot_check_types::Operator.less;}if name=="<=" {return blot_check_types::Operator.less_equal;}if name==">" {return blot_check_types::Operator.greater;}if name==">=" {return blot_check_types::Operator.greater_equal;}if name=="&" {return blot_check_types::Operator.bit_and;}if name=="|" {return blot_check_types::Operator.bit_or;}if name=="^" {return blot_check_types::Operator.bit_xor;}if name=="<<" {return blot_check_types::Operator.shift_left;}if name==">>" {return blot_check_types::Operator.shift_right;}return blot_check_types::Operator.none;}
fn identityOf(self_:const Engine&,ty:u32)->blot_support::Option<Identity> {return blot_check_types::receiverIdentity(self_.types.node(self_.types.head(ty,0)));}
fn indexAssociated(self_:Engine&)->blot_error::Error {
    for slot in 0..(self_.imported_global_order.capacity as i64) {if !blot_support_zigmap::used(self_.zig_orders,self_.imported_global_order,slot as u32) {continue;}let key=blot_support_zigmap::keyAt(self_.zig_orders,self_.imported_global_order,slot as u32);let found .= self_.imported_globals.get(key);assert(found!=null);let target:ExternalTarget=found;let text=self_.pool.get(key);let dot=lastDot(text);if !dot.present {continue;}let head=text[..dot.value];let name,present=self_.pool.lookup(head);if !present {continue;}if self_.builtin_catalog || self_.catalogs.nominal_names.contains(Qualified{0,name, ..}) {let binding,err=self_.importedBinding(target);if err!=blot_error::Error.none {return err;}if binding.present {self_.catalogs.globals.insert(key,binding.value);blot_support_zigmap::put(self_.zig_orders,self_.global_order,key,0);}}}
    for slot in 0..(self_.global_order.capacity as i64) {if !blot_support_zigmap::used(self_.zig_orders,self_.global_order,slot as u32) {continue;}let entry_key=blot_support_zigmap::keyAt(self_.zig_orders,self_.global_order,slot as u32);if self_.catalogs.implementation_names.contains(Qualified{0,entry_key, ..}) {continue;}let entry_found .= self_.catalogs.globals.get(entry_key);assert(entry_found!=null);let entry_val:u32=entry_found;let text=self_.pool.get(entry_key);let dot=lastDot(text);if !dot.present {continue;}let head=text[..dot.value];let member,present=self_.pool.lookup(text[dot.value+1..]);if !present {continue;}var identity=blot_support::none<Identity>();let name,present=self_.pool.lookup(head);if present {let scalar_lookup_18 .= self_.catalogs.nominal_names.get(Qualified{0,name, ..});if scalar_lookup_18 && self_.nominals[scalar_lookup_18].alias==0 {let index:u32=scalar_lookup_18;identity=blot_support::some(self_.nominals[index].identity);}}
        if !identity.present && self_.builtin_catalog {if head=="U32" {identity=blot_support::some(Identity{0,blot_check_types::u32_type, ..});}else if head=="F32" {identity=blot_support::some(Identity{0,blot_check_types::f32_type, ..});}else if head=="Bool" {identity=blot_support::some(Identity{0,blot_check_types::boolean, ..});}else if head=="Unit" {identity=blot_support::some(Identity{0,blot_check_types::unit, ..});}else if head=="Array" {identity=blot_support::some(Identity{0,0xffffffff, ..});}else {let kind=blot_check_storage_types::named(head);if kind.present {identity=blot_support::some(Identity{0xffffffff,kind.value, ..});}}}
        if identity.present {let owner=identity.value;if owner.unit!=0 && owner.unit!=self_.unit && !(self_.builtin_catalog && blot_check_storage_types::identity(owner.unit,owner.decl).present) {continue;}let operator=memberOperator(text[dot.value+1..]);let index=self_.associated.len as u32;self_.associated.push(Associated{owner,member,operator,entry_val, ..});if operator!=blot_check_types::Operator.none && self_.bindings[entry_val].capability_parameters.own!=0 {let err=self_.diagnostic(Code.own_parameter,self_.bindings[entry_val].declaration);if err!=blot_error::Error.none {return err;}}self_.catalogs.associated_members.insert(AssociatedMember{owner,member, ..},index);if operator!=blot_check_types::Operator.none {self_.catalogs.associated_ops.insert(AssociatedKey{owner,operator, ..},index);}}
    }return blot_error::Error.none;
}
enum AssociatedChoice {absent,waiting,selected {ty:u32,binding:u32}}
recursive fn tryAssociated(self_:Engine&,identity:Identity,member:u32,operator:blot_check_types::Operator,left:u32,right:u32,source:u32)->AssociatedChoice,blot_error::Error {var index:u32=0;if member==0 {let found:u32={let scalar_lookup_19 .= self_.catalogs.associated_ops.get(AssociatedKey{identity,operator, ..});if !scalar_lookup_19 {return AssociatedChoice.absent,blot_error::Error.none;}let scalar_value_19:u32=scalar_lookup_19;scalar_value_19};index=found;}else {let found:u32={let scalar_lookup_20 .= self_.catalogs.associated_members.get(AssociatedMember{identity,member, ..});if !scalar_lookup_20 {return AssociatedChoice.absent,blot_error::Error.none;}let scalar_value_20:u32=scalar_lookup_20;scalar_value_20};index=found;}let binding,err=self_.associatedBinding(index);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let prepared,err=self_.prepareSelectedGlobal(binding);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}if !prepared {return AssociatedChoice.waiting,blot_error::Error.none;}let point=self_.types.mark();let pending=self_.pending.len;self_.mark_depth+=1;let choice,err=tryAssociatedBody(self_,binding,left,right,source,point,pending);self_.mark_depth-=1;return choice,err;}
fn tryAssociatedBody(self_:Engine&,binding:u32,left:u32,right:u32,source:u32,point:blot_check_types::Mark,pending:i64)->AssociatedChoice,blot_error::Error {let function,err=self_.instantiate(binding,source);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let expected,err=self_.invocationBinary(left,right,result);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let err=self_.types.unify(function,expected);if err!=blot_error::Error.none {if err==blot_error::Error.type_mismatch || err==blot_error::Error.infinite_type || err==blot_error::Error.effect_mismatch || err==blot_error::Error.infinite_effect {self_.types.rollback(point);self_.pending.resize(pending);return AssociatedChoice.absent,blot_error::Error.none;}return AssociatedChoice.absent,err;}self_.dispatch_signatures[source]=expected;return AssociatedChoice.selected{result,binding, ..},blot_error::Error.none;}
recursive fn dispatch(self_:Engine&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,source:u32,direct:bool)->blot_support::Option<u32>,blot_error::Error {let a,err=self_.types.resolve(left,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let b,err=self_.types.resolve(right,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let an=self_.types.node(a);let bn=self_.types.node(b);if an.tag==blot_check_types::Tag.variable || bn.tag==blot_check_types::Tag.variable {return blot_support::none<u32>(),blot_error::Error.none;}
    let identity=self_.identityOf(a);if identity.present {let choice,err=self_.tryAssociated(identity.value,member,operator,a,b,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}match choice {absent=>{},waiting=>{return blot_support::none<u32>(),blot_error::Error.none;},selected value=>{if direct {self_.resolved[source]=value.binding;}self_.dispatch_side=blot_reuse_dispatch_explanation::Side.left;return blot_support::some(value.ty),blot_error::Error.none;},}}
    let scalar_a=an.tag==blot_check_types::Tag.unsigned32 || an.tag==blot_check_types::Tag.floating32 || an.tag==blot_check_types::Tag.boolean;let scalar_b=bn.tag==blot_check_types::Tag.unsigned32 || bn.tag==blot_check_types::Tag.floating32 || bn.tag==blot_check_types::Tag.boolean;
    if member==0 && scalar_a && scalar_b && an.tag==bn.tag {let comparison=operator==blot_check_types::Operator.equal || operator==blot_check_types::Operator.not_equal || operator==blot_check_types::Operator.less || operator==blot_check_types::Operator.less_equal || operator==blot_check_types::Operator.greater || operator==blot_check_types::Operator.greater_equal;let equality=operator==blot_check_types::Operator.equal || operator==blot_check_types::Operator.not_equal;let integer=operator==blot_check_types::Operator.rem || operator==blot_check_types::Operator.bit_and || operator==blot_check_types::Operator.bit_or || operator==blot_check_types::Operator.bit_xor || operator==blot_check_types::Operator.shift_left || operator==blot_check_types::Operator.shift_right;
        if (an.tag==blot_check_types::Tag.boolean && !equality) || (an.tag==blot_check_types::Tag.floating32 && integer) {let err=self_.diagnostic(Code.ambiguous_operator,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.explainDispatch(a,member,operator,true);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self_.types.fresh();return blot_support::some(result),err;}self_.dispatch_side=blot_reuse_dispatch_explanation::Side.builtin;if comparison {return blot_support::some(blot_check_types::boolean),blot_error::Error.none;}return blot_support::some(a),blot_error::Error.none;
    }
    if an.tag==blot_check_types::Tag.projection || bn.tag==blot_check_types::Tag.projection {return blot_support::none<u32>(),blot_error::Error.none;}
    var code=Code.ambiguous_operator;
    if member!=0 {code=Code.missing_associated;}
    let err=self_.diagnostic(code,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.explainDispatch(a,member,operator,false);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self_.types.fresh();return blot_support::some(result),err;
}
fn spellType(self_:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,ty:u32)->const u8[:],blot_error::Error {var buf:u8[>..<]=[];let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return default<const u8[:]>(),err;}let err=blot_reuse_type_display::append(self_,buf,resolved);if err!=blot_error::Error.none {return default<const u8[:]>(),err;}return builder.own(buf);}
fn spellStable(self_:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,root:u32)->const u8[:],blot_error::Error {var buf:u8[>..<]=[];let err=blot_reuse_type_display::appendStable(self_,buf,root);if err==blot_error::Error.out_of_memory {return default<const u8[:]>(),err;}if err!=blot_error::Error.none {builder.truncated=true;}return builder.own(buf);}
fn explainOperand(self_:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,side:blot_reuse_dispatch_explanation::Side,ty:u32,member:u32,operator:blot_check_types::Operator)->blot_error::Error {let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return err;}var outcome=blot_reuse_dispatch_explanation::Outcome.no_member;if self_.types.node(resolved).tag==blot_check_types::Tag.variable {outcome=blot_reuse_dispatch_explanation::Outcome.unknown_operand;}else {let identity=self_.identityOf(resolved);if identity.present {var present=false;if member==0 {present=self_.catalogs.associated_ops.contains(AssociatedKey{identity.value,operator, ..});}else {present=self_.catalogs.associated_members.contains(AssociatedMember{identity.value,member, ..});}if present {outcome=blot_reuse_dispatch_explanation::Outcome.incompatible;}}}let operand,err=self_.spellType(builder,resolved);if err!=blot_error::Error.none {return err;}builder.add(side,blot_support::some(operand),outcome);return blot_error::Error.none;}
fn attachExplanation(self_:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,member:u32,operator:blot_check_types::Operator)->blot_error::Error {let explanation,err=finishNamedExplanation(self_.pool,builder,member,operator);if err!=blot_error::Error.none {return err;}let issue .= self_.diagnostics[self_.diagnostics.len-1];if issue.explanation.present {issue.explanation.value.deinit();}issue.explanation=blot_support::Option<blot_reuse_dispatch_explanation::Explanation>{true,blot_reuse_dispatch_explanation::canonicalOwned(explanation)};return blot_error::Error.none;}
fn explainDispatch(self_:Engine&,left:u32,member:u32,operator:blot_check_types::Operator,scalar_rejected:bool)->blot_error::Error {
    var builder=blot_reuse_dispatch_explanation::Builder{..};
    var err=self_.explainOperand(builder,blot_reuse_dispatch_explanation::Side.left,left,member,operator);
    if err==blot_error::Error.none {
        if scalar_rejected {builder.add(blot_reuse_dispatch_explanation::Side.builtin,blot_support::none<const u8[:]>(),blot_reuse_dispatch_explanation::Outcome.unsupported_scalar);}
        err=self_.attachExplanation(builder,member,operator);
    }
    builder.deinit();
    return err;
}
fn explainSelected(self_:Engine&,left:u32,member:u32,operator:blot_check_types::Operator,side:blot_reuse_dispatch_explanation::Side)->blot_error::Error {
    var builder=blot_reuse_dispatch_explanation::Builder{..};
    let spelled,err=self_.spellType(builder,left);
    if err!=blot_error::Error.none {builder.deinit();return err;}
    builder.add(side,blot_support::some(spelled),blot_reuse_dispatch_explanation::Outcome.result_mismatch);
    let err=self_.attachExplanation(builder,member,operator);
    builder.deinit();
    return err;
}
fn explainResult(self_:Engine&,destination:u32,member:u32)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{..};var err=self_.explainOperand(builder,blot_reuse_dispatch_explanation::Side.destination,destination,member,blot_check_types::Operator.none);if err==blot_error::Error.none {err=self_.attachExplanation(builder,member,blot_check_types::Operator.none);}builder.deinit();return err;}
fn explainReceiver(self_:Engine&,receiver:u32,member:u32)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{..};let spelling,err=self_.spellType(builder,receiver);if err!=blot_error::Error.none {builder.deinit();return err;}builder.add(blot_reuse_dispatch_explanation::Side.receiver,blot_support::some(spelling),blot_reuse_dispatch_explanation::Outcome.no_member);let err=self_.attachExplanation(builder,member,blot_check_types::Operator.none);builder.deinit();return err;}
recursive fn resultDispatch(self_:Engine&,input:u32,expected:u32,member:u32,source:u32,direct:bool)->blot_support::Option<u32>,blot_error::Error {let destination,err=self_.types.resolve(expected,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let identity=self_.identityOf(destination);if !identity.present {return blot_support::none<u32>(),blot_error::Error.none;}let index:u32={let scalar_lookup_21 .= self_.catalogs.associated_members.get(AssociatedMember{identity.value,member, ..});if !scalar_lookup_21 {return blot_support::none<u32>(),blot_error::Error.none;}let scalar_value_21:u32=scalar_lookup_21;scalar_value_21};let binding,err=self_.associatedBinding(index);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let prepared,err=self_.prepareSelectedGlobal(binding);if err!=blot_error::Error.none || !prepared {return blot_support::none<u32>(),err;}let function,err=self_.instantiate(binding,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let expected_function,err=self_.invocation(input,destination);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.constrain(function,expected_function,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.dispatch_signatures[source]=expected_function;if direct {self_.resolved[source]=binding;}return blot_support::some(destination),blot_error::Error.none;}
fn typeVariable(self_:Engine&,name:u32,source:u32)->u32,blot_error::Error {for entry,index in self_.row_env.items {if entry.name==name {var point=source;if index<self_.inherited_rows {point=self_.annotation_binding;}let err=self_.diagnostic(Code.annotation_kind_mismatch,point);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}}var index=self_.type_env.items.len;while index!=0 {index-=1;if self_.type_env.items[index].name==name {return self_.type_env.items[index].ty,blot_error::Error.none;}}let ty,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}if self_.closed_type_variables {let err=self_.diagnostic(Code.unsupported_type,source);return ty,err;}let growth=self_.type_env.append(Engine_type_env{name,ty, ..});return ty,growth;}
fn rowVariable(self_:Engine&,name:u32,source:u32)->u32,blot_error::Error {var type_index=self_.type_env.items.len;while type_index!=0 {type_index-=1;let entry=self_.type_env.items[type_index];if entry.name!=name {continue;}let leaf=self_.types.node(self_.types.head(entry.ty,0));if (leaf.tag==blot_check_types::Tag.bound && leaf.b==1) || (leaf.tag==blot_check_types::Tag.rigid && leaf.c==1) {break;}var point=source;if type_index<self_.inherited_types {point=self_.annotation_binding;}let err=self_.diagnostic(Code.annotation_kind_mismatch,point);if err!=blot_error::Error.none {return 0,err;}return self_.types.freshEffects();}var index=self_.row_env.items.len;while index!=0 {index-=1;if self_.row_env.items[index].name==name {return self_.row_env.items[index].row,blot_error::Error.none;}}let row,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}if self_.closed_type_variables && !self_.implicit_row_parameters {let err=self_.diagnostic(Code.invalid_effect_annotation,source);return row,err;}let growth=self_.row_env.append(Engine_row_env{name,row, ..});return row,growth;}
recursive fn collectAnnotationNames(self_:Engine&,id:u32,depth:i64)->blot_error::Error {if id==0 {return blot_error::Error.none;}if depth>=1024 {return blot_error::Error.type_limit;}let node=self_.tree.node(id);match node.tag {
    blot_parse_ast::tag_let_stmt=>{if self_.source_validation {let binding=self_.tree.binding(id);for child in [binding.annotation,binding.where_node,binding.value,binding.fallback] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}}},
    blot_parse_ast::tag_type_name=>{let name=self_.pool.get(node.a);if blot_check_storage_types::named(name).present || blot_check_storage_types::parseLengthLiteral(name).present {return blot_error::Error.none;}if name.len!=0 && ((name[0]>='a' as u8 && name[0]<='z' as u8) || name[0]=='_' as u8) {let dot=firstDot(name);if !dot.present {let ty,err=self_.typeVariable(node.a,id);if err!=blot_error::Error.none {return err;}}else {let head,known=self_.pool.lookup(name[..dot.value]);if known && !self_.isNamespace(head) {let ty,err=self_.typeVariable(head,id);if err!=blot_error::Error.none {return err;}}}}},
    blot_parse_ast::tag_effect_row=>{if node.c!=0 {let row,err=self_.rowVariable(self_.tree.node(node.c).a,node.c);if err!=blot_error::Error.none {return err;}}let syntax_source_2=blot_parse_ast::List{node.a,node.b, ..};let syntax_count_2=self_.tree.list(syntax_source_2).len;for syntax_index_2 in 0..syntax_count_2 {let label=self_.tree.list(syntax_source_2)[syntax_index_2];let err=self_.collectEffectArgumentNames(label,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_where_clause=>{let syntax_source_3=blot_parse_ast::List{node.a,node.b, ..};let syntax_count_3=self_.tree.list(syntax_source_3).len;for syntax_index_3 in 0..syntax_count_3 {let child=self_.tree.list(syntax_source_3)[syntax_index_3];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_constraint=>{let details=checkedAstRange(self_.tree,node.c,node.c+3);let arguments=checkedAstList(self_.tree,blot_parse_ast::List{self_.tree.list(details)[0],self_.tree.list(details)[1], ..});var skip:i64=0;if self_.pool.get(node.a)=="operation" && (arguments.len as i64)!=0 {skip=1;}let ast_span_1=checkedAstSubspan(self_.tree,arguments,skip,(arguments.len as i64));for ast_index_1 in 0..(ast_span_1.len as i64) {let child=self_.tree.list(ast_span_1)[ast_index_1];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}let err=self_.collectAnnotationNames(self_.tree.list(details)[2],depth+1);if err!=blot_error::Error.none {return err;}},
    blot_parse_ast::tag_lambda=>{for child in [self_.tree.parameter(node.a).annotation,node.c,node.b] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_group,blot_parse_ast::tag_type_witness,blot_parse_ast::tag_field_access,blot_parse_ast::tag_return_stmt,blot_parse_ast::tag_forever_stmt=>{return self_.collectAnnotationNames(node.a,depth+1);},
    blot_parse_ast::tag_field,blot_parse_ast::tag_unary,blot_parse_ast::tag_operator_tail,blot_parse_ast::tag_type_usage=>{return self_.collectAnnotationNames(node.b,depth+1);},
    blot_parse_ast::tag_type_field,blot_parse_ast::tag_type_binder=>{if node.b==0 {let value,err=self_.typeVariable(node.a,id);return err;}return self_.collectAnnotationNames(node.b,depth+1);},
    blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access,blot_parse_ast::tag_rebind_stmt,blot_parse_ast::tag_type_apply,blot_parse_ast::tag_type_effect=>{for child in [node.a,node.b] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_binary=>{for child in [node.b,node.c] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_type_function,blot_parse_ast::tag_if_expr,blot_parse_ast::tag_if_stmt,blot_parse_ast::tag_range_stmt=>{for child in [node.a,node.b,node.c] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{for child in [node.c,node.b] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_product,blot_parse_ast::tag_array,blot_parse_ast::tag_record,blot_parse_ast::tag_type_product,blot_parse_ast::tag_type_array,blot_parse_ast::tag_type_record=>{let syntax_source_4=id;let syntax_count_4=self_.tree.children(syntax_source_4).len;for syntax_index_4 in 0..syntax_count_4 {let child=self_.tree.children(syntax_source_4)[syntax_index_4];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_block=>{let err=self_.collectAnnotationNames(node.c,depth+1);if err!=blot_error::Error.none {return err;}let syntax_source_5=id;let syntax_count_5=self_.tree.children(syntax_source_5).len;for syntax_index_5 in 0..syntax_count_5 {let child=self_.tree.children(syntax_source_5)[syntax_index_5];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_fork_expr=>{let err=self_.collectAnnotationNames(node.c,depth+1);if err!=blot_error::Error.none {return err;}},
    blot_parse_ast::tag_with_stmt=>{let entries=blot_parse_ast::List{node.a,node.b, ..};let ecount=self_.tree.list(entries).len;for ei in 0..ecount {let en=self_.tree.node(self_.tree.list(entries)[ei]);let err=self_.collectAnnotationNames(en.a,depth+1);if err!=blot_error::Error.none {return err;}if en.c==1 {let err=self_.collectAnnotationNames(en.b,depth+1);if err!=blot_error::Error.none {return err;}}}return self_.collectAnnotationNames(node.c,depth+1);},
    blot_parse_ast::tag_comptime_for=>{let err=self_.collectAnnotationNames(node.b,depth+1);if err!=blot_error::Error.none {return err;}return self_.collectAnnotationNames(self_.tree.extra.items[node.c],depth+1);},
    blot_parse_ast::tag_comptime_if=>{for child in [node.a,node.b,node.c] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_comptime_project=>{return self_.collectAnnotationNames(node.a,depth+1);},
    blot_parse_ast::tag_infix_chain=>{let err=self_.collectAnnotationNames(node.a,depth+1);if err!=blot_error::Error.none {return err;}let syntax_source_6=blot_parse_ast::List{node.b,node.c, ..};let syntax_count_6=self_.tree.list(syntax_source_6).len;for syntax_index_6 in 0..syntax_count_6 {let child=self_.tree.list(syntax_source_6)[syntax_index_6];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_if_let_stmt,blot_parse_ast::tag_for_stmt=>{let err=self_.collectAnnotationNames(node.b,depth+1);if err!=blot_error::Error.none {return err;}let metadata=checkedAstRange(self_.tree,node.c,self_.tree.extra.items.len);let ast_span_2=checkedAstSubspan(self_.tree,metadata,0,2);for ast_index_2 in 0..(ast_span_2.len as i64) {let child=self_.tree.list(ast_span_2)[ast_index_2];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_case_expr=>{let inputs=checkedAstRange(self_.tree,node.a,node.a+2);let syntax_source_7=blot_parse_ast::List{self_.tree.list(inputs)[0],self_.tree.list(inputs)[1], ..};let syntax_count_7=self_.tree.list(syntax_source_7).len;for syntax_index_7 in 0..syntax_count_7 {let child=self_.tree.list(syntax_source_7)[syntax_index_7];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}let syntax_source_8=blot_parse_ast::List{node.b,node.c, ..};let syntax_count_8=self_.tree.list(syntax_source_8).len;for syntax_index_8 in 0..syntax_count_8 {let child=self_.tree.list(syntax_source_8)[syntax_index_8];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_case_arm=>{let ast_walk_10_start=(node.c) as i64;let ast_walk_10_count=self_.tree.extra.items[ast_walk_10_start..node.c+2].len;for ast_walk_10_index in 0..ast_walk_10_count {let child=self_.tree.extra.items[ast_walk_10_start+ast_walk_10_index];let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_spark_expr=>{for child in [self_.tree.spark_source(id),self_.tree.spark_end(id),node.a] {let err=self_.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},_=>{},
    }return blot_error::Error.none;
}
recursive fn collectEffectArgumentNames(self_:Engine&,id:u32,depth:i64)->blot_error::Error {if depth>=1024 {return blot_error::Error.type_limit;}let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_type_apply {let err=self_.collectEffectArgumentNames(node.a,depth+1);if err!=blot_error::Error.none {return err;}return self_.collectAnnotationNames(node.b,depth+1);}return blot_error::Error.none;}
fn nominalIndex(self_:const Engine&,identity:Identity)->blot_support::Option<u32> {let scalar_lookup_24 .= self_.catalogs.nominal_identities.get(identity);if scalar_lookup_24 {let value:u32=scalar_lookup_24;return blot_support::some<u32>(value);}return blot_support::none<u32>();}
fn copyNominal(self_:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {
    var source=producer.nominals[source_index];
    let known=self_.nominalIndex(source.identity);
    if known.present {return known.value,blot_error::Error.none;}
    if source.is_opaque && self_.producer_storage.present {
        let storage=self_.producer_storage.value.lookup(source.identity);
        if storage.present {source.storage=storage.value;}
    }
    // Persistent worker packets retain constructor identities and indices.
    // A forwarding record reads its signature from the defining module.
    if source.identity.unit!=producer.unit && source.constructors.len!=0 {
        let first=producer.types.list(source.constructors)[0];
        if producer.constructors[first].scheme.root==blot_reuse_principal_interface::forwarded_constructor {
            return self_.copyForwardedNominal(source.identity);
        }
    }
    return self_.copyNominalDefinition(producer,source);
}
fn copyForwardedNominal(self_:Engine&,identity:Identity)->u32,blot_error::Error {
    if !self_.producer_storage.present {return 0,blot_error::Error.invalid_artifact;}
    let project .= self_.producer_storage.value.context.borrow();
    if !project {return 0,blot_error::Error.invalid_artifact;}
    let module=project.catalogModule(identity.unit);
    if !module.present {return 0,blot_error::Error.invalid_artifact;}
    let producer=module.value.catalog();
    let indices .= self_.catalogs.producer_nominal_indices;
    if !indices.contains(identity) {
        // Index the origin's own declarations together. Many imported names
        // can refer back to a single module.
        for nominal,index in producer.nominals[1..] {
            if nominal.identity.unit!=identity.unit {break;}
            if !nominal.private {indices.insert(nominal.identity,(index+1) as u32);}
        }
    }
    let index .= indices.get(identity);
    if !index {return 0,blot_error::Error.invalid_artifact;}
    return self_.copyNominalDefinition(producer,producer.nominals[index]);
}
fn copyNominalDefinition(self_:Engine&,producer:DeclarationCatalog,source:Nominal)->u32,blot_error::Error {
    var defer_result=false;
    if !self_.source_validation && source.closed_storage && !source.private && !source.is_opaque &&
        source.variables.len==0 && source.parameters.len==0 && source.alias==0 && self_.producer_storage.present {
        let project .= self_.producer_storage.value.context.borrow();
        if project {defer_result=project.persistent_cache!=0;}
    }
    var copier=blot_check_check_scheme_import::init(producer.types,self_.types,self_.import_tables);
    let index,error=copyNominalBody(self_,copier,producer,source,defer_result);
    copier.reset();
    return index,error;
}
// Copied type children have their own immutable spans. A closed copy therefore
// remains resolved when inference invalidates the store's transient caches.
fn copiedConstructorHeight(self_:const Engine&,root:u32)->u8 {
    if root==0 {return 1;}
    return self_.types.closedHeight(root);
}
fn copyNominalBody(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Nominal,defer_result:bool)->u32,blot_error::Error {
    var variables:u32[>..<]=[];for old in producer.types.list(source.variables) {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.push(fresh);}var parameters:u32[>..<]=[];for old in producer.types.list(source.parameters) {let parameter,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.push(parameter);}
    let index=self_.nominals.len as u32;let quantified,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let names,err=self_.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let patterns,err=self_.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let alias_rows,err=copier.quantifiedRows(source.alias_rows);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}var alias:u32=0;if source.alias!=0 {let value,err=copier.copy(source.alias,0);if err!=blot_error::Error.none {return 0,err;}alias=value;}
    self_.nominals.push(Nominal{ affine:source.affine, has_usage:source.has_usage, closed_storage:source.closed_storage, private:source.private, is_opaque:source.is_opaque, storage:source.storage, identity:source.identity, name:source.name, parameters:parameter_list, variables:quantified, patterns:patterns, parameter_names:names, alias:alias, alias_rows:alias_rows, .. });self_.catalogs.nominal_identities.insert(source.identity,index);
    var constructors:u32[>..<]=[];
    for old in producer.types.list(source.constructors) {
        if source.is_opaque {continue;}
        let ctor=producer.constructors[old];
        var signature=ctor.scheme.root;
        var delayed=false;
        if defer_result {
            // Complete archives may also supply this catalog. Verify the pure
            // constructor returns this exact family before dropping its root.
            let root=producer.types.node(signature);
            var result=root;
            var parameter:u32=0;
            if ctor.payload!=0 && root.tag==blot_check_types::Tag.function && root.c==0 {
                result=producer.types.node(root.b);
                parameter=root.a;
            }
            if (ctor.payload==0 || parameter!=0) && result.tag==blot_check_types::Tag.nominal &&
                result.a==source.identity.unit && result.b==source.identity.decl && producer.types.nominalArguments(result).len==0 {
                signature=parameter;
                delayed=true;
            }
        }
        let root,err=copier.copy(signature,0);
        if err!=blot_error::Error.none {return 0,err;}
        var payload:u32=0;
        if ctor.payload!=0 {
            let value,err=copier.copy(ctor.payload,0);
            if err!=blot_error::Error.none {return 0,err;}
            payload=value;
        }
        let own=self_.constructors.len as u32;
        self_.constructors.push(Constructor{identity:ctor.identity,nominal:index,tag:ctor.tag,name:ctor.name,scheme:blot_check_types::Scheme{root:root,variables:quantified,..},payload:payload,declared_record:ctor.declared_record,deferred_result:delayed,..});
        let signature_height=self_.copiedConstructorHeight(root);
        let payload_height=self_.copiedConstructorHeight(payload);
        // Editor completion can load another projected scheme after finalization.
        if !self_.editor_marker.present && signature_height!=0 && payload_height!=0 {
            while self_.imported_constructor_heights.len<own {self_.imported_constructor_heights.push(0);}
            self_.imported_constructor_heights.push(max(signature_height,payload_height));
        }
        self_.catalogs.constructor_identities.insert(ctor.identity,own);
        constructors.push(own);
    }
    let catalog,err=self_.types.saveList(constructors);if err!=blot_error::Error.none {return 0,err;}self_.nominals[index].constructors=catalog;return index,blot_error::Error.none;
}
fn copyEffectFamily(self_:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.effect_families[source_index];let scalar_lookup_25 .= self_.catalogs.effect_family_identities.get(source.identity);if scalar_lookup_25 {let known:u32=scalar_lookup_25;return known,blot_error::Error.none;}var copier=blot_check_check_scheme_import::init(producer.types,self_.types,self_.import_tables);let family,err=copyEffectFamilyBody(self_,copier,producer,source);copier.reset();return family,err;}
fn copyEffectFamilyBody(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:EffectFamily)->u32,blot_error::Error {
    var variables:u32[>..<]=[];for old in producer.types.list(source.variables) {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.push(fresh);}var parameters:u32[>..<]=[];for old in producer.types.list(source.parameters) {let copied,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.push(copied);}if self_.effect_families.len==0xffffffff {return 0,blot_error::Error.type_limit;}let family=self_.effect_families.len as u32;let patterns,err=self_.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}let names,err=self_.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}
    self_.effect_families.push(EffectFamily{ private:source.private, identity:source.identity, name:source.name, callable:source.callable, parameters:parameter_list, variables:quantified, patterns:patterns, parameter_names:names, .. });self_.catalogs.effect_family_identities.insert(source.identity,family);
    var operations:u32[>..<]=[];for old in producer.types.list(source.operations) {let template=producer.effect_templates[old];if self_.effect_templates.len==0xffffffff {return 0,blot_error::Error.type_limit;}let index=self_.effect_templates.len as u32;let parameter,err=copier.copy(template.parameter,0);if err!=blot_error::Error.none {return 0,err;}let result,err=copier.copy(template.result,0);if err!=blot_error::Error.none {return 0,err;}self_.effect_templates.push(EffectTemplate{template.identity,family,template.name,parameter,result, ..});self_.catalogs.effect_members.insert(EffectMember{family,template.name, ..},index);self_.catalogs.effect_template_identities.insert(template.identity,index);operations.push(index);}let catalog,err=self_.types.saveList(operations);if err!=blot_error::Error.none {return 0,err;}self_.effect_families[family].operations=catalog;return family,blot_error::Error.none;
}
fn catalog(self_:SourceCatalog)->DeclarationCatalog {return self_.producer;}
fn declaration(self_:SourceCatalog,id:u32)->SourceDeclaration {return self_.declarations[id];}
fn importAssociatedHeader(self_:Engine&,definition:SourceDeclaration,target:ExternalTarget,origin:u32,owned:blot_support::Option<ProducerCapability>)->blot_error::Error {var parameters=definition.capability_parameters;if owned.present {parameters=owned.value.parameters;}return self_.importHeader(SourceHeader{ capability_parameters:parameters, target:target, named_function:definition.named_function, origin:origin, expose:false, .. });}
fn importedMethodBinding(engine:Engine&,target:ExternalTarget)->u32,bool,blot_error::Error {let binding,err=engine.importedBinding(target);if err!=blot_error::Error.none {return 0,false,err;}assert(binding.present);return binding.value,true,blot_error::Error.none;}
fn importMethod(self_:SourceCatalog,engine:Engine&,definition:SourceDeclaration,target:ExternalTarget,owned:blot_support::Option<ProducerCapability>,binding:u32)->u32,bool,blot_error::Error {let err=engine.importAssociatedHeader(definition,target,self_.origin,owned);if err!=blot_error::Error.none {return 0,false,err;}return importedMethodBinding(engine,target);}
fn importMethod(self_:ImportedCatalog,engine:Engine&,definition:SourceDeclaration,target:ExternalTarget,owned:blot_support::Option<ProducerCapability>,binding:u32)->u32,bool,blot_error::Error {if engine.source_validation {let err=engine.importAssociatedHeader(definition,target,self_.origin,owned);if err!=blot_error::Error.none {return 0,false,err;}return importedMethodBinding(engine,target);}
 // The forwarding module copied the scheme only if it used the member, so
 // the producer's own scheme is preferred.
 var interface=default<SchemeInterface>();var produced=false;if definition.external.present {let published=engine.producerInterface(target);if published.present {interface=published.value;produced=true;}}if !produced {interface=self_.interface(binding);}
 if definition.external.present && interface.scheme.root==0 {return 0,false,blot_error::Error.none;}
 if owned.present {let facts=owned.value;interface.capability_parameters=facts.parameters.withOwnership(interface.capability_parameters);}let err=engine.importBinding(ImportedBinding{target:target,interface:interface,origin:self_.origin,expose:false, ..});if err!=blot_error::Error.none {return 0,false,err;}
 if engine.defersAssociated() {if engine.associated_pending.len>=pending_associated {return 0,false,blot_error::Error.type_limit;}let pending=pending_associated|(engine.associated_pending.len as u32);engine.associated_pending.push(target);return pending,true,blot_error::Error.none;}
 return importedMethodBinding(engine,target);}
fn importCatalog(self_:Engine&,imported,imported_associated:dictionary<ImportedAssociated,bool>&)->blot_error::Error {
    let producer=imported.catalog();if imported.kind==ImportedCatalog_kind.catalog {
        for index in 1..producer.nominals.len {if producer.nominals[index].private {continue;}let copied,err=self_.copyNominal(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for index in 1..producer.effect_families.len {if producer.effect_families[index].private {continue;}let copied,err=self_.copyEffectFamily(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for index in 0..producer.contracts.len {if producer.contracts[index].private {continue;}let copied,err=self_.copyContract(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for implementation,index in producer.implementations {if implementation.private {continue;}let copied,err=self_.copyImplementation(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for method in producer.associated {let definition=imported.declaration(method.binding);if definition.private {continue;}var target=ExternalTarget{producer.unit,method.binding, ..};if definition.external.present {target=definition.external.value;}
            // Catalogs repeat the members they import; each is recorded once.
            let key=ImportedAssociated{method.identity,method.member,target, ..};if imported_associated.contains(key) {continue;}imported_associated.insert(key,true);
            // A member the catalog's module itself imported keeps its
            // producer's capability facts, never the alias's copy.
            var owned=blot_support::none<ProducerCapability>();if definition.external.present {owned=self_.producerCapability(target);}
            let binding,recorded,err=imported.importMethod(self_,definition,target,owned,method.binding);if err!=blot_error::Error.none {return err;}
            // Forwarded without a copy and no producer to ask: another
            // catalog may still carry the member.
            if !recorded {imported_associated.remove(key);continue;}
            let index=self_.associated.len as u32;self_.associated.push(Associated{method.identity,method.member,method.operator,binding, ..});self_.catalogs.associated_members.insert(AssociatedMember{method.identity,method.member, ..},index);if method.operator!=blot_check_types::Operator.none {self_.catalogs.associated_ops.insert(AssociatedKey{method.identity,method.operator, ..},index);}
        }return blot_error::Error.none;
    }
    if imported.kind==ImportedCatalog_kind.effect_family {let family,err=self_.copyEffectFamily(producer,imported.index);if err!=blot_error::Error.none {return err;}let key=Qualified{imported.namespace_,imported.name, ..};if self_.catalogs.effect_family_names.contains(key) || self_.catalogs.nominal_names.contains(key) {let err=self_.diagnostic(Code.duplicate_name,imported.origin);if err!=blot_error::Error.none {return err;}}else {self_.catalogs.effect_family_names.insert(key,family);}if self_.effect_families[family].callable {let operations=checkedTypeList(self_.types,self_.effect_families[family].operations);if (operations.len as i64)!=1 {return blot_error::Error.type_limit;}self_.catalogs.effect_operation_names.insert(key,self_.types.list(operations)[0]);}return blot_error::Error.none;}
    let key=Qualified{imported.namespace_,imported.name, ..};if imported.kind==ImportedCatalog_kind.contract {let index,err=self_.copyContract(producer,imported.index);if err!=blot_error::Error.none {return err;}if self_.catalogs.contract_names.contains(key) || self_.catalogs.nominal_names.contains(key) {return self_.diagnostic(Code.duplicate_name,imported.origin);}self_.catalogs.contract_names.insert(key,index);return blot_error::Error.none;}
    if imported.kind==ImportedCatalog_kind.implementation {let index,err=self_.copyImplementation(producer,imported.index);if err!=blot_error::Error.none {return err;}if self_.catalogs.implementation_names.contains(key) {return self_.diagnostic(Code.duplicate_name,imported.origin);}self_.catalogs.implementation_names.insert(key,index);return blot_error::Error.none;}
    if imported.kind==ImportedCatalog_kind.nominal {let index,err=self_.copyNominal(producer,imported.index);if err!=blot_error::Error.none {return err;}if self_.catalogs.nominal_names.contains(key) {return self_.diagnostic(Code.duplicate_name,imported.origin);}self_.catalogs.nominal_names.insert(key,index);}
    else {let source=producer.constructors[imported.index];let copied,err=self_.copyNominal(producer,source.nominal);if err!=blot_error::Error.none {return err;}let index:u32={let scalar_lookup_26 .= self_.catalogs.constructor_identities.get(source.identity);assert(scalar_lookup_26!=null);let scalar_value_26:u32=scalar_lookup_26;scalar_value_26};if self_.catalogs.constructor_names.contains(key) {return self_.diagnostic(Code.duplicate_name,imported.origin);}self_.catalogs.constructor_names.insert(key,index);}return blot_error::Error.none;
}
fn prepareOpaqueStorage(self_:Engine&) {var remaining:i64=1000000;for nominal,index in self_.nominals {if !nominal.is_opaque || nominal.identity.unit!=self_.unit {continue;}self_.nominals[index].storage=blot_backend_opaque_storage::infer(borrowedTypeSource(self_.types),self_.nominals,self_.constructors,index as u32,remaining);}}
fn constructorDiagnostic(self_:Engine&,symbol:u32,source:u32)->blot_error::Error {let scalar_lookup_27 .= self_.catalogs.nominal_names.get(self_.catalogKey(symbol));if scalar_lookup_27 && self_.nominals[scalar_lookup_27].is_opaque && self_.nominals[scalar_lookup_27].identity.unit!=self_.unit {let index:u32=scalar_lookup_27;return self_.diagnostic(Code.private_access,source);}return self_.diagnostic(Code.unknown_constructor,source);}
fn constructorType(self_:Engine&,index:u32)->u32,blot_error::Error {return self_.constructorUse(index,false);}
struct VisibilityContext {engine:Engine&}
fn validateVisibility(self_:Engine&)->blot_error::Error {var private=false;for binding in self_.bindings {private=private || binding.private;}for nominal in self_.nominals {private=private || nominal.private;}for family in self_.effect_families {private=private || family.private;}for contract in self_.contracts {private=private || contract.private;}if !private {return blot_error::Error.none;}var context=makeVisibilityContext(self_);return blot_reuse_module_visibility::withScan<VisibilityContext>(borrowedTypeSource(self_.types),self_.nominals,self_.effect_families,self_.effect_templates,context,visibilityBody);}
fn visibilityBody(context:VisibilityContext&,scan:blot_reuse_module_visibility::Scan&)->blot_error::Error {
    let self_ .= context.engine;for contract in self_.contracts {if contract.private {scan.blocked.insert(contract.identity,true);}}
    for binding in self_.bindings {if binding.kind!=blot_reuse_principal_interface::Kind.global || binding.private {continue;}var allowed,err=scan.allowed(binding.scheme.root);if err!=blot_error::Error.none {return err;}let dtag=self_.tree.node(binding.declaration).tag;if dtag==blot_parse_ast::tag_value_decl {let ast_walk_11_source=self_.tree.value_decl(binding.declaration).where;let ast_walk_11_count=self_.tree.list(ast_walk_11_source).len;for ast_walk_11_index in 0..ast_walk_11_count {let predicate=self_.tree.list(ast_walk_11_source)[ast_walk_11_index];let name=self_.tree.node(predicate).a;let scalar_lookup_28 .= self_.catalogs.contract_names.get(self_.catalogKey(name));if scalar_lookup_28 && self_.contracts[scalar_lookup_28].private {let index:u32=scalar_lookup_28;allowed=false;}}}else if dtag!=blot_parse_ast::tag_entry_kernel_decl && dtag!=blot_parse_ast::tag_entry_process_decl {continue;}
        for requirement in self_.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start+binding.scheme.obligations.len] {if requirement.kind==blot_check_types::ObligationKind.callee_use && requirement.identity.decl<self_.bindings.len && self_.bindings[requirement.identity.decl].private {allowed=false;}for root in [requirement.ty,requirement.result,requirement.other,requirement.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}if !allowed {let err=self_.diagnostic(Code.private_identity_escape,binding.declaration);if err!=blot_error::Error.none {return err;}}
    }
    for nominal in self_.nominals {if nominal.identity.unit!=self_.unit || nominal.private {continue;}var allowed,err=scan.allowed(nominal.alias);if err!=blot_error::Error.none {return err;}let type_span_3=checkedTypeList(self_.types,nominal.parameters);for type_index_3 in 0..(type_span_3.len as i64) {let parameter=self_.types.list(type_span_3)[type_index_3];let valid,err=scan.allowed(parameter);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}if nominal.is_opaque {if !allowed {let err=self_.diagnostic(Code.private_identity_escape,nominal.declaration);if err!=blot_error::Error.none {return err;}}continue;}let type_span_4=checkedTypeList(self_.types,nominal.constructors);for type_index_4 in 0..(type_span_4.len as i64) {let index=self_.types.list(type_span_4)[type_index_4];let valid,err=scan.allowed(self_.constructors[index].payload);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}if !allowed {let err=self_.diagnostic(Code.private_identity_escape,nominal.declaration);if err!=blot_error::Error.none {return err;}}}
    for contract in self_.contracts {if contract.identity.unit!=self_.unit || contract.private {continue;}var allowed=true;for requirement in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {for root in [requirement.ty,requirement.result,requirement.other,requirement.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}for member in self_.contract_members[contract.members.start..contract.members.start+contract.members.len] {let valid,err=scan.allowed(member.root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}let body=self_.tree.node(self_.tree.node(contract.declaration).b);let ast_walk_12_source=blot_parse_ast::List{body.a,body.b, ..};let ast_walk_12_count=self_.tree.list(ast_walk_12_source).len;for ast_walk_12_index in 0..ast_walk_12_count {let predicate=self_.tree.list(ast_walk_12_source)[ast_walk_12_index];let scalar_lookup_29 .= self_.catalogs.contract_names.get(self_.catalogKey(self_.tree.node(predicate).a));if scalar_lookup_29 && self_.contracts[scalar_lookup_29].private {let index:u32=scalar_lookup_29;allowed=false;}}if !allowed {let err=self_.diagnostic(Code.private_identity_escape,contract.declaration);if err!=blot_error::Error.none {return err;}}}
    for implementation in self_.implementations {if implementation.identity.unit!=self_.unit || implementation.private {continue;}var allowed=!scan.blocked.contains(implementation.contract);let type_span_5=checkedTypeList(self_.types,implementation.head);for type_index_5 in 0..(type_span_5.len as i64) {let root=self_.types.list(type_span_5)[type_index_5];let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}for member in self_.implementation_members[implementation.members.start..implementation.members.start+implementation.members.len] {let valid,err=scan.allowed(member.root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}for predicate in self_.implementation_predicates[implementation.predicates.start..implementation.predicates.start+implementation.predicates.len] {if scan.blocked.contains(predicate.identity) {allowed=false;}for root in [predicate.ty,predicate.other,predicate.result,predicate.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}if !allowed {let err=self_.diagnostic(Code.private_identity_escape,implementation.declaration);if err!=blot_error::Error.none {return err;}}}
    for family in self_.effect_families {if family.identity.unit!=self_.unit || family.private {continue;}var allowed=true;let type_span_6=checkedTypeList(self_.types,family.operations);for type_index_6 in 0..(type_span_6.len as i64) {let index=self_.types.list(type_span_6)[type_index_6];let operation=self_.effect_templates[index];let parameter,err=scan.allowed(operation.parameter);if err!=blot_error::Error.none {return err;}if !parameter {allowed=false;}else {let result,err=scan.allowed(operation.result);if err!=blot_error::Error.none {return err;}if !result {allowed=false;}}}if !allowed {var decl_node:u32=0;for rid in self_.tree.roots.items {let rn=self_.tree.node(rid);if (rn.tag==blot_parse_ast::tag_effect_decl || rn.tag==blot_parse_ast::tag_effect_type_decl) && rn.a==family.name {decl_node=rid;break;}}let err=self_.diagnostic(Code.private_identity_escape,decl_node);if err!=blot_error::Error.none {return err;}}}
    return blot_error::Error.none;
}
fn copyPredicate(copier:blot_check_check_scheme_import::Copier&,old:blot_check_types::Obligation)->blot_check_types::Obligation,blot_error::Error {var value=old;let ty,err=copier.copy(old.ty,0);if err!=blot_error::Error.none {return value,err;}value.ty=ty;let other,err=copier.copy(old.other,0);if err!=blot_error::Error.none {return value,err;}value.other=other;let result,err=copier.copy(old.result,0);if err!=blot_error::Error.none {return value,err;}value.result=result;let signature,err=copier.copy(old.signature,0);if err!=blot_error::Error.none {return value,err;}value.signature=signature;value.source=0;return value,blot_error::Error.none;}
fn copyContract(self_:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.contracts[source_index];self_.has_associated_types=self_.has_associated_types || source.members.len!=0;let scalar_lookup_30 .= self_.catalogs.contract_identities.get(source.identity);if scalar_lookup_30 {let known:u32=scalar_lookup_30;return known,blot_error::Error.none;}var copier=blot_check_check_scheme_import::init(producer.types,self_.types,self_.import_tables);copier.associated=source.members.len!=0;let result,err=copyContractBody(self_,copier,producer,source);copier.reset();return result,err;}
fn copyContractBody(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Contract)->u32,blot_error::Error {
    var variables:u32[>..<]=[];for old in producer.types.list(source.variables) {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.push(fresh);}let rows,err=copier.quantifiedRows(source.row_variables);if err!=blot_error::Error.none {return 0,err;}var parameters:u32[>..<]=[];for old in producer.types.list(source.parameters) {let copied,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.push(copied);}let start=self_.contract_predicates.len as u32;for old in producer.contract_predicates[source.predicates.start..source.predicates.start+source.predicates.len] {let predicate,err=copyPredicate(copier,old);if err!=blot_error::Error.none {return 0,err;}self_.contract_predicates.push(predicate);}
    var row_parameters:u32[>..<]=[];for old in producer.types.list(source.row_parameters) {let copied,err=copier.copyRow(old,0);if err!=blot_error::Error.none {return 0,err;}row_parameters.push(copied);}let member_start=self_.contract_members.len as u32;for old in producer.contract_members[source.members.start..source.members.start+source.members.len] {var member=old;let root,err=copier.copy(old.root,0);if err!=blot_error::Error.none {return 0,err;}member.root=root;self_.contract_members.push(member);}
    let index=self_.contracts.len as u32;let patterns,err=self_.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}let names,err=self_.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_names,err=self_.types.saveList(producer.types.list(source.row_parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_list,err=self_.types.saveList(row_parameters);if err!=blot_error::Error.none {return 0,err;}
    self_.contracts.push(Contract{ private:source.private, identity:source.identity, name:source.name, parameters:parameter_list, variables:quantified, patterns:patterns, parameter_names:names, row_variables:rows, row_parameter_names:row_names, row_parameters:row_list, predicates:blot_check_types::List{start,source.predicates.len, ..}, members:blot_check_types::List{member_start,source.members.len, ..}, requires_implementation:source.requires_implementation, .. });self_.catalogs.contract_identities.insert(source.identity,index);return index,blot_error::Error.none;
}
fn copyImplementation(self_:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.implementations[source_index];for prior,index in self_.implementations {if prior.identity==source.identity {return index as u32,blot_error::Error.none;}}if self_.implementations.len>=4096 {return 0,blot_error::Error.type_limit;}for contract,index in producer.contracts {if contract.identity==source.contract {let copied,err=self_.copyContract(producer,index as u32);if err!=blot_error::Error.none {return 0,err;}break;}}var copier=blot_check_check_scheme_import::init(producer.types,self_.types,self_.import_tables);copier.associated=true;let result,err=copyImplementationBody(self_,copier,producer,source);copier.reset();return result,err;}
fn copyImplementationBody(self_:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Implementation)->u32,blot_error::Error {
    var variables:u32[>..<]=[];for old in producer.types.list(source.variables) {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.push(fresh);}let rows,err=copier.quantifiedRows(source.row_variables);if err!=blot_error::Error.none {return 0,err;}var head:u32[>..<]=[];for root in producer.types.list(source.head) {let copied,err=copier.copy(root,0);if err!=blot_error::Error.none {return 0,err;}head.push(copied);}var row_parameters:u32[>..<]=[];for row in producer.types.list(source.row_parameters) {let copied,err=copier.copyRow(row,0);if err!=blot_error::Error.none {return 0,err;}row_parameters.push(copied);}let predicate_start=self_.implementation_predicates.len as u32;
    for old in producer.implementation_predicates[source.predicates.start..source.predicates.start+source.predicates.len] {let predicate,err=copyPredicate(copier,old);if err!=blot_error::Error.none {return 0,err;}self_.implementation_predicates.push(predicate);}let member_start=self_.implementation_members.len as u32;for old in producer.implementation_members[source.members.start..source.members.start+source.members.len] {var value=old;let root,err=copier.copy(old.root,0);if err!=blot_error::Error.none {return 0,err;}value.root=root;self_.implementation_members.push(value);}
    let index=self_.implementations.len as u32;let head_list,err=self_.types.saveList(head);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let names,err=self_.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_list,err=self_.types.saveList(row_parameters);if err!=blot_error::Error.none {return 0,err;}let row_names,err=self_.types.saveList(producer.types.list(source.row_parameter_names));if err!=blot_error::Error.none {return 0,err;}
    self_.implementations.push(Implementation{ origin_span:source.origin_span, private:source.private, identity:source.identity, name:source.name, contract:source.contract, head:head_list, variables:quantified, parameter_names:names, row_variables:rows, row_parameter_names:row_names, row_parameters:row_list, predicates:blot_check_types::List{predicate_start,source.predicates.len, ..}, members:blot_check_types::List{member_start,source.members.len, ..}, .. });return index,blot_error::Error.none;
}
fn implementationScope(self_:Engine&,declaration:Implementation)->blot_error::Error {let variables=checkedTypeList(self_.types,declaration.variables);let type_span_7=checkedTypeList(self_.types,declaration.parameter_names);for index in 0..(type_span_7.len as i64) {let name=self_.types.list(type_span_7)[index];let growth=self_.type_env.append(Engine_type_env{name,self_.types.list(variables)[index], ..});if growth!=blot_error::Error.none {return growth;}}let rows=checkedTypeList(self_.types,declaration.row_parameters);let type_span_8=checkedTypeList(self_.types,declaration.row_parameter_names);for index in 0..(type_span_8.len as i64) {let name=self_.types.list(type_span_8)[index];let growth=self_.row_env.append(Engine_row_env{name,self_.types.list(rows)[index], ..});if growth!=blot_error::Error.none {return growth;}}return blot_error::Error.none;}
fn implementationHeaders(self_:Engine&)->blot_error::Error {let saved=self_.defer_associated;self_.defer_associated=true;let err=implementationHeadersBody(self_);self_.defer_associated=saved;return err;}
fn implementationHeadersBody(self_:Engine&)->blot_error::Error {
    let ast_walk_13_count=self_.tree.roots.items.len;for ast_walk_13_index in 0..ast_walk_13_count {let id=self_.tree.roots.items[ast_walk_13_index];if self_.tree.node(id).tag==blot_parse_ast::tag_value_decl {let err=traitConstImplementationHeader(self_,id);if err!=blot_error::Error.none {return err;}}}
    self_.type_env.clear();self_.row_env.clear();return blot_error::Error.none;
}
fn traitConstImplementationHeader(self_:Engine&,id:u32)->blot_error::Error {
    let decl=self_.tree.value_decl(id);
    if decl.runtime || decl.annotation==0 || !lastDot(self_.pool.get(decl.name)).present {return blot_error::Error.none;}
    var body_id=decl.body;
    while body_id!=0 && self_.tree.node(body_id).tag==blot_parse_ast::tag_group {body_id=self_.tree.node(body_id).a;}
    if body_id==0 || self_.tree.node(body_id).tag!=blot_parse_ast::tag_record || self_.tree.node(body_id).a!=0 {return blot_error::Error.none;}
    var head_id=decl.annotation;
    var rev_args=IdBuffer{..};
    loop {
        let n=self_.tree.node(head_id);
        if n.tag==blot_parse_ast::tag_group {head_id=n.a;continue;}
        if n.tag!=blot_parse_ast::tag_type_apply {break;}
        let err=rev_args.append(n.b);
        if err!=blot_error::Error.none {rev_args.deinit(equation_type_ids);return err;}
        head_id=n.a;
    }
    if self_.tree.node(head_id).tag!=blot_parse_ast::tag_type_name {rev_args.deinit(equation_type_ids);return blot_error::Error.none;}
    var contract_index:u32=0;var has_contract=false;
    {let c_lookup .= self_.catalogs.contract_names.get(self_.catalogKey(self_.tree.node(head_id).a));if c_lookup {contract_index=c_lookup;has_contract=true;}}
    if !has_contract {rev_args.deinit(equation_type_ids);return blot_error::Error.none;}
    let contract=self_.contracts[contract_index];
    if !contract.requires_implementation {rev_args.deinit(equation_type_ids);return blot_error::Error.none;}
    reverseIds(rev_args.items);
    var output_record:u32=0;
    var dispatch_count=rev_args.items.len;
    if dispatch_count==contract.parameters.len+1 && self_.tree.node(rev_args.items[dispatch_count-1]).tag==blot_parse_ast::tag_type_record {
        output_record=rev_args.items[dispatch_count-1];
        dispatch_count-=1;
    }
    if dispatch_count!=contract.parameters.len {rev_args.deinit(equation_type_ids);return blot_error::Error.none;}
    let allowed,aerr=self_.associatedStep(id);
    if aerr!=blot_error::Error.none || !allowed {rev_args.deinit(equation_type_ids);return aerr;}
    if self_.implementations.len>=4096 {rev_args.deinit(equation_type_ids);return self_.diagnostic(Code.associated_limit,id);}
    let key=Qualified{0,decl.name, ..};
    var duplicate=self_.catalogs.implementation_names.contains(key);
    for prior in self_.implementations {if prior.identity.unit==self_.unit && prior.name==decl.name {duplicate=true;}}
    if duplicate {rev_args.deinit(equation_type_ids);return self_.diagnostic(Code.duplicate_name,id);}
    self_.type_env.clear();self_.row_env.clear();
    let saved_closed=self_.closed_type_variables;let saved_implicit=self_.implicit_row_parameters;let saved_defer=self_.defer_associated;
    self_.closed_type_variables=false;self_.implicit_row_parameters=false;self_.defer_associated=true;
    for ordinal in 0..dispatch_count {
        let cerr=self_.collectAnnotationNames(rev_args.items[ordinal],0);
        if cerr!=blot_error::Error.none {self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_implicit;self_.defer_associated=saved_defer;rev_args.deinit(equation_type_ids);return cerr;}
    }
    var variables:u32[>..<]=[];var names:u32[>..<]=[];
    for entry in self_.type_env.items {variables.push(entry.ty);names.push(entry.name);}
    self_.closed_type_variables=true;
    let err=traitConstImplementationOwned(self_,id,decl,body_id,output_record,contract,rev_args.items[..dispatch_count],variables,names);
    self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_implicit;self_.defer_associated=saved_defer;
    rev_args.deinit(equation_type_ids);
    return err;
}
fn traitConstImplementationOwned(self_:Engine&,id:u32,decl:blot_parse_ast::ValueDecl,body_id:u32,output_record:u32,contract:Contract,dispatch_args:const u32[:],variables:u32[>..<]&,names:const u32[:])->blot_error::Error {
    var head:u32[>..<]=[];var contract_old:u32[>..<]=[];contract_old.append(self_.types.list(contract.variables));var contract_fresh:u32[>..<]=[];for ignored in 0..contract_old.len {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}contract_fresh.push(fresh);}var old_rows:u32[>..<]=[];old_rows.append(self_.types.list(contract.row_variables));var new_rows:u32[>..<]=[];for ignored in 0..old_rows.len {let fresh,err=self_.types.freshEffects();if err!=blot_error::Error.none {return err;}new_rows.push(fresh);}
    for ordinal in 0..dispatch_args.len {
        let argument=dispatch_args[ordinal];
        let actual,err=self_.parameterArgument(self_.parameter_patterns.list(contract.patterns)[ordinal],argument,true,0);if err!=blot_error::Error.none {return err;}
        let projection,err=self_.types.containsProjection(actual);if err!=blot_error::Error.none {return err;}
        if projection {let err=self_.diagnostic(Code.invalid_constraint,argument);if err!=blot_error::Error.none {return err;}}
        let expected,err=self_.types.substituteWithRows(self_.types.list(contract.parameters)[ordinal],contract_old,contract_fresh,old_rows,new_rows);if err!=blot_error::Error.none {return err;}
        let err=self_.constrainRaw(expected,actual,argument);if err!=blot_error::Error.none {return err;}
        head.push(actual);
    }
    let product,err=self_.types.product(head);if err!=blot_error::Error.none {return err;}
    let free,err=self_.types.freeVariables(product);if err!=blot_error::Error.none {return err;}
    let rows,err=self_.types.freeRowVariables(product);if err!=blot_error::Error.none {return err;}
    for &variable in variables {variable=self_.types.head(variable,0);if !inList(free,variable) {let err=self_.diagnostic(Code.undetermined_implementation,id);if err!=blot_error::Error.none {return err;}}}
    let member_start=self_.implementation_members.len as u32;let index=self_.implementations.len as u32;
    if output_record!=0 {
        let ocount=self_.tree.children(output_record).len;
        for oi in 0..ocount {
            let child=self_.tree.children(output_record)[oi];let item=self_.tree.node(child);
            let member_index=self_.memberIndex(contract,item.a);
            if !member_index.present {let err=self_.diagnostic(Code.missing_type_member,child);if err!=blot_error::Error.none {return err;}continue;}
            let required=self_.contract_members[member_index.value];
            if required.kind!=blot_reuse_principal_interface::ContractMemberKind.abstract_type {let err=self_.diagnostic(Code.type_mismatch,child);if err!=blot_error::Error.none {return err;}continue;}
            var repeated=false;for prior in self_.implementation_members[member_start..] {if prior.name==item.a {repeated=true;}}
            if repeated {let err=self_.diagnostic(Code.duplicate_name,child);if err!=blot_error::Error.none {return err;}continue;}
            let owned=self_.implementation_members.len as u32;
            self_.implementation_members.push(ImplementationMember{name:item.a,kind:blot_reuse_principal_interface::ImplementationMemberKind.type_, ..});
            self_.implementation_member_sources.insert(owned,child);
        }
    }
    let fcount=self_.tree.children(body_id).len;
    for fi in 0..fcount {
        let child=self_.tree.children(body_id)[fi];let item=self_.tree.node(child);
        let member_index=self_.memberIndex(contract,item.a);
        if !member_index.present {let err=self_.diagnostic(Code.missing_member,child);if err!=blot_error::Error.none {return err;}continue;}
        let required=self_.contract_members[member_index.value];
        if required.kind!=blot_reuse_principal_interface::ContractMemberKind.value {let err=self_.diagnostic(Code.type_mismatch,child);if err!=blot_error::Error.none {return err;}continue;}
        var repeated=false;for prior in self_.implementation_members[member_start..] {if prior.name==item.a {repeated=true;}}
        if repeated {let err=self_.diagnostic(Code.duplicate_name,child);if err!=blot_error::Error.none {return err;}continue;}
        let owned=self_.implementation_members.len as u32;
        self_.name_bytes.clear();self_.name_bytes.append(self_.pool.get(decl.name));self_.name_bytes.push('.' as u8);self_.name_bytes.append(self_.pool.get(item.a));
        let mname,err=self_.pool.intern(self_.name_bytes);if err!=blot_error::Error.none {if err==blot_error::Error.symbol_limit {return blot_error::Error.type_limit;}return err;}
        let ty,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}
        let is_named=item.b!=0 && self_.tree.node(item.b).tag==blot_parse_ast::tag_lambda;
        let binding,err=self_.addBinding(Binding{private:true,name:mname,declaration:child,owner:child,kind:blot_reuse_principal_interface::Kind.global,named_function:is_named,ty:ty, ..});if err!=blot_error::Error.none {return err;}
        self_.resolved[child]=binding;self_.implementation_bindings.insert(binding,index);self_.global_states.insert(binding,Global{..});
        self_.implementation_members.push(ImplementationMember{name:item.a,kind:blot_reuse_principal_interface::ImplementationMemberKind.value,target:ExternalTarget{self_.unit,binding, ..}, ..});
        self_.implementation_member_sources.insert(owned,child);
    }
    let members=blot_check_types::List{member_start,(self_.implementation_members.len-member_start) as u32, ..};
    for required in self_.contract_members[contract.members.start..contract.members.start+contract.members.len] {
        if required.kind==blot_reuse_principal_interface::ContractMemberKind.defined_type {continue;}
        var present=false;for member in self_.implementation_members[members.start..members.start+members.len] {if member.name==required.name {present=true;break;}}
        if !present {var code=Code.missing_type_member;if required.kind==blot_reuse_principal_interface::ContractMemberKind.value {code=Code.missing_member;}let err=self_.diagnostic(code,id);if err!=blot_error::Error.none {return err;}}
    }
    let head_list,err=self_.types.saveList(head);if err!=blot_error::Error.none {return err;}
    let variable_list,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return err;}
    let name_list,err=self_.types.saveList(names);if err!=blot_error::Error.none {return err;}
    let row_list,err=self_.types.saveList(rows);if err!=blot_error::Error.none {return err;}
    self_.implementations.push(Implementation{origin_span:blot_support::some(self_.tree.span(id)),declaration:id,private:blot_parse_ast::declaration_traits(self_.tree,id).private,identity:Identity{self_.unit,blot_check_types::opaque_name_bit|decl.name, ..},name:decl.name,contract:contract.identity,head:head_list,variables:variable_list,parameter_names:name_list,row_variables:row_list,members:members, ..});
    self_.catalogs.implementation_names.insert(Qualified{0,decl.name, ..},index);
    var owner=contract.identity.unit==self_.unit;
    if !owner && contract_old.len!=0 {let resolved,err=self_.types.resolve(contract_fresh[0],0);if err!=blot_error::Error.none {return err;}let anchor=self_.types.node(resolved);owner=anchor.tag==blot_check_types::Tag.nominal && anchor.a==self_.unit;}
    if !owner {let err=self_.diagnostic(Code.orphan_implementation,id);if err!=blot_error::Error.none {return err;}}
    var predicates:blot_check_types::Obligation[>..<]=[];
    let wcount=self_.tree.list(decl.where).len;
    for wi in 0..wcount {let predicate_source=self_.tree.list(decl.where)[wi];let err=self_.lowerPredicates(predicate_source,decl.where_node,predicates);if err!=blot_error::Error.none {return err;}}
    for old in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {let requirement,err=substitutePredicate(self_,old,contract_old,contract_fresh,old_rows,new_rows);if err!=blot_error::Error.none {return err;}var value=requirement;value.source=id;predicates.push(value);}
    let predicate_start=self_.implementation_predicates.len as u32;self_.implementation_predicates.append(predicates);self_.implementations[index].predicates=blot_check_types::List{predicate_start,predicates.len as u32, ..};
    return blot_error::Error.none;
}
fn substitutePredicate(self_:Engine&,old:blot_check_types::Obligation,variables:const u32[:],fresh:const u32[:],rows:const u32[:],new_rows:const u32[:])->blot_check_types::Obligation,blot_error::Error {var result=old;let ty,err=self_.types.substituteWithRows(old.ty,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.ty=ty;let other,err=self_.types.substituteWithRows(old.other,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.other=other;let value,err=self_.types.substituteWithRows(old.result,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.result=value;let signature,err=self_.types.substituteWithRows(old.signature,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.signature=signature;return result,blot_error::Error.none;}

type TypeEnvironment=blot_support_pooled_buffer::Buffer<Engine_type_env>;
type RowEnvironment=blot_support_pooled_buffer::Buffer<Engine_row_env>;
reusable[] var type_environment_values:Engine_type_env[>..];
reusable[] var row_environment_values:Engine_row_env[>..];
fn canonicalTypeEnvironment(value:TypeEnvironment)->TypeEnvironment {if value.storage.len==0 {return TypeEnvironment{..};}let storage=type_environment_values.realloc_slice(value.storage,value.storage.len);return TypeEnvironment{storage:storage,items:storage[..value.items.len]};}
fn canonicalRowEnvironment(value:RowEnvironment)->RowEnvironment {if value.storage.len==0 {return RowEnvironment{..};}let storage=row_environment_values.realloc_slice(value.storage,value.storage.len);return RowEnvironment{storage:storage,items:storage[..value.items.len]};}
fn blot_support_pooled_buffer::append(self_:blot_check_check::TypeEnvironment&,value:blot_check_check::Engine_type_env)->blot_error::Error {return blot_support_pooled_buffer::push(self_,value,blot_check_check::type_environment_values);}
fn blot_support_pooled_buffer::append(self_:blot_check_check::RowEnvironment&,value:blot_check_check::Engine_row_env)->blot_error::Error {return blot_support_pooled_buffer::push(self_,value,blot_check_check::row_environment_values);}
fn blot_support_pooled_buffer::deinit(self_:blot_check_check::TypeEnvironment&) {blot_support_pooled_buffer::deinit(self_,blot_check_check::type_environment_values);}
fn blot_support_pooled_buffer::deinit(self_:blot_check_check::RowEnvironment&) {blot_support_pooled_buffer::deinit(self_,blot_check_check::row_environment_values);}
struct OrderEntry {index:u32,path:blot_support::Option<const u8[:]>   = blot_support::none<const u8[:]>()}
struct ImplementationOrderContext {engine:Engine&}
fn byteOrder(left:const u8[:],right:const u8[:])->i32 {for index in 0..min(left.len,right.len) {if left[index]<right[index] {return -1;}if left[index]>right[index] {return 1;}}if left.len<right.len {return -1;}if left.len>right.len {return 1;}return 0;}
fn lessThan(self_:ImplementationOrderContext,a:i64,b:i64)->bool {let left=self_.engine.order_entries[a];let right=self_.engine.order_entries[b];let err=self_.engine.types.chargeProjection();if err!=blot_error::Error.none {return left.index<right.index;}let first=self_.engine.implementations[left.index];let second=self_.engine.implementations[right.index];if left.path.present && right.path.present {let order=byteOrder(left.path.value,right.path.value);if order!=0 {return order<0;}}if first.identity.unit!=second.identity.unit {return first.identity.unit<second.identity.unit;}if first.origin_span.present && second.origin_span.present {if first.origin_span.value.start!=second.origin_span.value.start {return first.origin_span.value.start<second.origin_span.value.start;}}return byteOrder(self_.engine.pool.get(first.name),self_.engine.pool.get(second.name))<0;}
fn swap(self_:ImplementationOrderContext,a:i64,b:i64) {let value=self_.engine.order_entries[a];self_.engine.order_entries[a]=self_.engine.order_entries[b];self_.engine.order_entries[b]=value;}
fn implementationOrder(self_:Engine&)->blot_error::Error {self_.order_entries.clear();for index in 0..self_.implementations.len {self_.order_entries.push(OrderEntry{index:index as u32, ..});}for &entry in self_.order_entries {let allowed,err=self_.associatedStep(0);if err!=blot_error::Error.none || !allowed {return err;}let path,err=self_.purity_origins.name(self_.implementations[entry.index].identity.unit,self_.unit);if err==blot_error::Error.out_of_memory {return err;}if err==blot_error::Error.none {entry.path=blot_support::some<const u8[:]>(path);}}
    let old_projection_exhausted:bool=self_.types.projection_exhausted;
    self_.types.projection_exhausted=false;
    let context=makeImplementationOrderContext(self_);
    blot_check_source_sort::pdqContext(0,self_.order_entries.len,context);
    let sort_exhausted:bool=self_.types.projection_exhausted;
    self_.types.projection_exhausted=old_projection_exhausted || sort_exhausted;
    if sort_exhausted {return self_.diagnostic(Code.associated_limit,0);}for entry in self_.order_entries {self_.implementation_order.push(entry.index);}return blot_error::Error.none;
}
fn implementationCoherence(self_:Engine&)->blot_error::Error {let err=self_.implementationOrder();if err!=blot_error::Error.none {return err;}for later_index,ordinal in self_.implementation_order {let later=self_.implementations[later_index];for earlier_index in self_.implementation_order[..ordinal] {let earlier=self_.implementations[earlier_index];if later.private && earlier.private && later.identity.unit!=earlier.identity.unit {continue;}let overlap,err=blot_check_trait_patterns::overlap(self_.types,earlier,later);if err!=blot_error::Error.none {return err;}if !overlap {continue;}var origin=later.declaration;if later.identity.unit!=self_.unit {origin=0;}let err=self_.diagnostic(Code.overlapping_implementation,origin);if err!=blot_error::Error.none {return err;}if later.identity.unit!=self_.unit {let issue .= self_.diagnostics[self_.diagnostics.len-1];issue.origin_unit=later.identity.unit;if self_.purity_origins.has_source_available && self_.purity_origins.sourceAvailable(later.identity.unit) && later.origin_span.present {issue.span=later.origin_span.value;}}return blot_error::Error.none;}}return blot_error::Error.none;}
fn implementationIndexForMember(self_:const Engine&,member:u32)->blot_support::Option<u32> {for declaration,index in self_.implementations {if member>=declaration.members.start && member-declaration.members.start<declaration.members.len {return blot_support::some(index as u32);}}return blot_support::none<u32>();}
fn implementationMemberIndex(self_:const Engine&,declaration:Implementation,name:u32)->blot_support::Option<u32> {for ordinal in declaration.members.start..declaration.members.start+declaration.members.len {if self_.implementation_members[ordinal].name==name {return blot_support::some(ordinal as u32);}}return blot_support::none<u32>();}
fn activeImplementation(self_:const Engine&)->blot_support::Option<u32> {if self_.checking_implementation.present {return self_.checking_implementation;}let scalar_lookup_32 .= self_.implementation_bindings.get(self_.current);if scalar_lookup_32 {let value:u32=scalar_lookup_32;return blot_support::some(value);}return blot_support::none<u32>();}
recursive fn implementationEquation(self_:Engine&,contract:Identity,name:u32,arguments:const u32[:])->blot_support::Option<u32>,blot_error::Error {let index=self_.activeImplementation();if !index.present {return blot_support::none<u32>(),blot_error::Error.none;}let declaration=self_.implementations[index.value];if contract!=declaration.contract || arguments.len!=declaration.head.len {return blot_support::none<u32>(),blot_error::Error.none;}let member=self_.implementationMemberIndex(declaration,name);if !member.present || self_.implementation_members[member.value].kind!=blot_reuse_principal_interface::ImplementationMemberKind.type_ {return blot_support::none<u32>(),blot_error::Error.none;}var same=true;for ordinal in 0..arguments.len {let equal,err=self_.types.equalSymbolic(arguments[ordinal],self_.types.list(declaration.head)[ordinal]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if !equal {same=false;}}
    if !same {let state .= self_.implementation_member_states.get(member.value);if state && state==Engine_implementation_member_states_state.visiting {let rigid,err=blot_check_trait_patterns::matchesRigid(self_.types,declaration,arguments);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if rigid {let source:u32={let scalar_lookup_33 .= self_.implementation_member_sources.get(member.value);assert(scalar_lookup_33!=null);let scalar_value_33:u32=scalar_lookup_33;scalar_value_33};let err=self_.diagnostic(Code.recursive_associated_type,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let fresh,err=self_.types.fresh();return blot_support::some(fresh),err;}}return blot_support::none<u32>(),blot_error::Error.none;}
    let root,err=self_.resolveImplementationMember(member.value);return blot_support::some(root),err;
}
recursive fn resolveImplementationMember(self_:Engine&,ordinal:u32)->u32,blot_error::Error {
    let member=self_.implementation_members[ordinal];if member.root!=0 {return member.root,blot_error::Error.none;}let index=self_.implementationIndexForMember(ordinal);assert(index.present);let declaration=self_.implementations[index.value];let source_ref:u32={let scalar_lookup_34 .= self_.implementation_member_sources.get(ordinal);if !scalar_lookup_34 {return 0,blot_error::Error.none;}let scalar_value_34:u32=scalar_lookup_34;scalar_value_34};let source:u32=source_ref;let state .= self_.implementation_member_states.get(ordinal);if state {if state==Engine_implementation_member_states_state.visiting {let err=self_.diagnostic(Code.recursive_associated_type,source);if err!=blot_error::Error.none {return 0,err;}}return self_.types.fresh();}
    self_.implementation_member_states.insert(ordinal,Engine_implementation_member_states_state.visiting);let saved_types=self_.type_env;let saved_rows=self_.row_env;let saved_closed=self_.closed_type_variables;let saved_implicit=self_.implicit_row_parameters;let saved_defer=self_.defer_associated;let saved_implementation=self_.checking_implementation;
    self_.type_env=TypeEnvironment{..};self_.row_env=RowEnvironment{..};self_.closed_type_variables=true;self_.implicit_row_parameters=false;self_.defer_associated=false;self_.checking_implementation=blot_support::some(index.value);
    let root,err=resolveImplementationMemberBody(self_,ordinal,member,declaration,source);self_.type_env.deinit();self_.row_env.deinit();self_.type_env=canonicalTypeEnvironment(saved_types);self_.row_env=canonicalRowEnvironment(saved_rows);self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_implicit;self_.defer_associated=saved_defer;self_.checking_implementation=saved_implementation;return root,err;
}
recursive fn resolveImplementationMemberBody(self_:Engine&,ordinal:u32,member:ImplementationMember,declaration:Implementation,source:u32)->u32,blot_error::Error {
    let err=self_.implementationScope(declaration);if err!=blot_error::Error.none {return 0,err;}var root:u32=0;if member.kind==blot_reuse_principal_interface::ImplementationMemberKind.type_ {let value,err=self_.annotation(self_.tree.node(source).b);if err!=blot_error::Error.none {return 0,err;}root=value;}
    else {let index:u32={let scalar_lookup_35 .= self_.catalogs.contract_identities.get(declaration.contract);assert(scalar_lookup_35!=null);let scalar_value_35:u32=scalar_lookup_35;scalar_value_35};let contract=self_.contracts[index];let member_index=self_.memberIndex(contract,member.name);assert(member_index.present);let descriptor=self_.contract_members[member_index.value];let value,err=resolveImplementationValue(self_,member,declaration,contract,descriptor,source);if err!=blot_error::Error.none {return 0,err;}root=value;}
    self_.implementation_members[ordinal].root=root;self_.implementation_member_states.insert(ordinal,Engine_implementation_member_states_state.ready);return root,blot_error::Error.none;
}
recursive fn resolveImplementationValue(self_:Engine&,member:ImplementationMember,declaration:Implementation,contract:Contract,descriptor:ContractMember,source:u32)->u32,blot_error::Error {
    let old=equation_type_ids.alloc_slice(contract.variables.len);let type_span_9=checkedTypeList(self_.types,contract.variables);for index in 0..(type_span_9.len as i64) {let value=self_.types.list(type_span_9)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let old_rows=equation_type_ids.alloc_slice(contract.row_variables.len);let new_rows=equation_type_ids.alloc_slice(old_rows.len);
    let root,err=resolveImplementationValueBody(self_,member,declaration,contract,descriptor,source,old,fresh,old_rows,new_rows);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return root,err;
}
recursive fn resolveImplementationValueBody(self_:Engine&,member:ImplementationMember,declaration:Implementation,contract:Contract,descriptor:ContractMember,source:u32,old:const u32[:],fresh:u32[:],old_rows:u32[:],new_rows:u32[:])->u32,blot_error::Error {
    for &variable in fresh {let value,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=value;}let type_span_10=checkedTypeList(self_.types,contract.row_variables);for index in 0..(type_span_10.len as i64) {let value=self_.types.list(type_span_10)[index];old_rows[index]=value;}for &row in new_rows {let value,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}row=value;}
    for parameter in 0..declaration.head.len {let before,err=self_.types.substituteWithRows(self_.types.list(contract.parameters)[parameter],old,fresh,old_rows,new_rows);if err!=blot_error::Error.none {return 0,err;}let err=self_.types.unify(before,self_.types.list(declaration.head)[parameter]);if err!=blot_error::Error.none {return 0,err;}}
    let selected,err=self_.types.substituteWithRows(descriptor.root,old,fresh,old_rows,new_rows);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.normalizeAssociated(selected,source,false);if err!=blot_error::Error.none {return 0,err;}if self_.tree.node(source).tag==blot_parse_ast::tag_value_decl {let annotation=self_.tree.value_decl(source).annotation;if annotation!=0 {let required,err=self_.annotation(annotation);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(root,required,annotation);if err!=blot_error::Error.none {return 0,err;}}}self_.bindings[member.target.binding].ty=root;return root,blot_error::Error.none;
}
fn provisionalEquation(self_:Engine&,contract:Identity,name:u32,arguments:const u32[:])->blot_support::Option<u32>,blot_error::Error {
    var ordinal=self_.provisional_equations.len;while ordinal!=0 {ordinal-=1;let frame=self_.provisional_equations[ordinal];let declaration=self_.implementations[frame.declaration];if declaration.contract!=contract || frame.arguments.len!=arguments.len {continue;}var same=true;let type_span_11=checkedTypeList(self_.types,frame.arguments);for index in 0..(type_span_11.len as i64) {let before=self_.types.list(type_span_11)[index];let equal,err=self_.types.equalSymbolic(before,arguments[index]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if !equal {same=false;break;}}if !same {continue;}let member_index=self_.implementationMemberIndex(declaration,name);if !member_index.present {return blot_support::none<u32>(),blot_error::Error.none;}let member=self_.implementation_members[member_index.value];if member.kind!=blot_reuse_principal_interface::ImplementationMemberKind.type_ {return blot_support::none<u32>(),blot_error::Error.none;}let old,err=blot_check_trait_patterns::typeBinders(self_.types,declaration);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.substituteWithRows(member.root,old,frame.variables,[],[]);return blot_support::some(root),err;
    }return blot_support::none<u32>(),blot_error::Error.none;
}
fn implementationBodies(self_:Engine&)->blot_error::Error {for declaration in self_.implementations {if declaration.identity.unit!=self_.unit {continue;}for member in declaration.members.start..declaration.members.start+declaration.members.len {let root,err=self_.resolveImplementationMember(member as u32);if err!=blot_error::Error.none {return err;}}}return blot_error::Error.none;}
fn implementationMethodScope(self_:Engine&,index:u32)->blot_error::Error {let declaration=self_.implementations[index];let err=self_.implementationScope(declaration);if err!=blot_error::Error.none {return err;}for member in self_.implementation_members[declaration.members.start..declaration.members.start+declaration.members.len] {if member.kind==blot_reuse_principal_interface::ImplementationMemberKind.value {self_.env.push(Entry{member.name,member.target.binding, ..});}}return blot_error::Error.none;}
fn implementationArgumentPack(self_:Engine&,span:blot_check_types::List)->u32,blot_error::Error {let roots=equation_type_ids.alloc_slice(span.len);let type_span_12=checkedTypeList(self_.types,span);for index in 0..(type_span_12.len as i64) {let value=self_.types.list(type_span_12)[index];roots[index]=value;}let result,err=self_.types.product(roots);equation_type_ids.free_slice(roots);return result,err;}
fn beginImplementationQualification(self_:Engine&,index:u32,scope:u32,value:u32)->blot_error::Error {let declaration=self_.implementations[index];let start=self_.declared_obligations.len as u32;for predicate in self_.implementation_predicates[declaration.predicates.start..declaration.predicates.start+declaration.predicates.len] {self_.declared_obligations.push(predicate);let err=self_.appendPending(PendingObligation{ value:predicate, owner:self_.current, declared:true, suspended:true, .. });if err!=blot_error::Error.none {return err;}}let pack,err=self_.implementationArgumentPack(declaration.head);if err!=blot_error::Error.none {return err;}let proof=blot_check_types::Obligation{ ty:pack, kind:blot_check_types::ObligationKind.contract, source:scope, identity:declaration.contract, explicit:true, .. };self_.declared_obligations.push(proof);if self_.tree.node(scope).tag!=blot_parse_ast::tag_field {let err=self_.appendPending(PendingObligation{ value:proof, owner:self_.current, declared:true, suspended:true, .. });if err!=blot_error::Error.none {return err;}}self_.qualifications.push(Qualification{scope:scope,owner:self_.current,clauses:blot_check_types::List{start:start,len:self_.declared_obligations.len as u32-start, ..},value:value, ..});return blot_error::Error.none;}
fn validateImplementationBinders(self_:Engine&,index:u32,source:u32)->blot_error::Error {let declaration=self_.implementations[index];for ordinal in 0..declaration.variables.len {let variable=self_.types.list(declaration.variables)[ordinal];let resolved=self_.types.head(variable,0);if self_.types.node(resolved).tag!=blot_check_types::Tag.variable {let err=self_.diagnostic(Code.type_mismatch,source);if err!=blot_error::Error.none {return err;}}for prior in 0..ordinal {if self_.types.head(self_.types.list(declaration.variables)[prior],0)==resolved {let err=self_.diagnostic(Code.type_mismatch,source);if err!=blot_error::Error.none {return err;}}}}let type_span_13=checkedTypeList(self_.types,declaration.row_parameters);for ordinal in 0..(type_span_13.len as i64) {let row=self_.types.list(type_span_13)[ordinal];let resolved_id,err=self_.types.resolveEffects(row,0);if err!=blot_error::Error.none {return err;}let resolved=self_.types.row(resolved_id);var variable=blot_support::none<u32>();match resolved.tail {variable payload=>{variable=blot_support::some(payload.value);},_=>{}}if resolved.labels.len!=0 || !variable.present {let err=self_.diagnostic(Code.effect_mismatch,source);if err!=blot_error::Error.none {return err;}continue;}for prior in self_.types.list(declaration.row_parameters)[..ordinal] {let previous_id,err=self_.types.resolveEffects(prior,0);if err!=blot_error::Error.none {return err;}let previous=self_.types.row(previous_id);match previous.tail {variable payload=>{if payload.value==variable.value {let err=self_.diagnostic(Code.effect_mismatch,source);if err!=blot_error::Error.none {return err;}}},_=>{}}}}return blot_error::Error.none;}
fn contractArgumentsEqual<A>(self_:Engine&,given:blot_check_types::Obligation,contract:Identity,arguments:A,resolve:bool)->bool,blot_error::Error {if given.kind!=blot_check_types::ObligationKind.contract || given.identity!=contract {return false,blot_error::Error.none;}let node=self_.types.node(self_.types.head(given.ty,0));if node.tag!=blot_check_types::Tag.product || node.b!=typeArgumentCount(arguments) {return false,blot_error::Error.none;}let expected=equation_type_ids.alloc_slice(node.b);let type_span_14=checkedTypeList(self_.types,blot_check_types::List{start:node.a,len:node.b, ..});for index in 0..(type_span_14.len as i64) {let item=self_.types.list(type_span_14)[index];expected[index]=item;}let same,err=contractArgumentsEqualBody(self_,expected,arguments,resolve);equation_type_ids.free_slice(expected);return same,err;}
fn contractArgumentsEqualBody<E,A>(self_:Engine&,expected:E,arguments:A,resolve:bool)->bool,blot_error::Error {var same=true;for index in 0..typeArgumentCount(expected) {let left=typeArgumentAt(self_,expected,index);var before=left;var after=typeArgumentAt(self_,arguments,index);if resolve {let value,err=self_.types.resolve(before,0);if err!=blot_error::Error.none {return false,err;}before=value;let value,err=self_.types.resolve(after,0);if err!=blot_error::Error.none {return false,err;}after=value;}let equal,err=self_.types.equalSymbolic(before,after);if err!=blot_error::Error.none {return false,err;}if !equal {same=false;}}return same,blot_error::Error.none;}
fn contractGiven<A>(self_:Engine&,contract:Identity,arguments:A)->bool,blot_error::Error {for boundary in self_.qualifications {if boundary.owner!=self_.current {continue;}for given in self_.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {let same,err=self_.contractArgumentsEqual(given,contract,arguments,false);if err!=blot_error::Error.none || same {return same,err;}}}if self_.checking_implementation.present {let declaration=self_.implementations[self_.checking_implementation.value];if declaration.contract==contract && declaration.head.len==typeArgumentCount(arguments) {let same,err=contractArgumentsEqualBody(self_,checkedTypeList(self_.types,declaration.head),arguments,false);if err!=blot_error::Error.none || same {return same,err;}}for given in self_.implementation_predicates[declaration.predicates.start..declaration.predicates.start+declaration.predicates.len] {let same,err=self_.contractArgumentsEqual(given,contract,arguments,false);if err!=blot_error::Error.none || same {return same,err;}}}return false,blot_error::Error.none;}
fn privateImplementationAllowed(self_:const Engine&,source:u32)->bool {let span=self_.tree.span(source);let ast_walk_14_count=self_.tree.roots.items.len;for ast_walk_14_index in 0..ast_walk_14_count {let root=self_.tree.roots.items[ast_walk_14_index];let enclosing=self_.tree.span(root);if span.start<enclosing.start || span.end>enclosing.end {continue;}if blot_parse_ast::declaration_traits(self_.tree,root).private {return true;}if self_.tree.node(root).tag!=blot_parse_ast::tag_value_decl {return false;}let value=self_.tree.value_decl(root);for header in [value.annotation,value.where_node] {if header==0 {continue;}let boundary=self_.tree.span(header);if span.start>=boundary.start && span.end<=boundary.end {return false;}}return true;}return self_.current!=0;}
recursive fn resolveTraitImpl(self_:Engine&,contract:Identity,input:const u32[:],member_name:u32,source:u32)->bool,u32,blot_error::Error {
    let arguments=equation_type_ids.alloc_slice(input.len);for value,index in input {arguments[index]=value;}
    let matched,member_ty,err=resolveTraitImplResolved(self_,contract,arguments,member_name,source);
    equation_type_ids.free_slice(arguments);
    return matched,member_ty,err;
}
recursive fn resolveTraitImplResolved(self_:Engine&,contract:Identity,arguments:u32[:],member_name:u32,source:u32)->bool,u32,blot_error::Error {
    for &argument in arguments {let root,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return false,0,err;}argument=root;}
    let given,err=self_.contractGiven(contract,arguments);if err!=blot_error::Error.none || given {return false,0,err;}
    for argument in arguments {let closed,err=self_.types.equalClosed(argument,argument);if err!=blot_error::Error.none || !closed {return false,0,err;}}
    if self_.active_evidence.len>=256 {let err=self_.diagnostic(Code.associated_limit,source);return false,0,err;}
    for active in self_.active_evidence {let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none || !allowed {return false,0,err;}if active.contract!=contract || active.arguments.len!=arguments.len {continue;}let same,err=contractArgumentsEqualBody(self_,arguments,checkedTypeList(self_.types,active.arguments),false);if err!=blot_error::Error.none {return false,0,err;}if same {let err=self_.diagnostic(Code.recursive_evidence,source);return false,0,err;}}
    let saved,err=self_.types.saveList(arguments);if err!=blot_error::Error.none {return false,0,err;}
    self_.active_evidence.push(Engine_active_evidence{contract:contract,arguments:saved, ..});
    let matched,member_ty,err=resolveTraitImplActive(self_,contract,arguments,member_name,source,saved);
    self_.active_evidence.resize(self_.active_evidence.len-1);
    return matched,member_ty,err;
}
recursive fn typeContainsOwn(self_:const Engine&,root:u32,depth:i64)->bool {
    if root==0 || depth>=64 {return false;}
    let id=self_.types.head(root,0);
    let node=self_.types.node(id);
    if node.tag==blot_check_types::Tag.usage && node.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {return true;}
    if node.tag==blot_check_types::Tag.function {return typeContainsOwn(self_,node.a,depth+1) || typeContainsOwn(self_,node.b,depth+1);}
    if node.tag==blot_check_types::Tag.usage || node.tag==blot_check_types::Tag.forall || node.tag==blot_check_types::Tag.array {return typeContainsOwn(self_,node.a,depth+1);}
    if node.tag==blot_check_types::Tag.product {
        let items=self_.types.list(blot_check_types::List{node.a,node.b, ..});
        for item in items {if typeContainsOwn(self_,item,depth+1) {return true;}}
    }
    if node.tag==blot_check_types::Tag.record {
        for idx in 0..node.b {if typeContainsOwn(self_,self_.types.recordField(node,idx).ty,depth+1) {return true;}}
    }
    if node.tag==blot_check_types::Tag.nominal {
        let args=self_.types.nominalArguments(node);
        for arg in args {if typeContainsOwn(self_,arg,depth+1) {return true;}}
    }
    return false;
}
fn traitIsReadOnly(self_:const Engine&,contract:Identity)->bool {
    let found .= self_.catalogs.contract_identities.get(contract);
    if !found {return false;}
    let c=self_.contracts[found];
    for m in self_.contract_members[c.members.start..c.members.start+c.members.len] {
        if m.kind!=blot_reuse_principal_interface::ContractMemberKind.value || m.root==0 {continue;}
        if typeContainsOwn(self_,m.root,0) {return false;}
    }
    return true;
}
fn liftedTraitArg0(self_:Engine&,ty:u32)->u32,blot_error::Error {
    var cur=ty;
    let unwrapped=blot_check_storage_types::sharedInner(self_.types,cur);
    if unwrapped.present {let inner,err=self_.types.resolve(unwrapped.value,0);if err!=blot_error::Error.none {return 0,err;}cur=inner;}
    let elem=blot_check_storage_types::arrayElement(self_.types,cur);
    if elem.present && self_.types.node(self_.types.head(cur,0)).tag!=blot_check_types::Tag.array {
        let arr,err=self_.types.array(elem.value);if err!=blot_error::Error.none {return 0,err;}cur=arr;
    }
    return cur,blot_error::Error.none;
}
recursive fn resolveTraitImplActive(self_:Engine&,contract:Identity,arguments:const u32[:],member_name:u32,source:u32,saved:blot_check_types::List)->bool,u32,blot_error::Error {
    var selected=blot_support::none<u32>();var lifted_storage=IdBuffer{..};var match_args=arguments;
    for ordinal in self_.implementation_order {
        let declaration=self_.implementations[ordinal];
        let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none || !allowed {lifted_storage.deinit(equation_type_ids);return false,0,err;}
        if declaration.contract!=contract {continue;}
        if declaration.private && declaration.identity.unit!=self_.unit {continue;}
        let matches,err=blot_check_trait_patterns::matches(self_.types,declaration,arguments);if err!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,err;}
        if !matches {continue;}
        if selected.present {lifted_storage.deinit(equation_type_ids);let err=self_.diagnostic(Code.overlapping_implementation,source);return false,0,err;}
        selected=blot_support::some(ordinal);
    }
    if !selected.present && arguments.len!=0 && self_.traitIsReadOnly(contract) {
        let lifted0,lerr=self_.liftedTraitArg0(arguments[0]);if lerr!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,lerr;}
        if lifted0!=arguments[0] {
            let aerr=lifted_storage.append(lifted0);if aerr!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,aerr;}
            for ai in 1..arguments.len {let aerr2=lifted_storage.append(arguments[ai]);if aerr2!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,aerr2;}}
            for ordinal in self_.implementation_order {
                let declaration=self_.implementations[ordinal];
                if declaration.contract!=contract {continue;}
                if declaration.private && declaration.identity.unit!=self_.unit {continue;}
                let matches,err=blot_check_trait_patterns::matches(self_.types,declaration,lifted_storage.items);if err!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,err;}
                if !matches {continue;}
                if selected.present {lifted_storage.deinit(equation_type_ids);let err=self_.diagnostic(Code.overlapping_implementation,source);return false,0,err;}
                selected=blot_support::some(ordinal);
            }
            if selected.present {match_args=lifted_storage.items;}
        }
    }
    if !selected.present {lifted_storage.deinit(equation_type_ids);let err=self_.diagnostic(Code.missing_implementation,source);return false,0,err;}
    let index=selected.value;let declaration=self_.implementations[index];
    if declaration.private && !self_.privateImplementationAllowed(source) {lifted_storage.deinit(equation_type_ids);let err=self_.diagnostic(Code.private_identity_escape,source);return false,0,err;}
    for member in declaration.members.start..declaration.members.start+declaration.members.len {if self_.implementation_members[member].root==0 {let root,err=self_.resolveImplementationMember(member as u32);if err!=blot_error::Error.none {lifted_storage.deinit(equation_type_ids);return false,0,err;}}}
    let variables=equation_type_ids.alloc_slice(declaration.variables.len);let old=equation_type_ids.alloc_slice(variables.len);
    let prerequisites=allocPredicates(declaration.predicates.len);for value,ordinal in self_.implementation_predicates[declaration.predicates.start..declaration.predicates.start+declaration.predicates.len] {setPredicate(prerequisites,ordinal,value);}
    let matched,member_ty,err=resolveTraitImplInstance(self_,match_args,member_name,source,saved,index,declaration,variables,old,prerequisites);
    freePredicates(prerequisites);equation_type_ids.free_slice(old);equation_type_ids.free_slice(variables);lifted_storage.deinit(equation_type_ids);
    return matched,member_ty,err;
}
recursive fn resolveTraitImplInstance(self_:Engine&,arguments:const u32[:],member_name:u32,source:u32,saved:blot_check_types::List,index:u32,declaration:Implementation,variables:u32[:],old:u32[:],prerequisites:PredicateRun)->bool,u32,blot_error::Error {
    let instance,err=blot_check_trait_patterns::instantiateInto(self_.types,declaration,variables);if err!=blot_error::Error.none {return false,0,err;}
    for argument,ordinal in arguments {let err=self_.types.unify(self_.types.list(instance.head)[ordinal],argument);if err!=blot_error::Error.none {return false,0,err;}}
    let type_span_21=checkedTypeList(self_.types,declaration.variables);for ordinal in 0..(type_span_21.len as i64) {old[ordinal]=self_.types.head(self_.types.list(type_span_21)[ordinal],0);}
    self_.provisional_equations.push(Engine_provisional_equations{declaration:index,arguments:saved,variables:equation_type_ids.realloc_slice(variables,variables.len),rows:default<const u32[:]>(), ..});
    let matched,member_ty,err=resolveTraitImplPrerequisites(self_,member_name,source,declaration,variables,old,prerequisites);
    self_.provisional_equations.resize(self_.provisional_equations.len-1);
    return matched,member_ty,err;
}
recursive fn resolveTraitImplPrerequisites(self_:Engine&,member_name:u32,source:u32,declaration:Implementation,variables:const u32[:],old:const u32[:],prerequisites:PredicateRun)->bool,u32,blot_error::Error {
    for ordinal in 0..prerequisites.len {
        let before=predicateAt(prerequisites,ordinal);
        let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none || !allowed {return false,0,err;}
        let normalized,err=self_.resolvePredicate(before);if err!=blot_error::Error.none {return false,0,err;}
        let predicate,err=self_.substitutePredicate(normalized,old,variables,[],[]);if err!=blot_error::Error.none {return false,0,err;}
        predicate.source=source;
        var ok=false;
        if predicate.kind==blot_check_types::ObligationKind.contract {
            let app=self_.types.node(self_.types.head(predicate.ty,0));
            if app.tag==blot_check_types::Tag.product {
                let child_ok,_,cerr=self_.resolveTraitImpl(predicate.identity,self_.types.list(blot_check_types::List{app.a,app.b, ..}),0,source);
                if cerr!=blot_error::Error.none {return false,0,cerr;}
                ok=child_ok;
            }
        } else if predicate.kind==blot_check_types::ObligationKind.type_eq {
            let left,lerr=self_.normalizeAssociated(predicate.ty,source,true);if lerr!=blot_error::Error.none {return false,0,lerr;}
            let right,rerr=self_.normalizeAssociated(predicate.result,source,true);if rerr!=blot_error::Error.none {return false,0,rerr;}
            let eq,eerr=self_.types.equalSymbolic(left,right);if eerr!=blot_error::Error.none {return false,0,eerr;}
            ok=eq;
        }
        if !ok {let err=self_.diagnostic(Code.incompatible_implementation,source);return false,0,err;}
    }
    var member_ty:u32=0;
    if member_name!=0 {
        for original in self_.implementation_members[declaration.members.start..declaration.members.start+declaration.members.len] {
            if original.name!=member_name {continue;}
            let resolved,err=self_.types.resolve(original.root,0);if err!=blot_error::Error.none {return false,0,err;}
            let root,err=self_.types.substituteWithRows(resolved,old,variables,[],[]);if err!=blot_error::Error.none {return false,0,err;}
            let normalized,err=self_.normalizeAssociated(root,source,true);if err!=blot_error::Error.none {return false,0,err;}
            let closed,err=self_.types.equalClosed(normalized,normalized);if err!=blot_error::Error.none {return false,0,err;}
            if !closed {let err=self_.diagnostic(Code.incompatible_implementation,source);return false,0,err;}
            member_ty=normalized;
            break;
        }
    }
    return true,member_ty,blot_error::Error.none;
}
fn resolvePredicate(self_:Engine&,before:blot_check_types::Obligation)->blot_check_types::Obligation,blot_error::Error {var result=before;let value,e=self_.types.resolve(before.ty,0);if e!=blot_error::Error.none {return result,e;}result.ty=value;let value,e=self_.types.resolve(before.other,0);if e!=blot_error::Error.none {return result,e;}result.other=value;let value,e=self_.types.resolve(before.result,0);if e!=blot_error::Error.none {return result,e;}result.result=value;let value,e=self_.types.resolve(before.signature,0);if e!=blot_error::Error.none {return result,e;}result.signature=value;return result,blot_error::Error.none;}
fn memberTemplates(self_:Engine&)->blot_error::Error {for slot in self_.catalogs.contract_names.slots {if slot.tag==0 {continue;}let key=slot.key;let contract=self_.contracts[slot.val];for member in self_.contract_members[contract.members.start..contract.members.start+contract.members.len] {if member.kind!=blot_reuse_principal_interface::ContractMemberKind.value {continue;}let allowed,err=self_.associatedStep(0);if err!=blot_error::Error.none || !allowed {return err;}self_.name_bytes.clear();if key.namespace_!=0 {for byte in self_.pool.get(key.namespace_) {self_.name_bytes.push(byte);}self_.name_bytes.push('.' as u8);}for byte in self_.pool.get(key.member) {self_.name_bytes.push(byte);}self_.name_bytes.push('.' as u8);for byte in self_.pool.get(member.name) {self_.name_bytes.push(byte);}let name,err=self_.pool.intern(self_.name_bytes);if err==blot_error::Error.symbol_limit {return blot_error::Error.type_limit;}if err!=blot_error::Error.none {return err;}if self_.hasGlobal(name) {continue;}let start=self_.obligations.len as u32;for predicate in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {self_.obligations.push(predicate);}let member_index=self_.memberIndex(contract,member.name);let scalar_lookup_36 .= self_.member_sources.get(member_index.value);var source:u32=0;if scalar_lookup_36 {let origin:u32=scalar_lookup_36;source=origin;}let pack,err=self_.implementationArgumentPack(contract.parameters);if err!=blot_error::Error.none {return err;}self_.obligations.push(blot_check_types::Obligation{ ty:pack, kind:blot_check_types::ObligationKind.contract, source:source, identity:contract.identity, explicit:true, .. });let principal=blot_check_types::Scheme{root:member.root,variables:contract.variables,row_variables:contract.row_variables,obligations:blot_check_types::List{start:start,len:self_.obligations.len as u32-start, ..}, ..};let summary,err=self_.summarize(principal);if err!=blot_error::Error.none {return err;}let binding,err=self_.addBinding(Binding{private:contract.private,name:name,declaration:source,owner:source,kind:blot_reuse_principal_interface::Kind.global,named_function:true,ty:member.root,scheme:principal,summary:summary, ..});if err!=blot_error::Error.none {return err;}self_.global_states.insert(binding,Global{state:State.complete, ..});self_.catalogs.globals.insert(name,binding);blot_support_zigmap::put(self_.zig_orders,self_.global_order,name,0);self_.member_templates.push(blot_reuse_principal_interface::MemberTemplate{binding:binding,contract:contract.identity,name:member.name,arguments:contract.parameters, ..});}}return blot_error::Error.none;}
fn memberTemplate(self_:Engine&,binding:u32,charge:bool)->blot_support::Option<blot_reuse_principal_interface::MemberTemplate>,blot_error::Error {for candidate in self_.member_templates {if charge {let err=self_.inferenceTransition();if err!=blot_error::Error.none {return blot_support::none<blot_reuse_principal_interface::MemberTemplate>(),err;}}if candidate.binding==binding {return blot_support::some(candidate),blot_error::Error.none;}}return blot_support::none<blot_reuse_principal_interface::MemberTemplate>(),blot_error::Error.none;}
fn contractHeaders(self_:Engine&)->blot_error::Error {let ast_walk_18_count=self_.tree.roots.items.len;for ast_walk_18_index in 0..ast_walk_18_count {let id=self_.tree.roots.items[ast_walk_18_index];let node=self_.tree.node(id);if node.tag!=blot_parse_ast::tag_contract_decl {continue;}let key=Qualified{namespace_:0,member:node.a, ..};if self_.catalogs.contract_names.contains(key) || self_.catalogs.nominal_names.contains(key) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}let meta=checkedAstRange(self_.tree,node.c,node.c+4);if self_.tree.list(meta)[3]!=0 {let err=self_.diagnostic(Code.unsupported_attribute,id);if err!=blot_error::Error.none {return err;}}self_.type_env.clear();self_.row_env.clear();let parameters=equation_type_ids.alloc_slice(self_.tree.list(meta)[1]);let patterns=equation_type_ids.alloc_slice(self_.tree.list(meta)[1]);let result=contractHeaderParameters(self_,id,node,key,meta,parameters,patterns);equation_type_ids.free_slice(patterns);equation_type_ids.free_slice(parameters);if result!=blot_error::Error.none {return result;}}self_.type_env.clear();self_.row_env.clear();return blot_error::Error.none;}
fn contractHeaderParameters(self_:Engine&,id:u32,node:blot_parse_ast::Node,key:Qualified,meta:blot_parse_ast::List,parameters:u32[:],patterns:u32[:])->blot_error::Error {let syntax_source_14=blot_parse_ast::List{start:self_.tree.list(meta)[0],len:self_.tree.list(meta)[1], ..};let syntax_count_14=self_.tree.list(syntax_source_14).len;for index in 0..syntax_count_14 {let parameter=self_.tree.list(syntax_source_14)[index];let parsed,err=self_.parameterAnnotation(parameter,0);if err!=blot_error::Error.none {return err;}parameters[index]=parsed.ty;patterns[index]=parsed.pattern;}let names=equation_type_ids.alloc_slice(self_.type_env.items.len);let variables=equation_type_ids.alloc_slice(names.len);for entry,index in self_.type_env.items {names[index]=entry.name;variables[index]=entry.ty;}let row_names=equation_type_ids.alloc_slice(self_.row_env.items.len);let row_parameters=equation_type_ids.alloc_slice(row_names.len);for entry,index in self_.row_env.items {row_names[index]=entry.name;row_parameters[index]=entry.row;}let result=contractHeaderBody(self_,id,node,key,parameters,patterns,names,variables,row_names,row_parameters);equation_type_ids.free_slice(row_parameters);equation_type_ids.free_slice(row_names);equation_type_ids.free_slice(variables);equation_type_ids.free_slice(names);return result;}
fn contractHeaderBody(self_:Engine&,id:u32,node:blot_parse_ast::Node,key:Qualified,parameters:const u32[:],patterns:const u32[:],names:const u32[:],variables:const u32[:],row_names:const u32[:],row_parameters:const u32[:])->blot_error::Error {let index=self_.contracts.len as u32;let identity=Identity{unit:self_.unit,decl:blot_check_types::opaque_name_bit|node.a, ..};let product,err=self_.types.product(parameters);if err!=blot_error::Error.none {return err;}let header_rows,err=self_.types.freeRowVariables(product);if err!=blot_error::Error.none {return err;}let body=self_.tree.node(node.b);let start=self_.contract_members.len as u32;var requires=false;let syntax_source_15=blot_parse_ast::List{body.a,body.b, ..};let syntax_count_15=self_.tree.list(syntax_source_15).len;for syntax_index_15 in 0..syntax_count_15 {let child=self_.tree.list(syntax_source_15)[syntax_index_15];let item=self_.tree.node(child);if item.tag!=blot_parse_ast::tag_contract_type_member && item.tag!=blot_parse_ast::tag_contract_value_member {continue;}let allowed,err=self_.associatedStep(child);if err!=blot_error::Error.none {return err;}if !allowed {continue;}var duplicate=false;for member in self_.contract_members[start..] {if member.name==item.a {duplicate=true;}}if duplicate {let err=self_.diagnostic(Code.duplicate_name,child);if err!=blot_error::Error.none {return err;}continue;}var kind=blot_reuse_principal_interface::ContractMemberKind.defined_type;if item.tag==blot_parse_ast::tag_contract_value_member {kind=blot_reuse_principal_interface::ContractMemberKind.value;}else if item.b==0 {kind=blot_reuse_principal_interface::ContractMemberKind.abstract_type;}requires=requires || kind!=blot_reuse_principal_interface::ContractMemberKind.defined_type;let member=self_.contract_members.len as u32;self_.contract_members.push(ContractMember{contract:identity,name:item.a,kind:kind, ..});self_.member_sources.insert(member,child);}let members=blot_check_types::List{start:start,len:self_.contract_members.len as u32-start, ..};self_.has_associated_types=self_.has_associated_types || members.len!=0;let parameter_list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return err;}let pattern_list,err=self_.parameter_patterns.saveList(patterns);if err!=blot_error::Error.none {return err;}let variable_list,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return err;}let name_list,err=self_.types.saveList(names);if err!=blot_error::Error.none {return err;}let row_list,err=self_.types.saveList(header_rows);if err!=blot_error::Error.none {return err;}let row_name_list,err=self_.types.saveList(row_names);if err!=blot_error::Error.none {return err;}let row_parameters_list,err=self_.types.saveList(row_parameters);if err!=blot_error::Error.none {return err;}let __alias_field_1_declaration: u32 = id; let __alias_field_2_private: bool = blot_parse_ast::declaration_traits(self_.tree,id).private; let __alias_field_3_identity: blot_reuse_principal_interface::Identity = identity; let __alias_field_4_name: u32 = node.a; let __alias_field_5_parameters: blot_reuse_principal_interface::List = parameter_list; let __alias_field_6_patterns: blot_reuse_principal_interface::List = pattern_list; let __alias_field_7_variables: blot_reuse_principal_interface::List = variable_list; let __alias_field_8_parameter_names: blot_reuse_principal_interface::List = name_list; let __alias_field_9_members: blot_reuse_principal_interface::List = members; let __alias_field_10_requires_implementation: bool = requires; let __alias_field_11_row_variables: blot_reuse_principal_interface::List = row_list; let __alias_field_12_row_parameter_names: blot_reuse_principal_interface::List = row_name_list; let __alias_field_13_row_parameters: blot_reuse_principal_interface::List = row_parameters_list; self_.contracts.push(Contract{ declaration: __alias_field_1_declaration, private: __alias_field_2_private, identity: __alias_field_3_identity, name: __alias_field_4_name, parameters: __alias_field_5_parameters, variables: __alias_field_7_variables, patterns: __alias_field_6_patterns, parameter_names: __alias_field_8_parameter_names, row_variables: __alias_field_11_row_variables, row_parameter_names: __alias_field_12_row_parameter_names, row_parameters: __alias_field_13_row_parameters, members: __alias_field_9_members, requires_implementation: __alias_field_10_requires_implementation, .. });self_.catalogs.contract_names.insert(key,index);self_.catalogs.contract_identities.insert(identity,index);return blot_error::Error.none;}
recursive fn resolveContract(self_:Engine&,index:u32)->blot_error::Error {let contract=self_.contracts[index];if contract.identity.unit!=self_.unit {return blot_error::Error.none;}let state .= self_.contract_states.get(index);if state {if state==Engine_contract_states_state.visiting {return self_.diagnostic(Code.recursive_contract,contract.declaration);}return blot_error::Error.none;}if self_.contract_depth>=256 {return blot_error::Error.type_limit;}self_.contract_depth+=1;self_.contract_states.insert(index,Engine_contract_states_state.visiting);let saved_types=self_.type_env;let saved_rows=self_.row_env;let saved_closed=self_.closed_type_variables;let saved_alias_rows=self_.implicit_row_parameters;self_.type_env=TypeEnvironment{..};self_.row_env=RowEnvironment{..};self_.closed_type_variables=true;self_.implicit_row_parameters=true;let result=resolveContractBody(self_,index,contract);self_.type_env.deinit();self_.row_env.deinit();self_.type_env=canonicalTypeEnvironment(saved_types);self_.row_env=canonicalRowEnvironment(saved_rows);self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_alias_rows;self_.contract_depth-=1;return result;}
recursive fn resolveContractBody(self_:Engine&,index:u32,contract:Contract)->blot_error::Error {for parameter in 0..contract.variables.len {let err=self_.type_env.append(Engine_type_env{name:self_.types.list(contract.parameter_names)[parameter],ty:self_.types.list(contract.variables)[parameter], ..});if err!=blot_error::Error.none {return err;}}let type_span_26=checkedTypeList(self_.types,contract.row_parameter_names);for ordinal in 0..(type_span_26.len as i64) {let name=self_.types.list(type_span_26)[ordinal];let err=self_.row_env.append(Engine_row_env{name:name,row:self_.types.list(contract.row_parameters)[ordinal], ..});if err!=blot_error::Error.none {return err;}}let body=self_.tree.node(contract.declaration).b;let node=self_.tree.node(body);var predicates=PredicateBuffer{..};var roots=IdBuffer{..};let result=resolveContractPredicates(self_,index,contract,body,node,predicates,roots);blot_support_pooled_buffer::deinit(roots,equation_type_ids);blot_support_pooled_buffer::deinit(predicates,equation_values);return result;}
type PredicateBuffer=blot_support_pooled_buffer::Buffer<blot_check_types::Obligation>;
type IdBuffer=blot_support_pooled_buffer::Buffer<u32>;
recursive fn resolveContractPredicates(self_:Engine&,index:u32,contract:Contract,body:u32,node:blot_parse_ast::Node,predicates:PredicateBuffer&,roots:IdBuffer&)->blot_error::Error {let syntax_source_16=blot_parse_ast::List{node.a,node.b, ..};let syntax_count_16=self_.tree.list(syntax_source_16).len;for syntax_index_16 in 0..syntax_count_16 {let child=self_.tree.list(syntax_source_16)[syntax_index_16];if self_.tree.node(child).tag==blot_parse_ast::tag_constraint {let err=self_.lowerPredicates(child,body,predicates);if err!=blot_error::Error.none {return err;}}}for member in contract.members.start..contract.members.start+contract.members.len {let err=self_.resolveMember(member as u32);if err!=blot_error::Error.none {return err;}}for &predicate in predicates.items {let normalized,err=self_.resolveNonzeroPredicateRoots(predicate,roots);if err!=blot_error::Error.none {return err;}predicate=normalized;}let type_span_27=checkedTypeList(self_.types,contract.parameters);for type_index_27 in 0..(type_span_27.len as i64) {let root=self_.types.list(type_span_27)[type_index_27];let err=roots.append(root);if err!=blot_error::Error.none {return err;}}let product,err=self_.types.product(roots.items);if err!=blot_error::Error.none {return err;}let rows,err=self_.types.freeRowVariables(product);if err!=blot_error::Error.none {return err;}let start=self_.contract_predicates.len as u32;for predicate in predicates.items {self_.contract_predicates.push(predicate);}self_.contracts[index].predicates=blot_check_types::List{start:start,len:predicates.items.len as u32, ..};let span,err=self_.types.saveList(rows);if err!=blot_error::Error.none {return err;}self_.contracts[index].row_variables=span;self_.contract_states.insert(index,Engine_contract_states_state.ready);return blot_error::Error.none;}
fn resolveNonzeroPredicateRoots(self_:Engine&,before:blot_check_types::Obligation,roots:IdBuffer&)->blot_check_types::Obligation,blot_error::Error {var result=before;for ordinal in 0..4 {var root=before.ty;if ordinal==1 {root=before.other;}else if ordinal==2 {root=before.result;}else if ordinal==3 {root=before.signature;}if root==0 {continue;}let value,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return result,err;}if ordinal==0 {result.ty=value;}else if ordinal==1 {result.other=value;}else if ordinal==2 {result.result=value;}else {result.signature=value;}let err=roots.append(value);if err!=blot_error::Error.none {return result,err;}}return result,blot_error::Error.none;}
fn blot_support_pooled_buffer::append(self_:blot_check_check::IdBuffer&,value:u32)->blot_error::Error {return blot_support_pooled_buffer::push(self_,value,blot_check_check::equation_type_ids);}
fn blot_support_pooled_buffer::append(self_:blot_check_check::PredicateBuffer&,value:blot_check_types::Obligation)->blot_error::Error {return blot_support_pooled_buffer::push(self_,value,blot_check_check::equation_values);}
fn associatedStep(self_:Engine&,source:u32)->bool,blot_error::Error {if self_.inference_transitions+self_.types.projection_steps>=self_.inference_limit {let err=self_.diagnostic(Code.associated_limit,source);return false,err;}let err=self_.types.chargeProjection();if err==blot_error::Error.type_limit {let issue=self_.diagnostic(Code.associated_limit,source);return false,issue;}return err==blot_error::Error.none,err;}
fn memberIndex(self_:const Engine&,contract:Contract,name:u32)->blot_support::Option<u32> {for index in contract.members.start..contract.members.start+contract.members.len {if self_.contract_members[index].name==name {return blot_support::some(index as u32);}}return blot_support::none<u32>();}
recursive fn resolveMember(self_:Engine&,index:u32)->blot_error::Error {let member=self_.contract_members[index];if member.contract.unit!=self_.unit || member.kind==blot_reuse_principal_interface::ContractMemberKind.abstract_type {return blot_error::Error.none;}if self_.member_states.contains(index) {return blot_error::Error.none;}self_.member_states.insert(index,Engine_member_states_state.visiting);let ordinal_ref:u32={let scalar_lookup_39 .= self_.catalogs.contract_identities.get(member.contract);assert(scalar_lookup_39!=null);let scalar_value_39:u32=scalar_lookup_39;scalar_value_39};let ordinal:u32=ordinal_ref;let contract=self_.contracts[ordinal];let source_ref:u32={let scalar_lookup_40 .= self_.member_sources.get(index);assert(scalar_lookup_40!=null);let scalar_value_40:u32=scalar_lookup_40;scalar_value_40};let source:u32=source_ref;let saved_types=self_.type_env;let saved_rows=self_.row_env;let saved_closed=self_.closed_type_variables;let saved_implicit=self_.implicit_row_parameters;let saved_defer=self_.defer_associated;self_.type_env=TypeEnvironment{..};self_.row_env=RowEnvironment{..};self_.closed_type_variables=true;self_.implicit_row_parameters=false;self_.defer_associated=true;let err=resolveMemberBody(self_,index,member,contract,source);self_.type_env.deinit();self_.row_env.deinit();self_.type_env=canonicalTypeEnvironment(saved_types);self_.row_env=canonicalRowEnvironment(saved_rows);self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_implicit;self_.defer_associated=saved_defer;return err;}
recursive fn resolveMemberBody(self_:Engine&,index:u32,member:ContractMember,contract:Contract,source:u32)->blot_error::Error {let type_span_28=checkedTypeList(self_.types,contract.parameter_names);for ordinal in 0..(type_span_28.len as i64) {let name=self_.types.list(type_span_28)[ordinal];let err=self_.type_env.append(Engine_type_env{name:name,ty:self_.types.list(contract.variables)[ordinal], ..});if err!=blot_error::Error.none {return err;}}let type_span_29=checkedTypeList(self_.types,contract.row_parameter_names);for ordinal in 0..(type_span_29.len as i64) {let name=self_.types.list(type_span_29)[ordinal];let err=self_.row_env.append(Engine_row_env{name:name,row:self_.types.list(contract.row_parameters)[ordinal], ..});if err!=blot_error::Error.none {return err;}}if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {let cparams=equation_type_ids.alloc_slice(contract.parameters.len);for pi in 0..contract.parameters.len {cparams[pi]=self_.types.list(contract.parameters)[pi];}for cm in self_.contract_members[contract.members.start..contract.members.start+contract.members.len] {if cm.kind==blot_reuse_principal_interface::ContractMemberKind.abstract_type {let proj,perr=self_.types.projection(contract.identity,cm.name,cparams);if perr!=blot_error::Error.none {equation_type_ids.free_slice(cparams);return perr;}self_.types.has_projections=true;self_.has_associated_types=true;let err=self_.type_env.append(Engine_type_env{name:cm.name,ty:proj, ..});if err!=blot_error::Error.none {equation_type_ids.free_slice(cparams);return err;}}}equation_type_ids.free_slice(cparams);}let root,err=self_.annotation(self_.tree.node(source).b);if err!=blot_error::Error.none {return err;}self_.contract_members[index].root=root;self_.member_states.insert(index,Engine_member_states_state.ready);return blot_error::Error.none;}
recursive fn projectionAnnotation(self_:Engine&,symbol:u32,syntax:const u32[:],source:u32)->blot_support::Option<u32>,blot_error::Error {let name=self_.pool.get(symbol);let separator=lastDot(name);if !separator.present {return blot_support::none<u32>(),blot_error::Error.none;}let path=name[..separator.value];let first_separator=firstDot(path);var first_text=path;if first_separator.present {first_text=path[..first_separator.value];}let first_name,known=self_.pool.lookup(first_text);if !known {return blot_support::none<u32>(),blot_error::Error.none;}for entry in self_.type_env.items {if entry.name==first_name {if !first_separator.present && syntax.len==0 {let m_sym,m_known=self_.pool.lookup(name[separator.value+1..]);if m_known {let var_head=self_.types.head(entry.ty,0);var found_contract=Identity{0,0, ..};var found_args=blot_check_types::List{..};var matches:i64=0;for boundary in self_.qualifications {if boundary.owner!=self_.current {continue;}for given in self_.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {if given.kind!=blot_check_types::ObligationKind.contract {continue;}let pack=self_.types.node(self_.types.head(given.ty,0));if pack.tag!=blot_check_types::Tag.product || pack.b==0 {continue;}if self_.types.head(self_.types.list(blot_check_types::List{pack.a,pack.b, ..})[0],0)!=var_head {continue;}let ci .= self_.catalogs.contract_identities.get(given.identity);if !ci {continue;}let cm=self_.memberIndex(self_.contracts[ci],m_sym);if !cm.present || self_.contract_members[cm.value].kind==blot_reuse_principal_interface::ContractMemberKind.value {continue;}if matches==0 || found_contract!=given.identity {found_contract=given.identity;found_args=blot_check_types::List{pack.a,pack.b, ..};matches+=1;}}}if self_.checking_implementation.present {let impl_=self_.implementations[self_.checking_implementation.value];for given in self_.implementation_predicates[impl_.predicates.start..impl_.predicates.start+impl_.predicates.len] {if given.kind!=blot_check_types::ObligationKind.contract {continue;}let pack=self_.types.node(self_.types.head(given.ty,0));if pack.tag!=blot_check_types::Tag.product || pack.b==0 {continue;}if self_.types.head(self_.types.list(blot_check_types::List{pack.a,pack.b, ..})[0],0)!=var_head {continue;}let ci .= self_.catalogs.contract_identities.get(given.identity);if !ci {continue;}let cm=self_.memberIndex(self_.contracts[ci],m_sym);if !cm.present || self_.contract_members[cm.value].kind==blot_reuse_principal_interface::ContractMemberKind.value {continue;}if matches==0 || found_contract!=given.identity {found_contract=given.identity;found_args=blot_check_types::List{pack.a,pack.b, ..};matches+=1;}}}if matches==0 && self_.source_validation {let span=self_.tree.span(source);for root in self_.tree.roots.items {if self_.tree.node(root).tag!=blot_parse_ast::tag_value_decl {continue;}let rspan=self_.tree.span(root);if span.start<rspan.start || span.end>rspan.end {continue;}let wd=self_.tree.value_decl(root);if wd.where_node==0 {continue;}let wlist=self_.tree.list(wd.where);for wi in 0..wlist.len {let cn=self_.tree.node(wlist[wi]);var has_ci=false;var ci_val:u32=0;{let ci .= self_.catalogs.contract_names.get(self_.catalogKey(cn.a));if ci {ci_val=ci;has_ci=true;}}if !has_ci {continue;}let details=checkedAstRange(self_.tree,cn.c,cn.c+3);let cargs=checkedAstList(self_.tree,blot_parse_ast::List{self_.tree.list(details)[0],self_.tree.list(details)[1], ..});if cargs.len==0 {continue;}let a0=self_.tree.node(self_.tree.list(cargs)[0]);if a0.tag!=blot_parse_ast::tag_type_name || a0.a!=first_name {continue;}let cm=self_.memberIndex(self_.contracts[ci_val],m_sym);if !cm.present || self_.contract_members[cm.value].kind==blot_reuse_principal_interface::ContractMemberKind.value {continue;}let sv_list,sv_err=self_.types.saveList([entry.ty]);if sv_err!=blot_error::Error.none {return blot_support::none<u32>(),sv_err;}if matches==0 || found_contract!=self_.contracts[ci_val].identity {found_contract=self_.contracts[ci_val].identity;found_args=sv_list;matches+=1;}}}}if matches==1 {let arg_copy=equation_type_ids.alloc_slice(found_args.len);for ai in 0..found_args.len {arg_copy[ai]=self_.types.list(found_args)[ai];}let proj,perr=self_.types.projection(found_contract,m_sym,arg_copy);equation_type_ids.free_slice(arg_copy);if perr!=blot_error::Error.none {return blot_support::none<u32>(),perr;}self_.types.has_projections=true;self_.has_associated_types=true;if self_.defer_associated {return blot_support::some(proj),blot_error::Error.none;}let norm,nerr=self_.normalizeAssociated(proj,source,true);return blot_support::some(norm),nerr;}if matches>1 {let err=self_.diagnostic(Code.ambiguous_qualified,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}}}let err=self_.diagnostic(Code.unsupported_type,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}}var key=Qualified{namespace_:0,member:first_name, ..};if first_separator.present {let member,known=self_.pool.lookup(path[first_separator.value+1..]);if !known {return blot_support::none<u32>(),blot_error::Error.none;}key=Qualified{namespace_:first_name,member:member, ..};}let index:u32={let scalar_lookup_41 .= self_.catalogs.contract_names.get(key);if !scalar_lookup_41 {return blot_support::none<u32>(),blot_error::Error.none;}let scalar_value_41:u32=scalar_lookup_41;scalar_value_41};let contract=self_.contracts[index];if contract.private {let span=self_.tree.span(source);let ast_walk_19_count=self_.tree.roots.items.len;for ast_walk_19_index in 0..ast_walk_19_count {let declaration=self_.tree.roots.items[ast_walk_19_index];let enclosing=self_.tree.span(declaration);if span.start<enclosing.start || span.end>enclosing.end || blot_parse_ast::declaration_traits(self_.tree,declaration).private {continue;}var escape=true;if self_.tree.node(declaration).tag==blot_parse_ast::tag_value_decl {let binding=self_.tree.value_decl(declaration);let annotation=self_.tree.span(binding.annotation);let where_span=self_.tree.span(binding.where_node);escape=(binding.annotation!=0 && span.start>=annotation.start && span.end<=annotation.end) || (binding.where_node!=0 && span.start>=where_span.start && span.end<=where_span.end);}if escape {let err=self_.diagnostic(Code.private_identity_escape,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}}}let member_name,known=self_.pool.lookup(name[separator.value+1..]);var member:u32=0;if known {member=member_name;}let selected=self_.memberIndex(contract,member);if !selected.present || self_.contract_members[selected.value].kind==blot_reuse_principal_interface::ContractMemberKind.value {let err=self_.diagnostic(Code.missing_type_member,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}if syntax.len!=contract.parameters.len {let err=self_.diagnostic(Code.associated_arity,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}let old=equation_type_ids.alloc_slice(contract.variables.len);let type_span_30=checkedTypeList(self_.types,contract.variables);for index in 0..(type_span_30.len as i64) {let value=self_.types.list(type_span_30)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let old_rows=equation_type_ids.alloc_slice(contract.row_variables.len);let type_span_31=checkedTypeList(self_.types,contract.row_variables);for index in 0..(type_span_31.len as i64) {let value=self_.types.list(type_span_31)[index];old_rows[index]=value;}let fresh_rows=equation_type_ids.alloc_slice(old_rows.len);let shapes=equation_type_ids.alloc_slice(contract.parameters.len);let type_span_32=checkedTypeList(self_.types,contract.parameters);for index in 0..(type_span_32.len as i64) {let value=self_.types.list(type_span_32)[index];shapes[index]=value;}let arguments=equation_type_ids.alloc_slice(shapes.len);let result,err=projectionAnnotationArguments(self_,contract,member,syntax,source,old,fresh,old_rows,fresh_rows,shapes,arguments);equation_type_ids.free_slice(arguments);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,err;}
recursive fn projectionAnnotationArguments(self_:Engine&,contract:Contract,member:u32,syntax:const u32[:],source:u32,old:const u32[:],fresh:u32[:],old_rows:const u32[:],fresh_rows:u32[:],shapes:const u32[:],arguments:u32[:])->blot_support::Option<u32>,blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}variable=root;}for &row in fresh_rows {let value,err=self_.types.freshEffects();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}row=value;}for shape,index in shapes {let actual,err=self_.parameterArgument(self_.parameter_patterns.list(contract.patterns)[index],syntax[index],true,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let expected,err=self_.types.substituteWithRows(shape,old,fresh,old_rows,fresh_rows);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.constrain(expected,actual,syntax[index]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}arguments[index]=actual;}let projection,err=self_.types.projection(contract.identity,member,arguments);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if self_.defer_associated {return blot_support::some(projection),blot_error::Error.none;}let root,err=self_.normalizeAssociated(projection,source,true);return blot_support::some(root),err;}
struct ProjectionMemo {member:u32,arguments:blot_check_types::List,result:u32}
struct AssociatedMemo {rows:blot_support_pooled_map::Map<u32,u32>   = blot_support_pooled_map::Map<u32,u32>{..},types:blot_support_pooled_map::Map<u32,u32>   = blot_support_pooled_map::Map<u32,u32>{..},projections:blot_support_pooled_buffer::Buffer<ProjectionMemo>   = blot_support_pooled_buffer::Buffer<ProjectionMemo>{..}}
reusable[] var associated_map_slots:dictionary_slot<u32,u32>[>..];
reusable[] var projection_memo_values:ProjectionMemo[>..];
reusable[] var equation_fields:blot_check_types::Field[>..];
fn deinit(self_:AssociatedMemo&) {self_.types.deinit(associated_map_slots);self_.rows.deinit(associated_map_slots);self_.projections.deinit(projection_memo_values);}
recursive fn normalizeAssociated(self_:Engine&,root:u32,source:u32,requirements:bool)->u32,blot_error::Error {var memo=AssociatedMemo{..};var active=IdBuffer{..};let result,err=self_.normalizeAssociatedNode(root,source,requirements,memo,active,0);active.deinit(equation_type_ids);memo.deinit();return result,err;}
recursive fn normalizeAssociatedNode(self_:Engine&,root:u32,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64)->u32,blot_error::Error {let id=self_.types.head(root,0);let node=self_.types.node(id);if id<=blot_check_types::never || node.tag==blot_check_types::Tag.variable || node.tag==blot_check_types::Tag.type_constructor {return id,blot_error::Error.none;}let scalar_lookup_42 .= memo.types.get(id);if scalar_lookup_42 {let known:u32=scalar_lookup_42;return known,blot_error::Error.none;}if depth>=256 {let err=self_.diagnostic(Code.associated_limit,source);return id,err;}let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none || !allowed {return id,err;}let result,err=normalizeAssociatedShape(self_,id,node,source,requirements,memo,active,depth);if err!=blot_error::Error.none {return 0,err;}memo.types.insert(id,result,associated_map_slots);return result,blot_error::Error.none;}
recursive fn normalizeAssociatedShape(self_:Engine&,id:u32,node:blot_check_types::Node,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64)->u32,blot_error::Error {let tag=node.tag;if tag==blot_check_types::Tag.projection || tag==blot_check_types::Tag.nominal || tag==blot_check_types::Tag.product {var span=blot_check_types::List{node.a,node.b, ..};if tag!=blot_check_types::Tag.product {span=blot_check_types::List{start:node.c,len:self_.types.nominalArguments(node).len as u32, ..};}let prior=equation_type_ids.alloc_slice(span.len);let children=selectedTypeChildren(self_.types,node);for value,index in children {prior[index]=value;}let values=equation_type_ids.alloc_slice(prior.len);let result,err=normalizeAssociatedChildren(self_,id,node,source,requirements,memo,active,depth,prior,values);equation_type_ids.free_slice(values);equation_type_ids.free_slice(prior);return result,err;}if tag==blot_check_types::Tag.function {let a,err=self_.normalizeAssociatedNode(node.a,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}let b,err=self_.normalizeAssociatedNode(node.b,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}let row,err=self_.normalizeAssociatedRow(node.c,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}if a==node.a && b==node.b && row==node.c {return id,blot_error::Error.none;}return self_.types.functionWithEffects(a,b,row);}if tag==blot_check_types::Tag.record {let fields=equation_fields.alloc_slice(node.b);let result,err=normalizeAssociatedRecord(self_,id,node,source,requirements,memo,active,depth,fields);equation_fields.free_slice(fields);return result,err;}if tag==blot_check_types::Tag.array || tag==blot_check_types::Tag.list || tag==blot_check_types::Tag.cursor || tag==blot_check_types::Tag.resolver || tag==blot_check_types::Tag.provider {let child,err=self_.normalizeAssociatedNode(node.a,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}var row=node.c;if tag==blot_check_types::Tag.provider {let value,err=self_.normalizeAssociatedRow(node.c,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}row=value;}if child==node.a && row==node.c {return id,blot_error::Error.none;}if tag==blot_check_types::Tag.resolver {return self_.types.resolver(child);}if tag==blot_check_types::Tag.provider {return self_.types.provider(child,row);}return self_.types.sequence(tag,child);}if tag==blot_check_types::Tag.usage {let child,err=self_.normalizeAssociatedNode(node.a,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}if child==node.a {return id,blot_error::Error.none;}let kind,valid=blot_check_types::usageKindFromCode(node.b);assert(valid);return self_.types.usage(child,kind,node.c);}if tag==blot_check_types::Tag.state_provider {let a,err=self_.normalizeAssociatedNode(node.a,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}let b,err=self_.normalizeAssociatedNode(node.b,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}let c,err=self_.normalizeAssociatedNode(node.c,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}if a==node.a && b==node.b && c==node.c {return id,blot_error::Error.none;}return self_.types.stateProvider(a,b,c);}return id,blot_error::Error.none;}
recursive fn normalizeAssociatedChildren(self_:Engine&,id:u32,node:blot_check_types::Node,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,prior:const u32[:],values:u32[:])->u32,blot_error::Error {var changed=false;for child,index in prior {let next,err=self_.normalizeAssociatedNode(child,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}changed=changed || next!=child;values[index]=next;}if node.tag==blot_check_types::Tag.product {if !changed {return id,blot_error::Error.none;}return self_.types.product(values);}if node.tag==blot_check_types::Tag.nominal {if !changed {return id,blot_error::Error.none;}return self_.types.nominal(Identity{node.a,node.b, ..},values);}return normalizeAssociatedProjection(self_,id,node,source,requirements,memo,active,depth,values,changed);}
recursive fn normalizeAssociatedRecord(self_:Engine&,id:u32,node:blot_check_types::Node,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,fields:blot_check_types::Field[:])->u32,blot_error::Error {var changed=false;for index in 0..node.b {let field=self_.types.recordField(node,index);let next,err=self_.normalizeAssociatedNode(field.ty,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}changed=changed || next!=field.ty;fields[index]=blot_check_types::Field{name:field.name,ty:next, ..};}if !changed {return id,blot_error::Error.none;}return self_.types.record(fields);}
recursive fn normalizeAssociatedProjection(self_:Engine&,id:u32,node:blot_check_types::Node,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,arguments:const u32[:],changed:bool)->u32,blot_error::Error {let identity=Identity{node.a,node.b, ..};let selected:u32={let scalar_lookup_43 .= self_.catalogs.contract_identities.get(identity);if !scalar_lookup_43 {let err=self_.diagnostic(Code.missing_type_member,source);return id,err;}let scalar_value_43:u32=scalar_lookup_43;scalar_value_43};let index=selected;let contract=self_.contracts[index];let name=self_.types.projectionMember(node);let selected_member=self_.memberIndex(contract,name);if !selected_member.present {let err=self_.diagnostic(Code.missing_type_member,source);return id,err;}let member=selected_member.value;if inList(active.items,member) {let err=self_.diagnostic(Code.recursive_associated_type,source);return id,err;}for cached in memo.projections.items {let allowed,err=self_.associatedStep(source);if err!=blot_error::Error.none || !allowed {return id,err;}if cached.member!=member || cached.arguments.len!=arguments.len {continue;}var same=true;let type_span_33=checkedTypeList(self_.types,cached.arguments);for ordinal in 0..(type_span_33.len as i64) {let before=self_.types.list(type_span_33)[ordinal];let equal,err=self_.types.equalSymbolic(before,arguments[ordinal]);if err!=blot_error::Error.none {return 0,err;}if !equal {same=false;break;}}if same {self_.counters.projection_memo_hits+=1;return cached.result,blot_error::Error.none;}}let err=self_.resolveMember(member);if err!=blot_error::Error.none {return 0,err;}let old=equation_type_ids.alloc_slice(contract.variables.len);let type_span_34=checkedTypeList(self_.types,contract.variables);for ordinal in 0..(type_span_34.len as i64) {let value=self_.types.list(type_span_34)[ordinal];old[ordinal]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let old_rows=equation_type_ids.alloc_slice(contract.row_variables.len);let type_span_35=checkedTypeList(self_.types,contract.row_variables);for ordinal in 0..(type_span_35.len as i64) {let value=self_.types.list(type_span_35)[ordinal];old_rows[ordinal]=value;}let fresh_rows=equation_type_ids.alloc_slice(old_rows.len);let shapes=equation_type_ids.alloc_slice(contract.parameters.len);let type_span_36=checkedTypeList(self_.types,contract.parameters);for ordinal in 0..(type_span_36.len as i64) {let value=self_.types.list(type_span_36)[ordinal];shapes[ordinal]=value;}let result,err=normalizeAssociatedProjectionBound(self_,id,identity,name,index,contract,member,source,requirements,memo,active,depth,arguments,changed,old,fresh,old_rows,fresh_rows,shapes);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,err;}
recursive fn normalizeAssociatedProjectionBound(self_:Engine&,id:u32,identity:Identity,name:u32,index:u32,contract:Contract,member_index:u32,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,arguments:const u32[:],changed:bool,old:const u32[:],fresh:u32[:],old_rows:const u32[:],fresh_rows:u32[:],shapes:const u32[:])->u32,blot_error::Error {let member=self_.contract_members[member_index];for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}for &row in fresh_rows {let root,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}row=root;}for shape,ordinal in shapes {let expected,err=self_.types.substituteWithRows(shape,old,fresh,old_rows,fresh_rows);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(expected,arguments[ordinal],source);if err!=blot_error::Error.none {return 0,err;}}let equation,err=self_.implementationEquation(identity,name,arguments);if err!=blot_error::Error.none {return 0,err;}if equation.present {return equation.value,blot_error::Error.none;}let provisional,err=self_.provisionalEquation(identity,name,arguments);if err!=blot_error::Error.none {return 0,err;}if provisional.present {let err=active.append(member_index);if err!=blot_error::Error.none {return 0,err;}let result,error=self_.normalizeAssociatedNode(provisional.value,source,requirements,memo,active,depth+1);active.resize(active.items.len-1);return result,error;}let lexical,err=self_.contractGiven(identity,arguments);if err!=blot_error::Error.none {return 0,err;}var selected_present=false;var selected_member_ty:u32=0;if contract.requires_implementation && !lexical {let matched,mty,err=self_.resolveTraitImpl(identity,arguments,name,source);if err!=blot_error::Error.none {return 0,err;}selected_present=matched;selected_member_ty=mty;}if selected_present && member.kind!=blot_reuse_principal_interface::ContractMemberKind.defined_type && selected_member_ty!=0 {return selected_member_ty,blot_error::Error.none;}if requirements {let err=normalizeAssociatedRequirements(self_,index,identity,source,arguments,old,fresh,old_rows,fresh_rows,selected_present,lexical);if err!=blot_error::Error.none {return 0,err;}}if member.kind!=blot_reuse_principal_interface::ContractMemberKind.defined_type {if !changed {return id,blot_error::Error.none;}return self_.types.projection(identity,name,arguments);}let err=active.append(member_index);if err!=blot_error::Error.none {return 0,err;}let result,error=normalizeAssociatedExpansion(self_,member,source,requirements,memo,active,depth,arguments,old,fresh,old_rows,fresh_rows,member_index);active.resize(active.items.len-1);return result,error;}
recursive fn normalizeAssociatedRequirements(self_:Engine&,index:u32,identity:Identity,source:u32,arguments:const u32[:],old:const u32[:],fresh:const u32[:],old_rows:const u32[:],fresh_rows:const u32[:],selected:bool,lexical:bool)->blot_error::Error {let err=self_.resolveContract(index);if err!=blot_error::Error.none {return err;}let contract=self_.contracts[index];for predicate in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {let instantiated,err=self_.substitutePredicate(predicate,old,fresh,old_rows,fresh_rows);if err!=blot_error::Error.none {return err;}instantiated.source=source;instantiated.explicit=true;instantiated.qualification_unit=self_.unit;instantiated.qualification_span=blot_support::some(self_.tree.span(source));if instantiated.kind==blot_check_types::ObligationKind.type_eq {let same,err=self_.types.equalSymbolic(instantiated.ty,instantiated.result);if err!=blot_error::Error.none {return err;}if same {continue;}}if self_.closed_type_variables && !self_.implicit_row_parameters && self_.current==0 {let open,err=self_.requirementOpen(instantiated);if err!=blot_error::Error.none {return err;}if open {let err=self_.diagnostic(Code.missing_predicate,source);if err!=blot_error::Error.none {return err;}}}let err=self_.appendPending(PendingObligation{ value:instantiated, owner:self_.current, suspended:true, .. });if err!=blot_error::Error.none {return err;}}if contract.requires_implementation && !selected && !lexical {let pack,err=self_.types.product(arguments);if err!=blot_error::Error.none {return err;}let requirement=blot_check_types::Obligation{ ty:pack, kind:blot_check_types::ObligationKind.contract, source:source, identity:identity, explicit:true, .. };if self_.closed_type_variables && !self_.implicit_row_parameters && self_.current==0 && !self_.checking_implementation.present {var code=Code.missing_implementation;let open,err=self_.requirementOpen(requirement);if err!=blot_error::Error.none {return err;}if open {code=Code.missing_predicate;}let err=self_.diagnostic(code,source);if err!=blot_error::Error.none {return err;}}let err=self_.appendPending(PendingObligation{ value:requirement, owner:self_.current, suspended:true, .. });if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
recursive fn normalizeAssociatedExpansion(self_:Engine&,member:ContractMember,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,arguments:const u32[:],old:const u32[:],fresh:const u32[:],old_rows:const u32[:],fresh_rows:const u32[:],member_index:u32)->u32,blot_error::Error {let expanded,err=self_.types.substituteWithRows(member.root,old,fresh,old_rows,fresh_rows);if err!=blot_error::Error.none {return 0,err;}let normalized,err=self_.normalizeAssociatedNode(expanded,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}let span,err=self_.types.saveList(arguments);if err!=blot_error::Error.none {return 0,err;}let err=blot_support_pooled_buffer::push(memo.projections,ProjectionMemo{member:member_index,arguments:span,result:normalized, ..},projection_memo_values);return normalized,err;}
recursive fn normalizeAssociatedRow(self_:Engine&,root:u32,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64)->u32,blot_error::Error {let scalar_lookup_44 .= memo.rows.get(root);if scalar_lookup_44 {let known:u32=scalar_lookup_44;return known,blot_error::Error.none;}if depth>=256 {return 0,blot_error::Error.type_limit;}let id,err=self_.types.resolveEffects(root,0);if err!=blot_error::Error.none {return 0,err;}let row=self_.types.row(id);let labels=equation_type_ids.alloc_slice(row.labels.len);let type_span_37=checkedRowLabels(self_.types,id);for index in 0..(type_span_37.len as i64) {let value=self_.types.effects.list(type_span_37)[index];labels[index]=value;}let result,error=normalizeAssociatedLabels(self_,id,row,source,requirements,memo,active,depth,labels);equation_type_ids.free_slice(labels);if error!=blot_error::Error.none {return 0,error;}memo.rows.insert(root,result,associated_map_slots);return result,blot_error::Error.none;}
recursive fn normalizeAssociatedLabels(self_:Engine&,id:u32,row:blot_check_effects::Row,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,labels:u32[:])->u32,blot_error::Error {var changed=false;for &label in labels {let err=self_.types.chargeProjection();if err!=blot_error::Error.none {return 0,err;}let operation=self_.types.operation(label);let arguments=equation_type_ids.alloc_slice(self_.types.operationArguments(label).len);let type_span_38=checkedOperationArguments(self_.types,label);for index in 0..(type_span_38.len as i64) {let value=self_.types.list(type_span_38)[index];arguments[index]=value;}let next,error=normalizeAssociatedOperation(self_,operation,source,requirements,memo,active,depth,arguments);equation_type_ids.free_slice(arguments);if error!=blot_error::Error.none {return 0,error;}changed=changed || next!=label;label=next;}if !changed {return id,blot_error::Error.none;}let result,err=self_.types.effects.rowAt(labels,row.tail,row.cursor);return result,blot_check_types::effectError(err);}
recursive fn normalizeAssociatedOperation(self_:Engine&,operation:blot_check_types::Operation,source:u32,requirements:bool,memo:AssociatedMemo&,active:IdBuffer&,depth:i64,arguments:u32[:])->u32,blot_error::Error {for &argument in arguments {let root,err=self_.normalizeAssociatedNode(argument,source,requirements,memo,active,depth+1);if err!=blot_error::Error.none {return 0,err;}argument=root;}return self_.types.internScopedOperation(operation.identity,operation.instance,arguments);}
fn validateMemberRequirements(self_:Engine&,index:u32)->blot_error::Error {let member=self_.contract_members[index];if member.root==0 || member.contract.unit!=self_.unit {return blot_error::Error.none;}let contract_index:u32={let scalar_lookup_45 .= self_.catalogs.contract_identities.get(member.contract);assert(scalar_lookup_45!=null);let scalar_value_45:u32=scalar_lookup_45;scalar_value_45};let contract=self_.contracts[contract_index];let source:u32={let scalar_lookup_46 .= self_.member_sources.get(index);assert(scalar_lookup_46!=null);let scalar_value_46:u32=scalar_lookup_46;scalar_value_46};let start=self_.pending.len;let err=validateMemberRequirementsBody(self_,member,contract,source,start);self_.pending.resize(start);return err;}
fn validateMemberRequirementsBody(self_:Engine&,member:ContractMember,contract:Contract,source:u32,start:i64)->blot_error::Error {let normalized,err=self_.normalizeAssociated(member.root,source,true);if err!=blot_error::Error.none {return err;}var cursor=start;while cursor<self_.pending.len {let pending=self_.pending[cursor];let wanted=pending.value;if wanted.kind==blot_check_types::ObligationKind.contract && wanted.identity==contract.identity {cursor+=1;continue;}var supplied=false;for given in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {let same,err=self_.unifyRequirement(wanted,given);if err!=blot_error::Error.none {return err;}if same {supplied=true;break;}}if supplied {cursor+=1;continue;}let open,err=self_.requirementOpen(wanted);if err!=blot_error::Error.none {return err;}if open || wanted.kind==blot_check_types::ObligationKind.contract {let err=self_.diagnostic(Code.missing_predicate,source);if err!=blot_error::Error.none {return err;}cursor+=1;continue;}self_.pending[cursor].suspended=false;let attempted,err=self_.attemptPending(cursor,self_.pending[cursor]);if err!=blot_error::Error.none {return err;}if !self_.pending[cursor].solved {let err=self_.diagnostic(Code.missing_predicate,source);if err!=blot_error::Error.none {return err;}}cursor+=1;}return blot_error::Error.none;}
fn constructorStorageType(self_:Engine&,index:u32)->u32,blot_error::Error {return self_.constructorUse(index,true);}
fn canonicalRecordType(self_:Engine&,record:blot_check_types::Node)->u32,blot_error::Error {if record.b==1 {return self_.types.recordField(record,0).ty,blot_error::Error.none;}let fields=equation_type_ids.alloc_slice(record.b);for index in 0..record.b {fields[index]=self_.types.recordField(record,index).ty;}let root,err=self_.types.product(fields);equation_type_ids.free_slice(fields);return root,err;}
fn constructorRoot(self_:Engine&,metadata:Constructor,storage:bool)->u32,blot_error::Error {
    var root=metadata.scheme.root;
    if metadata.deferred_result {
        let result,err=self_.types.nominal(self_.nominals[metadata.nominal].identity,[]);
        if err!=blot_error::Error.none || metadata.payload==0 {return result,err;}
        if storage && self_.types.node(metadata.payload).tag==blot_check_types::Tag.record {root=metadata.payload;}
        return self_.types.function(root,result);
    }
    if storage && metadata.payload!=0 && self_.types.node(metadata.payload).tag==blot_check_types::Tag.record {
        return self_.types.function(metadata.payload,self_.types.node(root).b);
    }
    return root,blot_error::Error.none;
}
fn constructorUse(self_:Engine&,index:u32,storage:bool)->u32,blot_error::Error {let metadata=self_.constructors[index];let principal=metadata.scheme;let root,err=self_.constructorRoot(metadata,storage);if err!=blot_error::Error.none {return 0,err;}let old=equation_type_ids.alloc_slice(principal.variables.len);let type_span_39=checkedTypeList(self_.types,principal.variables);for index in 0..(type_span_39.len as i64) {let value=self_.types.list(type_span_39)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let result,err=constructorUseVariables(self_,root,old,fresh);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,err;}
fn constructorUseVariables(self_:Engine&,root:u32,old:const u32[:],fresh:u32[:])->u32,blot_error::Error {for &id in fresh {let value,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}id=value;}return self_.types.substitute(root,old,fresh);}
fn dataHeaders(self_:Engine&)->blot_error::Error {let ast_walk_20_count=self_.tree.roots.items.len;for ast_walk_20_index in 0..ast_walk_20_count {let id=self_.tree.roots.items[ast_walk_20_index];let node=self_.tree.node(id);if node.tag!=blot_parse_ast::tag_data_decl && node.tag!=blot_parse_ast::tag_type_alias_decl {continue;}let key=Qualified{namespace_:0,member:node.a, ..};if self_.catalogs.nominal_names.contains(key) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}let index=self_.nominals.len as u32;let traits=blot_parse_ast::declaration_traits(self_.tree,id);var identity=Identity{unit:self_.unit,decl:index, ..};if traits.is_opaque {identity.decl=node.a|blot_check_types::opaque_name_bit;}self_.nominals.push(Nominal{private:traits.private,is_opaque:traits.is_opaque,declaration:id,identity:identity,name:node.a,parameters:blot_check_types::List{..},variables:blot_check_types::List{..}, ..});self_.catalogs.nominal_identities.insert(identity,index);self_.catalogs.nominal_names.insert(key,index);}for ordinal in 1..self_.nominals.len {let nominal=self_.nominals[ordinal];if nominal.identity.unit!=self_.unit {continue;}let node=self_.tree.node(nominal.declaration);let meta=checkedAstRange(self_.tree,node.c,node.c+4);if node.tag!=blot_parse_ast::tag_data_decl && self_.tree.list(meta)[3]!=0 {let err=self_.diagnostic(Code.unsupported_attribute,nominal.declaration);if err!=blot_error::Error.none {return err;}}self_.type_env.clear();self_.row_env.clear();let parameters=equation_type_ids.alloc_slice(self_.tree.list(meta)[1]);let patterns=equation_type_ids.alloc_slice(self_.tree.list(meta)[1]);let err=dataHeaderParameters(self_,ordinal as u32,meta,parameters,patterns);equation_type_ids.free_slice(patterns);equation_type_ids.free_slice(parameters);if err!=blot_error::Error.none {return err;}}self_.type_env.clear();self_.row_env.clear();return blot_error::Error.none;}
fn dataHeaderParameters(self_:Engine&,index:u32,meta:blot_parse_ast::List,parameters:u32[:],patterns:u32[:])->blot_error::Error {let syntax_source_17=blot_parse_ast::List{self_.tree.list(meta)[0],self_.tree.list(meta)[1], ..};let syntax_count_17=self_.tree.list(syntax_source_17).len;for ordinal in 0..syntax_count_17 {let parameter=self_.tree.list(syntax_source_17)[ordinal];let parsed,err=self_.parameterAnnotation(parameter,0);if err!=blot_error::Error.none {return err;}parameters[ordinal]=parsed.ty;patterns[ordinal]=parsed.pattern;}let names=equation_type_ids.alloc_slice(self_.type_env.items.len);let variables=equation_type_ids.alloc_slice(names.len);for entry,ordinal in self_.type_env.items {names[ordinal]=entry.name;variables[ordinal]=entry.ty;}let err=dataHeaderLists(self_,index,parameters,patterns,names,variables);equation_type_ids.free_slice(variables);equation_type_ids.free_slice(names);return err;}
fn dataHeaderLists(self_:Engine&,index:u32,parameters:const u32[:],patterns:const u32[:],names:const u32[:],variables:const u32[:])->blot_error::Error {let list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return err;}self_.nominals[index].parameters=list;let list,err=self_.parameter_patterns.saveList(patterns);if err!=blot_error::Error.none {return err;}self_.nominals[index].patterns=list;let list,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return err;}self_.nominals[index].variables=list;let list,err=self_.types.saveList(names);if err!=blot_error::Error.none {return err;}self_.nominals[index].parameter_names=list;return blot_error::Error.none;}
recursive fn resolveAlias(self_:Engine&,index:u32)->u32,blot_error::Error {let nominal=self_.nominals[index];if nominal.alias!=0 {return nominal.alias,blot_error::Error.none;}if nominal.identity.unit!=self_.unit || self_.tree.node(nominal.declaration).tag!=blot_parse_ast::tag_type_alias_decl {return 0,blot_error::Error.none;}if self_.active_aliases.contains(index) {let err=self_.diagnostic(Code.recursive_type_alias,nominal.declaration);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}if self_.active_aliases.count>=256 {return 0,blot_error::Error.type_limit;}self_.active_aliases.insert(index,true);let saved_defer=self_.defer_associated;let saved_types=self_.type_env;let saved_rows=self_.row_env;let saved_closed=self_.closed_type_variables;let saved_alias=self_.implicit_row_parameters;self_.defer_associated=true;self_.type_env=TypeEnvironment{..};self_.row_env=RowEnvironment{..};self_.closed_type_variables=true;self_.implicit_row_parameters=true;let target,err=resolveAliasBody(self_,index,nominal);self_.type_env.deinit();self_.row_env.deinit();self_.type_env=canonicalTypeEnvironment(saved_types);self_.row_env=canonicalRowEnvironment(saved_rows);self_.closed_type_variables=saved_closed;self_.implicit_row_parameters=saved_alias;self_.defer_associated=saved_defer;self_.active_aliases.remove(index);return target,err;}
recursive fn resolveAliasBody(self_:Engine&,index:u32,nominal:Nominal)->u32,blot_error::Error {for parameter in 0..nominal.variables.len {let err=self_.type_env.append(Engine_type_env{name:self_.types.list(nominal.parameter_names)[parameter],ty:self_.types.list(nominal.variables)[parameter], ..});if err!=blot_error::Error.none {return 0,err;}}let target,err=self_.annotation(self_.tree.node(nominal.declaration).b);if err!=blot_error::Error.none {return 0,err;}let rows,err=self_.types.freeRowVariables(target);if err!=blot_error::Error.none {return 0,err;}let span,err=self_.types.saveList(rows);if err!=blot_error::Error.none {return 0,err;}self_.nominals[index].alias_rows=span;self_.nominals[index].alias=target;return target,blot_error::Error.none;}
recursive fn aliasInstance(self_:Engine&,index:u32,old:const u32[:],fresh:const u32[:],source:u32)->blot_support::Option<u32>,blot_error::Error {let alias,err=self_.resolveAlias(index);if err!=blot_error::Error.none || alias==0 {return blot_support::none<u32>(),err;}if self_.closed_type_variables && !self_.implicit_row_parameters && self_.nominals[index].alias_rows.len!=0 {let err=self_.diagnostic(Code.unbound_alias_row,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}let rows=equation_type_ids.alloc_slice(self_.nominals[index].alias_rows.len);let type_span_40=checkedTypeList(self_.types,self_.nominals[index].alias_rows);for ordinal in 0..(type_span_40.len as i64) {let value=self_.types.list(type_span_40)[ordinal];rows[ordinal]=value;}let fresh_rows=equation_type_ids.alloc_slice(rows.len);let result,error=aliasInstanceRows(self_,alias,old,fresh,source,rows,fresh_rows);equation_type_ids.free_slice(fresh_rows);equation_type_ids.free_slice(rows);return result,error;}
recursive fn aliasInstanceRows(self_:Engine&,alias:u32,old:const u32[:],fresh:const u32[:],source:u32,rows:const u32[:],fresh_rows:u32[:])->blot_support::Option<u32>,blot_error::Error {for &row in fresh_rows {let id,err=self_.types.freshEffects();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}row=id;}let expanded,err=self_.types.substituteWithRows(alias,old,fresh,rows,fresh_rows);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if self_.defer_associated || !self_.has_associated_types {return blot_support::some(expanded),blot_error::Error.none;}let root,err=self_.normalizeAssociated(expanded,source,true);return blot_support::some(root),err;}
fn dataBodies(self_:Engine&)->blot_error::Error {self_.closed_type_variables=true;let err=dataBodiesClosed(self_);self_.closed_type_variables=false;return err;}
fn dataBodiesClosed(self_:Engine&)->blot_error::Error {var ctor_ordinal:u32=0;var index:i64=1;while index<self_.nominals.len {let nominal=self_.nominals[index];if nominal.identity.unit!=self_.unit {index+=1;continue;}if self_.tree.node(nominal.declaration).tag==blot_parse_ast::tag_type_alias_decl {let root,err=self_.resolveAlias(index as u32);if err!=blot_error::Error.none {return err;}index+=1;continue;}self_.type_env.clear();self_.row_env.clear();for ordinal in 0..nominal.variables.len {let err=self_.type_env.append(Engine_type_env{name:self_.types.list(nominal.parameter_names)[ordinal],ty:self_.types.list(nominal.variables)[ordinal], ..});if err!=blot_error::Error.none {return err;}}let args=equation_type_ids.alloc_slice(nominal.parameters.len);let type_span_41=checkedTypeList(self_.types,nominal.parameters);for ordinal in 0..(type_span_41.len as i64) {let value=self_.types.list(type_span_41)[ordinal];args[ordinal]=value;}let result,err=self_.types.nominal(nominal.identity,args);equation_type_ids.free_slice(args);if err!=blot_error::Error.none {return err;}var constructors=IdBuffer{..};let error=dataConstructors(self_,index as u32,nominal,result,constructors,ctor_ordinal);constructors.deinit(equation_type_ids);if error!=blot_error::Error.none {return error;}index+=1;}
 self_.type_env.clear();self_.row_env.clear();return blot_error::Error.none;}
fn dataConstructors(self_:Engine&,index:u32,nominal:Nominal,result:u32,constructors:IdBuffer&,ctor_ordinal:u32&)->blot_error::Error {let declaration=self_.tree.node(nominal.declaration);let syntax_source_18=declaration.b;let syntax_count_18=self_.tree.children(syntax_source_18).len;for tag in 0..syntax_count_18 {let id=self_.tree.children(syntax_source_18)[tag];let node=self_.tree.node(id);let key=self_.catalogKey(node.a);if self_.catalogs.constructor_names.contains(key) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}var payload:u32=0;if node.b!=0 {let root,err=self_.constructorPayloadAnnotation(node.b);if err!=blot_error::Error.none {return err;}payload=root;}if payload!=0 {let shape=self_.types.node(payload);if !nominal.is_opaque && shape.tag==blot_check_types::Tag.record && shape.b==0 {payload=0;}}let storage=self_.types.node(payload);var parameter=payload;if !nominal.is_opaque && payload!=0 && storage.tag==blot_check_types::Tag.record {let root,err=self_.canonicalRecordType(storage);if err!=blot_error::Error.none {return err;}parameter=root;}var ty=result;if payload!=0 {let root,err=self_.types.function(parameter,result);if err!=blot_error::Error.none {return err;}ty=root;}let constructor=self_.constructors.len as u32;ctor_ordinal+=1;let ctor_id=Identity{self_.unit,0x10000000|ctor_ordinal, ..};let declared_record=!nominal.is_opaque && node.b!=0 && self_.tree.node(node.b).tag==blot_parse_ast::tag_type_record && self_.tree.type_conversion_origin(node.b)==self_.tree.span(node.b).start;self_.constructors.push(Constructor{ private:nominal.private || nominal.is_opaque, identity:ctor_id, nominal:index, tag:tag as u32, name:node.a, scheme:blot_check_types::Scheme{root:ty,variables:nominal.variables, ..}, payload:payload, declared_record:declared_record, .. });self_.catalogs.constructor_identities.insert(ctor_id,constructor);self_.catalogs.constructor_names.insert(key,constructor);let err=constructors.append(constructor);if err!=blot_error::Error.none {return err;}self_.constructor_resolved[id]=constructor;}let span,err=self_.types.saveList(constructors.items);if err!=blot_error::Error.none {return err;}self_.nominals[index].constructors=span;return blot_error::Error.none;}
fn effectHeaders(self_:Engine&)->blot_error::Error {var family_ordinal:u32=0;var template_ordinal:u32=0;let ast_walk_21_count=self_.tree.roots.items.len;for ast_walk_21_index in 0..ast_walk_21_count {let id=self_.tree.roots.items[ast_walk_21_index];let node=self_.tree.node(id);if node.tag!=blot_parse_ast::tag_effect_decl && node.tag!=blot_parse_ast::tag_effect_type_decl {continue;}let attributes=checkedAstRange(self_.tree,node.c,self_.tree.extra.items.len);var attribute_index:i64=3;if node.tag==blot_parse_ast::tag_effect_decl {attribute_index=1;}if self_.tree.list(attributes)[attribute_index]!=0 {let err=self_.diagnostic(Code.unsupported_attribute,id);if err!=blot_error::Error.none {return err;}}if self_.pool.get(node.a)=="Foreign" {let err=self_.diagnostic(Code.sealed_effect,id);if err!=blot_error::Error.none {return err;}continue;}let key=self_.catalogKey(node.a);if self_.catalogs.effect_family_names.contains(key) || self_.catalogs.nominal_names.contains(key) || self_.hasGlobal(node.a) {let err=self_.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}self_.type_env.clear();self_.row_env.clear();var parameters=IdBuffer{..};var patterns=IdBuffer{..};let err=effectHeaderParameters(self_,id,node,key,parameters,patterns,family_ordinal,template_ordinal);patterns.deinit(equation_type_ids);parameters.deinit(equation_type_ids);if err!=blot_error::Error.none {return err;}}self_.type_env.clear();self_.row_env.clear();return blot_error::Error.none;}
fn effectHeaderParameters(self_:Engine&,id:u32,node:blot_parse_ast::Node,key:Qualified,parameters:IdBuffer&,patterns:IdBuffer&,family_ordinal:u32&,template_ordinal:u32&)->blot_error::Error {if node.tag==blot_parse_ast::tag_effect_type_decl {let meta=checkedAstRange(self_.tree,node.c,node.c+4);let syntax_source_19=blot_parse_ast::List{self_.tree.list(meta)[0],self_.tree.list(meta)[1], ..};let syntax_count_19=self_.tree.list(syntax_source_19).len;for syntax_index_19 in 0..syntax_count_19 {let parameter=self_.tree.list(syntax_source_19)[syntax_index_19];let parsed,err=self_.parameterAnnotation(parameter,0);if err!=blot_error::Error.none {return err;}let err=parameters.append(parsed.ty);if err!=blot_error::Error.none {return err;}let err=patterns.append(parsed.pattern);if err!=blot_error::Error.none {return err;}}}let names=equation_type_ids.alloc_slice(self_.type_env.items.len);let variables=equation_type_ids.alloc_slice(names.len);for entry,ordinal in self_.type_env.items {names[ordinal]=entry.name;variables[ordinal]=entry.ty;}let err=effectHeaderFamily(self_,id,node,key,parameters.items,patterns.items,names,variables,family_ordinal,template_ordinal);equation_type_ids.free_slice(variables);equation_type_ids.free_slice(names);return err;}
fn effectHeaderFamily(self_:Engine&,id:u32,node:blot_parse_ast::Node,key:Qualified,parameters:const u32[:],patterns:const u32[:],names:const u32[:],variables:const u32[:],family_ordinal:u32&,template_ordinal:u32&)->blot_error::Error {if self_.effect_families.len==0xffffffff {return blot_error::Error.type_limit;}let family=self_.effect_families.len as u32;family_ordinal+=1;let family_id=Identity{self_.unit,0x20000000|family_ordinal, ..};let pattern_list,err=self_.parameter_patterns.saveList(patterns);if err!=blot_error::Error.none {return err;}let parameter_list,err=self_.types.saveList(parameters);if err!=blot_error::Error.none {return err;}let variable_list,err=self_.types.saveList(variables);if err!=blot_error::Error.none {return err;}let name_list,err=self_.types.saveList(names);if err!=blot_error::Error.none {return err;}let __alias_field_14_private: bool = blot_parse_ast::declaration_traits(self_.tree,id).private; let __alias_field_15_identity: blot_reuse_principal_interface::Identity = family_id; let __alias_field_16_name: u32 = node.a; let __alias_field_17_callable: bool = self_.tree.node(node.b).tag!=blot_parse_ast::tag_effect_operations; let __alias_field_18_patterns: blot_reuse_principal_interface::List = pattern_list; let __alias_field_19_parameters: blot_reuse_principal_interface::List = parameter_list; let __alias_field_20_variables: blot_reuse_principal_interface::List = variable_list; let __alias_field_21_parameter_names: blot_reuse_principal_interface::List = name_list; self_.effect_families.push(EffectFamily{ private: __alias_field_14_private, identity: __alias_field_15_identity, name: __alias_field_16_name, callable: __alias_field_17_callable, parameters: __alias_field_19_parameters, variables: __alias_field_20_variables, patterns: __alias_field_18_patterns, parameter_names: __alias_field_21_parameter_names, .. });self_.catalogs.effect_family_names.insert(key,family);self_.catalogs.effect_family_identities.insert(family_id,family);var operations=IdBuffer{..};let error=effectHeaderOperations(self_,id,node,key,family,operations,template_ordinal);operations.deinit(equation_type_ids);return error;}
fn effectHeaderOperations(self_:Engine&,id:u32,node:blot_parse_ast::Node,key:Qualified,family:u32,operations:IdBuffer&,template_ordinal:u32&)->blot_error::Error {if self_.tree.node(node.b).tag==blot_parse_ast::tag_effect_operations {let syntax_source_20=node.b;let syntax_count_20=self_.tree.children(syntax_source_20).len;for syntax_index_20 in 0..syntax_count_20 {let member=self_.tree.children(syntax_source_20)[syntax_index_20];let operation=self_.tree.node(member);let key=EffectMember{family:family,member:operation.a, ..};if self_.catalogs.effect_members.contains(key) {let err=self_.diagnostic(Code.duplicate_name,member);if err!=blot_error::Error.none {return err;}continue;}template_ordinal+=1;let template,err=self_.effectSignature(family,member,0x30000000|template_ordinal,operation.a,operation.b);if err!=blot_error::Error.none {return err;}self_.catalogs.effect_members.insert(key,template);let err=operations.append(template);if err!=blot_error::Error.none {return err;}}}else {template_ordinal+=1;let template,err=self_.effectSignature(family,id,0x30000000|template_ordinal,node.a,node.b);if err!=blot_error::Error.none {return err;}self_.catalogs.effect_operation_names.insert(key,template);let err=operations.append(template);if err!=blot_error::Error.none {return err;}}let list,err=self_.types.saveList(operations.items);if err!=blot_error::Error.none {return err;}self_.effect_families[family].operations=list;return blot_error::Error.none;}
fn effectSignature(self_:Engine&,family:u32,ast_id:u32,identity:u32,name:u32,annotation:u32)->u32,blot_error::Error {let old=self_.closed_type_variables;self_.closed_type_variables=true;let result,err=effectSignatureClosed(self_,family,ast_id,identity,name,annotation);self_.closed_type_variables=old;return result,err;}
fn effectSignatureClosed(self_:Engine&,family:u32,ast_id:u32,identity:u32,name:u32,annotation:u32)->u32,blot_error::Error {let syntax=self_.tree.node(annotation);var signature:u32=0;if syntax.tag==blot_parse_ast::tag_type_function && syntax.c!=0 {let err=self_.diagnostic(Code.operation_signature,annotation);if err!=blot_error::Error.none {return 0,err;}let input,err=self_.annotation(syntax.a);if err!=blot_error::Error.none {return 0,err;}let output,err=self_.annotation(syntax.b);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.types.function(input,output);if err!=blot_error::Error.none {return 0,err;}signature=root;}else {let root,err=self_.annotation(annotation);if err!=blot_error::Error.none {return 0,err;}signature=root;}let function=self_.types.node(signature);if function.tag!=blot_check_types::Tag.function {var code=Code.unsupported_type;var source=annotation;if self_.source_validation {code=Code.operation_signature;source=ast_id;}let err=self_.diagnostic(code,source);if err!=blot_error::Error.none {return 0,err;}}if self_.effect_templates.len==0xffffffff {return 0,blot_error::Error.type_limit;}let index=self_.effect_templates.len as u32;var parameter=blot_check_types::unit;var result=signature;if function.tag==blot_check_types::Tag.function {parameter=function.a;result=function.b;}self_.effect_templates.push(EffectTemplate{identity:Identity{self_.unit,identity, ..},family:family,name:name,parameter:parameter,result:result, ..});self_.catalogs.effect_template_identities.insert(Identity{self_.unit,identity, ..},index);return index,blot_error::Error.none;}
fn textCatalogKey(self_:const Engine&,text:const u8[:])->blot_support::Option<Qualified> {let separator=firstDot(text);if !separator.present {let member,known=self_.pool.lookup(text);if !known {return blot_support::none<Qualified>();}return blot_support::some(Qualified{namespace_:0,member:member, ..});}let namespace_,known=self_.pool.lookup(text[..separator.value]);if !known {return blot_support::none<Qualified>();}let member,known=self_.pool.lookup(text[separator.value+1..]);if !known {return blot_support::none<Qualified>();}return blot_support::some(Qualified{namespace_:namespace_,member:member, ..});}
fn operationTemplate(self_:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {if self_.lookup(name).present {return blot_support::none<u32>(),blot_error::Error.none;}let global,err=self_.globalBinding(name);if err!=blot_error::Error.none || global.present {return blot_support::none<u32>(),err;}let text=self_.pool.get(name);let separator=firstDot(text);var end=text.len;if separator.present {end=separator.value;}let root,known=self_.pool.lookup(text[..end]);if known && (self_.lookup(root).present || self_.hasGlobal(root)) {return blot_support::none<u32>(),blot_error::Error.none;}return self_.catalogOperationTemplate(name),blot_error::Error.none;}
fn catalogOperationTemplate(self_:const Engine&,name:u32)->blot_support::Option<u32> {let scalar_lookup_47 .= self_.catalogs.effect_operation_names.get(self_.catalogKey(name));if scalar_lookup_47 {let single:u32=scalar_lookup_47;return blot_support::some(single);}let text=self_.pool.get(name);let separator=lastDot(text);if !separator.present {return blot_support::none<u32>();}let key=self_.textCatalogKey(text[..separator.value]);if !key.present {return blot_support::none<u32>();}let family:u32={let scalar_lookup_48 .= self_.catalogs.effect_family_names.get(key.value);if !scalar_lookup_48 {return blot_support::none<u32>();}let scalar_value_48:u32=scalar_lookup_48;scalar_value_48};let member,known=self_.pool.lookup(text[separator.value+1..]);if !known {return blot_support::none<u32>();}let result:u32={let scalar_lookup_49 .= self_.catalogs.effect_members.get(EffectMember{family:family,member:member, ..});if !scalar_lookup_49 {return blot_support::none<u32>();}let scalar_value_49:u32=scalar_lookup_49;scalar_value_49};return blot_support::some(result);}
recursive fn operationValue(self_:Engine&,source:u32,index:u32,syntax:blot_support::Option<const u32[:]>)->u32,blot_error::Error {let template=self_.effect_templates[index];let family=self_.effect_families[template.family];let old=equation_type_ids.alloc_slice(family.variables.len);let type_span_42=checkedTypeList(self_.types,family.variables);for ordinal in 0..(type_span_42.len as i64) {let value=self_.types.list(type_span_42)[ordinal];old[ordinal]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let shapes=equation_type_ids.alloc_slice(family.parameters.len);let type_span_43=checkedTypeList(self_.types,family.parameters);for ordinal in 0..(type_span_43.len as i64) {let value=self_.types.list(type_span_43)[ordinal];shapes[ordinal]=value;}let arguments=equation_type_ids.alloc_slice(shapes.len);let result,err=operationValueArguments(self_,source,index,template,family,syntax,old,fresh,shapes,arguments);equation_type_ids.free_slice(arguments);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,err;}
recursive fn operationValueArguments(self_:Engine&,source:u32,index:u32,template:EffectTemplate,family:EffectFamily,syntax:blot_support::Option<const u32[:]>,old:const u32[:],fresh:u32[:],shapes:const u32[:],arguments:u32[:])->u32,blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}if syntax.present {if syntax.value.len!=shapes.len {let err=self_.diagnostic(Code.effect_arity,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}for argument,ordinal in syntax.value {let actual,err=self_.parameterArgument(self_.parameter_patterns.list(family.patterns)[ordinal],argument,false,0);if err!=blot_error::Error.none {return 0,err;}let selected,err=self_.types.substitute(shapes[ordinal],old,fresh);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(selected,actual,argument);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(selected,0);if err!=blot_error::Error.none {return 0,err;}arguments[ordinal]=resolved;}}else {for shape,ordinal in shapes {let root,err=self_.types.substitute(shape,old,fresh);if err!=blot_error::Error.none {return 0,err;}arguments[ordinal]=root;}}let parameter,err=self_.types.substitute(template.parameter,old,fresh);if err!=blot_error::Error.none {return 0,err;}let result,err=self_.types.substitute(template.result,old,fresh);if err!=blot_error::Error.none {return 0,err;}let latent,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}var row=latent;var matched_ambient=false;if !syntax.present && shapes.len!=0 && self_.ambient!=0 {let amb_resolved,aerr=self_.types.resolveEffects(self_.ambient,0);if aerr!=blot_error::Error.none {return 0,aerr;}let amb_labels=checkedRowLabels(self_.types,amb_resolved);var match_count:i64=0;var matched_label:u32=0;for li in 0..(amb_labels.len as i64) {let lbl=self_.types.effects.list(amb_labels)[li];let op=self_.types.operation(lbl);if op.identity==template.identity && op.arguments.len==arguments.len {match_count+=1;matched_label=lbl;}}var fi=fork_outer_len;while match_count==0 && fi>fork_ambient_floor {fi-=1;let outer_amb=fork_outer_ambients[fi];if outer_amb==0 {continue;}let ores,oerr=self_.types.resolveEffects(outer_amb,0);if oerr!=blot_error::Error.none {return 0,oerr;}let olabels=checkedRowLabels(self_.types,ores);for li in 0..(olabels.len as i64) {let lbl=self_.types.effects.list(olabels)[li];let op=self_.types.operation(lbl);if op.identity==template.identity && op.arguments.len==arguments.len {match_count+=1;matched_label=lbl;}}}if match_count==1 {let op=self_.types.operation(matched_label);for ordinal in 0..arguments.len {let amb_arg=self_.types.list(op.arguments)[ordinal];let cerr=self_.constrain(arguments[ordinal],amb_arg,source);if cerr!=blot_error::Error.none {return 0,cerr;}}matched_ambient=true;}}var concrete=shapes.len==0 || syntax.present || matched_ambient;for &argument in arguments {let root,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return 0,err;}argument=root;if concrete {let closed,err=self_.types.equalClosed(root,root);if err!=blot_error::Error.none {return 0,err;}concrete=closed;}}if concrete {let label,err=self_.types.internOperation(template.identity,arguments);if err!=blot_error::Error.none {return 0,err;}let selected,err=self_.types.effects.row([label],self_.types.row(latent).tail);if err!=blot_error::Error.none {return 0,blot_check_types::effectError(err);}row=selected;}let signature,err=self_.types.functionWithEffects(parameter,result,row);if err!=blot_error::Error.none {return 0,err;}if self_.operation_uses.len==0xffffffff {return 0,blot_error::Error.type_limit;}let argument_list,err=self_.types.saveList(arguments);if err!=blot_error::Error.none {return 0,err;}self_.operation_uses.push(OperationUse{node:source,template:index,arguments:argument_list,signature:signature, ..});self_.operation_refs[source]=self_.operation_uses.len as u32;if !concrete {let pack,err=self_.types.product(arguments);if err!=blot_error::Error.none {return 0,err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:signature, kind:blot_check_types::ObligationKind.effect_operation, source:source, other:pack, signature:signature, identity:template.identity, .. }, owner:self_.current, direct:true, .. });if err!=blot_error::Error.none {return 0,err;}}return signature,blot_error::Error.none;}
fn builtinStateTemplate(self_:Engine&,read:bool)->u32,blot_error::Error {var identity=blot_check_types::builtin_state_write;if read {identity=blot_check_types::builtin_state_read;}let scalar_lookup_50 .= self_.catalogs.effect_template_identities.get(identity);if scalar_lookup_50 {let existing:u32=scalar_lookup_50;return existing,blot_error::Error.none;}if self_.effect_templates.len==0xffffffff {return 0,blot_error::Error.type_limit;}let state,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let index=self_.effect_templates.len as u32;var parameter=state;var result=blot_check_types::unit;if read {parameter=blot_check_types::unit;result=state;}self_.effect_templates.push(EffectTemplate{identity:identity,family:0,name:0,parameter:parameter,result:result, ..});self_.catalogs.effect_template_identities.insert(identity,index);return index,blot_error::Error.none;}
fn witnessResult(self_:Engine&,original:u32)->u32,blot_error::Error {var result=original;for ordinal in 0..1024 {let root,err=self_.types.resolve(result,0);if err!=blot_error::Error.none {return 0,err;}let node=self_.types.node(root);if node.tag!=blot_check_types::Tag.function {return result,blot_error::Error.none;}result=node.b;}return 0,blot_error::Error.type_limit;}
fn witnessType(self_:Engine&,operand:u32,source:u32)->u32,blot_error::Error {let known,err=self_.witnessResult(operand);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(known,0);if err!=blot_error::Error.none {return 0,err;}if self_.types.node(resolved).tag!=blot_check_types::Tag.variable {return known,blot_error::Error.none;}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:operand, kind:blot_check_types::ObligationKind.type_head, source:source, result:result, .. }, owner:self_.current, direct:true, .. });return result,err;}
recursive fn builtinStateApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {let syntax=self_.tree.node(id);if self_.tree.node(syntax.a).tag!=blot_parse_ast::tag_intrinsic {return blot_support::none<u32>(),blot_error::Error.none;}let name=self_.pool.get(self_.tree.node(syntax.a).a);let read=name=="@state.get";if !read && name!="@state.set" {return blot_support::none<u32>(),blot_error::Error.none;}let operand,err=self_.expression(syntax.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}var state=operand;if read {let root,err=self_.witnessType(operand,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}state=root;}let template,err=self_.builtinStateTemplate(read);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let identity=self_.effect_templates[template].identity;let latent,err=self_.types.freshEffects();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}var row=latent;let concrete,err=self_.types.equalClosed(state,state);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if concrete {let label,err=self_.types.internOperation(identity,[state]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let selected,err=self_.types.effects.row([label],self_.types.row(latent).tail);if err!=blot_error::Error.none {return blot_support::none<u32>(),blot_check_types::effectError(err);}row=selected;}var result=blot_check_types::unit;var parameter=state;var call=OperationUse_call.state_write;if read {result=state;parameter=blot_check_types::unit;call=OperationUse_call.state_read;}let signature,err=self_.types.functionWithEffects(parameter,result,row);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if self_.operation_uses.len==0xffffffff {return blot_support::none<u32>(),blot_error::Error.type_limit;}let arguments,err=self_.types.saveList([state]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.operation_uses.push(OperationUse{node:id,template:template,arguments:arguments,signature:signature,call:call,operand:syntax.b, ..});self_.operation_refs[id]=self_.operation_uses.len as u32;if !concrete {let product,err=self_.types.product([state]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:signature, kind:blot_check_types::ObligationKind.effect_operation, source:id, other:product, signature:signature, identity:identity, .. }, owner:self_.current, direct:true, .. });if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}let err=self_.constrainEffects(row,self_.ambient,id);return blot_support::some(result),err;}
fn reflectionType(self_:Engine&,descriptor:bool)->u32,blot_error::Error {var identity=blot_check_types::effect_set_identity;if descriptor {identity=blot_check_types::effect_descriptor_identity;}return self_.types.nominal(identity,[]);}
recursive fn reflectionOperation(self_:Engine&,original:u32,required:bool)->blot_support::Option<u32>,blot_error::Error {var id=original;while self_.tree.node(id).tag==blot_parse_ast::tag_group {id=self_.tree.node(id).a;}let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_name && self_.pool.get(node.a)=="Foreign" {return blot_support::some(blot_check_types::foreign_operation),blot_error::Error.none;}let expression,err=self_.expression(original);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let selected=self_.operation_refs[id];if selected==0 {if required {let err=self_.diagnostic(Code.operation_target,original);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}return blot_support::none<u32>(),blot_error::Error.none;}let use=self_.operation_uses[selected-1];if use.instance.decl!=0 {let err=self_.diagnostic(Code.open_effect_descriptor,original);return blot_support::none<u32>(),err;}let arguments=equation_type_ids.alloc_slice(use.arguments.len);let type_span_44=checkedTypeList(self_.types,use.arguments);for index in 0..(type_span_44.len as i64) {let value=self_.types.list(type_span_44)[index];arguments[index]=value;}let result,err=reflectionOperationArguments(self_,original,use,arguments);equation_type_ids.free_slice(arguments);return result,err;}
fn reflectionOperationArguments(self_:Engine&,original:u32,use:OperationUse,arguments:const u32[:])->blot_support::Option<u32>,blot_error::Error {for argument in arguments {let closed,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let equal,err=self_.types.equalClosed(closed,closed);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if !equal {let err=self_.diagnostic(Code.open_effect_descriptor,original);return blot_support::none<u32>(),err;}}let label,err=self_.types.internOperation(self_.effect_templates[use.template].identity,arguments);return blot_support::some(label),err;}
fn reflectDescriptor(self_:Engine&,original:u32,label:u32)->u32,blot_error::Error {var id=original;while self_.tree.node(id).tag==blot_parse_ast::tag_group {id=self_.tree.node(id).a;}self_.reflections.push(Reflection{node:id,kind:ReflectionKind.descriptor,label:label, ..});let ty,err=self_.reflectionType(true);if err!=blot_error::Error.none {return 0,err;}self_.expr_types[id]=ty;self_.expr_types[original]=ty;return ty,blot_error::Error.none;}
recursive fn storageApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;var backwards:u32[3]=[0;3];var count:i64=0;while self_.tree.node(head).tag==blot_parse_ast::tag_apply {let application=self_.tree.node(head);if count<backwards.len {backwards[count]=application.b;}count+=1;head=application.a;}let syntax=self_.tree.node(head);var operation=blot_support::none<blot_check_storage_ops::Op>();var from_intrinsic=false;if syntax.tag==blot_parse_ast::tag_intrinsic {operation=blot_check_storage_ops::lookup(self_.pool.get(syntax.a));from_intrinsic=true;}else if syntax.tag==blot_parse_ast::tag_name {let text=self_.pool.get(syntax.a);if (text=="freeze" || text=="copy") && !self_.lookup(syntax.a).present {let existing,err=self_.globalBinding(syntax.a);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if !existing.present {if text=="freeze" {operation=blot_support::some(blot_check_storage_ops::Op.share);}else {operation=blot_support::some(blot_check_storage_ops::Op.copy);}}}}if !operation.present {return blot_support::none<u32>(),blot_error::Error.none;}let op=operation.value;if count!=blot_check_storage_ops::arity(op) {let err=self_.diagnostic(Code.call_arity,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}let first=backwards[count-1];let input,err=self_.expression(first);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let resolved,err=self_.types.resolve(input,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let kind=blot_check_storage_types::info(self_.types,resolved);let element=blot_check_storage_types::readableElement(self_.types,resolved);let result,err=storageOperation(self_,op,first,input,resolved,kind,element,from_intrinsic,backwards[..count]);return blot_support::some(result),err;}
recursive fn storageOperation(self_:Engine&,op:blot_check_storage_ops::Op,first:u32,input:u32,resolved:u32,kind:blot_support::Option<blot_check_storage_types::Info>,element:blot_support::Option<u32>,from_intrinsic:bool,backwards:const u32[:])->u32,blot_error::Error {var result=blot_check_types::unit;var valid=true;match op {
 ref=>{var place=first;while self_.tree.node(place).tag==blot_parse_ast::tag_group {place=self_.tree.node(place).a;}valid=self_.tree.node(place).tag==blot_parse_ast::tag_name || self_.tree.node(place).tag==blot_parse_ast::tag_field_access;let root,err=blot_check_storage_types::make(self_.types,blot_check_storage_types::ref,input);if err!=blot_error::Error.none {return 0,err;}result=root;},
 at,link,view=>{valid=element.present && (op!=blot_check_storage_ops::Op.link || !kind.present || kind.value.kind==blot_check_storage_types::sized_array);let target,err=self_.knownOrFresh(element);if err!=blot_error::Error.none {return 0,err;}var target_kind=blot_check_storage_types::view;if op==blot_check_storage_ops::Op.at {target_kind=blot_check_storage_types::ref;}else if op==blot_check_storage_ops::Op.link {target_kind=blot_check_storage_types::link;}let root,err=blot_check_storage_types::make(self_.types,target_kind,target);if err!=blot_error::Error.none {return 0,err;}result=root;for argument in backwards[..backwards.len-1] {let value,err=self_.expression(argument);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,blot_check_types::u32_type,argument);if err!=blot_error::Error.none {return 0,err;}}},
 load=>{valid=kind.present && (kind.value.kind==blot_check_storage_types::ref || kind.value.kind==blot_check_storage_types::link);if valid {result=kind.value.element;}else {let value,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}result=value;}},
 length=>{valid=element.present;result=blot_check_types::u32_type;},
 read=>{valid=element.present;let value,err=self_.expression(backwards[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,blot_check_types::u32_type,backwards[0]);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.knownOrFresh(element);if err!=blot_error::Error.none {return 0,err;}result=root;},
 push=>{var elem_opt=element;if self_.types.node(resolved).tag==blot_check_types::Tag.variable {let fresh_elem,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let arr_ty,err=self_.types.array(fresh_elem);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(resolved,arr_ty,first);if err!=blot_error::Error.none {return 0,err;}elem_opt=blot_support::some(fresh_elem);valid=true;}else {valid=self_.types.node(resolved).tag==blot_check_types::Tag.array;}let value,err=self_.expression(backwards[0]);if err!=blot_error::Error.none {return 0,err;}let target,err=self_.knownOrFresh(elem_opt);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,target,backwards[0]);if err!=blot_error::Error.none {return 0,err;}},
 pop,truncate=>{var elem_opt=element;if self_.types.node(resolved).tag==blot_check_types::Tag.variable {let fresh_elem,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let arr_ty,err=self_.types.array(fresh_elem);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(resolved,arr_ty,first);if err!=blot_error::Error.none {return 0,err;}elem_opt=blot_support::some(fresh_elem);valid=true;}else {valid=self_.types.node(resolved).tag==blot_check_types::Tag.array;}if op==blot_check_storage_ops::Op.pop {let root,err=self_.knownOrFresh(elem_opt);if err!=blot_error::Error.none {return 0,err;}result=root;}else {let value,err=self_.expression(backwards[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,blot_check_types::u32_type,backwards[0]);if err!=blot_error::Error.none {return 0,err;}}},
 share=>{valid=true;if kind.present && kind.value.kind==blot_check_storage_types::shared {result=resolved;}else {let root,err=blot_check_storage_types::make(self_.types,blot_check_storage_types::shared,input);if err!=blot_error::Error.none {return 0,err;}result=root;}},
 copy=>{if from_intrinsic {valid=(element.present || (kind.present && kind.value.kind==blot_check_storage_types::shared)) && (!kind.present || kind.value.kind!=blot_check_storage_types::view);}else {valid=!kind.present || kind.value.kind!=blot_check_storage_types::view;}if kind.present && kind.value.kind==blot_check_storage_types::shared {result=kind.value.element;}else {result=input;}},
 }if !valid {let err=self_.diagnostic(Code.type_mismatch,first);if err!=blot_error::Error.none {return 0,err;}}return result,blot_error::Error.none;}
fn knownOrFresh(self_:Engine&,value:blot_support::Option<u32>)->u32,blot_error::Error {if value.present {return value.value,blot_error::Error.none;}return self_.types.fresh();}
recursive fn stagingApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;var backwards:u32[2]=[0;2];var count:i64=0;while self_.tree.node(head).tag==blot_parse_ast::tag_apply {let application=self_.tree.node(head);if count<backwards.len {backwards[count]=application.b;}count+=1;head=application.a;}let syntax=self_.tree.node(head);if syntax.tag!=blot_parse_ast::tag_intrinsic {return blot_support::none<u32>(),blot_error::Error.none;}let op,known=blot_check_typed_staging::lookup(self_.pool.get(syntax.a));if !known {return blot_support::none<u32>(),blot_error::Error.none;}if count!=blot_check_typed_staging::arity(op) {let err=self_.diagnostic(Code.call_arity,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}let operand=backwards[count-1];let result,err=stagingApplicationOperation(self_,id,op,operand,backwards[..count]);return blot_support::some(result),err;}
recursive fn stagingApplicationOperation(self_:Engine&,id:u32,op:blot_check_typed_staging::Op,operand:u32,backwards:const u32[:])->u32,blot_error::Error {
 if op==blot_check_typed_staging::Op.read_input {
    let key,error=self_.expression(operand);if error!=blot_error::Error.none {return 0,error;}
    let matched=self_.constrain(key,blot_check_types::u32_type,operand);if matched!=blot_error::Error.none {return 0,matched;}
    return self_.types.array(blot_check_types::u32_type);
 }
 if op==blot_check_typed_staging::Op.evaluate {let parent=self_.ambient;let fresh,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}self_.ambient=fresh;let result,error=stagingEvaluate(self_,operand);self_.ambient=parent;return result,error;}
 return self_.types.fresh();
}
recursive fn stagingEvaluate(self_:Engine&,operand:u32)->u32,blot_error::Error {let result,err=self_.expression(operand);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrainEffects(self_.ambient,0,operand);return result,err;}
type FieldBuffer=blot_support_pooled_buffer::Buffer<blot_check_types::Field>;
fn blot_support_pooled_buffer::append(self_:blot_check_check::FieldBuffer&,value:blot_check_types::Field)->blot_error::Error {return blot_support_pooled_buffer::push(self_,value,blot_check_check::equation_fields);}
recursive fn reflectionApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;while self_.tree.node(head).tag==blot_parse_ast::tag_apply {head=self_.tree.node(head).a;}let syntax=self_.tree.node(head);if syntax.tag!=blot_parse_ast::tag_intrinsic {return blot_support::none<u32>(),blot_error::Error.none;}let name=self_.pool.get(syntax.a);var kind=ReflectionKind.of;if name=="@effect.of" {kind=ReflectionKind.of;}else if name=="@effect.descriptor" {kind=ReflectionKind.descriptor;}else if name=="@effect.count" {kind=ReflectionKind.count;}else if name=="@effect.has" {kind=ReflectionKind.has;}else if name=="@effect.same" {kind=ReflectionKind.same;}else {return blot_support::none<u32>(),blot_error::Error.none;}var arity:i64=1;if kind==ReflectionKind.has || kind==ReflectionKind.same {arity=2;}var arguments=IdBuffer{..};var probe=id;var failure=blot_error::Error.none;while self_.tree.node(probe).tag==blot_parse_ast::tag_apply {failure=arguments.append(self_.tree.node(probe).b);if failure!=blot_error::Error.none {break;}probe=self_.tree.node(probe).a;}var result:u32=0;if failure==blot_error::Error.none {if arguments.items.len!=arity {failure=self_.diagnostic(Code.call_arity,id);if failure==blot_error::Error.none {let root,err=self_.types.fresh();result=root;failure=err;}}else {reverseIds(arguments.items);let root,err=reflectionArguments(self_,id,kind,arguments.items);result=root;failure=err;}}arguments.deinit(equation_type_ids);return blot_support::some(result),failure;}
fn reverseIds(values:u32[:]) {var at:i64=0;while at<values.len/2 {let opposite=values.len-1-at;let value=values[at];values[at]=values[opposite];values[opposite]=value;at+=1;}}
recursive fn reflectionArguments(self_:Engine&,id:u32,kind:ReflectionKind,arguments:const u32[:])->u32,blot_error::Error {let left=arguments[0];if kind==ReflectionKind.descriptor {let label,err=self_.reflectionOperation(left,true);if err!=blot_error::Error.none {return 0,err;}if !label.present {return self_.types.fresh();}return self_.reflectDescriptor(id,label.value);}if kind==ReflectionKind.of {let argument=self_.tree.node(left);var binding=blot_support::none<u32>();if argument.tag==blot_parse_ast::tag_name && !self_.lookup(argument.a).present {let selected,err=self_.globalBinding(argument.a);if err!=blot_error::Error.none {return 0,err;}binding=selected;}if argument.tag==blot_parse_ast::tag_field_access && self_.tree.node(argument.a).tag==blot_parse_ast::tag_name && !self_.lookup(self_.tree.node(argument.a).a).present {let selected,err=self_.qualifiedImportBinding(Qualified{namespace_:self_.tree.node(argument.a).a,member:argument.b, ..});if err!=blot_error::Error.none {return 0,err;}binding=selected;}if !binding.present || !self_.bindings[binding.value].named_function {let err=self_.diagnostic(Code.function_target,left);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let err=self_.prepareGlobal(binding.value);if err!=blot_error::Error.none {return 0,err;}self_.reflections.push(Reflection{node:id,kind:ReflectionKind.of,binding:binding.value, ..});return self_.reflectionType(false);}let value,err=self_.expression(left);if err!=blot_error::Error.none {return 0,err;}let required,err=self_.reflectionType(kind==ReflectionKind.same);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,required,left);if err!=blot_error::Error.none {return 0,err;}var right:u32=0;if arguments.len==2 {right=arguments[1];}if right!=0 {var ty:u32=0;if kind==ReflectionKind.has {let label,err=self_.reflectionOperation(right,false);if err!=blot_error::Error.none {return 0,err;}if label.present {let value,err=self_.reflectDescriptor(right,label.value);if err!=blot_error::Error.none {return 0,err;}ty=value;}else {ty=self_.expr_types[right];}}else {let value,err=self_.expression(right);if err!=blot_error::Error.none {return 0,err;}ty=value;}let required,err=self_.reflectionType(true);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(ty,required,right);if err!=blot_error::Error.none {return 0,err;}}self_.reflections.push(Reflection{node:id,kind:kind,left:left,right:right, ..});if kind==ReflectionKind.count {return blot_check_types::u32_type,blot_error::Error.none;}return blot_check_types::boolean,blot_error::Error.none;}
struct ReflectionOrder {engine:Engine&}
fn lessThan(self_:ReflectionOrder,left:i64,right:i64)->bool {return self_.engine.reflections[left].node<self_.engine.reflections[right].node;}
fn swap(self_:ReflectionOrder,left:i64,right:i64) {let item=self_.engine.reflections[left];self_.engine.reflections[left]=self_.engine.reflections[right];self_.engine.reflections[right]=item;}
fn finishReflection(self_:Engine&)->blot_error::Error {for &reflection in self_.reflections {if reflection.kind!=ReflectionKind.of {continue;}let binding=self_.bindings[reflection.binding];let root,err=self_.types.resolve(binding.scheme.root,0);if err!=blot_error::Error.none {return err;}let signature=self_.types.node(root);if signature.tag!=blot_check_types::Tag.function {let err=self_.diagnostic(Code.function_target,reflection.node);if err!=blot_error::Error.none {return err;}continue;}let row,err=self_.types.resolveEffects(signature.c,0);if err!=blot_error::Error.none {return err;}var closed=false;match self_.types.row(row).tail {closed=>{closed=true;},_=>{}}let type_span_48=checkedRowLabels(self_.types,row);for type_index_48 in 0..(type_span_48.len as i64) {let label=self_.types.effects.list(type_span_48)[type_index_48];let type_span_49=checkedOperationArguments(self_.types,label);for type_index_49 in 0..(type_span_49.len as i64) {let argument=self_.types.list(type_span_49)[type_index_49];if closed {let same,err=self_.types.equalClosed(argument,argument);if err!=blot_error::Error.none {return err;}closed=same;}}}if !closed {let err=self_.diagnostic(Code.open_effect_descriptor,reflection.node);if err!=blot_error::Error.none {return err;}continue;}reflection.row=row;}var context=makeReflectionOrder(self_);blot_check_source_sort::pdqContext(0,self_.reflections.len,context);return blot_error::Error.none;}
reusable[] var parameter_fields:blot_check_parameter_patterns::Field[>..];
fn copyParameterPatterns(self_:Engine&,source:blot_check_frozen_types::Patterns,span:blot_check_parameter_patterns::List,copier:blot_check_check_scheme_import::Copier&)->blot_check_parameter_patterns::List,blot_error::Error {let result=equation_type_ids.alloc_slice(span.len);let output,err=copyParameterPatternsBody(self_,source,span,copier,result);equation_type_ids.free_slice(result);return output,err;}
fn copyParameterPatternsBody(self_:Engine&,source:blot_check_frozen_types::Patterns,span:blot_check_parameter_patterns::List,copier:blot_check_check_scheme_import::Copier&,result:u32[:])->blot_check_parameter_patterns::List,blot_error::Error {for pattern,index in source.list(span) {let value,err=self_.copyParameterPattern(source,pattern,copier,0);if err!=blot_error::Error.none {return blot_check_parameter_patterns::List{..},err;}result[index]=value;}return self_.parameter_patterns.saveList(result);}
recursive fn copyParameterPattern(self_:Engine&,source:blot_check_frozen_types::Patterns,id:u32,copier:blot_check_check_scheme_import::Copier&,depth:i64)->u32,blot_error::Error {if depth>=1024 {return 0,blot_error::Error.type_limit;}let node=source.node(id);if node.kind==blot_check_parameter_patterns::Kind.binding {let ty,err=copier.copy(node.a,depth+1);if err!=blot_error::Error.none {return 0,err;}return self_.parameter_patterns.add(blot_check_parameter_patterns::Node{kind:blot_check_parameter_patterns::Kind.binding,a:ty, ..});}if node.kind==blot_check_parameter_patterns::Kind.record {let fields=parameter_fields.alloc_slice(node.b);let result,err=copyParameterRecord(self_,source,node,copier,depth,fields);parameter_fields.free_slice(fields);return result,err;}let children=equation_type_ids.alloc_slice(node.b);let result,err=copyParameterSequence(self_,source,node,copier,depth,children);equation_type_ids.free_slice(children);return result,err;}
recursive fn copyParameterRecord(self_:Engine&,source:blot_check_frozen_types::Patterns,node:blot_check_parameter_patterns::Node,copier:blot_check_check_scheme_import::Copier&,depth:i64,fields:blot_check_parameter_patterns::Field[:])->u32,blot_error::Error {for index in 0..node.b {let field=source.field(node,index);let pattern,err=self_.copyParameterPattern(source,field.pattern,copier,depth+1);if err!=blot_error::Error.none {return 0,err;}fields[index]=blot_check_parameter_patterns::Field{name:field.name,pattern:pattern, ..};}return self_.parameter_patterns.record(fields);}
recursive fn copyParameterSequence(self_:Engine&,source:blot_check_frozen_types::Patterns,node:blot_check_parameter_patterns::Node,copier:blot_check_check_scheme_import::Copier&,depth:i64,children:u32[:])->u32,blot_error::Error {for child,index in source.list(blot_check_types::List{node.a,node.b, ..}) {let pattern,err=self_.copyParameterPattern(source,child,copier,depth+1);if err!=blot_error::Error.none {return 0,err;}children[index]=pattern;}return self_.parameter_patterns.sequence(node.kind,children);}
struct ParameterAnnotation {ty:u32,pattern:u32}
recursive fn parameterAnnotation(self_:Engine&,id:u32,depth:i64)->ParameterAnnotation,blot_error::Error {if depth>=1024 {return ParameterAnnotation{..},blot_error::Error.type_limit;}let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_group {return self_.parameterAnnotation(node.a,depth+1);}if node.tag==blot_parse_ast::tag_type_product || node.tag==blot_parse_ast::tag_type_array {let children=checkedAstChildren(self_.tree,id);if node.tag==blot_parse_ast::tag_type_product && (children.len as i64)==1 {return self_.parameterAnnotation(self_.tree.list(children)[0],depth+1);}let types=equation_type_ids.alloc_slice((children.len as i64));let patterns=equation_type_ids.alloc_slice((children.len as i64));let result,err=parameterAnnotationSequence(self_,node,children,depth,types,patterns);equation_type_ids.free_slice(patterns);equation_type_ids.free_slice(types);return result,err;}if node.tag==blot_parse_ast::tag_type_record {let children=checkedAstChildren(self_.tree,id);let types=equation_fields.alloc_slice((children.len as i64));let fields=parameter_fields.alloc_slice((children.len as i64));let result,err=parameterAnnotationRecord(self_,id,children,depth,types,fields);parameter_fields.free_slice(fields);equation_fields.free_slice(types);return result,err;}if node.tag==blot_parse_ast::tag_type_name {let text=self_.pool.get(node.a);if text.len!=0 && ((text[0]>='a' as u8 && text[0]<='z' as u8) || text[0]=='_' as u8) && !firstDot(text).present {return self_.parameterBinding(node.a,id);}}{let err=self_.diagnostic(Code.type_parameter,id);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}let ty,err=self_.types.fresh();if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}let pattern,err=self_.parameter_patterns.add(blot_check_parameter_patterns::Node{kind:blot_check_parameter_patterns::Kind.binding,a:ty, ..});return ParameterAnnotation{ty,pattern, ..},err;}}
recursive fn parameterAnnotationSequence(self_:Engine&,node:blot_parse_ast::Node,children:blot_parse_ast::List,depth:i64,types:u32[:],patterns:u32[:])->ParameterAnnotation,blot_error::Error {let ast_span_5=children;for index in 0..(ast_span_5.len as i64) {let child=self_.tree.list(ast_span_5)[index];let parsed,err=self_.parameterAnnotation(child,depth+1);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}types[index]=parsed.ty;patterns[index]=parsed.pattern;}var ty=blot_check_types::unit;if types.len!=0 {let root,err=self_.types.product(types);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}ty=root;}var kind=blot_check_parameter_patterns::Kind.tuple;if node.tag==blot_parse_ast::tag_type_array {kind=blot_check_parameter_patterns::Kind.array;}let pattern,err=self_.parameter_patterns.sequence(kind,patterns);return ParameterAnnotation{ty,pattern, ..},err;}
recursive fn parameterAnnotationRecord(self_:Engine&,id:u32,children:blot_parse_ast::List,depth:i64,types:blot_check_types::Field[:],fields:blot_check_parameter_patterns::Field[:])->ParameterAnnotation,blot_error::Error {let ast_span_6=children;for index in 0..(ast_span_6.len as i64) {let child=self_.tree.list(ast_span_6)[index];let field=self_.tree.node(child);for prior in fields[..index] {if prior.name==field.a {let err=self_.diagnostic(Code.duplicate_type_field,id);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}}}var parsed=ParameterAnnotation{..};if field.b==0 {let value,err=self_.parameterBinding(field.a,child);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}parsed=value;}else {let value,err=self_.parameterAnnotation(field.b,depth+1);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}parsed=value;}types[index]=blot_check_types::Field{name:field.a,ty:parsed.ty, ..};fields[index]=blot_check_parameter_patterns::Field{name:field.a,pattern:parsed.pattern, ..};}let ty,err=self_.types.record(types);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}let pattern,err=self_.parameter_patterns.record(fields);return ParameterAnnotation{ty,pattern, ..},err;}
fn parameterBinding(self_:Engine&,name:u32,source:u32)->ParameterAnnotation,blot_error::Error {for prior in self_.type_env.items {if prior.name==name {let err=self_.diagnostic(Code.duplicate_type_parameter,source);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}break;}}let ty,err=self_.typeVariable(name,source);if err!=blot_error::Error.none {return ParameterAnnotation{..},err;}let pattern,err=self_.parameter_patterns.add(blot_check_parameter_patterns::Node{kind:blot_check_parameter_patterns::Kind.binding,a:ty, ..});return ParameterAnnotation{ty,pattern, ..},err;}
recursive fn scalarArgumentPossible(self_:Engine&,source:u32,allow_unit:bool,depth:i64)->bool,blot_error::Error {if depth>=1024 {return false,blot_error::Error.type_limit;}let node=self_.tree.node(source);if node.tag==blot_parse_ast::tag_group {return self_.scalarArgumentPossible(node.a,allow_unit,depth+1);}if node.tag==blot_parse_ast::tag_array {return false,blot_error::Error.none;}if node.tag==blot_parse_ast::tag_product {let child_count=self_.tree.children(source).len;for index in 0..child_count {let child=self_.tree.children(source)[index];let possible,err=self_.scalarArgumentPossible(child,true,depth+1);if err!=blot_error::Error.none || !possible {return false,err;}}return true,blot_error::Error.none;}return self_.possibleOperationType(source,allow_unit,depth+1);}
fn possibleParameterArgument(self_:Engine&,pattern:u32,source:u32,allow_unit:bool,depth:i64)->bool,blot_error::Error {if depth>=1024 {return false,blot_error::Error.type_limit;}let node=self_.parameter_patterns.node(pattern);if node.kind==blot_check_parameter_patterns::Kind.binding {return self_.scalarArgumentPossible(source,allow_unit,depth+1);}return self_.possibleOperationType(source,allow_unit || (node.kind==blot_check_parameter_patterns::Kind.tuple && node.b==0),depth+1);}
recursive fn scalarTypeArgument(self_:Engine&,source:u32,annotation:bool,depth:i64)->u32,blot_error::Error {if depth>=1024 {return 0,blot_error::Error.type_limit;}let node=self_.tree.node(source);if node.tag==blot_parse_ast::tag_group {return self_.scalarTypeArgument(node.a,annotation,depth+1);}if node.tag==blot_parse_ast::tag_array || node.tag==blot_parse_ast::tag_type_array {let err=self_.diagnostic(Code.type_argument,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}if node.tag==blot_parse_ast::tag_product || node.tag==blot_parse_ast::tag_type_product {let children=checkedAstChildren(self_.tree,source);let fields=equation_type_ids.alloc_slice((children.len as i64));let result,err=scalarTypeArgumentFields(self_,children,annotation,depth,fields);equation_type_ids.free_slice(fields);return result,err;}if annotation {return self_.annotation(source);}return self_.operationTypeArgument(source,depth+1);}
recursive fn scalarTypeArgumentFields(self_:Engine&,children:blot_parse_ast::List,annotation:bool,depth:i64,fields:u32[:])->u32,blot_error::Error {let ast_span_7=children;for index in 0..(ast_span_7.len as i64) {let child=self_.tree.list(ast_span_7)[index];let root,err=self_.scalarTypeArgument(child,annotation,depth+1);if err!=blot_error::Error.none {return 0,err;}fields[index]=root;}if fields.len==0 {return blot_check_types::unit,blot_error::Error.none;}if fields.len==1 {return fields[0],blot_error::Error.none;}return self_.types.product(fields);}
recursive fn parameterArgument(self_:Engine&,pattern:u32,source:u32,annotation:bool,depth:i64)->u32,blot_error::Error {if depth>=1024 {return 0,blot_error::Error.type_limit;}let node=self_.tree.node(source);if node.tag==blot_parse_ast::tag_group {return self_.parameterArgument(pattern,node.a,annotation,depth+1);}let formal=self_.parameter_patterns.node(pattern);if formal.kind==blot_check_parameter_patterns::Kind.binding {return self_.scalarTypeArgument(source,annotation,depth+1);}if formal.kind==blot_check_parameter_patterns::Kind.record && (node.tag==blot_parse_ast::tag_record || node.tag==blot_parse_ast::tag_type_record) {let children=checkedAstChildren(self_.tree,source);let ast_span_8=children;for index in 0..(ast_span_8.len as i64) {let child=self_.tree.list(ast_span_8)[index];let ast_span_9=checkedAstSubspan(self_.tree,children,0,index);for ast_index_9 in 0..(ast_span_9.len as i64) {let prior=self_.tree.list(ast_span_9)[ast_index_9];if self_.tree.node(prior).a==self_.tree.node(child).a {let err=self_.diagnostic(Code.duplicate_type_field,source);if err!=blot_error::Error.none {return 0,err;}}}}if (children.len as i64)!=formal.b {let err=self_.diagnostic(Code.type_argument,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let fields=equation_fields.alloc_slice(formal.b);let result,err=parameterArgumentRecord(self_,formal,source,children,annotation,depth,fields);equation_fields.free_slice(fields);return result,err;}let tuple=node.tag==blot_parse_ast::tag_product || node.tag==blot_parse_ast::tag_type_product || node.tag==blot_parse_ast::tag_unit;let array=(node.tag==blot_parse_ast::tag_array && node.c==1) || node.tag==blot_parse_ast::tag_type_array;if (formal.kind==blot_check_parameter_patterns::Kind.tuple && tuple) || (formal.kind==blot_check_parameter_patterns::Kind.array && array) {let children=selectedArgumentChildren(self_,source,node.tag);if (children.len as i64)!=formal.b {let err=self_.diagnostic(Code.type_argument,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let fields=equation_type_ids.alloc_slice((children.len as i64));let patterns=equation_type_ids.alloc_slice(formal.b);let type_span_50=checkedPatternList(self_.parameter_patterns,blot_check_types::List{formal.a,formal.b, ..});for index in 0..(type_span_50.len as i64) {let value=self_.parameter_patterns.list(type_span_50)[index];patterns[index]=value;}let result,err=parameterArgumentSequence(self_,patterns,children,annotation,depth,fields);equation_type_ids.free_slice(patterns);equation_type_ids.free_slice(fields);return result,err;}let err=self_.diagnostic(Code.type_argument,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}
recursive fn parameterArgumentRecord(self_:Engine&,formal:blot_check_parameter_patterns::Node,source:u32,children:blot_parse_ast::List,annotation:bool,depth:i64,fields:blot_check_types::Field[:])->u32,blot_error::Error {for index in 0..formal.b {let expected=self_.parameter_patterns.field(formal,index);var found:u32=0;let ast_span_10=children;for ast_index_10 in 0..(ast_span_10.len as i64) {let child=self_.tree.list(ast_span_10)[ast_index_10];if self_.tree.node(child).a==expected.name {found=child;break;}}if found==0 {let err=self_.diagnostic(Code.type_argument,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let actual=self_.tree.node(found);var ty:u32=0;if actual.b==0 {let root,err=self_.typeVariable(actual.a,found);if err!=blot_error::Error.none {return 0,err;}ty=root;}else {let root,err=self_.parameterArgument(expected.pattern,actual.b,annotation,depth+1);if err!=blot_error::Error.none {return 0,err;}ty=root;}fields[index]=blot_check_types::Field{name:expected.name,ty:ty, ..};}return self_.types.record(fields);}
recursive fn parameterArgumentSequence(self_:Engine&,patterns:const u32[:],children:blot_parse_ast::List,annotation:bool,depth:i64,fields:u32[:])->u32,blot_error::Error {for pattern,index in patterns {let root,err=self_.parameterArgument(pattern,self_.tree.list(children)[index],annotation,depth+1);if err!=blot_error::Error.none {return 0,err;}fields[index]=root;}if fields.len==0 {return blot_check_types::unit,blot_error::Error.none;}return self_.types.product(fields);}
recursive fn possibleOperationType(self_:Engine&,original:u32,allow_unit:bool,depth:i64)->bool,blot_error::Error {if depth>=1024 {return false,blot_error::Error.type_limit;}let node=self_.tree.node(original);if node.tag==blot_parse_ast::tag_group {return self_.possibleOperationType(node.a,allow_unit,depth+1);}if node.tag==blot_parse_ast::tag_unit {return allow_unit,blot_error::Error.none;}if node.tag==blot_parse_ast::tag_name {if self_.lookup(node.a).present {return false,blot_error::Error.none;}let global,err=self_.globalBinding(node.a);if err!=blot_error::Error.none || global.present {return false,err;}let text=self_.pool.get(node.a);if text=="Unit" || text=="Bool" || text=="U32" || text=="F32" || text=="Array" {return true,blot_error::Error.none;}for entry in self_.type_env.items {if entry.name==node.a {return true,blot_error::Error.none;}}return self_.catalogs.nominal_names.contains(self_.catalogKey(node.a)),blot_error::Error.none;}if node.tag==blot_parse_ast::tag_apply {let left,err=self_.possibleOperationType(node.a,false,depth+1);if err!=blot_error::Error.none || !left {return false,err;}return self_.possibleOperationType(node.b,true,depth+1);}if node.tag==blot_parse_ast::tag_product || node.tag==blot_parse_ast::tag_array {if node.tag==blot_parse_ast::tag_array && node.c==0 {return false,blot_error::Error.none;}let child_count=self_.tree.children(original).len;for child_index in child_count {let child:u32=self_.tree.children(original)[child_index];let possible,err=self_.possibleOperationType(child,true,depth+1);if err!=blot_error::Error.none || !possible {return false,err;}}return true,blot_error::Error.none;}if node.tag==blot_parse_ast::tag_record {if node.a!=0 {return false,blot_error::Error.none;}let child_count=self_.tree.children(original).len;for child_index in child_count {let child:u32=self_.tree.children(original)[child_index];let field=self_.tree.node(child);if field.b==0 {var known=false;for entry in self_.type_env.items {known=known || entry.name==field.a;}if !known {return false,blot_error::Error.none;}}else {let possible,err=self_.possibleOperationType(field.b,true,depth+1);if err!=blot_error::Error.none || !possible {return false,err;}}}return true,blot_error::Error.none;}return false,blot_error::Error.none;}
recursive fn operationTypeArgument(self_:Engine&,id:u32,depth:i64)->u32,blot_error::Error {if depth>=1024 {return 0,blot_error::Error.type_limit;}let node=self_.tree.node(id);if node.tag==blot_parse_ast::tag_unit {return blot_check_types::unit,blot_error::Error.none;}if node.tag==blot_parse_ast::tag_group {return self_.operationTypeArgument(node.a,depth+1);}if node.tag==blot_parse_ast::tag_name {let text=self_.pool.get(node.a);if text=="Unit" {return blot_check_types::unit,blot_error::Error.none;}if text=="Bool" {return blot_check_types::boolean,blot_error::Error.none;}if text=="U32" {return blot_check_types::u32_type,blot_error::Error.none;}if text=="F32" {return blot_check_types::f32_type,blot_error::Error.none;}for entry in self_.type_env.items {if entry.name==node.a {return entry.ty,blot_error::Error.none;}}let scalar_lookup_53 .= self_.catalogs.nominal_names.get(self_.catalogKey(node.a));if scalar_lookup_53 {let selected:u32=scalar_lookup_53;let index=selected;if self_.nominals[index].parameters.len!=0 {let err=self_.diagnostic(Code.type_arity,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let alias,err=self_.aliasInstance(index,[],[],id);if err!=blot_error::Error.none {return 0,err;}if alias.present {return alias.value,blot_error::Error.none;}return self_.types.nominal(self_.nominals[index].identity,[]);}}
 if node.tag==blot_parse_ast::tag_apply {var reverse=IdBuffer{..};var head=id;var error=blot_error::Error.none;loop {let syntax=self_.tree.node(head);if syntax.tag==blot_parse_ast::tag_group {head=syntax.a;continue;}if syntax.tag!=blot_parse_ast::tag_apply {break;}error=reverse.append(syntax.b);if error!=blot_error::Error.none {break;}head=syntax.a;}var result:u32=0;if error==blot_error::Error.none {reverseIds(reverse.items);let root,err=operationTypeApplication(self_,id,head,reverse.items,depth);result=root;error=err;}reverse.deinit(equation_type_ids);return result,error;}
 if node.tag==blot_parse_ast::tag_product || node.tag==blot_parse_ast::tag_array {if node.tag==blot_parse_ast::tag_array && node.c==0 {let err=self_.diagnostic(Code.type_argument,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let children=checkedAstChildren(self_.tree,id);let parts=equation_type_ids.alloc_slice((children.len as i64));let result,err=operationTypeProduct(self_,children,depth,parts);equation_type_ids.free_slice(parts);return result,err;}
 if node.tag==blot_parse_ast::tag_record {let children=checkedAstChildren(self_.tree,id);let fields=equation_fields.alloc_slice((children.len as i64));let result,err=operationTypeRecord(self_,children,depth,fields);equation_fields.free_slice(fields);return result,err;}let err=self_.diagnostic(Code.unsupported_type,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}
recursive fn operationTypeApplication(self_:Engine&,id:u32,head:u32,syntax:const u32[:],depth:i64)->u32,blot_error::Error {if self_.tree.node(head).tag!=blot_parse_ast::tag_name {return 0,blot_error::Error.type_limit;}let symbol=self_.tree.node(head).a;let name=self_.pool.get(symbol);if name=="Array" && syntax.len==1 {let child,err=self_.operationTypeArgument(syntax[0],depth+1);if err!=blot_error::Error.none {return 0,err;}return self_.types.sequence(blot_check_types::Tag.array,child);}let selected:u32={let scalar_lookup_54 .= self_.catalogs.nominal_names.get(self_.catalogKey(symbol));if !scalar_lookup_54 {return 0,blot_error::Error.type_limit;}let scalar_value_54:u32=scalar_lookup_54;scalar_value_54};let index=selected;let nominal=self_.nominals[index];let shapes=equation_type_ids.alloc_slice(nominal.parameters.len);let type_span_51=checkedTypeList(self_.types,nominal.parameters);for ordinal in 0..(type_span_51.len as i64) {let value=self_.types.list(type_span_51)[ordinal];shapes[ordinal]=value;}let old=equation_type_ids.alloc_slice(nominal.variables.len);let type_span_52=checkedTypeList(self_.types,nominal.variables);for ordinal in 0..(type_span_52.len as i64) {let value=self_.types.list(type_span_52)[ordinal];old[ordinal]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let arguments=equation_type_ids.alloc_slice(shapes.len);let result,err=operationTypeNominal(self_,id,index,nominal,syntax,depth,shapes,old,fresh,arguments);equation_type_ids.free_slice(arguments);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);equation_type_ids.free_slice(shapes);return result,err;}
recursive fn operationTypeNominal(self_:Engine&,id:u32,index:u32,nominal:Nominal,syntax:const u32[:],depth:i64,shapes:const u32[:],old:const u32[:],fresh:u32[:],arguments:u32[:])->u32,blot_error::Error {if syntax.len!=shapes.len {let err=self_.diagnostic(Code.type_arity,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}for origin,ordinal in syntax {let argument,err=self_.parameterArgument(self_.parameter_patterns.list(nominal.patterns)[ordinal],origin,false,depth+1);if err!=blot_error::Error.none {return 0,err;}let selected,err=self_.types.substitute(shapes[ordinal],old,fresh);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(selected,argument,origin);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(selected,0);if err!=blot_error::Error.none {return 0,err;}arguments[ordinal]=resolved;}let alias,err=self_.aliasInstance(index,old,fresh,id);if err!=blot_error::Error.none {return 0,err;}if alias.present {return alias.value,blot_error::Error.none;}return self_.types.nominal(nominal.identity,arguments);}
recursive fn operationTypeProduct(self_:Engine&,children:blot_parse_ast::List,depth:i64,parts:u32[:])->u32,blot_error::Error {let ast_span_11=children;for index in 0..(ast_span_11.len as i64) {let child=self_.tree.list(ast_span_11)[index];let root,err=self_.operationTypeArgument(child,depth+1);if err!=blot_error::Error.none {return 0,err;}parts[index]=root;}return self_.types.product(parts);}
recursive fn operationTypeRecord(self_:Engine&,children:blot_parse_ast::List,depth:i64,fields:blot_check_types::Field[:])->u32,blot_error::Error {let ast_span_12=children;for index in 0..(ast_span_12.len as i64) {let child=self_.tree.list(ast_span_12)[index];let field=self_.tree.node(child);var ty:u32=0;if field.b==0 {let root,err=self_.typeVariable(field.a,child);if err!=blot_error::Error.none {return 0,err;}ty=root;}else {let root,err=self_.operationTypeArgument(field.b,depth+1);if err!=blot_error::Error.none {return 0,err;}ty=root;}for known in fields[..index] {if known.name==field.a {let err=self_.diagnostic(Code.duplicate_field,child);if err!=blot_error::Error.none {return 0,err;}}}fields[index]=blot_check_types::Field{name:field.a,ty:ty, ..};}return self_.types.record(fields);}
recursive fn operationApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;loop {let syntax=self_.tree.node(head);if syntax.tag==blot_parse_ast::tag_group {head=syntax.a;continue;}if syntax.tag!=blot_parse_ast::tag_apply {break;}head=syntax.a;}if self_.tree.node(head).tag!=blot_parse_ast::tag_name {return blot_support::none<u32>(),blot_error::Error.none;}let template,err=self_.operationTemplate(self_.tree.node(head).a);if err!=blot_error::Error.none || !template.present {return blot_support::none<u32>(),err;}let family=self_.effect_families[self_.effect_templates[template.value].family];if family.parameters.len==0 {return blot_support::none<u32>(),blot_error::Error.none;}var reverse=IdBuffer{..};var arguments=IdBuffer{..};let result,error=operationApplications(self_,id,template.value,family,reverse,arguments);arguments.deinit(equation_type_ids);reverse.deinit(equation_type_ids);return result,error;}
recursive fn operationApplications(self_:Engine&,id:u32,template:u32,family:EffectFamily,reverse:IdBuffer&,arguments:IdBuffer&)->blot_support::Option<u32>,blot_error::Error {let count=family.parameters.len;var probe=id;loop {let syntax=self_.tree.node(probe);if syntax.tag==blot_parse_ast::tag_group {probe=syntax.a;continue;}if syntax.tag!=blot_parse_ast::tag_apply {break;}let err=reverse.append(probe);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}probe=syntax.a;}if reverse.items.len<count {return blot_support::none<u32>(),blot_error::Error.none;}reverseIds(reverse.items);let runtime=reverse.items.len>=count*2;for application,ordinal in reverse.items[..count] {let syntax=self_.tree.node(application).b;let possible,err=self_.possibleParameterArgument(self_.parameter_patterns.list(family.patterns)[ordinal],syntax,runtime,0);if err!=blot_error::Error.none || !possible {return blot_support::none<u32>(),err;}let err=arguments.append(syntax);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}if reverse.items.len>count {let possible,err=self_.possibleOperationType(self_.tree.node(reverse.items[count]).b,false,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if possible {let err=self_.diagnostic(Code.type_arity,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}}let specialized=reverse.items[count-1];let initial,err=self_.operationValue(specialized,template,blot_support::some<const u32[:]>(arguments.items));if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}var ty=initial;self_.expr_types[specialized]=ty;for application in reverse.items[count..] {let syntax=self_.tree.node(application);let argument,err=self_.checkArgument(syntax.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let invocation,err=self_.invocation(argument,result);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.constrain(ty,invocation,application);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}ty=result;self_.expr_types[application]=ty;}return blot_support::some(ty),blot_error::Error.none;}
// Bit i is set when parameter i of the function written at `body` is `own`.
fn ownParameters(tree:const blot_parse_ast::Tree&,body:u32)->u32 {
 var mask:u32=0;var index:u32=0;var at=body;
 while at!=0 && tree.node(at).tag==blot_parse_ast::tag_lambda && index<32 {if tree.parameter(tree.node(at).a).own {mask|=(1 as u32)<<index;}index+=1;at=tree.node(at).b;}
 return mask;
}
// `own` is built for the parameters of named functions first. On any other
// parameter (a lambda, or beyond the 32nd) it is refused, not ignored.
// Records which parameters each top-level named function takes over, and
// refuses `own` anywhere else: function types do not carry it yet, so only a
// function that is called by name can be held to it.
fn ownParameterHeaders(self_:Engine&)->blot_error::Error {
 var roots:dictionary<u32,bool> =dictionary<u32,bool>{};
 for id in self_.tree.roots.items {if self_.tree.node(id).tag==blot_parse_ast::tag_value_decl {roots.insert(id,true);}}
 var named:dictionary<u32,bool> =dictionary<u32,bool>{};
 for &binding in self_.bindings {
  if binding.kind!=blot_reuse_principal_interface::Kind.global {continue;}
  if !roots.contains(binding.declaration) {binding.capability_parameters.owned_results=true;continue;}
  // An entry's result goes to the host, which copies it, so an entry may
  // return what it shares; a caller inside the program cannot rely on it.
  binding.capability_parameters.owned_results=!self_.tree.value_decl(binding.declaration).runtime && !self_.tree.value_decl(binding.declaration).exported;
  if !binding.named_function {continue;}
  let body=self_.tree.value_decl(binding.declaration).body;
  binding.capability_parameters.own=ownParameters(self_.tree,body);
  var index:u32=0;var at=body;
  while at!=0 && self_.tree.node(at).tag==blot_parse_ast::tag_lambda && index<32 {named.insert(self_.tree.node(at).a,true);index+=1;at=self_.tree.node(at).b;}
  // How many arguments a call must give before the function runs.
  if binding.capability_parameters.own!=0 {binding.capability_parameters.own_count=index as u8;}
 }
 let count=self_.tree.nodes.items.len;
 for id in 0..count {
  if self_.tree.nodes.items[id].tag!=blot_parse_ast::tag_parameter || !self_.tree.parameter(id as u32).own || named.contains(id as u32) {continue;}
  // A lambda inside a value's declaration may take a parameter over: its
  // type says so. A member of a contract or an implementation may not yet.
  let at=self_.tree.span(id as u32).start;var inside=false;
  for root in self_.tree.roots.items {if (self_.tree.node(root).tag==blot_parse_ast::tag_value_decl || self_.tree.node(root).tag==blot_parse_ast::tag_entry_kernel_decl) && self_.tree.span(root).start<=at && at<self_.tree.span(root).end {inside=true;break;}}
  if inside {continue;}
  let err=self_.diagnostic(Code.own_parameter,id as u32);if err!=blot_error::Error.none {return err;}
 }
 return blot_error::Error.none;
}
fn capabilityFamilyAnnotation(self_:const Engine&,original:u32)->blot_support::Option<u32> {if original==0 {return blot_support::none<u32>();}var head=original;while self_.tree.node(head).tag==blot_parse_ast::tag_type_apply {head=self_.tree.node(head).a;}let name=self_.tree.node(head);if name.tag!=blot_parse_ast::tag_type_name {return blot_support::none<u32>();}let family:u32={let scalar_lookup_57 .= self_.catalogs.effect_family_names.get(self_.catalogKey(name.a));if !scalar_lookup_57 {return blot_support::none<u32>();}let scalar_value_57:u32=scalar_lookup_57;scalar_value_57};return blot_support::some(family);}
recursive fn capabilityDescriptorAnnotation(self_:Engine&,original:u32)->blot_support::Option<u32>,blot_error::Error {let index=self_.capabilityFamilyAnnotation(original);if !index.present {return blot_support::none<u32>(),blot_error::Error.none;}let family=self_.effect_families[index.value];var syntax=IdBuffer{..};var arguments=IdBuffer{..};let result,err=capabilityDescriptorArguments(self_,original,family,syntax,arguments);arguments.deinit(equation_type_ids);syntax.deinit(equation_type_ids);return result,err;}
recursive fn capabilityDescriptorArguments(self_:Engine&,original:u32,family:EffectFamily,syntax:IdBuffer&,arguments:IdBuffer&)->blot_support::Option<u32>,blot_error::Error {var head=original;while self_.tree.node(head).tag==blot_parse_ast::tag_type_apply {let err=syntax.append(self_.tree.node(head).b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}head=self_.tree.node(head).a;}if syntax.items.len!=family.parameters.len {let err=self_.diagnostic(Code.type_arity,original);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.fresh();return blot_support::some(root),err;}reverseIds(syntax.items);for source,index in syntax.items {let argument,err=self_.parameterArgument(self_.parameter_patterns.list(family.patterns)[index],source,true,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=arguments.append(argument);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}let root,err=self_.types.nominal(family.identity,arguments.items);return blot_support::some(root),err;}
fn diagnosticFresh(self_:Engine&,code:Code,source:u32)->u32,blot_error::Error {let err=self_.diagnostic(code,source);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}
fn freeVariableRun(store:blot_check_types::Store&,root:u32)->u32[:],blot_error::Error {let variables,err=store.freeVariables(root);if err!=blot_error::Error.none {return default<u32[:]>(),err;}let result=equation_type_ids.alloc_slice(variables.len);for variable,index in variables {result[index]=variable;}return result,blot_error::Error.none;}
recursive fn scopedOperation(self_:Engine&,source:u32,receiver:u32,member:u32,capability_source:u32)->blot_support::Option<u32>,blot_error::Error {let root,err=self_.types.resolve(receiver,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let capability=self_.types.node(root);if capability.tag!=blot_check_types::Tag.scoped {return blot_support::none<u32>(),blot_error::Error.none;}let root,err=self_.types.resolve(capability.a,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let descriptor=self_.types.node(root);if descriptor.tag!=blot_check_types::Tag.nominal {return blot_support::none<u32>(),blot_error::Error.type_limit;}let selected:u32={let scalar_lookup_59 .= self_.catalogs.effect_family_identities.get(Identity{descriptor.a,descriptor.b, ..});if !scalar_lookup_59 {return blot_support::none<u32>(),blot_error::Error.type_limit;}let scalar_value_59:u32=scalar_lookup_59;scalar_value_59};let index=selected;let selected:u32={let scalar_lookup_60 .= self_.catalogs.effect_members.get(EffectMember{family:index,member:member, ..});if !scalar_lookup_60 {let root,err=self_.diagnosticFresh(Code.unknown_field,source);return blot_support::some(root),err;}let scalar_value_60:u32=scalar_lookup_60;scalar_value_60};let template=selected;let family=self_.effect_families[index];let arguments=equation_type_ids.alloc_slice(self_.types.nominalArguments(descriptor).len);let type_span_63=checkedNominalArguments(self_.types,descriptor);for index in 0..(type_span_63.len as i64) {let value=self_.types.list(type_span_63)[index];arguments[index]=value;}let shapes=equation_type_ids.alloc_slice(family.parameters.len);let type_span_64=checkedTypeList(self_.types,family.parameters);for index in 0..(type_span_64.len as i64) {let value=self_.types.list(type_span_64)[index];shapes[index]=value;}let variables=equation_type_ids.alloc_slice(family.variables.len);let type_span_65=checkedTypeList(self_.types,family.variables);for index in 0..(type_span_65.len as i64) {let value=self_.types.list(type_span_65)[index];variables[index]=value;}let fresh=equation_type_ids.alloc_slice(variables.len);let result,error=scopedOperationArguments(self_,source,capability_source,capability,template,self_.effect_templates[template],arguments,shapes,variables,fresh);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(variables);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(arguments);return blot_support::some(result),error;}
recursive fn scopedOperationArguments(self_:Engine&,source:u32,capability_source:u32,capability:blot_check_types::Node,template_index:u32,template:EffectTemplate,arguments:const u32[:],shapes:const u32[:],variables:const u32[:],fresh:u32[:])->u32,blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}for shape,index in shapes {let selected,err=self_.types.substitute(shape,variables,fresh);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(selected,arguments[index],source);if err!=blot_error::Error.none {return 0,err;}}let root,err=self_.types.substitute(template.parameter,variables,fresh);if err!=blot_error::Error.none {return 0,err;}let parameter,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.types.substitute(template.result,variables,fresh);if err!=blot_error::Error.none {return 0,err;}let result,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return 0,err;}let instance=Identity{capability.b,capability.c, ..};let label,err=self_.types.internScopedOperation(template.identity,instance,arguments);if err!=blot_error::Error.none {return 0,err;}let latent,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}let row,err=self_.types.effects.row([label],self_.types.row(latent).tail);if err!=blot_error::Error.none {return 0,blot_check_types::effectError(err);}let signature,err=self_.types.functionWithEffects(parameter,result,row);if err!=blot_error::Error.none {return 0,err;}let list,err=self_.types.saveList(arguments);if err!=blot_error::Error.none {return 0,err;}self_.operation_uses.push(OperationUse{node:source,template:template_index,arguments:list,signature:signature,instance:instance,capability:capability_source, ..});self_.operation_refs[source]=self_.operation_uses.len as u32;return signature,blot_error::Error.none;}
struct OperationTarget {token:u32,signature:u32,label:u32}
recursive fn operationTarget(self_:Engine&,original:u32)->blot_support::Option<OperationTarget>,blot_error::Error {var source=original;while self_.tree.node(source).tag==blot_parse_ast::tag_group {source=self_.tree.node(source).a;}let syntax=self_.tree.node(source);if syntax.tag==blot_parse_ast::tag_name && self_.pool.get(syntax.a)=="Foreign" {let err=self_.diagnostic(Code.sealed_effect,source);return blot_support::none<OperationTarget>(),err;}let signature,err=self_.expression(original);if err!=blot_error::Error.none {return blot_support::none<OperationTarget>(),err;}let index=self_.operation_refs[source];if index==0 {let err=self_.diagnostic(Code.operation_target,source);return blot_support::none<OperationTarget>(),err;}let use=self_.operation_uses[index-1];let root,err=self_.types.resolve(signature,0);if err!=blot_error::Error.none {return blot_support::none<OperationTarget>(),err;}let function=self_.types.node(root);let labels=checkedRowLabels(self_.types,function.c);if (labels.len as i64)!=1 {let err=self_.diagnostic(Code.operation_target,source);return blot_support::none<OperationTarget>(),err;}let label=self_.types.effects.list(labels)[0];let identity=self_.effect_templates[use.template].identity;let arguments=equation_type_ids.alloc_slice(use.arguments.len);let type_span_66=checkedTypeList(self_.types,use.arguments);for index in 0..(type_span_66.len as i64) {let value=self_.types.list(type_span_66)[index];arguments[index]=value;}let token,err=self_.types.nominal(identity,arguments);equation_type_ids.free_slice(arguments);if err!=blot_error::Error.none {return blot_support::none<OperationTarget>(),err;}var selected=token;if use.instance.decl!=0 {let root,err=self_.types.scoped(token,use.instance);if err!=blot_error::Error.none {return blot_support::none<OperationTarget>(),err;}selected=root;}return blot_support::some(OperationTarget{token:selected,signature:signature,label:label, ..}),blot_error::Error.none;}
recursive fn providerApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;while self_.tree.node(head).tag==blot_parse_ast::tag_apply {head=self_.tree.node(head).a;}let syntax=self_.tree.node(head);if syntax.tag!=blot_parse_ast::tag_intrinsic {return blot_support::none<u32>(),blot_error::Error.none;}let name=self_.pool.get(syntax.a);let ordinary=name=="@effect.provider";let state=name=="@effect.state";if !ordinary && !state {return blot_support::none<u32>(),blot_error::Error.none;}var reverse=IdBuffer{..};let result,err=providerArguments(self_,id,ordinary,reverse);reverse.deinit(equation_type_ids);return blot_support::some(result),err;}
recursive fn providerArguments(self_:Engine&,id:u32,ordinary:bool,reverse:IdBuffer&)->u32,blot_error::Error {var probe=id;while self_.tree.node(probe).tag==blot_parse_ast::tag_apply {let err=reverse.append(self_.tree.node(probe).b);if err!=blot_error::Error.none {return 0,err;}probe=self_.tree.node(probe).a;}reverseIds(reverse.items);let arguments=reverse.items;var arity:i64=3;if ordinary {arity=2;}if arguments.len!=arity {return self_.diagnosticFresh(Code.call_arity,id);}let read,err=self_.operationTarget(arguments[0]);if err!=blot_error::Error.none {return 0,err;}if !read.present {return self_.types.fresh();}let root,err=self_.types.resolve(read.value.signature,0);if err!=blot_error::Error.none {return 0,err;}let reader=self_.types.node(root);if ordinary {let implementation,err=self_.expression(arguments[1]);if err!=blot_error::Error.none {return 0,err;}let row,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}let required,err=self_.types.functionWithEffects(reader.a,reader.b,row);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(implementation,required,arguments[1]);if err!=blot_error::Error.none {return 0,err;}return self_.types.provider(read.value.token,row);}let write,err=self_.operationTarget(arguments[1]);if err!=blot_error::Error.none {return 0,err;}if !write.present {return self_.types.fresh();}if self_.types.operation(read.value.label).instance!=self_.types.operation(write.value.label).instance {return self_.diagnosticFresh(Code.effect_identity_scope,id);}if read.value.label==write.value.label {return self_.diagnosticFresh(Code.invalid_state_provider,id);}let root,err=self_.types.resolve(write.value.signature,0);if err!=blot_error::Error.none {return 0,err;}let writer=self_.types.node(root);let initial,err=self_.expression(arguments[2]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(reader.a,blot_check_types::unit,arguments[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(writer.b,blot_check_types::unit,arguments[1]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(reader.b,writer.a,id);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(initial,reader.b,arguments[2]);if err!=blot_error::Error.none {return 0,err;}return self_.types.stateProvider(read.value.token,write.value.token,reader.b);}
fn runnerTemplate(self_:Engine&,original:u32)->blot_support::Option<u32>,blot_error::Error {var source=original;while self_.tree.node(source).tag==blot_parse_ast::tag_group {source=self_.tree.node(source).a;}let syntax=self_.tree.node(source);if syntax.tag!=blot_parse_ast::tag_name {let err=self_.diagnostic(Code.operation_target,original);return blot_support::none<u32>(),err;}let index,err=self_.operationTemplate(syntax.a);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if !index.present {let err=self_.diagnostic(Code.operation_target,original);return blot_support::none<u32>(),err;}let family=self_.effect_families[self_.effect_templates[index.value].family];if family.parameters.len==0 {let err=self_.diagnostic(Code.operation_target,original);return blot_support::none<u32>(),err;}if family.parameters.len!=1 || self_.types.node(self_.types.list(family.parameters)[0]).tag!=blot_check_types::Tag.variable {let err=self_.diagnostic(Code.type_arity,original);return blot_support::none<u32>(),err;}return index,blot_error::Error.none;}
struct RunnerOperation {token:u32,parameter:u32,result:u32}
fn runnerOperation(self_:Engine&,index:u32,state:u32)->RunnerOperation,blot_error::Error {let template=self_.effect_templates[index];let family=self_.effect_families[template.family];let old=equation_type_ids.alloc_slice(family.variables.len);let type_span_67=checkedTypeList(self_.types,family.variables);for index in 0..(type_span_67.len as i64) {let value=self_.types.list(type_span_67)[index];old[index]=value;}let result,err=runnerOperationVariables(self_,template,state,old);equation_type_ids.free_slice(old);return result,err;}
fn runnerOperationVariables(self_:Engine&,template:EffectTemplate,state:u32,old:const u32[:])->RunnerOperation,blot_error::Error {if old.len!=1 {return RunnerOperation{..},blot_error::Error.type_limit;}let parameter,err=self_.types.substitute(template.parameter,old,[state]);if err!=blot_error::Error.none {return RunnerOperation{..},err;}let result,err=self_.types.substitute(template.result,old,[state]);if err!=blot_error::Error.none {return RunnerOperation{..},err;}let token,err=self_.types.nominal(template.identity,[state]);return RunnerOperation{token,parameter,result, ..},err;}
fn handlerEquation(self_:Engine&,token_type:u32,extended:u32,residual:u32,source:u32)->bool,blot_error::Error {let root,err=self_.types.resolve(token_type,0);if err!=blot_error::Error.none {return false,err;}var token=self_.types.node(root);var instance=Identity{0,0, ..};if token.tag==blot_check_types::Tag.scoped {instance=Identity{token.b,token.c, ..};let root,err=self_.types.resolve(token.a,0);if err!=blot_error::Error.none {return false,err;}token=self_.types.node(root);}if token.tag!=blot_check_types::Tag.nominal {return false,blot_error::Error.type_limit;}let arguments=equation_type_ids.alloc_slice(self_.types.nominalArguments(token).len);let type_span_68=checkedNominalArguments(self_.types,token);for index in 0..(type_span_68.len as i64) {let value=self_.types.list(type_span_68)[index];arguments[index]=value;}let result,error=handlerArguments(self_,token,instance,extended,residual,source,arguments);equation_type_ids.free_slice(arguments);return result,error;}
fn handlerArguments(self_:Engine&,token:blot_check_types::Node,instance:Identity,extended:u32,residual:u32,source:u32,arguments:u32[:])->bool,blot_error::Error {for &argument in arguments {let root,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return false,err;}argument=root;let closed,err=self_.types.equalClosed(root,root);if err!=blot_error::Error.none || !closed {return false,err;}}let label,err=self_.types.internScopedOperation(Identity{token.a,token.b, ..},instance,arguments);if err!=blot_error::Error.none {return false,err;}let tail,err=self_.types.resolveEffects(residual,0);if err!=blot_error::Error.none {return false,err;}let labels=equation_type_ids.alloc_slice(self_.types.rowLabels(tail).len+1);labels[0]=label;let type_span_69=checkedRowLabels(self_.types,tail);for index in 0..(type_span_69.len as i64) {let value=self_.types.effects.list(type_span_69)[index];labels[index+1]=value;}let row,error=self_.types.effects.rowAt(labels,self_.types.row(tail).tail,self_.types.row(tail).cursor);equation_type_ids.free_slice(labels);if error!=blot_error::Error.none {return false,blot_check_types::effectError(error);}let err=self_.constrainEffects(extended,row,source);return err==blot_error::Error.none,err;}
fn runnerHandler(self_:Engine&,source:u32,token:u32,extended:u32,residual:u32)->blot_error::Error {let solved,err=self_.handlerEquation(token,extended,residual,source);if err!=blot_error::Error.none || solved {return err;}let signature,err=self_.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,extended);if err!=blot_error::Error.none {return err;}let remainder,err=self_.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,residual);if err!=blot_error::Error.none {return err;}return self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:token, kind:blot_check_types::ObligationKind.effect_handler, source:source, other:remainder, signature:signature, .. }, owner:self_.current, direct:true, .. });}
recursive fn effectRunnerApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {var head=id;while self_.tree.node(head).tag==blot_parse_ast::tag_apply {head=self_.tree.node(head).a;}let syntax=self_.tree.node(head);if syntax.tag!=blot_parse_ast::tag_intrinsic {return blot_support::none<u32>(),blot_error::Error.none;}let name=self_.pool.get(syntax.a);let builtin=starts_with(name,"@state.");var kind=EffectRunnerKind.run;if name=="@effect.run" || name=="@state.run" {kind=EffectRunnerKind.run;}else if name=="@effect.reader" || name=="@state.reader" {kind=EffectRunnerKind.reader;}else if name=="@effect.writer" || name=="@state.writer" {kind=EffectRunnerKind.writer;}else {return blot_support::none<u32>(),blot_error::Error.none;}var arity:i64=4;if builtin {arity=3;if kind==EffectRunnerKind.run {arity=2;}}var reverse=IdBuffer{..};let result,err=effectRunnerArguments(self_,id,builtin,kind,arity,reverse);reverse.deinit(equation_type_ids);return blot_support::some(result),err;}
recursive fn effectRunnerArguments(self_:Engine&,id:u32,builtin:bool,kind:EffectRunnerKind,arity:i64,reverse:IdBuffer&)->u32,blot_error::Error {var probe=id;while self_.tree.node(probe).tag==blot_parse_ast::tag_apply {let err=reverse.append(self_.tree.node(probe).b);if err!=blot_error::Error.none {return 0,err;}probe=self_.tree.node(probe).a;}if reverse.items.len!=arity {return self_.diagnosticFresh(Code.call_arity,id);}reverseIds(reverse.items);let arguments=reverse.items;var first:u32=0;if builtin {let template,err=self_.builtinStateTemplate(kind!=EffectRunnerKind.writer);if err!=blot_error::Error.none {return 0,err;}first=template;}else {let template,err=self_.runnerTemplate(arguments[0]);if err!=blot_error::Error.none {return 0,err;}if !template.present {return self_.types.fresh();}first=template.value;}var second:u32=0;if kind==EffectRunnerKind.run {if builtin {let template,err=self_.builtinStateTemplate(false);if err!=blot_error::Error.none {return 0,err;}second=template;}else {let template,err=self_.runnerTemplate(arguments[1]);if err!=blot_error::Error.none {return 0,err;}if !template.present {return self_.types.fresh();}second=template.value;}}if !builtin && kind==EffectRunnerKind.run && self_.effect_templates[first].family!=self_.effect_templates[second].family {return self_.diagnosticFresh(Code.effect_family,id);}var state_operand:i64=1;if builtin {state_operand=0;}else if kind==EffectRunnerKind.run {state_operand=2;}var implementation_operand:i64=2;if builtin {implementation_operand=1;}let action_operand=arguments.len-1;let initial,err=self_.expression(arguments[state_operand]);if err!=blot_error::Error.none {return 0,err;}var state=initial;if kind!=EffectRunnerKind.run {let witness,err=self_.witnessType(initial,arguments[state_operand]);if err!=blot_error::Error.none {return 0,err;}state=witness;}var operation=RunnerOperation{..};if builtin {let token,err=self_.types.nominal(self_.effect_templates[first].identity,[state]);if err!=blot_error::Error.none {return 0,err;}var parameter=state;var result=blot_check_types::unit;if kind!=EffectRunnerKind.writer {parameter=blot_check_types::unit;result=state;}operation=RunnerOperation{token,parameter,result, ..};}else {let value,err=self_.runnerOperation(first,state);if err!=blot_error::Error.none {return 0,err;}operation=value;}let body_result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let body_row,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}let action_type,err=self_.types.functionWithEffects(blot_check_types::unit,body_result,body_row);if err!=blot_error::Error.none {return 0,err;}var metadata=EffectRunner{node:id,kind:kind,action:arguments[action_operand],state_type:state,body_result:body_result,result:body_result,action_type:action_type,body_effects:body_row,outer_effects:self_.ambient, ..};if kind==EffectRunnerKind.run {var writer=RunnerOperation{..};if builtin {let token,err=self_.types.nominal(self_.effect_templates[second].identity,[state]);if err!=blot_error::Error.none {return 0,err;}writer=RunnerOperation{token:token,parameter:state,result:blot_check_types::unit, ..};}else {let value,err=self_.runnerOperation(second,state);if err!=blot_error::Error.none {return 0,err;}writer=value;}let read_identity=self_.types.node(operation.token);let write_identity=self_.types.node(writer.token);if read_identity.a==write_identity.a && read_identity.b==write_identity.b {return self_.diagnosticFresh(Code.invalid_state_provider,id);}let err=self_.constrain(operation.parameter,blot_check_types::unit,arguments[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(operation.result,state,arguments[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(writer.parameter,state,arguments[1]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(writer.result,blot_check_types::unit,arguments[1]);if err!=blot_error::Error.none {return 0,err;}let intermediate,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}let err=self_.runnerHandler(id,operation.token,body_row,intermediate);if err!=blot_error::Error.none {return 0,err;}let err=self_.runnerHandler(id,writer.token,intermediate,self_.ambient);if err!=blot_error::Error.none {return 0,err;}metadata.read_token=operation.token;metadata.write_token=writer.token;metadata.initial=arguments[state_operand];let result,err=self_.types.product([state,body_result]);if err!=blot_error::Error.none {return 0,err;}metadata.result=result;}else {var parameter=state;var result=blot_check_types::unit;if kind==EffectRunnerKind.reader {parameter=blot_check_types::unit;result=state;}let err=self_.constrain(operation.parameter,parameter,arguments[0]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(operation.result,result,arguments[0]);if err!=blot_error::Error.none {return 0,err;}let implementation,err=self_.expression(arguments[implementation_operand]);if err!=blot_error::Error.none {return 0,err;}let required,err=self_.types.functionWithEffects(parameter,result,self_.ambient);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(implementation,required,arguments[implementation_operand]);if err!=blot_error::Error.none {return 0,err;}let err=self_.runnerHandler(id,operation.token,body_row,self_.ambient);if err!=blot_error::Error.none {return 0,err;}metadata.witness=arguments[state_operand];metadata.implementation=arguments[implementation_operand];metadata.implementation_type=required;if kind==EffectRunnerKind.reader {metadata.read_token=operation.token;}else {metadata.write_token=operation.token;}}let action,err=self_.expression(arguments[action_operand]);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(action,action_type,arguments[action_operand]);if err!=blot_error::Error.none {return 0,err;}if self_.effect_runners.len==0xffffffff {return 0,blot_error::Error.type_limit;}self_.effect_runners.push(metadata);self_.effect_runner_ids[id]=self_.effect_runners.len as u32;return metadata.result,blot_error::Error.none;}
recursive fn providerBlock(self_:Engine&,id:u32,provider_type:u32)->u32,blot_error::Error {let syntax=self_.tree.node(id);let root,err=self_.types.resolve(provider_type,0);if err!=blot_error::Error.none {return 0,err;}let provider=self_.types.node(root);let scope=self_.env.len;let target=self_.return_target;let owner=self_.owner;let ambient=self_.ambient;let storage_count=self_.storage_frames.len;var labels=IdBuffer{..};let result,error=providerBlockLabels(self_,id,syntax,provider,ambient,labels);labels.deinit(equation_type_ids);self_.storage_frames.resize(storage_count);self_.env.resize(scope);self_.return_target=target;self_.owner=owner;self_.ambient=ambient;return result,error;}
recursive fn providerBlockLabels(self_:Engine&,id:u32,syntax:blot_parse_ast::Node,provider:blot_check_types::Node,ambient:u32,labels:IdBuffer&)->u32,blot_error::Error {if provider.tag==blot_check_types::Tag.provider {let err=self_.constrainEffects(provider.c,ambient,syntax.c);if err!=blot_error::Error.none {return 0,err;}}var tokens:u32[2]=[provider.a,0];if provider.tag==blot_check_types::Tag.state_provider {tokens[1]=provider.b;}for token in tokens {if token==0 {continue;}let root,err=self_.types.resolve(token,0);if err!=blot_error::Error.none {return 0,err;}var nominal=self_.types.node(root);var instance=Identity{0,0, ..};if nominal.tag==blot_check_types::Tag.scoped {instance=Identity{nominal.b,nominal.c, ..};let root,err=self_.types.resolve(nominal.a,0);if err!=blot_error::Error.none {return 0,err;}nominal=self_.types.node(root);}if nominal.tag!=blot_check_types::Tag.nominal {return 0,blot_error::Error.type_limit;}let arguments=equation_type_ids.alloc_slice(self_.types.nominalArguments(nominal).len);let type_span_70=checkedNominalArguments(self_.types,nominal);for index in 0..(type_span_70.len as i64) {let value=self_.types.list(type_span_70)[index];arguments[index]=value;}let label,error=providerBlockToken(self_,nominal,instance,arguments);equation_type_ids.free_slice(arguments);if error!=blot_error::Error.none {return 0,error;}let err=labels.append(label);if err!=blot_error::Error.none {return 0,err;}}let outer,err=self_.types.resolveEffects(ambient,0);if err!=blot_error::Error.none {return 0,err;}let type_span_71=checkedRowLabels(self_.types,outer);for type_index_71 in 0..(type_span_71.len as i64) {let label=self_.types.effects.list(type_span_71)[type_index_71];let err=labels.append(label);if err!=blot_error::Error.none {return 0,err;}}let row,err=self_.types.effects.rowAt(labels.items,self_.types.row(outer).tail,self_.types.row(outer).cursor);if err!=blot_error::Error.none {return 0,blot_check_types::effectError(err);}self_.ambient=row;self_.owner=id;let initial,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}var result=initial;self_.return_target=result;let flow,err=self_.suite(id);if err!=blot_error::Error.none {return 0,err;}if !flow.exits {let err=self_.constrain(result,blot_check_types::unit,id);if err!=blot_error::Error.none {return 0,err;}}if flow.exits && flow.breaks && !flow.returns {result=blot_check_types::never;}var output=result;if provider.tag==blot_check_types::Tag.state_provider && result!=blot_check_types::never {let product,err=self_.types.product([provider.c,result]);if err!=blot_error::Error.none {return 0,err;}output=product;}if self_.provider_blocks.len==0xffffffff {return 0,blot_error::Error.type_limit;}self_.provider_blocks.push(ProviderBlock{node:id,provider:syntax.c,body_result:result,result:output,body_effects:row,outer_effects:ambient, ..});self_.provider_block_ids[id]=self_.provider_blocks.len as u32;return output,blot_error::Error.none;}
fn providerBlockToken(self_:Engine&,nominal:blot_check_types::Node,instance:Identity,arguments:u32[:])->u32,blot_error::Error {for &argument in arguments {let root,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return 0,err;}argument=root;}return self_.types.internScopedOperation(Identity{nominal.a,nominal.b, ..},instance,arguments);}
fn typeArity(self_:Engine&,source:u32,application:TypeApplication)->blot_error::Error {var point=self_.tree.type_conversion_origin(source);if application==TypeApplication.extra {point=self_.tree.span(source).start;}self_.diagnostics.push(Diagnostic{code:Code.type_arity,span:blot_parse_ast::Span{start:point,end:point, ..},node:source,type_application:blot_support::some(application), ..});return blot_error::Error.none;}
recursive fn argumentTypeNames(self_:Engine&,source:u32,depth:i64)->blot_error::Error {if depth>=1024 {return blot_error::Error.type_limit;}let node=self_.tree.node(source);if node.tag==blot_parse_ast::tag_type_name {let name=self_.pool.get(node.a);if name.len!=0 && ((name[0]>='a' as u8 && name[0]<='z' as u8) || name[0]=='_' as u8) && !firstDot(name).present {return blot_error::Error.none;}for builtin in ["Unit","Bool","U32","F32","Array","EffectSet","EffectDescriptor"] {if name==builtin {return blot_error::Error.none;}}if !self_.catalogs.nominal_names.contains(self_.catalogKey(node.a)) {let err=self_.diagnostic(Code.unsupported_type,source);if err!=blot_error::Error.none {return err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.tree.span(source).start;}return blot_error::Error.none;}if node.tag==blot_parse_ast::tag_group {return self_.argumentTypeNames(node.a,depth+1);}if node.tag==blot_parse_ast::tag_type_apply || node.tag==blot_parse_ast::tag_type_function {let err=self_.argumentTypeNames(node.a,depth+1);if err!=blot_error::Error.none {return err;}return self_.argumentTypeNames(node.b,depth+1);}if node.tag==blot_parse_ast::tag_type_product || node.tag==blot_parse_ast::tag_type_array {let syntax_source_29=source;let syntax_count_29=self_.tree.children(syntax_source_29).len;for syntax_index_29 in 0..syntax_count_29 {let child=self_.tree.children(syntax_source_29)[syntax_index_29];let err=self_.argumentTypeNames(child,depth+1);if err!=blot_error::Error.none {return err;}}}else if node.tag==blot_parse_ast::tag_type_record {let syntax_source_30=source;let syntax_count_30=self_.tree.children(syntax_source_30).len;for syntax_index_30 in 0..syntax_count_30 {let child=self_.tree.children(syntax_source_30)[syntax_index_30];let field=self_.tree.node(child);if field.b!=0 {let err=self_.argumentTypeNames(field.b,depth+1);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;}
fn applicationDiagnosticOrigin(self_:Engine&,before:i64,source:u32) {for &issue in self_.diagnostics[before..] {if !issue.type_application.present || issue.type_application.value==TypeApplication.extra {continue;}let point=self_.tree.type_conversion_origin(source);issue.span=blot_parse_ast::Span{start:point,end:point, ..};issue.node=source;}}
struct WithHandlerScope { env_base:i64=0, owner:u32=0, shadowed_start:i64=0, shadowed_len:i64=0 }
var with_handler_stack:WithHandlerScope[64]=[WithHandlerScope{};64];
var with_handler_len:i64=0;
var with_locked_bindings:u32[4096]=[0;4096];
var with_locked_len:i64=0;
var with_shadowed_runs:u32[4096]=[0;4096];
var with_shadowed_len:i64=0;
var with_shadowed_overflow:bool=false;
var with_active_labels:u32[1024]=[0;1024];
var with_active_foreign:bool[1024]=[false;1024];
var with_active_len:i64=0;
var fork_outer_ambients:u32[256]=[0;256];
var fork_outer_len:i64=0;
var fork_ambient_floor:i64=0;
struct ComptimeBinder { name:u32=0, binding:u32=0, target_ty:u32=0, is_variants:bool=false, builder:LoopFrame=LoopFrame{..} }
var comptime_binders:ComptimeBinder[32]=[ComptimeBinder{};32];
var comptime_binder_depth:i64[32]=[0;32];
var comptime_binder_len:i64=0;
var comptime_lambda_depth:i64=0;
var comptime_field_vars:u32[256]=[0;256];
var comptime_field_var_len:i64=0;
let comptime_meta_tag_base:u32=0x40000000;
fn resetWithState() { with_handler_len=0; with_locked_len=0; with_shadowed_len=0; with_shadowed_overflow=false; with_active_len=0; fork_outer_len=0; fork_ambient_floor=0; comptime_binder_len=0; comptime_lambda_depth=0; comptime_field_var_len=0; }
fn isActiveWithForeign(label:u32)->bool {
 var i=with_active_len;
 while i>0 {
  i-=1;
  if with_active_labels[i]==label { return with_active_foreign[i]; }
 }
 return false;
}
fn rowUsesForeign(self_:Engine&,row:u32)->bool,blot_error::Error {
 if row==0 { return false,blot_error::Error.none; }
 let resolved,rerr=self_.types.resolveEffects(row,0);
 if rerr!=blot_error::Error.none { return false,rerr; }
 let labels=self_.types.rowLabels(resolved);
 for lbl in labels {
  if lbl==blot_check_types::foreign_operation || isActiveWithForeign(lbl) { return true,blot_error::Error.none; }
 }
 return false,blot_error::Error.none;
}
fn checkComptimeCapture(self_:Engine&,bidx:i64,source:u32)->bool,blot_error::Error {
 if comptime_binder_depth[bidx]!=comptime_lambda_depth {
  let err=self_.diagnostic(Code.unsupported,source);
  if err!=blot_error::Error.none { return true,err; }
  self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Cannot capture compile-time `#for` binder inside a closure"));
  return true,blot_error::Error.none;
 }
 return false,blot_error::Error.none;
}
fn checkOpaqueNominal(self_:Engine&,ty:u32,source:u32)->blot_error::Error {
 if ty==0 { return blot_error::Error.none; }
 let resolved,err=self_.types.resolve(ty,0);
 if err!=blot_error::Error.none { return err; }
 var eff=resolved;
 let unw=blot_check_storage_types::sharedInner(self_.types,resolved);
 if unw.present {
  let inner,ierr=self_.types.resolve(unw.value,0);
  if ierr!=blot_error::Error.none { return ierr; }
  eff=inner;
 }
 let node=self_.types.node(eff);
 if node.tag==blot_check_types::Tag.nominal && !blot_check_storage_types::identity(node.a,node.b).present {
  let idx=self_.nominalIndex(Identity{node.a,node.b, ..});
  if idx.present {
   let def=self_.nominals[idx.value];
   if def.is_opaque && def.identity.unit!=self_.unit {
    return self_.diagnostic(Code.private_access,source);
   }
  }
 }
 return blot_error::Error.none;
}
fn removeSelfEntry(self_:Engine&,index:i64) {
 if index<0 || index>=self_.env.len { return; }
 var cursor=index;
 while cursor+1<self_.env.len {
  self_.env[cursor]=self_.env[cursor+1];
  cursor+=1;
 }
 self_.env.resize(self_.env.len-1);
}
fn findComptimeBinder(name:u32)->i64 {
 var i=comptime_binder_len;
 while i>0 { i-=1; if comptime_binders[i].name==name { return i; } }
 return -1;
}
fn recordComptimeFieldVar(self_:const Engine&,ty:u32) {
 let head=self_.types.head(ty,0);
 if head==0 || comptime_field_var_len>=256 { return; }
 for i in 0..comptime_field_var_len { if comptime_field_vars[i]==head { return; } }
 comptime_field_vars[comptime_field_var_len]=head;
 comptime_field_var_len+=1;
}
fn isComptimeFieldVar(self_:const Engine&,ty:u32)->bool {
 if comptime_field_var_len==0 || ty==0 { return false; }
 let head=self_.types.head(ty,0);
 for i in 0..comptime_field_var_len { if comptime_field_vars[i]==head { return true; } }
 let node=self_.types.node(head);
 if node.tag==blot_check_types::Tag.product {
  for idx in 0..node.b {
   let elem=self_.types.head(self_.types.extra.items[node.a+idx],0);
   for i in 0..comptime_field_var_len { if comptime_field_vars[i]==elem { return true; } }
  }
 }
 return false;
}
fn pendingHasComptimeFieldVar(self_:const Engine&,ob:blot_check_types::Obligation)->bool {
 if comptime_field_var_len==0 { return false; }
 return isComptimeFieldVar(self_,ob.ty) || isComptimeFieldVar(self_,ob.other);
}
fn constructorFieldDefault(self_:const Engine&,constructor:u32,field_name:u32)->u32 {
 if constructor==0 || constructor>=self_.constructors.len { return 0; }
 let ctor=self_.constructors[constructor];
 if ctor.identity.unit!=self_.unit { return 0; }
 let nom=self_.nominals[ctor.nominal];
 if nom.declaration==0 { return 0; }
 let decl_children=self_.tree.children(self_.tree.node(nom.declaration).b);
 if (ctor.tag as i64)>=decl_children.len { return 0; }
 let cnode=self_.tree.node(decl_children[ctor.tag]);
 if cnode.tag!=blot_parse_ast::tag_constructor_ref || cnode.b==0 { return 0; }
 let pnode=self_.tree.node(cnode.b);
 if pnode.tag!=blot_parse_ast::tag_type_record { return 0; }
 let count=self_.tree.children(cnode.b).len;
 for idx in 0..count {
  let fid=self_.tree.children(cnode.b)[idx];
  let fnode=self_.tree.node(fid);
  if fnode.a==field_name && fnode.c!=0 { return self_.tree.extra.items[fnode.c+1]; }
 }
 return 0;
}
fn checkDataTagsAndDefaults(self_:Engine&)->blot_error::Error {
 if self_.source_validation { return blot_error::Error.none; }
 let saved_ambient=self_.ambient;
 let saved_owner=self_.owner;
 let saved_current=self_.current;
 let saved_env_len=self_.env.len;
 self_.ambient=0;
 self_.owner=0;
 self_.current=0;
 self_.env.resize(0);
 var err=blot_error::Error.none;
 for ordinal in 1..self_.nominals.len {
  let nominal=self_.nominals[ordinal];
  if nominal.identity.unit!=self_.unit { continue; }
  let dnode=self_.tree.node(nominal.declaration);
  if dnode.tag!=blot_parse_ast::tag_data_decl { continue; }
  let meta=checkedAstRange(self_.tree,dnode.c,dnode.c+4);
  let attr_list=blot_parse_ast::List{self_.tree.list(meta)[2],self_.tree.list(meta)[3], ..};
  let attr_count=self_.tree.list(attr_list).len;
  for ai in 0..attr_count {
   let attr_id=self_.tree.list(attr_list)[ai];
   let _,aerr=self_.pureExpression(self_.tree.node(attr_id).a,0);
   if aerr!=blot_error::Error.none { err=aerr; break; }
  }
  if err!=blot_error::Error.none { break; }
  let ccount=self_.tree.children(dnode.b).len;
  for ci in 0..ccount {
   let cid=self_.tree.children(dnode.b)[ci];
   let cnode=self_.tree.node(cid);
   if cnode.c!=0 {
    let clist=blot_parse_ast::List{self_.tree.extra.items[cnode.c-1],self_.tree.extra.items[cnode.c], ..};
    let calen=self_.tree.list(clist).len;
    for ai in 0..calen {
     let attr_id=self_.tree.list(clist)[ai];
     let _,aerr=self_.pureExpression(self_.tree.node(attr_id).a,0);
     if aerr!=blot_error::Error.none { err=aerr; break; }
    }
    if err!=blot_error::Error.none { break; }
   }
   if cnode.b!=0 && self_.tree.node(cnode.b).tag==blot_parse_ast::tag_type_record {
    let fcount=self_.tree.children(cnode.b).len;
    var has_any_default=false;
    for fi in 0..fcount {
     let fid=self_.tree.children(cnode.b)[fi];
     let fnode=self_.tree.node(fid);
     if fnode.c!=0 && self_.tree.extra.items[fnode.c+1]!=0 { has_any_default=true; break; }
    }
    var payload_ty:u32=0;
    if has_any_default {
     let ctor_idx=self_.constructor_resolved[cid];
     if ctor_idx!=0 && ctor_idx<self_.constructors.len && self_.constructors[ctor_idx].payload!=0 {
      let orig_payload=self_.constructors[ctor_idx].payload;
      if nominal.variables.len==0 {
       payload_ty=orig_payload;
      } else {
       let old=equation_type_ids.alloc_slice(nominal.variables.len);
       let rigids=equation_type_ids.alloc_slice(nominal.variables.len);
       for vi in 0..(nominal.variables.len as i64) {
        old[vi]=self_.types.list(nominal.variables)[vi];
        let r,rerr=self_.types.rigid(nominal.declaration,vi as u32,0);
        if rerr!=blot_error::Error.none { err=rerr; break; }
        rigids[vi]=r;
       }
       if err==blot_error::Error.none {
        let sub,serr=self_.types.substitute(orig_payload,old,rigids);
        if serr!=blot_error::Error.none { err=serr; }
        else { payload_ty=sub; }
       }
       equation_type_ids.free_slice(rigids);
       equation_type_ids.free_slice(old);
       if err!=blot_error::Error.none { break; }
      }
     }
    }
    for fi in 0..fcount {
     let fid=self_.tree.children(cnode.b)[fi];
     let fnode=self_.tree.node(fid);
     if fnode.c==0 { continue; }
     let flist=blot_parse_ast::List{self_.tree.extra.items[fnode.c-1],self_.tree.extra.items[fnode.c], ..};
     let falen=self_.tree.list(flist).len;
     for ai in 0..falen {
      let attr_id=self_.tree.list(flist)[ai];
      let _,aerr=self_.pureExpression(self_.tree.node(attr_id).a,0);
      if aerr!=blot_error::Error.none { err=aerr; break; }
     }
     if err!=blot_error::Error.none { break; }
     let def_expr=self_.tree.extra.items[fnode.c+1];
     if def_expr!=0 {
      let def_ty,derr=self_.pureExpression(def_expr,0);
      if derr!=blot_error::Error.none { err=derr; break; }
      if payload_ty!=0 {
       let pnode=self_.types.node(payload_ty);
       if pnode.tag==blot_check_types::Tag.record {
        for pi in 0..pnode.b {
         let decl_f=self_.types.recordField(pnode,pi);
         if decl_f.name==fnode.a {
          let cerr=self_.constrain(def_ty,decl_f.ty,def_expr);
          if cerr!=blot_error::Error.none { err=cerr; }
          break;
         }
        }
       }
      }
      if err!=blot_error::Error.none { break; }
     }
    }
    if err!=blot_error::Error.none { break; }
   }
  }
  if err!=blot_error::Error.none { break; }
 }
 self_.ambient=saved_ambient;
 self_.owner=saved_owner;
 self_.current=saved_current;
 self_.env.resize(saved_env_len);
 return err;
}
fn isWithLocked(binding:u32)->bool { for i in 0..with_locked_len { if with_locked_bindings[i]==binding { return true; } } return false; }
fn findWithOuterTarget(self_:const Engine&,previous:u32)->u32 {
 if with_handler_len==0 || previous==0 { return 0; }
 let top=with_handler_stack[with_handler_len-1];
 var cur=previous;
 var steps:i64=0;
 while cur!=0 && steps<256 {
  let b=self_.bindings[cur];
  if b.kind==blot_reuse_principal_interface::Kind.global || b.kind==blot_reuse_principal_interface::Kind.external { return 0; }
  for entry in self_.env[..top.env_base] {
   if entry.binding==cur { return cur; }
  }
  cur=b.predecessor;
  steps+=1;
 }
 return 0;
}
fn recordWithShadowed(outer_b:u32) {
 if with_handler_len==0 || outer_b==0 { return; }
 let idx=with_handler_len-1;
 let start=with_handler_stack[idx].shadowed_start;
 let end=start+with_handler_stack[idx].shadowed_len;
 for i in start..end { if with_shadowed_runs[i]==outer_b { return; } }
 if with_shadowed_len>=4096 { with_shadowed_overflow=true; return; }
 with_shadowed_runs[with_shadowed_len]=outer_b;
 with_shadowed_len+=1;
 with_handler_stack[idx].shadowed_len+=1;
}
fn effectFamilyNominal(self_:const Engine&,ty:u32)->blot_support::Option<u32> {
 if ty==0 { return blot_support::none<u32>(); }
 let root=self_.types.head(ty,0);
 let node=self_.types.node(root);
 if node.tag!=blot_check_types::Tag.nominal { return blot_support::none<u32>(); }
 let found .= self_.catalogs.effect_family_identities.get(Identity{node.a,node.b, ..});
 if !found { return blot_support::none<u32>(); }
 let family_idx:u32=found;
 return blot_support::some(family_idx);
}
recursive fn effectRecordAnnotation(self_:Engine&,family_idx:u32,arguments:const u32[:],source:u32)->u32,blot_error::Error {
 let family=self_.effect_families[family_idx];
 if arguments.len!=family.parameters.len {
  var application=TypeApplication.extra;
  if arguments.len<family.parameters.len { application=TypeApplication.missing_nominal; }
  let err=self_.typeArity(source,application);
  if err!=blot_error::Error.none { return 0,err; }
  return self_.types.fresh();
 }
 let old=equation_type_ids.alloc_slice(family.variables.len);
 for ordinal in 0..family.variables.len { old[ordinal]=self_.types.list(family.variables)[ordinal]; }
 let fresh=equation_type_ids.alloc_slice(old.len);
 let shapes=equation_type_ids.alloc_slice(family.parameters.len);
 for ordinal in 0..family.parameters.len { shapes[ordinal]=self_.types.list(family.parameters)[ordinal]; }
 var args=IdBuffer{..};
 var failure=blot_error::Error.none;
 for &v in fresh { let fv,err=self_.types.fresh(); if err!=blot_error::Error.none { failure=err; break; } v=fv; }
 if failure==blot_error::Error.none {
  for argument,ordinal in arguments {
   let pattern=self_.parameter_patterns.list(family.patterns)[ordinal];
   let actual,err=self_.parameterArgument(pattern,argument,true,0);
   if err!=blot_error::Error.none { failure=err; break; }
   let selected,err=self_.types.substitute(shapes[ordinal],old,fresh);
   if err!=blot_error::Error.none { failure=err; break; }
   let cerr=self_.constrain(selected,actual,argument);
   if cerr!=blot_error::Error.none { failure=cerr; break; }
   let root,err=self_.types.resolve(selected,0);
   if err!=blot_error::Error.none { failure=err; break; }
   let aerr=args.append(root);
   if aerr!=blot_error::Error.none { failure=aerr; break; }
  }
 }
 var res:u32=0;
 if failure==blot_error::Error.none {
  let nom,err=self_.types.nominal(family.identity,args.items);
  res=nom; failure=err;
 }
 args.deinit(equation_type_ids);
 equation_type_ids.free_slice(shapes);
 equation_type_ids.free_slice(fresh);
 equation_type_ids.free_slice(old);
 return res,failure;
}
recursive fn instantiateEffectOpTypes(self_:Engine&,family_idx:u32,nom_args:const u32[:],row:u32,source:u32,out_sigs:IdBuffer&)->blot_error::Error {
 let family=self_.effect_families[family_idx];
 let old=equation_type_ids.alloc_slice(family.variables.len);
 for ordinal in 0..family.variables.len { old[ordinal]=self_.types.list(family.variables)[ordinal]; }
 let fresh=equation_type_ids.alloc_slice(old.len);
 let shapes=equation_type_ids.alloc_slice(family.parameters.len);
 for ordinal in 0..family.parameters.len { shapes[ordinal]=self_.types.list(family.parameters)[ordinal]; }
 var failure=blot_error::Error.none;
 for &v in fresh { let fv,err=self_.types.fresh(); if err!=blot_error::Error.none { failure=err; break; } v=fv; }
 if failure==blot_error::Error.none {
  for shape,ordinal in shapes {
   let selected,err=self_.types.substitute(shape,old,fresh);
   if err!=blot_error::Error.none { failure=err; break; }
   let cerr=self_.constrain(selected,nom_args[ordinal],source);
   if cerr!=blot_error::Error.none { failure=cerr; break; }
  }
 }
 if failure==blot_error::Error.none {
  let ops=checkedTypeList(self_.types,family.operations);
  for op_i in 0..(ops.len as i64) {
   let tmpl_idx=self_.types.list(ops)[op_i];
   let tmpl=self_.effect_templates[tmpl_idx];
   let param,perr=self_.types.substitute(tmpl.parameter,old,fresh);
   if perr!=blot_error::Error.none { failure=perr; break; }
   let res,rerr=self_.types.substitute(tmpl.result,old,fresh);
   if rerr!=blot_error::Error.none { failure=rerr; break; }
   var op_row=row;
   if row==0xffffffff {
    let frow,ferr=self_.types.freshEffects();
    if ferr!=blot_error::Error.none { failure=ferr; break; }
    op_row=frow;
   }
   let sig,serr=self_.types.functionWithEffects(param,res,op_row);
   if serr!=blot_error::Error.none { failure=serr; break; }
   let aerr=out_sigs.append(sig);
   if aerr!=blot_error::Error.none { failure=aerr; break; }
  }
 }
 equation_type_ids.free_slice(shapes);
 equation_type_ids.free_slice(fresh);
 equation_type_ids.free_slice(old);
 return failure;
}
recursive fn checkEffectRecordValue(self_:Engine&,source:u32,required:u32,family_idx:u32,outer_ambient:u32,allow_effects:bool,out_op_sigs:IdBuffer&,out_op_nodes:IdBuffer&,out_op_foreign:IdBuffer&)->u32,blot_error::Error {
 let family=self_.effect_families[family_idx];
 let resolved,rerr=self_.types.resolve(required,0);
 if rerr!=blot_error::Error.none { return 0,rerr; }
 let nom_node=self_.types.node(resolved);
 let arg_count=self_.types.nominalArguments(nom_node).len;
 let nom_args=equation_type_ids.alloc_slice(arg_count);
 for ai in 0..arg_count { nom_args[ai]=self_.types.nominalArguments(nom_node)[ai]; }
 var row_mode:u32=0;
 if allow_effects { row_mode=0xffffffff; }
 let ierr=self_.instantiateEffectOpTypes(family_idx,nom_args,row_mode,source,out_op_sigs);
 equation_type_ids.free_slice(nom_args);
 if ierr!=blot_error::Error.none { return 0,ierr; }
 let ops=checkedTypeList(self_.types,family.operations);
 let op_count=ops.len as i64;
 let syntax=self_.tree.node(source);
 if family.callable {
  let tmpl_idx=self_.types.list(ops)[0];
  let expected_sig=out_op_sigs.items[0];
  let actual,err=self_.contextualLambda(source,expected_sig);
  if err!=blot_error::Error.none { return 0,err; }
  let cerr=self_.constrain(actual,expected_sig,source);
  if cerr!=blot_error::Error.none { return 0,cerr; }
  var uses_foreign=false;
  if allow_effects {
   let sferr=self_.solveFields();
   if sferr!=blot_error::Error.none { return 0,sferr; }
   let op_row=self_.types.node(self_.types.head(expected_sig,0)).c;
   let uf,uerr=self_.rowUsesForeign(op_row);
   if uerr!=blot_error::Error.none { return 0,uerr; }
   uses_foreign=uf;
   let eerr=self_.constrainEffects(op_row,outer_ambient,source);
   if eerr!=blot_error::Error.none { return 0,eerr; }
  }
  var uf_flag:u32=0;if uses_foreign { uf_flag=1; }
  let af=out_op_foreign.append(uf_flag); if af!=blot_error::Error.none { return 0,af; }
  let a1=out_op_nodes.append(tmpl_idx); if a1!=blot_error::Error.none { return 0,a1; }
  let a2=out_op_nodes.append(source); if a2!=blot_error::Error.none { return 0,a2; }
  self_.expr_types[source]=required;
  return required,blot_error::Error.none;
 }
 let supplied=boolean_runs.alloc_slice(op_count);
 let op_foreign=boolean_runs.alloc_slice(op_count);
 let field_asts=equation_type_ids.alloc_slice(op_count);
 for oi in 0..op_count { supplied[oi]=false; op_foreign[oi]=false; field_asts[oi]=0; }
 var failure=blot_error::Error.none;
 let child_count=self_.tree.children(source).len;
 for ci in 0..child_count {
  let child=self_.tree.children(source)[ci];
  let field=self_.tree.node(child);
  var found=false;
  for oi in 0..op_count {
   let tmpl_idx=self_.types.list(ops)[oi];
   if self_.effect_templates[tmpl_idx].name==field.a {
    found=true;
    if supplied[oi] {
     let derr=self_.diagnostic(Code.duplicate_field,child);
     if derr!=blot_error::Error.none { failure=derr; }
     break;
    }
    supplied[oi]=true;
    field_asts[oi]=child;
    self_.projections[child]=oi as u32;
    let expected_sig=out_op_sigs.items[oi];
    var actual:u32=0;
    if field.b==0 {
     let sh,serr=self_.shorthand(child,field.a);
     if serr!=blot_error::Error.none { failure=serr; break; }
     actual=sh;
    } else {
     let ev,eerr=self_.contextualLambda(field.b,expected_sig);
     if eerr!=blot_error::Error.none { failure=eerr; break; }
     actual=ev;
    }
    let cerr=self_.constrain(actual,expected_sig,child);
    if cerr!=blot_error::Error.none { failure=cerr; break; }
    if allow_effects {
     let sferr=self_.solveFields();
     if sferr!=blot_error::Error.none { failure=sferr; break; }
     let op_row=self_.types.node(self_.types.head(expected_sig,0)).c;
     let uf,uerr=self_.rowUsesForeign(op_row);
     if uerr!=blot_error::Error.none { failure=uerr; break; }
     op_foreign[oi]=uf;
     let eerr=self_.constrainEffects(op_row,outer_ambient,child);
     if eerr!=blot_error::Error.none { failure=eerr; break; }
    }
    self_.expr_types[child]=expected_sig;
    break;
   }
  }
  if failure!=blot_error::Error.none { break; }
  if !found {
   let derr=self_.diagnostic(Code.unknown_field,child);
   if derr!=blot_error::Error.none { failure=derr; break; }
  }
 }
 if failure==blot_error::Error.none {
  for oi in 0..op_count {
   if !supplied[oi] {
    let derr=self_.diagnostic(Code.missing_field,source);
    if derr!=blot_error::Error.none { failure=derr; break; }
    break;
   }
   let tmpl_idx=self_.types.list(ops)[oi];
   var of_flag:u32=0;if op_foreign[oi] { of_flag=1; }
   let af=out_op_foreign.append(of_flag); if af!=blot_error::Error.none { failure=af; break; }
   let a1=out_op_nodes.append(tmpl_idx); if a1!=blot_error::Error.none { failure=a1; break; }
   let a2=out_op_nodes.append(field_asts[oi]); if a2!=blot_error::Error.none { failure=a2; break; }
  }
 }
 equation_type_ids.free_slice(field_asts);
 boolean_runs.free_slice(op_foreign);
 boolean_runs.free_slice(supplied);
 if failure!=blot_error::Error.none { return 0,failure; }
 self_.expr_types[source]=required;
 return required,blot_error::Error.none;
}
recursive fn withStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {
 let node=self_.tree.node(id);
 let outer_ambient=self_.ambient;
 let base_env_len=self_.env.len;
 if with_handler_len>=64 { return Flow{..},blot_error::Error.type_limit; }
 with_handler_stack[with_handler_len]=WithHandlerScope{ env_base:base_env_len, owner:self_.owner, shadowed_start:with_shadowed_len, shadowed_len:0 };
 with_handler_len+=1;
 var handled_labels=IdBuffer{..};
 var handled_foreign=IdBuffer{..};
 let entries=blot_parse_ast::List{node.a,node.b, ..};
 let entry_count=self_.tree.list(entries).len;
 var failure=blot_error::Error.none;
 for ei in 0..entry_count {
  let entry_id=self_.tree.list(entries)[ei];
  let entry=self_.tree.node(entry_id);
  if entry.c==1 {
   var rev_args=IdBuffer{..};
   var head=entry.a;
   while self_.tree.node(head).tag==blot_parse_ast::tag_type_apply {
    let aerr=rev_args.append(self_.tree.node(head).b);
    if aerr!=blot_error::Error.none { failure=aerr; break; }
    head=self_.tree.node(head).a;
   }
   if failure!=blot_error::Error.none { rev_args.deinit(equation_type_ids); break; }
   reverseIds(rev_args.items);
   let head_node=self_.tree.node(head);
   if head_node.tag==blot_parse_ast::tag_type_name && self_.pool.get(head_node.a)=="Foreign" {
    let derr=self_.diagnostic(Code.sealed_effect,entry.a);
    rev_args.deinit(equation_type_ids);
    if derr!=blot_error::Error.none { failure=derr; break; }
    continue;
   }
   var has_ef=false; var family_idx:u32=0;
   if head_node.tag==blot_parse_ast::tag_type_name {
    let lk .= self_.catalogs.effect_family_names.get(self_.catalogKey(head_node.a));
    if lk { family_idx=lk; has_ef=true; }
   }
   if !has_ef {
    let derr=self_.diagnostic(Code.unknown_effect,entry.a);
    rev_args.deinit(equation_type_ids);
    if derr!=blot_error::Error.none { failure=derr; break; }
    continue;
   }
   let effect_nom,nerr=self_.effectRecordAnnotation(family_idx,rev_args.items,entry.a);
   rev_args.deinit(equation_type_ids);
   if nerr!=blot_error::Error.none { failure=nerr; break; }
   let family=self_.effect_families[family_idx];
   let resolved_nom,rnerr=self_.types.resolve(effect_nom,0);
   if rnerr!=blot_error::Error.none { failure=rnerr; break; }
   let nom_node=self_.types.node(resolved_nom);
   if nom_node.tag!=blot_check_types::Tag.nominal { continue; }
   var handler_src=entry.b;
   while self_.tree.node(handler_src).tag==blot_parse_ast::tag_group { handler_src=self_.tree.node(handler_src).a; }
   let handler_tag=self_.tree.node(handler_src).tag;
   let is_inline=(!family.callable && handler_tag==blot_parse_ast::tag_record && self_.tree.node(handler_src).a==0) || (family.callable && handler_tag==blot_parse_ast::tag_lambda);
   var op_sigs=IdBuffer{..};
   var op_nodes=IdBuffer{..};
   var op_foreign=IdBuffer{..};
   if is_inline {
    let _,cerr=self_.checkEffectRecordValue(handler_src,effect_nom,family_idx,outer_ambient,true,op_sigs,op_nodes,op_foreign);
    if cerr!=blot_error::Error.none { op_sigs.deinit(equation_type_ids); op_nodes.deinit(equation_type_ids); op_foreign.deinit(equation_type_ids); failure=cerr; break; }
    self_.expr_types[entry.b]=effect_nom;
    self_.projections[entry_id]=1;
   } else {
    let actual,eerr=self_.contextualLambda(entry.b,effect_nom);
    if eerr!=blot_error::Error.none { op_sigs.deinit(equation_type_ids); op_nodes.deinit(equation_type_ids); op_foreign.deinit(equation_type_ids); failure=eerr; break; }
    let cerr=self_.constrain(actual,effect_nom,entry.b);
    if cerr!=blot_error::Error.none { op_sigs.deinit(equation_type_ids); op_nodes.deinit(equation_type_ids); op_foreign.deinit(equation_type_ids); failure=cerr; break; }
    let arg_n=self_.types.nominalArguments(nom_node).len;
    let na=equation_type_ids.alloc_slice(arg_n);
    for ai in 0..arg_n { na[ai]=self_.types.nominalArguments(nom_node)[ai]; }
    let ierr=self_.instantiateEffectOpTypes(family_idx,na,0,entry_id,op_sigs);
    equation_type_ids.free_slice(na);
    if ierr!=blot_error::Error.none { op_sigs.deinit(equation_type_ids); op_nodes.deinit(equation_type_ids); op_foreign.deinit(equation_type_ids); failure=ierr; break; }
    let ops=checkedTypeList(self_.types,family.operations);
    for oi in 0..(ops.len as i64) {
     let a1=op_nodes.append(self_.types.list(ops)[oi]); if a1!=blot_error::Error.none { failure=a1; break; }
     let a2=op_nodes.append(oi as u32); if a2!=blot_error::Error.none { failure=a2; break; }
    }
    if failure!=blot_error::Error.none { op_sigs.deinit(equation_type_ids); op_nodes.deinit(equation_type_ids); op_foreign.deinit(equation_type_ids); break; }
    self_.projections[entry_id]=0;
   }
   var saved_types=IdBuffer{..};
   let arg_n=self_.types.nominalArguments(nom_node).len;
   let na=equation_type_ids.alloc_slice(arg_n);
   for ai in 0..arg_n {
    let a=self_.types.nominalArguments(nom_node)[ai];
    na[ai]=a;
    let aerr=saved_types.append(a);
    if aerr!=blot_error::Error.none { failure=aerr; break; }
   }
   if failure==blot_error::Error.none {
    for sig in op_sigs.items { let aerr=saved_types.append(sig); if aerr!=blot_error::Error.none { failure=aerr; break; } }
   }
   if failure==blot_error::Error.none {
    let ops=checkedTypeList(self_.types,family.operations);
    var dup_reported=false;
    for oi in 0..(ops.len as i64) {
     let tmpl=self_.effect_templates[self_.types.list(ops)[oi]];
     let lbl,lerr=self_.types.internScopedOperation(tmpl.identity,Identity{0,0, ..},na);
     if lerr!=blot_error::Error.none { failure=lerr; break; }
     if inList(handled_labels.items,lbl) {
      if !dup_reported {
       dup_reported=true;
       let derr=self_.diagnostic(Code.duplicate_request_handler,entry_id);
       if derr!=blot_error::Error.none { failure=derr; break; }
       self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Duplicate effect handler in the same `with` clause"));
      }
     } else {
      let aerr=handled_labels.append(lbl);
      if aerr!=blot_error::Error.none { failure=aerr; break; }
      var is_foreign:u32=0;
      if is_inline && oi<op_foreign.items.len { is_foreign=op_foreign.items[oi]; }
      let ferr=handled_foreign.append(is_foreign);
      if ferr!=blot_error::Error.none { failure=ferr; break; }
     }
    }
   }
   equation_type_ids.free_slice(na);
   if failure==blot_error::Error.none {
    let tl,terr=self_.types.saveList(saved_types.items);
    if terr!=blot_error::Error.none { failure=terr; }
    else {
     let nl,nlerr=self_.types.saveList(op_nodes.items);
     if nlerr!=blot_error::Error.none { failure=nlerr; }
     else {
      self_.resolved[entry_id]=family_idx;
      self_.access_types[entry_id]=tl;
      self_.access_nodes[entry_id]=nl;
      self_.expr_types[entry_id]=effect_nom;
     }
    }
   }
   saved_types.deinit(equation_type_ids);
   op_sigs.deinit(equation_type_ids);
   op_nodes.deinit(equation_type_ids);
   op_foreign.deinit(equation_type_ids);
   if failure!=blot_error::Error.none { break; }
  } else {
   let actual,eerr=self_.expression(entry.a);
   if eerr!=blot_error::Error.none { failure=eerr; break; }
   let resolved,rerr=self_.types.resolve(actual,0);
   if rerr!=blot_error::Error.none { failure=rerr; break; }
   let ef_opt=self_.effectFamilyNominal(resolved);
   if !ef_opt.present {
    let derr=self_.diagnostic(Code.invalid_provider,entry.a);
    if derr!=blot_error::Error.none { failure=derr; break; }
    continue;
   }
   let family_idx=ef_opt.value;
   let family=self_.effect_families[family_idx];
   let nom_node=self_.types.node(resolved);
   let arg_n=self_.types.nominalArguments(nom_node).len;
   let na=equation_type_ids.alloc_slice(arg_n);
   for ai in 0..arg_n { na[ai]=self_.types.nominalArguments(nom_node)[ai]; }
   var op_sigs=IdBuffer{..};
   var op_nodes=IdBuffer{..};
   var saved_types=IdBuffer{..};
   let ierr=self_.instantiateEffectOpTypes(family_idx,na,0,entry_id,op_sigs);
   if ierr!=blot_error::Error.none { failure=ierr; }
   if failure==blot_error::Error.none {
    for ai in 0..arg_n { let aerr=saved_types.append(na[ai]); if aerr!=blot_error::Error.none { failure=aerr; break; } }
   }
   if failure==blot_error::Error.none {
    for sig in op_sigs.items { let aerr=saved_types.append(sig); if aerr!=blot_error::Error.none { failure=aerr; break; } }
   }
   if failure==blot_error::Error.none {
    let ops=checkedTypeList(self_.types,family.operations);
    var dup_reported=false;
    for oi in 0..(ops.len as i64) {
     let tmpl_idx=self_.types.list(ops)[oi];
     let tmpl=self_.effect_templates[tmpl_idx];
     let lbl,lerr=self_.types.internScopedOperation(tmpl.identity,Identity{0,0, ..},na);
     if lerr!=blot_error::Error.none { failure=lerr; break; }
     if inList(handled_labels.items,lbl) {
      if !dup_reported {
       dup_reported=true;
       let derr=self_.diagnostic(Code.duplicate_request_handler,entry_id);
       if derr!=blot_error::Error.none { failure=derr; break; }
       self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Duplicate effect handler in the same `with` clause"));
      }
     } else {
      let a1=handled_labels.append(lbl); if a1!=blot_error::Error.none { failure=a1; break; }
      let f1=handled_foreign.append(0); if f1!=blot_error::Error.none { failure=f1; break; }
     }
     let a2=op_nodes.append(tmpl_idx); if a2!=blot_error::Error.none { failure=a2; break; }
     let a3=op_nodes.append(oi as u32); if a3!=blot_error::Error.none { failure=a3; break; }
    }
   }
   equation_type_ids.free_slice(na);
   if failure==blot_error::Error.none {
    let tl,terr=self_.types.saveList(saved_types.items);
    if terr!=blot_error::Error.none { failure=terr; }
    else {
     let nl,nlerr=self_.types.saveList(op_nodes.items);
     if nlerr!=blot_error::Error.none { failure=nlerr; }
     else {
      self_.resolved[entry_id]=family_idx;
      self_.access_types[entry_id]=tl;
      self_.access_nodes[entry_id]=nl;
      self_.projections[entry_id]=0;
      self_.expr_types[entry_id]=resolved;
     }
    }
   }
   saved_types.deinit(equation_type_ids);
   op_sigs.deinit(equation_type_ids);
   op_nodes.deinit(equation_type_ids);
   if failure!=blot_error::Error.none { break; }
  }
 }
 let top=with_handler_stack[with_handler_len-1];
 with_handler_len-=1;
 if with_shadowed_overflow {
  with_shadowed_overflow=false;
  with_shadowed_len=top.shadowed_start;
  handled_labels.deinit(equation_type_ids);
  handled_foreign.deinit(equation_type_ids);
  return Flow{..},blot_error::Error.type_limit;
 }
 if failure!=blot_error::Error.none {
  with_shadowed_len=top.shadowed_start;
  handled_labels.deinit(equation_type_ids);
  handled_foreign.deinit(equation_type_ids);
  return Flow{..},failure;
 }
 let locked_mark=with_locked_len;
 for si in top.shadowed_start..(top.shadowed_start+top.shadowed_len) {
  if with_locked_len>=4096 {
   with_locked_len=locked_mark;
   with_shadowed_len=top.shadowed_start;
   handled_labels.deinit(equation_type_ids);
   handled_foreign.deinit(equation_type_ids);
   return Flow{..},blot_error::Error.type_limit;
  }
  with_locked_bindings[with_locked_len]=with_shadowed_runs[si];
  with_locked_len+=1;
 }
 let outer_resolved,orerr=self_.types.resolveEffects(outer_ambient,0);
 if orerr!=blot_error::Error.none {
  with_locked_len=locked_mark;
  with_shadowed_len=top.shadowed_start;
  handled_labels.deinit(equation_type_ids);
  handled_foreign.deinit(equation_type_ids);
  return Flow{..},orerr;
 }
 let active_mark=with_active_len;
 for hi in 0..handled_foreign.items.len {
  if with_active_len>=1024 {
   with_active_len=active_mark;
   with_locked_len=locked_mark;
   with_shadowed_len=top.shadowed_start;
   handled_labels.deinit(equation_type_ids);
   handled_foreign.deinit(equation_type_ids);
   return Flow{..},blot_error::Error.type_limit;
  }
  with_active_labels[with_active_len]=handled_labels.items[hi];
  with_active_foreign[with_active_len]=handled_foreign.items[hi]!=0;
  with_active_len+=1;
 }
 handled_foreign.deinit(equation_type_ids);
 let outer_labels=checkedRowLabels(self_.types,outer_resolved);
 for oi in 0..(outer_labels.len as i64) {
  let aerr=handled_labels.append(self_.types.effects.list(outer_labels)[oi]);
  if aerr!=blot_error::Error.none {
   with_active_len=active_mark;
   with_locked_len=locked_mark;
   with_shadowed_len=top.shadowed_start;
   handled_labels.deinit(equation_type_ids);
   return Flow{..},aerr;
  }
 }
 let extended_row,ererr=self_.types.effects.rowAt(handled_labels.items,self_.types.row(outer_resolved).tail,self_.types.row(outer_resolved).cursor);
 handled_labels.deinit(equation_type_ids);
 if ererr!=blot_error::Error.none {
  with_active_len=active_mark;
  with_locked_len=locked_mark;
  with_shadowed_len=top.shadowed_start;
  return Flow{..},blot_check_types::effectError(ererr);
 }
 let base=global_entry_runs.alloc_slice(self_.env.len);
 for entry,index in self_.env { base[index]=entry; }
 self_.ambient=extended_row;
 let flow,serr=self_.suite(node.c);
 self_.ambient=outer_ambient;
 with_active_len=active_mark;
 with_locked_len=locked_mark;
 if serr!=blot_error::Error.none {
  if base.len!=0 { global_entry_runs.free_slice(base); }
  with_shadowed_len=top.shadowed_start;
  return Flow{..},serr;
 }
 for &entry in base { entry.binding=self_.latestSuccessor(entry.binding); }
 self_.env.clear();
 self_.env.append(base);
 if base.len!=0 { global_entry_runs.free_slice(base); }
 var cell_pairs=IdBuffer{..};
 for si in top.shadowed_start..(top.shadowed_start+top.shadowed_len) {
  let outer_b=with_shadowed_runs[si];
  let ob=self_.bindings[outer_b];
  let after_b,berr=self_.addBinding(Binding{ read:true, name:ob.name, declaration:id, owner:self_.owner, kind:blot_reuse_principal_interface::Kind.local, ty:ob.ty, scheme:blot_check_types::Scheme{root:ob.ty, ..}, predecessor:outer_b, .. });
  if berr!=blot_error::Error.none { failure=berr; break; }
  self_.env.push(Entry{ name:ob.name, binding:after_b, .. });
  let a1=cell_pairs.append(outer_b); if a1!=blot_error::Error.none { failure=a1; break; }
  let a2=cell_pairs.append(after_b); if a2!=blot_error::Error.none { failure=a2; break; }
 }
 with_shadowed_len=top.shadowed_start;
 if failure==blot_error::Error.none {
  let cl,cerr=self_.types.saveList(cell_pairs.items);
  if cerr!=blot_error::Error.none { failure=cerr; }
  else { self_.access_nodes[id]=cl; }
 }
 cell_pairs.deinit(equation_type_ids);
 if failure!=blot_error::Error.none { return Flow{..},failure; }
 self_.expr_types[id]=blot_check_types::unit;
 if flow.exits { self_.expr_types[id]=blot_check_types::never; }
 return flow,blot_error::Error.none;
}
recursive fn nominalAnnotation(self_:Engine&,head:u32,arguments:const u32[:],source:u32)->u32,blot_error::Error {if self_.editorAt(head) {for argument in arguments {let root,err=self_.annotation(argument);if err!=blot_error::Error.none {return 0,err;}}let result,err=self_.captureEditor(head,0,self_.catalogKey(self_.tree.node(head).a).namespace_);if err!=blot_error::Error.none {return 0,err;}self_.editor_capture.value.kind=blot_reuse_completion_probe::Kind.type_;self_.expr_types[head]=result;return result,blot_error::Error.none;}let name=self_.tree.node(head).a;let text=self_.pool.get(name);let len_lit=blot_check_storage_types::parseLengthLiteral(text);if len_lit.present {if arguments.len!=0 {let err=self_.typeArity(source,TypeApplication.extra);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}return blot_check_storage_types::makeLengthLiteral(self_.types,len_lit.value);}let storage=blot_check_storage_types::named(text);if storage.present && (starts_with(text,"@storage.") || !self_.catalogs.nominal_names.contains(self_.catalogKey(name))) {let want_arity=blot_check_storage_types::arity(storage.value);if arguments.len!=want_arity {var application=TypeApplication.extra;if arguments.len<want_arity {application=TypeApplication.missing_nominal;}let err=self_.typeArity(source,application);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}if want_arity==2 {let length,err=self_.annotation(arguments[0]);if err!=blot_error::Error.none {return 0,err;}let element,err=self_.annotation(arguments[1]);if err!=blot_error::Error.none {return 0,err;}return blot_check_storage_types::makeSized(self_.types,storage.value,length,element);}let element,err=self_.annotation(arguments[0]);if err!=blot_error::Error.none {return 0,err;}return blot_check_storage_types::make(self_.types,storage.value,element);}let projection,err=self_.projectionAnnotation(name,arguments,source);if err!=blot_error::Error.none {return 0,err;}if projection.present {return projection.value,blot_error::Error.none;}if text=="Array" {if arguments.len==0 {let err=self_.typeArity(source,TypeApplication.missing_array);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let before=self_.diagnostics.len;if arguments.len>1 {for argument in arguments {let err=self_.argumentTypeNames(argument,0);if err!=blot_error::Error.none {return 0,err;}}}if self_.diagnostics.len!=before {return self_.types.fresh();}let element,err=self_.annotation(arguments[0]);if err!=blot_error::Error.none {return 0,err;}self_.applicationDiagnosticOrigin(before,source);if self_.diagnostics.len!=before {return self_.types.fresh();}if arguments.len>1 {let err=self_.typeArity(source,TypeApplication.extra);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}return self_.types.sequence(blot_check_types::Tag.array,element);}for builtin in ["Unit","Bool","U32","F32","EffectSet","EffectDescriptor"] {if text==builtin {let before=self_.diagnostics.len;for argument in arguments {let err=self_.argumentTypeNames(argument,0);if err!=blot_error::Error.none {return 0,err;}}if self_.diagnostics.len==before {let err=self_.typeArity(source,TypeApplication.extra);if err!=blot_error::Error.none {return 0,err;}}return self_.types.fresh();}}let selected:u32={var has_nom=false;var nom_val:u32=0;var has_tr=false;var tr_val:u32=0;var has_ef=false;var ef_val:u32=0;{let scalar_lookup_61 .= self_.catalogs.nominal_names.get(self_.catalogKey(name));if scalar_lookup_61 {nom_val=scalar_lookup_61;has_nom=true;}else {let trait_lookup .= self_.catalogs.contract_names.get(self_.catalogKey(name));if trait_lookup {tr_val=trait_lookup;has_tr=true;}else {let ef_lookup .= self_.catalogs.effect_family_names.get(self_.catalogKey(name));if ef_lookup {ef_val=ef_lookup;has_ef=true;}}}}if !has_nom {if has_tr {return self_.traitRecordAnnotation(tr_val,arguments,source);}if has_ef {return self_.effectRecordAnnotation(ef_val,arguments,source);}return self_.diagnosticFresh(Code.unsupported_type,source);}nom_val};let index=selected;let nominal=self_.nominals[index];let before=self_.diagnostics.len;if arguments.len!=nominal.parameters.len {for argument in arguments {let err=self_.argumentTypeNames(argument,0);if err!=blot_error::Error.none {return 0,err;}}}if self_.diagnostics.len!=before {return self_.types.fresh();}let old=equation_type_ids.alloc_slice(nominal.variables.len);let type_span_72=checkedTypeList(self_.types,nominal.variables);for ordinal in 0..(type_span_72.len as i64) {let value=self_.types.list(type_span_72)[ordinal];old[ordinal]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let shapes=equation_type_ids.alloc_slice(nominal.parameters.len);let type_span_73=checkedTypeList(self_.types,nominal.parameters);for ordinal in 0..(type_span_73.len as i64) {let value=self_.types.list(type_span_73)[ordinal];shapes[ordinal]=value;}var args=IdBuffer{..};let result,error=nominalAnnotationArguments(self_,index,nominal,source,arguments,before,old,fresh,shapes,args);args.deinit(equation_type_ids);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,error;}
recursive fn nominalAnnotationArguments(self_:Engine&,index:u32,nominal:Nominal,source:u32,arguments:const u32[:],before:i64,old:const u32[:],fresh:u32[:],shapes:const u32[:],args:IdBuffer&)->u32,blot_error::Error {for &replacement in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}replacement=root;}let count=min(arguments.len,shapes.len);for argument,ordinal in arguments[..count] {let pattern=self_.parameter_patterns.list(nominal.patterns)[ordinal];let actual,err=self_.parameterArgument(pattern,argument,true,0);if err!=blot_error::Error.none {return 0,err;}let selected,err=self_.types.substitute(shapes[ordinal],old,fresh);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(selected,actual,argument);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.types.resolve(selected,0);if err!=blot_error::Error.none {return 0,err;}let err=args.append(root);if err!=blot_error::Error.none {return 0,err;}}self_.applicationDiagnosticOrigin(before,source);if arguments.len!=shapes.len {if self_.diagnostics.len==before {var application=TypeApplication.extra;if arguments.len<shapes.len {application=TypeApplication.missing_nominal;}let err=self_.typeArity(source,application);if err!=blot_error::Error.none {return 0,err;}}return self_.types.fresh();}let alias,err=self_.aliasInstance(index,old,fresh,source);if err!=blot_error::Error.none {return 0,err;}if alias.present {return alias.value,blot_error::Error.none;}return self_.types.nominal(nominal.identity,args.items);}
recursive fn substituteTraitOutputs(self_:Engine&,root:u32,contract_id:Identity,out_names:const u32[:],out_types:const u32[:],depth:i64)->u32,blot_error::Error {
    if depth>=256 || root==0 {return root,blot_error::Error.none;}
    let id=self_.types.head(root,0);
    let node=self_.types.node(id);
    if node.tag==blot_check_types::Tag.projection && node.a==contract_id.unit && node.b==contract_id.decl {
        let member=self_.types.projectionMember(node);
        for oname,oi in out_names {if oname==member {return out_types[oi],blot_error::Error.none;}}
    }
    if node.tag==blot_check_types::Tag.function {
        let a,e1=self_.substituteTraitOutputs(node.a,contract_id,out_names,out_types,depth+1);if e1!=blot_error::Error.none {return 0,e1;}
        let b,e2=self_.substituteTraitOutputs(node.b,contract_id,out_names,out_types,depth+1);if e2!=blot_error::Error.none {return 0,e2;}
        if a==node.a && b==node.b {return id,blot_error::Error.none;}
        return self_.types.functionWithEffects(a,b,node.c);
    }
    if node.tag==blot_check_types::Tag.usage {
        let inner,e1=self_.substituteTraitOutputs(node.a,contract_id,out_names,out_types,depth+1);if e1!=blot_error::Error.none {return 0,e1;}
        if inner==node.a {return id,blot_error::Error.none;}
        let kind,valid=blot_check_types::usageKindFromCode(node.b);assert(valid);
        return self_.types.usage(inner,kind,node.c);
    }
    if node.tag==blot_check_types::Tag.array {
        let inner,e1=self_.substituteTraitOutputs(node.a,contract_id,out_names,out_types,depth+1);if e1!=blot_error::Error.none {return 0,e1;}
        if inner==node.a {return id,blot_error::Error.none;}
        return self_.types.sequence(node.tag,inner);
    }
    if node.tag==blot_check_types::Tag.product {
        let vals=equation_type_ids.alloc_slice(node.b);var changed=false;
        for pi in 0..node.b {
            let child=self_.types.list(blot_check_types::List{node.a,node.b, ..})[pi];
            let next,e1=self_.substituteTraitOutputs(child,contract_id,out_names,out_types,depth+1);
            if e1!=blot_error::Error.none {equation_type_ids.free_slice(vals);return 0,e1;}
            if next!=child {changed=true;} vals[pi]=next;
        }
        if !changed {equation_type_ids.free_slice(vals);return id,blot_error::Error.none;}
        let res,err=self_.types.product(vals);equation_type_ids.free_slice(vals);return res,err;
    }
    if node.tag==blot_check_types::Tag.nominal {
        let count=self_.types.nominalArguments(node).len;
        let vals=equation_type_ids.alloc_slice(count);var changed=false;
        for pi in 0..count {
            let child=self_.types.nominalArguments(node)[pi];
            let next,e1=self_.substituteTraitOutputs(child,contract_id,out_names,out_types,depth+1);
            if e1!=blot_error::Error.none {equation_type_ids.free_slice(vals);return 0,e1;}
            if next!=child {changed=true;} vals[pi]=next;
        }
        if !changed {equation_type_ids.free_slice(vals);return id,blot_error::Error.none;}
        let res,err=self_.types.nominal(Identity{node.a,node.b, ..},vals);equation_type_ids.free_slice(vals);return res,err;
    }
    if node.tag==blot_check_types::Tag.record {
        let fields=equation_fields.alloc_slice(node.b);var changed=false;
        for fi in 0..node.b {
            let f=self_.types.recordField(node,fi);
            let next,e1=self_.substituteTraitOutputs(f.ty,contract_id,out_names,out_types,depth+1);
            if e1!=blot_error::Error.none {equation_fields.free_slice(fields);return 0,e1;}
            if next!=f.ty {changed=true;} fields[fi]=blot_check_types::Field{name:f.name,ty:next, ..};
        }
        if !changed {equation_fields.free_slice(fields);return id,blot_error::Error.none;}
        let res,err=self_.types.record(fields);equation_fields.free_slice(fields);return res,err;
    }
    return id,blot_error::Error.none;
}
recursive fn traitRecordAnnotation(self_:Engine&,c_index:u32,arguments:const u32[:],source:u32)->u32,blot_error::Error {
    let rerr=self_.resolveContract(c_index);if rerr!=blot_error::Error.none {return 0,rerr;}
    let contract=self_.contracts[c_index];
    var out_record:u32=0;var arg_count=arguments.len;
    if arg_count==contract.parameters.len+1 && self_.tree.node(arguments[arg_count-1]).tag==blot_parse_ast::tag_type_record {
        out_record=arguments[arg_count-1];arg_count-=1;
    }
    if arg_count!=contract.parameters.len {
        var application=TypeApplication.extra;if arg_count<contract.parameters.len {application=TypeApplication.missing_nominal;}
        let err=self_.typeArity(source,application);if err!=blot_error::Error.none {return 0,err;}
        return self_.types.fresh();
    }
    let old=equation_type_ids.alloc_slice(contract.variables.len);
    for oi in 0..contract.variables.len {old[oi]=self_.types.list(contract.variables)[oi];}
    let fresh=equation_type_ids.alloc_slice(old.len);
    for &v in fresh {let fv,err=self_.types.fresh();if err!=blot_error::Error.none {equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}v=fv;}
    let old_rows=equation_type_ids.alloc_slice(contract.row_variables.len);
    for oi in 0..contract.row_variables.len {old_rows[oi]=self_.types.list(contract.row_variables)[oi];}
    let new_rows=equation_type_ids.alloc_slice(old_rows.len);
    for &r in new_rows {let fr,err=self_.types.freshEffects();if err!=blot_error::Error.none {equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}r=fr;}
    for oi in 0..arg_count {
        let actual,err=self_.parameterArgument(self_.parameter_patterns.list(contract.patterns)[oi],arguments[oi],true,0);
        if err!=blot_error::Error.none {equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}
        let expected,err=self_.types.substituteWithRows(self_.types.list(contract.parameters)[oi],old,fresh,old_rows,new_rows);
        if err!=blot_error::Error.none {equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}
        let err=self_.constrain(expected,actual,arguments[oi]);
        if err!=blot_error::Error.none {equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}
    }
    var out_names=IdBuffer{..};var out_types=IdBuffer{..};
    if out_record!=0 {
        let ocount=self_.tree.children(out_record).len;
        for oi in 0..ocount {
            let child=self_.tree.children(out_record)[oi];let item=self_.tree.node(child);
            let ot,err=self_.annotation(item.b);
            if err!=blot_error::Error.none {out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}
            let e1=out_names.append(item.a);let e2=out_types.append(ot);
            if e1!=blot_error::Error.none || e2!=blot_error::Error.none {out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,blot_error::Error.out_of_memory;}
        }
    }
    var fields=FieldBuffer{..};
    for m in self_.contract_members[contract.members.start..contract.members.start+contract.members.len] {
        if m.kind!=blot_reuse_principal_interface::ContractMemberKind.value || m.root==0 {continue;}
        let sub,err=self_.types.substituteWithRows(m.root,old,fresh,old_rows,new_rows);
        if err!=blot_error::Error.none {fields.deinit(equation_fields);out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,err;}
        var resolved=sub;
        if out_names.items.len!=0 {
            let replaced,rerr=self_.substituteTraitOutputs(sub,contract.identity,out_names.items,out_types.items,0);
            if rerr!=blot_error::Error.none {fields.deinit(equation_fields);out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,rerr;}
            resolved=replaced;
        }
        let ferr=fields.push(blot_check_types::Field{name:m.name,ty:resolved, ..},equation_fields);
        if ferr!=blot_error::Error.none {fields.deinit(equation_fields);out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return 0,ferr;}
    }
    let rec,err=self_.types.record(fields.items);
    fields.deinit(equation_fields);out_names.deinit(equation_type_ids);out_types.deinit(equation_type_ids);
    equation_type_ids.free_slice(new_rows);equation_type_ids.free_slice(old_rows);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);
    return rec,err;
}
fn projectionOrigin(self_:Engine&,source:u32,name:u32,read:bool)->u32,blot_error::Error {if self_.qualifications.len==0 {return 0,blot_error::Error.none;}let ast_walk_27_count=self_.tree.operator_origins.items.len;for ast_walk_27_index in 0..ast_walk_27_count {let origin=self_.tree.operator_origins.items[ast_walk_27_index];if origin.node==source && origin.member==name {var span=origin.span;if read {span=blot_parse_ast::Span{start:origin.span.end,end:origin.span.end, ..};}self_.predicate_origins.push(span);return self_.predicate_origins.len as u32,blot_error::Error.none;}}return 0,blot_error::Error.none;}
fn memberUseOrigin(self_:Engine&,requirement:blot_check_types::Obligation,source:u32)->u32,blot_error::Error {if requirement.explicit || requirement.kind!=blot_check_types::ObligationKind.receiver || self_.types.node(self_.types.head(requirement.other,0)).tag!=blot_check_types::Tag.unit {return 0,blot_error::Error.none;}let point=self_.tree.span(source).start;self_.predicate_origins.push(blot_parse_ast::Span{start:point,end:point, ..});return self_.predicate_origins.len as u32,blot_error::Error.none;}
struct FieldProjection {ty:u32,projection:u32}
struct PhysicalField {root:u32=0,identity:Identity=Identity{0,0, ..},early:bool=false}
// A field that an update goes through has one type wherever the same
// value's field is named: `access.log[0] := 5` sees what `let log:
// ResizeArray U32 = access.log` said, and a later read of `access.log` sees
// both. A name that is only read may be a member with type variables of its
// own, so two reads are not tied to each other.
fn sharedField(self_:Engine&,ty:u32,name:u32,sure:bool,result:u32,source:u32)->blot_error::Error {let count=self_.pending.len;for index in 0..count {let other=self_.pending[index];if other.owner!=self_.current || other.value.name!=name || other.value.ty!=ty {continue;}if other.value.kind!=blot_check_types::ObligationKind.writable_field && other.value.kind!=blot_check_types::ObligationKind.field {continue;}if !sure && !other.field_only {continue;}let err=self_.constrain(result,other.value.result,source);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn findTraitMethodBinding(self_:Engine&,ty:u32,name:u32,source:u32)->blot_support::Option<u32>,u32,bool,blot_error::Error {
    if self_.member_templates.len==0 {return blot_support::none<u32>(),ty,false,blot_error::Error.none;}
    let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,err;}
    let node=self_.types.node(resolved);
    let unwrapped=blot_check_storage_types::sharedInner(self_.types,resolved);
    var inner_ty=resolved;var inner_node=node;
    if unwrapped.present {let inner,ierr=self_.types.resolve(unwrapped.value,0);if ierr!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,ierr;}inner_ty=inner;inner_node=self_.types.node(inner);}
    if inner_node.tag==blot_check_types::Tag.variable || inner_node.tag==blot_check_types::Tag.projection {
        let var_head=self_.types.head(inner_ty,0);
        var found=blot_support::none<u32>();var found_contract=Identity{0,0, ..};var matches:i64=0;
        for boundary in self_.qualifications {
            if boundary.owner!=self_.current {continue;}
            for given in self_.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {
                if given.kind!=blot_check_types::ObligationKind.contract {continue;}
                if unwrapped.present && !self_.traitIsReadOnly(given.identity) {continue;}
                let pack=self_.types.node(self_.types.head(given.ty,0));
                if pack.tag!=blot_check_types::Tag.product || pack.b==0 {continue;}
                if self_.types.head(self_.types.list(blot_check_types::List{pack.a,pack.b, ..})[0],0)!=var_head {continue;}
                for tmpl in self_.member_templates {
                    if tmpl.contract==given.identity && tmpl.name==name {
                        if matches==0 || found_contract!=given.identity {found=blot_support::some(tmpl.binding);found_contract=given.identity;matches+=1;}
                    }
                }
            }
        }
        if self_.checking_implementation.present {
            let impl_=self_.implementations[self_.checking_implementation.value];
            for given in self_.implementation_predicates[impl_.predicates.start..impl_.predicates.start+impl_.predicates.len] {
                if given.kind!=blot_check_types::ObligationKind.contract {continue;}
                if unwrapped.present && !self_.traitIsReadOnly(given.identity) {continue;}
                let pack=self_.types.node(self_.types.head(given.ty,0));
                if pack.tag!=blot_check_types::Tag.product || pack.b==0 {continue;}
                if self_.types.head(self_.types.list(blot_check_types::List{pack.a,pack.b, ..})[0],0)!=var_head {continue;}
                for tmpl in self_.member_templates {
                    if tmpl.contract==given.identity && tmpl.name==name {
                        if matches==0 || found_contract!=given.identity {found=blot_support::some(tmpl.binding);found_contract=given.identity;matches+=1;}
                    }
                }
            }
        }
        if matches>1 {let derr=self_.diagnostic(Code.ambiguous_member,source);if derr==blot_error::Error.none {self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Multiple traits in scope provide this member; qualify the call with Trait.member"));}return blot_support::none<u32>(),ty,true,derr;}
        if matches==1 {return found,inner_ty,false,blot_error::Error.none;}
        return blot_support::none<u32>(),ty,false,blot_error::Error.none;
    }
    var found=blot_support::none<u32>();var found_contract=Identity{0,0, ..};var matches:i64=0;var found_recv=resolved;
    for tmpl in self_.member_templates {
        if tmpl.name!=name {continue;}
        var matched=false;var recv_ty=resolved;
        let given,gerr=self_.contractGiven(tmpl.contract,[resolved]);if gerr!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,gerr;}
        if given {matched=true;}
        if !matched {
            for ordinal in self_.implementation_order {
                let decl=self_.implementations[ordinal];
                if decl.contract!=tmpl.contract {continue;}
                if decl.private && decl.identity.unit!=self_.unit {continue;}
                let ok,merr=blot_check_trait_patterns::matches(self_.types,decl,[resolved]);if merr!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,merr;}
                if ok {matched=true;break;}
            }
        }
        if !matched && self_.traitIsReadOnly(tmpl.contract) {
            let lifted0,lerr=self_.liftedTraitArg0(resolved);if lerr!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,lerr;}
            if lifted0!=resolved {
                for ordinal in self_.implementation_order {
                    let decl=self_.implementations[ordinal];
                    if decl.contract!=tmpl.contract {continue;}
                    if decl.private && decl.identity.unit!=self_.unit {continue;}
                    let ok,merr=blot_check_trait_patterns::matches(self_.types,decl,[lifted0]);if merr!=blot_error::Error.none {return blot_support::none<u32>(),ty,false,merr;}
                    if ok {matched=true;recv_ty=lifted0;break;}
                }
            }
        }
        if matched && (matches==0 || found_contract!=tmpl.contract) {found=blot_support::some(tmpl.binding);found_contract=tmpl.contract;found_recv=recv_ty;matches+=1;}
    }
    if matches>1 {let derr=self_.diagnostic(Code.ambiguous_member,source);if derr==blot_error::Error.none {self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Multiple traits in scope provide this member; qualify the call with Trait.member"));}return blot_support::none<u32>(),ty,true,derr;}
    if matches==1 {return found,found_recv,false,blot_error::Error.none;}
    return blot_support::none<u32>(),ty,false,blot_error::Error.none;
}
recursive fn projectTraitMethod(self_:Engine&,receiver:u32,template_binding:u32,name:u32,source:u32)->FieldProjection,blot_error::Error {
    let function,err=self_.instantiate(template_binding,source);if err!=blot_error::Error.none {return FieldProjection{..},err;}
    let result,err=self_.types.fresh();if err!=blot_error::Error.none {return FieldProjection{..},err;}
    var param0=receiver;
    {let callee,rerr=self_.types.resolve(function,0);if rerr!=blot_error::Error.none {return FieldProjection{..},rerr;}
     let shape=self_.types.node(callee);
     if shape.tag==blot_check_types::Tag.function {
         let first=self_.types.node(self_.types.head(shape.a,0));
         if first.tag==blot_check_types::Tag.usage && first.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {
             let wrapped,werr=self_.types.usage(receiver,blot_parse_ast::usagekind_own,0);if werr!=blot_error::Error.none {return FieldProjection{..},werr;}
             param0=wrapped;
         }
     }}
    let expected,err=self_.invocation(param0,result);if err!=blot_error::Error.none {return FieldProjection{..},err;}
    let cerr=self_.constrain(function,expected,source);if cerr!=blot_error::Error.none {return FieldProjection{..},cerr;}
    self_.dispatch_signatures[source]=expected;
    if self_.tree.node(source).tag==blot_parse_ast::tag_name {
        if source<self_.access_paths.len && self_.access_paths[source].len!=0 {
            let pcount=self_.types.list(self_.access_paths[source]).len;
            for pi in 0..pcount {
                let cat=self_.types.list(self_.access_paths[source])[pi];
                if cat<self_.projection_catalog.len && self_.projection_catalog[cat].field==name && self_.projection_catalog[cat].nominal.decl==0 && self_.projection_catalog[cat].variants.len==0 {
                    self_.projection_catalog[cat].nominal=Identity{0xffffffff,template_binding, ..};
                    return FieldProjection{result,cat, ..},blot_error::Error.none;
                }
            }
        }
        let projection=self_.projection_catalog.len as u32;
        self_.projection_catalog.push(Projection{nominal:Identity{0xffffffff,template_binding, ..},field:name,variants:blot_check_types::List{..}, ..});
        return FieldProjection{result,projection, ..},blot_error::Error.none;
    }
    self_.resolved[source]=template_binding;
    self_.projection_resolved[source]=0;
    return FieldProjection{result,0, ..},blot_error::Error.none;
}
recursive fn projectField(self_:Engine&,original:u32,name:u32,source:u32,writable:bool,request:blot_support::Option<PendingObligation>)->FieldProjection,blot_error::Error {let on_path=self_.field_path;self_.field_path=false;let ty,err=self_.types.resolve(original,0);if err!=blot_error::Error.none {return FieldProjection{..},err;}let node=self_.types.node(ty);if node.tag==blot_check_types::Tag.variable || node.tag==blot_check_types::Tag.projection {if !writable {let trait_binding,trait_recv,trait_ambig,terr=self_.findTraitMethodBinding(ty,name,source);if terr!=blot_error::Error.none {return FieldProjection{..},terr;}if trait_ambig {let fresh,ferr=self_.types.fresh();return FieldProjection{fresh,0, ..},ferr;}if trait_binding.present {return self_.projectTraitMethod(trait_recv,trait_binding.value,name,source);}}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return FieldProjection{..},err;}let origin,err=self_.projectionOrigin(source,name,!writable);if err!=blot_error::Error.none {return FieldProjection{..},err;}var kind=blot_check_types::ObligationKind.field;var signature:u32=0;if writable {kind=blot_check_types::ObligationKind.writable_field;}else {let function,err=self_.invocation(ty,result);if err!=blot_error::Error.none {return FieldProjection{..},err;}signature=function;}let sure=writable || on_path;let shared=self_.sharedField(ty,name,sure,result,source);if shared!=blot_error::Error.none {return FieldProjection{..},shared;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:ty, kind:kind, source:source, name:name, result:result, signature:signature, .. }, owner:self_.current, origin:origin, field_only:sure, .. });if err!=blot_error::Error.none {return FieldProjection{..},err;}let projection=self_.projection_catalog.len as u32;self_.projection_catalog.push(Projection{nominal:Identity{0,0, ..},field:name,variants:blot_check_types::List{..}, ..});return FieldProjection{result,projection, ..},blot_error::Error.none;}var variants=IdBuffer{..};let result,error=projectKnownField(self_,ty,node,name,source,writable,request,variants);variants.deinit(equation_type_ids);return result,error;}
recursive fn projectKnownField(self_:Engine&,ty:u32,node:blot_check_types::Node,name:u32,source:u32,writable:bool,request:blot_support::Option<PendingObligation>,variants:IdBuffer&)->FieldProjection,blot_error::Error {var effective_ty=ty;var effective_node=node;var from_shared=false;if !writable {let unwrapped=blot_check_storage_types::sharedInner(self_.types,ty);if unwrapped.present {let inner,err=self_.types.resolve(unwrapped.value,0);if err!=blot_error::Error.none {return FieldProjection{..},err;}effective_ty=inner;effective_node=self_.types.node(inner);from_shared=true;}}let physical,err=projectPhysicalField(self_,effective_ty,effective_node,name,source,variants);if err!=blot_error::Error.none {return FieldProjection{..},err;}if physical.early {return FieldProjection{physical.root,0, ..},blot_error::Error.none;}var result=physical.root;var identity=physical.identity;if from_shared && result!=0 && !blot_check_storage_types::isShared(self_.types,self_.types.head(result,0)) {let holds,err=self_.holdsStorage(result,0);if err!=blot_error::Error.none {return FieldProjection{..},err;}if holds {let shared_res,err=blot_check_storage_types::make(self_.types,blot_check_storage_types::shared,result);if err!=blot_error::Error.none {return FieldProjection{..},err;}result=shared_res;}}var method=blot_support::none<u32>();var method_ty=effective_ty;var from_array_fallback=false;if !writable {let receiver=self_.identityOf(effective_ty);if receiver.present {let scalar_lookup_62 .= self_.catalogs.associated_members.get(AssociatedMember{identity:receiver.value,member:name, ..});if scalar_lookup_62 {let index:u32=scalar_lookup_62;method=blot_support::some(index);}}if !method.present {let arr_elem=blot_check_storage_types::arrayElement(self_.types,effective_ty);if arr_elem.present {let scalar_lookup_arr .= self_.catalogs.associated_members.get(AssociatedMember{identity:Identity{0,0xffffffff, ..},member:name, ..});if scalar_lookup_arr {let index:u32=scalar_lookup_arr;let arr_ty,err=self_.types.array(arr_elem.value);if err!=blot_error::Error.none {return FieldProjection{..},err;}method=blot_support::some(index);method_ty=arr_ty;from_array_fallback=true;}}}if method.present && (from_shared || from_array_fallback) {let binding,err=self_.associatedBinding(method.value);if err!=blot_error::Error.none {return FieldProjection{..},err;}if (self_.bindings[binding].capability_parameters.own & 1)!=0 {method=blot_support::none<u32>();}}}if method.present {if result!=0 {let err=self_.diagnostic(Code.ambiguous_member,source);if err!=blot_error::Error.none {return FieldProjection{..},err;}}else {let root,err=projectMethod(self_,method_ty,name,source,request,method.value);if err!=blot_error::Error.none {return FieldProjection{..},err;}result=root;identity=Identity{0,0, ..};variants.clear();}}else if result==0 {if !writable {let trait_binding,trait_recv,trait_ambig,terr=self_.findTraitMethodBinding(ty,name,source);if terr!=blot_error::Error.none {return FieldProjection{..},terr;}if trait_ambig {let fresh,ferr=self_.types.fresh();return FieldProjection{fresh,0, ..},ferr;}if trait_binding.present {return self_.projectTraitMethod(trait_recv,trait_binding.value,name,source);}}var code=Code.missing_member;if writable {code=Code.missing_field;}let err=self_.diagnostic(code,source);if err!=blot_error::Error.none {return FieldProjection{..},err;}if !writable {let err=self_.explainReceiver(ty,name);if err!=blot_error::Error.none {return FieldProjection{..},err;}}let root,err=self_.types.fresh();return FieldProjection{root,0, ..},err;}let projection=self_.projection_catalog.len as u32;let span,err=self_.types.saveList(variants.items);if err!=blot_error::Error.none {return FieldProjection{..},err;}self_.projection_catalog.push(Projection{nominal:identity,field:name,variants:span, ..});return FieldProjection{result,projection, ..},blot_error::Error.none;}
recursive fn projectPhysicalField(self_:Engine&,ty:u32,node:blot_check_types::Node,name:u32,source:u32,variants:IdBuffer&)->PhysicalField,blot_error::Error {var result=PhysicalField{..};if node.tag==blot_check_types::Tag.record {for index in 0..node.b {let field=self_.types.recordField(node,index);if field.name==name {result.root=field.ty;let err=variants.append(0);if err!=blot_error::Error.none {return result,err;}let err=variants.append(index as u32);if err!=blot_error::Error.none {return result,err;}break;}}}else if node.tag==blot_check_types::Tag.nominal && !blot_check_storage_types::identity(node.a,node.b).present {result.identity=Identity{node.a,node.b, ..};let index=self_.nominalIndex(result.identity);if !index.present {let root,err=self_.diagnosticFresh(Code.unknown_field,source);return PhysicalField{root:root,early:true, ..},err;}let definition=self_.nominals[index.value];if definition.is_opaque && definition.identity.unit!=self_.unit && !self_.catalogs.associated_members.contains(AssociatedMember{identity:result.identity,member:name, ..}) {let root,err=self_.diagnosticFresh(Code.private_access,source);return PhysicalField{root:root,early:true, ..},err;}let constructors=equation_type_ids.alloc_slice(definition.constructors.len);let type_span_74=checkedTypeList(self_.types,definition.constructors);for index in 0..(type_span_74.len as i64) {let value=self_.types.list(type_span_74)[index];constructors[index]=value;}let root,err=projectConstructorFields(self_,ty,name,source,constructors,variants);equation_type_ids.free_slice(constructors);if err!=blot_error::Error.none {return result,err;}result.root=root;}return result,blot_error::Error.none;}
recursive fn projectConstructorFields(self_:Engine&,ty:u32,name:u32,source:u32,constructors:const u32[:],variants:IdBuffer&)->u32,blot_error::Error {var result:u32=0;for constructor in constructors {let definition=self_.constructors[constructor];let use,err=self_.constructorStorageType(constructor);if err!=blot_error::Error.none {return 0,err;}let function=self_.types.node(use);if function.tag!=blot_check_types::Tag.function {result=0;break;}let err=self_.constrain(function.b,ty,source);if err!=blot_error::Error.none {return 0,err;}let root,err=self_.types.resolve(function.a,0);if err!=blot_error::Error.none {return 0,err;}let payload=self_.types.node(root);if payload.tag!=blot_check_types::Tag.record {result=0;break;}var found:u32=0;for index in 0..payload.b {let field=self_.types.recordField(payload,index);if field.name==name {found=field.ty;let err=variants.append(definition.tag);if err!=blot_error::Error.none {return 0,err;}let err=variants.append(index as u32);if err!=blot_error::Error.none {return 0,err;}break;}}if found==0 {result=0;break;}if result==0 {result=found;}else {let err=self_.constrain(result,found,source);if err!=blot_error::Error.none {return 0,err;}}}return result,blot_error::Error.none;}
recursive fn projectMethod(self_:Engine&,ty:u32,name:u32,source:u32,request:blot_support::Option<PendingObligation>,index:u32)->u32,blot_error::Error {let binding,err=self_.associatedBinding(index);if err!=blot_error::Error.none {return 0,err;}let state .= self_.global_states.get(binding);var active=false;if state {active=state.state==State.active;}var open_self=false;if !active && request.present {let pending=request.value;if pending.owner==binding && self_.bindings[binding].scheme.root==0 {let state .= self_.global_states.get(binding);if state && state.state==State.complete {var requirement=pending.value;requirement.kind=blot_check_types::ObligationKind.receiver;requirement.other=blot_check_types::unit;let open,err=self_.requirementOpen(requirement);if err!=blot_error::Error.none {return 0,err;}open_self=open;}}}var waiting=false;if !active && !open_self {let prepared,err=self_.prepareSelectedGlobal(binding);if err!=blot_error::Error.none {return 0,err;}waiting=!prepared;}let retained=!active && self_.retainsSelfMember(binding,self_.associated[index]);if active || open_self || retained || waiting {let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let function,err=self_.invocation(ty,result);if err!=blot_error::Error.none {return 0,err;}self_.dispatch_signatures[source]=function;var deferred=PendingObligation{ value:blot_check_types::Obligation{ ty:ty, kind:blot_check_types::ObligationKind.receiver, source:source, name:name, result:result, other:blot_check_types::unit, signature:function, .. }, owner:self_.current, scope:self_.qualification_scope, .. };if request.present {deferred=request.value;}deferred.value.ty=ty;deferred.value.kind=blot_check_types::ObligationKind.receiver;if waiting {deferred.value.kind=blot_check_types::ObligationKind.field;}deferred.value.name=name;deferred.value.other=blot_check_types::unit;deferred.value.result=result;deferred.value.signature=function;deferred.value.source=source;deferred.method_member=!waiting;deferred.wait_target=0;if waiting {deferred.wait_target=binding;}if deferred.origin==0 {let origin,err=self_.projectionOrigin(source,name,true);if err!=blot_error::Error.none {return 0,err;}deferred.origin=origin;}self_.pushPending(deferred);return result,blot_error::Error.none;}let start=self_.pending.len;let function,err=self_.instantiate(binding,source);if err!=blot_error::Error.none {return 0,err;}var projected_origin=blot_support::none<u32>();for &pending in self_.pending[start..] {if pending.value.explicit || pending.value.kind!=blot_check_types::ObligationKind.receiver || self_.types.node(self_.types.head(pending.value.other,0)).tag!=blot_check_types::Tag.unit {continue;}if !projected_origin.present {if request.present && request.value.origin!=0 {projected_origin=blot_support::some(request.value.origin);}else {let origin,err=self_.projectionOrigin(source,name,true);if err!=blot_error::Error.none {return 0,err;}projected_origin=blot_support::some(origin);}}if projected_origin.value!=0 {pending.origin=projected_origin.value;}}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}var receiver=ty;{let callee,err=self_.types.resolve(function,0);if err!=blot_error::Error.none {return 0,err;}let shape=self_.types.node(callee);if shape.tag==blot_check_types::Tag.function {let first=self_.types.node(self_.types.head(shape.a,0));if first.tag==blot_check_types::Tag.usage && first.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {let wrapped,err=self_.types.usage(ty,blot_parse_ast::usagekind_own,0);if err!=blot_error::Error.none {return 0,err;}receiver=wrapped;}}}let expected,err=self_.invocation(receiver,result);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(function,expected,source);if err!=blot_error::Error.none {return 0,err;}self_.dispatch_signatures[source]=expected;return result,blot_error::Error.none;}
fn retainsSelfMember(self_:const Engine&,binding:u32,member:Associated)->bool {let declaration=self_.bindings[binding].declaration;let state .= self_.global_states.get(binding);if !state || state.state!=State.complete {return false;}let range=self_.pendingRange([binding]);for pending in self_.pending[range.start..range.end] {if pending.owner!=binding || pending.scope!=declaration || !pending.method_member || (!pending.suspended && !state.on_stack) || pending.solved || pending.covered || pending.declared {continue;}let requirement=pending.value;if requirement.explicit || requirement.kind!=blot_check_types::ObligationKind.receiver || requirement.name!=member.member || self_.types.node(self_.types.head(requirement.other,0)).tag!=blot_check_types::Tag.unit {continue;}let receiver=self_.identityOf(requirement.ty);if receiver.present && receiver.value==member.identity {return true;}}return false;}
// Keep symbol identity across recursive work; symbol storage may grow.
struct NameParts {name:u32,position:i64=0,finished:bool=false}
fn next(self_:NameParts&,pool:const blot_parse_symbols::Pool&)->blot_support::Option<const u8[:]> {if self_.finished {return blot_support::none<const u8[:]>();}let text=pool.get(self_.name);let start=self_.position;while self_.position<text.len {if text[self_.position]=='.' as u8 {let end=self_.position;self_.position+=1;return blot_support::some<const u8[:]>(text[start..end]);}self_.position+=1;}self_.finished=true;return blot_support::some<const u8[:]>(text[start..]);}
fn peek(self_:const NameParts&,pool:const blot_parse_symbols::Pool&)->blot_support::Option<const u8[:]> {if self_.finished {return blot_support::none<const u8[:]>();}let text=pool.get(self_.name);var end=self_.position;while end<text.len {if text[end]=='.' as u8 {break;}end+=1;}return blot_support::some<const u8[:]>(text[self_.position..end]);}

recursive fn qualifiedValue(self_:Engine&,id:u32,name:u32)->blot_support::Option<u32>,blot_error::Error {var parts=NameParts{name:name, ..};let first=parts.next(self_.pool);assert(first.present);if !parts.peek(self_.pool).present {return blot_support::none<u32>(),blot_error::Error.none;}let root,known=self_.pool.lookup(first.value);if !known {return blot_support::none<u32>(),blot_error::Error.none;}var binding=self_.lookup(root);if !binding.present {let global,err=self_.globalBinding(root);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}binding=global;}if !binding.present {let member=parts.next(self_.pool);assert(member.present);if self_.editorAt(id) && !parts.peek(self_.pool).present && self_.isNamespace(root) {let capture,err=self_.captureEditor(id,0,root);return blot_support::some(capture),err;}let symbol,known=self_.pool.lookup(member.value);if known {let imported,err=self_.qualifiedImportBinding(Qualified{namespace_:root,member:symbol, ..});if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}binding=imported;}}if !binding.present {return blot_support::none<u32>(),blot_error::Error.none;}var path=IdBuffer{..};var types=IdBuffer{..};let result,err=qualifiedValueParts(self_,id,binding.value,parts,path,types);types.deinit(equation_type_ids);path.deinit(equation_type_ids);return result,err;}
recursive fn qualifiedValueParts(self_:Engine&,id:u32,target:u32,parts:NameParts&,path:IdBuffer&,types:IdBuffer&)->blot_support::Option<u32>,blot_error::Error {if isWithLocked(target) {let root,err=self_.diagnosticFresh(Code.borrow_conflict,id);return blot_support::some(root),err;}var ty:u32=0;if self_.bindings[target].kind==blot_reuse_principal_interface::Kind.global || self_.bindings[target].kind==blot_reuse_principal_interface::Kind.external {let root,err=self_.globalReference(target,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}ty=root;}else {let root,err=self_.instantiate(target,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}ty=root;}self_.resolved[id]=target;let err=types.append(ty);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}loop {let part=parts.next(self_.pool);if !part.present {break;}if self_.editorAt(id) && !parts.peek(self_.pool).present {let result,err=self_.captureEditor(id,ty,0);return blot_support::some(result),err;}let symbol,known=self_.pool.lookup(part.value);if !known {let root,err=self_.diagnosticFresh(Code.unknown_field,id);return blot_support::some(root),err;}let operation,err=self_.scopedOperation(id,ty,symbol,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if operation.present {self_.operation_uses[self_.operation_refs[id]-1].capability_binding=target;let list,err=self_.types.saveList(path.items);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.access_paths[id]=list;let list,err=self_.types.saveList(types.items);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.access_types[id]=list;if parts.peek(self_.pool).present {let err=self_.diagnostic(Code.effect_identity_scope,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}return operation,blot_error::Error.none;}let projected,err=self_.projectField(ty,symbol,id,false,blot_support::none<PendingObligation>());if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}ty=projected.ty;let err=path.append(projected.projection);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=types.append(ty);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}let list,err=self_.types.saveList(path.items);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.access_paths[id]=list;let list,err=self_.types.saveList(types.items);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.access_types[id]=list;return blot_support::some(ty),blot_error::Error.none;}
recursive fn selectorFunction(self_:Engine&,id:u32)->u32,blot_error::Error {let saved=self_.ambient;let latent,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}self_.ambient=latent;var path=IdBuffer{..};var types=IdBuffer{..};let result,error=selectorFunctionBody(self_,id,latent,path,types);types.deinit(equation_type_ids);path.deinit(equation_type_ids);self_.ambient=saved;return result,error;}
recursive fn selectorFunctionBody(self_:Engine&,id:u32,latent:u32,path:IdBuffer&,types:IdBuffer&)->u32,blot_error::Error {match self_.types.row(latent).tail {variable payload=>{self_.row_sources.insert(payload.value,id);},_=>{abort("fresh effects must have a variable tail");}}let input,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}if self_.editorAt(id) {let result,err=self_.captureEditor(id,input,0);if err!=blot_error::Error.none {return 0,err;}return self_.types.functionWithEffects(input,result,latent);}let binding,err=self_.addBinding(Binding{name:0,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.parameter,ty:input, ..});if err!=blot_error::Error.none {return 0,err;}self_.resolved[id]=binding;let err=types.append(input);if err!=blot_error::Error.none {return 0,err;}var current=input;var names=NameParts{name:self_.tree.node(id).a, ..};loop {let part=names.next(self_.pool);if !part.present {break;}let name,known=self_.pool.lookup(part.value);if !known {return 0,blot_error::Error.type_limit;}let projected,err=self_.projectField(current,name,id,false,blot_support::none<PendingObligation>());if err!=blot_error::Error.none {return 0,err;}let err=path.append(projected.projection);if err!=blot_error::Error.none {return 0,err;}let err=types.append(projected.ty);if err!=blot_error::Error.none {return 0,err;}current=projected.ty;}let list,err=self_.types.saveList(path.items);if err!=blot_error::Error.none {return 0,err;}self_.access_paths[id]=list;let list,err=self_.types.saveList(types.items);if err!=blot_error::Error.none {return 0,err;}self_.access_types[id]=list;return self_.types.functionWithEffects(input,current,latent);}
reusable[] var boolean_runs:bool[>..];
recursive fn recordValue(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);if node.a==0 {var fields=FieldBuffer{..};let result,err=recordLiteral(self_,id,fields);fields.deinit(equation_fields);return result,err;}let selected:u32={let scalar_lookup_63 .= self_.catalogs.constructor_names.get(self_.catalogKey(node.a));if !scalar_lookup_63 {let err=self_.constructorDiagnostic(self_.tree.node(id).a,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let scalar_value_63:u32=scalar_lookup_63;scalar_value_63};let constructor=selected;self_.constructor_resolved[id]=constructor;let use,err=self_.constructorStorageType(constructor);if err!=blot_error::Error.none {return 0,err;}let function=self_.types.node(use);if function.tag!=blot_check_types::Tag.function {if self_.constructors[constructor].payload==0 && self_.tree.children(id).len==0 {return use,blot_error::Error.none;}let err=self_.diagnostic(Code.type_mismatch,id);return use,err;}let payload=self_.types.node(function.a);if payload.tag!=blot_check_types::Tag.record {let err=self_.diagnostic(Code.type_mismatch,id);return function.b,err;}let supplied=boolean_runs.alloc_slice(payload.b);for &present in supplied {present=false;}let result,error=recordConstructorFields(self_,id,constructor,function,payload,supplied);boolean_runs.free_slice(supplied);return result,error;}
recursive fn recordLiteral(self_:Engine&,id:u32,fields:FieldBuffer&)->u32,blot_error::Error {var diverges=false;let child_count:i64=self_.tree.children(id).len;for index in 0..child_count {let child:u32=self_.tree.children(id)[index];let field=self_.tree.node(child);for prior in fields.items {if prior.name==field.a {let err=self_.diagnostic(Code.duplicate_field,child);if err!=blot_error::Error.none {return 0,err;}}}var raw:u32=0;if field.b==0 {let root,err=self_.shorthand(child,field.a);if err!=blot_error::Error.none {return 0,err;}raw=root;}else {let root,err=self_.expression(field.b);if err!=blot_error::Error.none {return 0,err;}raw=root;}let value,err=self_.runtimeValue(raw,child);if err!=blot_error::Error.none {return 0,err;}if !diverges {let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}diverges=resolved==blot_check_types::never;}self_.expr_types[child]=value;self_.projections[child]=index as u32;let err=fields.append(blot_check_types::Field{name:field.a,ty:value, ..});if err!=blot_error::Error.none {return 0,err;}}if diverges {return blot_check_types::never,blot_error::Error.none;}return self_.types.record(fields.items);}
recursive fn recordConstructorFields(self_:Engine&,id:u32,constructor:u32,function:blot_check_types::Node,payload:blot_check_types::Node,supplied:bool[:])->u32,blot_error::Error {var diverges=false;let child_count:i64=self_.tree.children(id).len;for child_index in 0..child_count {let child:u32=self_.tree.children(id)[child_index];let field=self_.tree.node(child);var raw:u32=0;if field.b==0 {let root,err=self_.shorthand(child,field.a);if err!=blot_error::Error.none {return 0,err;}raw=root;}else {let root,err=self_.expression(field.b);if err!=blot_error::Error.none {return 0,err;}raw=root;}let value,err=self_.runtimeValue(raw,child);if err!=blot_error::Error.none {return 0,err;}if !diverges {let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}diverges=resolved==blot_check_types::never;}self_.expr_types[child]=value;var found=false;for index in 0..payload.b {let declared=self_.types.recordField(payload,index);if declared.name==field.a {found=true;if supplied[index] {let err=self_.diagnostic(Code.duplicate_field,child);if err!=blot_error::Error.none {return 0,err;}}supplied[index]=true;self_.projections[child]=index as u32;let err=self_.constrain(value,declared.ty,child);if err!=blot_error::Error.none {return 0,err;}break;}}if !found {let err=self_.diagnostic(Code.unknown_field,child);if err!=blot_error::Error.none {return 0,err;}}}for present,index in supplied {if !present {let declared=self_.types.recordField(payload,index);if self_.constructorFieldDefault(constructor,declared.name)==0 {let err=self_.diagnostic(Code.missing_field,id);if err!=blot_error::Error.none {return 0,err;}break;}}}if diverges {return blot_check_types::never,blot_error::Error.none;}return function.b,blot_error::Error.none;}
recursive fn typeConstructorValue(self_:Engine&,key:Qualified)->blot_support::Option<u32>,blot_error::Error {if key.namespace_!=0 && self_.lookup(key.namespace_).present {return blot_support::none<u32>(),blot_error::Error.none;}var catalog:u32=0;block {let found:u32={let scalar_lookup_64 .= self_.catalogs.nominal_names.get(key);if !scalar_lookup_64 {return blot_support::none<u32>(),blot_error::Error.none;}let scalar_value_64:u32=scalar_lookup_64;scalar_value_64};catalog=found;}let alias,err=self_.resolveAlias(catalog);if err!=blot_error::Error.none || alias!=0 {return blot_support::none<u32>(),err;}let root,err=self_.types.typeConstructor(self_.nominals[catalog].identity);return blot_support::some(root),err;}
recursive fn shorthand(self_:Engine&,id:u32,name:u32)->u32,blot_error::Error {return self_.shorthandBefore(id,name,self_.env.len);}
recursive fn shorthandBefore(self_:Engine&,id:u32,name:u32,limit:i64)->u32,blot_error::Error {for offset in 0..limit {let entry=self_.env[limit-offset-1];if entry.name==name {if isWithLocked(entry.binding) {return self_.diagnosticFresh(Code.borrow_conflict,id);}self_.resolved[id]=entry.binding;return self_.instantiate(entry.binding,id);}}let binding,err=self_.globalBinding(name);if err!=blot_error::Error.none {return 0,err;}if binding.present {return self_.globalReference(binding.value,id);}return self_.diagnosticFresh(Code.unknown_name,id);}
recursive fn associatedApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {let outer=self_.tree.node(id);if self_.tree.node(outer.a).tag!=blot_parse_ast::tag_apply {return blot_support::none<u32>(),blot_error::Error.none;}let middle=self_.tree.node(outer.a);if self_.tree.node(middle.a).tag!=blot_parse_ast::tag_apply {return blot_support::none<u32>(),blot_error::Error.none;}let inner=self_.tree.node(middle.a);let head=self_.tree.node(inner.a);if head.tag!=blot_parse_ast::tag_intrinsic || self_.pool.get(head.a)!="@type.call" {return blot_support::none<u32>(),blot_error::Error.none;}let literal=self_.tree.node(inner.b);if literal.tag!=blot_parse_ast::tag_string {let root,err=self_.diagnosticFresh(Code.call_arity,inner.b);return blot_support::some(root),err;}let left,err=self_.expression(middle.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let right,err=self_.expression(outer.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let operation=memberOperator(self_.pool.get(literal.a));let dispatched,err=self_.dispatch(left,right,literal.a,operation,id,true);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if dispatched.present {return dispatched,blot_error::Error.none;}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let signature,err=self_.invocationBinary(left,right,result);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:left, kind:blot_check_types::ObligationKind.dispatch, source:id, name:literal.a, result:result, other:right, signature:signature, operator:operation, .. }, owner:self_.current, direct:true, .. });return blot_support::some(result),err;}
recursive fn resultApplication(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {let outer=self_.tree.node(id);let inner=self_.tree.node(outer.a);if inner.tag!=blot_parse_ast::tag_apply {return blot_support::none<u32>(),blot_error::Error.none;}let head=self_.tree.node(inner.a);if head.tag!=blot_parse_ast::tag_intrinsic || self_.pool.get(head.a)!="@type.result" {return blot_support::none<u32>(),blot_error::Error.none;}var member=inner.b;while self_.tree.node(member).tag==blot_parse_ast::tag_group {member=self_.tree.node(member).a;}let literal=self_.tree.node(member);if literal.tag!=blot_parse_ast::tag_string {let root,err=self_.diagnosticFresh(Code.literal_required,member);return blot_support::some(root),err;}let input,err=self_.expression(outer.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let signature,err=self_.invocation(input,result);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:input, kind:blot_check_types::ObligationKind.result_dispatch, source:id, name:literal.a, result:result, signature:signature, .. }, owner:self_.current, direct:true, .. });return blot_support::some(result),err;}
recursive fn productProjection(self_:Engine&,id:u32)->blot_support::Option<u32>,blot_error::Error {let node=self_.tree.node(id);if self_.tree.node(node.a).tag!=blot_parse_ast::tag_apply {return blot_support::none<u32>(),blot_error::Error.none;}let inner=self_.tree.node(node.a);if self_.tree.node(inner.a).tag!=blot_parse_ast::tag_intrinsic || self_.pool.get(self_.tree.node(inner.a).a)!="@product.get" {return blot_support::none<u32>(),blot_error::Error.none;}let index=self_.tree.node(node.b);if index.tag!=blot_parse_ast::tag_integer {let err=self_.diagnostic(Code.product_index_literal,node.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.diagnostics[self_.diagnostics.len-1].span.start;let root,err=self_.types.fresh();return blot_support::some(root),err;}let ty,err=self_.expression(inner.b);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let product=self_.types.node(root);self_.expr_types[node.b]=blot_check_types::u32_type;if product.tag==blot_check_types::Tag.never {return blot_support::some(blot_check_types::never),blot_error::Error.none;}if product.tag==blot_check_types::Tag.product && index.a<product.b {self_.projections[id]=index.a;return blot_support::some(self_.types.extra.items[product.a+index.a]),blot_error::Error.none;}var code=Code.type_mismatch;if product.tag==blot_check_types::Tag.variable {code=Code.unknown_product_shape;}else if product.tag==blot_check_types::Tag.product {code=Code.product_index;}let err=self_.diagnostic(code,id);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.diagnostics[self_.diagnostics.len-1].span.start;let root,err=self_.types.fresh();return blot_support::some(root),err;}
recursive fn patternConstrain(self_:Engine&,left:u32,right:u32,source:u32)->blot_error::Error {let before=self_.diagnostics.len;let err=self_.constrain(left,right,source);if err!=blot_error::Error.none {return err;}if self_.let_pattern_source!=0 {for &issue in self_.diagnostics[before..] {if issue.node!=source {continue;}let point=self_.tree.span(self_.let_pattern_source).start;issue.node=self_.let_pattern_source;issue.span=blot_parse_ast::Span{start:point,end:point, ..};}}return blot_error::Error.none;}
recursive fn pattern(self_:Engine&,id:u32,ty:u32,scope:i64,reuse:const Entry[:],generalize:bool)->bool,blot_error::Error {if id==0 {return true,blot_error::Error.none;}if self_.depth>=1024 {return false,blot_error::Error.type_limit;}self_.depth+=1;let result,err=patternBody(self_,id,ty,scope,reuse,generalize);self_.depth-=1;return result,err;}
recursive fn patternBody(self_:Engine&,id:u32,ty:u32,scope:i64,reuse:const Entry[:],generalize:bool)->bool,blot_error::Error {let node=self_.tree.node(id);self_.expr_types[id]=ty;let tag=node.tag;if tag==blot_parse_ast::tag_pattern_name || tag==blot_parse_ast::tag_pattern_field {if self_.pool.get(node.a)=="_" {return true,blot_error::Error.none;}for prior in self_.env[scope..] {if prior.name==node.a {let err=self_.diagnostic(Code.duplicate_name,id);return true,err;}}var selected=blot_support::none<u32>();for prior in reuse {if prior.name==node.a {selected=blot_support::some(prior.binding);let err=self_.patternConstrain(self_.bindings[prior.binding].ty,ty,id);if err!=blot_error::Error.none {return false,err;}break;}}var binding:u32=0;if selected.present {binding=selected.value;}else if generalize {let value,err=self_.local(node.a,ty,id);if err!=blot_error::Error.none {return false,err;}binding=value;}else {let value,err=self_.addBinding(Binding{name:node.a,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..}, ..});if err!=blot_error::Error.none {return false,err;}binding=value;}if selected.present || !generalize {self_.env.push(Entry{name:node.a,binding:binding, ..});}self_.resolved[id]=binding;return true,blot_error::Error.none;}if tag==blot_parse_ast::tag_pattern_integer {let err=self_.patternConstrain(ty,blot_check_types::u32_type,id);return false,err;}if tag==blot_parse_ast::tag_pattern_boolean {let err=self_.patternConstrain(ty,blot_check_types::boolean,id);return false,err;}if tag==blot_parse_ast::tag_pattern_value {let value,err=self_.shorthandBefore(id,node.a,scope);if err!=blot_error::Error.none {return false,err;}let err=self_.patternConstrain(ty,value,id);if err!=blot_error::Error.none {return false,err;}let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return false,err;}let tag=self_.types.node(resolved).tag;if tag!=blot_check_types::Tag.unsigned32 && tag!=blot_check_types::Tag.boolean {var source=id;if self_.case_pattern_source!=0 {source=self_.case_pattern_source;}let err=self_.diagnostic(Code.value_pattern_type,source);if err!=blot_error::Error.none {return false,err;}}return false,blot_error::Error.none;}if tag==blot_parse_ast::tag_pattern_constructor {return constructorPattern(self_,id,node,ty,scope,reuse,generalize);}if tag==blot_parse_ast::tag_pattern_product {let children=checkedAstChildren(self_.tree,id);if (children.len as i64)==0 {let err=self_.patternConstrain(ty,blot_check_types::unit,id);return true,err;}let fields=equation_type_ids.alloc_slice((children.len as i64));let result,err=productPattern(self_,id,ty,scope,reuse,generalize,children,fields);equation_type_ids.free_slice(fields);return result,err;}if tag==blot_parse_ast::tag_pattern_record {let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return false,err;}let record=self_.types.node(root);if record.tag!=blot_check_types::Tag.record {let err=self_.diagnostic(Code.type_mismatch,id);return false,err;}let seen=boolean_runs.alloc_slice(record.b);for &present in seen {present=false;}let result,error=recordPattern(self_,id,record,scope,reuse,generalize,seen);boolean_runs.free_slice(seen);return result,error;}let err=self_.diagnostic(Code.unsupported,id);return false,err;}
recursive fn constructorPattern(self_:Engine&,id:u32,node:blot_parse_ast::Node,ty:u32,scope:i64,reuse:const Entry[:],generalize:bool)->bool,blot_error::Error {let selected:u32={let scalar_lookup_65 .= self_.catalogs.constructor_names.get(self_.catalogKey(node.a));if !scalar_lookup_65 {let err=self_.constructorDiagnostic(self_.tree.node(id).a,id);return false,err;}let scalar_value_65:u32=scalar_lookup_65;scalar_value_65};let constructor=selected;self_.constructor_resolved[id]=constructor;let use,err=self_.constructorStorageType(constructor);if err!=blot_error::Error.none {return false,err;}let function=self_.types.node(use);var payload:u32=0;var result=use;if function.tag==blot_check_types::Tag.function {payload=function.a;result=function.b;}let err=self_.patternConstrain(ty,result,id);if err!=blot_error::Error.none {return false,err;}let definition=self_.constructors[constructor];let unique=self_.nominals[definition.nominal].constructors.len==1;if payload==0 {if node.b!=0 && !(self_.tree.node(node.b).tag==blot_parse_ast::tag_pattern_record && self_.tree.children(node.b).len==0) {let err=self_.diagnostic(Code.constructor_arity,id);if err!=blot_error::Error.none {return false,err;}}return unique,blot_error::Error.none;}if node.b==0 {let err=self_.diagnostic(Code.constructor_arity,id);return false,err;}let root,err=self_.types.resolve(payload,0);if err!=blot_error::Error.none {return false,err;}let shape=self_.types.node(root);if !self_.nominals[definition.nominal].is_opaque && self_.types.node(definition.payload).tag==blot_check_types::Tag.record && shape.tag==blot_check_types::Tag.record && self_.tree.node(node.b).tag!=blot_parse_ast::tag_pattern_record {let canonical,err=self_.canonicalRecordType(shape);if err!=blot_error::Error.none {return false,err;}payload=canonical;}let total,err=self_.pattern(node.b,payload,scope,reuse,generalize);return total && unique,err;}
recursive fn productPattern(self_:Engine&,id:u32,ty:u32,scope:i64,reuse:const Entry[:],generalize:bool,children:blot_parse_ast::List,fields:u32[:])->bool,blot_error::Error {for &field in fields {let value,err=self_.types.fresh();if err!=blot_error::Error.none {return false,err;}field=value;}let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return false,err;}let actual=self_.types.node(root);if actual.tag==blot_check_types::Tag.product && actual.b!=(children.len as i64) {var source=id;if self_.let_pattern_source!=0 {source=self_.let_pattern_source;}let err=self_.diagnostic(Code.product_arity,source);if err!=blot_error::Error.none {return false,err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.diagnostics[self_.diagnostics.len-1].span.start;}else {let product,err=self_.types.product(fields);if err!=blot_error::Error.none {return false,err;}let err=self_.patternConstrain(ty,product,id);if err!=blot_error::Error.none {return false,err;}}var total=true;let ast_span_15=children;for index in 0..(ast_span_15.len as i64) {let child=self_.tree.list(ast_span_15)[index];let matched,err=self_.pattern(child,fields[index],scope,reuse,generalize);if err!=blot_error::Error.none {return false,err;}total=matched && total;}return total,blot_error::Error.none;}
recursive fn recordPattern(self_:Engine&,id:u32,record:blot_check_types::Node,scope:i64,reuse:const Entry[:],generalize:bool,seen:bool[:])->bool,blot_error::Error {var total=true;let syntax_source_31=id;let syntax_count_31=self_.tree.children(syntax_source_31).len;for syntax_index_31 in 0..syntax_count_31 {let child=self_.tree.children(syntax_source_31)[syntax_index_31];let field=self_.tree.node(child);var found=false;for index in 0..record.b {let declared=self_.types.recordField(record,index);if declared.name==field.a {found=true;if seen[index] {let err=self_.diagnostic(Code.duplicate_field,child);if err!=blot_error::Error.none {return false,err;}}seen[index]=true;self_.projections[child]=index as u32;self_.expr_types[child]=declared.ty;var source=child;if field.b!=0 {source=field.b;}let matched,err=self_.pattern(source,declared.ty,scope,reuse,generalize);if err!=blot_error::Error.none {return false,err;}total=matched && total;break;}}if !found {let err=self_.diagnostic(Code.unknown_field,child);if err!=blot_error::Error.none {return false,err;}}}return total,blot_error::Error.none;}
reusable[] var entry_runs:Entry[>..];
recursive fn caseExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let statement=self_.statement_case==id;self_.statement_case=0;let input_words=checkedAstRange(self_.tree,node.a,node.a+2);let inputs=blot_parse_ast::List{self_.tree.list(input_words)[0],self_.tree.list(input_words)[1], ..};var types=IdBuffer{..};let result,err=caseInputs(self_,id,node,statement,inputs,types);types.deinit(equation_type_ids);return result,err;}
recursive fn caseInputs(self_:Engine&,id:u32,node:blot_parse_ast::Node,statement:bool,inputs:blot_parse_ast::List,types:IdBuffer&)->u32,blot_error::Error {var diverges=false;let syntax_source_32=inputs;let syntax_count_32=self_.tree.list(syntax_source_32).len;for syntax_index_32 in 0..syntax_count_32 {let input=self_.tree.list(syntax_source_32)[syntax_index_32];let value,err=self_.expression(input);if err!=blot_error::Error.none {return 0,err;}let err=types.append(value);if err!=blot_error::Error.none {return 0,err;}if !diverges {let root,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}diverges=root==blot_check_types::never;}}let scope=self_.env.len;var kept=scope;let result,err=self_.types.fresh();if err!=blot_error::Error.none {self_.env.resize(kept);return 0,err;}let arms=blot_parse_ast::List{node.b,node.c, ..};let arm_count=self_.tree.list(arms).len;let carry=!diverges && arm_count!=0;var version_count:i64=0;if carry {if scope!=0 && arm_count>0x7fffffffffffffff/scope {self_.env.resize(kept);return 0,blot_error::Error.type_limit;}version_count=arm_count*scope;}let versions=equation_type_ids.alloc_slice(version_count);var exit_count:i64=0;if carry {exit_count=arm_count;}let exits=boolean_runs.alloc_slice(exit_count);var versions_start:i64=0;if versions.len!=0 {versions_start=equation_type_ids.index_of(versions[0]);}let output,error=caseArms(self_,id,result,scope,arms,types.items,statement,carry,versions_start,exits);if error==blot_error::Error.none && carry {self_.env.resize(scope);let err=self_.joinCaseArms(id,arms,versions,exits);if err!=blot_error::Error.none {boolean_runs.free_slice(exits);equation_type_ids.free_slice(versions);self_.env.resize(kept);return 0,err;}kept=self_.env.len;}boolean_runs.free_slice(exits);equation_type_ids.free_slice(versions);self_.env.resize(kept);if error!=blot_error::Error.none {return 0,error;}if diverges {return blot_check_types::never,blot_error::Error.none;}return output,blot_error::Error.none;}
recursive fn caseArms(self_:Engine&,id:u32,result:u32,scope:i64,arms:blot_parse_ast::List,types:const u32[:],statement:bool,carry:bool,versions_start:i64,exits:bool[:])->u32,blot_error::Error {let arm_count=self_.tree.list(arms).len;var all_exited=arm_count!=0;for arm_index in 0..arm_count {let arm_id=self_.tree.list(arms)[arm_index];let arm=self_.tree.node(arm_id);let meta=checkedAstRange(self_.tree,arm.c,arm.c+2);let guard_source=self_.tree.list(meta)[0];let body_source=self_.tree.list(meta)[1];let first,err=caseArmBindings(self_,id,arm,scope,types);if err!=blot_error::Error.none {if first.len!=0 {entry_runs.free_slice(first);}return 0,err;}self_.env.resize(scope);for entry in first {self_.env.push(entry);}if first.len!=0 {entry_runs.free_slice(first);}if guard_source!=0 {let guard_,err=self_.expression(guard_source);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(guard_,blot_check_types::boolean,guard_source);if err!=blot_error::Error.none {return 0,err;}}if !carry {let ty,err=self_.expression(body_source);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(result,ty,arm_id);if err!=blot_error::Error.none {return 0,err;}if self_.types.head(ty,0)!=blot_check_types::never {all_exited=false;}continue;}let capture=ArmCapture{block_:body_source,versions_start:versions_start+arm_index*scope,versions_len:scope,..};let current=armVersions(capture);for entry,index in self_.env[..scope] {current[index]=entry.binding;}var ty:u32=0;var error=blot_error::Error.none;var carrying=false;if statement {let saved=self_.arm_capture;self_.arm_capture=blot_support::some(capture);let v,e=self_.expression(body_source);ty=v;error=e;carrying=self_.arm_capture.value.carrying;self_.arm_capture=saved;if error==blot_error::Error.none && !carrying {for entry,index in self_.env[..scope] {current[index]=self_.latestSuccessor(entry.binding);}}}else {let v,e=self_.expression(body_source);ty=v;error=e;if error==blot_error::Error.none {for entry,index in self_.env[..scope] {current[index]=self_.latestSuccessor(entry.binding);}}}if error!=blot_error::Error.none {return 0,error;}let err=self_.constrain(result,ty,arm_id);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return 0,err;}exits[arm_index]=resolved==blot_check_types::never;if !exits[arm_index] {all_exited=false;}if carrying {self_.statement_arms.push(StatementArm{node:body_source, ..});}}self_.cases.push(id);if all_exited {return blot_check_types::never,blot_error::Error.none;}return result,blot_error::Error.none;}
recursive fn caseArmBindings(self_:Engine&,id:u32,arm:blot_parse_ast::Node,scope:i64,types:const u32[:])->Entry[:],blot_error::Error {var first:Entry[:]=default<Entry[:]>();let syntax_source_33=blot_parse_ast::List{arm.a,arm.b, ..};let syntax_count_33=self_.tree.list(syntax_source_33).len;for row_index in 0..syntax_count_33 {let row=self_.tree.list(syntax_source_33)[row_index];self_.env.resize(scope);let pattern_count=self_.tree.children(row).len;if pattern_count!=types.len {let err=self_.diagnostic(Code.pattern_arity,row);if err!=blot_error::Error.none {return first,err;}continue;}let saved=self_.case_pattern_source;self_.case_pattern_source=id;let error=caseRowPatterns(self_,row,types,scope,first);self_.case_pattern_source=saved;if error!=blot_error::Error.none {return first,error;}if row_index==0 {first=entry_runs.alloc_slice(self_.env.len-scope);for entry,index in self_.env[scope..] {first[index]=entry;}}else {if self_.env.len-scope!=first.len {let err=self_.diagnostic(Code.pattern_bindings,row);if err!=blot_error::Error.none {return first,err;}}for entry in self_.env[scope..] {var found=false;for prior in first {if entry.name==prior.name {found=true;break;}}if !found {let err=self_.diagnostic(Code.pattern_bindings,row);if err!=blot_error::Error.none {return first,err;}}}}}return first,blot_error::Error.none;}
recursive fn caseRowPatterns(self_:Engine&,row:u32,types:const u32[:],scope:i64,reuse:const Entry[:])->blot_error::Error {let pattern_count=self_.tree.children(row).len;for index in 0..pattern_count {let pattern=self_.tree.children(row)[index];let matched,err=self_.pattern(pattern,types[index],scope,reuse,false);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
recursive fn joinCaseArms(self_:Engine&,id:u32,arms:blot_parse_ast::List,versions:const u32[:],exits:const bool[:])->blot_error::Error {let scope=self_.env.len;let arm_count=self_.tree.list(arms).len;for index in 0..scope {let entry=self_.env[index];var shadowed=false;for later in self_.env[index+1..scope] {if later.name==entry.name {shadowed=true;break;}}if shadowed {continue;}var changed=false;var live:u32=0;for ordinal in 0..arm_count {let arm=self_.tree.list(arms)[ordinal];let version=versions[ordinal*scope+index];changed=changed || version!=entry.binding;if exits[ordinal] {continue;}if live==0 {live=version;}else {let err=self_.constrain(self_.bindings[live].ty,self_.bindings[version].ty,arm);if err!=blot_error::Error.none {return err;}}}if !changed || live==0 {continue;}var level=arm_count-1;var joined=versions[(arm_count-1)*scope+index];var joined_exits=exits[arm_count-1];if arm_count==1 {level=arm_count;joined=entry.binding;joined_exits=false;}while level!=0 {level-=1;let version=versions[level*scope+index];if exits[level] {continue;}if joined_exits {joined=version;joined_exits=false;continue;}if version==joined {continue;}if arm_count==1 {let err=self_.constrain(self_.bindings[version].ty,self_.bindings[joined].ty,self_.tree.list(arms)[level]);if err!=blot_error::Error.none {return err;}}let merged,err=self_.addBinding(Binding{name:entry.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:self_.bindings[version].ty,predecessor:entry.binding, ..});if err!=blot_error::Error.none {return err;}self_.merges.push(Merge{node:self_.tree.list(arms)[level],result:merged,then_binding:version,else_binding:joined, ..});joined=merged;}if !joined_exits && joined!=entry.binding {self_.env.push(Entry{name:entry.name,binding:joined, ..});}}return blot_error::Error.none;}
recursive fn annotationEffects(self_:Engine&,id:u32)->u32,blot_error::Error {let row=self_.tree.node(id);if row.tag!=blot_parse_ast::tag_effect_row {return 0,blot_error::Error.type_limit;}var tail=blot_check_effects::Tail.closed;if row.c!=0 {let variable,err=self_.rowVariable(self_.tree.node(row.c).a,row.c);if err!=blot_error::Error.none {return 0,err;}tail=self_.types.row(variable).tail;}var labels=IdBuffer{..};let result,err=annotationEffectLabels(self_,row,tail,labels);labels.deinit(equation_type_ids);return result,err;}
recursive fn annotationEffectLabels(self_:Engine&,row:blot_parse_ast::Node,tail:blot_check_effects::Tail,labels:IdBuffer&)->u32,blot_error::Error {let syntax_source_34=blot_parse_ast::List{row.a,row.b, ..};let syntax_count_34=self_.tree.list(syntax_source_34).len;for syntax_index_34 in 0..syntax_count_34 {let source=self_.tree.list(syntax_source_34)[syntax_index_34];var reverse=IdBuffer{..};let err=annotationEffectLabel(self_,source,reverse,labels);reverse.deinit(equation_type_ids);if err!=blot_error::Error.none {return 0,err;}}let result,err=self_.types.effects.row(labels.items,tail);return result,blot_check_types::effectError(err);}
recursive fn annotationEffectLabel(self_:Engine&,source:u32,reverse:IdBuffer&,labels:IdBuffer&)->blot_error::Error {var head=source;while self_.tree.node(head).tag==blot_parse_ast::tag_type_apply {let err=reverse.append(self_.tree.node(head).b);if err!=blot_error::Error.none {return err;}head=self_.tree.node(head).a;}let name=self_.tree.node(head);if name.tag!=blot_parse_ast::tag_type_name {return self_.diagnostic(Code.unknown_effect,source);}if reverse.items.len==0 {let lexical,err=annotationLexicalEffect(self_,name.a);if err!=blot_error::Error.none {return err;}if lexical.present {return labels.append(lexical.value);}}let text=self_.pool.get(name.a);if text=="Foreign" {if reverse.items.len!=0 {return self_.diagnostic(Code.type_arity,source);}return labels.append(blot_check_types::foreign_operation);}var family=blot_support::none<u32>();var member=blot_support::none<u32>();let scalar_lookup_66 .= self_.catalogs.effect_family_names.get(self_.catalogKey(name.a));if scalar_lookup_66 {let found:u32=scalar_lookup_66;family=blot_support::some(found);}else {let scalar_lookup_67 .= self_.catalogs.effect_operation_names.get(self_.catalogKey(name.a));if scalar_lookup_67 {let found:u32=scalar_lookup_67;member=blot_support::some(found);family=blot_support::some(self_.effect_templates[found].family);}else {let separator=lastDot(text);if separator.present {let key=self_.textCatalogKey(text[..separator.value]);if key.present {let scalar_lookup_68 .= self_.catalogs.effect_family_names.get(key.value);if scalar_lookup_68 {let selected:u32=scalar_lookup_68;let symbol,known=self_.pool.lookup(text[separator.value+1..]);if known {let scalar_lookup_69 .= self_.catalogs.effect_members.get(EffectMember{family:selected,member:symbol, ..});if scalar_lookup_69 {let template:u32=scalar_lookup_69;family=blot_support::some(selected);member=blot_support::some(template);}}}}}}}if !family.present {return self_.diagnostic(Code.unknown_effect,source);}let descriptor=self_.effect_families[family.value];let shapes=equation_type_ids.alloc_slice(descriptor.parameters.len);let type_span_75=checkedTypeList(self_.types,descriptor.parameters);for index in 0..(type_span_75.len as i64) {let value=self_.types.list(type_span_75)[index];shapes[index]=value;}if reverse.items.len!=shapes.len {equation_type_ids.free_slice(shapes);return self_.diagnostic(Code.type_arity,source);}reverseIds(reverse.items);let old=equation_type_ids.alloc_slice(descriptor.variables.len);let type_span_76=checkedTypeList(self_.types,descriptor.variables);for index in 0..(type_span_76.len as i64) {let value=self_.types.list(type_span_76)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let arguments=equation_type_ids.alloc_slice(shapes.len);let err=annotationEffectArguments(self_,descriptor,member,reverse.items,shapes,old,fresh,arguments,labels);equation_type_ids.free_slice(arguments);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);equation_type_ids.free_slice(shapes);return err;}
fn annotationLexicalEffect(self_:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let binding=self_.lookup(name);if binding.present && self_.bindings[binding.value].operation_ref!=0 {let root,err=self_.types.resolve(self_.bindings[binding.value].ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let signature=self_.types.node(root);if signature.tag==blot_check_types::Tag.function && self_.types.rowLabels(signature.c).len==1 {return blot_support::some(self_.types.rowLabels(signature.c)[0]),blot_error::Error.none;}}let text=self_.pool.get(name);let separator=lastDot(text);if !separator.present {return blot_support::none<u32>(),blot_error::Error.none;}let root_name,known=self_.pool.lookup(text[..separator.value]);if !known {return blot_support::none<u32>(),blot_error::Error.none;}let binding=self_.lookup(root_name);if !binding.present {return blot_support::none<u32>(),blot_error::Error.none;}let root,err=self_.types.resolve(self_.bindings[binding.value].ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let capability=self_.types.node(root);if capability.tag!=blot_check_types::Tag.scoped {return blot_support::none<u32>(),blot_error::Error.none;}let root,err=self_.types.resolve(capability.a,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let descriptor=self_.types.node(root);if descriptor.tag!=blot_check_types::Tag.nominal {return blot_support::none<u32>(),blot_error::Error.none;}let family:u32={let scalar_lookup_70 .= self_.catalogs.effect_family_identities.get(Identity{descriptor.a,descriptor.b, ..});if !scalar_lookup_70 {return blot_support::none<u32>(),blot_error::Error.none;}let scalar_value_70:u32=scalar_lookup_70;scalar_value_70};let member,known=self_.pool.lookup(text[separator.value+1..]);if !known {return blot_support::none<u32>(),blot_error::Error.none;}let operation:u32={let scalar_lookup_71 .= self_.catalogs.effect_members.get(EffectMember{family:family,member:member, ..});if !scalar_lookup_71 {return blot_support::none<u32>(),blot_error::Error.none;}let scalar_value_71:u32=scalar_lookup_71;scalar_value_71};let arguments=equation_type_ids.alloc_slice(self_.types.nominalArguments(descriptor).len);let type_span_77=checkedNominalArguments(self_.types,descriptor);for index in 0..(type_span_77.len as i64) {let value=self_.types.list(type_span_77)[index];arguments[index]=value;}let label,err=self_.types.internScopedOperation(self_.effect_templates[operation].identity,Identity{capability.b,capability.c, ..},arguments);equation_type_ids.free_slice(arguments);return blot_support::some(label),err;}
recursive fn annotationEffectArguments(self_:Engine&,family:EffectFamily,member:blot_support::Option<u32>,syntax:const u32[:],shapes:const u32[:],old:const u32[:],fresh:u32[:],arguments:u32[:],labels:IdBuffer&)->blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}variable=root;}for origin,index in syntax {let argument,err=self_.parameterArgument(self_.parameter_patterns.list(family.patterns)[index],origin,true,0);if err!=blot_error::Error.none {return err;}let selected,err=self_.types.substitute(shapes[index],old,fresh);if err!=blot_error::Error.none {return err;}let err=self_.constrain(argument,selected,origin);if err!=blot_error::Error.none {return err;}let resolved,err=self_.types.resolve(selected,0);if err!=blot_error::Error.none {return err;}arguments[index]=resolved;}var count=family.operations.len;if member.present {count=1;}let operations=equation_type_ids.alloc_slice(count);if member.present {operations[0]=member.value;}else {let type_span_78=checkedTypeList(self_.types,family.operations);for index in 0..(type_span_78.len as i64) {let value=self_.types.list(type_span_78)[index];operations[index]=value;}}let error=annotationOperationLabels(self_,operations,arguments,labels);equation_type_ids.free_slice(operations);return error;}
fn annotationOperationLabels(self_:Engine&,operations:const u32[:],arguments:const u32[:],labels:IdBuffer&)->blot_error::Error {for operation in operations {let label,err=self_.types.internSymbolicOperation(self_.effect_templates[operation].identity,arguments);if err!=blot_error::Error.none {return err;}let err=labels.append(label);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn constructorPayloadAnnotation(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);if node.tag!=blot_parse_ast::tag_type_record {return self_.annotation(id);}let fields=checkedAstChildren(self_.tree,id);if self_.tree.type_conversion_origin(id)!=self_.tree.span(id).start {let ast_span_16=fields;for index in 0..(ast_span_16.len as i64) {let field=self_.tree.list(ast_span_16)[index];let ast_span_17=checkedAstSubspan(self_.tree,fields,0,index);for ast_index_17 in 0..(ast_span_17.len as i64) {let earlier=self_.tree.list(ast_span_17)[ast_index_17];if self_.tree.node(field).a==self_.tree.node(earlier).a {let err=self_.diagnostic(Code.duplicate_type_field,id);if err!=blot_error::Error.none {return 0,err;}let issue .= self_.diagnostics[self_.diagnostics.len-1];issue.span.end=issue.span.start;issue.symbol=self_.tree.node(field).a;return self_.types.fresh();}}}let err=self_.diagnostic(Code.type_argument,id);if err!=blot_error::Error.none {return 0,err;}let point=self_.tree.type_conversion_origin(id);self_.diagnostics[self_.diagnostics.len-1].span=blot_parse_ast::Span{point,point, ..};return self_.types.fresh();}return self_.recordAnnotation(id);}
recursive fn recordAnnotation(self_:Engine&,id:u32)->u32,blot_error::Error {var fields=FieldBuffer{..};let result,err=recordAnnotationFields(self_,id,fields);fields.deinit(equation_fields);return result,err;}
recursive fn recordAnnotationFields(self_:Engine&,id:u32,fields:FieldBuffer&)->u32,blot_error::Error {let child_count:i64=self_.tree.children(id).len;for child_index in 0..child_count {let child:u32=self_.tree.children(id)[child_index];let field=self_.tree.node(child);for prior in fields.items {if prior.name==field.a {let err=self_.diagnostic(Code.duplicate_field,child);if err!=blot_error::Error.none {return 0,err;}}}var ty:u32=0;if field.b==0 {let root,err=self_.typeVariable(field.a,child);if err!=blot_error::Error.none {return 0,err;}ty=root;}else {let root,err=self_.annotation(field.b);if err!=blot_error::Error.none {return 0,err;}ty=root;}let err=fields.append(blot_check_types::Field{name:field.a,ty:ty, ..});if err!=blot_error::Error.none {return 0,err;}}return self_.types.record(fields.items);}
recursive fn dependentParameter(self_:Engine&,id:u32)->u32,blot_error::Error {let binder=self_.tree.node(id);let descriptor,err=self_.capabilityDescriptorAnnotation(binder.b);if err!=blot_error::Error.none {return 0,err;}if !descriptor.present {return self_.diagnosticFresh(Code.effect_identity_scope,id);}let parameter,err=self_.types.capabilityParameter(descriptor.value);if err!=blot_error::Error.none {return 0,err;}let binding,err=self_.addBinding(Binding{name:binder.a,declaration:id,owner:id,kind:blot_reuse_principal_interface::Kind.parameter,ty:parameter, ..});if err!=blot_error::Error.none {return 0,err;}self_.env.push(Entry{name:binder.a,binding:binding, ..});self_.expr_types[id]=parameter;return parameter,blot_error::Error.none;}
reusable[] var contract_member_runs:ContractMember[>..];
recursive fn contextualLambda(self_:Engine&,source:u32,required:u32)->u32,blot_error::Error {let syntax=self_.tree.node(source);if syntax.tag==blot_parse_ast::tag_group {let value,err=self_.contextualLambda(syntax.a,required);if err!=blot_error::Error.none {return 0,err;}self_.expr_types[source]=value;return value,blot_error::Error.none;}let resolved,err=self_.types.resolve(required,0);if err!=blot_error::Error.none {return 0,err;}let expected=self_.types.node(resolved);let ef_nom=self_.effectFamilyNominal(resolved);if ef_nom.present {let ef_family=self_.effect_families[ef_nom.value];if (!ef_family.callable && syntax.tag==blot_parse_ast::tag_record && syntax.a==0) || (ef_family.callable && syntax.tag==blot_parse_ast::tag_lambda) {var ef_sigs=IdBuffer{..};var ef_nodes=IdBuffer{..};var ef_foreign=IdBuffer{..};let res,err=self_.checkEffectRecordValue(source,required,ef_nom.value,0,false,ef_sigs,ef_nodes,ef_foreign);ef_sigs.deinit(equation_type_ids);ef_nodes.deinit(equation_type_ids);ef_foreign.deinit(equation_type_ids);return res,err;}}let storage=blot_check_storage_types::info(self_.types,resolved);if storage.present && blot_check_storage_types::isSized(storage.value.kind) {if syntax.tag==blot_parse_ast::tag_array && syntax.c==0 {let syntax_source_37=source;let syntax_count_37=self_.tree.children(syntax_source_37).len;if blot_check_storage_types::isSized(storage.value.kind) {let len_opt=blot_check_storage_types::lengthOf(self_.types,resolved);if len_opt.present {let len_resolved,err=self_.types.resolve(len_opt.value,0);if err!=blot_error::Error.none {return 0,err;}let len_node=self_.types.node(len_resolved);if len_node.tag==blot_check_types::Tag.nominal && blot_check_storage_types::isLengthLiteral(len_node.a,len_node.b) && blot_check_storage_types::lengthLiteralValue(len_node.b)!=(syntax_count_37 as u32) {let err=self_.diagnostic(Code.type_mismatch,source);if err!=blot_error::Error.none {return 0,err;}}}}for syntax_index_37 in 0..syntax_count_37 {let child=self_.tree.children(syntax_source_37)[syntax_index_37];let value,err=self_.contextualLambda(child,storage.value.element);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(value,storage.value.element,child);if err!=blot_error::Error.none {return 0,err;}}self_.expr_types[source]=required;return required,blot_error::Error.none;}if syntax.tag==blot_parse_ast::tag_if_expr {return contextualIf(self_,source,syntax,required);}}let saved_source=self_.expected_lambda_source;let saved_type=self_.expected_lambda_type;self_.expected_lambda_source=source;self_.expected_lambda_type=required;let result,error=self_.expression(source);self_.expected_lambda_source=saved_source;self_.expected_lambda_type=saved_type;return result,error;}
recursive fn contextualIf(self_:Engine&,source:u32,syntax:blot_parse_ast::Node,required:u32)->u32,blot_error::Error {let condition,err=self_.expression(syntax.a);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(condition,blot_check_types::boolean,syntax.a);if err!=blot_error::Error.none {return 0,err;}let left,err=self_.contextualLambda(syntax.b,required);if err!=blot_error::Error.none {return 0,err;}let right,err=self_.contextualLambda(syntax.c,required);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(left,required,syntax.b);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(right,required,syntax.c);if err!=blot_error::Error.none {return 0,err;}self_.expr_types[source]=required;return required,blot_error::Error.none;}

fn clauseCount(self_:PredicateRun)->i64 {return self_.len;}
fn clauseAt(self_:PredicateRun,index:i64)->blot_check_types::Obligation {return predicateAt(self_,index);}
recursive fn annotation(self_:Engine&,id:u32)->u32,blot_error::Error {if id==0 {return self_.types.fresh();}if self_.depth>=1024 {return 0,blot_error::Error.type_limit;}self_.depth+=1;let result,err=annotationBody(self_,id);self_.depth-=1;return result,err;}
recursive fn annotationBody(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let tag=node.tag;if tag==blot_parse_ast::tag_type_name && self_.editorAt(id) {let key=self_.catalogKey(node.a);let result,err=self_.captureEditor(id,0,key.namespace_);if err!=blot_error::Error.none {return 0,err;}self_.editor_capture.value.kind=blot_reuse_completion_probe::Kind.type_;self_.expr_types[id]=result;return result,blot_error::Error.none;}if tag==blot_parse_ast::tag_type_name {let implementation=self_.activeImplementation();if implementation.present {let member=self_.implementationMemberIndex(self_.implementations[implementation.value],node.a);if member.present && self_.implementation_members[member.value].kind==blot_reuse_principal_interface::ImplementationMemberKind.type_ {return self_.resolveImplementationMember(member.value);}}let name=self_.pool.get(node.a);if name=="EffectSet" {return self_.reflectionType(false);}if name=="EffectDescriptor" {return self_.reflectionType(true);}if name=="Unit" {return blot_check_types::unit,blot_error::Error.none;}if name=="Bool" {return blot_check_types::boolean,blot_error::Error.none;}if name=="U32" {return blot_check_types::u32_type,blot_error::Error.none;}if name=="F32" {return blot_check_types::f32_type,blot_error::Error.none;}if name.len!=0 && ((name[0]>='a' as u8 && name[0]<='z' as u8) || name[0]=='_' as u8) && !firstDot(name).present {let variable,err=self_.typeVariable(node.a,id);if err!=blot_error::Error.none {return 0,err;}let bound=self_.types.node(self_.types.head(variable,0));if (bound.tag==blot_check_types::Tag.bound && bound.b==2) || (bound.tag==blot_check_types::Tag.rigid && bound.c==2) {return self_.diagnosticFresh(Code.unsupported_type,id);}return variable,blot_error::Error.none;}return self_.nominalAnnotation(id,[],id);}
 if tag==blot_parse_ast::tag_type_usage {return usageAnnotation(self_,id,node);}
 if tag==blot_parse_ast::tag_type_function {if self_.tree.node(node.a).tag==blot_parse_ast::tag_type_binder {let scope=self_.env.len;let result,err=dependentFunctionAnnotation(self_,node);self_.env.resize(scope);return result,err;}let outer_own=self_.own_position;self_.own_position=node.a;let parameter,err=self_.annotation(node.a);self_.own_position=outer_own;if err!=blot_error::Error.none {return 0,err;}let result,err=self_.annotation(node.b);if err!=blot_error::Error.none {return 0,err;}var row:u32=0;if node.c!=0 {let value,err=self_.annotationEffects(node.c);if err!=blot_error::Error.none {return 0,err;}row=value;}return self_.types.functionWithEffects(parameter,result,row);}
 if tag==blot_parse_ast::tag_type_effect {let err=self_.diagnostic(Code.invalid_effect_annotation,id);if err!=blot_error::Error.none {return 0,err;}return self_.annotation(node.a);}
 if tag==blot_parse_ast::tag_type_product {let children=checkedAstChildren(self_.tree,id);let fields=equation_type_ids.alloc_slice((children.len as i64));let result,err=annotationProduct(self_,children,fields);equation_type_ids.free_slice(fields);return result,err;}
 if tag==blot_parse_ast::tag_type_record {return self_.recordAnnotation(id);}
 if tag==blot_parse_ast::tag_type_array {return self_.diagnosticFresh(Code.type_argument,id);}
 if tag==blot_parse_ast::tag_type_apply {var reverse=IdBuffer{..};let result,err=annotationApplication(self_,id,reverse);reverse.deinit(equation_type_ids);return result,err;}
 if tag==blot_parse_ast::tag_group {let before=self_.diagnostics.len;let result,err=self_.annotation(node.a);if err!=blot_error::Error.none {return 0,err;}self_.applicationDiagnosticOrigin(before,id);return result,blot_error::Error.none;}return self_.diagnosticFresh(Code.unsupported_type,id);
}
recursive fn usageAnnotation(self_:Engine&,id:u32,node:blot_parse_ast::Node)->u32,blot_error::Error {let kind,valid=blot_check_types::usageKindFromCode(node.a);assert(valid);if kind!=blot_parse_ast::usagekind_own {return self_.diagnosticFresh(Code.unsupported_type,id);}if self_.own_position!=id {return self_.diagnosticFresh(Code.own_parameter,id);}let payload,err=self_.annotation(node.b);if err!=blot_error::Error.none {return 0,err;}return self_.types.usage(payload,kind,0);}
recursive fn dependentFunctionAnnotation(self_:Engine&,node:blot_parse_ast::Node)->u32,blot_error::Error {let parameter,err=self_.dependentParameter(node.a);if err!=blot_error::Error.none {return 0,err;}let result,err=self_.annotation(node.b);if err!=blot_error::Error.none {return 0,err;}var row:u32=0;if node.c!=0 {let effects,err=self_.annotationEffects(node.c);if err!=blot_error::Error.none {return 0,err;}row=effects;}return self_.types.functionWithEffects(parameter,result,row);}
recursive fn annotationProduct(self_:Engine&,children:blot_parse_ast::List,fields:u32[:])->u32,blot_error::Error {let ast_span_18=children;for index in 0..(ast_span_18.len as i64) {let child=self_.tree.list(ast_span_18)[index];let root,err=self_.annotation(child);if err!=blot_error::Error.none {return 0,err;}fields[index]=root;}if fields.len==0 {return blot_check_types::unit,blot_error::Error.none;}return self_.types.product(fields);}
recursive fn annotationApplication(self_:Engine&,id:u32,reverse:IdBuffer&)->u32,blot_error::Error {var head=id;loop {let node=self_.tree.node(head);if node.tag==blot_parse_ast::tag_group {head=node.a;continue;}if node.tag!=blot_parse_ast::tag_type_apply {break;}let err=reverse.append(node.b);if err!=blot_error::Error.none {return 0,err;}head=node.a;}reverseIds(reverse.items);if self_.tree.node(head).tag!=blot_parse_ast::tag_type_name {return self_.diagnosticFresh(Code.unsupported_type,id);}return self_.nominalAnnotation(head,reverse.items,id);}
fn obligation(self_:Engine&,ty:u32,kind:blot_check_types::ObligationKind,id:u32)->blot_error::Error {return self_.appendPending(PendingObligation{value:blot_check_types::Obligation{ty:ty,kind:kind,source:id, ..},owner:self_.current, ..});}
reusable[] var row_environment_snapshots:Engine_row_env[>..];
fn resolvePredicateNonzero(self_:Engine&,before:blot_check_types::Obligation)->blot_check_types::Obligation,blot_error::Error {var result=before;for ordinal in 0..4 {var root=before.ty;if ordinal==1 {root=before.other;}else if ordinal==2 {root=before.result;}else if ordinal==3 {root=before.signature;}if root==0 {continue;}let value,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return result,err;}if ordinal==0 {result.ty=value;}else if ordinal==1 {result.other=value;}else if ordinal==2 {result.result=value;}else {result.signature=value;}}return result,blot_error::Error.none;}
fn predicateValues(output:PredicateBuffer&)->const blot_check_types::Obligation[:] {return output.items;}
fn predicateValues(output:blot_check_types::Obligation[>..<]&)->const blot_check_types::Obligation[:] {return output;}
fn predicateAppend(output:PredicateBuffer&,value:blot_check_types::Obligation)->blot_error::Error {return output.append(value);}
fn predicateAppend(output:blot_check_types::Obligation[>..<]&,value:blot_check_types::Obligation)->blot_error::Error {output.push(value);return blot_error::Error.none;}
recursive fn lowerPredicates<O>(self_:Engine&,id:u32,where_node:u32,output:O&)->blot_error::Error {let node=self_.tree.node(id);let selected:u32={let scalar_lookup_73 .= self_.catalogs.contract_names.get(self_.catalogKey(node.a));if !scalar_lookup_73 {let predicate,err=self_.lowerPredicate(id,where_node);if err!=blot_error::Error.none {return err;}if predicate.present {if predicateValues(output).len>=65536 {return blot_error::Error.type_limit;}return predicateAppend(output,predicate.value);}return blot_error::Error.none;}let scalar_value_73:u32=scalar_lookup_73;scalar_value_73};let index=selected;let err=self_.resolveContract(index);if err!=blot_error::Error.none {return err;}let contract=self_.contracts[index];let details=checkedAstRange(self_.tree,node.c,node.c+3);var syntax=checkedAstList(self_.tree,blot_parse_ast::List{self_.tree.list(details)[0],self_.tree.list(details)[1], ..});var output_record:u32=0;if (syntax.len as i64)==contract.parameters.len+1 && self_.tree.node(self_.tree.list(syntax)[contract.parameters.len]).tag==blot_parse_ast::tag_type_record {output_record=self_.tree.list(syntax)[contract.parameters.len];syntax=checkedAstSubspan(self_.tree,syntax,0,contract.parameters.len);}if node.b!=0 || self_.tree.list(details)[2]!=0 || (syntax.len as i64)!=contract.parameters.len {return self_.diagnostic(Code.contract_arity,id);}let old=equation_type_ids.alloc_slice(contract.variables.len);let type_span_88=checkedTypeList(self_.types,contract.variables);for index in 0..(type_span_88.len as i64) {let value=self_.types.list(type_span_88)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let shapes=equation_type_ids.alloc_slice(contract.parameters.len);let type_span_89=checkedTypeList(self_.types,contract.parameters);for index in 0..(type_span_89.len as i64) {let value=self_.types.list(type_span_89)[index];shapes[index]=value;}let result=lowerContractParameters(self_,id,where_node,contract,syntax,output_record,old,fresh,shapes,output);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result;}
recursive fn lowerContractParameters<O>(self_:Engine&,id:u32,where_node:u32,contract:Contract,syntax:blot_parse_ast::List,output_record:u32,old:const u32[:],fresh:u32[:],shapes:const u32[:],output:O&)->blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}variable=root;}let actuals=equation_type_ids.alloc_slice(shapes.len);for shape,index in shapes {let actual,err=self_.parameterArgument(self_.parameter_patterns.list(contract.patterns)[index],self_.tree.list(syntax)[index],true,0);if err!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return err;}actuals[index]=actual;let selected,err=self_.types.substitute(shape,old,fresh);if err!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return err;}let err=self_.constrain(selected,actual,self_.tree.list(syntax)[index]);if err!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return err;}}let rows=equation_type_ids.alloc_slice(contract.row_variables.len);let type_span_90=checkedTypeList(self_.types,contract.row_variables);for index in 0..(type_span_90.len as i64) {let row=self_.types.list(type_span_90)[index];rows[index]=row;}let fresh_rows=equation_type_ids.alloc_slice(rows.len);let result=lowerContractRows(self_,id,where_node,contract,old,fresh,shapes,rows,fresh_rows,output);equation_type_ids.free_slice(fresh_rows);equation_type_ids.free_slice(rows);if result!=blot_error::Error.none || output_record==0 {equation_type_ids.free_slice(actuals);return result;}let ocount=self_.tree.children(output_record).len;for oi in 0..ocount {let child=self_.tree.children(output_record)[oi];let item=self_.tree.node(child);let mi=self_.memberIndex(contract,item.a);if !mi.present || self_.contract_members[mi.value].kind==blot_reuse_principal_interface::ContractMemberKind.value {equation_type_ids.free_slice(actuals);return self_.diagnostic(Code.missing_type_member,child);}let proj,perr=self_.types.projection(contract.identity,item.a,actuals);if perr!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return perr;}let rhs,aerr=self_.annotation(item.b);if aerr!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return aerr;}self_.has_associated_types=true;self_.types.has_projections=true;let perr2=predicateAppend(output,blot_check_types::Obligation{ ty:proj, kind:blot_check_types::ObligationKind.type_eq, source:child, result:rhs, explicit:true, qualification_span:blot_support::some(self_.tree.span(where_node)), qualification_unit:self_.unit, .. });if perr2!=blot_error::Error.none {equation_type_ids.free_slice(actuals);return perr2;}}equation_type_ids.free_slice(actuals);return blot_error::Error.none;}
fn lowerContractRows<O>(self_:Engine&,id:u32,where_node:u32,contract:Contract,old:const u32[:],fresh:const u32[:],shapes:const u32[:],rows:const u32[:],fresh_rows:u32[:],output:O&)->blot_error::Error {for &row in fresh_rows {let value,err=self_.types.freshEffects();if err!=blot_error::Error.none {return err;}row=value;}if contract.requires_implementation {let application=equation_type_ids.alloc_slice(shapes.len);let pack,err=lowerContractApplication(self_,shapes,old,fresh,rows,fresh_rows,application);equation_type_ids.free_slice(application);       if err!=blot_error::Error.none {return err;}              let __field_order_44_kind: blot_check_types::ObligationKind = blot_check_types::ObligationKind.contract; let __field_order_45_identity: blot_check_types::NominalIdentity = contract.identity; let __field_order_46_ty: blot_check_types::Id = pack; let __field_order_47_source: u32 = id; let __field_order_48_explicit: bool = true; let __field_order_49_qualification_unit: u32 = self_.unit; let __field_order_50_qualification_span: blot_support::Option<blot_parse_ast::Span> = blot_support::some(self_.tree.span(where_node)); let err=predicateAppend(output,blot_check_types::Obligation{ ty: __field_order_46_ty, kind: __field_order_44_kind, source: __field_order_47_source, identity: __field_order_45_identity, explicit: __field_order_48_explicit, qualification_span: __field_order_50_qualification_span, qualification_unit: __field_order_49_qualification_unit, .. });if err!=blot_error::Error.none {return err;}}if contract.predicates.len>65536-predicateValues(output).len {return blot_error::Error.type_limit;}for before in self_.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {let predicate,err=self_.substitutePredicateNonzero(before,old,fresh,rows,fresh_rows);if err!=blot_error::Error.none {return err;}predicate.source=id;predicate.qualification_unit=self_.unit;predicate.qualification_span=blot_support::some(self_.tree.span(where_node));let err=predicateAppend(output,predicate);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn lowerContractApplication(self_:Engine&,shapes:const u32[:],old:const u32[:],fresh:const u32[:],rows:const u32[:],fresh_rows:const u32[:],application:u32[:])->u32,blot_error::Error {for shape,index in shapes {let root,err=self_.types.substituteWithRows(shape,old,fresh,rows,fresh_rows);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return 0,err;}application[index]=resolved;}return self_.types.product(application);}
fn substitutePredicateNonzero(self_:Engine&,before:blot_check_types::Obligation,old:const u32[:],fresh:const u32[:],rows:const u32[:],fresh_rows:const u32[:])->blot_check_types::Obligation,blot_error::Error {var result=before;for ordinal in 0..4 {var root=before.ty;if ordinal==1 {root=before.other;}else if ordinal==2 {root=before.result;}else if ordinal==3 {root=before.signature;}if root==0 {continue;}let value,err=self_.types.substituteWithRows(root,old,fresh,rows,fresh_rows);if err!=blot_error::Error.none {return result,err;}if ordinal==0 {result.ty=value;}else if ordinal==1 {result.other=value;}else if ordinal==2 {result.result=value;}else {result.signature=value;}}return result,blot_error::Error.none;}
recursive fn lowerPredicate(self_:Engine&,id:u32,where_node:u32)->blot_support::Option<blot_check_types::Obligation>,blot_error::Error {let node=self_.tree.node(id);let details=checkedAstRange(self_.tree,node.c,node.c+3);let syntax=checkedAstList(self_.tree,blot_parse_ast::List{self_.tree.list(details)[0],self_.tree.list(details)[1], ..});let name=self_.pool.get(node.a);var kind=blot_check_types::ObligationKind.type_eq;if name=="type_eq" {kind=blot_check_types::ObligationKind.type_eq;}else if name=="associated" {kind=blot_check_types::ObligationKind.dispatch;}else if name=="result" {kind=blot_check_types::ObligationKind.result_dispatch;}else if name=="receiver" {kind=blot_check_types::ObligationKind.receiver;}else if name=="field" {kind=blot_check_types::ObligationKind.field;}else if name=="update" {kind=blot_check_types::ObligationKind.update;}else if name=="operation" {kind=blot_check_types::ObligationKind.effect_operation;}else if name=="type_rep" {kind=blot_check_types::ObligationKind.type_rep;}else if name=="effect_rep" {kind=blot_check_types::ObligationKind.effect_rep;}else {let err=self_.diagnostic(Code.invalid_constraint,id);return blot_support::none<blot_check_types::Obligation>(),err;}self_.has_associated_types=self_.has_associated_types || kind==blot_check_types::ObligationKind.type_eq;self_.types.has_projections=self_.types.has_projections || kind==blot_check_types::ObligationKind.type_eq;let named=kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.receiver || kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.update;var expected=(syntax.len as i64);if kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.receiver || kind==blot_check_types::ObligationKind.update {expected=3;}else if kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.type_eq {expected=2;}else if kind==blot_check_types::ObligationKind.type_rep {expected=1;}else if kind==blot_check_types::ObligationKind.effect_rep {expected=0;}let invocation=kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.receiver || kind==blot_check_types::ObligationKind.update;if (named && node.b==0) || (!named && node.b!=0) || (syntax.len as i64)!=expected || (kind==blot_check_types::ObligationKind.effect_rep && self_.tree.list(details)[2]==0) || (!invocation && kind!=blot_check_types::ObligationKind.effect_rep && self_.tree.list(details)[2]!=0) || (kind==blot_check_types::ObligationKind.effect_operation && (syntax.len as i64)==0) {let err=self_.diagnostic(Code.invalid_constraint,id);return blot_support::none<blot_check_types::Obligation>(),err;}var arguments=IdBuffer{..};let result,error=lowerPredicateArguments(self_,id,where_node,node,details,syntax,kind,invocation,arguments);arguments.deinit(equation_type_ids);return result,error;}
recursive fn lowerPredicateArguments(self_:Engine&,id:u32,where_node:u32,node:blot_parse_ast::Node,details:blot_parse_ast::List,syntax:blot_parse_ast::List,kind:blot_check_types::ObligationKind,invocation:bool,arguments:IdBuffer&)->blot_support::Option<blot_check_types::Obligation>,blot_error::Error {if kind!=blot_check_types::ObligationKind.effect_operation {let ast_span_19=syntax;for ast_index_19 in 0..(ast_span_19.len as i64) {let argument=self_.tree.list(ast_span_19)[ast_index_19];let root,err=self_.annotation(argument);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let err=arguments.append(root);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}}}var result=blot_check_types::Obligation{ty:blot_check_types::unit,kind:kind,source:id,name:node.b,explicit:true,qualification_span:blot_support::some(self_.tree.span(where_node)),qualification_unit:self_.unit, ..};if kind==blot_check_types::ObligationKind.type_rep {result.ty=arguments.items[0];}else if kind==blot_check_types::ObligationKind.effect_operation {let operation,err=lowerOperationPredicate(self_,id,where_node,syntax,arguments,result);if err!=blot_error::Error.none || !operation.present {return operation,err;}result=operation.value;}else if kind!=blot_check_types::ObligationKind.effect_rep {result.ty=arguments.items[0];if kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.type_eq {result.result=arguments.items[1];}else {result.other=arguments.items[1];result.result=arguments.items[2];if kind==blot_check_types::ObligationKind.dispatch {result.operator=memberOperator(self_.pool.get(node.b));}}}if invocation || kind==blot_check_types::ObligationKind.effect_rep {let previous=self_.diagnostics.len;var row:u32=0;if self_.tree.list(details)[2]==0 {let value,err=self_.types.freshEffects();if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}row=value;}else {let value,err=self_.annotationEffects(self_.tree.list(details)[2]);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}row=value;}for &issue in self_.diagnostics[previous..] {if issue.code==Code.unsupported_polymorphic_effect_label || issue.code==Code.unsupported_type {issue.code=Code.unsupported_polymorphic_effect_label;}if issue.code==Code.unsupported_polymorphic_effect_label || issue.code==Code.unknown_effect {issue.node=id;issue.span=self_.tree.span(id);}}let signature,err=self_.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,row);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}result.signature=signature;}return blot_support::some(result),blot_error::Error.none;}
recursive fn lowerOperationPredicate(self_:Engine&,id:u32,where_node:u32,syntax:blot_parse_ast::List,arguments:IdBuffer&,before:blot_check_types::Obligation)->blot_support::Option<blot_check_types::Obligation>,blot_error::Error {let head=self_.tree.node(self_.tree.list(syntax)[0]);var selected=blot_support::none<u32>();if head.tag==blot_parse_ast::tag_type_name {selected=self_.catalogOperationTemplate(head.a);}if !selected.present {let err=self_.diagnostic(Code.invalid_constraint,id);return blot_support::none<blot_check_types::Obligation>(),err;}let template=self_.effect_templates[selected.value];let family=self_.effect_families[template.family];if family.callable || family.parameters.len==0 {let err=self_.diagnostic(Code.invalid_constraint,id);return blot_support::none<blot_check_types::Obligation>(),err;}if (syntax.len as i64)-1!=family.parameters.len {let err=self_.diagnostic(Code.effect_arity,where_node);return blot_support::none<blot_check_types::Obligation>(),err;}let old=equation_type_ids.alloc_slice(family.variables.len);let type_span_91=checkedTypeList(self_.types,family.variables);for index in 0..(type_span_91.len as i64) {let value=self_.types.list(type_span_91)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let shapes=equation_type_ids.alloc_slice(family.parameters.len);let type_span_92=checkedTypeList(self_.types,family.parameters);for index in 0..(type_span_92.len as i64) {let value=self_.types.list(type_span_92)[index];shapes[index]=value;}let result,error=lowerOperationArguments(self_,template,family,checkedAstSubspan(self_.tree,syntax,1,(syntax.len as i64)),old,fresh,shapes,arguments,before);equation_type_ids.free_slice(shapes);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);return result,error;}
recursive fn lowerOperationArguments(self_:Engine&,template:EffectTemplate,family:EffectFamily,syntax:blot_parse_ast::List,old:const u32[:],fresh:u32[:],shapes:const u32[:],arguments:IdBuffer&,before:blot_check_types::Obligation)->blot_support::Option<blot_check_types::Obligation>,blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}variable=root;}for shape,index in shapes {let argument,err=self_.parameterArgument(self_.parameter_patterns.list(family.patterns)[index],self_.tree.list(syntax)[index],true,0);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let selected,err=self_.types.substitute(shape,old,fresh);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let err=self_.constrain(selected,argument,self_.tree.list(syntax)[index]);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let root,err=self_.types.resolve(selected,0);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let err=arguments.append(root);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}}let parameter,err=self_.types.substitute(template.parameter,old,fresh);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let output,err=self_.types.substitute(template.result,old,fresh);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let latent,err=self_.types.freshEffects();if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}var row=latent;if self_.current==0 && self_.closed_type_variables {let label,err=self_.types.internSymbolicOperation(template.identity,arguments.items);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}let established,err=self_.types.effects.row([label],blot_check_effects::Tail.closed);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),blot_check_types::effectError(err);}row=established;}var result=before;let ty,err=self_.types.functionWithEffects(parameter,output,row);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}result.ty=ty;result.signature=ty;let product,err=self_.types.product(arguments.items);if err!=blot_error::Error.none {return blot_support::none<blot_check_types::Obligation>(),err;}result.other=product;result.identity=template.identity;return blot_support::some(result),blot_error::Error.none;}
recursive fn beginQualification(self_:Engine&,scope:u32,where_node:u32,annotation:u32,value:u32)->blot_error::Error {if where_node==0 {return blot_error::Error.none;}if annotation==0 {var annotated=false;let stag=self_.tree.node(scope).tag;if (stag==blot_parse_ast::tag_value_decl&&self_.tree.value_decl(scope).function_declaration)||(stag==blot_parse_ast::tag_entry_kernel_decl&&self_.tree.entry_kernel_decl(scope).stateless) {var body=value;while self_.tree.node(body).tag==blot_parse_ast::tag_lambda {let lambda_node=self_.tree.node(body);let parameter=self_.tree.parameter(lambda_node.a);if !parameter.is_unit&&parameter.annotation==0 {break;}if lambda_node.c!=0 {annotated=true;break;}body=lambda_node.b;}}if !annotated {let err=self_.diagnostic(Code.invalid_constraint,where_node);if err!=blot_error::Error.none {return err;}}}let node=self_.tree.node(where_node);let start=self_.declared_obligations.len as u32;var predicates=PredicateBuffer{..};let result=beginQualificationPredicates(self_,scope,where_node,value,node,start,predicates);predicates.deinit(equation_values);return result;}
recursive fn beginQualificationPredicates(self_:Engine&,scope:u32,where_node:u32,value:u32,node:blot_parse_ast::Node,start:u32,predicates:PredicateBuffer&)->blot_error::Error {let syntax_source_40=blot_parse_ast::List{node.a,node.b, ..};let syntax_count_40=self_.tree.list(syntax_source_40).len;for syntax_index_40 in 0..syntax_count_40 {let syntax=self_.tree.list(syntax_source_40)[syntax_index_40];let err=self_.lowerPredicates(syntax,where_node,predicates);if err!=blot_error::Error.none {return err;}}for constraint in predicates.items {self_.declared_obligations.push(constraint);let err=self_.appendPending(PendingObligation{ value:constraint, owner:self_.current, declared:true, suspended:true, .. });if err!=blot_error::Error.none {return err;}}self_.qualifications.push(Qualification{scope:scope,owner:self_.current,clauses:blot_check_types::List{start:start,len:self_.declared_obligations.len as u32-start, ..},value:value, ..});return blot_error::Error.none;}
fn requirementOpen(self_:Engine&,constraint:blot_check_types::Obligation)->bool,blot_error::Error {let include=constraint.kind!=blot_check_types::ObligationKind.dispatch && constraint.kind!=blot_check_types::ObligationKind.result_dispatch && constraint.kind!=blot_check_types::ObligationKind.receiver && constraint.kind!=blot_check_types::ObligationKind.update;var parts:u32[4]=[constraint.ty,constraint.other,constraint.result,0];if include {parts[3]=constraint.signature;}for part in parts {if part==0 {continue;}let projection,err=self_.types.containsProjection(part);if err!=blot_error::Error.none || projection {return projection,err;}let values,err=self_.types.freeVariables(part);if err!=blot_error::Error.none {return false,err;}if values.len!=0 {return true,blot_error::Error.none;}let rows,err=self_.types.freeRowVariables(part);if err!=blot_error::Error.none {return false,err;}if rows.len!=0 {return true,blot_error::Error.none;}}return false,blot_error::Error.none;}
fn sourceRequirement(kind:blot_check_types::ObligationKind)->bool {return kind==blot_check_types::ObligationKind.type_eq || kind==blot_check_types::ObligationKind.contract || kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.writable_field || kind==blot_check_types::ObligationKind.receiver || kind==blot_check_types::ObligationKind.update || kind==blot_check_types::ObligationKind.effect_operation || kind==blot_check_types::ObligationKind.type_rep || kind==blot_check_types::ObligationKind.effect_rep;}
fn requirementHead(self_:const Engine&,wanted:blot_check_types::Obligation,declared:blot_check_types::Obligation)->bool {if wanted.kind==blot_check_types::ObligationKind.dispatch && declared.kind==blot_check_types::ObligationKind.dispatch {if wanted.name!=0 {return wanted.name==declared.name;}return wanted.operator!=blot_check_types::Operator.none && wanted.operator==declared.operator;}if wanted.kind==blot_check_types::ObligationKind.field && (declared.kind==blot_check_types::ObligationKind.field || declared.kind==blot_check_types::ObligationKind.receiver) {return wanted.name==declared.name && (declared.kind==blot_check_types::ObligationKind.field || self_.types.node(self_.types.head(declared.other,0)).tag==blot_check_types::Tag.unit);}if wanted.kind==blot_check_types::ObligationKind.writable_field && declared.kind==blot_check_types::ObligationKind.update {return wanted.name==declared.name;}if wanted.kind!=declared.kind {return false;}if wanted.kind==blot_check_types::ObligationKind.effect_operation || wanted.kind==blot_check_types::ObligationKind.contract {return wanted.identity==declared.identity;}return wanted.name==declared.name;}
fn unifyRequirement(self_:Engine&,wanted:blot_check_types::Obligation,declared:blot_check_types::Obligation)->bool,blot_error::Error {if !self_.requirementHead(wanted,declared) {return false,blot_error::Error.none;}if wanted.kind==blot_check_types::ObligationKind.contract {let left,err=self_.rewriteGiven(wanted.ty,0);if err!=blot_error::Error.none {return false,err;}let right,err=self_.rewriteGiven(declared.ty,0);if err!=blot_error::Error.none {return false,err;}return self_.types.equalSymbolic(left,right);}if wanted.kind==blot_check_types::ObligationKind.type_eq {let left,err=self_.rewriteGiven(wanted.ty,0);if err!=blot_error::Error.none {return false,err;}let right,err=self_.rewriteGiven(wanted.result,0);if err!=blot_error::Error.none {return false,err;}return self_.types.equalSymbolic(left,right);}let point=self_.types.mark();let matched,err=unifyRequirementTrial(self_,wanted,declared);if err==blot_error::Error.none && !matched {self_.types.rollback(point);}return matched,err;}
fn requirementUnify(self_:Engine&,left:u32,right:u32)->bool,blot_error::Error {let err=self_.types.unify(left,right);if err==blot_error::Error.out_of_memory || err==blot_error::Error.type_limit {return false,err;}return err==blot_error::Error.none,blot_error::Error.none;}
fn unifyRequirementTrial(self_:Engine&,wanted:blot_check_types::Obligation,declared:blot_check_types::Obligation)->bool,blot_error::Error {let matched,err=requirementUnify(self_,wanted.ty,declared.ty);if err!=blot_error::Error.none || !matched {return false,err;}if wanted.kind==blot_check_types::ObligationKind.writable_field && declared.kind==blot_check_types::ObligationKind.update {let matched,err=requirementUnify(self_,wanted.result,declared.other);if err!=blot_error::Error.none || !matched {return false,err;}let matched,err=requirementUnify(self_,wanted.ty,declared.result);if err!=blot_error::Error.none || !matched {return false,err;}}else {if wanted.other!=0 && declared.other!=0 && wanted.kind!=blot_check_types::ObligationKind.field {let matched,err=requirementUnify(self_,wanted.other,declared.other);if err!=blot_error::Error.none || !matched {return false,err;}}if wanted.result!=0 && declared.result!=0 {let matched,err=requirementUnify(self_,wanted.result,declared.result);if err!=blot_error::Error.none || !matched {return false,err;}}}if wanted.signature!=0 && declared.signature!=0 {if wanted.kind==blot_check_types::ObligationKind.effect_operation {return requirementUnify(self_,wanted.signature,declared.signature);}let left,err=self_.types.resolve(wanted.signature,0);if err!=blot_error::Error.none {return false,err;}let right,err=self_.types.resolve(declared.signature,0);if err!=blot_error::Error.none {return false,err;}let a=self_.types.node(left);let b=self_.types.node(right);if a.tag!=blot_check_types::Tag.function || b.tag!=blot_check_types::Tag.function {return false,blot_error::Error.none;}let ambient_signature=wanted.kind==blot_check_types::ObligationKind.dispatch || wanted.kind==blot_check_types::ObligationKind.result_dispatch;let row,err=self_.types.resolveEffects(a.c,0);if err!=blot_error::Error.none {return false,err;}let ambient=self_.types.row(row);var closed=false;match ambient.tail {closed=>{closed=true;},_=>{}}let pure=closed && ambient.labels.len==0;if !ambient_signature || pure {let err=self_.types.unifyEffects(a.c,b.c);if err==blot_error::Error.out_of_memory {return false,err;}if err!=blot_error::Error.none {return false,blot_error::Error.none;}}}return true,blot_error::Error.none;}
fn checkQualification(self_:Engine&,index:i64)->blot_error::Error {let boundary=self_.qualifications[index];if boundary.checked {return blot_error::Error.none;}for use in self_.qualification_uses {if use.scope==boundary.scope {let state .= self_.global_states.get(use.target);assert(state!=null);if state.on_stack && !inList(self_.finishing_group,use.target) {return blot_error::Error.none;}}}var ordinal:i64=0;while ordinal<self_.pending.len {let err=checkQualificationPending(self_,boundary,ordinal);if err!=blot_error::Error.none {return err;}ordinal+=1;}self_.qualifications[index].checked=true;return blot_error::Error.none;}
fn checkQualificationPending(self_:Engine&,boundary:Qualification,index:i64)->blot_error::Error {let pending=self_.pending[index];if pending.scope!=boundary.scope || pending.declared || pending.covered || pending.solved || pending.local_scheme {return blot_error::Error.none;}if pending.value.kind==blot_check_types::ObligationKind.callee_use {self_.pending[index].solved=true;return self_.expandUse(pending,pending.expansion);}if !sourceRequirement(pending.value.kind) {return blot_error::Error.none;}if pendingHasComptimeFieldVar(self_,pending.value) {return blot_error::Error.none;}let open,err=self_.requirementOpen(pending.value);if err!=blot_error::Error.none {return err;}if !open {if pending.method_member && !pending.value.explicit && pending.value.kind==blot_check_types::ObligationKind.receiver && self_.types.node(self_.types.head(pending.value.other,0)).tag==blot_check_types::Tag.unit && pending.owner!=0 && pending.scope==self_.bindings[pending.owner].declaration && self_.bindings[pending.owner].scheme.root==0 {let state .= self_.global_states.get(pending.owner);if state && state.state==State.complete {let receiver=self_.identityOf(pending.value.ty);if receiver.present {let scalar_lookup_74 .= self_.catalogs.associated_members.get(AssociatedMember{identity:receiver.value,member:pending.value.name, ..});if scalar_lookup_74 && self_.associated[scalar_lookup_74].binding==pending.owner {let member:u32=scalar_lookup_74;self_.pending[index].suspended=true;}}}}return blot_error::Error.none;}var coverage=pending.value;if pending.method_member && !coverage.explicit && coverage.kind==blot_check_types::ObligationKind.receiver && self_.types.node(self_.types.head(coverage.other,0)).tag==blot_check_types::Tag.unit {coverage.kind=blot_check_types::ObligationKind.field;coverage.other=0;}var matched=false;for clause in 0..boundary.clauses.len {let declared=self_.declared_obligations[boundary.clauses.start+clause];let equal,err=self_.unifyRequirement(coverage,declared);if err!=blot_error::Error.none {return err;}if equal {if coverage.kind==blot_check_types::ObligationKind.result_dispatch {let resolved,err=self_.types.resolve(declared.signature,0);if err!=blot_error::Error.none {return err;}let carrier=self_.types.node(resolved);let signature,err=self_.types.functionWithEffects(coverage.ty,coverage.result,carrier.c);if err!=blot_error::Error.none {return err;}self_.dispatch_signatures[coverage.source]=signature;}matched=true;break;}}if !matched {let err=self_.diagnostic(Code.missing_predicate,pending.value.source);if err!=blot_error::Error.none {return err;}if pending.origin!=0 {self_.diagnostics[self_.diagnostics.len-1].span=self_.predicate_origins[pending.origin-1];}else {let ast_walk_28_count=self_.tree.operator_origins.items.len;for ast_walk_28_index in 0..ast_walk_28_count {let origin=self_.tree.operator_origins.items[ast_walk_28_index];if origin.node==pending.value.source && self_.tree.node(origin.node).tag==blot_parse_ast::tag_binary {self_.diagnostics[self_.diagnostics.len-1].span=origin.span;break;}}}}else {self_.covered_requirements.push(CoveredRequirement{scope:boundary.scope,value:pending.value, ..});self_.pending[index].covered=true;self_.pending[index].suspended=true;}return blot_error::Error.none;}
fn targetRequirements(self_:Engine&,target:u32,limit:i64,visited:IdBuffer&,output:PredicateBuffer&)->blot_error::Error {var work=IdBuffer{..};let result=targetRequirementWork(self_,target,limit,visited,output,work);work.deinit(equation_type_ids);return result;}
fn targetRequirementWork(self_:Engine&,target:u32,limit:i64,visited:IdBuffer&,output:PredicateBuffer&,work:IdBuffer&)->blot_error::Error {let err=work.append(target);if err!=blot_error::Error.none {return err;}while work.items.len!=0 {let current=work.items[work.items.len-1];work.resize(work.items.len-1);let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}if inList(visited.items,current) {continue;}let err=visited.append(current);if err!=blot_error::Error.none {return err;}let scope=self_.bindings[current].declaration;var qualified=false;for boundary in self_.qualifications {if boundary.scope==scope {for predicate in self_.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {let err=output.append(predicate);if err!=blot_error::Error.none {return err;}}qualified=true;break;}}if qualified {continue;}for pending in self_.pending[..limit] {if pending.scope==scope && !pending.solved && !pending.declared && !pending.covered && !pending.local_scheme {let err=output.append(pending.value);if err!=blot_error::Error.none {return err;}}}var index=self_.qualification_uses.len;while index!=0 {index-=1;let use=self_.qualification_uses[index];if use.scope==scope {let err=work.append(use.target);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;}
fn prepareQualifications(self_:Engine&,group:const u32[:])->blot_error::Error {var index:i64=0;while index<self_.pending.len {let pending=self_.pending[index];if pending.declared || pending.covered || pending.solved || pending.local_scheme || pending.value.kind!=blot_check_types::ObligationKind.callee_use {index+=1;continue;}var qualified=false;for boundary in self_.qualifications {if boundary.scope==pending.scope && inList(group,boundary.owner) {qualified=true;break;}}if qualified {let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}self_.pending[index].solved=true;let err=self_.expandUse(pending,pending.expansion);if err!=blot_error::Error.none {return err;}}index+=1;}return blot_error::Error.none;}
fn expandQualificationUses(self_:Engine&,group:const u32[:])->blot_error::Error {var qualified=false;for boundary in self_.qualifications {if inList(group,boundary.owner) {qualified=true;break;}}if !qualified {return blot_error::Error.none;}let limit=self_.pending.len;let scope=self_.qualification_scope;let count=self_.qualification_uses.len;let result=expandQualificationReferences(self_,group,limit,count);self_.qualification_scope=scope;return result;}
fn expandQualificationReferences(self_:Engine&,group:const u32[:],limit:i64,count:i64)->blot_error::Error {for index in 0..count {let use=self_.qualification_uses[index];if !inList(group,use.target) {continue;}var visited=IdBuffer{..};var requirements=PredicateBuffer{..};let result=forwardQualificationRequirements(self_,use,index,limit,visited,requirements);requirements.deinit(equation_values);visited.deinit(equation_type_ids);if result!=blot_error::Error.none {return result;}}return blot_error::Error.none;}
fn forwardQualificationRequirements(self_:Engine&,use:QualificationUse,index:i64,limit:i64,visited:IdBuffer&,requirements:PredicateBuffer&)->blot_error::Error {let err=self_.targetRequirements(use.target,limit,visited,requirements);if err!=blot_error::Error.none {return err;}self_.qualification_scope=use.scope;for constraint in requirements.items {let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}let forwarded=ForwardedRequirement{use:index,value:constraint, ..};if self_.forwarded_requirements.contains(forwarded) {continue;}var value=constraint;value.source=use.source;let origin,err=self_.memberUseOrigin(value,use.source);if err!=blot_error::Error.none {return err;}let err=self_.appendPending(PendingObligation{ value:value, owner:use.owner, origin:origin, suspended:value.explicit, .. });if err!=blot_error::Error.none {return err;}self_.forwarded_requirements.insert(forwarded,true);}return blot_error::Error.none;}
fn explicitRequirement(self_:const Engine&,value:blot_check_types::Obligation)->bool {return value.explicit || (value.kind==blot_check_types::ObligationKind.callee_use && self_.bindings[value.identity.decl].summary.has_explicit);}
struct SchemeCandidate {index:i64,variables:blot_check_types::List,rows:blot_check_types::List,retained:bool=false}
struct SchemeCandidates {entries:blot_support_pooled_buffer::Buffer<SchemeCandidate>   = blot_support_pooled_buffer::Buffer<SchemeCandidate>{..},variables:IdBuffer=IdBuffer{..},rows:IdBuffer=IdBuffer{..}}
reusable[] var scheme_candidate_runs:SchemeCandidate[>..];
type Suspensions=blot_support_pooled_buffer::Buffer<i64>;
reusable[] var suspension_runs:i64[>..];
fn deinit(self_:SchemeCandidates&) {self_.entries.deinit(scheme_candidate_runs);self_.variables.deinit(equation_type_ids);self_.rows.deinit(equation_type_ids);}
fn types(self_:const SchemeCandidates&,candidate:SchemeCandidate)->const u32[:] {return self_.variables.items[candidate.variables.start..candidate.variables.start+candidate.variables.len];}
fn effects(self_:const SchemeCandidates&,candidate:SchemeCandidate)->const u32[:] {return self_.rows.items[candidate.rows.start..candidate.rows.start+candidate.rows.len];}
recursive fn schemeCandidates(self_:Engine&,group:const u32[:],capture_concrete:bool,qualification_scope:u32,candidates:SchemeCandidates&)->blot_error::Error {self_.frontend_work.scheme_calls+=1;let range=self_.pendingRange(group);self_.frontend_work.candidate_scans+=(range.end-range.start) as u64;var parts=IdBuffer{..};let result=schemeCandidateScan(self_,group,capture_concrete,qualification_scope,candidates,range,parts);parts.deinit(equation_type_ids);return result;}
fn hasDiagnosticCodeAt(self_:const Engine&,code:Code,source:u32)->bool {
 for issue in self_.diagnostics {
  if issue.code==code && issue.node==source {return true;}
 }
 return false;
}
recursive fn solveTypeEq(self_:Engine&,constraint:blot_check_types::Obligation)->bool,blot_error::Error {
 let had_lproj,lperr0=self_.types.containsProjection(constraint.ty);
 if lperr0!=blot_error::Error.none {return false,lperr0;}
 let had_rproj,rperr0=self_.types.containsProjection(constraint.result);
 if rperr0!=blot_error::Error.none {return false,rperr0;}
 let had_missing=hasDiagnosticCodeAt(self_,Code.missing_implementation,constraint.source);
 let before=self_.diagnostics.len;
 let left,lerr=self_.normalizeAssociated(constraint.ty,constraint.source,false);
 if lerr!=blot_error::Error.none {return false,lerr;}
 let right,rerr=self_.normalizeAssociated(constraint.result,constraint.source,false);
 if rerr!=blot_error::Error.none {return false,rerr;}
 if self_.diagnostics.len!=before {
  if had_missing {
   var all_dup=true;
   for issue in self_.diagnostics[before..] {
    if issue.code!=Code.missing_implementation || issue.node!=constraint.source {all_dup=false;break;}
   }
   if all_dup {
    deinitDiagnosticPayloads(self_.diagnostics[before..]);
    self_.diagnostics.resize(before);
   }
  }
  return true,blot_error::Error.none;
 }
 let lproj,lperr=self_.types.containsProjection(left);
 if lperr!=blot_error::Error.none {return false,lperr;}
 let rproj,rperr=self_.types.containsProjection(right);
 if rperr!=blot_error::Error.none {return false,rperr;}
 if lproj || rproj {return false,blot_error::Error.none;}
 if !had_lproj && !had_rproj {
  var normalized=constraint;
  normalized.ty=left;
  normalized.result=right;
  let open,oerr=self_.requirementOpen(normalized);
  if oerr!=blot_error::Error.none {return false,oerr;}
  if open {return false,blot_error::Error.none;}
 }
 let err=self_.constrain(left,right,constraint.source);
 if err!=blot_error::Error.none {return false,err;}
 return true,blot_error::Error.none;
}
recursive fn schemeCandidateScan(self_:Engine&,group:const u32[:],capture:bool,scope:u32,candidates:SchemeCandidates&,range:PendingRange,parts:IdBuffer&)->blot_error::Error {for index in range.start..range.end {let pending=self_.pending[index];if pending.solved || pending.covered || pending.local_scheme || !inList(group,pending.owner) || (pending.declared && pending.scope!=scope) {continue;}if pendingHasComptimeFieldVar(self_,pending.value) {continue;}if pending.value.kind==blot_check_types::ObligationKind.contract {if !pending.declared {let open,err=self_.requirementOpen(pending.value);if err!=blot_error::Error.none {return err;}if !open {let saved=self_.current;self_.current=pending.owner;let solved,error=schemeSelectClosed(self_,pending);self_.current=saved;if error!=blot_error::Error.none {return error;}if solved {self_.pending[index].solved=true;continue;}}}}if pending.value.kind==blot_check_types::ObligationKind.type_eq && !pending.declared {let saved=self_.current;let saved_impl=self_.checking_implementation;self_.current=pending.owner;{let il .= self_.implementation_bindings.get(pending.owner);if il {self_.checking_implementation=blot_support::some(il);}else {self_.checking_implementation=blot_support::none<u32>();}}let solved,error=self_.solveTypeEq(pending.value);self_.current=saved;self_.checking_implementation=saved_impl;if error!=blot_error::Error.none {return error;}if solved {self_.pending[index].solved=true;continue;}}if !capture && self_.explicitRequirement(pending.value) && index<self_.local_requirements_start {continue;}var qualified=false;for boundary in self_.qualifications {if boundary.scope==scope {qualified=true;break;}}if qualified && !pending.declared && pending.scope==scope && sourceRequirement(pending.value.kind) {continue;}self_.frontend_work.candidates+=1;if candidates.variables.items.len>0xffffffff || candidates.rows.items.len>0xffffffff {return blot_error::Error.type_limit;}let variable_start=candidates.variables.items.len as u32;let row_start=candidates.rows.items.len as u32;parts.clear();if !capture && pending.value.kind==blot_check_types::ObligationKind.callee_use && self_.bindings[pending.value.identity.decl].summary.has_explicit {let err=self_.requirementParts(pending.value,parts);if err!=blot_error::Error.none {return err;}}else {for part in [pending.value.ty,pending.value.other,pending.value.result,pending.value.signature] {if part!=0 {let err=parts.append(part);if err!=blot_error::Error.none {return err;}}}}self_.frontend_work.candidate_parts+=parts.items.len as u64;if self_.execution.scheme_dependency_reuse {let dependencies,err=self_.scheme_dependencies.query(self_.types,index,parts.items);if err!=blot_error::Error.none {return err;}assert(dependencies!=null);for variable in dependencies.variables {let err=candidates.variables.append(variable);if err!=blot_error::Error.none {return err;}}for row in dependencies.rows {let err=candidates.rows.append(row);if err!=blot_error::Error.none {return err;}}}else {for part in parts.items {if part==0 {continue;}let free,err=self_.types.freeVariables(part);if err!=blot_error::Error.none {return err;}for variable in free {if !inList(candidates.variables.items[variable_start..],variable) {let err=candidates.variables.append(variable);if err!=blot_error::Error.none {return err;}}}}for part in parts.items {if part==0 {continue;}let free,err=self_.types.freeRowVariables(part);if err!=blot_error::Error.none {return err;}for row in free {if !inList(candidates.rows.items[row_start..],row) {let err=candidates.rows.append(row);if err!=blot_error::Error.none {return err;}}}}}if candidates.variables.items.len-variable_start>0xffffffff || candidates.rows.items.len-row_start>0xffffffff {return blot_error::Error.type_limit;}let variables=blot_check_types::List{start:variable_start,len:(candidates.variables.items.len-variable_start) as u32, ..};let rows=blot_check_types::List{start:row_start,len:(candidates.rows.items.len-row_start) as u32, ..};self_.frontend_work.candidate_variables+=variables.len;self_.frontend_work.candidate_rows+=rows.len;let err=blot_support_pooled_buffer::push(candidates.entries,SchemeCandidate{index:index,variables:variables,rows:rows, ..},scheme_candidate_runs);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
recursive fn schemeSelectClosed(self_:Engine&,pending:PendingObligation)->bool,blot_error::Error {let application=self_.types.node(self_.types.head(pending.value.ty,0));if application.tag!=blot_check_types::Tag.product {return false,blot_error::Error.none;}let had_missing=hasDiagnosticCodeAt(self_,Code.missing_implementation,pending.value.source);let before=self_.diagnostics.len;let matched,_,err=self_.resolveTraitImpl(pending.value.identity,self_.types.list(blot_check_types::List{application.a,application.b, ..}),0,pending.value.source);if err!=blot_error::Error.none {return false,err;}let emitted=self_.diagnostics.len!=before;if emitted && had_missing {var all_dup=true;for issue in self_.diagnostics[before..] {if issue.code!=Code.missing_implementation || issue.node!=pending.value.source {all_dup=false;break;}}if all_dup {deinitDiagnosticPayloads(self_.diagnostics[before..]);self_.diagnostics.resize(before);}}return matched || emitted,blot_error::Error.none;}
fn schemeRequirements<O>(self_:Engine&,candidates:const SchemeCandidate[:],capture:bool,output:O&,suspensions:Suspensions?)->blot_check_types::List,blot_error::Error {let start=predicateValues(output).len as u32;for candidate in candidates {if !candidate.retained {continue;}let pending=self_.pending[candidate.index];if pending.solved || pending.covered {continue;}let ty,err=self_.types.resolve(pending.value.ty,0);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}var result:u32=0;if pending.value.result!=0 {let root,err=self_.types.resolve(pending.value.result,0);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}result=root;}var other:u32=0;if pending.value.other!=0 {let root,err=self_.types.resolve(pending.value.other,0);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}other=root;}var signature:u32=0;if pending.value.signature!=0 {let root,err=self_.types.resolve(pending.value.signature,0);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}signature=root;}let value=blot_check_types::Obligation{ty:ty,kind:pending.value.kind,source:pending.value.source,name:pending.value.name,result:result,other:other,signature:signature,operator:pending.value.operator,identity:pending.value.identity,explicit:pending.value.explicit,qualification_span:pending.value.qualification_span,qualification_unit:pending.value.qualification_unit, ..};let err=predicateAppend(output,value);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}if suspensions {let err=blot_support_pooled_buffer::push(suspensions,candidate.index,suspension_runs);if err!=blot_error::Error.none {return blot_check_types::List{..},err;}}else {self_.pending[candidate.index].suspended=true;}if !capture && self_.explicitRequirement(pending.value) {self_.pending[candidate.index].local_scheme=true;}}return blot_check_types::List{start:start,len:predicateValues(output).len as u32-start, ..},blot_error::Error.none;}
struct SchemeWork {candidates:SchemeCandidates=SchemeCandidates{..},outer:IdBuffer=IdBuffer{..},outer_rows:IdBuffer=IdBuffer{..},variables:IdBuffer=IdBuffer{..},row_variables:IdBuffer=IdBuffer{..},protected_rows:IdBuffer=IdBuffer{..},outer_index:blot_check_ordered_membership::PooledIndex=blot_check_ordered_membership::PooledIndex{..},outer_rows_index:blot_check_ordered_membership::PooledIndex=blot_check_ordered_membership::PooledIndex{..},variables_index:blot_check_ordered_membership::PooledIndex=blot_check_ordered_membership::PooledIndex{..},row_variables_index:blot_check_ordered_membership::PooledIndex=blot_check_ordered_membership::PooledIndex{..},protected_rows_index:blot_check_ordered_membership::PooledIndex=blot_check_ordered_membership::PooledIndex{..}}
fn deinit(self_:SchemeWork&) {self_.protected_rows_index.deinit();self_.row_variables_index.deinit();self_.variables_index.deinit();self_.outer_rows_index.deinit();self_.outer_index.deinit();self_.protected_rows.deinit(equation_type_ids);self_.row_variables.deinit(equation_type_ids);self_.variables.deinit(equation_type_ids);self_.outer_rows.deinit(equation_type_ids);self_.outer.deinit(equation_type_ids);self_.candidates.deinit();}
recursive fn scheme(self_:Engine&,root:u32,excluded:const u32[:],group:const u32[:],capture:bool,certificate_owner:u32,scope:u32)->blot_check_types::Scheme,blot_error::Error {return self_.schemeInto(root,excluded,group,capture,certificate_owner,scope,self_.obligations,null);}
recursive fn schemeInto<O>(self_:Engine&,root:u32,excluded:const u32[:],group:const u32[:],capture:bool,certificate_owner:u32,scope:u32,output:O&,suspensions:Suspensions?)->blot_check_types::Scheme,blot_error::Error {let err=self_.solveFields();if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}if capture {
    let err=self_.expandInformedUses(group,false);
    if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}
    let err=self_.inferResultOperands(group,0,0);
    if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}
}let resolved,err=self_.types.resolve(root,0);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let free,err=freeVariableRun(self_.types,resolved);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}var work=SchemeWork{..};let enabled=self_.execution.indexed_scheme_membership;work.outer_index.enabled=enabled;work.outer_rows_index.enabled=enabled;work.variables_index.enabled=enabled;work.row_variables_index.enabled=enabled;work.protected_rows_index.enabled=enabled;let result,error=schemeIntoWork(self_,resolved,free,excluded,group,capture,certificate_owner,scope,output,suspensions,work);work.deinit();equation_type_ids.free_slice(free);return result,error;}
fn freeRowRun(store:blot_check_types::Store&,root:u32)->u32[:],blot_error::Error {let values,err=store.freeRowVariables(root);if err!=blot_error::Error.none {return default<u32[:]>(),err;}let result=equation_type_ids.alloc_slice(values.len);for value,index in values {result[index]=value;}return result,blot_error::Error.none;}
fn environmentRows(self_:Engine&)->u32[:],blot_error::Error {var free=IdBuffer{..};let error=environmentRowValues(self_,free);if error!=blot_error::Error.none {free.deinit(equation_type_ids);return default<u32[:]>(),error;}let result=equation_type_ids.alloc_slice(free.items.len);for value,index in free.items {result[index]=value;}free.deinit(equation_type_ids);return result,blot_error::Error.none;}
fn environmentRowValues(self_:Engine&,free:IdBuffer&)->blot_error::Error {for entry in self_.env {let binding=self_.bindings[entry.binding];var root=binding.ty;if binding.scheme.root!=0 {root=binding.scheme.root;}let variables,err=self_.types.freeRowVariables(root);if err!=blot_error::Error.none {return err;}for variable in variables {if !inList(self_.types.list(binding.scheme.row_variables),variable) && !inList(free.items,variable) {let err=free.append(variable);if err!=blot_error::Error.none {return err;}}}}for binding in self_.active {let variables,err=self_.types.freeRowVariables(self_.bindings[binding].ty);if err!=blot_error::Error.none {return err;}for variable in variables {if !inList(free.items,variable) {let err=free.append(variable);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;}
fn environmentFree(self_:Engine&)->u32[:],blot_error::Error {var free=IdBuffer{..};let error=environmentTypeValues(self_,free);if error!=blot_error::Error.none {free.deinit(equation_type_ids);return default<u32[:]>(),error;}let result=equation_type_ids.alloc_slice(free.items.len);for value,index in free.items {result[index]=value;}free.deinit(equation_type_ids);return result,blot_error::Error.none;}
fn environmentTypeValues(self_:Engine&,free:IdBuffer&)->blot_error::Error {for entry in self_.env {let binding=self_.bindings[entry.binding];var root=binding.ty;if binding.scheme.root!=0 {root=binding.scheme.root;}let variables,err=self_.types.freeVariables(root);if err!=blot_error::Error.none {return err;}for variable in variables {if !inList(self_.types.list(binding.scheme.variables),variable) && !inList(free.items,variable) {let err=free.append(variable);if err!=blot_error::Error.none {return err;}}}}for binding in self_.active {let variables,err=self_.types.freeVariables(self_.bindings[binding].ty);if err!=blot_error::Error.none {return err;}for variable in variables {if !inList(free.items,variable) {let err=free.append(variable);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;}
recursive fn schemeIntoWork<O>(self_:Engine&,resolved:u32,free:const u32[:],excluded:const u32[:],group:const u32[:],capture:bool,certificate_owner:u32,scope:u32,output:O&,suspensions:Suspensions?,work:SchemeWork&)->blot_check_types::Scheme,blot_error::Error {let err=self_.schemeCandidates(group,capture,scope,work.candidates);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for variable in excluded {let err=work.outer.append(variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}let ambient,err=self_.types.effects.freeVariables(self_.ambient);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},blot_check_types::effectError(err);}for row in ambient {let err=work.outer_rows.append(row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}if !capture {for annotation in self_.computation_annotations {let variables,err=self_.types.freeVariables(annotation);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for variable in variables {let err=work.outer.append(variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}let rows,err=self_.types.freeRowVariables(annotation);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for row in rows {let err=work.outer_rows.append(row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}}for variable in self_.computed_variables {let err=work.outer.append(variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}for row in self_.computed_rows {let err=work.outer_rows.append(row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}let rows,err=self_.environmentRows();if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let error=appendSchemeRows(work.outer_rows,rows);equation_type_ids.free_slice(rows);if error!=blot_error::Error.none {return blot_check_types::Scheme{..},error;}}let err=schemeOuterClosure(work);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for variable in free {let outer,err=work.outer_index.contains(work.outer.items,variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}if !outer {let err=work.variables.append(variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}}let rows,err=self_.types.freeRowVariables(resolved);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for row in rows {let outer,err=work.outer_rows_index.contains(work.outer_rows.items,row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}if !outer {let err=work.row_variables.append(row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}}let err=schemeRetainedClosure(self_,capture,work);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}for candidate in work.candidates.entries.items {if !candidate.retained {continue;}for row in work.candidates.effects(candidate) {let protected,err=work.protected_rows_index.contains(work.protected_rows.items,row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}if !protected {let err=work.protected_rows.append(row);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}}}}return schemeClose(self_,resolved,capture,certificate_owner,output,suspensions,work);}
fn appendSchemeRows(output:IdBuffer&,rows:const u32[:])->blot_error::Error {for row in rows {let err=output.append(row);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn schemeOuterClosure(work:SchemeWork&)->blot_error::Error {var progress=true;while progress {progress=false;for candidate in work.candidates.entries.items {var connected=false;for variable in work.candidates.types(candidate) {let outer,err=work.outer_index.contains(work.outer.items,variable);if err!=blot_error::Error.none {return err;}if outer {connected=true;break;}}for row in work.candidates.effects(candidate) {let outer,err=work.outer_rows_index.contains(work.outer_rows.items,row);if err!=blot_error::Error.none {return err;}if outer {connected=true;break;}}if !connected {continue;}for row in work.candidates.effects(candidate) {let outer,err=work.outer_rows_index.contains(work.outer_rows.items,row);if err!=blot_error::Error.none {return err;}if !outer {let err=work.outer_rows.append(row);if err!=blot_error::Error.none {return err;}progress=true;}}for variable in work.candidates.types(candidate) {let outer,err=work.outer_index.contains(work.outer.items,variable);if err!=blot_error::Error.none {return err;}if !outer {let err=work.outer.append(variable);if err!=blot_error::Error.none {return err;}progress=true;}}}}return blot_error::Error.none;}
fn schemeConcreteKind(kind:blot_check_types::ObligationKind)->bool {return kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.effect_operation || kind==blot_check_types::ObligationKind.effect_handler || kind==blot_check_types::ObligationKind.type_head || kind==blot_check_types::ObligationKind.callee_use;}
fn schemeRetainedClosure(self_:Engine&,capture:bool,work:SchemeWork&)->blot_error::Error {var progress=true;while progress {progress=false;for &candidate in work.candidates.entries.items {let pending=self_.pending[candidate.index];var retained=candidate.retained || pending.method_member || self_.explicitRequirement(pending.value) || (capture && schemeConcreteKind(pending.value.kind) && !pending.suspended);if !retained {for variable in work.candidates.types(candidate) {let known,err=work.variables_index.contains(work.variables.items,variable);if err!=blot_error::Error.none {return err;}if known {retained=true;break;}}}if !retained {for row in work.candidates.effects(candidate) {let known,err=work.row_variables_index.contains(work.row_variables.items,row);if err!=blot_error::Error.none {return err;}if known {retained=true;break;}}}if !retained {continue;}if !candidate.retained {candidate.retained=true;progress=true;}for row in work.candidates.effects(candidate) {let outer,err=work.outer_rows_index.contains(work.outer_rows.items,row);if err!=blot_error::Error.none {return err;}if !outer {let known,err=work.row_variables_index.contains(work.row_variables.items,row);if err!=blot_error::Error.none {return err;}if !known {let err=work.row_variables.append(row);if err!=blot_error::Error.none {return err;}progress=true;}}}for variable in work.candidates.types(candidate) {let outer,err=work.outer_index.contains(work.outer.items,variable);if err!=blot_error::Error.none {return err;}if !outer {let known,err=work.variables_index.contains(work.variables.items,variable);if err!=blot_error::Error.none {return err;}if !known {let err=work.variables.append(variable);if err!=blot_error::Error.none {return err;}progress=true;}}}}}return blot_error::Error.none;}
fn schemeClose<O>(self_:Engine&,resolved:u32,capture:bool,certificate_owner:u32,output:O&,suspensions:Suspensions?,work:SchemeWork&)->blot_check_types::Scheme,blot_error::Error {let closed,err=self_.types.closeCovariantCertified(resolved,work.row_variables.items,work.protected_rows.items);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let err=self_.recordClosedRows(certificate_owner,closed.closed_rows);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let remaining,err=self_.types.freeRowVariables(closed.root);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}var kept:i64=0;for variable in work.row_variables.items {var retain=inList(remaining,variable);if !retain {let protected,err=work.protected_rows_index.contains(work.protected_rows.items,variable);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}retain=protected;}if retain {work.row_variables.items[kept]=variable;kept+=1;}}work.row_variables.resize(kept);let variables,err=self_.types.saveList(work.variables.items);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let requirements,err=self_.schemeRequirements(work.candidates.entries.items,capture,output,suspensions);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}let rows,err=self_.types.saveList(work.row_variables.items);if err!=blot_error::Error.none {return blot_check_types::Scheme{..},err;}var root=closed.root;
if variables.len!=0 {
    let shared,error=self_.types.compactSignature(root);
    if error!=blot_error::Error.none {return blot_check_types::Scheme{..},error;}
    root=shared;
}
return blot_check_types::Scheme{ root:root, variables:variables, row_variables:rows, closed_rows:closed.closed_rows, obligations:requirements, .. },blot_error::Error.none;}
fn sharedKind(kind:blot_check_types::ObligationKind)->bool {return kind==blot_check_types::ObligationKind.dispatch || kind==blot_check_types::ObligationKind.result_dispatch || kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.writable_field || kind==blot_check_types::ObligationKind.receiver || kind==blot_check_types::ObligationKind.collection || kind==blot_check_types::ObligationKind.update || kind==blot_check_types::ObligationKind.effect_operation || kind==blot_check_types::ObligationKind.type_head || kind==blot_check_types::ObligationKind.type_rep || kind==blot_check_types::ObligationKind.effect_rep || kind==blot_check_types::ObligationKind.callee_use;}
fn requirementParts(self_:Engine&,requirement:blot_check_types::Obligation,output:IdBuffer&)->blot_error::Error {if requirement.kind==blot_check_types::ObligationKind.callee_use {let summary=self_.bindings[requirement.identity.decl].summary;let root,err=self_.types.resolve(requirement.ty,0);if err!=blot_error::Error.none {return err;}let product=self_.types.node(root);let instance=checkedTypeList(self_.types,blot_check_types::List{product.a,product.b, ..});let type_span_93=checkedTypeSubspan(self_.types,instance,0,summary.public_variables.len);for index in 0..(type_span_93.len as i64) {let part=self_.types.list(type_span_93)[index];if self_.types.list(summary.requirement_variables)[index]!=0 {let err=output.append(part);if err!=blot_error::Error.none {return err;}}}let type_span_94=checkedTypeSubspan(self_.types,instance,summary.public_variables.len,(instance.len as i64));for index in 0..(type_span_94.len as i64) {let part=self_.types.list(type_span_94)[index];if self_.types.list(summary.requirement_rows)[index]!=0 {let err=output.append(part);if err!=blot_error::Error.none {return err;}}}}else if sourceRequirement(requirement.kind) {let parts:u32[4]=[requirement.ty,requirement.other,requirement.result,requirement.signature];for part,index in parts {if part!=0 && !inList(parts[..index],part) {let err=output.append(part);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;}
struct SummaryWork {public_vars:IdBuffer=IdBuffer{..},public_rows:IdBuffer=IdBuffer{..},parameter_free:IdBuffer=IdBuffer{..},requirements:IdBuffer=IdBuffer{..},requirement_variables:IdBuffer=IdBuffer{..},requirement_rows:IdBuffer=IdBuffer{..}}
fn deinit(self_:SummaryWork&) {self_.requirement_rows.deinit(equation_type_ids);self_.requirement_variables.deinit(equation_type_ids);self_.requirements.deinit(equation_type_ids);self_.parameter_free.deinit(equation_type_ids);self_.public_rows.deinit(equation_type_ids);self_.public_vars.deinit(equation_type_ids);}
fn summarize(self_:Engine&,principal:blot_check_types::Scheme)->SchemeSummary,blot_error::Error {return self_.summarizeFrom(principal,self_.obligations);}
fn summarizeFrom(self_:Engine&,principal:blot_check_types::Scheme,obligations:const blot_check_types::Obligation[:])->SchemeSummary,blot_error::Error {var summary=SchemeSummary{ only_result_selected:principal.obligations.len!=0, shareable:principal.root!=0 && principal.obligations.len!=0, .. };var flat:u64=0;for constraint in obligations[principal.obligations.start..principal.obligations.start+principal.obligations.len] {if !sharedKind(constraint.kind) {summary.shareable=false;}summary.has_explicit=summary.has_explicit || constraint.explicit;if constraint.kind==blot_check_types::ObligationKind.callee_use {let callee=self_.bindings[constraint.identity.decl].summary;if !callee.shareable {summary.shareable=false;}summary.has_explicit=summary.has_explicit || callee.has_explicit;summary.only_result_selected=summary.only_result_selected && callee.only_result_selected;flat+=callee.flat_size;}else {summary.only_result_selected=summary.only_result_selected && constraint.kind==blot_check_types::ObligationKind.result_dispatch;flat+=1;}}summary.flat_size=min(flat,1073741824 as u64) as u32;if principal.root==0 || (!self_.execution.eager_scheme_summaries && principal.obligations.len==0) {return summary,blot_error::Error.none;}var work=SummaryWork{..};let result,err=summarizePublic(self_,principal,obligations,summary,work);work.deinit();return result,err;}
fn summarizePublic(self_:Engine&,principal:blot_check_types::Scheme,obligations:const blot_check_types::Obligation[:],summary:SchemeSummary,work:SummaryWork&)->SchemeSummary,blot_error::Error {let resolved,err=self_.types.resolve(principal.root,0);if err!=blot_error::Error.none {return summary,err;}let free,err=self_.types.freeVariables(resolved);if err!=blot_error::Error.none {return summary,err;}let resolved,err=self_.types.resolve(principal.root,0);if err!=blot_error::Error.none {return summary,err;}let rows,err=self_.types.freeRowVariables(resolved);if err!=blot_error::Error.none {return summary,err;}let type_span_95=checkedTypeList(self_.types,principal.variables);for type_index_95 in 0..(type_span_95.len as i64) {let variable=self_.types.list(type_span_95)[type_index_95];if inList(free,variable) {let err=work.public_vars.append(variable);if err!=blot_error::Error.none {return summary,err;}}}let type_span_96=checkedTypeList(self_.types,principal.row_variables);for type_index_96 in 0..(type_span_96.len as i64) {let row=self_.types.list(type_span_96)[type_index_96];if inList(rows,row) {let err=work.public_rows.append(row);if err!=blot_error::Error.none {return summary,err;}}}var result=summary;if work.public_vars.items.len!=free.len || work.public_rows.items.len!=rows.len {result.shareable=false;}let initial,err=self_.types.resolve(principal.root,0);if err!=blot_error::Error.none {return result,err;}var cursor=initial;while self_.types.node(cursor).tag==blot_check_types::Tag.function {let function=self_.types.node(cursor);let variables,err=self_.types.freeVariables(function.a);if err!=blot_error::Error.none {return result,err;}for variable in variables {let err=work.parameter_free.append(variable);if err!=blot_error::Error.none {return result,err;}}let resolved,err=self_.types.resolve(function.b,0);if err!=blot_error::Error.none {return result,err;}cursor=resolved;}let flags=equation_type_ids.alloc_slice(work.public_vars.items.len);let output,error=summarizeFlags(self_,principal,obligations,cursor,result,work,flags);equation_type_ids.free_slice(flags);return output,error;}
fn summarizeFlags(self_:Engine&,principal:blot_check_types::Scheme,obligations:const blot_check_types::Obligation[:],cursor:u32,summary:SchemeSummary,work:SummaryWork&,flags:u32[:])->SchemeSummary,blot_error::Error {var result=summary;for variable,index in work.public_vars.items {flags[index]=0;if inList(work.parameter_free.items,variable) {flags[index]=1;}}let inputs,err=self_.types.saveList(flags);if err!=blot_error::Error.none {return result,err;}result.public_inputs=inputs;let output_free,err=self_.types.freeVariables(cursor);if err!=blot_error::Error.none {return result,err;}for variable,index in work.public_vars.items {flags[index]=0;if inList(output_free,variable) {flags[index]=1;}}let outputs,err=self_.types.saveList(flags);if err!=blot_error::Error.none {return result,err;}result.public_outputs=outputs;for constraint in obligations[principal.obligations.start..principal.obligations.start+principal.obligations.len] {let err=self_.requirementParts(constraint,work.requirements);if err!=blot_error::Error.none {return result,err;}}for part in work.requirements.items {let variables,err=self_.types.freeVariables(part);if err!=blot_error::Error.none {return result,err;}for variable in variables {let err=work.requirement_variables.append(variable);if err!=blot_error::Error.none {return result,err;}}let rows,err=self_.types.freeRowVariables(part);if err!=blot_error::Error.none {return result,err;}for row in rows {let err=work.requirement_rows.append(row);if err!=blot_error::Error.none {return result,err;}}}for variable,index in work.public_vars.items {flags[index]=0;if inList(work.requirement_variables.items,variable) {flags[index]=1;}}let variables,err=self_.types.saveList(flags);if err!=blot_error::Error.none {return result,err;}result.requirement_variables=variables;let row_flags=equation_type_ids.alloc_slice(work.public_rows.items.len);for row,index in work.public_rows.items {row_flags[index]=0;if inList(work.requirement_rows.items,row) {row_flags[index]=1;}}let rows,error=self_.types.saveList(row_flags);equation_type_ids.free_slice(row_flags);if error!=blot_error::Error.none {return result,error;}result.requirement_rows=rows;let public_vars,err=self_.types.saveList(work.public_vars.items);if err!=blot_error::Error.none {return result,err;}result.public_variables=public_vars;let public_rows,err=self_.types.saveList(work.public_rows.items);if err!=blot_error::Error.none {return result,err;}result.public_rows=public_rows;return result,blot_error::Error.none;}
fn instantiate(self_: Engine&, binding: u32, source: u32) -> u32, blot_error::Error {
    self_.bindings[binding].read = true;
    self_.operation_refs[source] = self_.bindings[binding].operation_ref;
    let principal = self_.bindings[binding].scheme;
    if principal.root == 0 {
        let value, error = self_.types.resolve(self_.bindings[binding].ty, 0);
        if error != blot_error::Error.none { return 0, error; }
        if self_.exact_argument_types { return value, blot_error::Error.none; }
        return self_.types.openCovariant(value);
    }
    self_.counters.instantiations += 1;
    if principal.variables.len == 0 && principal.row_variables.len == 0 &&
       principal.obligations.len == 0 {
        if self_.exact_argument_types { return principal.root, blot_error::Error.none; }
        return self_.types.openCovariant(principal.root);
    }
    if self_.bindings[binding].summary.shareable { return self_.shareScheme(binding, source); }
    let old = equation_type_ids.alloc_slice(principal.variables.len);
    let variables = checkedTypeList(self_.types, principal.variables);
    for index in old.len { old[index] = self_.types.list(variables)[index]; }
    let fresh = equation_type_ids.alloc_slice(old.len);
    let result, error = instantiateVariables(self_, principal, source, old, fresh);
    equation_type_ids.free_slice(fresh);
    equation_type_ids.free_slice(old);
    return result, error;
}
fn instantiateVariables(self_:Engine&,principal:blot_check_types::Scheme,source:u32,old:const u32[:],fresh:u32[:])->u32,blot_error::Error {for &variable in fresh {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}let old_rows=equation_type_ids.alloc_slice(principal.row_variables.len);let type_span_98=checkedTypeList(self_.types,principal.row_variables);for index in 0..(type_span_98.len as i64) {let value=self_.types.list(type_span_98)[index];old_rows[index]=value;}let rows=equation_type_ids.alloc_slice(old_rows.len);let result,err=instantiateRows(self_,principal,source,old,fresh,old_rows,rows);equation_type_ids.free_slice(rows);equation_type_ids.free_slice(old_rows);return result,err;}
fn instantiateRows(self_:Engine&,principal:blot_check_types::Scheme,source:u32,old:const u32[:],fresh:const u32[:],old_rows:const u32[:],rows:u32[:])->u32,blot_error::Error {for &row in rows {let root,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}row=root;}var leaves:dictionary<u32,u32> = dictionary<u32,u32>{};var row_leaves:dictionary<u32,u32> = dictionary<u32,u32>{};let prepared,err=self_.types.prepareSubstitution(old,fresh,old_rows,rows,leaves,row_leaves);if err!=blot_error::Error.none {return 0,err;}var substitution=prepared;let result,error=instantiatePrepared(self_,principal,source,substitution);substitution.deinit();return result,error;}
fn instantiatePrepared(self_:Engine&,principal:blot_check_types::Scheme,source:u32,substitution:blot_check_types::Substitution&)->u32,blot_error::Error {let value,err=self_.types.substitutePrepared(substitution,principal.root);if err!=blot_error::Error.none {return 0,err;}let err=self_.appendInstance(principal.obligations,substitution,source,0);if err!=blot_error::Error.none {return 0,err;}if self_.exact_argument_types {return value,blot_error::Error.none;}return self_.types.openCovariant(value);}
fn appendInstance(self_:Engine&,span:blot_check_types::List,substitution:blot_check_types::Substitution&,source:u32,expansion:u32)->blot_error::Error {for constraint in self_.obligations[span.start..span.start+span.len] {let ty,err=self_.types.substitutePrepared(substitution,constraint.ty);if err!=blot_error::Error.none {return err;}let origin,err=self_.memberUseOrigin(constraint,source);if err!=blot_error::Error.none {return err;}var result:u32=0;if constraint.result!=0 {let root,err=self_.types.substitutePrepared(substitution,constraint.result);if err!=blot_error::Error.none {return err;}result=root;}var other:u32=0;if constraint.other!=0 {let root,err=self_.types.substitutePrepared(substitution,constraint.other);if err!=blot_error::Error.none {return err;}other=root;}var signature:u32=0;if constraint.signature!=0 {let root,err=self_.types.substitutePrepared(substitution,constraint.signature);if err!=blot_error::Error.none {return err;}signature=root;}let value=blot_check_types::Obligation{ty:ty,kind:constraint.kind,source:source,name:constraint.name,result:result,other:other,signature:signature,operator:constraint.operator,identity:constraint.identity,explicit:constraint.explicit,qualification_span:constraint.qualification_span,qualification_unit:constraint.qualification_unit, ..};let err=self_.appendPending(PendingObligation{ value:value, owner:self_.current, origin:origin, method_member:constraint.kind==blot_check_types::ObligationKind.receiver && !constraint.explicit, suspended:constraint.explicit && constraint.kind!=blot_check_types::ObligationKind.type_eq, expansion:expansion, .. });if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn shareScheme(self_:Engine&,binding:u32,source:u32)->u32,blot_error::Error {let callee=self_.bindings[binding];let public_vars=equation_type_ids.alloc_slice(callee.summary.public_variables.len);let type_span_100=checkedTypeList(self_.types,callee.summary.public_variables);for index in 0..(type_span_100.len as i64) {let value=self_.types.list(type_span_100)[index];public_vars[index]=value;}let public_rows=equation_type_ids.alloc_slice(callee.summary.public_rows.len);let type_span_101=checkedTypeList(self_.types,callee.summary.public_rows);for index in 0..(type_span_101.len as i64) {let value=self_.types.list(type_span_101)[index];public_rows[index]=value;}if public_rows.len>0x7fffffffffffffff-public_vars.len {equation_type_ids.free_slice(public_rows);equation_type_ids.free_slice(public_vars);return 0,blot_error::Error.type_limit;}let instance=equation_type_ids.alloc_slice(public_vars.len+public_rows.len);let rows=equation_type_ids.alloc_slice(public_rows.len);let result,err=shareSchemeInstance(self_,binding,source,callee,public_vars,public_rows,instance,rows);equation_type_ids.free_slice(rows);equation_type_ids.free_slice(instance);equation_type_ids.free_slice(public_rows);equation_type_ids.free_slice(public_vars);return result,err;}
fn shareSchemeInstance(self_:Engine&,binding:u32,source:u32,callee:Binding,public_vars:const u32[:],public_rows:const u32[:],instance:u32[:],rows:u32[:])->u32,blot_error::Error {for &variable in instance[..public_vars.len] {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}variable=root;}for &row,index in rows {let root,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}row=root;let carrier,err=self_.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,root);if err!=blot_error::Error.none {return 0,err;}instance[public_vars.len+index]=carrier;}let value,err=self_.types.substituteWithRows(callee.scheme.root,public_vars,instance[..public_vars.len],public_rows,rows);if err!=blot_error::Error.none {return 0,err;}let product,err=self_.types.product(instance);if err!=blot_error::Error.none {return 0,err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ty:product,kind:blot_check_types::ObligationKind.callee_use,source:source,identity:Identity{unit:self_.unit,decl:binding, ..}, ..}, owner:self_.current, .. });if err!=blot_error::Error.none {return 0,err;}self_.counters.shared_uses+=1;if self_.exact_argument_types {return value,blot_error::Error.none;}return self_.types.openCovariant(value);}
fn findId(values:const u32[:],wanted:u32)->blot_support::Option<i64> {for value,index in values {if value==wanted {return blot_support::some(index);}}return blot_support::none<i64>();}
fn instanceArguments(self_:Engine&,root:u32)->u32[:] {
    let product=self_.types.node(root);
    let source=self_.types.list(blot_check_types::List{product.a,product.b,..});
    let arguments=equation_type_ids.alloc_slice(source.len);
    for value,index in source {arguments[index]=value;}
    return arguments;
}
fn expandUse(self_:Engine&,use:PendingObligation,expansion:u32)->blot_error::Error {
    let root,error=self_.types.resolve(use.value.ty,0);
    if error!=blot_error::Error.none {return error;}
    let arguments=self_.instanceArguments(root);
    let result=self_.expandUseArguments(use,expansion,arguments);
    equation_type_ids.free_slice(arguments);
    return result;
}
fn expandUseArguments(self_:Engine&,use:PendingObligation,expansion:u32,arguments:const u32[:])->blot_error::Error {
    let owner=self_.current;
    let scope=self_.qualification_scope;
    self_.current=use.owner;
    self_.qualification_scope=use.scope;
    let error=expandUsePrincipal(self_,use,expansion,arguments);
    self_.current=owner;
    self_.qualification_scope=scope;
    return error;
}
fn expandUsePrincipal(self_:Engine&,use:PendingObligation,expansion:u32,instance:const u32[:])->blot_error::Error {
    let callee=self_.bindings[use.value.identity.decl];
    let principal=callee.scheme;
let public_vars=equation_type_ids.alloc_slice(callee.summary.public_variables.len);let type_span_103=checkedTypeList(self_.types,callee.summary.public_variables);for index in 0..(type_span_103.len as i64) {let value=self_.types.list(type_span_103)[index];public_vars[index]=value;}let public_rows=equation_type_ids.alloc_slice(callee.summary.public_rows.len);let type_span_104=checkedTypeList(self_.types,callee.summary.public_rows);for index in 0..(type_span_104.len as i64) {let value=self_.types.list(type_span_104)[index];public_rows[index]=value;}let old=equation_type_ids.alloc_slice(principal.variables.len);let type_span_105=checkedTypeList(self_.types,principal.variables);for index in 0..(type_span_105.len as i64) {let value=self_.types.list(type_span_105)[index];old[index]=value;}let fresh=equation_type_ids.alloc_slice(old.len);let error=expandUseVariables(self_,use,expansion,principal,instance,public_vars,public_rows,old,fresh);equation_type_ids.free_slice(fresh);equation_type_ids.free_slice(old);equation_type_ids.free_slice(public_rows);equation_type_ids.free_slice(public_vars);return error;}
fn expandUseVariables(self_:Engine&,use:PendingObligation,expansion:u32,principal:blot_check_types::Scheme,instance:const u32[:],public_vars:const u32[:],public_rows:const u32[:],old:const u32[:],fresh:u32[:])->blot_error::Error {for variable,index in old {let at=findId(public_vars,variable);if at.present {fresh[index]=instance[at.value];}else {let root,err=self_.types.fresh();if err!=blot_error::Error.none {return err;}fresh[index]=root;}}let old_rows=equation_type_ids.alloc_slice(principal.row_variables.len);let type_span_106=checkedTypeList(self_.types,principal.row_variables);for index in 0..(type_span_106.len as i64) {let value=self_.types.list(type_span_106)[index];old_rows[index]=value;}let rows=equation_type_ids.alloc_slice(old_rows.len);let result=expandUseRows(self_,use,expansion,principal,instance,public_vars,public_rows,old,fresh,old_rows,rows);equation_type_ids.free_slice(rows);equation_type_ids.free_slice(old_rows);return result;}
fn expandUseRows(self_:Engine&,use:PendingObligation,expansion:u32,principal:blot_check_types::Scheme,instance:const u32[:],public_vars:const u32[:],public_rows:const u32[:],old:const u32[:],fresh:const u32[:],old_rows:const u32[:],rows:u32[:])->blot_error::Error {for variable,index in old_rows {let at=findId(public_rows,variable);if at.present {rows[index]=self_.types.node(instance[public_vars.len+at.value]).c;}else {let row,err=self_.types.freshEffects();if err!=blot_error::Error.none {return err;}rows[index]=row;}}var leaves:dictionary<u32,u32> = dictionary<u32,u32>{};var row_leaves:dictionary<u32,u32> = dictionary<u32,u32>{};let prepared,err=self_.types.prepareSubstitution(old,fresh,old_rows,rows,leaves,row_leaves);if err!=blot_error::Error.none {return err;}var substitution=prepared;let result=self_.appendInstance(principal.obligations,substitution,use.value.source,expansion);substitution.deinit();return result;}

// Stable source names used by purity diagnostic specialization keys.
struct PuritySource {engine:Engine&,texts:blot_support_pooled_buffer::Buffer<const u8[:]> =blot_support_pooled_buffer::Buffer<const u8[:]> {..}}
reusable[] var purity_text_refs:(const u8[:])[>..];
fn deinit(self_:PuritySource&) {for text in self_.texts.items {freeDiagnosticText(text);}self_.texts.deinit(purity_text_refs);}
fn origin(self_:PuritySource&,identity:Identity,kind:blot_check_purity_type_key::Kind)->blot_check_purity_type_key::Identity,blot_error::Error {
 let engine .= self_.engine;let module,err=engine.purity_origins.name(identity.unit,engine.unit);if err!=blot_error::Error.none {return default<blot_check_purity_type_key::Identity>(),err;}let declaration,declaration_error=selectedPurityDeclaration(self_,identity,kind);if declaration_error!=blot_error::Error.none {return default<blot_check_purity_type_key::Identity>(),declaration_error;}
 let owned_module=ownDiagnosticText(module);let module_error=self_.texts.push(owned_module,purity_text_refs);if module_error!=blot_error::Error.none {freeDiagnosticText(owned_module);return default<blot_check_purity_type_key::Identity>(),module_error;}
 let owned_declaration=ownDiagnosticText(declaration);let declaration_error=self_.texts.push(owned_declaration,purity_text_refs);if declaration_error!=blot_error::Error.none {freeDiagnosticText(owned_declaration);return default<blot_check_purity_type_key::Identity>(),declaration_error;}
 return blot_check_purity_type_key::Identity{canonicalDiagnosticText(owned_module),canonicalDiagnosticText(owned_declaration), ..},blot_error::Error.none;
}
struct PurityArgument {pattern:u32,actual:u32}
fn arguments(self_:PuritySource&,identity:Identity,kind:blot_check_purity_type_key::Kind,actual:const u32[:])->u32[>..],blot_error::Error {
 let engine .= self_.engine;var patterns=blot_check_parameter_patterns::List{..};var variables=blot_check_types::List{..};
 match kind {
  nominal => {let index:u32={let scalar_lookup_75 .= engine.catalogs.nominal_identities.get(identity);if !scalar_lookup_75 {return [],blot_error::Error.source_identity_unavailable;}let scalar_value_75:u32=scalar_lookup_75;scalar_value_75};let nominal=engine.nominals[index];patterns=nominal.patterns;variables=nominal.variables;},
  operation => {let index:u32={let scalar_lookup_76 .= engine.catalogs.effect_template_identities.get(identity);if !scalar_lookup_76 {return [],blot_error::Error.source_identity_unavailable;}let scalar_value_76:u32=scalar_lookup_76;scalar_value_76};let template=engine.effect_templates[index];if template.family==0 {return [],blot_error::Error.source_identity_unavailable;}let family=engine.effect_families[template.family];patterns=family.patterns;variables=family.variables;},
 }
 let shapes=engine.parameter_patterns.list(patterns);if shapes.len!=actual.len {return [],blot_error::Error.type_limit;}var binders:u32[>..]=[];binders.append(engine.types.list(variables));var result:u32[>..]=[];result.resize(binders.len,0);var pending:PurityArgument[>..]=[];for shape,index in shapes {pending.push(PurityArgument{shape,actual[index], ..});}
 while pending.len!=0 {let item=pending.pop();let formal=engine.parameter_patterns.node(item.pattern);let resolved,err=engine.types.resolve(item.actual,0);if err!=blot_error::Error.none {return [],err;}if formal.kind==blot_check_parameter_patterns::Kind.binding {var found=false;for variable,index in binders {if variable==formal.a {result[index]=resolved;found=true;break;}}if !found {return [],blot_error::Error.type_limit;}continue;}let shape=engine.types.node(resolved);if formal.kind==blot_check_parameter_patterns::Kind.record {if shape.tag!=blot_check_types::Tag.record || shape.b!=formal.b {return [],blot_error::Error.type_limit;}for index in 0..formal.b {let field=engine.parameter_patterns.field(formal,index);var child:u32=0;for actual_index in 0..shape.b {let actual_field=engine.types.recordField(shape,actual_index);if actual_field.name==field.name {child=actual_field.ty;break;}}if child==0 {return [],blot_error::Error.type_limit;}pending.push(PurityArgument{field.pattern,child, ..});}}else {if formal.b==0 && shape.tag==blot_check_types::Tag.unit {continue;}if shape.tag!=blot_check_types::Tag.product || shape.b!=formal.b {return [],blot_error::Error.type_limit;}for child,index in engine.parameter_patterns.list(blot_check_parameter_patterns::List{formal.a,formal.b, ..}) {pending.push(PurityArgument{child,engine.types.extra.items[shape.a+index], ..});}}}
 for ty in result {if ty==0 {return [],blot_error::Error.type_limit;}}return result,blot_error::Error.none;
}
fn initializerPurity(self_:Engine&,declaration:u32)->blot_error::Error {
 let resolved,err=self_.types.resolveEffects(self_.ambient,0);if err!=blot_error::Error.none {return err;}let labels=checkedRowLabels(self_.types,resolved);if (labels.len as i64)==0 {return self_.types.unifyEffects(resolved,0);}let operation=self_.types.operation(self_.types.effects.list(labels)[0]);var witness=PurityWitness{identity:operation.identity,foreign:self_.types.effects.list(labels)[0]==blot_check_types::foreign_operation,specialized:operation.arguments.len!=0,operation_name:blot_support::none<const u8[:]>(), ..};let scalar_lookup_77 .= self_.catalogs.effect_template_identities.get(operation.identity);if scalar_lookup_77 {let index:u32=scalar_lookup_77;let template=self_.effect_templates[index];if template.family!=0 {let family=self_.effect_families[template.family];witness.family=family.name;witness.member=template.name;witness.compound=!family.callable;}}
 var source=makePuritySource(self_);let initialized,initial_error=blot_check_purity_type_key::initContext(self_.types,source);if initial_error!=blot_error::Error.none {source.deinit();return initial_error;}var context=initialized;let identity,error=context.operation(self_.types.effects.list(labels)[0],65536);if error==blot_error::Error.none {let name=str(identity.module,"::",identity.declaration);witness.operation_name=blot_support::some(ownDiagnosticText(name));}else if error==blot_error::Error.source_identity_unavailable {witness.origin_unavailable=true;}else {context.deinit();context.source.deinit();if error==blot_error::Error.ambiguous_type_key || error==blot_error::Error.specialization_limit {return blot_error::Error.type_limit;}return error;}context.deinit();context.source.deinit();let dtag=self_.tree.node(declaration).tag;let is_field_decl=dtag==blot_parse_ast::tag_field;var point=self_.tree.span(declaration).start;var is_runtime=false;if dtag==blot_parse_ast::tag_entry_kernel_decl {point=self_.tree.entry_kernel_decl(declaration).name_point;}else if dtag==blot_parse_ast::tag_entry_process_decl {point=self_.tree.entry_process_decl(declaration).name_point;}else if !is_field_decl {let p,present=self_.tree.value_name_point(declaration);if !present {if witness.operation_name.present {freeDiagnosticText(witness.operation_name.value);}return blot_error::Error.type_limit;}point=p;is_runtime=self_.tree.value_decl(declaration).runtime;}var code=Code.const_effect;if is_runtime {code=Code.initializer_effect;}self_.diagnostics.push(Diagnostic{code:code,span:blot_parse_ast::Span{point,point, ..},node:declaration,purity:blot_support::some(witness), ..});self_.initializer_rejected=true;return blot_error::Error.none;
}

// Global frames retain only fixed descriptors and reusable runs across inference.
reusable[] var global_loop_runs:LoopFrame[>..];
reusable[] var global_entry_runs:Entry[>..];
fn canonicalLoop(value:LoopFrame)->LoopFrame {return LoopFrame{node:value.node,carries:global_entry_runs.realloc_slice(value.carries,value.carries.len),iterations:equation_type_ids.realloc_slice(value.iterations,value.iterations.len),exits:value.exits};}
struct GlobalContext {
 depth:i64,current:u32,pending_start:i64,owner:u32,qualification_scope:u32,target:u32,
 loops:LoopFrame[:]=default<LoopFrame[:]>(),ambient:u32,annotation_binding:u32,inherited_types:i64,inherited_rows:i64,closed_types:bool,implicit_rows:bool,
 type_env:TypeEnvironment=TypeEnvironment{..},row_env:RowEnvironment=RowEnvironment{..},computation_annotations:u32[:]=default<u32[:]>(),env:Entry[:]=default<Entry[:]>(),
 loops_changed:bool=false,annotations_changed:bool=false,env_changed:bool=false,types_changed:bool=false,rows_changed:bool=false,computations_changed:bool=false,
}
fn canonicalGlobalContext(value:GlobalContext)->GlobalContext {return GlobalContext{depth:value.depth,current:value.current,pending_start:value.pending_start,owner:value.owner,qualification_scope:value.qualification_scope,target:value.target,loops:global_loop_runs.realloc_slice(value.loops,value.loops.len),ambient:value.ambient,annotation_binding:value.annotation_binding,inherited_types:value.inherited_types,inherited_rows:value.inherited_rows,closed_types:value.closed_types,implicit_rows:value.implicit_rows,type_env:canonicalTypeEnvironment(value.type_env),row_env:canonicalRowEnvironment(value.row_env),computation_annotations:equation_type_ids.realloc_slice(value.computation_annotations,value.computation_annotations.len),env:global_entry_runs.realloc_slice(value.env,value.env.len),loops_changed:value.loops_changed,annotations_changed:value.annotations_changed,env_changed:value.env_changed,types_changed:value.types_changed,rows_changed:value.rows_changed,computations_changed:value.computations_changed};}

fn restore(self_:GlobalContext&,engine:Engine&) {
 engine.closed_type_variables=self_.closed_types;engine.implicit_row_parameters=self_.implicit_rows;engine.depth=self_.depth;
 if self_.env_changed {engine.env.clear();engine.env.append(self_.env);engine.current=self_.current;engine.owner=self_.owner;engine.return_target=self_.target;}if self_.env.len!=0 {global_entry_runs.free_slice(self_.env);}
 if self_.annotations_changed {engine.annotation_binding=self_.annotation_binding;engine.inherited_types=self_.inherited_types;engine.inherited_rows=self_.inherited_rows;}
 if self_.computations_changed {engine.computation_annotations.clear();engine.computation_annotations.append(self_.computation_annotations);}if self_.computation_annotations.len!=0 {equation_type_ids.free_slice(self_.computation_annotations);}
 if self_.rows_changed {engine.row_env.deinit();engine.row_env=canonicalRowEnvironment(self_.row_env);}if self_.types_changed {engine.type_env.deinit();engine.type_env=canonicalTypeEnvironment(self_.type_env);}
 if self_.loops_changed {engine.loop_stack.clear();for frame in self_.loops {engine.loop_stack.push(canonicalLoop(frame));}}if self_.loops.len!=0 {global_loop_runs.free_slice(self_.loops);}
 engine.ambient=self_.ambient;engine.qualification_scope=self_.qualification_scope;engine.pending_start=self_.pending_start;
 self_.env=default<blot_check_check::Entry[:]>();self_.loops=default<blot_check_check::LoopFrame[:]>();self_.computation_annotations=default<u32[:]>();self_.types_changed=false;self_.rows_changed=false;self_.loops_changed=false;self_.env_changed=false;self_.computations_changed=false;
}
struct GlobalFrame {binding:u32,id:u32,required:u32,initializer_diagnostics:i64,operations_before:i64=0,context:GlobalContext,plan_index:i64=0,before:blot_support::Option<Global> =blot_support::none<Global>()}
fn traceGlobal(self_:Engine&,kind:GlobalTrace_kind,binding:u32) {let observe .= self_.execution.observe;if !observe {return;}let state .= self_.global_states.get(binding);assert(state);observe.observe(GlobalTrace{kind:kind,binding:binding,counter:self_.counter,index:state.index,low:state.low,active:self_.active.len,current:self_.current,owner:self_.owner,ambient:self_.ambient,pending_start:self_.pending_start,type_nodes:self_.types.nodes.len,type_versions:self_.types.versions.len,row_versions:self_.types.effects.versions.len,type_env:self_.type_env.items.len,row_env:self_.row_env.items.len,computation_annotations:self_.computation_annotations.len, ..});}
recursive fn beginGlobal(self_:Engine&,binding:u32)->GlobalFrame,blot_error::Error {
 let err=self_.inferenceTransition();if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}self_.counter+=1;self_.global_states.insert(binding,Global{state:State.active,index:self_.counter,low:self_.counter,on_stack:true, ..});self_.active.push(binding);
 var context=GlobalContext{ depth:self_.depth, current:self_.current, pending_start:self_.pending_start, owner:self_.owner, qualification_scope:self_.qualification_scope, target:self_.return_target, ambient:self_.ambient, annotation_binding:self_.annotation_binding, inherited_types:self_.inherited_types, inherited_rows:self_.inherited_rows, closed_types:self_.closed_type_variables, implicit_rows:self_.implicit_row_parameters, .. };let frame,error=beginGlobalBody(self_,binding,context);if error!=blot_error::Error.none {context.restore(self_);}return frame,error;
}
recursive fn beginGlobalBody(self_:Engine&,binding:u32,context:GlobalContext&)->GlobalFrame,blot_error::Error {
 if self_.global_driver {self_.depth=0;}self_.pending_start=self_.pending.len;let ambient,err=self_.types.freshEffects();if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}self_.ambient=ambient;
 context.loops=global_loop_runs.alloc_slice(self_.loop_stack.len);for frame,index in self_.loop_stack {context.loops[index]=canonicalLoop(frame);}self_.loop_stack.clear();context.loops_changed=true;
 context.type_env=canonicalTypeEnvironment(self_.type_env);self_.type_env=TypeEnvironment{..};context.types_changed=true;context.row_env=canonicalRowEnvironment(self_.row_env);self_.row_env=RowEnvironment{..};context.rows_changed=true;
 context.computation_annotations=equation_type_ids.alloc_slice(self_.computation_annotations.len);for annotation,index in self_.computation_annotations {context.computation_annotations[index]=annotation;}self_.computation_annotations.clear();context.computations_changed=true;
 self_.annotation_binding=0;self_.inherited_types=0;self_.inherited_rows=0;context.annotations_changed=true;context.env=global_entry_runs.alloc_slice(self_.env.len);for entry,index in self_.env {context.env[index]=entry;}self_.env.clear();self_.current=binding;self_.owner=self_.bindings[binding].declaration;self_.return_target=0;context.env_changed=true;let id=self_.bindings[binding].declaration;self_.qualification_scope=id;
 let scalar_lookup_78 .= self_.implementation_bindings.get(binding);if scalar_lookup_78 {let implementation:u32=scalar_lookup_78;let err=self_.implementationMethodScope(implementation);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}self_.closed_type_variables=true;self_.implicit_row_parameters=false;let initial=self_.diagnostics.len;var impl_body:u32=0;if self_.tree.node(id).tag==blot_parse_ast::tag_field {impl_body=self_.tree.node(id).b;}else {impl_body=self_.tree.value_decl(id).body;}let err=self_.beginImplementationQualification(implementation,id,impl_body);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}self_.body_elaborations+=1;return GlobalFrame{binding:binding,id:id,required:self_.bindings[binding].ty,initializer_diagnostics:initial,operations_before:self_.operation_uses.len,context:canonicalGlobalContext(context), ..},blot_error::Error.none;}
 let dtag=self_.tree.node(id).tag;
 if dtag==blot_parse_ast::tag_entry_kernel_decl {
  let decl=self_.tree.entry_kernel_decl(id);
  var sources:u32[3]=[decl.annotation,0,0];
  if decl.stateless {sources[1]=decl.first;sources[2]=decl.second;}
  for node in sources {let err=self_.collectAnnotationNames(node,0);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}}
  let initial=self_.diagnostics.len;
  if decl.stateless {
   let saved_defer=self_.defer_associated;if self_.implementations.len!=0 {self_.defer_associated=true;}
   let err=self_.beginQualification(id,decl.second,0,decl.first);
   self_.defer_associated=saved_defer;
   if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}
  }
  var required:u32=0;
  if decl.annotation!=0 {
   let value,err=self_.annotation(decl.annotation);
   if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}
   required=value;
   self_.expr_types[decl.annotation]=required;
  }
  self_.body_elaborations+=1;self_.traceGlobal(GlobalTrace_kind.begun,binding);
  return GlobalFrame{binding:binding,id:id,required:required,initializer_diagnostics:initial,operations_before:self_.operation_uses.len,context:canonicalGlobalContext(context), ..},blot_error::Error.none;
 }
 if dtag==blot_parse_ast::tag_entry_process_decl {
  let decl=self_.tree.entry_process_decl(id);
  let err=self_.collectAnnotationNames(decl.annotation,0);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}
  let initial=self_.diagnostics.len;
  var required:u32=0;
  if decl.annotation!=0 {
   let value,err=self_.annotation(decl.annotation);
   if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}
   required=value;
   self_.expr_types[decl.annotation]=required;
  }
  self_.body_elaborations+=1;self_.traceGlobal(GlobalTrace_kind.begun,binding);
  return GlobalFrame{binding:binding,id:id,required:required,initializer_diagnostics:initial,operations_before:self_.operation_uses.len,context:canonicalGlobalContext(context), ..},blot_error::Error.none;
 }
 let declaration=self_.tree.value_decl(id);
 for node in [declaration.annotation,declaration.where_node,declaration.body] {let err=self_.collectAnnotationNames(node,0);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}}let syntax_source_41=declaration.attributes;let syntax_count_41=self_.tree.list(syntax_source_41).len;for syntax_index_41 in 0..syntax_count_41 {let attribute=self_.tree.list(syntax_source_41)[syntax_index_41];let err=self_.collectAnnotationNames(self_.tree.node(attribute).a,0);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}}
 let initial=self_.diagnostics.len;let saved_defer=self_.defer_associated;if self_.implementations.len!=0 {self_.defer_associated=true;}let err=self_.beginQualification(id,declaration.where_node,declaration.annotation,declaration.body);self_.defer_associated=saved_defer;if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}var required:u32=0;
 if declaration.annotation!=0 {let value,err=self_.annotation(declaration.annotation);if err!=blot_error::Error.none {return default<GlobalFrame>(),err;}required=value;let written=self_.tree.node(declaration.annotation);if blot_check_storage_types::isArray(self_.types,self_.types.head(required,0)) || self_.effectFamilyNominal(required).present || written.tag==blot_parse_ast::tag_type_usage || (written.tag==blot_parse_ast::tag_type_function && self_.tree.node(written.a).tag==blot_parse_ast::tag_type_binder) {self_.expr_types[declaration.annotation]=required;}}
 self_.body_elaborations+=1;self_.traceGlobal(GlobalTrace_kind.begun,binding);return GlobalFrame{binding:binding,id:id,required:required,initializer_diagnostics:initial,operations_before:self_.operation_uses.len,context:canonicalGlobalContext(context), ..},blot_error::Error.none;
}
recursive fn finishGlobal(self_:Engine&,frame:const GlobalFrame&,value:u32)->blot_error::Error {
 let binding=frame.binding;let id=frame.id;let required=frame.required;let dtag=self_.tree.node(id).tag;var has_attrs=false;var decl_annotation:u32=0;if dtag==blot_parse_ast::tag_value_decl {let declaration=self_.tree.value_decl(id);has_attrs=declaration.attributes.len!=0;decl_annotation=declaration.annotation;}else if dtag==blot_parse_ast::tag_entry_kernel_decl {let declaration=self_.tree.entry_kernel_decl(id);has_attrs=declaration.attributes.len!=0;decl_annotation=declaration.annotation;}else if dtag==blot_parse_ast::tag_entry_process_decl {let declaration=self_.tree.entry_process_decl(id);has_attrs=declaration.attributes.len!=0;decl_annotation=declaration.annotation;}if required!=0 {var origin=id;if has_attrs {origin=decl_annotation;}let err=self_.constrainRaw(self_.bindings[binding].ty,required,origin);if err!=blot_error::Error.none {return err;}}var origin=id;if has_attrs && required!=0 {origin=decl_annotation;}let err=self_.constrain(self_.bindings[binding].ty,value,origin);if err!=blot_error::Error.none {return err;}
 if self_.diagnostics.len==frame.initializer_diagnostics {let err=self_.initializerPurity(id);if err==blot_error::Error.infinite_effect {let err=self_.diagnostic(Code.infinite_effect,id);if err!=blot_error::Error.none {return err;}}else if err!=blot_error::Error.none {return err;}}
 let scalar_lookup_79 .= self_.implementation_bindings.get(binding);if scalar_lookup_79 {let implementation:u32=scalar_lookup_79;let err=self_.validateImplementationBinders(implementation,id);if err!=blot_error::Error.none {return err;}}let state .= self_.global_states.get(binding);assert(state);state.state=State.complete;let now=state;if now.low==now.index {let err=self_.finishComponent(binding);if err!=blot_error::Error.none {return err;}}self_.traceGlobal(GlobalTrace_kind.finished,binding);return blot_error::Error.none;
}
fn inferenceTransition(self_:Engine&)->blot_error::Error {if self_.inference_transitions+self_.types.projection_steps>=self_.inference_limit {self_.exhaustBudget();return blot_error::Error.type_limit;}self_.inference_transitions+=1;self_.types.projection_limit=min<i64>(self_.types.projection_limit,self_.inference_limit-self_.inference_transitions);return blot_error::Error.none;}
fn exhaustBudget(self_:Engine&) {let record .= self_.budget_exhaustion;if !record || record.exhausted {return;}var binding=self_.root_global;if self_.dependency_owner.present {binding=self_.dependency_owner.value;}else if self_.active.len!=0 {binding=self_.active[self_.active.len-1];}else if self_.current!=0 {binding=self_.current;}var name:u32=0;var node:u32=0;var span=blot_parse_ast::Span{0,0, ..};if binding<self_.bindings.len {name=self_.bindings[binding].name;node=self_.bindings[binding].declaration;}if node!=0 {span=self_.tree.span(node);}record=BudgetExhaustion{exhausted:true,name:name,node:node,span:span, ..};}
fn componentLow(self_:Engine&,start:i64,binding:u32)->u32 {let state .= self_.global_states.get(binding);assert(state);var low=state.low;for member in self_.active[start..] {let member_state .= self_.global_states.get(member);assert(member_state);low=min(low,member_state.low);}state.low=low;return low;}
fn resetQualifications(self_:Engine&,group:const u32[:]) {for &boundary in self_.qualifications {if inList(group,boundary.owner) {boundary.checked=false;}}}
fn pendingState(self_:const Engine&)->i64 {var count=0;for pending in self_.pending {if !pending.solved && !pending.declared && !pending.covered && !pending.local_scheme {count+=1;}}return count;}
reusable[] var component_schemes:blot_check_types::Scheme[>..];
reusable[] var component_summaries:SchemeSummary[>..];
reusable[] var component_diagnostics:Diagnostic[>..];
struct ComponentStage {schemes:blot_check_types::Scheme[:]=default<blot_check_types::Scheme[:]>(),summaries:SchemeSummary[:]=default<SchemeSummary[:]>(),obligations:PredicateBuffer=PredicateBuffer{..},suspensions:Suspensions=Suspensions{..},diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),diagnostics_published:bool=false}
fn deinit(self_:ComponentStage&) {if self_.schemes.len!=0 {component_schemes.free_slice(self_.schemes);}if self_.summaries.len!=0 {component_summaries.free_slice(self_.summaries);}self_.obligations.deinit(equation_values);self_.suspensions.deinit(suspension_runs);if self_.diagnostics.len!=0 {if !self_.diagnostics_published {deinitDiagnosticPayloads(self_.diagnostics);}component_diagnostics.free_slice(self_.diagnostics);}self_.schemes=default<blot_check_types::Scheme[:]>();self_.summaries=default<blot_check_check::SchemeSummary[:]>();self_.diagnostics=default<blot_check_check::Diagnostic[:]>();}
enum ComponentProgress {done,retry}
recursive fn finishComponent(self_:Engine&,binding:u32)->blot_error::Error {var group=IdBuffer{..};let saved=self_.finishing_group;let err=finishComponentWork(self_,binding,group);self_.finishing_group=equation_type_ids.realloc_slice(saved,saved.len);group.deinit(equation_type_ids);return err;}
recursive fn finishComponentWork(self_:Engine&,binding:u32,group:IdBuffer&)->blot_error::Error {
 var start:i64=0;while start<self_.active.len && self_.active[start]!=binding {start+=1;}assert(start<self_.active.len);
 loop {let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}let state .= self_.global_states.get(binding);assert(state);let state_index=state.index;if self_.componentLow(start,binding)!=state_index {return blot_error::Error.none;}group.clear();var cursor=self_.active.len;while cursor>start {cursor-=1;let err=group.append(self_.active[cursor]);if err!=blot_error::Error.none {return err;}}self_.finishing_group=equation_type_ids.realloc_slice(group.items,group.items.len);var recursive_=group.items.len>1;for use in self_.qualification_uses {if inList(group.items,use.owner) && inList(group.items,use.target) {recursive_=true;break;}}
 if recursive_ {let err=self_.expandInformedUses(group.items,true);if err!=blot_error::Error.none {return err;}}let err=self_.expandQualificationUses(group.items);if err!=blot_error::Error.none {return err;}let err=self_.prepareQualifications(group.items);if err!=blot_error::Error.none {return err;}let err=self_.solveFields();if err!=blot_error::Error.none {return err;}if self_.selected_globals.len!=0 || self_.componentLow(start,binding)!=state_index {return blot_error::Error.none;}if self_.active.len!=start+group.items.len {continue;}
 var stage=ComponentStage{schemes:component_schemes.alloc_slice(group.items.len),summaries:component_summaries.alloc_slice(group.items.len), ..};let progress,error=finishComponentStage(self_,binding,start,state_index,group.items,recursive_,stage);stage.deinit();if error!=blot_error::Error.none {return error;}if progress==ComponentProgress.done {return blot_error::Error.none;}}
}
recursive fn finishComponentStage(self_:Engine&,binding:u32,start:i64,state_index:u32,group:const u32[:],recursive_:bool,stage:ComponentStage&)->ComponentProgress,blot_error::Error {
 let before_pending=self_.pending.len;for member,index in group {let principal,err=self_.schemeInto(self_.bindings[member].ty,[],group,true,member,self_.bindings[member].declaration,stage.obligations,stage.suspensions);if err!=blot_error::Error.none {return ComponentProgress.done,err;}stage.schemes[index]=principal;let summary,err=self_.summarizeFrom(principal,stage.obligations.items);if err!=blot_error::Error.none {return ComponentProgress.done,err;}stage.summaries[index]=summary;if recursive_ {stage.summaries[index].shareable=false;}}
 if self_.selected_globals.len!=0 || self_.componentLow(start,binding)!=state_index {return ComponentProgress.done,blot_error::Error.none;}if self_.active.len!=start+group.len || self_.pending.len!=before_pending {return ComponentProgress.retry,blot_error::Error.none;}
 let staged_cursor=self_.types.cursor();let staged_pending=self_.pendingState();let staged_uses=self_.qualification_uses.len;let diagnostic_start=self_.diagnostics.len;var qualification:i64=0;while qualification<self_.qualifications.len {if inList(group,self_.qualifications[qualification].owner) {let err=self_.checkQualification(qualification);if err!=blot_error::Error.none {return ComponentProgress.done,err;}}qualification+=1;}
 let diagnostic_count=self_.diagnostics.len-diagnostic_start;stage.diagnostics=component_diagnostics.alloc_slice(diagnostic_count);for index in 0..diagnostic_count {let diagnostic=self_.diagnostics[diagnostic_start+index];stage.diagnostics[index]=canonicalDiagnostic(diagnostic);}self_.diagnostics.resize(diagnostic_start);
 let err=self_.solveFields();if err!=blot_error::Error.none {return ComponentProgress.done,err;}if self_.selected_globals.len!=0 || self_.componentLow(start,binding)!=state_index {self_.resetQualifications(group);return ComponentProgress.done,blot_error::Error.none;}
 if self_.active.len!=start+group.len || self_.pending.len!=before_pending || self_.types.cursor()!=staged_cursor || self_.pendingState()!=staged_pending || self_.qualification_uses.len!=staged_uses {self_.resetQualifications(group);return ComponentProgress.retry,blot_error::Error.none;}
 if self_.obligations.len>0xffffffff-stage.obligations.items.len {return ComponentProgress.done,blot_error::Error.type_limit;}let obligation_start=self_.obligations.len as u32;self_.obligations.append(stage.obligations.items);for pending in stage.suspensions.items {self_.pending[pending].suspended=true;}for &principal in stage.schemes {principal.obligations.start+=obligation_start;}
 // No source diagnostics can occur between the stability check and this insertion.
 let old_length=self_.diagnostics.len;let diagnostic_count=stage.diagnostics.len;self_.diagnostics.resize(old_length+diagnostic_count,default<Diagnostic>());var cursor=old_length;while cursor>diagnostic_start {cursor-=1;self_.diagnostics[cursor+diagnostic_count]=canonicalDiagnostic(self_.diagnostics[cursor]);}for index in 0..diagnostic_count {let diagnostic=stage.diagnostics[index];self_.diagnostics[diagnostic_start+index]=canonicalDiagnostic(diagnostic);}stage.diagnostics_published=true;
 for member,index in group {self_.bindings[member].scheme=stage.schemes[index];self_.bindings[member].summary=stage.summaries[index];let state .= self_.global_states.get(member);assert(state);state.on_stack=false;}self_.active.resize(start);return ComponentProgress.done,blot_error::Error.none;
}
recursive fn inferGlobal(self_:Engine&,binding:u32)->blot_error::Error {let state .= self_.global_states.get(binding);assert(state);if state.state!=State.pending {return self_.flushGlobalDiagnostics(binding);}if self_.execution.alias_globals && self_.aliasEntryContext() {let stats .= self_.execution.stats;if stats {stats.attempts+=1;}var plan=AliasPlan{..};let err=self_.aliasPlan(binding,plan);if err!=blot_error::Error.none {plan.deinit();return err;}if plan.items.len!=0 {if stats {stats.admitted+=1;}let result=self_.inferAliasPlan(plan.items);plan.deinit();return result;}plan.deinit();if stats {stats.declined+=1;}}if self_.execution.schedule_globals && !self_.global_driver {return self_.inferScheduledGlobal(binding);}let initial,err=self_.beginGlobal(binding);if err!=blot_error::Error.none {return err;}var frame=initial;let value,error=self_.inferDeclarationNode(frame.id);var result=error;if result==blot_error::Error.none {result=self_.finishGlobal(frame,value);}frame.context.restore(self_);return result;}
recursive fn inferTraitConstRecord(self_:Engine&,body_id:u32)->u32,blot_error::Error {
    var fields=FieldBuffer{..};
    let child_count:i64=self_.tree.children(body_id).len;
    for index in 0..child_count {
        let child:u32=self_.tree.children(body_id)[index];
        let field=self_.tree.node(child);
        var raw:u32=0;
        let mb=self_.resolved[child];
        if mb!=0 && self_.implementation_bindings.contains(mb) {
            let root,err=self_.globalReference(mb,child);
            if err!=blot_error::Error.none {fields.deinit(equation_fields);return 0,err;}
            raw=root;
        }else if field.b==0 {
            let root,err=self_.shorthand(child,field.a);
            if err!=blot_error::Error.none {fields.deinit(equation_fields);return 0,err;}
            raw=root;
        }else {
            let root,err=self_.expression(field.b);
            if err!=blot_error::Error.none {fields.deinit(equation_fields);return 0,err;}
            raw=root;
        }
        self_.expr_types[child]=raw;
        self_.projections[child]=index as u32;
        let err=fields.append(blot_check_types::Field{name:field.a,ty:raw, ..});
        if err!=blot_error::Error.none {fields.deinit(equation_fields);return 0,err;}
    }
    let rec,err=self_.types.record(fields.items);
    fields.deinit(equation_fields);
    if err!=blot_error::Error.none {return 0,err;}
    self_.expr_types[body_id]=rec;
    return rec,blot_error::Error.none;
}
struct CallableTarget {binding:u32=0,ty:u32=0}
fn lookupBuiltinNominal(self_:const Engine&,name:const u8[:],expected_vars:i64)->blot_support::Option<u32> {
 let sym,ok=self_.pool.lookup(name);
 if ok {
  let found .= self_.catalogs.nominal_names.get(Qualified{0,sym, ..});
  if found {
   let idx:u32=found;
   if self_.nominals[idx].variables.len==expected_vars {return blot_support::some(idx);}
  }
 }
 for idx in 1..self_.nominals.len {
  if self_.nominals[idx].variables.len==expected_vars && self_.pool.get(self_.nominals[idx].name)==name {
   return blot_support::some(idx as u32);
  }
 }
 return blot_support::none<u32>();
}
fn extractNominalTriple(self_:Engine&,ann_node:blot_check_types::Node)->bool,u32,u32,u32,blot_error::Error {
 let nargs=self_.types.nominalArguments(ann_node);
 if nargs.len==3 {return true,nargs[0],nargs[1],nargs[2],blot_error::Error.none;}
 if nargs.len==1 {
  let inner,ierr=self_.types.resolve(nargs[0],0);if ierr!=blot_error::Error.none {return false,0,0,0,ierr;}
  let pnode=self_.types.node(inner);
  if pnode.tag==blot_check_types::Tag.product && pnode.b==3 {
   let elems=self_.types.list(blot_check_types::List{pnode.a,pnode.b, ..});
   return true,elems[0],elems[1],elems[2],blot_error::Error.none;
  }
 }
 return false,0,0,0,blot_error::Error.none;
}
fn makeNominalTriple(self_:Engine&,nom_idx:u32,t0:u32,t1:u32,t2:u32)->u32,blot_error::Error {
 let ident=self_.nominals[nom_idx].identity;
 if self_.nominals[nom_idx].parameters.len==1 {
  let pack,perr=self_.types.product([t0,t1,t2]);if perr!=blot_error::Error.none {return 0,perr;}
  return self_.types.nominal(ident,[pack]);
 }
 return self_.types.nominal(ident,[t0,t1,t2]);
}
recursive fn resolveCallablePath(self_:Engine&,path_id:u32)->blot_support::Option<CallableTarget>,blot_error::Error {
 let node=self_.tree.node(path_id);
 if node.tag!=blot_parse_ast::tag_name {let err=self_.diagnostic(Code.kernel_callable,path_id);return blot_support::none<CallableTarget>(),err;}
 let found,err=self_.catalogBinding(node.a);
 if err!=blot_error::Error.none {return blot_support::none<CallableTarget>(),err;}
 if !found.present {let derr=self_.diagnostic(Code.unknown_name,path_id);return blot_support::none<CallableTarget>(),derr;}
 let binding=found.value;
 if !self_.bindings[binding].named_function {let derr=self_.diagnostic(Code.kernel_callable,path_id);return blot_support::none<CallableTarget>(),derr;}
 let ty,gerr=self_.globalReference(binding,path_id);
 if gerr!=blot_error::Error.none {return blot_support::none<CallableTarget>(),gerr;}
 self_.expr_types[path_id]=ty;
 return blot_support::some(CallableTarget{binding:binding,ty:ty, ..}),blot_error::Error.none;
}
fn requirePureEffectRow(self_:Engine&,row:u32,source:u32,code:Code)->blot_error::Error {
 let resolved,rerr=self_.types.resolveEffects(row,0);if rerr!=blot_error::Error.none {return rerr;}
 let uerr=self_.types.unifyEffects(resolved,0);
 if uerr==blot_error::Error.effect_mismatch || uerr==blot_error::Error.infinite_effect {return self_.diagnostic(code,source);}
 return uerr;
}
recursive fn inferEntryKernelDecl(self_:Engine&,id:u32)->u32,blot_error::Error {
 let decl=self_.tree.entry_kernel_decl(id);
 let kernel_nom=self_.lookupBuiltinNominal("Kernel",3);
 if !kernel_nom.present {return self_.diagnosticFresh(Code.kernel_type,id);}
 let kernel_ident=self_.nominals[kernel_nom.value].identity;
 if decl.stateless {
  if decl.first==0 || self_.tree.node(decl.first).tag!=blot_parse_ast::tag_lambda {return self_.diagnosticFresh(Code.kernel_callable,id);}
  let lnode=self_.tree.node(decl.first);
  if self_.tree.parameter(lnode.a).own {let err=self_.diagnostic(Code.kernel_callable,lnode.a);if err!=blot_error::Error.none {return 0,err;}}
  var inner_body=lnode.b;
  while inner_body!=0 && self_.tree.node(inner_body).tag==blot_parse_ast::tag_group {inner_body=self_.tree.node(inner_body).a;}
  if inner_body!=0 && self_.tree.node(inner_body).tag==blot_parse_ast::tag_lambda {let err=self_.diagnostic(Code.kernel_callable,decl.first);if err!=blot_error::Error.none {return 0,err;}}
  let fn_ty,ferr=self_.expression(decl.first);if ferr!=blot_error::Error.none {return 0,ferr;}
  let serr=self_.solveFields();if serr!=blot_error::Error.none {return 0,serr;}
  let resolved_fn,rerr=self_.types.resolve(fn_ty,0);if rerr!=blot_error::Error.none {return 0,rerr;}
  let arrow=self_.types.node(resolved_fn);
  if arrow.tag!=blot_check_types::Tag.function {return self_.diagnosticFresh(Code.kernel_callable,decl.first);}
  let perr=self_.requirePureEffectRow(arrow.c,decl.first,Code.kernel_effectful);if perr!=blot_error::Error.none {return 0,perr;}
  let fn_binding=self_.resolved[decl.first];
  if fn_binding!=0 {
   let cerr=self_.constrain(self_.bindings[fn_binding].ty,resolved_fn,decl.first);if cerr!=blot_error::Error.none {return 0,cerr;}
   self_.bindings[fn_binding].scheme=blot_check_types::Scheme{root:resolved_fn, ..};
  }
  return self_.makeNominalTriple(kernel_nom.value,blot_check_types::unit,arrow.a,arrow.b);
 }
 if decl.annotation==0 {return self_.diagnosticFresh(Code.kernel_type,id);}
 let ann_ty=self_.expr_types[decl.annotation];
 let resolved_ann,aerr=self_.types.resolve(ann_ty,0);if aerr!=blot_error::Error.none {return 0,aerr;}
 let ann_node=self_.types.node(resolved_ann);
 let ok_triple,ctx_ty,item_ty,out_ty,terr=self_.extractNominalTriple(ann_node);if terr!=blot_error::Error.none {return 0,terr;}
 if ann_node.tag!=blot_check_types::Tag.nominal || ann_node.a!=kernel_ident.unit || ann_node.b!=kernel_ident.decl || !ok_triple {
  let err=self_.diagnostic(Code.kernel_type,decl.annotation);return ann_ty,err;
 }
 let prepared_ctx,pcerr=self_.types.fresh();if pcerr!=blot_error::Error.none {return 0,pcerr;}
 let prep_opt,perr=self_.resolveCallablePath(decl.first);if perr!=blot_error::Error.none {return 0,perr;}
 if prep_opt.present {
  let prep=prep_opt.value;
  if (self_.bindings[prep.binding].capability_parameters.own & 1)!=0 || !self_.bindings[prep.binding].capability_parameters.owned_results {let derr=self_.diagnostic(Code.kernel_callable,decl.first);if derr!=blot_error::Error.none {return 0,derr;}}
  let prep_eff,eerr=self_.types.freshEffects();if eerr!=blot_error::Error.none {return 0,eerr;}
  let expected_prep,fperr=self_.types.functionWithEffects(ctx_ty,prepared_ctx,prep_eff);if fperr!=blot_error::Error.none {return 0,fperr;}
  let cerr=self_.constrain(prep.ty,expected_prep,decl.first);if cerr!=blot_error::Error.none {return 0,cerr;}
  let peerr=self_.requirePureEffectRow(prep_eff,decl.first,Code.kernel_effectful);if peerr!=blot_error::Error.none {return 0,peerr;}
 }
 let run_opt,rerr=self_.resolveCallablePath(decl.second);if rerr!=blot_error::Error.none {return 0,rerr;}
 if run_opt.present {
  let run=run_opt.value;
  if (self_.bindings[run.binding].capability_parameters.own & 3)!=0 || !self_.bindings[run.binding].capability_parameters.owned_results {let derr=self_.diagnostic(Code.kernel_callable,decl.second);if derr!=blot_error::Error.none {return 0,derr;}}
  let run_eff1,e1err=self_.types.freshEffects();if e1err!=blot_error::Error.none {return 0,e1err;}
  let run_eff2,e2err=self_.types.freshEffects();if e2err!=blot_error::Error.none {return 0,e2err;}
  let inner_arrow,ierr=self_.types.functionWithEffects(item_ty,out_ty,run_eff2);if ierr!=blot_error::Error.none {return 0,ierr;}
  let expected_run,frerr=self_.types.functionWithEffects(prepared_ctx,inner_arrow,run_eff1);if frerr!=blot_error::Error.none {return 0,frerr;}
  let cerr=self_.constrain(run.ty,expected_run,decl.second);if cerr!=blot_error::Error.none {return 0,cerr;}
  let re1=self_.requirePureEffectRow(run_eff1,decl.second,Code.kernel_effectful);if re1!=blot_error::Error.none {return 0,re1;}
  let re2=self_.requirePureEffectRow(run_eff2,decl.second,Code.kernel_effectful);if re2!=blot_error::Error.none {return 0,re2;}
 }
 return ann_ty,blot_error::Error.none;
}
recursive fn inferEntryProcessDecl(self_:Engine&,id:u32)->u32,blot_error::Error {
 let decl=self_.tree.entry_process_decl(id);
 let proc_nom=self_.lookupBuiltinNominal("Process",3);
 if !proc_nom.present {return self_.diagnosticFresh(Code.kernel_type,id);}
 let proc_ident=self_.nominals[proc_nom.value].identity;
 if decl.annotation==0 {return self_.diagnosticFresh(Code.kernel_type,id);}
 let ann_ty=self_.expr_types[decl.annotation];
 let resolved_ann,aerr=self_.types.resolve(ann_ty,0);if aerr!=blot_error::Error.none {return 0,aerr;}
 let ann_node=self_.types.node(resolved_ann);
 let ok_triple,cfg_ty,cmd_ty,reply_ty,terr=self_.extractNominalTriple(ann_node);if terr!=blot_error::Error.none {return 0,terr;}
 if ann_node.tag!=blot_check_types::Tag.nominal || ann_node.a!=proc_ident.unit || ann_node.b!=proc_ident.decl || !ok_triple {
  let err=self_.diagnostic(Code.kernel_type,decl.annotation);return ann_ty,err;
 }
 let state_ty,sterr=self_.types.fresh();if sterr!=blot_error::Error.none {return 0,sterr;}
 let init_opt,ierr=self_.resolveCallablePath(decl.init);if ierr!=blot_error::Error.none {return 0,ierr;}
 if init_opt.present {
  let init_fn=init_opt.value;
  if (self_.bindings[init_fn.binding].capability_parameters.own & 1)!=0 || !self_.bindings[init_fn.binding].capability_parameters.owned_results {let derr=self_.diagnostic(Code.kernel_callable,decl.init);if derr!=blot_error::Error.none {return 0,derr;}}
  let init_eff,eerr=self_.types.freshEffects();if eerr!=blot_error::Error.none {return 0,eerr;}
  let expected_init,fierr=self_.types.functionWithEffects(cfg_ty,state_ty,init_eff);if fierr!=blot_error::Error.none {return 0,fierr;}
  let cerr=self_.constrain(init_fn.ty,expected_init,decl.init);if cerr!=blot_error::Error.none {return 0,cerr;}
  let peerr=self_.requirePureEffectRow(init_eff,decl.init,Code.kernel_effectful);if peerr!=blot_error::Error.none {return 0,peerr;}
 }
 let step_opt,serr=self_.resolveCallablePath(decl.step);if serr!=blot_error::Error.none {return 0,serr;}
 if step_opt.present {
  let step_fn=step_opt.value;
  let own_mask=self_.bindings[step_fn.binding].capability_parameters.own;
  if (own_mask & 1)==0 || (own_mask & 2)!=0 || !self_.bindings[step_fn.binding].capability_parameters.owned_results {let derr=self_.diagnostic(Code.kernel_callable,decl.step);if derr!=blot_error::Error.none {return 0,derr;}}
  let step_eff1,e1err=self_.types.freshEffects();if e1err!=blot_error::Error.none {return 0,e1err;}
  let step_eff2,e2err=self_.types.freshEffects();if e2err!=blot_error::Error.none {return 0,e2err;}
  let own_state,werr=self_.types.usage(state_ty,blot_parse_ast::usagekind_own,0);if werr!=blot_error::Error.none {return 0,werr;}
  let out_pair,perr=self_.types.product([state_ty,reply_ty]);if perr!=blot_error::Error.none {return 0,perr;}
  let inner_arrow,iaerr=self_.types.functionWithEffects(cmd_ty,out_pair,step_eff2);if iaerr!=blot_error::Error.none {return 0,iaerr;}
  let expected_step,fserr=self_.types.functionWithEffects(own_state,inner_arrow,step_eff1);if fserr!=blot_error::Error.none {return 0,fserr;}
  let cerr=self_.constrain(step_fn.ty,expected_step,decl.step);if cerr!=blot_error::Error.none {return 0,cerr;}
  let se1=self_.requirePureEffectRow(step_eff1,decl.step,Code.kernel_effectful);if se1!=blot_error::Error.none {return 0,se1;}
  let se2=self_.requirePureEffectRow(step_eff2,decl.step,Code.kernel_effectful);if se2!=blot_error::Error.none {return 0,se2;}
 }
 return ann_ty,blot_error::Error.none;
}
recursive fn inferDeclarationNode(self_:Engine&,id:u32)->u32,blot_error::Error {let dtag=self_.tree.node(id).tag;if dtag==blot_parse_ast::tag_entry_kernel_decl {return self_.inferEntryKernelDecl(id);}if dtag==blot_parse_ast::tag_entry_process_decl {return self_.inferEntryProcessDecl(id);}if dtag==blot_parse_ast::tag_field {let field=self_.tree.node(id);if field.b!=0 {return self_.expression(field.b);}let target,err=self_.globalBinding(field.a);if err!=blot_error::Error.none {return 0,err;}if !target.present {return self_.diagnosticFresh(Code.unknown_name,id);}let saved=self_.resolved[id];let ty,rerr=self_.globalReference(target.value,id);self_.resolved[id]=saved;return ty,rerr;}let decl=self_.tree.value_decl(id);var is_trait_const=false;{let il .= self_.catalogs.implementation_names.get(Qualified{0,decl.name, ..});if il && self_.implementations[il].declaration==id {is_trait_const=true;}}if is_trait_const {var body_id=decl.body;while body_id!=0 && self_.tree.node(body_id).tag==blot_parse_ast::tag_group {body_id=self_.tree.node(body_id).a;}if body_id!=0 && self_.tree.node(body_id).tag==blot_parse_ast::tag_record {return self_.inferTraitConstRecord(body_id);}}return self_.inferDeclarationBody(decl);}
recursive fn inferDeclarationBody(self_:Engine&,declaration:blot_parse_ast::ValueDecl)->u32,blot_error::Error {return self_.taggedExpression(checkedAstList(self_.tree,declaration.attributes),declaration.body,0);}
fn firstByte(text:const u8[:],byte:u8)->i64 {for value,index in text {if value==byte {return index;}}return -1;}
fn discoveryShadowed(self_:const Engine&,locals:const u32[:],name:u32)->bool {if inList(locals,name) {return true;}let text=self_.pool.get(name);let dot=firstByte(text,'.');if dot>=0 {let root,present=self_.pool.lookup(text[..dot]);if present {return inList(locals,root);}}return false;}
struct DiscoveryResolver {engine:Engine&}
fn resolve(self_:DiscoveryResolver&,kind:blot_reuse_global_references::Kind,name:u32,member:u32,locals:const u32[:])->blot_support::Option<u32>,blot_error::Error {return self_.engine.discoveryReference(kind,name,member,locals);}
fn discoveryReference(self_:Engine&,kind:blot_reuse_global_references::Kind,name:u32,member:u32,locals:const u32[:])->blot_support::Option<u32>,blot_error::Error {var selected=blot_support::none<u32>();match kind {
 name => {if !self_.discoveryShadowed(locals,name) {let scalar_lookup_80 .= self_.catalogs.globals.get(name);if scalar_lookup_80 {let binding:u32=scalar_lookup_80;selected=blot_support::some(binding);}if !selected.present {let text=self_.pool.get(name);let dot=firstByte(text,'.');if dot>=0 {let root,present=self_.pool.lookup(text[..dot]);if present {let scalar_lookup_81 .= self_.catalogs.globals.get(root);if scalar_lookup_81 {let binding:u32=scalar_lookup_81;selected=blot_support::some(binding);}}}}}},
 qualified => {if !self_.discoveryShadowed(locals,name) {let scalar_lookup_82 .= self_.catalogs.qualified.get(Qualified{namespace_:name,member:member, ..});if scalar_lookup_82 {let binding:u32=scalar_lookup_82;selected=blot_support::some(binding);}}},
 operator => {},
 }if !selected.present || self_.bindings[selected.value].kind!=blot_reuse_principal_interface::Kind.global {return blot_support::none<u32>(),blot_error::Error.none;}return selected,blot_error::Error.none;}
fn flushGlobalDiagnostics(self_:Engine&,binding:u32)->blot_error::Error {
    var start:i64=0;var count:i64=0;
    {let stored .= self_.staged_global_diagnostics.get(binding);if !stored {return blot_error::Error.none;}count=stored.len;
     if count!=0 {let values:Diagnostic[:]=stored;let canonical=component_diagnostics.realloc_slice(values,count);start=component_diagnostics.index_of(canonical[0]);assert(blot_support::same_slice_identity(canonical,values));}}
    for index in 0..count {let diagnostic=component_diagnostics[start+index];self_.diagnostics.push(canonicalDiagnostic(diagnostic));}
    self_.staged_global_diagnostics.remove(binding);if count!=0 {component_diagnostics.free_slice(component_diagnostics[start..start+count]);}return blot_error::Error.none;
}
struct ScheduledGlobal {frame:GlobalFrame,references:const blot_reuse_global_references::Reference[:],next:i64=0,value:blot_support::Option<u32> =blot_support::none<u32>(),finished:bool=false,before:blot_support::Option<Global> =blot_support::none<Global>(),owner:u32=0,diagnostic_start:i64,diagnostic_at:blot_support::Option<i64> =blot_support::none<i64>()}
reusable[] var scheduled_frame_runs:ScheduledGlobal[>..];
type ScheduledFrames=blot_support_pooled_buffer::Buffer<ScheduledGlobal>;
recursive fn scheduledFrame(self_:Engine&,binding:u32,before:blot_support::Option<Global>,owner:u32,diagnostic_at:blot_support::Option<i64>)->ScheduledGlobal,blot_error::Error {var resolver=makeDiscoveryResolver(self_);let references,error=blot_reuse_global_references::discover(self_.tree,self_.bindings[binding].declaration,resolver,self_.self_name,self_.inference_transitions,self_.inference_limit);if error!=blot_error::Error.none {if error==blot_error::Error.type_limit && self_.inference_transitions>=self_.inference_limit {self_.exhaustBudget();}return default<ScheduledGlobal>(),error;}let diagnostic_start=self_.diagnostics.len;let frame,err=self_.beginGlobal(binding);if err!=blot_error::Error.none {blot_reuse_global_references::release(references);return default<ScheduledGlobal>(),err;}return ScheduledGlobal{frame:frame,references:references,before:before,owner:owner,diagnostic_start:diagnostic_start,diagnostic_at:diagnostic_at, ..},blot_error::Error.none;}
recursive fn inferScheduledGlobal(self_:Engine&,initial:u32)->blot_error::Error {assert(!self_.global_driver);self_.global_driver=true;var frames=ScheduledFrames{..};let error=inferScheduledWork(self_,initial,frames);while frames.items.len!=0 {var unfinished=frames.items[frames.items.len-1];frames.resize(frames.items.len-1);blot_reuse_global_references::release(unfinished.references);unfinished.frame.context.restore(self_);}frames.deinit(scheduled_frame_runs);self_.global_driver=false;return error;}
recursive fn pushScheduled(self_:Engine&,frames:ScheduledFrames&,binding:u32,before:blot_support::Option<Global>,owner:u32,at:blot_support::Option<i64>)->blot_error::Error {let err=frames.ensure(frames.items.len+1,scheduled_frame_runs);if err!=blot_error::Error.none {return err;}let frame,error=self_.scheduledFrame(binding,before,owner,at);if error!=blot_error::Error.none {return error;}return frames.push(frame,scheduled_frame_runs);}
recursive fn inferScheduledWork(self_:Engine&,initial:u32,frames:ScheduledFrames&)->blot_error::Error {let err=pushScheduled(self_,frames,initial,blot_support::none<Global>(),0,blot_support::none<i64>());if err!=blot_error::Error.none {return err;}while frames.items.len!=0 {let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}let index=frames.items.len-1;
 if frames.items[index].next<frames.items[index].references.len {let reference=frames.items[index].references[frames.items[index].next];frames.items[index].next+=1;let before .= self_.global_states.get(reference.binding);assert(before);let old=before;let owner=frames.items[index].frame.binding;if old.state==State.pending {let err=pushScheduled(self_,frames,reference.binding,blot_support::some(old),owner,blot_support::none<i64>());if err!=blot_error::Error.none {return err;}}else {let err=self_.finishPreparedGlobalOwner(reference.binding,old,owner);if err!=blot_error::Error.none {return err;}}continue;}
 if !frames.items[index].value.present {let root=frames.items[index].frame.id;let value,error=self_.inferDeclarationNode(root);if error!=blot_error::Error.none {return error;}frames.items[index].value=blot_support::some(value);}
 if self_.selected_globals.len!=0 {let selected=self_.selected_globals[0];for position in 1..self_.selected_globals.len {self_.selected_globals[position-1]=self_.selected_globals[position];}self_.selected_globals.resize(self_.selected_globals.len-1);let state .= self_.global_states.get(selected.binding);assert(state);let before=state;if before.state==State.pending {let err=pushScheduled(self_,frames,selected.binding,blot_support::some(before),selected.owner,blot_support::some(selected.diagnostic_at));if err!=blot_error::Error.none {return err;}}else {let err=self_.finishPreparedGlobalOwner(selected.binding,before,selected.owner);if err!=blot_error::Error.none {return err;}}continue;}
 if !frames.items[index].finished {let frame=frames.items[index].frame;let value=frames.items[index].value.value;let err=self_.finishGlobal(frame,value);if err!=blot_error::Error.none {return err;}frames.items[index].finished=true;if self_.selected_globals.len!=0 {continue;}}else {let binding=frames.items[index].frame.binding;let state .= self_.global_states.get(binding);assert(state);if state.on_stack && state.low==state.index {let err=self_.finishComponent(binding);if err!=blot_error::Error.none {return err;}}if self_.selected_globals.len!=0 {continue;}}
 var done=frames.items[index];frames.resize(index);let error=finishScheduled(self_,done);blot_reuse_global_references::release(done.references);done.frame.context.restore(self_);if error!=blot_error::Error.none {return error;}}
 return blot_error::Error.none;}
fn insertDiagnostics(self_:Engine&,at:i64,values:const Diagnostic[:]) {let count=self_.diagnostics.len;let value_count=values.len;self_.diagnostics.resize(count+value_count,default<Diagnostic>());var index=count;while index>at {index-=1;self_.diagnostics[index+value_count]=canonicalDiagnostic(self_.diagnostics[index]);}for value_index in 0..value_count {let value=values[value_index];self_.diagnostics[at+value_index]=canonicalDiagnostic(value);}}
fn finishScheduled(self_:Engine&,done:ScheduledGlobal&)->blot_error::Error {if !done.before.present {return blot_error::Error.none;}let error=self_.finishPreparedGlobalOwner(done.frame.binding,done.before.value,done.owner);if error!=blot_error::Error.none {return error;}let diagnostic_count=self_.diagnostics.len-done.diagnostic_start;let diagnostics=component_diagnostics.alloc_slice(diagnostic_count);for index in 0..diagnostic_count {let diagnostic=self_.diagnostics[done.diagnostic_start+index];diagnostics[index]=canonicalDiagnostic(diagnostic);}self_.diagnostics.resize(done.diagnostic_start);if done.diagnostic_at.present {let at=min(done.diagnostic_at.value,self_.diagnostics.len);insertDiagnostics(self_,at,diagnostics);for &pending in self_.selected_globals {if pending.diagnostic_at>=at {pending.diagnostic_at+=diagnostics.len;}}if diagnostics.len!=0 {component_diagnostics.free_slice(diagnostics);}}else {assert(!self_.staged_global_diagnostics.contains(done.frame.binding));self_.staged_global_diagnostics.insert(done.frame.binding,diagnostics);}return blot_error::Error.none;}
recursive fn prepareSelectedGlobal(self_:Engine&,binding:u32)->bool,blot_error::Error {let state .= self_.global_states.get(binding);if self_.bindings[binding].kind!=blot_reuse_principal_interface::Kind.external && self_.global_driver && state && state.state==State.pending {var owner=self_.current;if self_.dependency_owner.present {owner=self_.dependency_owner.value;}for pending in self_.selected_globals {if pending.binding==binding && pending.owner==owner {return false,blot_error::Error.none;}}self_.selected_globals.push(SelectedGlobal{binding,owner,self_.diagnostics.len, ..});return false,blot_error::Error.none;}let err=self_.prepareGlobal(binding);return err==blot_error::Error.none,err;}
struct AliasStep {binding:u32,body:u32,target:u32=0,next:i64=0}
reusable[] var alias_step_runs:AliasStep[>..];
reusable[] var alias_frame_runs:GlobalFrame[>..];
reusable[] var alias_visited_runs:dictionary_slot<u32,i64>[>..];
struct AliasPlan {storage:AliasStep[:]=default<AliasStep[:]>(),items:AliasStep[:]=default<AliasStep[:]>()}
fn deinit(self_:AliasPlan&) {self_.items=default<blot_check_check::AliasStep[:]>();if self_.storage.len!=0 {alias_step_runs.free_slice(self_.storage);}self_.storage=default<blot_check_check::AliasStep[:]>();}
fn aliasEntryContext(self_:const Engine&)->bool {return self_.current==0 && self_.depth==0 && self_.active.len==0 && self_.pending.len==0 && self_.env.len==0 && self_.type_env.items.len==0 && self_.row_env.items.len==0 && self_.computation_annotations.len==0 && self_.loop_stack.len==0 && self_.return_target==0 && self_.owner==0 && self_.qualification_scope==0 && self_.annotation_binding==0 && self_.inherited_types==0 && self_.inherited_rows==0 && self_.local_qualification_scope==0 && self_.local_requirements_start==0 && self_.diagnostics.len==0;}
fn aliasPlan(self_:const Engine&,initial:u32,result:AliasPlan&)->blot_error::Error {var visited=blot_support_pooled_map::Map<u32,i64>{..};let error=aliasPlanWork(self_,initial,result,visited);visited.deinit(alias_visited_runs);return error;}
fn aliasPlanWork(self_:const Engine&,initial:u32,result:AliasPlan&,visited:blot_support_pooled_map::Map<u32,i64>&)->blot_error::Error {var binding=initial;loop {let known .= visited.get(binding);if known {result.items[result.items.len-1].next=known;return blot_error::Error.none;}let info=self_.bindings[binding];if info.kind!=blot_reuse_principal_interface::Kind.global || info.external.present || info.declaration==0 || info.named_function {break;}if self_.tree.node(info.declaration).tag!=blot_parse_ast::tag_value_decl || firstByte(self_.pool.get(info.name),'.')>=0 {break;}let declaration=self_.tree.value_decl(info.declaration);if declaration.where_node!=0 || declaration.attributes.len!=0 || declaration.body==0 {break;}if declaration.annotation!=0 {let annotation=self_.tree.node(declaration.annotation);if annotation.tag!=blot_parse_ast::tag_type_name {break;}let name=self_.pool.get(annotation.a);if name!="Unit" && name!="Bool" && name!="U32" && name!="F32" {break;}}let node=self_.tree.node(declaration.body);var target:u32=0;if node.tag==blot_parse_ast::tag_name {if firstByte(self_.pool.get(node.a),'.')>=0 {break;}let found:u32={let scalar_lookup_85 .= self_.catalogs.globals.get(node.a);if !scalar_lookup_85 {break;}let scalar_value_85:u32=scalar_lookup_85;scalar_value_85};target=found;}else if node.tag!=blot_parse_ast::tag_unit && node.tag!=blot_parse_ast::tag_boolean && node.tag!=blot_parse_ast::tag_integer && node.tag!=blot_parse_ast::tag_float {break;}visited.insert(binding,result.items.len,alias_visited_runs);let error=blot_support_pooled_buffer::push(result,AliasStep{binding,declaration.body,target,result.items.len+1, ..},alias_step_runs);if error!=blot_error::Error.none {return error;}if target==0 {return blot_error::Error.none;}binding=target;}result.items=result.storage[..0];return blot_error::Error.none;}
recursive fn inferAliasPlan(self_:Engine&,plan:const AliasStep[:])->blot_error::Error {var frames=blot_support_pooled_buffer::Buffer<GlobalFrame>{..};let error=inferAliasWork(self_,plan,frames);while frames.items.len!=0 {var frame=frames.items[frames.items.len-1];frames.resize(frames.items.len-1);frame.context.restore(self_);}frames.deinit(alias_frame_runs);return error;}
recursive fn inferAliasWork(self_:Engine&,plan:const AliasStep[:],frames:blot_support_pooled_buffer::Buffer<GlobalFrame>&)->blot_error::Error {let err=frames.ensure(plan.len,alias_frame_runs);if err!=blot_error::Error.none {return err;}let first,error=self_.beginGlobal(plan[0].binding);if error!=blot_error::Error.none {return error;}let err=frames.push(first,alias_frame_runs);if err!=blot_error::Error.none {return err;}while frames.items.len!=0 {let index=frames.items.len-1;let step=plan[frames.items[index].plan_index];let stats .= self_.execution.stats;if stats {stats.peak_frames=max(stats.peak_frames,frames.items.len);}if step.target!=0 && !frames.items[index].before.present {let state .= self_.global_states.get(step.target);assert(state);let before=state;frames.items[index].before=blot_support::some(before);if before.state==State.pending {let initial,err=self_.beginGlobal(step.target);if err!=blot_error::Error.none {return err;}var child=initial;child.plan_index=step.next;let err=frames.push(child,alias_frame_runs);if err!=blot_error::Error.none {child.context.restore(self_);return err;}continue;}}var value:u32=0;if step.target==0 {let result,err=self_.expression(step.body);if err!=blot_error::Error.none {return err;}value=result;}else {assert(self_.depth==0);self_.depth+=1;let result,error=aliasReference(self_,step.target,frames.items[index].before.value,step.body);self_.depth-=1;if error!=blot_error::Error.none {return error;}value=result;}let frame=frames.items[index];let error=self_.finishGlobal(frame,value);if error!=blot_error::Error.none {return error;}var finished=frames.items[index];frames.resize(index);finished.context.restore(self_);if stats {stats.frames+=1;}}return blot_error::Error.none;}
fn aliasReference(self_:Engine&,target:u32,before:Global,body:u32)->u32,blot_error::Error {let error=self_.finishPreparedGlobal(target,before);if error!=blot_error::Error.none {return 0,error;}let result,err=self_.preparedGlobalReference(target,body);if err!=blot_error::Error.none {return 0,err;}return self_.finishExpression(body,result),blot_error::Error.none;}
recursive fn prepareGlobal(self_:Engine&,binding:u32)->blot_error::Error {if self_.bindings[binding].kind==blot_reuse_principal_interface::Kind.external {return blot_error::Error.none;}let err=self_.inferenceTransition();if err!=blot_error::Error.none {return err;}var owner=self_.current;if self_.dependency_owner.present {owner=self_.dependency_owner.value;}let saved=self_.dependency_owner;self_.dependency_owner=blot_support::none<u32>();let state .= self_.global_states.get(binding);assert(state);let before=state;let error=prepareGlobalBody(self_,binding,before,owner);self_.dependency_owner=saved;return error;}
recursive fn prepareGlobalBody(self_:Engine&,binding:u32,before:Global,owner:u32)->blot_error::Error {if before.state==State.pending {let err=self_.inferGlobal(binding);if err!=blot_error::Error.none {return err;}}let err=self_.flushGlobalDiagnostics(binding);if err!=blot_error::Error.none {return err;}return self_.finishPreparedGlobalOwner(binding,before,owner);}
fn finishPreparedGlobal(self_:Engine&,binding:u32,before:Global)->blot_error::Error {return self_.finishPreparedGlobalOwner(binding,before,self_.current);}
fn finishPreparedGlobalOwner(self_:Engine&,binding:u32,before:Global,owner:u32)->blot_error::Error {let state .= self_.global_states.get(binding);assert(state);let after=state;if owner!=0 && after.on_stack {let current .= self_.global_states.get(owner);assert(current);var low=after.index;if before.state==State.pending {low=after.low;}current.low=min(current.low,low);}return blot_error::Error.none;}
recursive fn globalReference(self_:Engine&,binding:u32,id:u32)->u32,blot_error::Error {if binding==self_.current && self_.bindings[binding].kind==blot_reuse_principal_interface::Kind.global && self_.tree.node(self_.bindings[binding].declaration).tag==blot_parse_ast::tag_value_decl {let attributes=checkedAstList(self_.tree,self_.tree.value_decl(self_.bindings[binding].declaration).attributes);if (attributes.len as i64)!=0 {let err=self_.diagnostic(Code.recursive_tag,self_.tree.list(attributes)[0]);if err!=blot_error::Error.none {return 0,err;}self_.resolved[id]=binding;return self_.types.fresh();}}let err=self_.prepareGlobal(binding);if err!=blot_error::Error.none {return 0,err;}return self_.preparedGlobalReference(binding,id);}
fn preparedGlobalReference(self_:Engine&,binding:u32,id:u32)->u32,blot_error::Error {if self_.bindings[binding].kind==blot_reuse_principal_interface::Kind.global && self_.bindings[binding].scheme.root==0 {self_.qualification_uses.push(QualificationUse{scope:self_.qualification_scope,owner:self_.current,target:binding,source:id, ..});}self_.resolved[id]=binding;return self_.instantiate(binding,id);}
fn startsBytes(text:const u8[:],prefix:const u8[:])->bool {return text.len>=prefix.len && text[..prefix.len]==prefix;}
fn exactIntrinsicArity(name:const u8[:])->blot_support::Option<i64> {if startsBytes(name,"@u32.") || startsBytes(name,"@f32.") {return blot_support::none<i64>();}return intrinsicArity(name);}
fn intrinsicArity(name:const u8[:])->blot_support::Option<i64> {
 let storage=blot_check_storage_ops::lookup(name);if storage.present {return blot_support::some(blot_check_storage_ops::arity(storage.value) as i64);}let staging,present=blot_check_typed_staging::lookup(name);if present {return blot_support::some(blot_check_typed_staging::arity(staging) as i64);}let simd_=blot_backend_simd_intrinsics::lookup(name);if simd_.present {return blot_support::some(simd_.value.arity as i64);}let collection=blot_backend_collection_ops::lookup(name);if collection.present {return blot_support::some(collection.value.arity as i64);}
 if name=="@hole" {return blot_support::some(0 as i64);}
 for candidate in ["@state.get","@state.set","@effect.of","@effect.descriptor","@effect.count","@u32.to_f32","@f32.to_u32","@f32.neg","@f32.abs","@f32.sqrt","@f32.floor","@f32.ceil","@f32.trunc","@array.length","@panic","@flat.encode","@flat.decode","@flat.schema_hash","@flat.kernel_id","@flat.kernel_binding_hash","@flat.kernel_ctx_hash","@flat.kernel_io_hash","@flat.process_id","@flat.process_binding_hash","@flat.encode_wire","@flat.decode_wire","@flat.encode_batch","@flat.decode_batch"] {if name==candidate {return blot_support::some(1 as i64);}}
 for candidate in ["@effect.has","@effect.same","@state.run","@effect.provider","@type.same","@type.result","@u32.add","@u32.sub","@u32.mul","@u32.div","@u32.rem","@u32.bit_and","@u32.bit_or","@u32.bit_xor","@u32.shl","@u32.shr","@u32.eq","@u32.lt","@f32.add","@f32.sub","@f32.mul","@f32.div","@f32.eq","@f32.ne","@f32.lt","@f32.le","@f32.gt","@f32.ge","@array.get","@array.fill","@array.generate","@product.get"] {if name==candidate {return blot_support::some(2 as i64);}}
 for candidate in ["@state.reader","@state.writer","@effect.state","@array.set","@type.call"] {if name==candidate {return blot_support::some(3 as i64);}}
 for candidate in ["@effect.run","@effect.reader","@effect.writer"] {if name==candidate {return blot_support::some(4 as i64);}}return blot_support::none<i64>();
}
// The element of what `source` indexes. A container whose type is known
// must be an array of some kind. One that is a field of a record whose type
// is not known yet (`access.log[0]` in a function written against any
// record with that field) waits for the type; anything else is an array.
// Known owners determine their own element type. A projected field can carry
// this obligation to its caller; an ordinary unconstrained name defaults to Array.
recursive fn constrainIndexed(self_:Engine&,owner:u32,element:u32,source:u32,mode:u32=blot_check_storage_types::indexed_read)->blot_error::Error {
 let root,err=self_.types.resolve(owner,0);if err!=blot_error::Error.none {return err;}
 let actual=blot_check_storage_types::collectionElement(self_.types,self_.types.head(root,0),mode);
 if actual.present {return self_.constrain(element,actual.value,source);}
 if self_.types.node(root).tag==blot_check_types::Tag.variable {
  let count=self_.pending.len;
  for index in 0..count {
   let other=self_.pending[index];
   if other.owner!=self_.current || other.solved {continue;}
   if other.value.kind!=blot_check_types::ObligationKind.writable_field && other.value.kind!=blot_check_types::ObligationKind.field {continue;}
   let result,err=self_.types.resolve(other.value.result,0);if err!=blot_error::Error.none {return err;}
   if result==root {return self_.appendPending(PendingObligation{value:blot_check_types::Obligation{ty:owner,kind:blot_check_types::ObligationKind.collection,source:source,result:element,signature:mode,..},owner:self_.current,..});}
  }
 }
 let sequence,err=self_.types.sequence(blot_check_types::Tag.array,element);if err!=blot_error::Error.none {return err;}
 return self_.constrain(owner,sequence,source);
}
recursive fn constrainCollection(self_:Engine&,owner:u32,element:u32,source:u32)->blot_error::Error {let actual=blot_check_storage_types::readableElement(self_.types,self_.types.head(owner,0));if actual.present {return self_.constrain(element,actual.value,source);}let tag=self_.types.node(self_.types.head(owner,0)).tag;if tag==blot_check_types::Tag.variable {return self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:owner, kind:blot_check_types::ObligationKind.collection, source:source, result:element, .. }, owner:self_.current, .. });}let sequence,err=self_.types.sequence(blot_check_types::Tag.array,element);if err!=blot_error::Error.none {return err;}return self_.constrain(owner,sequence,source);}
fn arrow2(self_:Engine&,first:u32,second:u32,result:u32)->u32,blot_error::Error {let tail,err=self_.types.function(second,result);if err!=blot_error::Error.none {return 0,err;}return self_.types.function(first,tail);}
fn arrow3(self_:Engine&,first:u32,second:u32,third:u32,result:u32)->u32,blot_error::Error {let tail,err=arrow2(self_,second,third,result);if err!=blot_error::Error.none {return 0,err;}return self_.types.function(first,tail);}
recursive fn intrinsic(self_:Engine&,id:u32,name:u32)->u32,blot_error::Error {
 let text=self_.pool.get(name);if self_.editorAt(id) {return self_.captureEditor(id,0,0);}let intrinsic=blot_backend_simd_intrinsics::lookup(text);if intrinsic.present {let op=intrinsic.value;var element=blot_check_types::u32_type;if op.floating {element=blot_check_types::f32_type;}let vector,err=self_.types.product([element,element,element,element]);if err!=blot_error::Error.none {return 0,err;}let lanes,err=self_.types.product([blot_check_types::u32_type,blot_check_types::u32_type,blot_check_types::u32_type,blot_check_types::u32_type]);if err!=blot_error::Error.none {return 0,err;}var result_element=blot_check_types::u32_type;if op.resultLane()==blot_backend_simd_intrinsics::Lane.floating {result_element=blot_check_types::f32_type;}let output,err=self_.types.product([result_element,result_element,result_element,result_element]);if err!=blot_error::Error.none {return 0,err;}let pair,err=self_.types.product([vector,vector]);if err!=blot_error::Error.none {return 0,err;}match op.shape {
 unary,convert => {return self_.types.function(vector,output);},
 binary,compare => {return arrow2(self_,vector,vector,output);},
 shift,broadcast => {return arrow2(self_,vector,blot_check_types::u32_type,vector);},
 reduce => {return self_.types.function(vector,blot_check_types::boolean);},
 select,shuffle => {return arrow2(self_,lanes,pair,vector);},
 madd => {return arrow2(self_,vector,pair,vector);},
 swizzle => {return arrow2(self_,lanes,vector,vector);},
 }}
 if startsBytes(text,"@flat.") {
  if !self_.is_std {return self_.diagnosticFresh(Code.std_only_intrinsic,id);}
  if exactIntrinsicArity(text).present && self_.permitted_intrinsic!=id {return self_.diagnosticFresh(Code.call_arity,id);}
  let pair_u32,perr=self_.types.product([blot_check_types::u32_type,blot_check_types::u32_type]);if perr!=blot_error::Error.none {return 0,perr;}
  if text=="@flat.encode" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let arr,seqerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if seqerr!=blot_error::Error.none {return 0,seqerr;}
   return self_.types.function(a,arr);
  }
  if text=="@flat.decode" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let arr,seqerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if seqerr!=blot_error::Error.none {return 0,seqerr;}
   let maybe_nom=self_.lookupBuiltinNominal("Maybe",1);if !maybe_nom.present {return self_.diagnosticFresh(Code.unsupported,id);}
   let maybe_a,merr=self_.types.nominal(self_.nominals[maybe_nom.value].identity,[a]);if merr!=blot_error::Error.none {return 0,merr;}
   return self_.types.function(arr,maybe_a);
  }
  if text=="@flat.schema_hash" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   return self_.types.function(a,pair_u32);
  }
  if text=="@flat.kernel_id" || text=="@flat.kernel_binding_hash" || text=="@flat.kernel_ctx_hash" || text=="@flat.kernel_io_hash" {
   let kernel_nom=self_.lookupBuiltinNominal("Kernel",3);if !kernel_nom.present {return self_.diagnosticFresh(Code.unsupported,id);}
   let c,cerr=self_.types.fresh();if cerr!=blot_error::Error.none {return 0,cerr;}
   let i,ierr=self_.types.fresh();if ierr!=blot_error::Error.none {return 0,ierr;}
   let o,oerr=self_.types.fresh();if oerr!=blot_error::Error.none {return 0,oerr;}
   let kty,kerr=self_.makeNominalTriple(kernel_nom.value,c,i,o);if kerr!=blot_error::Error.none {return 0,kerr;}
   if text=="@flat.kernel_id" {return self_.types.function(kty,blot_check_types::u32_type);}
   return self_.types.function(kty,pair_u32);
  }
  if text=="@flat.process_id" || text=="@flat.process_binding_hash" {
   let proc_nom=self_.lookupBuiltinNominal("Process",3);if !proc_nom.present {return self_.diagnosticFresh(Code.unsupported,id);}
   let c,cerr=self_.types.fresh();if cerr!=blot_error::Error.none {return 0,cerr;}
   let m,merr=self_.types.fresh();if merr!=blot_error::Error.none {return 0,merr;}
   let r,rerr=self_.types.fresh();if rerr!=blot_error::Error.none {return 0,rerr;}
   let pty,perr2=self_.makeNominalTriple(proc_nom.value,c,m,r);if perr2!=blot_error::Error.none {return 0,perr2;}
   if text=="@flat.process_id" {return self_.types.function(pty,blot_check_types::u32_type);}
   return self_.types.function(pty,pair_u32);
  }
  if text=="@flat.encode_wire" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let arr,seqerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if seqerr!=blot_error::Error.none {return 0,seqerr;}
   return self_.types.function(a,arr);
  }
  if text=="@flat.decode_wire" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let arr,seqerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if seqerr!=blot_error::Error.none {return 0,seqerr;}
   let maybe_nom=self_.lookupBuiltinNominal("Maybe",1);if !maybe_nom.present {return self_.diagnosticFresh(Code.unsupported,id);}
   let maybe_a,merr=self_.types.nominal(self_.nominals[maybe_nom.value].identity,[a]);if merr!=blot_error::Error.none {return 0,merr;}
   return self_.types.function(arr,maybe_a);
  }
  if text=="@flat.encode_batch" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let in_arr,inerr=self_.types.sequence(blot_check_types::Tag.array,a);if inerr!=blot_error::Error.none {return 0,inerr;}
   let out_arr,outerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if outerr!=blot_error::Error.none {return 0,outerr;}
   return self_.types.function(in_arr,out_arr);
  }
  if text=="@flat.decode_batch" {
   let a,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
   let in_arr,inerr=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);if inerr!=blot_error::Error.none {return 0,inerr;}
   let out_arr,outerr=self_.types.sequence(blot_check_types::Tag.array,a);if outerr!=blot_error::Error.none {return 0,outerr;}
   let maybe_nom=self_.lookupBuiltinNominal("Maybe",1);if !maybe_nom.present {return self_.diagnosticFresh(Code.unsupported,id);}
   let maybe_arr,merr=self_.types.nominal(self_.nominals[maybe_nom.value].identity,[out_arr]);if merr!=blot_error::Error.none {return 0,merr;}
   return self_.types.function(in_arr,maybe_arr);
  }
 }
 if text=="@hole" {let scope,err=self_.holeScope();if err!=blot_error::Error.none {return 0,err;}self_.holes.push(Engine_holes{id,scope,self_.current, ..});return self_.types.fresh();}if exactIntrinsicArity(text).present && self_.permitted_intrinsic!=id {let err=self_.diagnostic(Code.call_arity,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}
 if text=="@type.same" {let left,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let right,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}return arrow2(self_,left,right,blot_check_types::boolean);}var scalar:u32=0;if startsBytes(text,"@u32.") {scalar=blot_check_types::u32_type;}else if startsBytes(text,"@f32.") {scalar=blot_check_types::f32_type;}
 if scalar!=0 {let member=text[5..];for candidate in ["add","sub","mul","div"] {if member==candidate {return arrow2(self_,scalar,scalar,scalar);}}if scalar==blot_check_types::u32_type {for candidate in ["rem","bit_and","bit_or","bit_xor","shl","shr"] {if member==candidate {return arrow2(self_,scalar,scalar,scalar);}}}for candidate in ["eq","ne","lt","le","gt","ge"] {if member==candidate && (scalar==blot_check_types::f32_type || member=="eq" || member=="lt") {return arrow2(self_,scalar,scalar,blot_check_types::boolean);}}if scalar==blot_check_types::f32_type {for candidate in ["neg","abs","sqrt","floor","ceil","trunc"] {if member==candidate {return self_.types.function(scalar,scalar);}}}if scalar==blot_check_types::u32_type && member=="to_f32" {return self_.types.function(blot_check_types::u32_type,blot_check_types::f32_type);}if scalar==blot_check_types::f32_type && member=="to_u32" {return self_.types.function(blot_check_types::f32_type,blot_check_types::u32_type);}}
 let collection=blot_backend_collection_ops::lookup(text);if collection.present {return collectionIntrinsic(self_,id,collection.value);}let err=self_.diagnostic(Code.unsupported,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();
}
recursive fn collectionIntrinsic(self_:Engine&,id:u32,primitive:blot_backend_collection_ops::Primitive)->u32,blot_error::Error {let element,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let op=primitive.op;let sequence,err=self_.types.sequence(blot_check_types::Tag.array,element);if err!=blot_error::Error.none {return 0,err;}match op {
 flatten => {let array,err=self_.types.sequence(blot_check_types::Tag.array,sequence);if err!=blot_error::Error.none {return 0,err;}return self_.types.function(array,sequence);},
 length => {return self_.types.function(sequence,blot_check_types::u32_type);},
 get => {return arrow2(self_,sequence,blot_check_types::u32_type,element);},
 set => {return arrow3(self_,sequence,blot_check_types::u32_type,element,sequence);},
 fill => {return arrow2(self_,blot_check_types::u32_type,element,sequence);},
 generate => {let callback,err=self_.types.function(blot_check_types::u32_type,element);if err!=blot_error::Error.none {return 0,err;}return arrow2(self_,blot_check_types::u32_type,callback,sequence);},
 append,prepend => {return arrow2(self_,sequence,element,sequence);},
 identity => {return self_.types.function(sequence,sequence);},
 concat => {return arrow2(self_,sequence,sequence,sequence);},
 slice => {return arrow3(self_,sequence,blot_check_types::u32_type,blot_check_types::u32_type,sequence);},
 simd_load => {
    let storage,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}
    let err=self_.appendPending(PendingObligation{value:blot_check_types::Obligation{ty:storage,kind:blot_check_types::ObligationKind.collection,source:id,result:element,signature:blot_check_types::unit,..},owner:self_.current,..});
    if err!=blot_error::Error.none {return 0,err;}
    let vector,err=self_.types.product([element,element,element,element]);if err!=blot_error::Error.none {return 0,err;}
    return arrow2(self_,storage,blot_check_types::u32_type,vector);
 },
 simd_store => {
    let storage,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}
    let err=self_.appendPending(PendingObligation{value:blot_check_types::Obligation{ty:storage,kind:blot_check_types::ObligationKind.collection,source:id,result:element,signature:blot_check_storage_types::indexed_write,..},owner:self_.current,..});
    if err!=blot_error::Error.none {return 0,err;}
    let vector,err=self_.types.product([element,element,element,element]);if err!=blot_error::Error.none {return 0,err;}
    return arrow3(self_,storage,blot_check_types::u32_type,vector,storage);
 },
 }}
fn reverseWords(values:u32[:]) {var first:i64=0;var last=values.len;while first<last {last-=1;if first>=last {break;}let old=values[first];values[first]=values[last];values[last]=old;first+=1;}}
fn runtimeValue(self_:Engine&,ty:u32,source:u32)->u32,blot_error::Error {return ty,blot_error::Error.none;}
fn checkComptimeProp(self_:Engine&,id:u32,binder_name:u32,member_text:const u8[:])->blot_support::Option<u32>,blot_error::Error {
 let bidx=findComptimeBinder(binder_name);
 if bidx<0 { return blot_support::none<u32>(),blot_error::Error.none; }
 let cap,cerr=self_.checkComptimeCapture(bidx,id);
 if cerr!=blot_error::Error.none { return blot_support::none<u32>(),cerr; }
 if cap { let f,ferr=self_.types.fresh(); return blot_support::some(f),ferr; }
 let binder=comptime_binders[bidx];
 if member_text=="name" {
  self_.resolved[id]=binder.binding;
  self_.projections[id]=comptime_meta_tag_base|1;
  let ty,err=self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);
  return blot_support::some(ty),err;
 }
 if member_text=="has_default" && !binder.is_variants {
  self_.resolved[id]=binder.binding;
  self_.projections[id]=comptime_meta_tag_base|2;
  return blot_support::some(blot_check_types::boolean),blot_error::Error.none;
 }
 if member_text=="default" && !binder.is_variants {
  let fv,err=self_.types.fresh();
  if err!=blot_error::Error.none { return blot_support::none<u32>(),err; }
  recordComptimeFieldVar(self_,fv);
  self_.resolved[id]=binder.binding;
  self_.projections[id]=comptime_meta_tag_base|10;
  return blot_support::some(fv),blot_error::Error.none;
 }
 if member_text=="index" {
  self_.resolved[id]=binder.binding;
  self_.projections[id]=comptime_meta_tag_base|5;
  return blot_support::some(blot_check_types::u32_type),blot_error::Error.none;
 }
 return blot_support::none<u32>(),blot_error::Error.none;
}
recursive fn checkComptimeTagQuery(self_:Engine&,id:u32,direct_source:u32,arg_source:u32)->blot_support::Option<u32>,blot_error::Error {
 if comptime_binder_len==0 { return blot_support::none<u32>(),blot_error::Error.none; }
 let direct=self_.tree.node(direct_source);
 var binder_sym:u32=0;
 var is_has=false;
 var is_get=false;
 if direct.tag==blot_parse_ast::tag_name {
  let txt=self_.pool.get(direct.a);
  let dot=firstDot(txt);
  if !dot.present { return blot_support::none<u32>(),blot_error::Error.none; }
  let head,known=self_.pool.lookup(txt[..dot.value]);
  if !known { return blot_support::none<u32>(),blot_error::Error.none; }
  binder_sym=head;
  let mtxt=txt[dot.value+1..];
  is_has=mtxt=="has_tag";
  is_get=mtxt=="tag";
 } else if direct.tag==blot_parse_ast::tag_field_access {
  var base_id=direct.a;
  while self_.tree.node(base_id).tag==blot_parse_ast::tag_group { base_id=self_.tree.node(base_id).a; }
  let base=self_.tree.node(base_id);
  if base.tag!=blot_parse_ast::tag_name { return blot_support::none<u32>(),blot_error::Error.none; }
  binder_sym=base.a;
  let mtxt=self_.pool.get(direct.b);
  is_has=mtxt=="has_tag";
  is_get=mtxt=="tag";
 } else {
  return blot_support::none<u32>(),blot_error::Error.none;
 }
 if !is_has && !is_get { return blot_support::none<u32>(),blot_error::Error.none; }
 let bidx=findComptimeBinder(binder_sym);
 if bidx<0 { return blot_support::none<u32>(),blot_error::Error.none; }
 let cap,cap_err=self_.checkComptimeCapture(bidx,id);
 if cap_err!=blot_error::Error.none { return blot_support::none<u32>(),cap_err; }
 if cap { let f,ferr=self_.types.fresh(); return blot_support::some(f),ferr; }
 let binder=comptime_binders[bidx];
 var arg_id=arg_source;
 while self_.tree.node(arg_id).tag==blot_parse_ast::tag_group { arg_id=self_.tree.node(arg_id).a; }
 let arg_node=self_.tree.node(arg_id);
 // Form 1: nominal type name (Skip or Codec.Skip)
 var nom_found=blot_support::none<u32>();
 if arg_node.tag==blot_parse_ast::tag_name && !self_.lookup(arg_node.a).present {
  let lk .= self_.catalogs.nominal_names.get(self_.catalogKey(arg_node.a));
  if lk { let v:u32=lk; nom_found=blot_support::some(v); }
 } else if arg_node.tag==blot_parse_ast::tag_field_access {
  var ab=arg_node.a;
  while self_.tree.node(ab).tag==blot_parse_ast::tag_group { ab=self_.tree.node(ab).a; }
  let abn=self_.tree.node(ab);
  if abn.tag==blot_parse_ast::tag_name && !self_.lookup(abn.a).present {
   let lk .= self_.catalogs.nominal_names.get(Qualified{namespace_:abn.a,member:arg_node.b, ..});
   if lk { let v:u32=lk; nom_found=blot_support::some(v); }
  }
 }
 if nom_found.present {
  let nom=self_.nominals[nom_found.value];
  if nom.parameters.len==0 {
   let tag_ty,err=self_.types.nominal(nom.identity,[]);
   if err!=blot_error::Error.none { return blot_support::none<u32>(),err; }
   self_.expr_types[self_.tree.node(id).b]=tag_ty;
   self_.resolved[id]=binder.binding;
   var op:u32=4;
   var res_ty:u32=tag_ty;
   if is_has { op=3; res_ty=blot_check_types::boolean; }
   self_.projections[id]=comptime_meta_tag_base|op;
   return blot_support::some(res_ty),blot_error::Error.none;
  }
 }
 // Form 2: bare constructor ref ($Skip or $Since)
 if arg_node.tag==blot_parse_ast::tag_constructor_ref {
  let lk .= self_.catalogs.constructor_names.get(self_.catalogKey(arg_node.a));
  if !lk {
   let err=self_.constructorDiagnostic(arg_node.a,arg_id);
   if err!=blot_error::Error.none { return blot_support::none<u32>(),err; }
   let f,ferr=self_.types.fresh();
   return blot_support::some(f),ferr;
  }
  let ctor_idx:u32=lk;
  self_.constructor_resolved[id]=ctor_idx;
  self_.resolved[id]=binder.binding;
  if is_has {
   self_.projections[id]=comptime_meta_tag_base|6;
   return blot_support::some(blot_check_types::boolean),blot_error::Error.none;
  }
  let ctor_use,cerr=self_.constructorStorageType(ctor_idx);
  if cerr!=blot_error::Error.none { return blot_support::none<u32>(),cerr; }
  let fn_node=self_.types.node(ctor_use);
  var res_ty=ctor_use;
  if fn_node.tag==blot_check_types::Tag.function { res_ty=fn_node.a; }
  self_.projections[id]=comptime_meta_tag_base|7;
  return blot_support::some(res_ty),blot_error::Error.none;
 }
 // Form 3: value expression ($Since 3 or const tag)
 let val_ty,verr=self_.expression(arg_source);
 if verr!=blot_error::Error.none { return blot_support::none<u32>(),verr; }
 self_.resolved[id]=binder.binding;
 var op:u32=9;
 var res_ty=val_ty;
 if is_has { op=8; res_ty=blot_check_types::boolean; }
 self_.projections[id]=comptime_meta_tag_base|op;
 return blot_support::some(res_ty),blot_error::Error.none;
}
recursive fn comptimeProjectExpression(self_:Engine&,id:u32)->u32,blot_error::Error {
 let node=self_.tree.node(id);
 let bidx=findComptimeBinder(node.b);
 if bidx<0 || comptime_binders[bidx].is_variants { return self_.diagnosticFresh(Code.unknown_name,id); }
 let cap,cap_err=self_.checkComptimeCapture(bidx,id);
 if cap_err!=blot_error::Error.none { return 0,cap_err; }
 if cap { return self_.types.fresh(); }
 let binder=comptime_binders[bidx];
 let val_ty,err=self_.expression(node.a);
 if err!=blot_error::Error.none { return 0,err; }
 let val_res,rerr=self_.types.resolve(val_ty,0);
 if rerr!=blot_error::Error.none { return 0,rerr; }
 var eff_val=val_res;
 let unw=blot_check_storage_types::sharedInner(self_.types,val_res);
 if unw.present { eff_val=unw.value; }
 var eff_target=binder.target_ty;
 let tunw=blot_check_storage_types::sharedInner(self_.types,self_.types.head(eff_target,0));
 if tunw.present { eff_target=tunw.value; }
 let target_was_var=self_.types.node(self_.types.head(eff_target,0)).tag==blot_check_types::Tag.variable;
 let cerr=self_.constrain(eff_val,eff_target,node.a);
 if cerr!=blot_error::Error.none { return 0,cerr; }
 if target_was_var {
  let oerr=self_.checkOpaqueNominal(eff_val,id);
  if oerr!=blot_error::Error.none { return 0,oerr; }
 }
 let fv,ferr=self_.types.fresh();
 if ferr!=blot_error::Error.none { return 0,ferr; }
 recordComptimeFieldVar(self_,fv);
 self_.resolved[id]=binder.binding;
 return fv,blot_error::Error.none;
}
recursive fn comptimeNameChain(self_:Engine&,id:u32,name_sym:u32)->blot_support::Option<u32>,blot_error::Error {
 var parts=NameParts{name:name_sym, ..};
 let first=parts.next(self_.pool);
 if !first.present || !parts.peek(self_.pool).present { return blot_support::none<u32>(),blot_error::Error.none; }
 let head,hknown=self_.pool.lookup(first.value);
 if !hknown || findComptimeBinder(head)<0 { return blot_support::none<u32>(),blot_error::Error.none; }
 let second=parts.next(self_.pool);
 if !second.present { return blot_support::none<u32>(),blot_error::Error.none; }
 let prop,perr=self_.checkComptimeProp(id,head,second.value);
 if perr!=blot_error::Error.none || !prop.present { return prop,perr; }
 if !parts.peek(self_.pool).present { return prop,blot_error::Error.none; }
 var path=IdBuffer{..};
 var types=IdBuffer{..};
 var ty=prop.value;
 let e0=types.append(ty);
 if e0!=blot_error::Error.none { path.deinit(equation_type_ids); types.deinit(equation_type_ids); return blot_support::none<u32>(),e0; }
 loop {
  let part=parts.next(self_.pool);
  if !part.present { break; }
  let psym,pknown=self_.pool.lookup(part.value);
  if !pknown {
   path.deinit(equation_type_ids); types.deinit(equation_type_ids);
   let root,derr=self_.diagnosticFresh(Code.unknown_field,id);
   return blot_support::some(root),derr;
  }
  let projected,jerr=self_.projectField(ty,psym,id,false,blot_support::none<PendingObligation>());
  if jerr!=blot_error::Error.none { path.deinit(equation_type_ids); types.deinit(equation_type_ids); return blot_support::none<u32>(),jerr; }
  ty=projected.ty;
  let ep=path.append(projected.projection);
  if ep!=blot_error::Error.none { path.deinit(equation_type_ids); types.deinit(equation_type_ids); return blot_support::none<u32>(),ep; }
  let et=types.append(ty);
  if et!=blot_error::Error.none { path.deinit(equation_type_ids); types.deinit(equation_type_ids); return blot_support::none<u32>(),et; }
 }
 let plist,epl=self_.types.saveList(path.items);
 let tlist,etl=self_.types.saveList(types.items);
 path.deinit(equation_type_ids);
 types.deinit(equation_type_ids);
 if epl!=blot_error::Error.none { return blot_support::none<u32>(),epl; }
 if etl!=blot_error::Error.none { return blot_support::none<u32>(),etl; }
 self_.access_paths[id]=plist;
 self_.access_types[id]=tlist;
 return blot_support::some(ty),blot_error::Error.none;
}
fn diagnosticEditDistanceLe2(a:const u8[:],b:const u8[:])->i64 {
    let al=a.len;let bl=b.len;
    if al==0 || bl==0 || al>48 || bl>48 {return 3;}
    var diff=al-bl;if diff<0 {diff=-diff;}
    if diff>2 {return 3;}
    var prev:i64[49]=[0;49];var curr:i64[49]=[0;49];
    for j in 0..(bl+1) {prev[j]=j;}
    for i in 1..(al+1) {
        curr[0]=i;var row_min=curr[0];
        for j in 1..(bl+1) {
            var cost:i64=1;if a[i-1]==b[j-1] {cost=0;}
            var best=prev[j]+1;
            if curr[j-1]+1<best {best=curr[j-1]+1;}
            if prev[j-1]+cost<best {best=prev[j-1]+cost;}
            curr[j]=best;if best<row_min {row_min=best;}
        }
        if row_min>2 {return 3;}
        for j in 0..(bl+1) {prev[j]=curr[j];}
    }
    return prev[bl];
}
fn unknownSymbolDetail(self_:Engine&,symbol:u32)->blot_support::Option<const u8[:]> {
    if symbol==0 {return blot_support::none<const u8[:]>();}
    let missing=self_.pool.get(symbol);
    if self_.sourceConstructorExists(symbol) {
        var buf:u8[>..<]=[];
        buf.append("Unknown value `");
        buf.append(missing);
        buf.append("`; constructors require a leading `$` in Blot (did you mean `$");
        buf.append(missing);
        buf.append("`?)");
        return blot_support::some<const u8[:]>(ownDiagnosticText(buf));
    }
    var best_sym:u32=0;var best_dist:i64=3;
    for entry in self_.env {
        if entry.name==0 {continue;}
        let d=diagnosticEditDistanceLe2(missing,self_.pool.get(entry.name));
        if d>0 && d<best_dist {best_dist=d;best_sym=entry.name;}
    }
    for slot in self_.catalogs.globals.slots {
        if slot.tag==0 || slot.key==0 {continue;}
        let d=diagnosticEditDistanceLe2(missing,self_.pool.get(slot.key));
        if d>0 && d<best_dist {best_dist=d;best_sym=slot.key;}
    }
    for slot in self_.imported_globals.slots {
        if slot.tag==0 || slot.key==0 {continue;}
        let d=diagnosticEditDistanceLe2(missing,self_.pool.get(slot.key));
        if d>0 && d<best_dist {best_dist=d;best_sym=slot.key;}
    }
    if best_sym!=0 {
        var buf:u8[>..<]=[];
        buf.append("Unknown value `");
        buf.append(missing);
        buf.append("`; did you mean `");
        buf.append(self_.pool.get(best_sym));
        buf.append("`?");
        return blot_support::some<const u8[:]>(ownDiagnosticText(buf));
    }
    return blot_support::none<const u8[:]>();
}
fn unknownNameDiagnosticFresh(self_:Engine&,id:u32,symbol:u32)->u32,blot_error::Error {
    let err=self_.diagnostic(Code.unknown_name,id);
    if err!=blot_error::Error.none {return 0,err;}
    let index=self_.diagnostics.len-1;
    self_.diagnostics[index].symbol=symbol;
    let detail=self_.unknownSymbolDetail(symbol);
    if detail.present {self_.diagnostics[index].detail=detail;}
    return self_.types.fresh();
}
recursive fn nameExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);if self_.editorAt(id) && self_.editor_marker.present && self_.editor_marker.value.kind==blot_reuse_completion_probe::Kind.expression {return self_.captureEditor(id,0,0);}if comptime_binder_len!=0 {let prop,perr=self_.comptimeNameChain(id,node.a);if perr!=blot_error::Error.none {return 0,perr;}if prop.present {return prop.value,blot_error::Error.none;}}let found=self_.lookup(node.a);if found.present {let binding=found.value;if isWithLocked(binding) {return self_.diagnosticFresh(Code.borrow_conflict,id);}self_.resolved[id]=binding;let ty,err=self_.instantiate(binding,id);if err!=blot_error::Error.none {return 0,err;}return ty,blot_error::Error.none;}let global,err=self_.globalBinding(node.a);if err!=blot_error::Error.none {return 0,err;}if global.present {return self_.globalReference(global.value,id);}let qualified,err=self_.qualifiedValue(id,node.a);if err!=blot_error::Error.none {return 0,err;}if qualified.present {return qualified.value,blot_error::Error.none;}let template,err=self_.operationTemplate(node.a);if err!=blot_error::Error.none {return 0,err;}if template.present {return self_.operationValue(id,template.value,blot_support::none<const u32[:]>());}let constructor,err=self_.typeConstructorValue(self_.catalogKey(node.a));if err!=blot_error::Error.none {return 0,err;}if constructor.present {return constructor.value,blot_error::Error.none;}return self_.unknownNameDiagnosticFresh(id,node.a);}
recursive fn fieldExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);var parent=node.a;while self_.tree.node(parent).tag==blot_parse_ast::tag_group {parent=self_.tree.node(parent).a;}let base=self_.tree.node(parent);if comptime_binder_len!=0 && base.tag==blot_parse_ast::tag_name {let prop,perr=self_.checkComptimeProp(id,base.a,self_.pool.get(node.b));if perr!=blot_error::Error.none {return 0,perr;}if prop.present {return prop.value,blot_error::Error.none;}}if base.tag==blot_parse_ast::tag_name && !self_.lookup(base.a).present {let binding,err=self_.qualifiedImportBinding(Qualified{namespace_:base.a,member:node.b, ..});if err!=blot_error::Error.none {return 0,err;}if binding.present {return self_.globalReference(binding.value,id);}let constructor,err=self_.typeConstructorValue(Qualified{namespace_:base.a,member:node.b, ..});if err!=blot_error::Error.none {return 0,err;}if constructor.present {return constructor.value,blot_error::Error.none;}}if self_.editorAt(id) {var namespace_:u32=0;var receiver:u32=0;if base.tag==blot_parse_ast::tag_name && !self_.lookup(base.a).present && self_.isNamespace(base.a) {namespace_=base.a;}else {let ty,err=self_.expression(node.a);if err!=blot_error::Error.none {return 0,err;}receiver=ty;}return self_.captureEditor(id,receiver,namespace_);}let receiver,err=self_.expression(node.a);if err!=blot_error::Error.none {return 0,err;}let operation,err=self_.scopedOperation(id,receiver,node.b,node.a);if err!=blot_error::Error.none {return 0,err;}if operation.present {return operation.value,blot_error::Error.none;}let projected,err=self_.projectField(receiver,node.b,id,false,blot_support::none<PendingObligation>());if err!=blot_error::Error.none {return 0,err;}self_.projection_resolved[id]=projected.projection;return projected.ty,blot_error::Error.none;}
fn constructorExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);if self_.editorAt(id) {return self_.captureEditor(id,0,self_.catalogKey(node.a).namespace_);}let ctor:u32={let scalar_lookup_91 .= self_.catalogs.constructor_names.get(self_.catalogKey(node.a));if !scalar_lookup_91 {let err=self_.constructorDiagnostic(node.a,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let scalar_value_91:u32=scalar_lookup_91;scalar_value_91};self_.constructor_resolved[id]=ctor;let ty,err=self_.constructorType(ctor);if err!=blot_error::Error.none {return 0,err;}return self_.types.openCovariant(ty);}
recursive fn witnessExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let value,err=self_.expression(node.a);if err!=blot_error::Error.none {return 0,err;}let name,present=self_.pool.lookup("Type");if !present {let err=self_.constructorDiagnostic(node.a,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let ctor:u32={let scalar_lookup_92 .= self_.catalogs.constructor_names.get(self_.catalogKey(name));if !scalar_lookup_92 {let err=self_.constructorDiagnostic(node.a,id);if err!=blot_error::Error.none {return 0,err;}return self_.types.fresh();}let scalar_value_92:u32=scalar_lookup_92;scalar_value_92};self_.constructor_resolved[id]=ctor;let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let constructor,err=self_.constructorType(ctor);if err!=blot_error::Error.none {return 0,err;}let function,err=self_.types.function(value,result);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(constructor,function,id);return result,err;}
recursive fn indexExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let owner,err=self_.expression(node.a);if err!=blot_error::Error.none {return 0,err;}let index,err=self_.expression(node.b);if err!=blot_error::Error.none {return 0,err;}let element,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let actual=blot_check_storage_types::readableElement(self_.types,self_.types.head(owner,0));if actual.present {let err=self_.constrain(element,actual.value,id);if err!=blot_error::Error.none {return 0,err;}}else {let err=self_.constrainIndexed(owner,element,id);if err!=blot_error::Error.none {return 0,err;}}let err=self_.constrain(index,blot_check_types::u32_type,node.b);return element,err;}
recursive fn arrayExpression(self_:Engine&,id:u32)->u32,blot_error::Error {if self_.tree.node(id).c!=0 {let err=self_.diagnostic(Code.unsupported_expression,id);if err!=blot_error::Error.none {return 0,err;}var buf:u8[>..<]=[];buf.append("Bare `[...]` list literals are not supported; array literals use `#[...]` in Blot (e.g. `#[1, 2, 3]`)");self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText(buf));return self_.types.fresh();}let element,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}var diverges=false;let syntax_source_43=id;let syntax_count_43=self_.tree.children(syntax_source_43).len;for syntax_index_43 in 0..syntax_count_43 {let child=self_.tree.children(syntax_source_43)[syntax_index_43];let expression,err=self_.expression(child);if err!=blot_error::Error.none {return 0,err;}let value,err=self_.runtimeValue(expression,child);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(element,value,child);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}diverges=diverges || resolved==blot_check_types::never;}if diverges {return blot_check_types::never,blot_error::Error.none;}return self_.types.sequence(blot_check_types::Tag.array,element);}
reusable[] var lambda_storage_frames:Engine_storage_frames[>..];
struct LambdaContext {scoped_parameter:u32,scope:i64,owner:u32,target:u32,function_body:u32,function_exit_allowed:bool,function_exit_target:u32,function_result_expected:u32,ambient:u32,loops:LoopFrame[:]=default<LoopFrame[:]>(),frames:Engine_storage_frames[:]=default<Engine_storage_frames[:]>(),has_frames:bool=false,body_started:bool=false}
fn restore(self_:LambdaContext&,engine:Engine&) {engine.scoped_parameter=self_.scoped_parameter;if self_.has_frames {engine.storage_frames.clear();engine.storage_frames.append(self_.frames);if self_.frames.len!=0 {lambda_storage_frames.free_slice(self_.frames);}}if self_.body_started {engine.env.resize(self_.scope);engine.owner=self_.owner;engine.return_target=self_.target;engine.function_body=self_.function_body;engine.function_exit_allowed=self_.function_exit_allowed;engine.function_exit_target=self_.function_exit_target;engine.function_result_expected=self_.function_result_expected;engine.loop_stack.clear();for frame in self_.loops {engine.loop_stack.push(canonicalLoop(frame));}if self_.loops.len!=0 {global_loop_runs.free_slice(self_.loops);}}engine.ambient=self_.ambient;}
recursive fn lambdaExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let saved_ct_depth=comptime_lambda_depth;comptime_lambda_depth+=1;let saved_fork_floor=fork_ambient_floor;fork_ambient_floor=fork_outer_len;var saved=LambdaContext{scoped_parameter:self_.scoped_parameter,scope:self_.env.len,owner:self_.owner,target:self_.return_target,function_body:self_.function_body,function_exit_allowed:self_.function_exit_allowed,function_exit_target:self_.function_exit_target,function_result_expected:self_.function_result_expected,ambient:self_.ambient, ..};let result,error=lambdaExpressionBody(self_,id,saved);saved.restore(self_);fork_ambient_floor=saved_fork_floor;comptime_lambda_depth=saved_ct_depth;return result,error;}
fn usesAsCapabilityParam(tree:const blot_parse_ast::Tree&,pool:const blot_parse_symbols::Pool&,body:u32,param_name:u32)->bool {
 if param_name==0 { return false; }
 // Effect capability parameter detection via member access
 let pname=pool.get(param_name);
 let node_span=tree.span(body);
 for ni in 1..tree.nodes.len {
  let sp=tree.span(ni as u32);
  if sp.start<node_span.start || sp.end>node_span.end { continue; }
  let nd=tree.node(ni as u32);
  if nd.tag==blot_parse_ast::tag_field_access {
   let base=tree.node(nd.a);
   if base.tag==blot_parse_ast::tag_name && base.a==param_name { return true; }
  }
  if nd.tag==blot_parse_ast::tag_name {
   let txt=pool.get(nd.a);
   if txt.len>pname.len && txt[pname.len]=='.' as u8 && starts_with(txt,pname) { return true; }
  }
 }
 return false;
}
recursive fn lambdaExpressionBody(self_:Engine&,id:u32,saved:LambdaContext&)->u32,blot_error::Error {
 let node=self_.tree.node(id);let parameter=self_.tree.parameter(node.a);if parameter.where_node!=0 {let err=self_.diagnostic(Code.higher_rank_constraint,parameter.where_node);if err!=blot_error::Error.none {return 0,err;}}var expected:u32=0;if self_.expected_lambda_source==id {expected=self_.expected_lambda_type;}var required_arrow=blot_check_types::Node{tag:blot_check_types::Tag.absent, ..};if expected!=0 {let resolved,err=self_.types.resolve(expected,0);if err!=blot_error::Error.none {return 0,err;}required_arrow=self_.types.node(resolved);}let contextual=expected!=0 && required_arrow.tag==blot_check_types::Tag.function;var takes=parameter.own;if contextual {let wanted,err=self_.types.resolve(required_arrow.a,0);if err!=blot_error::Error.none {return 0,err;}let wrapper=self_.types.node(wanted);if wrapper.tag==blot_check_types::Tag.usage && wrapper.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {takes=true;required_arrow.a=wrapper.a;}}var contextual_capability=false;if contextual {let root,err=self_.types.resolve(required_arrow.a,0);if err!=blot_error::Error.none {return 0,err;}contextual_capability=self_.types.node(root).tag==blot_check_types::Tag.scoped;}let scoped=node.a==self_.scoped_parameter;if !scoped {self_.scoped_parameter=0;}var descriptor=blot_support::none<u32>();if !scoped && parameter.annotation!=0 && self_.capabilityFamilyAnnotation(parameter.annotation).present && usesAsCapabilityParam(self_.tree,self_.pool,node.b,parameter.name) {let family,err=self_.capabilityDescriptorAnnotation(parameter.annotation);if err!=blot_error::Error.none {return 0,err;}descriptor=family;}let symbolic=descriptor.present || contextual_capability;var element_ty:u32=0;
 if scoped {element_ty=self_.scoped_parameter_type;}else if contextual {element_ty=required_arrow.a;}else if descriptor.present {let ty,err=self_.types.capabilityParameter(descriptor.value);if err!=blot_error::Error.none {return 0,err;}element_ty=ty;}else if parameter.is_unit {element_ty=blot_check_types::unit;}else {let ty,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}element_ty=ty;}
 if contextual {if descriptor.present {let capability,err=self_.types.capabilityParameter(descriptor.value);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(element_ty,capability,node.a);if err!=blot_error::Error.none {return 0,err;}}if parameter.is_unit {let err=self_.constrain(element_ty,blot_check_types::unit,node.a);if err!=blot_error::Error.none {return 0,err;}}}if !scoped && !symbolic && parameter.annotation!=0 {let written,err=self_.annotation(parameter.annotation);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(element_ty,written,node.a);if err!=blot_error::Error.none {return 0,err;}}
 saved.has_frames=self_.storage_frames.len!=0 && !scoped;if saved.has_frames {saved.frames=lambda_storage_frames.alloc_slice(self_.storage_frames.len);for frame,index in self_.storage_frames {saved.frames[index]=frame;}self_.storage_frames.clear();}let ambient,err=self_.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}self_.ambient=ambient;let latent=self_.ambient;match self_.types.row(latent).tail {variable payload=>{self_.row_sources.insert(payload.value,id);},_=>{abort("fresh effect row must have a variable tail");},}
 // The contextual row must be available while checking calls in the body.
 let contextual_effects=contextual && self_.types.row(required_arrow.c).labels.len!=0;
 if contextual_effects {
  let err=self_.constrainEffects(latent,required_arrow.c,id);
  if err!=blot_error::Error.none {return 0,err;}
 }
 saved.loops=global_loop_runs.alloc_slice(self_.loop_stack.len);for loop_,index in self_.loop_stack {saved.loops[index]=canonicalLoop(loop_);}self_.loop_stack.clear();self_.owner=id;self_.return_target=0;self_.function_exit_allowed=true;self_.function_exit_target=0;saved.body_started=true;
 if parameter.name!=0 {let binding,err=self_.addBinding(Binding{name:parameter.name,declaration:node.a,owner:id,kind:blot_reuse_principal_interface::Kind.parameter,ty:element_ty, ..});if err!=blot_error::Error.none {return 0,err;}self_.resolved[node.a]=binding;self_.env.push(Entry{parameter.name,binding, ..});}self_.expr_types[node.a]=element_ty;var result_annotation=node.c;if node.c!=0 && self_.tree.node(node.c).tag==blot_parse_ast::tag_type_effect {result_annotation=self_.tree.node(node.c).a;}var required:u32=0;if result_annotation!=0 {let written,err=self_.annotation(result_annotation);if err!=blot_error::Error.none {return 0,err;}required=written;}self_.function_result_expected=0;if required!=0 {self_.function_result_expected=required;}else if contextual {self_.function_result_expected=required_arrow.b;}if node.c!=0 && self_.tree.node(node.c).tag==blot_parse_ast::tag_type_effect {let row,err=self_.annotationEffects(self_.tree.node(node.c).b);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrainEffects(latent,row,id);if err!=blot_error::Error.none {return 0,err;}}
 self_.function_body=node.b;var result:u32=0;if required!=0 {let value,err=self_.contextualLambda(node.b,required);if err!=blot_error::Error.none {return 0,err;}result=value;}else if contextual {let value,err=self_.contextualLambda(node.b,required_arrow.b);if err!=blot_error::Error.none {return 0,err;}result=value;}else {let value,err=self_.expression(node.b);if err!=blot_error::Error.none {return 0,err;}result=value;}
 if parameter.requires_return {var written=node.b;if parameter.pattern_bound {written=self_.tree.node(self_.tree.children(node.b)[1]).a;}let root,err=self_.types.resolve(self_.expr_types[written],0);if err!=blot_error::Error.none {return 0,err;}let allow_unit_handler=with_handler_len!=0 && self_.function_exit_target==0 && root==blot_check_types::unit;if !allow_unit_handler && (self_.function_exit_target==0 || root!=blot_check_types::never) {let err=self_.diagnostic(Code.function_return_required,id);if err!=blot_error::Error.none {return 0,err;}}}if self_.function_exit_target!=0 {self_.function_exit_lambdas.push(id);let resolved,err=self_.types.resolve(result,0);if err!=blot_error::Error.none {return 0,err;}if resolved!=blot_check_types::never {let err=self_.constrain(self_.function_exit_target,result,id);if err!=blot_error::Error.none {return 0,err;}}result=self_.function_exit_target;}
 if required!=0 {
  let err=self_.constrain(result,required,id);
  if err!=blot_error::Error.none {return 0,err;}
  result=required;
 } else {
  let resolved,err=self_.types.resolve(result,0);
  if err!=blot_error::Error.none {return 0,err;}
  if resolved==blot_check_types::never {
   let declaration=if self_.current==0 {0 as u32} else {self_.bindings[self_.current].declaration};
   if declaration!=0 && self_.tree.node(declaration).tag==blot_parse_ast::tag_value_decl &&
      self_.tree.value_decl(declaration).body==id && self_.tree.testMeta(declaration).present {
    // A diverging test still needs a concrete result for its guest ABI.
    result=blot_check_types::unit;
   } else {
    let fresh,err=self_.types.fresh();
    if err!=blot_error::Error.none {return 0,err;}
    result=fresh;
   }
  }
 }
 var taken=element_ty;if takes {let wrapped,err=self_.types.usage(element_ty,blot_parse_ast::usagekind_own,0);if err!=blot_error::Error.none {return 0,err;}taken=wrapped;}let raw,err=self_.types.functionWithEffects(taken,result,latent);if err!=blot_error::Error.none {return 0,err;}if contextual && !contextual_effects {let err=self_.constrainEffects(latent,required_arrow.c,id);if err!=blot_error::Error.none {return 0,err;}}let err=self_.certifyLambda(id,raw,saved.ambient);return raw,err;
}
recursive fn applicationExpression(self_:Engine&,id:u32)->u32,blot_error::Error {
 let node=self_.tree.node(id);var direct_source=node.a;while self_.tree.node(direct_source).tag==blot_parse_ast::tag_group {direct_source=self_.tree.node(direct_source).a;}let direct=self_.tree.node(direct_source);
 if comptime_binder_len!=0 {let ctq,ctq_err=self_.checkComptimeTagQuery(id,direct_source,node.b);if ctq_err!=blot_error::Error.none {return 0,ctq_err;}if ctq.present {return ctq.value,blot_error::Error.none;}}
 let storage,err=self_.storageApplication(id);if err!=blot_error::Error.none {return 0,err;}if storage.present {return storage.value,blot_error::Error.none;}
 if self_.tree.has_typed_staging {let staging,err=self_.stagingApplication(id);if err!=blot_error::Error.none {return 0,err;}if staging.present {return staging.value,blot_error::Error.none;}}let operation,err=self_.operationApplication(id);if err!=blot_error::Error.none {return 0,err;}if operation.present {return operation.value,blot_error::Error.none;}
 var leaf=node.a;var arity:i64=1;while self_.tree.node(leaf).tag==blot_parse_ast::tag_apply {arity+=1;leaf=self_.tree.node(leaf).a;}let saved=self_.permitted_intrinsic;let result,error=applicationAfterArity(self_,id,node,leaf,arity);self_.permitted_intrinsic=saved;return result,error;
}
recursive fn applicationAfterArity(self_:Engine&,id:u32,node:blot_parse_ast::Node,leaf:u32,arity:i64)->u32,blot_error::Error {if self_.tree.node(leaf).tag==blot_parse_ast::tag_intrinsic {let expected=exactIntrinsicArity(self_.pool.get(self_.tree.node(leaf).a));if expected.present {if self_.permitted_intrinsic!=leaf && arity!=expected.value {return self_.diagnosticFresh(Code.call_arity,id);}self_.permitted_intrinsic=leaf;}}
 let reflection,err=self_.reflectionApplication(id);if err!=blot_error::Error.none {return 0,err;}if reflection.present {return reflection.value,blot_error::Error.none;}let state,err=self_.builtinStateApplication(id);if err!=blot_error::Error.none {return 0,err;}if state.present {return state.value,blot_error::Error.none;}let runner,err=self_.effectRunnerApplication(id);if err!=blot_error::Error.none {return 0,err;}if runner.present {return runner.value,blot_error::Error.none;}let provider,err=self_.providerApplication(id);if err!=blot_error::Error.none {return 0,err;}if provider.present {return provider.value,blot_error::Error.none;}
 let head=self_.tree.node(node.a);
 if head.tag==blot_parse_ast::tag_intrinsic && self_.pool.get(head.a)=="@panic" {var argument=node.b;while self_.tree.node(argument).tag==blot_parse_ast::tag_group {argument=self_.tree.node(argument).a;}if self_.tree.node(argument).tag!=blot_parse_ast::tag_string {let err=self_.diagnostic(Code.call_arity,argument);if err!=blot_error::Error.none {return 0,err;}}return blot_check_types::never,blot_error::Error.none;}
 let projection,err=self_.productProjection(id);if err!=blot_error::Error.none {return 0,err;}if projection.present {return projection.value,blot_error::Error.none;}let associated,err=self_.associatedApplication(id);if err!=blot_error::Error.none {return 0,err;}if associated.present {return associated.value,blot_error::Error.none;}let result,err=self_.resultApplication(id);if err!=blot_error::Error.none {return 0,err;}if result.present {return result.value,blot_error::Error.none;}return self_.ordinaryApplication(id,leaf);
}
recursive fn ordinaryApplication(self_:Engine&,id:u32,leaf:u32)->u32,blot_error::Error {
    let node=self_.tree.node(id);
    let pending_begin=self_.pending.len;
    let expression,err=self_.expression(node.a);
    if err!=blot_error::Error.none {return 0,err;}
    let resolved,err=self_.types.resolve(expression,0);
    if err!=blot_error::Error.none {return 0,err;}
    let opened,err=self_.types.openCovariant(resolved);
    if err!=blot_error::Error.none {return 0,err;}
    var function_ty=opened;
    let qualified_input=function_ty;
    let nodes_before=self_.types.nodes.len;
    let rows_before=self_.types.effects.rows.len;
    let qualified_id,err=self_.types.resolve(qualified_input,0);
    if err!=blot_error::Error.none {return 0,err;}
    let qualified=self_.types.node(qualified_id);
    let cleanup=qualified.tag==blot_check_types::Tag.usage && qualified.b==blot_parse_ast::usagekind_cleanup;
    let concurrent=qualified.tag==blot_check_types::Tag.usage && qualified.b==blot_parse_ast::usagekind_concurrent;
    if qualified.tag==blot_check_types::Tag.usage && (qualified.b==blot_parse_ast::usagekind_once || qualified.b==blot_parse_ast::usagekind_many || cleanup || concurrent) {
        function_ty=qualified.a;
    } else {
        let shared_fn=blot_check_storage_types::sharedInner(self_.types,qualified_id);
        if shared_fn.present {function_ty=shared_fn.value;}
    }
    // A repeat can hit a store limit if the first read built temporary
    // nodes or rows. Projected calls also charge each visit to their budget.
    let repeat=self_.types.has_projections ||
        function_ty!=qualified_input || self_.types.nodes.len!=nodes_before || self_.types.effects.rows.len!=rows_before;
    self_.expr_types[node.a]=function_ty;
    if cleanup || concurrent {self_.expr_types[node.a]=qualified_id;}
    var function=qualified;
    if repeat {
        let root,err=self_.types.resolve(function_ty,0);
        if err!=blot_error::Error.none {return 0,err;}
        function=self_.types.node(root);
    }
    let saved=self_.exact_argument_types;
    let evidence,err=self_.evidenceCall(node.a,0);
    if err!=blot_error::Error.none {return 0,err;}
    self_.exact_argument_types=saved || evidence;
    let argument,error=ordinaryArgument(self_,node.b,function);
    self_.exact_argument_types=saved;
    if error!=blot_error::Error.none {return 0,error;}
    return ordinaryApplicationFinish(self_,id,leaf,node,pending_begin,function_ty,function,argument);
}
recursive fn ordinaryArgument(self_:Engine&,source:u32,function:blot_check_types::Node)->u32,blot_error::Error {if function.tag==blot_check_types::Tag.function {var wanted=function.a;let outer=self_.types.node(self_.types.head(wanted,0));if outer.tag==blot_check_types::Tag.usage && outer.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {wanted=outer.a;}let root,err=self_.types.resolve(wanted,0);if err!=blot_error::Error.none {return 0,err;}var taking=false;if self_.types.node(root).tag==blot_check_types::Tag.function {let first=self_.types.node(self_.types.head(self_.types.node(root).a,0));taking=first.tag==blot_check_types::Tag.usage && first.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own);}if self_.types.node(root).tag==blot_check_types::Tag.forall || taking || self_.types.node(self_.types.head(wanted,0)).tag==blot_check_types::Tag.usage || blot_check_storage_types::isArray(self_.types,self_.types.head(wanted,0)) || self_.effectFamilyNominal(root).present {return self_.contextualLambda(source,wanted);}}return self_.checkArgument(source);}
recursive fn ordinaryApplicationFinish(self_:Engine&,id:u32,leaf:u32,node:blot_parse_ast::Node,pending_begin:i64,function_ty:u32,function:blot_check_types::Node,argument:u32)->u32,blot_error::Error {
 if function.tag==blot_check_types::Tag.function {var source=node.b;while self_.tree.node(source).tag==blot_parse_ast::tag_group {source=self_.tree.node(source).a;}let supplied=self_.tree.node(source);let expected_id,err=self_.types.resolve(function.a,0);if err!=blot_error::Error.none {return 0,err;}let expected=self_.types.node(expected_id);if supplied.tag==blot_parse_ast::tag_record && supplied.a==0 && expected.tag==blot_check_types::Tag.record {let syntax_source_44=source;let syntax_count_44=self_.tree.children(syntax_source_44).len;for syntax_index_44 in 0..syntax_count_44 {let field_source=self_.tree.children(syntax_source_44)[syntax_index_44];let name=self_.tree.node(field_source).a;var found=false;for index in 0..expected.b {if self_.types.recordField(expected,index).name==name {found=true;break;}}if !found {return self_.diagnosticFresh(Code.unknown_field,field_source);}}}}
 if self_.tree.node(leaf).tag==blot_parse_ast::tag_intrinsic && self_.pool.get(self_.tree.node(leaf).a)=="@type.same" {let rigid,err=self_.types.containsRigid(argument,0);if err!=blot_error::Error.none {return 0,err;}if rigid {let err=self_.diagnostic(Code.abstract_representation_access,node.b);if err!=blot_error::Error.none {return 0,err;}}}
 let initial,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}var result=initial;var given=argument;var takes=false;{var marked=node.b;while self_.tree.node(marked).tag==blot_parse_ast::tag_group {if self_.tree.node(marked).b==1 {takes=true;}marked=self_.tree.node(marked).a;}}if function.tag==blot_check_types::Tag.function {let wanted,err=self_.types.resolve(function.a,0);if err!=blot_error::Error.none {return 0,err;}let wrapper=self_.types.node(wanted);if wrapper.tag==blot_check_types::Tag.usage && wrapper.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {takes=true;}else if !takes {let actual=self_.types.head(argument,0);let actual_node=self_.types.node(actual);let actual_info=blot_check_storage_types::info(self_.types,actual);let wanted_info=blot_check_storage_types::info(self_.types,wanted);if wrapper.tag==blot_check_types::Tag.array && actual_node.tag!=blot_check_types::Tag.array && actual_node.tag!=blot_check_types::Tag.variable {let readable=blot_check_storage_types::readableElement(self_.types,actual);if readable.present && (!actual_info.present || actual_info.value.kind!=blot_check_storage_types::view) {let err=self_.constrain(readable.value,wrapper.a,id);if err!=blot_error::Error.none {return 0,err;}given=wanted;}}else if wanted_info.present && wanted_info.value.kind==blot_check_storage_types::sized_array && actual!=wanted && actual_node.tag!=blot_check_types::Tag.variable {let act_unwrapped=self_.types.head(blot_check_storage_types::unwrapShared(self_.types,actual),0);let act_uinfo=blot_check_storage_types::info(self_.types,act_unwrapped);if act_uinfo.present && blot_check_storage_types::isSized(act_uinfo.value.kind) {let wlen=blot_check_storage_types::lengthOf(self_.types,wanted);let alen=blot_check_storage_types::lengthOf(self_.types,act_unwrapped);let err=self_.constrain(alen.value,wlen.value,id);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(act_uinfo.value.element,wanted_info.value.element,id);if err!=blot_error::Error.none {return 0,err;}given=wanted;}}else if actual_info.present && actual_info.value.kind==blot_check_storage_types::shared && wrapper.tag!=blot_check_types::Tag.variable && (!wanted_info.present || wanted_info.value.kind!=blot_check_storage_types::shared) {let err=self_.constrain(actual_info.value.element,wanted,id);if err!=blot_error::Error.none {return 0,err;}given=wanted;}}}if takes {let wrapped,err=self_.types.usage(argument,blot_parse_ast::usagekind_own,0);if err!=blot_error::Error.none {return 0,err;}given=wrapped;}let invocation,err=self_.invocation(given,result);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(function_ty,invocation,id);if err!=blot_error::Error.none {return 0,err;}
 return self_.applicationFlow(id,function_ty,argument,result);
}
recursive fn productExpression(self_:Engine&,id:u32)->u32,blot_error::Error {var fields=IdBuffer{..};let result,error=productExpressionWork(self_,id,fields);fields.deinit(equation_type_ids);return result,error;}
recursive fn productExpressionWork(self_:Engine&,id:u32,fields:IdBuffer&)->u32,blot_error::Error {var diverges=false;let syntax_source_45=id;let syntax_count_45=self_.tree.children(syntax_source_45).len;for syntax_index_45 in 0..syntax_count_45 {let child=self_.tree.children(syntax_source_45)[syntax_index_45];let expression,err=self_.expression(child);if err!=blot_error::Error.none {return 0,err;}let value,err=self_.runtimeValue(expression,child);if err!=blot_error::Error.none {return 0,err;}let err=fields.append(value);if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}diverges=diverges || resolved==blot_check_types::never;}if diverges {return blot_check_types::never,blot_error::Error.none;}return self_.types.product(fields.items);}
recursive fn unaryExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let operand,err=self_.expression(node.b);if err!=blot_error::Error.none {return 0,err;}if self_.pool.get(node.a)=="-" {let err=self_.constrain(operand,blot_check_types::f32_type,id);return blot_check_types::f32_type,err;}if self_.pool.get(node.a)=="not" {let err=self_.constrain(operand,blot_check_types::boolean,id);return blot_check_types::boolean,err;}return self_.diagnosticFresh(Code.invalid_operator,id);}
recursive fn conditionalExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);let condition,err=self_.expression(node.a);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(condition,blot_check_types::boolean,node.a);if err!=blot_error::Error.none {return 0,err;}let left,err=self_.expression(node.b);if err!=blot_error::Error.none {return 0,err;}let right,err=self_.expression(node.c);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(left,right,id);if err!=blot_error::Error.none {return 0,err;}if left==blot_check_types::never {return right,blot_error::Error.none;}return left,blot_error::Error.none;}
recursive fn blockExpression(self_:Engine&,id:u32)->u32,blot_error::Error {let node=self_.tree.node(id);var resolver_type:u32=0;if node.c!=0 {let value,err=self_.expression(node.c);if err!=blot_error::Error.none {return 0,err;}resolver_type=value;}if resolver_type!=0 {let root,err=self_.types.resolve(resolver_type,0);if err!=blot_error::Error.none {return 0,err;}let resolver=self_.types.node(root);if resolver.tag==blot_check_types::Tag.provider || resolver.tag==blot_check_types::Tag.state_provider {return self_.providerBlock(id,resolver_type);}}let scope=self_.env.len;let target=self_.return_target;let owner=self_.owner;let arm_block=self_.arm_block;let arm_return=self_.arm_nested_return;let result,error=blockExpressionBody(self_,id,node,resolver_type);self_.env.resize(scope);self_.return_target=target;self_.owner=owner;self_.arm_block=arm_block;self_.arm_nested_return=arm_return;return result,error;}
recursive fn blockExpressionBody(self_:Engine&,id:u32,node:blot_parse_ast::Node,resolver_type:u32)->u32,blot_error::Error {let scope=self_.env.len;let first_binding=self_.bindings.len;let nested=self_.function_body!=id;var arm=blot_support::none<ArmCapture>();let capture=self_.arm_capture;if capture.present && capture.value.block_==id && resolver_type==0 {arm=capture;}if arm.present {self_.arm_block=id;self_.arm_nested_return=0;}let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}var result=fresh;if self_.expected_lambda_source==id && (blot_check_storage_types::isArray(self_.types,self_.types.head(self_.expected_lambda_type,0))) {result=self_.expected_lambda_type;}
 if resolver_type!=0 {let err=self_.diagnostic(Code.invalid_provider,node.c);if err!=blot_error::Error.none {return 0,err;}}
 self_.return_target=result;self_.owner=id;let flow,err=self_.suite(id);if err!=blot_error::Error.none {return 0,err;}var carried:i64=0;if arm.present {let versions=armVersions(arm.value);let enclosing=self_.env[..versions.len];for entry,index in enclosing {versions[index]=self_.latestSuccessor(entry.binding);}var carrying=false;for entry,index in enclosing {if versions[index]!=entry.binding {carrying=true;break;}}self_.arm_capture.value.carrying=carrying;carried=versions.len;if carrying && self_.arm_nested_return!=0 {let err=self_.diagnostic(Code.case_arm_return,self_.arm_nested_return);if err!=blot_error::Error.none {return 0,err;}}}if nested {let err=self_.deadRebindings(scope,first_binding,carried);if err!=blot_error::Error.none {return 0,err;}}if !flow.exits {let err=self_.constrain(result,blot_check_types::unit,id);if err!=blot_error::Error.none {return 0,err;}}if flow.exits && flow.breaks && !flow.returns {return blot_check_types::never,blot_error::Error.none;}return result,blot_error::Error.none;
}
recursive fn forkExpression(self_:Engine&,id:u32)->u32,blot_error::Error {
 let node=self_.tree.node(id);
 let entries=blot_parse_ast::List{node.a,node.b, ..};
 let count=self_.tree.list(entries).len;
 let saved_env=self_.env.len;
 let saved_owner=self_.owner;
 let saved_return_target=self_.return_target;
 let saved_function_body=self_.function_body;
 let saved_exit_allowed=self_.function_exit_allowed;
 let saved_exit_target=self_.function_exit_target;
 let saved_result_expected=self_.function_result_expected;
 let saved_ambient=self_.ambient;
 let saved_loops=global_loop_runs.alloc_slice(self_.loop_stack.len);
 for loop_,index in self_.loop_stack {saved_loops[index]=canonicalLoop(loop_);}
 self_.loop_stack.clear();
 var err=blot_error::Error.none;
 for index in 0..count {
  let entry_id=self_.tree.list(entries)[index];
  let entry=self_.tree.node(entry_id);
  let found=self_.lookup(entry.a);
  if !found.present {
   err=self_.diagnostic(Code.unknown_rebinding,entry.b);
   if err!=blot_error::Error.none {break;}
  } else {
   let outer=found.value;
   self_.resolved[entry.b]=outer;
   let outer_ty=self_.bindings[outer].ty;
   self_.expr_types[entry.b]=outer_ty;
   let inner,add_err=self_.addBinding(Binding{name:entry.a,declaration:entry_id,owner:id,kind:blot_reuse_principal_interface::Kind.local,ty:outer_ty,scheme:blot_check_types::Scheme{root:outer_ty, ..}, ..});
   if add_err!=blot_error::Error.none {err=add_err;break;}
   self_.resolved[entry_id]=inner;
   self_.expr_types[entry_id]=outer_ty;
   self_.env.push(Entry{entry.a,inner, ..});
  }
 }
 var result:u32=blot_check_types::unit;
 var fork_ambient:u32=0;
 if err==blot_error::Error.none {
  let fresh_row,row_err=self_.types.freshEffects();
  if row_err!=blot_error::Error.none {err=row_err;}
  else {fork_ambient=fresh_row;}
 }
 if err==blot_error::Error.none {
  self_.ambient=fork_ambient;
  self_.owner=id;
  self_.function_body=node.c;
  self_.return_target=0;
  self_.function_exit_allowed=true;
  self_.function_exit_target=0;
  self_.function_result_expected=0;
  if fork_outer_len>=256 { err=blot_error::Error.type_limit; }
  else {
   let fork_mark=fork_outer_len;
   fork_outer_ambients[fork_outer_len]=saved_ambient;
   fork_outer_len+=1;
   let flow,suite_err=self_.suite(node.c);
   fork_outer_len=fork_mark;
   if suite_err!=blot_error::Error.none {err=suite_err;}
   else if self_.function_exit_target!=0 {
    if !flow.exits {err=self_.diagnostic(Code.function_return_required,id);}
    result=self_.function_exit_target;
   } else if flow.exits {
    result=blot_check_types::never;
   }
  }
 }
 if err==blot_error::Error.none {
  err=self_.solveFields();
 }
 if err==blot_error::Error.none {
  let has_foreign,ferr=self_.rowUsesForeign(fork_ambient);
  if ferr!=blot_error::Error.none {err=ferr;}
  else if has_foreign {
   err=self_.diagnostic(Code.sealed_effect,id);
  } else {
   err=self_.constrainEffects(fork_ambient,saved_ambient,id);
  }
 }
 self_.env.resize(saved_env);
 self_.owner=saved_owner;
 self_.return_target=saved_return_target;
 self_.function_body=saved_function_body;
 self_.function_exit_allowed=saved_exit_allowed;
 self_.function_exit_target=saved_exit_target;
 self_.function_result_expected=saved_result_expected;
 self_.ambient=saved_ambient;
 self_.loop_stack.clear();
 for loop_ in saved_loops {self_.loop_stack.push(canonicalLoop(loop_));}
 if saved_loops.len!=0 {global_loop_runs.free_slice(saved_loops);}
 return result,err;
}
fn isOuterSparkBinding(self_:const Engine&,name:u32)->bool {
 if self_.spark_env_floor<0 {return false;}
 var idx=self_.env.len;
 while idx!=0 {
  idx-=1;
  if self_.env[idx].name==name {return idx<self_.spark_env_floor;}
 }
 return false;
}
recursive fn sparkExpression(self_:Engine&,id:u32)->u32,blot_error::Error {
 let node=self_.tree.node(id);
 let src_id=self_.tree.spark_source(id);
 let end_id=self_.tree.spark_end(id);
 var elem_ty:u32=blot_check_types::u32_type;
 if end_id!=0 {
  let first_ty,ferr=self_.expression(src_id);if ferr!=blot_error::Error.none {return 0,ferr;}
  let c1=self_.constrain(first_ty,blot_check_types::u32_type,src_id);if c1!=blot_error::Error.none {return 0,c1;}
  let last_ty,lerr=self_.expression(end_id);if lerr!=blot_error::Error.none {return 0,lerr;}
  let c2=self_.constrain(last_ty,blot_check_types::u32_type,end_id);if c2!=blot_error::Error.none {return 0,c2;}
 }else {
  let src_ty,serr=self_.expression(src_id);if serr!=blot_error::Error.none {return 0,serr;}
  let fresh,ferr=self_.types.fresh();if ferr!=blot_error::Error.none {return 0,ferr;}
  let cerr=self_.constrainCollection(src_ty,fresh,src_id);if cerr!=blot_error::Error.none {return 0,cerr;}
  elem_ty=fresh;
 }
 let saved_env=self_.env.len;
 let saved_ambient=self_.ambient;
 let saved_floor=self_.spark_env_floor;
 let saved_owner=self_.owner;
 let saved_return_target=self_.return_target;
 let saved_exit_allowed=self_.function_exit_allowed;
 let saved_loops=global_loop_runs.alloc_slice(self_.loop_stack.len);
 for loop_,index in self_.loop_stack {saved_loops[index]=canonicalLoop(loop_);}
 self_.loop_stack.clear();
 self_.spark_env_floor=saved_env;
 self_.owner=id;
 self_.return_target=0;
 self_.function_exit_allowed=false;
 var err=blot_error::Error.none;
 var body_ty:u32=blot_check_types::unit;
 let total,perr=self_.pattern(node.b,elem_ty,saved_env,[],false);
 if perr!=blot_error::Error.none {err=perr;}
 else {
  if !total {err=self_.diagnostic(Code.spark_generator,node.b);}
  if err==blot_error::Error.none {
   let spark_row,rerr=self_.types.freshEffects();
   if rerr!=blot_error::Error.none {err=rerr;}
   else {
    self_.ambient=spark_row;
    let inferred,berr=self_.expression(node.a);
    if berr!=blot_error::Error.none {err=berr;}
    else {
     body_ty=inferred;
     err=self_.requirePureEffectRow(spark_row,node.a,Code.spark_effectful);
    }
   }
  }
 }
 self_.env.resize(saved_env);
 self_.ambient=saved_ambient;
 self_.spark_env_floor=saved_floor;
 self_.owner=saved_owner;
 self_.return_target=saved_return_target;
 self_.function_exit_allowed=saved_exit_allowed;
 self_.loop_stack.clear();
 for loop_ in saved_loops {self_.loop_stack.push(canonicalLoop(loop_));}
 if saved_loops.len!=0 {global_loop_runs.free_slice(saved_loops);}
 if err!=blot_error::Error.none {return 0,err;}
 return self_.types.sequence(blot_check_types::Tag.array,body_ty);
}
recursive fn expression(self_:Engine&,id:u32)->u32,blot_error::Error {if id==0 {return blot_check_types::unit,blot_error::Error.none;}if self_.depth==1024 {let err=self_.diagnostic(Code.nesting_limit,id);return blot_check_types::absent,err;}self_.depth+=1;let value,error=expressionValue(self_,id,self_.tree.node(id));self_.depth-=1;if error!=blot_error::Error.none {return 0,error;}return self_.finishExpression(id,value),blot_error::Error.none;}
recursive fn expressionValue(self_:Engine&,id:u32,node:blot_parse_ast::Node)->u32,blot_error::Error {match node.tag {
 blot_parse_ast::tag_unit=>{return blot_check_types::unit,blot_error::Error.none;},blot_parse_ast::tag_boolean=>{return blot_check_types::boolean,blot_error::Error.none;},blot_parse_ast::tag_integer=>{return blot_check_types::u32_type,blot_error::Error.none;},blot_parse_ast::tag_float=>{return blot_check_types::f32_type,blot_error::Error.none;},blot_parse_ast::tag_string=>{return self_.types.sequence(blot_check_types::Tag.array,blot_check_types::u32_type);},blot_parse_ast::tag_group=>{return self_.expression(node.a);},blot_parse_ast::tag_name=>{return self_.nameExpression(id);},blot_parse_ast::tag_selector=>{return self_.selectorFunction(id);},blot_parse_ast::tag_field_access=>{return self_.fieldExpression(id);},blot_parse_ast::tag_constructor_ref=>{return self_.constructorExpression(id);},blot_parse_ast::tag_type_witness=>{return self_.witnessExpression(id);},blot_parse_ast::tag_record=>{return self_.recordValue(id);},blot_parse_ast::tag_index_access=>{return self_.indexExpression(id);},blot_parse_ast::tag_array=>{return self_.arrayExpression(id);},blot_parse_ast::tag_intrinsic=>{let value,err=self_.intrinsic(id,node.a);if err!=blot_error::Error.none {return 0,err;}return self_.types.openCovariant(value);},blot_parse_ast::tag_lambda=>{return self_.lambdaExpression(id);},blot_parse_ast::tag_apply=>{return self_.applicationExpression(id);},blot_parse_ast::tag_product=>{return self_.productExpression(id);},blot_parse_ast::tag_unary=>{return self_.unaryExpression(id);},blot_parse_ast::tag_binary=>{return self_.binary(id);},blot_parse_ast::tag_case_expr=>{return self_.caseExpression(id);},blot_parse_ast::tag_if_expr=>{return self_.conditionalExpression(id);},blot_parse_ast::tag_block=>{return self_.blockExpression(id);},blot_parse_ast::tag_fork_expr=>{return self_.forkExpression(id);},blot_parse_ast::tag_spark_expr=>{return self_.sparkExpression(id);},blot_parse_ast::tag_comptime_for=>{let _,err=self_.comptimeForStatement(id);return self_.expr_types[id],err;},blot_parse_ast::tag_comptime_project=>{return self_.comptimeProjectExpression(id);},_=>{return self_.diagnosticFresh(Code.unsupported,id);},}}
fn finishExpression(self_:Engine&,id:u32,value:u32)->u32 {self_.expr_types[id]=value;return value;}
recursive fn taggedExpression(self_:Engine&,attributes:blot_parse_ast::List,body:u32,depth:i64)->u32,blot_error::Error {if depth>=1024 {return 0,blot_error::Error.type_limit;}if (attributes.len as i64)==0 {if self_.current!=0 && self_.bindings[self_.current].kind==blot_reuse_principal_interface::Kind.global && self_.tree.node(self_.bindings[self_.current].declaration).tag==blot_parse_ast::tag_value_decl {let declaration=self_.tree.value_decl(self_.bindings[self_.current].declaration);if declaration.body==body && declaration.annotation!=0 {let written=self_.tree.node(declaration.annotation);if blot_check_storage_types::isArray(self_.types,self_.types.head(self_.expr_types[declaration.annotation],0)) || self_.effectFamilyNominal(self_.expr_types[declaration.annotation]).present || written.tag==blot_parse_ast::tag_type_usage || (written.tag==blot_parse_ast::tag_type_function && self_.tree.node(written.a).tag==blot_parse_ast::tag_type_binder) {return self_.contextualLambda(body,self_.expr_types[declaration.annotation]);}}}return self_.expression(body);}let attribute=self_.tree.list(attributes)[0];let function_ty,err=self_.expression(self_.tree.node(attribute).a);if err!=blot_error::Error.none {return 0,err;}let argument,err=self_.taggedArgument(attributes,body,depth,function_ty);
 if err!=blot_error::Error.none {return 0,err;}
 let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}let invocation,err=self_.invocation(argument,result);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(function_ty,invocation,attribute);if err!=blot_error::Error.none {return 0,err;}self_.expr_types[attribute]=result;
 if self_.current!=0 && self_.bindings[self_.current].kind==blot_reuse_principal_interface::Kind.global && self_.tree.node(self_.bindings[self_.current].declaration).tag==blot_parse_ast::tag_value_decl {
  let declaration=self_.tree.value_decl(self_.bindings[self_.current].declaration);
  if declaration.function_declaration && declaration.body==body {
   let err=self_.namedFunctionTag(body,result,attribute);
   if err!=blot_error::Error.none {return 0,err;}
  }
 }
 return result,blot_error::Error.none;
}
recursive fn taggedArgument(self_:Engine&,attributes:blot_parse_ast::List,body:u32,depth:i64,function_ty:u32)->u32,blot_error::Error {
 if attributes.len==1 {
  var syntax=self_.tree.node(body);
  while syntax.tag==blot_parse_ast::tag_group {syntax=self_.tree.node(syntax.a);}
  if syntax.tag==blot_parse_ast::tag_lambda {
   var function=self_.types.node(self_.types.head(function_ty,0));
   while function.tag==blot_check_types::Tag.forall {function=self_.types.node(self_.types.head(function.a,0));}
   if function.tag==blot_check_types::Tag.function {return self_.contextualLambda(body,function.a);}
  }
 }
 return self_.taggedExpression(checkedAstSubspan(self_.tree,attributes,1,(attributes.len as i64)),body,depth+1);
}
recursive fn namedFunctionTag(self_:Engine&,body:u32,transformed:u32,attribute:u32)->blot_error::Error {
 var source=body;
 var result=transformed;
 var remaining:i64=1024;
 while self_.tree.node(source).tag==blot_parse_ast::tag_lambda {
  if remaining==0 {return blot_error::Error.type_limit;}
  remaining-=1;
  let node=self_.types.node(self_.types.head(result,0));
  if node.tag==blot_check_types::Tag.usage || node.tag==blot_check_types::Tag.forall {
   result=node.a;
   continue;
  }
  let syntax=self_.tree.node(source);
  let output,err=self_.types.fresh();
  if err!=blot_error::Error.none {return err;}
  let effects,err=self_.types.freshEffects();
  if err!=blot_error::Error.none {return err;}
  let arrow,err=self_.types.functionWithEffects(self_.expr_types[syntax.a],output,effects);
  if err!=blot_error::Error.none {return err;}
  // Preserve dispatch parameters and written results; wrapper effects may change.
  let err=self_.constrain(arrow,result,attribute);
  if err!=blot_error::Error.none {return err;}
  if syntax.c!=0 {
   let original=self_.types.node(self_.types.head(self_.expr_types[source],0));
   let err=self_.constrain(original.b,output,attribute);
   if err!=blot_error::Error.none {return err;}
  }
  source=syntax.b;
  result=output;
 }
 return blot_error::Error.none;
}
fn applicationFlow(self_:Engine&,id:u32,callee:u32,argument:u32,result:u32)->u32,blot_error::Error {
    var head=id; var count:i64=0;
    while self_.tree.node(head).tag==blot_parse_ast::tag_apply {count+=1;head=self_.tree.node(head).a;}
    var arity=blot_support::none<i64>();
    if self_.tree.node(head).tag==blot_parse_ast::tag_intrinsic {arity=intrinsicArity(self_.pool.get(self_.tree.node(head).a));}
    // Intrinsics evaluate their collected arguments at saturation. Projected
    // types also charge these visits to their observable inference budget.
    var diverges=false;
    if self_.types.has_projections || (arity.present && arity.value==count) {
        var call=id;
        while call!=head && !diverges {
            let node=self_.tree.node(call);let value,err=self_.types.resolve(self_.expr_types[node.b],0);
            if err!=blot_error::Error.none {return 0,err;}
            diverges=value==blot_check_types::never;call=node.a;
        }
    }
    if arity.present && count<=arity.value {
        if count==arity.value && diverges {return blot_check_types::never,blot_error::Error.none;}
        return result,blot_error::Error.none;
    }
    let resolved,err=self_.types.resolve(callee,0);if err!=blot_error::Error.none {return 0,err;}
    let function=self_.types.node(resolved);
    if function.tag==blot_check_types::Tag.never {return blot_check_types::never,blot_error::Error.none;}
    if function.tag==blot_check_types::Tag.function {
        let value,err=self_.types.resolve(function.b,0);if err!=blot_error::Error.none {return 0,err;}
        if value==blot_check_types::never {return value,blot_error::Error.none;}
    }
    let value,err=self_.types.resolve(argument,0);if err!=blot_error::Error.none {return 0,err;}
    if value==blot_check_types::never {return value,blot_error::Error.none;}
    return result,blot_error::Error.none;
}
recursive fn evidenceCall(self_:Engine&,source:u32,depth:i64)->bool,blot_error::Error {if self_.implementations.len==0 {return false,blot_error::Error.none;}if depth>=256 {return false,blot_error::Error.type_limit;}let step,err=self_.associatedStep(source);if err!=blot_error::Error.none {return false,err;}if !step {return false,blot_error::Error.type_limit;}let node=self_.tree.node(source);if node.tag==blot_parse_ast::tag_apply || node.tag==blot_parse_ast::tag_group {return self_.evidenceCall(node.a,depth+1);}let binding=self_.resolved[source];if binding==0 {return false,blot_error::Error.none;}return self_.evidenceScheme(binding,depth);}
recursive fn evidenceScheme(self_:Engine&,binding:u32,depth:i64)->bool,blot_error::Error {if depth>=256 {return false,blot_error::Error.type_limit;}let step,err=self_.associatedStep(self_.bindings[binding].declaration);if err!=blot_error::Error.none {return false,err;}if !step {return false,blot_error::Error.type_limit;}let principal=self_.bindings[binding].scheme;for predicate in self_.obligations[principal.obligations.start..principal.obligations.start+principal.obligations.len] {if predicate.kind==blot_check_types::ObligationKind.contract || predicate.kind==blot_check_types::ObligationKind.type_eq {return true,blot_error::Error.none;}if predicate.kind==blot_check_types::ObligationKind.callee_use && predicate.identity.unit==self_.unit {let evidence,err=self_.evidenceScheme(predicate.identity.decl,depth+1);if err!=blot_error::Error.none {return false,err;}if evidence {return true,blot_error::Error.none;}}}return false,blot_error::Error.none;}
recursive fn checkArgument(self_:Engine&,id:u32)->u32,blot_error::Error {let actual,err=self_.expression(id);if err!=blot_error::Error.none {return 0,err;}if !self_.exact_argument_types {return actual,blot_error::Error.none;}var certified=IdBuffer{..};let result,error=checkArgumentRows(self_,id,actual,certified);certified.deinit(equation_type_ids);return result,error;}
fn checkArgumentRows(self_:Engine&,id:u32,actual:u32,certified:IdBuffer&)->u32,blot_error::Error {for decision in self_.body_closed_rows {let step,err=self_.associatedStep(id);if err!=blot_error::Error.none {return 0,err;}if !step {return actual,blot_error::Error.none;}if decision.owner==self_.current {let err=certified.append(decision.variable);if err!=blot_error::Error.none {return 0,err;}}}let resolved,err=self_.types.resolve(actual,0);if err!=blot_error::Error.none {return 0,err;}return self_.types.closeCovariant(resolved,certified.items,[]);}
fn operatorMethodName(op:blot_check_types::Operator)->const u8[:] {
    match op {
        add=>{return "add";},sub=>{return "sub";},mul=>{return "mul";},div=>{return "div";},rem=>{return "rem";},
        equal=>{return "eq";},not_equal=>{return "ne";},less=>{return "lt";},less_equal=>{return "le";},greater=>{return "gt";},greater_equal=>{return "ge";},
        bit_and=>{return "bit_and";},bit_or=>{return "bit_or";},bit_xor=>{return "bit_xor";},shift_left=>{return "shl";},shift_right=>{return "shr";},
        _=>{return "";},
    }
}
recursive fn binary(self_:Engine&,id:u32)->u32,blot_error::Error {
 let node=self_.tree.node(id);let operator=self_.pool.get(node.a);
 if operator=="and" || operator=="or" {let left,err=self_.expression(node.b);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(left,blot_check_types::boolean,node.b);if err!=blot_error::Error.none {return 0,err;}let right,err=self_.expression(node.c);if err!=blot_error::Error.none {return 0,err;}let err=self_.constrain(right,blot_check_types::boolean,node.c);return blot_check_types::boolean,err;}
 if operator=="|>" {
  let left,err=self_.checkArgument(node.b);if err!=blot_error::Error.none {return 0,err;}
  let right_raw,err=self_.expression(node.c);if err!=blot_error::Error.none {return 0,err;}
  let resolved,err=self_.types.resolve(right_raw,0);if err!=blot_error::Error.none {return 0,err;}
  let opened,err=self_.types.openCovariant(resolved);if err!=blot_error::Error.none {return 0,err;}
  var fn_ty=opened;
  let qid,err=self_.types.resolve(fn_ty,0);if err!=blot_error::Error.none {return 0,err;}
  let qn=self_.types.node(qid);
  if qn.tag==blot_check_types::Tag.usage && (qn.b==blot_parse_ast::usagekind_once || qn.b==blot_parse_ast::usagekind_many || qn.b==blot_parse_ast::usagekind_cleanup || qn.b==blot_parse_ast::usagekind_concurrent) {fn_ty=qn.a;}
  else {let shared_fn=blot_check_storage_types::sharedInner(self_.types,qid);if shared_fn.present {fn_ty=shared_fn.value;}}
  self_.expr_types[node.c]=fn_ty;
  let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}
  var given=left;
  let fn_root,err=self_.types.resolve(fn_ty,0);if err!=blot_error::Error.none {return 0,err;}
  let fn_node=self_.types.node(fn_root);
  if fn_node.tag==blot_check_types::Tag.function {
   let wanted,err=self_.types.resolve(fn_node.a,0);if err!=blot_error::Error.none {return 0,err;}
   let wrapper=self_.types.node(wanted);
   if wrapper.tag==blot_check_types::Tag.usage && wrapper.b==blot_check_types::usageCode(blot_parse_ast::usagekind_own) {
    let wrapped,err=self_.types.usage(left,blot_parse_ast::usagekind_own,0);if err!=blot_error::Error.none {return 0,err;}
    given=wrapped;
   } else {
    let actual=self_.types.head(left,0);let actual_node=self_.types.node(actual);let actual_info=blot_check_storage_types::info(self_.types,actual);
    if wrapper.tag==blot_check_types::Tag.array && actual_node.tag!=blot_check_types::Tag.array && actual_node.tag!=blot_check_types::Tag.variable {
     let readable=blot_check_storage_types::readableElement(self_.types,actual);
     if readable.present && (!actual_info.present || actual_info.value.kind!=blot_check_storage_types::view) {
      let err=self_.constrain(readable.value,wrapper.a,id);if err!=blot_error::Error.none {return 0,err;}
      given=wanted;
     }
    }
   }
  }
  let inv,err=self_.invocation(given,result);if err!=blot_error::Error.none {return 0,err;}
  let err=self_.constrain(fn_ty,inv,id);if err!=blot_error::Error.none {return 0,err;}
  return result,blot_error::Error.none;
 }
 let op_kind=symbolOperator(operator);
 if op_kind!=blot_check_types::Operator.none {
  let lv,lerr=self_.checkArgument(node.b);if lerr!=blot_error::Error.none {return 0,lerr;}
  if self_.member_templates.len!=0 {
   let mtext=operatorMethodName(op_kind);let msym,mknown=self_.pool.lookup(mtext);
   if mknown {
    let tb,trecv,tambig,terr=self_.findTraitMethodBinding(lv,msym,id);if terr!=blot_error::Error.none {return 0,terr;}
    if tambig {
     let _,rerr=self_.checkArgument(node.c);if rerr!=blot_error::Error.none {return 0,rerr;}
     return self_.types.fresh();
    }
    if tb.present {
     self_.resolved[id]=tb.value;let fn_ty,ferr=self_.instantiate(tb.value,id);if ferr!=blot_error::Error.none {return 0,ferr;}
     self_.dispatch_signatures[id]=fn_ty;let after,aerr=self_.types.fresh();if aerr!=blot_error::Error.none {return 0,aerr;}
     let inv1,i1err=self_.invocation(trecv,after);if i1err!=blot_error::Error.none {return 0,i1err;}
     let c1err=self_.constrain(fn_ty,inv1,id);if c1err!=blot_error::Error.none {return 0,c1err;}
     let rv,rerr=self_.checkArgument(node.c);if rerr!=blot_error::Error.none {return 0,rerr;}
     let res,reserr=self_.types.fresh();if reserr!=blot_error::Error.none {return 0,reserr;}
     let inv2,i2err=self_.invocation(rv,res);if i2err!=blot_error::Error.none {return 0,i2err;}
     let c2err=self_.constrain(after,inv2,id);return res,c2err;
    }
   }
  }
  let rv,rerr=self_.checkArgument(node.c);if rerr!=blot_error::Error.none {return 0,rerr;}
  let dispatched,derr=self_.dispatch(lv,rv,0,op_kind,id,true);if derr!=blot_error::Error.none {return 0,derr;}
  if dispatched.present {return dispatched.value,blot_error::Error.none;}
  let result,err=self_.types.fresh();if err!=blot_error::Error.none {return 0,err;}
  let signature,err=self_.invocationBinary(lv,rv,result);if err!=blot_error::Error.none {return 0,err;}
  let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:lv, kind:blot_check_types::ObligationKind.dispatch, source:id, name:0, result:result, other:rv, signature:signature, operator:op_kind, .. }, owner:self_.current, direct:true, .. });
  return result,err;
 }
 let point=blot_parse_source_operators::origin(self_.tree,id);self_.diagnostics.push(Diagnostic{ code:Code.unknown_operator, span:blot_parse_ast::Span{point,point, ..}, node:id, symbol:node.a, .. });return self_.types.fresh();
}
fn closedArrayLocal(self_:const Engine&,resolved:u32)->bool {if !self_.execution.closed_array_locals {return false;}if !blot_check_storage_types::arrayElement(self_.types,resolved).present || !self_.types.knownClosed(resolved) {return false;}let range=self_.pendingRange([self_.current]);for index in range.start..range.end {let pending=self_.pending[index];if pending.solved || pending.covered || pending.local_scheme || pending.owner!=self_.current || (pending.declared && pending.scope!=self_.local_qualification_scope) {continue;}if pending.value.kind==blot_check_types::ObligationKind.contract {return false;}let explicit=self_.explicitRequirement(pending.value);if explicit && index<self_.local_requirements_start {continue;}if pending.method_member || explicit {return false;}}return true;}
// The new version of a rebound name. A rebinding keeps one type, so its
// value is never generalized.
recursive fn rebound(self_:Engine&,name:u32,value:u32,declaration:u32)->u32,blot_error::Error {let err=self_.solveFields();if err!=blot_error::Error.none {return 0,err;}let binding,err=self_.addBinding(Binding{name:name,declaration:declaration,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:value,scheme:blot_check_types::Scheme{root:value, ..}, ..});if err!=blot_error::Error.none {return 0,err;}self_.env.push(Entry{name,binding, ..});return binding,blot_error::Error.none;}
recursive fn local(self_:Engine&,name:u32,value:u32,declaration:u32)->u32,blot_error::Error {let err=self_.solveFields();if err!=blot_error::Error.none {return 0,err;}let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return 0,err;}let tag=self_.types.node(resolved).tag;var qualified=false;for boundary in self_.qualifications {if boundary.scope==self_.local_qualification_scope {qualified=true;break;}}if !qualified && (tag==blot_check_types::Tag.unit || tag==blot_check_types::Tag.boolean || tag==blot_check_types::Tag.unsigned32 || tag==blot_check_types::Tag.floating32 || tag==blot_check_types::Tag.never) {let binding,err=self_.addBinding(Binding{name:name,declaration:declaration,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:resolved,scheme:blot_check_types::Scheme{root:resolved, ..}, ..});if err!=blot_error::Error.none {return 0,err;}self_.env.push(Entry{name,binding, ..});return binding,blot_error::Error.none;}if !qualified && self_.closedArrayLocal(resolved) {let binding,err=self_.addBinding(Binding{name:name,declaration:declaration,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:value,scheme:blot_check_types::Scheme{root:resolved, ..}, ..});if err!=blot_error::Error.none {return 0,err;}self_.env.push(Entry{name,binding, ..});self_.frontend_work.closed_array_locals+=1;return binding,blot_error::Error.none;}let excluded,err=self_.environmentFree();if err!=blot_error::Error.none {return 0,err;}let principal,error=self_.scheme(value,excluded,[self_.current],false,self_.current,self_.local_qualification_scope);equation_type_ids.free_slice(excluded);if error!=blot_error::Error.none {return 0,error;}let binding,err=self_.addBinding(Binding{name:name,declaration:declaration,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:value,scheme:principal, ..});if err!=blot_error::Error.none {return 0,err;}self_.env.push(Entry{name,binding, ..});return binding,blot_error::Error.none;}
// The value restriction: only a written function is generalized.
fn functionValue(self_:const Engine&,id:u32)->bool {var source=id;while self_.tree.node(source).tag==blot_parse_ast::tag_group {source=self_.tree.node(source).a;}return self_.tree.node(source).tag==blot_parse_ast::tag_lambda;}
recursive fn templateValue(self_:const Engine&,id:u32)->bool {let node=self_.tree.node(id);match node.tag {blot_parse_ast::tag_lambda,blot_parse_ast::tag_constructor_ref=>{return true;},blot_parse_ast::tag_group=>{return self_.templateValue(node.a);},blot_parse_ast::tag_name,blot_parse_ast::tag_field_access=>{let binding=self_.resolved[id];if binding==0 {return self_.operation_refs[id]!=0;}let kind=self_.bindings[binding].kind;return kind==blot_reuse_principal_interface::Kind.global || kind==blot_reuse_principal_interface::Kind.external;},_=>{return self_.operation_refs[id]!=0;},}}
fn blockComputedRequirements(self_:Engine&,start:i64,qualified:bool)->blot_error::Error {var explicit=false;for pending in self_.pending[start..] {if pending.owner==self_.current && pending.scope==self_.qualification_scope && !pending.solved && !pending.covered && self_.explicitRequirement(pending.value) {explicit=true;break;}}if !explicit {return blot_error::Error.none;}var parts=IdBuffer{..};let error=blockComputedWork(self_,start,qualified,parts);parts.deinit(equation_type_ids);return error;}
fn blockComputedWork(self_:Engine&,start:i64,qualified:bool,parts:IdBuffer&)->blot_error::Error {for pending in self_.pending[start..] {if pending.owner!=self_.current || pending.scope!=self_.qualification_scope || pending.solved || pending.covered || (qualified && !pending.declared) {continue;}parts.clear();let err=self_.requirementParts(pending.value,parts);if err!=blot_error::Error.none {return err;}for part in parts.items {let values,err=self_.types.freeVariables(part);if err!=blot_error::Error.none {return err;}for variable in values {if !inList(self_.computed_variables,variable) {self_.computed_variables.push(variable);}}let rows,err=self_.types.freeRowVariables(part);if err!=blot_error::Error.none {return err;}for row in rows {if !inList(self_.computed_rows,row) {self_.computed_rows.push(row);}}}}return blot_error::Error.none;}
recursive fn definitelyPanic(self_:const Engine&,id:u32,depth:i64)->bool {if id==0 || depth>=1024 {return false;}let node=self_.tree.node(id);match node.tag {blot_parse_ast::tag_group=>{return self_.definitelyPanic(node.a,depth+1);},blot_parse_ast::tag_apply=>{return self_.tree.node(node.a).tag==blot_parse_ast::tag_intrinsic && self_.pool.get(self_.tree.node(node.a).a)=="@panic";},blot_parse_ast::tag_if_expr=>{return self_.definitelyPanic(node.a,depth+1) || (self_.definitelyPanic(node.b,depth+1) && self_.definitelyPanic(node.c,depth+1));},blot_parse_ast::tag_case_expr=>{let inputs=checkedAstRange(self_.tree,node.a,node.a+2);let ast_walk_29_source=blot_parse_ast::List{self_.tree.list(inputs)[0],self_.tree.list(inputs)[1], ..};let ast_walk_29_count=self_.tree.list(ast_walk_29_source).len;for ast_walk_29_index in 0..ast_walk_29_count {let input=self_.tree.list(ast_walk_29_source)[ast_walk_29_index];if self_.definitelyPanic(input,depth+1) {return true;}}let ast_walk_30_source=blot_parse_ast::List{node.b,node.c, ..};let ast_walk_30_count=self_.tree.list(ast_walk_30_source).len;for ast_walk_30_index in 0..ast_walk_30_count {let arm=self_.tree.list(ast_walk_30_source)[ast_walk_30_index];let metadata=checkedAstRange(self_.tree,self_.tree.node(arm).c,self_.tree.node(arm).c+2);if !self_.definitelyPanic(self_.tree.list(metadata)[1],depth+1) {return false;}}return true;},_=>{return false;},}}
recursive fn letStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let type_scope=self_.type_env.items.len;let row_scope=self_.row_env.items.len;let annotation_binding=self_.annotation_binding;let inherited_types=self_.inherited_types;let inherited_rows=self_.inherited_rows;let qualification=self_.qualification_scope;let computed_values=self_.computed_variables.len;let computed_rows=self_.computed_rows.len;let local_qualification=self_.local_qualification_scope;let local_requirements=self_.local_requirements_start;let result,error=letStatementBody(self_,id);self_.type_env.resize(type_scope);self_.row_env.resize(row_scope);self_.annotation_binding=annotation_binding;self_.inherited_types=inherited_types;self_.inherited_rows=inherited_rows;self_.qualification_scope=qualification;self_.computed_variables.resize(computed_values);self_.computed_rows.resize(computed_rows);self_.local_qualification_scope=local_qualification;self_.local_requirements_start=local_requirements;return result,error;}
recursive fn letStatementBody(self_:Engine&,id:u32)->Flow,blot_error::Error {let written=self_.tree.binding(id);let computation_scope=self_.computation_annotations.len;if written.where_node!=0 {self_.qualification_scope=id;}self_.annotation_binding=id;self_.inherited_types=self_.type_env.items.len;self_.inherited_rows=self_.row_env.items.len;for source in [written.annotation,written.where_node,written.value,written.fallback] {let err=self_.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return Flow{..},err;}}var required:u32=0;if written.annotation!=0 {let root,err=self_.annotation(written.annotation);if err!=blot_error::Error.none {return Flow{..},err;}required=root;}let qualification_index=self_.qualifications.len;let requirement_start=self_.pending.len;let err=self_.beginQualification(id,written.where_node,written.annotation,written.value);if err!=blot_error::Error.none {return Flow{..},err;}var contextual:u32=0;if required!=0 {if blot_check_storage_types::isArray(self_.types,self_.types.head(required,0)) || self_.effectFamilyNominal(required).present {contextual=required;}}let inferred,err=self_.pureExpression(written.value,contextual);if err!=blot_error::Error.none {return Flow{..},err;}if required!=0 {let err=self_.constrain(inferred,required,id);if err!=blot_error::Error.none {return Flow{..},err;}}var value=inferred;if required!=0 {value=required;}if written.where_node!=0 {let err=self_.checkQualification(qualification_index);if err!=blot_error::Error.none {return Flow{..},err;}}if written.annotation!=0 || written.where_node!=0 {self_.computation_annotations.resize(computation_scope);}if !self_.templateValue(written.value) {
    if written.where_node==0 {
        let err=self_.inferComputedResultOperands(requirement_start,value);
        if err!=blot_error::Error.none {return Flow{..},err;}
    }
    let err=self_.blockComputedRequirements(requirement_start,written.where_node!=0);
    if err!=blot_error::Error.none {return Flow{..},err;}
}let root,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return Flow{..},err;}let exits=self_.types.node(root).tag==blot_check_types::Tag.never;let scope=self_.env.len;self_.local_qualification_scope=0;if written.where_node!=0 {self_.local_qualification_scope=id;}self_.local_requirements_start=requirement_start;var generalize=written.fallback==0 && self_.tree.node(written.pattern).tag==blot_parse_ast::tag_pattern_name && self_.functionValue(written.value) && comptime_binder_len==0;if generalize {let holds,err=self_.holdsStorage(value,0);if err!=blot_error::Error.none {return Flow{..},err;}if holds {let resolved,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return Flow{..},err;}if !self_.types.knownClosed(resolved) {generalize=false;}}}if !generalize && written.fallback==0 && self_.tree.node(written.pattern).tag==blot_parse_ast::tag_pattern_name {let ferr=self_.solveFields();if ferr!=blot_error::Error.none {return Flow{..},ferr;}}let saved=self_.let_pattern_source;self_.let_pattern_source=id;let total,error=self_.pattern(written.pattern,value,scope,[],generalize);self_.let_pattern_source=saved;if error!=blot_error::Error.none {return Flow{..},error;}
 if written.fallback!=0 {let success=global_entry_runs.alloc_slice(self_.env.len);for entry,index in self_.env {success[index]=entry;}self_.env.resize(scope);let flow,error=self_.suite(written.fallback);if error!=blot_error::Error.none {if success.len!=0 {global_entry_runs.free_slice(success);}return Flow{..},error;}if !flow.exits {let err=self_.diagnostic(Code.guard_fallthrough,id);if err!=blot_error::Error.none {if success.len!=0 {global_entry_runs.free_slice(success);}return Flow{..},err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.diagnostics[self_.diagnostics.len-1].span.start;}self_.env.clear();self_.env.append(success);if success.len!=0 {global_entry_runs.free_slice(success);}}
 if !total && written.fallback==0 {let err=self_.diagnostic(Code.non_exhaustive_match,id);if err!=blot_error::Error.none {return Flow{..},err;}self_.diagnostics[self_.diagnostics.len-1].span.end=self_.diagnostics[self_.diagnostics.len-1].span.start;}self_.resolved[id]=self_.resolved[written.pattern];if self_.resolved[id]!=0 && self_.tree.node(written.pattern).tag==blot_parse_ast::tag_pattern_name {var source=written.value;while self_.tree.node(source).tag==blot_parse_ast::tag_group {source=self_.tree.node(source).a;}self_.bindings[self_.resolved[id]].operation_ref=self_.operation_refs[source];}self_.expr_types[id]=blot_check_types::unit;if exits {self_.expr_types[id]=blot_check_types::never;}return Flow{exits:exits,breaks:exits, ..},blot_error::Error.none;}
fn deadRebindings(self_:Engine&,scope:i64,first_binding:i64,carried:i64)->blot_error::Error {for entry,offset in self_.env[scope..] {let index=scope+offset;if entry.name==self_.self_name {continue;}let binding=self_.bindings[entry.binding];if binding.predecessor==0 || binding.read {continue;}var writes_storage=false;for version in self_.bindings[first_binding..] {if version.name!=entry.name || version.declaration>=self_.rebindings.len || self_.rebindings[version.declaration].path.len==0 {continue;}let selectors=checkedTypeList(self_.types,self_.access_nodes[version.declaration]);let path_types=checkedTypeList(self_.types,self_.access_types[version.declaration]);let type_span_107=selectors;for part in 0..(type_span_107.len as i64) {let access=self_.types.list(type_span_107)[part];if self_.tree.node(access).tag!=blot_parse_ast::tag_index_access || part>=(path_types.len as i64) {continue;}let owner=self_.types.head(self_.types.list(path_types)[part],0);if self_.types.node(owner).tag==blot_check_types::Tag.array {writes_storage=true;break;}let storage=blot_check_storage_types::info(self_.types,owner);if storage.present && storage.value.kind==blot_check_storage_types::sized_array {writes_storage=true;break;}}if writes_storage {break;}}if writes_storage {continue;}var last=true;for next in self_.env[index+1..] {if next.name==entry.name {last=false;break;}}if !last {continue;}var root=binding.predecessor;var enclosing=false;for step in 0..64 {if root==0 {break;}for prior in self_.env[carried..scope] {if prior.binding==root {enclosing=true;break;}}if enclosing {break;}root=self_.bindings[root].predecessor;}if !enclosing {continue;}var read=false;for version in self_.bindings[first_binding..] {if version.name==entry.name && version.read {read=true;break;}}if !read {let err=self_.diagnostic(Code.dead_rebinding,binding.declaration);if err!=blot_error::Error.none {return err;}}}return blot_error::Error.none;}
recursive fn rebindStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let node=self_.tree.node(id);if self_.tree.node(node.a).tag!=blot_parse_ast::tag_name {return self_.rebindFields(id);}let name=self_.tree.node(node.a).a;let previous=self_.lookup(name);if !previous.present {let err=self_.diagnostic(Code.unknown_rebinding,id);return Flow{..},err;}if isOuterSparkBinding(self_,name) {let err=self_.diagnostic(Code.spark_capture,id);return Flow{..},err;}if isWithLocked(previous.value) {let err=self_.diagnostic(Code.borrow_conflict,id);return Flow{..},err;}let with_outer=self_.findWithOuterTarget(previous.value);let scope=self_.env.len;self_.env.push(Entry{self_.self_name,previous.value, ..});let value,error=self_.pureExpression(node.b,0);if error!=blot_error::Error.none {self_.env.resize(scope);return Flow{..},error;}removeSelfEntry(self_,scope);if with_outer!=0 {let cerr=self_.constrain(self_.bindings[with_outer].ty,value,id);if cerr!=blot_error::Error.none {return Flow{..},cerr;}recordWithShadowed(with_outer);self_.projection_resolved[id]=with_outer;}let latest_prev=self_.latestSuccessor(previous.value);let binding,err=self_.rebound(name,value,id);if err!=blot_error::Error.none {return Flow{..},err;}self_.bindings[binding].predecessor=latest_prev;if with_outer!=0 {self_.bindings[binding].read=true;}self_.resolved[id]=binding;self_.resolved[node.a]=previous.value;self_.expr_types[node.a]=self_.bindings[previous.value].ty;let root,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return Flow{..},err;}let exits=root==blot_check_types::never;self_.expr_types[id]=blot_check_types::unit;if exits {self_.expr_types[id]=blot_check_types::never;}return Flow{exits:exits,breaks:exits, ..},blot_error::Error.none;}
recursive fn returnStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let node=self_.tree.node(id);if self_.arm_block!=0 && self_.owner==self_.arm_block && self_.arm_nested_return==0 && !inList(self_.tree.children(self_.arm_block),id) {self_.arm_nested_return=id;}var value:u32=0;if self_.return_target!=0 && (blot_check_storage_types::isArray(self_.types,self_.types.head(self_.return_target,0)) || self_.effectFamilyNominal(self_.return_target).present) {let result,err=self_.contextualLambda(node.a,self_.return_target);if err!=blot_error::Error.none {return Flow{..},err;}value=result;}else {let result,err=self_.expression(node.a);if err!=blot_error::Error.none {return Flow{..},err;}value=result;}
 if node.b!=0 {let err=self_.diagnostic(Code.resolver_required,id);if err!=blot_error::Error.none {return Flow{..},err;}}if self_.return_target==0 {let err=self_.diagnostic(Code.return_outside_block,id);if err!=blot_error::Error.none {return Flow{..},err;}}else {let err=self_.constrain(self_.return_target,value,id);if err!=blot_error::Error.none {return Flow{..},err;}}self_.expr_types[id]=blot_check_types::never;
 for i in 0..comptime_binder_len {
  let builder=comptime_binders[i].builder;
  if builder.node!=0 && builder.node==self_.owner && builder.carries.len!=0 {
   var versions=IdBuffer{..};
   let err=recordLoopExit(self_,id,builder,versions,true);
   versions.deinit(equation_type_ids);
   if err!=blot_error::Error.none {return Flow{..},err;}
   break;
  }
 }
 return Flow{ty:blot_check_types::never,exits:true,returns:true, ..},blot_error::Error.none;}

recursive fn functionReturnStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let operand=self_.tree.node(id).a;var value:u32=0;if self_.function_result_expected!=0 {let ty,err=self_.contextualLambda(operand,self_.function_result_expected);if err!=blot_error::Error.none {return Flow{..},err;}value=ty;}else {let ty,err=self_.expression(operand);if err!=blot_error::Error.none {return Flow{..},err;}value=ty;}if !self_.function_exit_allowed {let err=self_.diagnostic(Code.return_outside_function,id);if err!=blot_error::Error.none {return Flow{..},err;}}else {if self_.function_exit_target==0 {let fresh,err=self_.types.fresh();if err!=blot_error::Error.none {return Flow{..},err;}self_.function_exit_target=fresh;}let err=self_.constrain(self_.function_exit_target,value,id);if err!=blot_error::Error.none {return Flow{..},err;}}self_.expr_types[id]=blot_check_types::never;return Flow{ty:blot_check_types::never,exits:true,breaks:true, ..},blot_error::Error.none;}
recursive fn useStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let node=self_.tree.node(id);let value,err=self_.expression(node.b);if err!=blot_error::Error.none {return Flow{..},err;}if node.c!=0 {let required,err=self_.annotation(node.c);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(value,required,id);if err!=blot_error::Error.none {return Flow{..},err;}}if node.a!=0 {let binding,err=self_.addBinding(Binding{name:node.a,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:value,scheme:blot_check_types::Scheme{root:value, ..}, ..});if err!=blot_error::Error.none {return Flow{..},err;}self_.env.push(Entry{node.a,binding, ..});self_.resolved[id]=binding;}self_.expr_types[id]=blot_check_types::unit;return Flow{..},blot_error::Error.none;}
recursive fn comptimeForStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {
 let node=self_.tree.node(id);
 let body=self_.tree.extra.items[node.c];
 let mode=self_.tree.extra.items[node.c+1];
 var field_var:u32=0;
 if mode==2 {
  if !self_.function_exit_allowed {
   let err=self_.diagnostic(Code.unsupported,id);
   return Flow{..},err;
  }
  let fv,err=self_.types.fresh();
  if err!=blot_error::Error.none {return Flow{..},err;}
  field_var=fv;
 }
 let target_ty,terr=self_.annotation(node.b);
 if terr!=blot_error::Error.none { return Flow{..},terr; }
 let oerr=self_.checkOpaqueNominal(target_ty,node.b);
 if oerr!=blot_error::Error.none { return Flow{..},oerr; }
 let binder_b,berr=self_.addBinding(Binding{name:node.a,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:target_ty,scheme:blot_check_types::Scheme{root:target_ty, ..}, ..});
 if berr!=blot_error::Error.none { return Flow{..},berr; }
 self_.resolved[id]=binder_b;
 var work=LoopWork{..};
 let cerr=collectLoopCarries(self_,0,body,work);
 if cerr!=blot_error::Error.none { work.deinit(); return Flow{..},cerr; }
 saveLoopBase(self_,work);
 for incoming in work.carries.items {
  let ty=self_.bindings[incoming.binding].ty;
  let iteration,ierr=self_.addBinding(Binding{name:incoming.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..},predecessor:incoming.binding, ..});
  if ierr!=blot_error::Error.none { self_.env.clear(); self_.env.append(work.base); work.deinit(); return Flow{..},ierr; }
  let aerr=work.iterations.append(iteration);
  if aerr!=blot_error::Error.none { self_.env.clear(); self_.env.append(work.base); work.deinit(); return Flow{..},aerr; }
  self_.env.push(Entry{incoming.name,iteration, ..});
 }
 let saved_b=comptime_binder_len;
 let saved_owner=self_.owner;
 let saved_target=self_.return_target;
 var binder=ComptimeBinder{name:node.a,binding:binder_b,target_ty:target_ty,is_variants:mode==1, ..};
 if mode==2 {
  binder.builder=LoopFrame{node:id,carries:work.carries.items,iterations:work.iterations.items, ..};
  recordComptimeFieldVar(self_,field_var);
  self_.owner=id;
  self_.return_target=field_var;
 }
 if comptime_binder_len<32 {
  comptime_binders[comptime_binder_len]=binder;
  comptime_binder_depth[comptime_binder_len]=comptime_lambda_depth;
  comptime_binder_len+=1;
 }
 let flow,ferr=self_.suite(body);
 comptime_binder_len=saved_b;
 self_.owner=saved_owner;
 self_.return_target=saved_target;
 if ferr!=blot_error::Error.none { self_.env.clear(); self_.env.append(work.base); work.deinit(); return Flow{..},ferr; }
 if mode==2 {
  if !flow.exits {
   let err=self_.constrain(field_var,blot_check_types::unit,id);
   if err!=blot_error::Error.none {self_.env.clear();self_.env.append(work.base);work.deinit();return Flow{..},err;}
  }
  self_.expr_types[body]=field_var;
 }
 for iteration in work.iterations.items {
  let backedge=self_.latestSuccessor(iteration);
  let aerr=work.backedges.append(backedge);
  if aerr!=blot_error::Error.none { self_.env.clear(); self_.env.append(work.base); work.deinit(); return Flow{..},aerr; }
  let uerr=self_.constrain(self_.bindings[iteration].ty,self_.bindings[backedge].ty,id);
  if uerr!=blot_error::Error.none { self_.env.clear(); self_.env.append(work.base); work.deinit(); return Flow{..},uerr; }
 }
 self_.env.clear();
 self_.env.append(work.base);
 let start=self_.loop_carries.len;
 for incoming,index in work.carries.items {
  let ty=self_.bindings[incoming.binding].ty;
  let outgoing,oerr=self_.addBinding(Binding{name:incoming.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..},predecessor:incoming.binding, ..});
  if oerr!=blot_error::Error.none { work.deinit(); return Flow{..},oerr; }
  self_.env.push(Entry{incoming.name,outgoing, ..});
  self_.loop_carries.push(LoopCarry{node:id,incoming:incoming.binding,iteration:work.iterations.items[index],backedge:work.backedges.items[index],outgoing:outgoing, ..});
 }
 if start>0xffffffff || work.carries.items.len>0xffffffff { work.deinit(); return Flow{..},blot_error::Error.type_limit; }
 self_.loop_ranges[id]=blot_check_types::List{start as u32,work.carries.items.len as u32, ..};
 self_.expr_types[id]=blot_check_types::unit;
 if mode==2 {self_.expr_types[id]=target_ty;}
 work.deinit();
 return Flow{exits:false,returns:flow.returns, ..},blot_error::Error.none;
}
recursive fn statement(self_:Engine&,id:u32)->Flow,blot_error::Error {match self_.tree.node(id).tag {blot_parse_ast::tag_let_stmt=>{return self_.letStatement(id);},blot_parse_ast::tag_rebind_stmt=>{return self_.rebindStatement(id);},blot_parse_ast::tag_return_stmt=>{return self_.returnStatement(id);},blot_parse_ast::tag_function_return_stmt=>{return self_.functionReturnStatement(id);},blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{return self_.useStatement(id);},blot_parse_ast::tag_forever_stmt,blot_parse_ast::tag_range_stmt,blot_parse_ast::tag_for_stmt=>{return self_.loopStatement(id);},blot_parse_ast::tag_break_stmt=>{return self_.breakStatement(id);},blot_parse_ast::tag_continue_stmt=>{return self_.continueStatement(id);},blot_parse_ast::tag_if_stmt,blot_parse_ast::tag_if_let_stmt,blot_parse_ast::tag_comptime_if=>{return self_.conditional(id);},blot_parse_ast::tag_with_stmt=>{return self_.withStatement(id);},blot_parse_ast::tag_comptime_for=>{return self_.comptimeForStatement(id);},blot_parse_ast::tag_case_expr=>{return self_.caseStatement(id);},_=>{let ty,err=self_.expression(id);if err!=blot_error::Error.none {return Flow{..},err;}let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return Flow{..},err;}let exits=self_.types.node(root).tag==blot_check_types::Tag.never;return Flow{exits:exits,breaks:exits, ..},blot_error::Error.none;},}}
recursive fn caseStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let saved=self_.statement_case;self_.statement_case=id;let ty,error=self_.expression(id);self_.statement_case=saved;if error!=blot_error::Error.none {return Flow{..},error;}let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return Flow{..},err;}let exits=self_.types.node(root).tag==blot_check_types::Tag.never;return Flow{exits:exits,breaks:exits, ..},blot_error::Error.none;}
recursive fn suite(self_:Engine&,id:u32)->Flow,blot_error::Error {var result=Flow{..};var direct_exit=false;let syntax_source_46=id;let syntax_count_46=self_.tree.children(syntax_source_46).len;for syntax_index_46 in 0..syntax_count_46 {let child=self_.tree.children(syntax_source_46)[syntax_index_46];if direct_exit {let err=self_.diagnostic(Code.unreachable_statement,child);if err!=blot_error::Error.none {return Flow{..},err;}}let flow,err=self_.statement(child);if err!=blot_error::Error.none {return Flow{..},err;}if !result.exits {result.returns=result.returns || flow.returns;result.breaks=result.breaks || flow.breaks;}result.exits=result.exits || flow.exits;let tag=self_.tree.node(child).tag;direct_exit=direct_exit || tag==blot_parse_ast::tag_return_stmt || tag==blot_parse_ast::tag_function_return_stmt || tag==blot_parse_ast::tag_break_stmt || tag==blot_parse_ast::tag_continue_stmt;}self_.expr_types[id]=blot_check_types::unit;if result.exits {self_.expr_types[id]=blot_check_types::never;}return result,blot_error::Error.none;}
fn flowsFrom(self_:const Engine&,initial:u32,original:u32)->bool {var binding=initial;var steps:i64=0;while binding!=0 && steps<self_.bindings.len {if binding==original {return true;}binding=self_.bindings[binding].predecessor;steps+=1;}return false;}
fn latestSuccessor(self_:const Engine&,original:u32)->u32 {let name=self_.bindings[original].name;var index=self_.env.len;while index!=0 {index-=1;let entry=self_.env[index];if entry.name==name && self_.flowsFrom(entry.binding,original) {return entry.binding;}}return original;}
struct LoopWork {base:Entry[:]=default<Entry[:]>(),carries:blot_support_pooled_buffer::Buffer<Entry> =blot_support_pooled_buffer::Buffer<Entry>{},iterations:IdBuffer=IdBuffer{..},backedges:IdBuffer=IdBuffer{..}}
fn deinit(self_:LoopWork&) {if self_.base.len!=0 {global_entry_runs.free_slice(self_.base);}self_.carries.deinit(global_entry_runs);self_.iterations.deinit(equation_type_ids);self_.backedges.deinit(equation_type_ids);}
fn collectLoopCarries(self_:Engine&,pattern:u32,body:u32,work:LoopWork&)->blot_error::Error {let targets,error=blot_backend_loop_targets::collect(self_.tree,self_.pool,pattern,body);if error!=blot_error::Error.none {if error==blot_error::Error.target_limit {return blot_error::Error.type_limit;}return error;}var result=blot_error::Error.none;for name in targets {let binding=self_.lookup(name);if binding.present {let err=work.carries.push(Entry{name,binding.value, ..},global_entry_runs);if err!=blot_error::Error.none {result=err;break;}}}blot_backend_loop_targets::release(targets);return result;}
fn saveLoopBase(self_:Engine&,work:LoopWork&) {work.base=global_entry_runs.alloc_slice(self_.env.len);for entry,index in self_.env {work.base[index]=entry;}}
recursive fn iteratorStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {let expansion=self_.tree.extra.items[self_.tree.node(id).c+3];let base=global_entry_runs.alloc_slice(self_.env.len);for entry,index in self_.env {base[index]=entry;}self_.iterator_bodies[id]=expansion;let flow,error=self_.suite(expansion);if error!=blot_error::Error.none {if base.len!=0 {global_entry_runs.free_slice(base);}return Flow{..},error;}for &entry in base {entry.binding=self_.latestSuccessor(entry.binding);}self_.env.clear();self_.env.append(base);if base.len!=0 {global_entry_runs.free_slice(base);}self_.expr_types[id]=blot_check_types::unit;if flow.exits {self_.expr_types[id]=blot_check_types::never;}return flow,blot_error::Error.none;}
recursive fn loopStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {if self_.depth>=1024 {return Flow{..},blot_error::Error.type_limit;}self_.depth+=1;let node=self_.tree.node(id);let result,error=loopStatementDispatch(self_,id,node);self_.depth-=1;return result,error;}
recursive fn loopStatementDispatch(self_:Engine&,id:u32,node:blot_parse_ast::Node)->Flow,blot_error::Error {var pattern:u32=0;var body=node.a;var element=blot_check_types::u32_type;if node.tag==blot_parse_ast::tag_range_stmt {let first,err=self_.expression(node.a);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(first,blot_check_types::u32_type,node.a);if err!=blot_error::Error.none {return Flow{..},err;}let last,err=self_.expression(node.b);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(last,blot_check_types::u32_type,node.b);if err!=blot_error::Error.none {return Flow{..},err;}body=node.c;}else if node.tag==blot_parse_ast::tag_for_stmt {let parts=checkedAstRange(self_.tree,node.c,node.c+3);pattern=node.a;body=self_.tree.list(parts)[1];let value,err=self_.expression(node.b);if err!=blot_error::Error.none {return Flow{..},err;}if self_.tree.list(parts)[0]!=0 {let err=self_.constrain(value,blot_check_types::u32_type,node.b);if err!=blot_error::Error.none {return Flow{..},err;}let last,err=self_.expression(self_.tree.list(parts)[0]);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(last,blot_check_types::u32_type,self_.tree.list(parts)[0]);if err!=blot_error::Error.none {return Flow{..},err;}}else {let source,err=self_.types.resolve(value,0);if err!=blot_error::Error.none {return Flow{..},err;}let item=blot_check_storage_types::readableElement(self_.types,source);if item.present {element=item.value;}else {return self_.iteratorStatement(id);}}}
 var work=LoopWork{..};let stack=self_.loop_stack.len;var published=false;let flow,error=loopStatementBody(self_,id,node,pattern,body,element,work,published);self_.loop_stack.resize(stack);if !published && work.base.len!=0 {self_.env.clear();self_.env.append(work.base);}work.deinit();return flow,error;}
recursive fn loopStatementBody(self_:Engine&,id:u32,node:blot_parse_ast::Node,pattern:u32,body:u32,element:u32,work:LoopWork&,published:bool&)->Flow,blot_error::Error {let err=collectLoopCarries(self_,pattern,body,work);if err!=blot_error::Error.none {return Flow{..},err;}saveLoopBase(self_,work);for incoming in work.carries.items {let ty=self_.bindings[incoming.binding].ty;let iteration,err=self_.addBinding(Binding{name:incoming.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..},predecessor:incoming.binding, ..});if err!=blot_error::Error.none {return Flow{..},err;}let err=work.iterations.append(iteration);if err!=blot_error::Error.none {return Flow{..},err;}self_.env.push(Entry{incoming.name,iteration, ..});}let stack_mark=self_.loop_stack.len;self_.loop_stack.push(canonicalLoop(LoopFrame{node:id,carries:work.carries.items,iterations:work.iterations.items, ..}));if pattern!=0 {let total,err=self_.pattern(pattern,element,self_.env.len,[],false);if err!=blot_error::Error.none {return Flow{..},err;}if !total {let err=self_.diagnostic(Code.non_exhaustive_match,pattern);if err!=blot_error::Error.none {return Flow{..},err;}}}let flow,err=self_.suite(body);if err!=blot_error::Error.none {return Flow{..},err;}let breaks=self_.loop_stack[stack_mark].exits;for iteration in work.iterations.items {let backedge=self_.latestSuccessor(iteration);let err=work.backedges.append(backedge);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(self_.bindings[iteration].ty,self_.bindings[backedge].ty,id);if err!=blot_error::Error.none {return Flow{..},err;}}self_.env.clear();self_.env.append(work.base);let start=self_.loop_carries.len;for incoming,index in work.carries.items {let ty=self_.bindings[incoming.binding].ty;let outgoing,err=self_.addBinding(Binding{name:incoming.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..},predecessor:incoming.binding, ..});if err!=blot_error::Error.none {return Flow{..},err;}self_.env.push(Entry{incoming.name,outgoing, ..});self_.loop_carries.push(LoopCarry{node:id,incoming:incoming.binding,iteration:work.iterations.items[index],backedge:work.backedges.items[index],outgoing:outgoing, ..});}if start>0xffffffff || work.carries.items.len>0xffffffff {return Flow{..},blot_error::Error.type_limit;}self_.loop_ranges[id]=blot_check_types::List{start as u32,work.carries.items.len as u32, ..};self_.expr_types[id]=blot_check_types::unit;published=true;let forever_exits=node.tag==blot_parse_ast::tag_forever_stmt && breaks==0;return Flow{exits:forever_exits,breaks:forever_exits,returns:flow.returns, ..},blot_error::Error.none;}
recursive fn breakStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {return self_.loopExitStatement(id,false);}
recursive fn continueStatement(self_:Engine&,id:u32)->Flow,blot_error::Error {return self_.loopExitStatement(id,true);}
recursive fn loopExitStatement(self_:Engine&,id:u32,continues:bool)->Flow,blot_error::Error {self_.expr_types[id]=blot_check_types::never;if self_.loop_stack.len==0 {var code=Code.break_scope;if continues {code=Code.continue_scope;}let err=self_.diagnostic(code,id);return Flow{exits:true,breaks:true, ..},err;}let index=self_.loop_stack.len-1;let frame=self_.loop_stack[index];var current=IdBuffer{..};let result,error=loopExitBindings(self_,id,continues,index,frame,current);current.deinit(equation_type_ids);return result,error;}
recursive fn loopExitBindings(self_:Engine&,id:u32,continues:bool,frame_index:i64,frame:LoopFrame,current:IdBuffer&)->Flow,blot_error::Error {
 let err=recordLoopExit(self_,id,frame,current,false);
 if err!=blot_error::Error.none {return Flow{..},err;}
 if !continues {self_.loop_stack[frame_index].exits+=1;}
 return Flow{exits:true,breaks:true, ..},blot_error::Error.none;
}
fn recordLoopExit(self_:Engine&,id:u32,frame:LoopFrame,current:IdBuffer&,builder:bool)->blot_error::Error {for carry,index in frame.carries {let iteration=frame.iterations[index];var binding=self_.latestSuccessor(iteration);if !builder {let found=self_.lookup(carry.name);if found.present {binding=found.value;}}let err=current.append(binding);if err!=blot_error::Error.none {return err;}let err=self_.constrain(self_.bindings[iteration].ty,self_.bindings[binding].ty,id);if err!=blot_error::Error.none {return err;}}let bindings,err=self_.types.saveList(current.items);if err!=blot_error::Error.none {return err;}self_.loop_exits.push(LoopExit{node:id,loop_:frame.node,bindings:bindings, ..});return blot_error::Error.none;}

recursive fn updatedFieldType(self_:Engine&,original:u32,name:u32,assigned:u32,source:u32)->blot_support::Option<u32>,blot_error::Error {let owner,err=self_.types.resolve(original,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let node=self_.types.node(owner);if node.tag==blot_check_types::Tag.variable {return blot_support::none<u32>(),blot_error::Error.none;}if node.tag==blot_check_types::Tag.record {var fields=FieldBuffer{..};var found=false;for index in 0..node.b {var field=self_.types.recordField(node,index);if field.name==name {field.ty=assigned;found=true;}let err=fields.append(field);if err!=blot_error::Error.none {fields.deinit(equation_fields);return blot_support::none<u32>(),err;}}if found {let root,error=self_.types.record(fields.items);fields.deinit(equation_fields);return blot_support::some(root),error;}fields.deinit(equation_fields);}else if node.tag==blot_check_types::Tag.nominal {let nominal=self_.nominalIndex(Identity{node.a,node.b, ..});if !nominal.present {let root,error=self_.diagnosticFresh(Code.missing_field,source);return blot_support::some(root),error;}let constructors=equation_type_ids.alloc_slice(self_.nominals[nominal.value].constructors.len);let type_span_108=checkedTypeList(self_.types,self_.nominals[nominal.value].constructors);for index in 0..(type_span_108.len as i64) {let constructor=self_.types.list(type_span_108)[index];constructors[index]=constructor;}let result,error=updatedNominalFields(self_,owner,name,assigned,source,constructors);equation_type_ids.free_slice(constructors);if error!=blot_error::Error.none || result.present {return result,error;}}let root,error=self_.diagnosticFresh(Code.missing_field,source);return blot_support::some(root),error;}
recursive fn updatedNominalFields(self_:Engine&,owner:u32,name:u32,assigned:u32,source:u32,constructors:const u32[:])->blot_support::Option<u32>,blot_error::Error {var result:u32=0;for constructor in constructors {let input_id,err=self_.constructorStorageType(constructor);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let input=self_.types.node(input_id);let output_id,err=self_.constructorStorageType(constructor);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let output=self_.types.node(output_id);if input.tag!=blot_check_types::Tag.function || output.tag!=blot_check_types::Tag.function {return blot_support::none<u32>(),blot_error::Error.none;}let err=self_.constrain(input.b,owner,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let before_id,err=self_.types.resolve(input.a,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let after_id,err=self_.types.resolve(output.a,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let before=self_.types.node(before_id);let after=self_.types.node(after_id);if before.tag!=blot_check_types::Tag.record || after.tag!=blot_check_types::Tag.record || before.b!=after.b {return blot_support::none<u32>(),blot_error::Error.none;}var found=false;for index in 0..before.b {let old=self_.types.recordField(before,index);let fresh=self_.types.recordField(after,index);if old.name!=fresh.name {return blot_support::none<u32>(),blot_error::Error.type_limit;}if old.name==name {let err=self_.constrain(fresh.ty,assigned,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}found=true;}else {let err=self_.constrain(old.ty,fresh.ty,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}}if !found {return blot_support::none<u32>(),blot_error::Error.none;}if result==0 {result=output.b;}else {let err=self_.constrain(result,output.b,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}}if result!=0 {return blot_support::some(result),blot_error::Error.none;}return blot_support::none<u32>(),blot_error::Error.none;}
struct RebindingWork {reverse:IdBuffer=IdBuffer{..},path:IdBuffer=IdBuffer{..},types:IdBuffer=IdBuffer{..}}
fn deinit(self_:RebindingWork&) {self_.reverse.deinit(equation_type_ids);self_.path.deinit(equation_type_ids);self_.types.deinit(equation_type_ids);}
recursive fn rebindFields(self_:Engine&,id:u32)->Flow,blot_error::Error {let ambient=self_.ambient;let row,err=self_.types.freshEffects();if err!=blot_error::Error.none {return Flow{..},err;}self_.ambient=row;let scope=self_.env.len;var work=RebindingWork{..};let result,error=rebindFieldsBody(self_,id,work);if error!=blot_error::Error.none {self_.env.resize(scope);}self_.ambient=ambient;work.deinit();return result,error;}
recursive fn rebindFieldsBody(self_:Engine&,id:u32,work:RebindingWork&)->Flow,blot_error::Error {let statement=self_.tree.node(id);var root=statement.a;while self_.tree.node(root).tag==blot_parse_ast::tag_field_access || self_.tree.node(root).tag==blot_parse_ast::tag_index_access || self_.tree.node(root).tag==blot_parse_ast::tag_comptime_project {if work.reverse.items.len>=1024 {return Flow{..},blot_error::Error.type_limit;}let err=work.reverse.append(root);if err!=blot_error::Error.none {return Flow{..},err;}root=self_.tree.node(root).a;}let root_node=self_.tree.node(root);if root_node.tag!=blot_parse_ast::tag_name {let err=self_.diagnostic(Code.unsupported,id);return Flow{..},err;}let found=self_.lookup(root_node.a);if !found.present {let err=self_.diagnostic(Code.unknown_rebinding,id);return Flow{..},err;}if isOuterSparkBinding(self_,root_node.a) {let err=self_.diagnostic(Code.spark_capture,id);return Flow{..},err;}let previous=found.value;if isWithLocked(previous) {let err=self_.diagnostic(Code.borrow_conflict,id);return Flow{..},err;}let with_outer=self_.findWithOuterTarget(previous);reverseWords(work.reverse.items);var first_index=work.reverse.items.len;
var reflective=false;
for access,index in work.reverse.items {
 let tag=self_.tree.node(access).tag;
 if tag==blot_parse_ast::tag_index_access && first_index==work.reverse.items.len {first_index=index;}
 if tag==blot_parse_ast::tag_comptime_project {reflective=true;}
}var ty=self_.bindings[previous].ty;let err=work.types.append(ty);if err!=blot_error::Error.none {return Flow{..},err;}let scope=self_.env.len;self_.env.push(Entry{self_.self_name,previous, ..});for access,part in work.reverse.items {let selector=self_.tree.node(access);var projection:u32=0;if selector.tag==blot_parse_ast::tag_index_access {let known,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return Flow{..},err;}let element=blot_check_storage_types::arrayElement(self_.types,self_.types.head(known,0));var child:u32=0;if element.present {child=element.value;}else {let inferred,err=self_.types.fresh();if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrainIndexed(ty,inferred,access,blot_check_storage_types::indexed_write);if err!=blot_error::Error.none {return Flow{..},err;}child=inferred;}let index,err=self_.expression(selector.b);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.constrain(index,blot_check_types::u32_type,selector.b);if err!=blot_error::Error.none {return Flow{..},err;}ty=child;}else if selector.tag==blot_parse_ast::tag_comptime_project {
 let bidx=findComptimeBinder(selector.b);
 if bidx<0 || comptime_binders[bidx].is_variants {let err=self_.diagnostic(Code.unknown_name,access);return Flow{..},err;}
 let cap,cap_err=self_.checkComptimeCapture(bidx,access);
 if cap_err!=blot_error::Error.none {return Flow{..},cap_err;}
 if cap {removeSelfEntry(self_,scope);return Flow{..},blot_error::Error.none;}
 let binder=comptime_binders[bidx];
 let storage=blot_check_storage_types::info(self_.types,self_.types.head(ty,0));
 if storage.present && !blot_check_storage_types::isSized(storage.value.kind) {
  let err=self_.diagnostic(Code.type_mismatch,access);return Flow{..},err;
 }
 let target_was_var=self_.types.node(self_.types.head(binder.target_ty,0)).tag==blot_check_types::Tag.variable;
 let err=self_.constrain(ty,binder.target_ty,access);
 if err!=blot_error::Error.none {return Flow{..},err;}
 if target_was_var {
  let oerr=self_.checkOpaqueNominal(ty,access);
  if oerr!=blot_error::Error.none {return Flow{..},oerr;}
 }
 let fv,err=self_.types.fresh();
 if err!=blot_error::Error.none {return Flow{..},err;}
 recordComptimeFieldVar(self_,fv);
 self_.resolved[access]=binder.binding;
 ty=fv;
}else {let pending_start=self_.pending.len;self_.field_path=true;let projected,err=self_.projectField(ty,selector.b,access,reflective || first_index==work.reverse.items.len || part>=first_index,blot_support::none<PendingObligation>());if err!=blot_error::Error.none {return Flow{..},err;}if !reflective && first_index==work.reverse.items.len {for &pending in self_.pending[pending_start..] {if pending.value.kind==blot_check_types::ObligationKind.writable_field && pending.value.source==access {pending.covered=true;pending.suspended=true;}}}ty=projected.ty;projection=projected.projection;}self_.expr_types[access]=ty;self_.projection_resolved[access]=projection;let err=work.path.append(projection);if err!=blot_error::Error.none {return Flow{..},err;}let err=work.types.append(ty);if err!=blot_error::Error.none {return Flow{..},err;}}
 removeSelfEntry(self_,scope);self_.resolved[root]=previous;self_.expr_types[root]=self_.bindings[previous].ty;let self_binding,err=self_.addBinding(Binding{name:self_.self_name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,scheme:blot_check_types::Scheme{root:ty, ..}, ..});if err!=blot_error::Error.none {return Flow{..},err;}let rhs_scope=self_.env.len;self_.env.push(Entry{self_.self_name,self_binding, ..});let value,err=self_.expression(statement.b);if err!=blot_error::Error.none {return Flow{..},err;}removeSelfEntry(self_,rhs_scope);var updated=value;var remaining=work.reverse.items.len;while remaining!=0 {remaining-=1;let selector=self_.tree.node(work.reverse.items[remaining]);let owner=work.types.items[remaining];if reflective || selector.tag==blot_parse_ast::tag_index_access {let err=self_.constrain(work.types.items[remaining+1],updated,id);if err!=blot_error::Error.none {return Flow{..},err;}updated=owner;}else if first_index<work.reverse.items.len {if remaining>first_index {let err=self_.constrain(work.types.items[remaining+1],updated,id);if err!=blot_error::Error.none {return Flow{..},err;}}updated=owner;}else {let replaced,err=self_.updatedFieldType(owner,selector.b,updated,work.reverse.items[remaining]);if err!=blot_error::Error.none {return Flow{..},err;}if replaced.present {updated=replaced.value;}else {let result,err=self_.types.fresh();if err!=blot_error::Error.none {return Flow{..},err;}let origin,err=self_.projectionOrigin(work.reverse.items[remaining],selector.b,false);if err!=blot_error::Error.none {return Flow{..},err;}let signature,err=self_.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,0);if err!=blot_error::Error.none {return Flow{..},err;}let err=self_.appendPending(PendingObligation{ value:blot_check_types::Obligation{ ty:owner, kind:blot_check_types::ObligationKind.update, source:work.reverse.items[remaining], name:selector.b, result:result, other:updated, signature:signature, .. }, owner:self_.current, origin:origin, .. });if err!=blot_error::Error.none {return Flow{..},err;}updated=result;}}}
 if with_outer!=0 {let cerr=self_.constrain(self_.bindings[with_outer].ty,updated,id);if cerr!=blot_error::Error.none {return Flow{..},cerr;}recordWithShadowed(with_outer);self_.projection_resolved[id]=with_outer;}
 let latest_prev=self_.latestSuccessor(previous);
 let successor,err=self_.rebound(root_node.a,updated,id);if err!=blot_error::Error.none {return Flow{..},err;}self_.bindings[successor].predecessor=latest_prev;if with_outer!=0 {self_.bindings[successor].read=true;}self_.resolved[id]=successor;self_.expr_types[id]=blot_check_types::unit;let range,err=self_.types.saveList(work.path.items);if err!=blot_error::Error.none {return Flow{..},err;}self_.rebindings[id]=Rebinding{root:latest_prev,self_binding:self_binding,path:range, ..};let types,err=self_.types.saveList(work.types.items);if err!=blot_error::Error.none {return Flow{..},err;}self_.access_types[id]=types;let nodes,err=self_.types.saveList(work.reverse.items);if err!=blot_error::Error.none {return Flow{..},err;}self_.access_nodes[id]=nodes;let error=self_.types.unifyEffects(self_.ambient,0);if error==blot_error::Error.effect_mismatch {let err=self_.diagnostic(Code.let_effect,id);return Flow{..},err;}if error==blot_error::Error.infinite_effect {let err=self_.diagnostic(Code.infinite_effect,id);return Flow{..},err;}return Flow{..},error;
}
// Whether a value of `ty` is or directly holds storage, through records and
// tuples. Unresolved and other types count as not holding it. Storage has one
// identity, so a local holding it keeps one type: its stores and reads must
// agree (tasks/MEMORY_MODEL.md rule 8).
recursive fn holdsStorage(self_:Engine&,ty:u32,depth:i64)->bool,blot_error::Error {
 if depth>8 {return false,blot_error::Error.none;}let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return false,err;}
 if blot_check_storage_types::readableElement(self_.types,resolved).present {return true,blot_error::Error.none;}let node=self_.types.node(resolved);
 if node.tag==blot_check_types::Tag.record {for index in 0..node.b {let held,err=self_.holdsStorage(self_.types.recordField(node,index).ty,depth+1);if err!=blot_error::Error.none || held {return held,err;}}return false,blot_error::Error.none;}
 if node.tag==blot_check_types::Tag.product {var items=IdBuffer{..};let err=blot_support_pooled_buffer::append(items,self_.types.list(blot_check_types::List{start:node.a,len:node.b, ..}),equation_type_ids);if err!=blot_error::Error.none {items.deinit(equation_type_ids);return false,err;}var result=false;var failure=blot_error::Error.none;for item in items.items {let held,err=self_.holdsStorage(item,depth+1);if err!=blot_error::Error.none || held {result=held;failure=err;break;}}items.deinit(equation_type_ids);return result,failure;}
 return false,blot_error::Error.none;
}
recursive fn conditional(self_:Engine&,id:u32)->Flow,blot_error::Error {let node=self_.tree.node(id);let patterned=node.tag==blot_parse_ast::tag_if_let_stmt;var source=node.a;if patterned {source=node.b;}let subject,err=self_.expression(source);if err!=blot_error::Error.none {return Flow{..},err;}if !patterned {let err=self_.constrain(subject,blot_check_types::boolean,node.a);if err!=blot_error::Error.none {return Flow{..},err;}}var bodies:u32[2]=[node.b,node.c];if patterned {bodies=[self_.tree.extra.items[node.c],self_.tree.extra.items[node.c+1]];}let base=global_entry_runs.alloc_slice(self_.env.len);for entry,index in self_.env {base[index]=entry;}let left=equation_type_ids.alloc_slice(base.len);let right=equation_type_ids.alloc_slice(base.len);let result,error=conditionalBody(self_,id,node,patterned,subject,bodies,base,left,right);if right.len!=0 {equation_type_ids.free_slice(right);}if left.len!=0 {equation_type_ids.free_slice(left);}if base.len!=0 {global_entry_runs.free_slice(base);}return result,error;}
recursive fn conditionalBody(self_:Engine&,id:u32,node:blot_parse_ast::Node,patterned:bool,subject:u32,bodies:u32[2],base:const Entry[:],left:u32[:],right:u32[:])->Flow,blot_error::Error {if patterned {let total,err=self_.pattern(node.a,subject,base.len,[],false);if err!=blot_error::Error.none {return Flow{..},err;}}let then_flow,err=self_.suite(bodies[0]);if err!=blot_error::Error.none {return Flow{..},err;}for entry,index in base {left[index]=self_.latestSuccessor(entry.binding);}self_.env.clear();self_.env.append(base);var else_flow=Flow{..};if bodies[1]!=0 {let flow,err=self_.suite(bodies[1]);if err!=blot_error::Error.none {return Flow{..},err;}else_flow=flow;}for entry,index in base {right[index]=self_.latestSuccessor(entry.binding);}self_.env.clear();self_.env.append(base);
 for entry,index in base {let a=left[index];let b=right[index];var shadowed=false;for later in base[index+1..] {if later.name==entry.name {shadowed=true;break;}}if shadowed || (a==entry.binding && b==entry.binding) || (then_flow.exits && else_flow.exits) {continue;}if then_flow.exits {self_.env.push(Entry{entry.name,b, ..});continue;}if else_flow.exits {self_.env.push(Entry{entry.name,a, ..});continue;}let err=self_.constrain(self_.bindings[a].ty,self_.bindings[b].ty,id);if err!=blot_error::Error.none {return Flow{..},err;}let ty=self_.bindings[a].ty;let merged,err=self_.addBinding(Binding{name:entry.name,declaration:id,owner:self_.owner,kind:blot_reuse_principal_interface::Kind.local,ty:ty,predecessor:entry.binding, ..});if err!=blot_error::Error.none {return Flow{..},err;}self_.env.push(Entry{entry.name,merged, ..});self_.merges.push(Merge{node:id,result:merged,then_binding:a,else_binding:b, ..});}
 self_.expr_types[id]=blot_check_types::unit;return Flow{exits:then_flow.exits && else_flow.exits,returns:then_flow.returns || else_flow.returns,breaks:then_flow.breaks || else_flow.breaks, ..},blot_error::Error.none;
}
recursive fn inferComputedResultOperands(self_:Engine&,start:i64,result:u32)->blot_error::Error {
    let count=self_.pending.len;
    for index in start..count {
        let pending=self_.pending[index];
        if pending.owner!=self_.current || pending.solved || pending.suspended {continue;}
        let goal=pending.value;
        var has_operand=false;
        if goal.kind==blot_check_types::ObligationKind.result_dispatch {
            let output=self_.types.head(goal.result,0);
            if self_.types.node(output).tag==blot_check_types::Tag.variable {
                let exposed,err=self_.resultOperandExposed([],result,output);
                if err!=blot_error::Error.none {return err;}
                has_operand=!exposed;
            }
        }
        if goal.kind==blot_check_types::ObligationKind.callee_use {
            let summary=self_.bindings[goal.identity.decl].summary;
            if !summary.only_result_selected || !self_.calleeSettled(goal.identity.decl) {continue;}
            let product=self_.types.node(self_.types.head(goal.ty,0));
            for slot in 0..(summary.public_outputs.len as i64) {
                if self_.types.list(summary.public_outputs)[slot]==0 {continue;}
                let actual=self_.types.list(blot_check_types::List{product.a,product.b})[slot];
                let output=self_.types.head(actual,0);
                if self_.types.node(output).tag!=blot_check_types::Tag.variable {continue;}
                let exposed,err=self_.resultOperandExposed([],result,output);
                if err!=blot_error::Error.none {return err;}
                if !exposed {has_operand=true;break;}
            }
        }
        if has_operand {
            let err=self_.expandInformedUses([self_.current],false);
            if err!=blot_error::Error.none {return err;}
            return self_.inferResultOperands([self_.current],start,result);
        }
    }
    return blot_error::Error.none;
}
// A concrete homogeneous operator can supply the expected type of a
// result-selected operand. Consider this after ordinary constraints settle:
// the other operand may itself be inferred, and an explicit destination wins.
recursive fn inferResultOperands(self_:Engine&,group:const u32[:],start:i64,exposed_root:u32)->blot_error::Error {
    var changed=true;
    while changed {
        changed=false;
        let range=self_.pendingRange(group);
        for index in min(range.end,max(start,range.start))..range.end {
            if self_.selected_globals.len!=0 {return blot_error::Error.none;}
            let pending=self_.pending[index];
            if pending.solved || pending.suspended || !inList(group,pending.owner) {continue;}
            let goal=pending.value;
            if goal.kind!=blot_check_types::ObligationKind.dispatch || goal.operator==blot_check_types::Operator.none {continue;}
            let left=self_.types.head(goal.ty,0);
            let right=self_.types.head(goal.other,0);
            let missing_left=self_.types.node(left).tag==blot_check_types::Tag.variable;
            var known=left;
            var missing=right;
            if missing_left {known=right;missing=left;}
            if known!=blot_check_types::u32_type && known!=blot_check_types::f32_type && known!=blot_check_types::boolean {continue;}
            if self_.types.node(missing).tag!=blot_check_types::Tag.variable {continue;}
            let exposed,err=self_.resultOperandExposed(group,exposed_root,missing);
            if err!=blot_error::Error.none {return err;}
            if exposed {continue;}
            let member,expanded,err=self_.resultOperandMember(pending.owner,missing);
            if err!=blot_error::Error.none {return err;}
            if expanded {changed=true;continue;}
            if member==0 {continue;}
            let unique,err=self_.uniqueResultOperand(goal,known,missing_left,member);
            if err!=blot_error::Error.none {return err;}
            if unique {let err=self_.types.unify(missing,known);if err!=blot_error::Error.none {return err;}changed=true;}
        }
        if changed {
            let err=self_.solveFields();
            if err!=blot_error::Error.none {return err;}
            let err=self_.expandInformedUses(group,false);
            if err!=blot_error::Error.none {return err;}
        }
    }
    return blot_error::Error.none;
}
// Keep a caller's ability to constrain the conversion through a parameter or
// through another part of the enclosing result.
fn resultOperandExposed(self_:Engine&,group:const u32[:],exposed_root:u32,missing:u32)->bool,blot_error::Error {
    if exposed_root!=0 {
        let variables,err=self_.types.freeVariables(exposed_root);
        if err!=blot_error::Error.none {return false,err;}
        if inList(variables,missing) {return true,blot_error::Error.none;}
    }
    for binding in group {
        let variables,err=self_.types.freeVariables(self_.bindings[binding].ty);
        if err!=blot_error::Error.none {return false,err;}
        if inList(variables,missing) {return true,blot_error::Error.none;}
    }
    return false,blot_error::Error.none;
}
fn resultOperandMember(self_:Engine&,owner:u32,missing:u32)->u32,bool,blot_error::Error {
    let count=self_.pending.len;
    for index in 0..count {
        let candidate=self_.pending[index];
        if candidate.owner!=owner || candidate.solved || candidate.suspended {continue;}
        let goal=candidate.value;
        if goal.kind==blot_check_types::ObligationKind.result_dispatch {
            let output,err=self_.types.resolve(goal.result,0);
            if err!=blot_error::Error.none {return 0,false,err;}
            if output==missing {return goal.name,false,blot_error::Error.none;}
        }
        if goal.kind!=blot_check_types::ObligationKind.callee_use {continue;}
        let summary=self_.bindings[goal.identity.decl].summary;
        if !summary.only_result_selected || !self_.calleeSettled(goal.identity.decl) {continue;}
        let product,err=self_.types.resolve(goal.ty,0);
        if err!=blot_error::Error.none {return 0,false,err;}
        let node=self_.types.node(product);
        for slot in 0..(summary.public_outputs.len as i64) {
            if self_.types.list(summary.public_outputs)[slot]==0 {continue;}
            let actual=self_.types.list(blot_check_types::List{node.a,node.b})[slot];
            let output,err=self_.types.resolve(actual,0);
            if err!=blot_error::Error.none {return 0,false,err;}
            if output!=missing {continue;}
            self_.pending[index].solved=true;
            self_.counters.use_expansions+=1;
            let err=self_.expandUse(candidate,0);
            return 0,true,err;
        }
    }
    return 0,false,blot_error::Error.none;
}
// Stay conservative about open signatures and members on alternative
// conversion destinations. They can participate in ordinary left/right
// dispatch and may provide a different expected operand type.
recursive fn uniqueResultOperand(self_:Engine&,goal:blot_check_types::Obligation,known:u32,missing_left:bool,member:u32)->bool,blot_error::Error {
    let identity=Identity{0,known};
    if !self_.catalogs.associated_members.contains(AssociatedMember{identity,member}) {return false,blot_error::Error.none;}
    var selected_index:u32=0;
    if goal.name!=0 {
        let selected .= self_.catalogs.associated_members.get(AssociatedMember{identity,goal.name});
        if !selected {return false,blot_error::Error.none;}
        selected_index=selected;
    } else {
        let selected .= self_.catalogs.associated_ops.get(AssociatedKey{identity,goal.operator});
        if !selected {return false,blot_error::Error.none;}
        selected_index=selected;
    }
    let parameters,result,err=self_.binaryMemberSignature(selected_index);
    if err!=blot_error::Error.none {return false,err;}
    if parameters[0]!=known || parameters[1]!=known {return false,blot_error::Error.none;}
    let expected,err=self_.types.resolve(goal.result,0);
    if err!=blot_error::Error.none {return false,err;}
    if self_.types.knownClosed(expected) && self_.types.knownClosed(result) {
        let same,err=self_.types.equalClosed(expected,result);
        if err!=blot_error::Error.none || !same {return false,err;}
    }
    let count=self_.associated.len;
    for index in 0..count {
        let candidate=self_.associated[index];
        if (goal.name!=0 && candidate.member!=goal.name) || (goal.name==0 && candidate.operator!=goal.operator) || candidate.identity==identity {continue;}
        if !self_.catalogs.associated_members.contains(AssociatedMember{candidate.identity,member}) {continue;}
        let parameters,result,err=self_.binaryMemberSignature(index as u32);
        if err!=blot_error::Error.none {return false,err;}
        var parameter=parameters[0];
        if missing_left {parameter=parameters[1];}
        if self_.types.knownClosed(parameter) {
            let same,err=self_.types.equalClosed(parameter,known);
            if err!=blot_error::Error.none {return false,err;}
            if !same {continue;}
        }
        if self_.types.knownClosed(expected) && self_.types.knownClosed(result) {
            let same,err=self_.types.equalClosed(expected,result);
            if err!=blot_error::Error.none {return false,err;}
            if !same {continue;}
        }
        return false,blot_error::Error.none;
    }
    return true,blot_error::Error.none;
}
recursive fn binaryMemberSignature(self_:Engine&,index:u32)->u32[2],u32,blot_error::Error {
    let binding,err=self_.associatedBinding(index);
    if err!=blot_error::Error.none {return [0,0],0,err;}
    let prepared,err=self_.prepareSelectedGlobal(binding);
    if err!=blot_error::Error.none || !prepared {return [0,0],0,err;}
    let first=self_.types.node(self_.types.head(self_.bindings[binding].ty,0));
    if first.tag!=blot_check_types::Tag.function {return [0,0],0,blot_error::Error.none;}
    let second=self_.types.node(self_.types.head(first.b,0));
    if second.tag!=blot_check_types::Tag.function {return [0,0],0,blot_error::Error.none;}
    return [self_.types.head(first.a,0),self_.types.head(second.a,0)],self_.types.head(second.b,0),blot_error::Error.none;
}
recursive fn solveFields(self_:Engine&)->blot_error::Error {return self_.solveFieldsFrom(0);}
recursive fn solveFieldsFrom(self_:Engine&,start:i64)->blot_error::Error {var progress=true;while progress {progress=false;var cursor=start;loop {if self_.selected_globals.len!=0 {return blot_error::Error.none;}let err=self_.syncPendingQueue();if err!=blot_error::Error.none {return err;}let selected=self_.pending_queue.take(cursor);if !selected.present {break;}let index=selected.value;cursor=index+1;let pending=self_.pending[index];if pending.solved {self_.pending_queue.complete(index);continue;}if pending.suspended {self_.pending_queue.requeue(index);continue;}if pending.wait_target!=0 {let state .= self_.global_states.get(pending.wait_target);assert(state);if state.state!=State.complete {self_.pending_queue.requeue(index);continue;}self_.pending[index].wait_target=0;}let made,err=self_.attemptPending(index,pending);if err!=blot_error::Error.none {return err;}progress=progress || made;let err=self_.syncPendingQueue();if err!=blot_error::Error.none {return err;}if index>=self_.pending.len {continue;}let after=self_.pending[index];if after.solved {self_.pending_queue.complete(index);}else if after.value.kind==blot_check_types::ObligationKind.effect_operation && !after.suspended {let err=self_.pending_queue.watch(self_.types,index,[after.value.other,after.value.signature],false,false);if err!=blot_error::Error.none {return err;}}else if after.value.kind==blot_check_types::ObligationKind.callee_use && !after.suspended && self_.calleeSettled(after.value.identity.decl) {let err=self_.pending_queue.watch(self_.types,index,[after.value.ty],false,false);if err!=blot_error::Error.none {return err;}}else {let input,err=self_.pendingSelectionInput(after);if err!=blot_error::Error.none {return err;}if input.present {let err=self_.pending_queue.watch(self_.types,index,[input.value],false,false);if err!=blot_error::Error.none {return err;}}else {self_.pending_queue.requeue(index);}}}}return blot_error::Error.none;}
fn pendingSelectionInput(self_:Engine&,pending:PendingObligation)->blot_support::Option<u32>,blot_error::Error {if pending.suspended {return blot_support::none<u32>(),blot_error::Error.none;}var input:u32=0;match pending.value.kind {field,writable_field,dispatch=>{input=pending.value.ty;},result_dispatch=>{input=pending.value.result;},_=>{return blot_support::none<u32>(),blot_error::Error.none;},}let root,err=self_.types.resolve(input,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}if self_.types.node(root).tag!=blot_check_types::Tag.variable {return blot_support::none<u32>(),blot_error::Error.none;}return blot_support::some(input),blot_error::Error.none;}
fn calleeSettled(self_:const Engine&,binding:u32)->bool {if binding>=self_.bindings.len {return false;}if self_.bindings[binding].kind==blot_reuse_principal_interface::Kind.external {return true;}let state .= self_.global_states.get(binding);if !state {return false;}return state.state==State.complete && !state.on_stack;}
fn syncPendingQueue(self_:Engine&)->blot_error::Error {self_.pending_queue.truncate(self_.pending.len);while self_.pending_queue.entries.len<self_.pending.len {let err=self_.pending_queue.add(true);if err!=blot_error::Error.none {return err;}}self_.pending_queue.observe(self_.types);return blot_error::Error.none;}
recursive fn attemptPending(self_:Engine&,index:i64,pending:PendingObligation)->bool,blot_error::Error {let saved=self_.dependency_owner;self_.dependency_owner=blot_support::some(pending.owner);let err=self_.inferenceTransition();if err!=blot_error::Error.none {self_.dependency_owner=saved;return false,err;}let result,error=attemptPendingBody(self_,index,pending);self_.dependency_owner=saved;return result,error;}
recursive fn attemptPendingBody(self_:Engine&,index:i64,pending:PendingObligation)->bool,blot_error::Error {let constraint=pending.value;let kind=constraint.kind;if kind==blot_check_types::ObligationKind.callee_use {return self_.resolveUse(index);}
 if kind==blot_check_types::ObligationKind.type_eq {let saved_cur=self_.current;let saved_impl=self_.checking_implementation;self_.current=pending.owner;{let il .= self_.implementation_bindings.get(pending.owner);if il {self_.checking_implementation=blot_support::some(il);}else {self_.checking_implementation=blot_support::none<u32>();}}let solved,err=self_.solveTypeEq(constraint);self_.current=saved_cur;self_.checking_implementation=saved_impl;if err!=blot_error::Error.none {return false,err;}if solved {self_.pending[index].solved=true;}return solved,blot_error::Error.none;}
 if kind==blot_check_types::ObligationKind.contract {let root=self_.types.node(self_.types.head(constraint.ty,0));if root.tag!=blot_check_types::Tag.product {return false,blot_error::Error.none;}let matched,_,err=self_.resolveTraitImpl(constraint.identity,self_.types.list(blot_check_types::List{root.a,root.b, ..}),0,constraint.source);if err!=blot_error::Error.none {return false,err;}if matched {self_.pending[index].solved=true;return true,blot_error::Error.none;}return false,blot_error::Error.none;}
 if kind==blot_check_types::ObligationKind.collection {
  let root,err=self_.types.resolve(constraint.ty,0);if err!=blot_error::Error.none {return false,err;}
  let owner=self_.types.node(root);if owner.tag==blot_check_types::Tag.variable || owner.tag==blot_check_types::Tag.projection {return false,blot_error::Error.none;}
  let element=blot_check_storage_types::collectionElement(self_.types,self_.types.head(root,0),constraint.signature);
  if element.present {let err=self_.constrain(element.value,constraint.result,constraint.source);if err!=blot_error::Error.none {return false,err;}}
  else {let err=self_.diagnostic(Code.type_mismatch,constraint.source);if err!=blot_error::Error.none {return false,err;}}
  self_.pending[index].solved=true;return true,blot_error::Error.none;
 }
 if kind==blot_check_types::ObligationKind.type_head {let head,err=self_.witnessResult(constraint.ty);if err!=blot_error::Error.none {return false,err;}let root,err=self_.types.resolve(head,0);if err!=blot_error::Error.none {return false,err;}if self_.types.node(root).tag==blot_check_types::Tag.variable {return false,blot_error::Error.none;}let err=self_.constrain(head,constraint.result,constraint.source);if err!=blot_error::Error.none {return false,err;}self_.pending[index].solved=true;return true,blot_error::Error.none;}
 if kind==blot_check_types::ObligationKind.effect_handler {let a,err=self_.types.resolve(constraint.signature,0);if err!=blot_error::Error.none {return false,err;}let b,err=self_.types.resolve(constraint.other,0);if err!=blot_error::Error.none {return false,err;}let extended=self_.types.node(a);let residual=self_.types.node(b);if extended.tag!=blot_check_types::Tag.function || residual.tag!=blot_check_types::Tag.function {return false,blot_error::Error.type_limit;}let solved,err=self_.handlerEquation(constraint.ty,extended.c,residual.c,constraint.source);if err!=blot_error::Error.none {return false,err;}if solved {self_.pending[index].solved=true;}return solved,blot_error::Error.none;}
 if kind==blot_check_types::ObligationKind.effect_operation {let arguments,err=self_.types.resolve(constraint.other,0);if err!=blot_error::Error.none {return false,err;}let closed,err=self_.types.equalClosed(arguments,arguments);if err!=blot_error::Error.none {return false,err;}if !closed {return false,blot_error::Error.none;}let pack=self_.types.node(arguments);if pack.tag!=blot_check_types::Tag.product {return false,blot_error::Error.type_limit;}let owned=equation_type_ids.alloc_slice(pack.b);let type_span_109=checkedTypeList(self_.types,blot_check_types::List{pack.a,pack.b, ..});for position in 0..(type_span_109.len as i64) {let argument=self_.types.list(type_span_109)[position];owned[position]=argument;}let label,row,error=internPendingOperation(self_,constraint,owned);equation_type_ids.free_slice(owned);if error!=blot_error::Error.none {return false,error;}let type_span_110=checkedRowLabels(self_.types,row);for type_index_110 in 0..(type_span_110.len as i64) {let known=self_.types.effects.list(type_span_110)[type_index_110];if known==label {self_.pending[index].solved=true;return true,blot_error::Error.none;}}return false,blot_error::Error.none;}
 if kind==blot_check_types::ObligationKind.update {let updated,err=self_.updatedFieldType(constraint.ty,constraint.name,constraint.other,constraint.source);if err!=blot_error::Error.none {return false,err;}if updated.present {let err=self_.constrain(constraint.result,updated.value,constraint.source);if err!=blot_error::Error.none {return false,err;}self_.pending[index].solved=true;return true,blot_error::Error.none;}return false,blot_error::Error.none;}
 if kind!=blot_check_types::ObligationKind.field && kind!=blot_check_types::ObligationKind.writable_field && kind!=blot_check_types::ObligationKind.dispatch && kind!=blot_check_types::ObligationKind.result_dispatch {return false,blot_error::Error.none;}let saved=self_.ambient;if constraint.signature!=0 {let root,err=self_.types.resolve(constraint.signature,0);if err!=blot_error::Error.none {return false,err;}self_.ambient=self_.types.node(root).c;}let selected,error=pendingMemberSelection(self_,index,pending);self_.ambient=saved;return selected,error;
}
fn internPendingOperation(self_:Engine&,constraint:blot_check_types::Obligation,arguments:const u32[:])->u32,u32,blot_error::Error {let root,err=self_.types.resolve(constraint.signature,0);if err!=blot_error::Error.none {return 0,0,err;}let signature=self_.types.node(root);if signature.tag!=blot_check_types::Tag.function {return 0,0,blot_error::Error.type_limit;}let label,error=self_.types.internOperation(constraint.identity,arguments);return label,signature.c,error;}
recursive fn pendingMemberSelection(self_:Engine&,index:i64,pending:PendingObligation)->bool,blot_error::Error {let constraint=pending.value;let kind=constraint.kind;var input=constraint.ty;if kind==blot_check_types::ObligationKind.result_dispatch {input=constraint.result;}let owner,err=self_.types.resolve(input,0);if err!=blot_error::Error.none {return false,err;}let tag=self_.types.node(owner).tag;if tag==blot_check_types::Tag.variable || tag==blot_check_types::Tag.projection {if self_.member_templates.len!=0 && (kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.dispatch) {let saved_cur=self_.current;let saved_scope=self_.qualification_scope;let saved_impl=self_.checking_implementation;self_.current=pending.owner;self_.qualification_scope=pending.scope;{let il .= self_.implementation_bindings.get(pending.owner);if il {self_.checking_implementation=blot_support::some(il);}}var mname=constraint.name;if kind==blot_check_types::ObligationKind.dispatch {let mtext=operatorMethodName(constraint.operator);if mtext.len!=0 {let ms,mk=self_.pool.lookup(mtext);if mk {mname=ms;}}}if mname!=0 {let tb,trecv,tambig,terr=self_.findTraitMethodBinding(owner,mname,constraint.source);if terr!=blot_error::Error.none {self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;return false,terr;}if tambig {self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;self_.pending[index].solved=true;return true,blot_error::Error.none;}if tb.present {self_.pending[index].suspended=true;if kind==blot_check_types::ObligationKind.field {let projected,perr=self_.projectTraitMethod(trecv,tb.value,mname,constraint.source);self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;self_.pending[index].suspended=false;if perr!=blot_error::Error.none {return false,perr;}let cerr=self_.constrain(constraint.result,projected.ty,constraint.source);if cerr!=blot_error::Error.none {return false,cerr;}self_.pending[index].solved=true;return true,blot_error::Error.none;}else {self_.resolved[constraint.source]=tb.value;let fn_ty,ferr=self_.instantiate(tb.value,constraint.source);if ferr!=blot_error::Error.none {self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;self_.pending[index].suspended=false;return false,ferr;}self_.dispatch_signatures[constraint.source]=fn_ty;let inv,ierr=self_.invocationBinary(trecv,constraint.other,constraint.result);self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;self_.pending[index].suspended=false;if ierr!=blot_error::Error.none {return false,ierr;}let cerr=self_.constrain(fn_ty,inv,constraint.source);if cerr!=blot_error::Error.none {return false,cerr;}self_.pending[index].solved=true;return true,blot_error::Error.none;}}}self_.current=saved_cur;self_.qualification_scope=saved_scope;self_.checking_implementation=saved_impl;}return false,blot_error::Error.none;}self_.pending[index].suspended=true;let selected,error=pendingMemberValue(self_,owner,pending);if error!=blot_error::Error.none {return false,error;}self_.pending[index].suspended=false;if selected.present {let before=self_.diagnostics.len;let err=self_.constrain(constraint.result,selected.value,constraint.source);if err!=blot_error::Error.none {return false,err;}if kind==blot_check_types::ObligationKind.dispatch && self_.diagnostics.len!=before && self_.dispatch_side!=blot_reuse_dispatch_explanation::Side.builtin {let err=self_.explainSelected(owner,constraint.name,constraint.operator,self_.dispatch_side);if err!=blot_error::Error.none {return false,err;}}self_.pending[index].solved=true;return true,blot_error::Error.none;}return false,blot_error::Error.none;}
recursive fn pendingMemberValue(self_:Engine&,owner:u32,pending:PendingObligation)->blot_support::Option<u32>,blot_error::Error {let value=pending.value;if value.kind==blot_check_types::ObligationKind.field || value.kind==blot_check_types::ObligationKind.writable_field {let result,err=self_.projectField(owner,value.name,value.source,value.kind==blot_check_types::ObligationKind.writable_field,blot_support::some(pending));return blot_support::some(result.ty),err;}if value.kind==blot_check_types::ObligationKind.result_dispatch {return self_.resultDispatch(value.ty,owner,value.name,value.source,pending.direct);}return self_.dispatch(owner,value.other,value.name,value.operator,value.source,pending.direct);}
type KeyBuffer=blot_support_pooled_buffer::Buffer<u8>;
reusable[] var key_bytes:u8[>..];
reusable[] var key_buffers:KeyBuffer[>..];
fn byte(self_:KeyBuffer&,value:u8)->blot_error::Error {return self_.push(value,key_bytes);}
fn word(self_:KeyBuffer&,value:u32)->blot_error::Error {for shift in 0..4 {let err=self_.byte((value>>((shift*8) as u32)) as! u8);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn length(self_:KeyBuffer&,value:i64)->blot_error::Error {let bits=value as u64;for shift in 0..8 {let err=self_.byte((bits>>((shift*8) as u64)) as! u8);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
struct KeyFieldOrder {store:blot_check_types::Store,node:blot_check_types::Node,order:u32[:]}
fn lessThan(self_:KeyFieldOrder,left:i64,right:i64)->bool {return self_.store.recordField(self_.node,self_.order[left]).name<self_.store.recordField(self_.node,self_.order[right]).name;}
fn swap(self_:KeyFieldOrder,left:i64,right:i64) {let old=self_.order[left];self_.order[left]=self_.order[right];self_.order[right]=old;}
struct KeyByteOrder {values:KeyBuffer[:]}
fn lessThan(self_:KeyByteOrder,left:i64,right:i64)->bool {let a=self_.values[left].items;let b=self_.values[right].items;for index in min(a.len,b.len) {if a[index]!=b[index] {return a[index]<b[index];}}return a.len<b.len;}
fn canonicalKeyBuffer(value:KeyBuffer)->KeyBuffer {if value.storage.len==0 {return KeyBuffer{..};}let storage=key_bytes.realloc_slice(value.storage,value.storage.len);return KeyBuffer{storage:storage,items:storage[..value.items.len]};}
fn swap(self_:KeyByteOrder,left:i64,right:i64) {let old=canonicalKeyBuffer(self_.values[left]);self_.values[left]=canonicalKeyBuffer(self_.values[right]);self_.values[right]=old;}
recursive fn closedKey(self_:Engine&,ty:u32,out:KeyBuffer&,depth:i64)->bool,blot_error::Error {if depth>=256 {return false,blot_error::Error.none;}let root,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return false,err;}let value=self_.types.node(root);let err=out.byte(blot_check_types::tagCode(value.tag) as! u8);if err!=blot_error::Error.none {return false,err;}match value.tag {
 unit,boolean,unsigned32,floating32,never=>{return true,blot_error::Error.none;},
 function=>{let row,err=self_.types.resolveEffects(value.c,0);if err!=blot_error::Error.none {return false,err;}let closed,err=self_.closedRowKey(row,out,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}let closed,err=self_.closedKey(value.a,out,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}return self_.closedKey(value.b,out,depth+1);},
 product=>{let err=out.word(value.b);if err!=blot_error::Error.none {return false,err;}for index in 0..value.b {let child=self_.types.list(blot_check_types::List{value.a,value.b, ..})[index];let closed,err=self_.closedKey(child,out,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}}return true,blot_error::Error.none;},
 record=>{let err=out.word(value.b);if err!=blot_error::Error.none {return false,err;}let order=equation_type_ids.alloc_slice(value.b);for &slot,index in order {slot=index as u32;}blot_check_source_sort::pdqContext(0,order.len,makeKeyFieldOrder(self_.types,value,order));let result,error=closedRecordKey(self_,value,order,out,depth);equation_type_ids.free_slice(order);return result,error;},
 nominal=>{let err=out.word(value.a);if err!=blot_error::Error.none {return false,err;}let err=out.word(value.b);if err!=blot_error::Error.none {return false,err;}let count=self_.types.nominalArguments(value).len;let err=out.length(count);if err!=blot_error::Error.none {return false,err;}for index in 0..count {let child=self_.types.nominalArguments(value)[index];let closed,err=self_.closedKey(child,out,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}}return true,blot_error::Error.none;},
 array=>{return self_.closedKey(value.a,out,depth+1);},
 type_constructor=>{let err=out.word(value.a);if err!=blot_error::Error.none {return false,err;}let err=out.word(value.b);return err==blot_error::Error.none,err;},_=>{return false,blot_error::Error.none;},}}
recursive fn closedRecordKey(self_:Engine&,value:blot_check_types::Node,order:const u32[:],out:KeyBuffer&,depth:i64)->bool,blot_error::Error {for index in order {let field=self_.types.recordField(value,index);let err=out.word(field.name);if err!=blot_error::Error.none {return false,err;}let closed,err=self_.closedKey(field.ty,out,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}}return true,blot_error::Error.none;}
recursive fn closedRowKey(self_:Engine&,row:u32,out:KeyBuffer&,depth:i64)->bool,blot_error::Error {let value=self_.types.row(row);if value.tail!=blot_check_effects::Tail.closed {return false,blot_error::Error.none;}let labels=checkedRowLabels(self_.types,row);let err=out.length((labels.len as i64));if err!=blot_error::Error.none {return false,err;}if (labels.len as i64)==0 {return true,blot_error::Error.none;}let owned=equation_type_ids.alloc_slice((labels.len as i64));let type_span_111=labels;for index in 0..(type_span_111.len as i64) {let label=self_.types.effects.list(type_span_111)[index];owned[index]=label;}var encoded=blot_support_pooled_buffer::Buffer<KeyBuffer>{..};let result,error=closedLabelsKey(self_,owned,out,depth,encoded);for &bytes in encoded.items {bytes.deinit(key_bytes);}encoded.deinit(key_buffers);equation_type_ids.free_slice(owned);return result,error;}
recursive fn closedLabelsKey(self_:Engine&,labels:const u32[:],out:KeyBuffer&,depth:i64,encoded:blot_support_pooled_buffer::Buffer<KeyBuffer>&)->bool,blot_error::Error {for label in labels {var bytes=KeyBuffer{..};let closed,error=closedLabelKey(self_,label,bytes,depth);if error!=blot_error::Error.none || !closed {bytes.deinit(key_bytes);return closed,error;}let err=encoded.push(bytes,key_buffers);if err!=blot_error::Error.none {bytes.deinit(key_bytes);return false,err;}}blot_check_source_sort::pdqContext(0,encoded.items.len,makeKeyByteOrder(encoded.items));for item in encoded.items {let err=out.length(item.items.len);if err!=blot_error::Error.none {return false,err;}let err=out.append(item.items,key_bytes);if err!=blot_error::Error.none {return false,err;}}return true,blot_error::Error.none;}
recursive fn closedLabelKey(self_:Engine&,label:u32,bytes:KeyBuffer&,depth:i64)->bool,blot_error::Error {let operation=self_.types.operation(label);for word in [operation.identity.unit,operation.identity.decl,operation.instance.unit,operation.instance.decl] {let err=bytes.word(word);if err!=blot_error::Error.none {return false,err;}}let count=self_.types.operationArguments(label).len;for index in 0..count {let argument=self_.types.operationArguments(label)[index];let closed,err=self_.closedKey(argument,bytes,depth+1);if err!=blot_error::Error.none || !closed {return closed,err;}}return true,blot_error::Error.none;}
struct UseWork {instance:u32[:]=default<u32[:]>(),key:KeyBuffer=KeyBuffer{..},open:Suspensions=Suspensions{..},seen_types:IdBuffer=IdBuffer{..},seen_rows:IdBuffer=IdBuffer{..}}
fn deinit(self_:UseWork&) {if self_.instance.len!=0 {equation_type_ids.free_slice(self_.instance);}self_.key.deinit(key_bytes);self_.open.deinit(suspension_runs);self_.seen_types.deinit(equation_type_ids);self_.seen_rows.deinit(equation_type_ids);}
let unchanged_output:u32=0xffffffff;
recursive fn resolveUse(self_:Engine&,index:i64)->bool,blot_error::Error {let use=self_.pending[index];let callee=self_.bindings[use.value.identity.decl];let root,err=self_.types.resolve(use.value.ty,0);if err!=blot_error::Error.none {return false,err;}var work=UseWork{instance:self_.instanceArguments(root), ..};let result,error=resolveUseWork(self_,index,use,callee,work);work.deinit();return result,error;}
// Checking a key only reads the instance. Projected stores account for every resolution.
fn expandCheckedUse(self_:Engine&,use:PendingObligation,serial:u32,arguments:const u32[:])->blot_error::Error {
    if self_.types.has_projections {return self_.expandUse(use,serial);}
    return self_.expandUseArguments(use,serial,arguments);
}
recursive fn resolveUseWork(self_:Engine&,index:i64,use:PendingObligation,callee:Binding,work:UseWork&)->bool,blot_error::Error {let type_count=callee.summary.public_variables.len;let err=work.key.word(use.value.identity.decl);if err!=blot_error::Error.none {return false,err;}var input_open=false;var input_partial=false;var plain=true;for item,position in work.instance {if position<type_count {let value=self_.types.node(item);let input=self_.types.list(callee.summary.public_inputs)[position]!=0;if value.tag==blot_check_types::Tag.variable {if input {input_open=true;}if inList(work.seen_types.items,value.a) {plain=false;}else {let err=work.seen_types.append(value.a);if err!=blot_error::Error.none {return false,err;}}let err=work.open.push(position,suspension_runs);if err!=blot_error::Error.none {return false,err;}let err=work.key.byte(0);if err!=blot_error::Error.none {return false,err;}}else {let err=work.key.byte(1);if err!=blot_error::Error.none {return false,err;}let closed,err=self_.closedKey(item,work.key,0);if err!=blot_error::Error.none {return false,err;}if !closed {plain=false;if input {input_partial=true;}}}}else {let row,err=self_.types.resolveEffects(self_.types.node(item).c,0);if err!=blot_error::Error.none {return false,err;}let value=self_.types.row(row);var variable=blot_support::none<u32>();match value.tail {variable payload=>{if value.labels.len==0 {variable=blot_support::some(payload.value);}},_=>{},}if variable.present {if inList(work.seen_rows.items,variable.value) {plain=false;}else {let err=work.seen_rows.append(variable.value);if err!=blot_error::Error.none {return false,err;}}let err=work.open.push(position,suspension_runs);if err!=blot_error::Error.none {return false,err;}let err=work.key.byte(0);if err!=blot_error::Error.none {return false,err;}}else {let err=work.key.byte(1);if err!=blot_error::Error.none {return false,err;}let closed,err=self_.closedRowKey(row,work.key,0);if err!=blot_error::Error.none {return false,err;}if !closed {plain=false;}}}}
 if callee.summary.only_result_selected {let type_span_113=checkedTypeList(self_.types,callee.summary.public_outputs);for ordinal in 0..(type_span_113.len as i64) {let output=self_.types.list(type_span_113)[ordinal];if output!=0 {let actual=work.instance[ordinal];let closed,err=self_.types.equalClosed(actual,actual);if err!=blot_error::Error.none {return false,err;}if !closed {return false,blot_error::Error.none;}}}if plain && work.open.items.len==0 {return false,blot_error::Error.none;}}else if !input_partial && input_open {return false,blot_error::Error.none;}if callee.summary.has_explicit && plain && !input_partial {var data_closed=true;for position in work.open.items {if position<type_count {data_closed=false;break;}}if data_closed {return false,blot_error::Error.none;}}
 self_.counters.use_expansions+=1;if input_partial || !plain || self_.expansion_depth>=64 {self_.pending[index].solved=true;let err=self_.expandCheckedUse(use,0,work.instance);return true,err;}let outcome .= self_.callee_memo.get(work.key.items);if outcome {var matched=true;for position,slot in work.open.items {var error=blot_error::Error.none;if position<type_count {if outcome.types[slot]!=unchanged_output {error=self_.types.unify(work.instance[position],outcome.types[slot]);}}else {if outcome.rows[slot]!=unchanged_output {error=self_.types.unifyEffects(self_.types.node(work.instance[position]).c,outcome.rows[slot]);}}if error==blot_error::Error.out_of_memory || error==blot_error::Error.type_limit {return false,error;}if error!=blot_error::Error.none {matched=false;}}if matched {self_.counters.memo_hits+=1;self_.pending[index].solved=true;return true,blot_error::Error.none;}self_.pending[index].solved=true;let err=self_.expandUse(use,0);return true,err;}
 self_.expansion_serial+=1;let serial=self_.expansion_serial;let start=self_.pending.len;let diagnostic_count=self_.diagnostics.len;self_.pending[index].suspended=true;let err=self_.expandCheckedUse(use,serial,work.instance);if err!=blot_error::Error.none {return false,err;}self_.expansion_depth+=1;let result,error=resolveUseOutcome(self_,index,serial,start,diagnostic_count,type_count,work);self_.expansion_depth-=1;return result,error;
}
recursive fn resolveUseOutcome(self_:Engine&,index:i64,serial:u32,start:i64,diagnostics:i64,type_count:u32,work:UseWork&)->bool,blot_error::Error {let err=self_.solveFieldsFrom(start);if err!=blot_error::Error.none {return false,err;}self_.pending[index].suspended=false;self_.pending[index].solved=true;var complete=self_.diagnostics.len==diagnostics && self_.mark_depth==0;if complete {for item in self_.pending[start..] {if item.expansion>=serial && !item.solved {complete=false;break;}}}if !complete {self_.counters.memo_declined+=1;return true,blot_error::Error.none;}
    let types=equation_type_ids.alloc_slice(work.open.items.len);
    let rows=equation_type_ids.alloc_slice(work.open.items.len);
    let cacheable,error=self_.calleeOutputs(type_count,work,types,rows);
    if error==blot_error::Error.none && cacheable && !self_.callee_memo.contains(work.key.items) {
        self_.callee_memo.insert(ownDiagnosticText(work.key.items),CalleeOutcome{types,rows,..});
        self_.counters.memo_misses+=1;
        return true,blot_error::Error.none;
    }
    equation_type_ids.free_slice(rows);
    equation_type_ids.free_slice(types);
    if error!=blot_error::Error.none {return false,error;}
    if !cacheable {self_.counters.memo_declined+=1;}
    return true,blot_error::Error.none;
}
fn calleeOutputs(self_:Engine&,type_count:u32,work:UseWork&,types:u32[:],rows:u32[:])->bool,blot_error::Error {
    for &value in types {value=0;}for &value in rows {value=0;}work.seen_types.clear();work.seen_rows.clear();for position,slot in work.open.items {if position<type_count {let closed,err=self_.types.resolve(work.instance[position],0);if err!=blot_error::Error.none {return false,err;}let shape=self_.types.node(closed);if shape.tag==blot_check_types::Tag.variable {if inList(work.seen_types.items,shape.a) {return false,blot_error::Error.none;}let err=work.seen_types.append(shape.a);if err!=blot_error::Error.none {return false,err;}types[slot]=unchanged_output;}else {let equal,err=self_.types.equalClosed(closed,closed);if err!=blot_error::Error.none {return false,err;}if !equal {return false,blot_error::Error.none;}types[slot]=closed;}}else {let row,err=self_.types.resolveEffects(self_.types.node(work.instance[position]).c,0);if err!=blot_error::Error.none {return false,err;}let shape=self_.types.row(row);var variable=blot_support::none<u32>();match shape.tail {variable payload=>{if shape.labels.len==0 {variable=blot_support::some(payload.value);}},_=>{},}if variable.present {if inList(work.seen_rows.items,variable.value) {return false,blot_error::Error.none;}let err=work.seen_rows.append(variable.value);if err!=blot_error::Error.none {return false,err;}rows[slot]=unchanged_output;}else if shape.tail==blot_check_effects::Tail.closed {rows[slot]=row;}else {return false,blot_error::Error.none;}}}
    return true,blot_error::Error.none;
}
recursive fn expandInformedUses(self_:Engine&,group:const u32[:],recursive_:bool)->blot_error::Error {var changed=true;while changed {changed=false;var index=self_.pendingRange(group).start;while index<self_.pending.len {let item=self_.pending[index];if item.solved || item.suspended || item.value.kind!=blot_check_types::ObligationKind.callee_use || !inList(group,item.owner) {index+=1;continue;}let root,err=self_.types.resolve(item.value.ty,0);if err!=blot_error::Error.none {return err;}let product=self_.types.node(root);let summary=self_.bindings[item.value.identity.decl].summary;let count=summary.public_variables.len;if !recursive_ && summary.only_result_selected {let resolved,err=self_.resolveUse(index);if err!=blot_error::Error.none {return err;}changed=changed || resolved;index+=1;continue;}if !recursive_ && summary.has_explicit {var closed=true;for ordinal in 0..count {let part=self_.types.list(blot_check_types::List{product.a,product.b, ..})[ordinal];let fixed,err=self_.types.equalClosed(part,part);if err!=blot_error::Error.none {return err;}if !fixed {closed=false;break;}}if closed {index+=1;continue;}}var informed=recursive_;for ordinal in 0..count {let part=self_.types.list(blot_check_types::List{product.a,product.b, ..})[ordinal];if self_.types.node(part).tag!=blot_check_types::Tag.variable {informed=true;break;}}if !informed {index+=1;continue;}self_.pending[index].solved=true;self_.counters.use_expansions+=1;let err=self_.expandUse(item,0);if err!=blot_error::Error.none {return err;}changed=true;index+=1;}if changed {let err=self_.solveFields();if err!=blot_error::Error.none {return err;}}}return blot_error::Error.none;}
fn sourceEditorProbe(self_:const Engine&,id:u32)->bool {return self_.editorAt(id);}
fn editorAt(self_:const Engine&,id:u32)->bool {if !self_.editor_marker.present {return false;}let span=self_.tree.span(id);let marker=self_.editor_marker.value;return span.start<=marker.span.start && span.end==marker.span.end;}
fn isNamespace(self_:const Engine&,name:u32)->bool {for slot in self_.imported_qualified.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.qualified.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.nominal_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.constructor_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.contract_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.implementation_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.effect_family_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}for slot in self_.catalogs.effect_operation_names.slots {if slot.tag!=0 && slot.key.namespace_==name {return true;}}return false;}
fn captureEditor(self_:Engine&,id:u32,receiver:u32,namespace_:u32)->u32,blot_error::Error {if self_.editor_capture.present && self_.editor_capture.value.node==id && self_.expr_types[id]!=0 {return self_.expr_types[id],blot_error::Error.none;}var scope_bindings:u32[33]=[0;33];var scope_names:u32[33]=[0;33];var count:i64=0;var visible:u32[>..]=[];var visible_names:u32[>..]=[];var seen:dictionary<u32,bool> = dictionary<u32,bool>{};var truncated=false;var index=self_.env.len;while index!=0 {index-=1;let entry=self_.env[index];if entry.name==0 || seen.contains(entry.name) {continue;}seen.insert(entry.name,true);if count<scope_bindings.len {scope_bindings[count]=entry.binding;scope_names[count]=entry.name;count+=1;}if !startsBytes(self_.pool.get(entry.name),self_.editor_marker.value.prefix) {continue;}if visible.len==4096 {truncated=true;break;}visible.push(entry.binding);visible_names.push(entry.name);}var type_scope:u32[>..]=[];var type_index=self_.type_env.items.len;while type_index!=0 {type_index-=1;let entry=self_.type_env.items[type_index];type_scope.append([entry.name,entry.ty]);}let scope,err=self_.types.saveList(scope_bindings[..count]);if err!=blot_error::Error.none {return 0,err;}self_.holes.push(Engine_holes{id,scope,self_.current, ..});let names,err=self_.types.saveList(scope_names[..count]);if err!=blot_error::Error.none {return 0,err;}let values,err=self_.types.saveList(visible);if err!=blot_error::Error.none {return 0,err;}let visible_labels,err=self_.types.saveList(visible_names);if err!=blot_error::Error.none {return 0,err;}let types,err=self_.types.saveList(type_scope);if err!=blot_error::Error.none {return 0,err;}self_.editor_capture=blot_support::some(EditorCapture{ kind:self_.editor_marker.value.kind, node:id, scope:scope, visible:values, visible_names:visible_labels, scope_names:names, type_scope:types, truncated:truncated, owner:self_.current, receiver:receiver, namespace_:namespace_, .. });return self_.types.fresh();}
fn holeScope(self_:Engine&)->blot_check_types::List,blot_error::Error {var scope:u32[33]=[0;33];var count:i64=0;var index=self_.env.len;while index!=0 && count!=scope.len {index-=1;let entry=self_.env[index];var shadowed=false;for binding in scope[..count] {if self_.bindings[binding].name==entry.name {shadowed=true;break;}}if !shadowed {scope[count]=entry.binding;count+=1;}}return self_.types.saveList(scope[..count]);}
fn prepareCompletionImports(self_:Engine&,capture:const EditorCapture&)->blot_error::Error {if capture.kind==blot_reuse_completion_probe::Kind.type_ || capture.kind==blot_reuse_completion_probe::Kind.constructor || capture.kind==blot_reuse_completion_probe::Kind.intrinsic {return blot_error::Error.none;}let prefix=self_.editor_marker.value.prefix;if capture.namespace_==0 {if capture.receiver!=0 {return blot_error::Error.none;}for position in 0..(self_.imported_global_order.capacity as i64) {if !blot_support_zigmap::used(self_.zig_orders,self_.imported_global_order,position as u32) {continue;}let key=blot_support_zigmap::keyAt(self_.zig_orders,self_.imported_global_order,position as u32);if !startsBytes(self_.pool.get(key),prefix) {continue;}let found .= self_.imported_globals.get(key);assert(found!=null);let target:ExternalTarget=found;let binding,err=self_.importedBinding(target);if err!=blot_error::Error.none {return err;}if binding.present {self_.catalogs.globals.insert(key,binding.value);blot_support_zigmap::put(self_.zig_orders,self_.global_order,key,0);}}}else {for slot in self_.imported_qualified.slots {if slot.tag==0 || slot.key.namespace_!=capture.namespace_ || !startsBytes(self_.pool.get(slot.key.member),prefix) {continue;}let binding,err=self_.importedBinding(slot.val);if err!=blot_error::Error.none {return err;}if binding.present {self_.catalogs.qualified.insert(slot.key,binding.value);}}}return blot_error::Error.none;}
fn finishHoles(self_:Engine&)->blot_error::Error {for hole in self_.holes {if self_.editor_capture.present && self_.editor_capture.value.node==hole.node {let capture .= self_.editor_capture.value;if capture.context.present {continue;}let err=self_.prepareCompletionImports(capture);if err!=blot_error::Error.none {return err;}let names,err=blot_reuse_completion_names::capture(self_,capture,self_.identityOf(capture.receiver));if err!=blot_error::Error.none {return err;}capture.names=names;let context,err=blot_reuse_hole_diagnostics::buildNamed(self_,hole.node,hole.scope,hole.owner,self_.types.list(capture.scope_names));if err!=blot_error::Error.none {return err;}capture.context=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,blot_reuse_hole_diagnostics::canonicalOwned(context)};continue;}var bytes:u8[>..<]=[];let err=blot_reuse_type_display::text(self_,bytes,"Unfilled expression; expected: ");if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::append(self_,bytes,self_.expr_types[hole.node]);if err!=blot_error::Error.none {return err;}if hole.scope.len!=0 {let err=blot_reuse_type_display::text(self_,bytes,"; in scope: ");if err!=blot_error::Error.none {return err;}}for index in 0..hole.scope.len {let binding=self_.types.list(hole.scope)[index];if index==32 {let err=blot_reuse_type_display::text(self_,bytes,", ...");if err!=blot_error::Error.none {return err;}break;}if index!=0 {let err=blot_reuse_type_display::text(self_,bytes,", ");if err!=blot_error::Error.none {return err;}}let err=blot_reuse_type_display::text(self_,bytes,self_.pool.get(self_.bindings[binding].name));if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::text(self_,bytes,": ");if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::append(self_,bytes,self_.bindings[binding].ty);if err!=blot_error::Error.none {return err;}}let err=self_.diagnostic(Code.typed_hole,hole.node);if err!=blot_error::Error.none {return err;}self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText(bytes));let snapshot,err=blot_reuse_hole_diagnostics::build(self_,hole.node,hole.scope,hole.owner);if err!=blot_error::Error.none {return err;}self_.diagnostics[self_.diagnostics.len-1].hole=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,blot_reuse_hole_diagnostics::canonicalOwned(snapshot)};}return blot_error::Error.none;}
fn normalizeList(self_:Engine&,list:blot_check_types::List)->blot_error::Error {for index in 0..list.len {let old=self_.types.list(list)[index];let resolved,err=self_.types.resolve(old,0);if err!=blot_error::Error.none {return err;}self_.types.replaceListItem(list,index,resolved);}return blot_error::Error.none;}
fn finish(self_:Engine&)->blot_error::Error {let derr=self_.checkDataTagsAndDefaults();if derr!=blot_error::Error.none {return derr;}let err=self_.solveFields();if err!=blot_error::Error.none {return err;}var lambda_rows:dictionary<u32,IdBuffer> = dictionary<u32,IdBuffer>{};let error=finishFacts(self_,lambda_rows);for &slot in lambda_rows.slots {if slot.tag!=0 {slot.val.deinit(equation_type_ids);}}return error;}
fn finishFacts(self_:Engine&,lambda_rows:dictionary<u32,IdBuffer>&)->blot_error::Error {for decision in self_.body_closed_rows {let scalar_lookup_93 .= self_.row_sources.get(decision.variable);if scalar_lookup_93 {let source:u32=scalar_lookup_93;let known .= lambda_rows.get(source);if !known {lambda_rows.insert(source,IdBuffer{..});}let list .= lambda_rows.get(source);assert(list);if !inList(list.items,decision.variable) {let err=list.append(decision.variable);if err!=blot_error::Error.none {return err;}}}}for slot in lambda_rows.slots {if slot.tag!=0 {let list,err=self_.types.saveList(slot.val.items);if err!=blot_error::Error.none {return err;}self_.lambda_closed_rows[slot.key]=list;}}let error=finishUnsolved(self_);if error!=blot_error::Error.none {return error;}return finishNormalized(self_);}
fn finishUnsolved(self_:Engine&)->blot_error::Error {
    // Most modules finish with no open variable obligations. Build the index
    // on the first query and compare exact type IDs, including historical views.
    var quantified:u64[>..]=[];
    for pending in self_.pending {
        if pending.solved || pending.suspended {continue;}
        if pendingHasComptimeFieldVar(self_,pending.value) {continue;}
        let resolved,err=self_.types.resolve(pending.value.ty,0);
        if err!=blot_error::Error.none {return err;}
        let tag=self_.types.node(resolved).tag;
        if tag==blot_check_types::Tag.variable {
            if quantified.len==0 {
                quantified.resize((self_.types.nodes.len+63)/64,0);
                for binding in self_.bindings[1..] {
                    for id in self_.types.list(binding.scheme.variables) {
                        quantified[id/64] |= (1 as u64) << (id%64);
                    }
                }
            }
            if resolved/64<quantified.len && (quantified[resolved/64] & ((1 as u64) << (resolved%64)))!=0 {continue;}
        }
        let kind=pending.value.kind;if kind==blot_check_types::ObligationKind.callee_use {continue;}if kind==blot_check_types::ObligationKind.type_eq {let open,oerr=self_.requirementOpen(pending.value);if oerr!=blot_error::Error.none {return oerr;}var code=Code.ambiguous_qualified;if !open {code=Code.type_mismatch;}let err=self_.diagnostic(code,pending.value.source);if err!=blot_error::Error.none {return err;}self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Unresolved associated type equality constraint"));continue;}if kind==blot_check_types::ObligationKind.effect_operation || kind==blot_check_types::ObligationKind.effect_handler || kind==blot_check_types::ObligationKind.type_head {continue;}if kind==blot_check_types::ObligationKind.field || kind==blot_check_types::ObligationKind.writable_field {var code=Code.missing_member;if kind==blot_check_types::ObligationKind.writable_field {code=Code.missing_field;}let err=self_.diagnostic(code,pending.value.source);if err!=blot_error::Error.none {return err;}let err=self_.explainReceiver(pending.value.ty,pending.value.name);if err!=blot_error::Error.none {return err;}continue;}if kind==blot_check_types::ObligationKind.result_dispatch {let destination,err=self_.types.resolve(pending.value.result,0);if err!=blot_error::Error.none {return err;}var code=Code.missing_associated;if self_.types.node(destination).tag==blot_check_types::Tag.variable {code=Code.ambiguous_associated;}let err=self_.diagnostic(code,pending.value.source);if err!=blot_error::Error.none {return err;}let err=self_.explainResult(destination,pending.value.name);if err!=blot_error::Error.none {return err;}continue;}if kind==blot_check_types::ObligationKind.dispatch {var code=Code.missing_associated;if pending.value.name==0 {code=Code.ambiguous_operator;}let err=self_.diagnostic(code,pending.value.source);if err!=blot_error::Error.none {return err;}let err=self_.explainDispatch(pending.value.ty,pending.value.name,pending.value.operator,false);if err!=blot_error::Error.none {return err;}continue;}if tag==blot_check_types::Tag.unsigned32 || (tag==blot_check_types::Tag.floating32 && kind!=blot_check_types::ObligationKind.integer) || (tag==blot_check_types::Tag.boolean && kind==blot_check_types::ObligationKind.equality) {continue;}let err=self_.diagnostic(Code.ambiguous_operator,pending.value.source);if err!=blot_error::Error.none {return err;}var detail:u8[>..<]=[];let err=blot_reuse_type_display::text(self_,detail,"Unresolved ");if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::text(self_,detail,blot_check_types::obligationKindName(kind));if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::text(self_,detail," requirement for ");if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::append(self_,detail,resolved);if err!=blot_error::Error.none {return err;}if kind==blot_check_types::ObligationKind.update && pending.value.name!=0 {let err=blot_reuse_type_display::text(self_,detail," at field ");if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::text(self_,detail,self_.pool.get(pending.value.name));if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::text(self_,detail," with replacement ");if err!=blot_error::Error.none {return err;}let root,err=self_.types.resolve(pending.value.other,0);if err!=blot_error::Error.none {return err;}let err=blot_reuse_type_display::append(self_,detail,root);if err!=blot_error::Error.none {return err;}}self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText(detail));}return blot_error::Error.none;}

// This batch reads final type roots at cursor zero. Discard the table before
// normalization begins replacing elements in the store's lists.
fn settledType(self_:Engine&,root:u32,cache:u32[:])->u32,blot_error::Error {
    if root>=cache.len {return self_.types.resolve(root,0);}
    let known=cache[root];
    if known!=0 {return known,blot_error::Error.none;}
    let result,error=self_.types.resolve(root,0);
    if error==blot_error::Error.none {cache[root]=result;}
    return result,error;
}
fn finishRootTypes(self_:Engine&,cache:u32[:])->blot_error::Error {
for &id in self_.expr_types {if id!=0 {
{let value,err=settledType(self_,id,cache);if err!=blot_error::Error.none {return err;}id=value;}
}}
for &id in self_.dispatch_signatures {if id!=0 {
{let value,err=settledType(self_,id,cache);if err!=blot_error::Error.none {return err;}id=value;}
}}
for &binding in self_.bindings[1..] {
{let value,err=settledType(self_,binding.ty,cache);if err!=blot_error::Error.none {return err;}binding.ty=value;}
if binding.scheme.root!=0 {
{let value,err=settledType(self_,binding.scheme.root,cache);if err!=blot_error::Error.none {return err;}binding.scheme.root=value;}
}
}
return blot_error::Error.none;
}
recursive fn typeContainsSizedArray(self_:Engine&,root:u32,depth:i64)->bool,blot_error::Error {
 if root==0 || depth>=64 {return false,blot_error::Error.none;}
 let id,err=self_.types.resolve(root,0);
 if err!=blot_error::Error.none {return false,err;}
 let sinfo=blot_check_storage_types::info(self_.types,id);
 if sinfo.present {
  if sinfo.value.kind==blot_check_storage_types::sized_array {return true,blot_error::Error.none;}
  return self_.typeContainsSizedArray(sinfo.value.element,depth+1);
 }
 let node=self_.types.node(id);
 if node.tag==blot_check_types::Tag.usage || node.tag==blot_check_types::Tag.array || node.tag==blot_check_types::Tag.forall {
  return self_.typeContainsSizedArray(node.a,depth+1);
 }
 if node.tag==blot_check_types::Tag.product {
  let span=checkedTypeList(self_.types,blot_check_types::List{node.a,node.b, ..});
  for idx in 0..(span.len as i64) {
   let has,herr=self_.typeContainsSizedArray(self_.types.list(span)[idx],depth+1);
   if herr!=blot_error::Error.none || has {return has,herr;}
  }
  return false,blot_error::Error.none;
 }
 if node.tag==blot_check_types::Tag.record {
  for idx in 0..node.b {
   let has,herr=self_.typeContainsSizedArray(self_.types.recordField(node,idx).ty,depth+1);
   if herr!=blot_error::Error.none || has {return has,herr;}
  }
  return false,blot_error::Error.none;
 }
 if node.tag==blot_check_types::Tag.nominal {
  let span=checkedNominalArguments(self_.types,node);
  for idx in 0..(span.len as i64) {
   let has,herr=self_.typeContainsSizedArray(self_.types.list(span)[idx],depth+1);
   if herr!=blot_error::Error.none || has {return has,herr;}
  }
 }
 return false,blot_error::Error.none;
}
fn validateTestsAndEntries(self_:Engine&)->blot_error::Error {
 for bi in 1..self_.bindings.len {
  let binding=self_.bindings[bi];
  if binding.kind!=blot_reuse_principal_interface::Kind.global || binding.declaration==0 {continue;}
  let decl=binding.declaration;
  if self_.tree.node(decl).tag!=blot_parse_ast::tag_value_decl {continue;}
  let tmeta=self_.tree.testMeta(decl);
  if tmeta.present {
   if !tmeta.value.is_trap {
    let root,rerr=self_.types.resolve(binding.ty,0);
    if rerr!=blot_error::Error.none {return rerr;}
    let fn_node=self_.types.node(root);
    if fn_node.tag==blot_check_types::Tag.function {
     let ret,reterr=self_.types.resolve(fn_node.b,0);
     if reterr!=blot_error::Error.none {return reterr;}
     let rnode=self_.types.node(ret);
     let ok_ret=rnode.tag==blot_check_types::Tag.boolean ||
                rnode.tag==blot_check_types::Tag.unit ||
                rnode.tag==blot_check_types::Tag.never ||
                (rnode.tag==blot_check_types::Tag.array &&
                 self_.types.head(rnode.a,0)==blot_check_types::u32_type);
     if !ok_ret {
      let derr=self_.diagnostic(Code.entry_type,decl);
      if derr!=blot_error::Error.none {return derr;}
      var detail:u8[>..<]=[];
      let t1=blot_reuse_type_display::text(self_,detail,"test declaration must return Bool, Unit, or #[U32]; got ");
      if t1!=blot_error::Error.none {return t1;}
      let t2=blot_reuse_type_display::append(self_,detail,ret);
      if t2!=blot_error::Error.none {return t2;}
      self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText(detail));
     }
    }
   }
   continue;
  }
  let vdecl=self_.tree.value_decl(decl);
  if vdecl.exported {
   var cur,cerr=self_.types.resolve(binding.ty,0);
   if cerr!=blot_error::Error.none {return cerr;}
   var steps:i64=0;
   while steps<64 && self_.types.node(cur).tag==blot_check_types::Tag.function {
    let fn_node=self_.types.node(cur);
    let has_sized,serr=self_.typeContainsSizedArray(fn_node.a,0);
    if serr!=blot_error::Error.none {return serr;}
    if has_sized {
     let derr=self_.diagnostic(Code.entry_type,decl);
     if derr!=blot_error::Error.none {return derr;}
     self_.diagnostics[self_.diagnostics.len-1].detail=blot_support::some<const u8[:]>(ownDiagnosticText("Fixed-size array #[N; T] is not supported as an io entry parameter; use #[T] instead"));
     break;
    }
    let next,nerr=self_.types.resolve(fn_node.b,0);
    if nerr!=blot_error::Error.none {return nerr;}
    cur=next;
    steps+=1;
   }
  }
 }
 return blot_error::Error.none;
}
fn finishNormalized(self_:Engine&)->blot_error::Error {
    var count:i64=0;
    if !self_.types.has_projections {count=self_.types.nodes.len;}
    let cache=equation_type_ids.alloc_slice(count);
    for &slot in cache {slot=0;}
    let error=finishRootTypes(self_,cache);
    equation_type_ids.free_slice(cache);
    if error!=blot_error::Error.none {return error;}
for list in self_.access_types {let err=self_.normalizeList(list);if err!=blot_error::Error.none {return err;}}
for &nominal in self_.nominals[1..] {
{let err=self_.normalizeList(nominal.parameters);if err!=blot_error::Error.none {return err;}}
{let err=self_.normalizeList(nominal.variables);if err!=blot_error::Error.none {return err;}}
}
for &constructor,offset in self_.constructors[1..] {
if constructor.deferred_result && self_.types.has_projections {
    // Every original resolution visit counts toward the public projection budget.
    let root,err=self_.constructorRoot(constructor,false);
    if err!=blot_error::Error.none {return err;}
    constructor.scheme.root=root;
    constructor.deferred_result=false;
}
let index=offset+1;
var height:u8=0;
if index<self_.imported_constructor_heights.len {height=self_.imported_constructor_heights[index];}
if self_.types.has_projections || height==0 || height>self_.types.resolution_depth_limit {
{let value,err=self_.types.resolve(constructor.scheme.root,0);if err!=blot_error::Error.none {return err;}constructor.scheme.root=value;}
{let value,err=self_.types.resolve(constructor.payload,0);if err!=blot_error::Error.none {return err;}constructor.payload=value;}
}
{let err=self_.normalizeList(constructor.scheme.variables);if err!=blot_error::Error.none {return err;}}
}
for &family in self_.effect_families[1..] {
{let err=self_.normalizeList(family.parameters);if err!=blot_error::Error.none {return err;}}
{let err=self_.normalizeList(family.variables);if err!=blot_error::Error.none {return err;}}
}
for &template in self_.effect_templates[1..] {
{let value,err=self_.types.resolve(template.parameter,0);if err!=blot_error::Error.none {return err;}template.parameter=value;}
{let value,err=self_.types.resolve(template.result,0);if err!=blot_error::Error.none {return err;}template.result=value;}
}
for &use in self_.operation_uses {let err=self_.normalizeList(use.arguments);if err!=blot_error::Error.none {return err;}
{let value,err=self_.types.resolve(use.signature,0);if err!=blot_error::Error.none {return err;}use.signature=value;}
}

for &block_ in self_.provider_blocks {
{let value,err=self_.types.resolve(block_.body_result,0);if err!=blot_error::Error.none {return err;}block_.body_result=value;}
{let value,err=self_.types.resolve(block_.result,0);if err!=blot_error::Error.none {return err;}block_.result=value;}
{let value,err=self_.types.resolveEffects(block_.body_effects,0);if err!=blot_error::Error.none {return err;}block_.body_effects=value;}
{let value,err=self_.types.resolveEffects(block_.outer_effects,0);if err!=blot_error::Error.none {return err;}block_.outer_effects=value;}
}
for &runner in self_.effect_runners {
if runner.read_token!=0 {
{let value,err=self_.types.resolve(runner.read_token,0);if err!=blot_error::Error.none {return err;}runner.read_token=value;}
}
if runner.write_token!=0 {
{let value,err=self_.types.resolve(runner.write_token,0);if err!=blot_error::Error.none {return err;}runner.write_token=value;}
}
{let value,err=self_.types.resolve(runner.state_type,0);if err!=blot_error::Error.none {return err;}runner.state_type=value;}
{let value,err=self_.types.resolve(runner.body_result,0);if err!=blot_error::Error.none {return err;}runner.body_result=value;}
{let value,err=self_.types.resolve(runner.result,0);if err!=blot_error::Error.none {return err;}runner.result=value;}
if runner.implementation_type!=0 {
{let value,err=self_.types.resolve(runner.implementation_type,0);if err!=blot_error::Error.none {return err;}runner.implementation_type=value;}
}
{let value,err=self_.types.resolve(runner.action_type,0);if err!=blot_error::Error.none {return err;}runner.action_type=value;}
{let value,err=self_.types.resolveEffects(runner.body_effects,0);if err!=blot_error::Error.none {return err;}runner.body_effects=value;}
{let value,err=self_.types.resolveEffects(runner.outer_effects,0);if err!=blot_error::Error.none {return err;}runner.outer_effects=value;}
}
for &computation in self_.computations {
{let value,err=self_.types.resolve(computation.ty,0);if err!=blot_error::Error.none {return err;}computation.ty=value;}
{let value,err=self_.types.resolve(computation.action_type,0);if err!=blot_error::Error.none {return err;}computation.action_type=value;}
}
for &predicate in self_.obligations {
{let value,err=self_.types.resolve(predicate.ty,0);if err!=blot_error::Error.none {return err;}predicate.ty=value;}
if predicate.result!=0 {
{let value,err=self_.types.resolve(predicate.result,0);if err!=blot_error::Error.none {return err;}predicate.result=value;}
}
if predicate.other!=0 {
{let value,err=self_.types.resolve(predicate.other,0);if err!=blot_error::Error.none {return err;}predicate.other=value;}
}
if predicate.signature!=0 {
{let value,err=self_.types.resolve(predicate.signature,0);if err!=blot_error::Error.none {return err;}predicate.signature=value;}
}
}
for &requirement in self_.covered_requirements {
if requirement.value.ty!=0 {
{let value,err=self_.types.resolve(requirement.value.ty,0);if err!=blot_error::Error.none {return err;}requirement.value.ty=value;}
}
if requirement.value.other!=0 {
{let value,err=self_.types.resolve(requirement.value.other,0);if err!=blot_error::Error.none {return err;}requirement.value.other=value;}
}
if requirement.value.result!=0 {
{let value,err=self_.types.resolve(requirement.value.result,0);if err!=blot_error::Error.none {return err;}requirement.value.result=value;}
}
if requirement.value.signature!=0 {
{let value,err=self_.types.resolve(requirement.value.signature,0);if err!=blot_error::Error.none {return err;}requirement.value.signature=value;}
}
}
if self_.diagnostics.len==0 {for id in self_.cases {let err=self_.checkCoverage(id);if err!=blot_error::Error.none {return err;}}}if self_.diagnostics.len==0 {let verr=self_.validateTestsAndEntries();if verr!=blot_error::Error.none {return verr;}}return blot_error::Error.none;
}
fn wildcard(self_:const Engine&,id:u32)->bool {if id==0 {return true;}let tag=self_.tree.node(id).tag;return tag==blot_parse_ast::tag_pattern_name || tag==blot_parse_ast::tag_pattern_field;}
type CoverageRows=blot_support_pooled_buffer::Buffer<const u32[:]>;
type CoverageRanges=blot_support_pooled_buffer::Buffer<blot_check_types::List>;
reusable[] var coverage_rows:(const u32[:])[>..];
reusable[] var coverage_ranges:blot_check_types::List[>..];
// Same-size pool reification validates membership without moving the live run.
fn canonicalCoverageRows(rows:const(const u32[:])[:])->const(const u32[:])[:] {if rows.len==0 {return default<const(const u32[:])[:]>();}let owned=coverage_rows.realloc_slice(rows,rows.len);assert(blot_support::same_slice_identity(owned,rows));return owned;}
fn canonicalCoverageTypes(types:const u32[:])->const u32[:] {if types.len==0 {return default<const u32[:]>();}let owned=equation_type_ids.realloc_slice(types,types.len);assert(blot_support::same_slice_identity(owned,types));return owned;}
struct CoverageWork {variants:IdBuffer=IdBuffer{..},children:IdBuffer=IdBuffer{..},words:IdBuffer=IdBuffer{..},ranges:CoverageRanges=CoverageRanges{..},specialized:CoverageRows=CoverageRows{..}}
fn deinit(self_:CoverageWork&) {self_.variants.deinit(equation_type_ids);self_.children.deinit(equation_type_ids);self_.words.deinit(equation_type_ids);self_.ranges.deinit(coverage_ranges);self_.specialized.deinit(coverage_rows);}
fn checkCoverage(self_:Engine&,id:u32)->blot_error::Error {let node=self_.tree.node(id);let input=checkedAstRange(self_.tree,node.a,node.a+2);var types=IdBuffer{..};var rows=CoverageRows{..};let error=checkCoverageRows(self_,id,node,input,types,rows);types.deinit(equation_type_ids);rows.deinit(coverage_rows);return error;}
fn checkCoverageRows(self_:Engine&,id:u32,node:blot_parse_ast::Node,input:blot_parse_ast::List,types:IdBuffer&,rows:CoverageRows&)->blot_error::Error {let syntax_source_47=blot_parse_ast::List{self_.tree.list(input)[0],self_.tree.list(input)[1], ..};let syntax_count_47=self_.tree.list(syntax_source_47).len;for syntax_index_47 in 0..syntax_count_47 {let child=self_.tree.list(syntax_source_47)[syntax_index_47];let ty=self_.expr_types[child];let resolved,err=self_.types.resolve(ty,0);if err!=blot_error::Error.none {return err;}if resolved==blot_check_types::never {return blot_error::Error.none;}let err=types.append(ty);if err!=blot_error::Error.none {return err;}}let syntax_source_48=blot_parse_ast::List{node.b,node.c, ..};let syntax_count_48=self_.tree.list(syntax_source_48).len;for syntax_index_48 in 0..syntax_count_48 {let arm_id=self_.tree.list(syntax_source_48)[syntax_index_48];let arm=self_.tree.node(arm_id);if self_.tree.extra.items[arm.c]!=0 {continue;}let syntax_source_49=blot_parse_ast::List{arm.a,arm.b, ..};let syntax_count_49=self_.tree.list(syntax_source_49).len;for syntax_index_49 in 0..syntax_count_49 {let row=self_.tree.list(syntax_source_49)[syntax_index_49];let tree=blot_parse_ast::canonical(self_.tree);let ast_children_source=row;let ast_children_count=tree.children(ast_children_source).len;let owned:const u32[:]=blot_parse_ast::tree_WordBuffer_runs.realloc_slice(tree.children(ast_children_source),ast_children_count);let err=rows.push(owned,coverage_rows);if err!=blot_error::Error.none {return err;}}}var budget:i64=100000;let covered,err=self_.covered(canonicalCoverageRows(rows.items),canonicalCoverageTypes(types.items),0,budget);if err!=blot_error::Error.none {return err;}if !covered {return self_.diagnostic(Code.non_exhaustive_match,id);}return blot_error::Error.none;}
recursive fn covered(self_:Engine&,rows:const(const u32[:])[:],types:const u32[:],depth:i64,budget:i64&)->bool,blot_error::Error {if budget==0 || depth>=1024 {return false,blot_error::Error.type_limit;}budget-=1;if rows.len==0 {return false,blot_error::Error.none;}if types.len==0 {return true,blot_error::Error.none;}for row in rows {var all=true;for pattern in row {all=all && self_.wildcard(pattern);}if all {return true,blot_error::Error.none;}}let ty,err=self_.types.resolve(types[0],0);if err!=blot_error::Error.none {return false,err;}let node=self_.types.node(ty);var work=CoverageWork{..};let result,error=coveredVariants(self_,rows,types,ty,node,depth,budget,work);work.deinit();return result,error;}
recursive fn coveredVariants(self_:Engine&,rows:const(const u32[:])[:],types:const u32[:],ty:u32,node:blot_check_types::Node,depth:i64,budget:i64&,work:CoverageWork&)->bool,blot_error::Error {match node.tag {
 boolean=>{let err=work.variants.append(0);if err!=blot_error::Error.none {return false,err;}let err=work.variants.append(1);if err!=blot_error::Error.none {return false,err;}},
 nominal=>{let index=self_.nominalIndex(Identity{node.a,node.b, ..});if !index.present {return false,blot_error::Error.none;}let err=blot_support_pooled_buffer::append(work.variants,self_.types.list(self_.nominals[index.value].constructors),equation_type_ids);if err!=blot_error::Error.none {return false,err;}},
 unit,record,product=>{let err=work.variants.append(0);if err!=blot_error::Error.none {return false,err;}},
 _=>{let row_count=rows.len;for row_index in 0..row_count {if self_.wildcard(rows[row_index][0]) {let err=work.specialized.push(rows[row_index][1..],coverage_rows);if err!=blot_error::Error.none {return false,err;}}}return self_.covered(canonicalCoverageRows(work.specialized.items),canonicalCoverageTypes(types[1..]),depth+1,budget);},}
 let variant_count=work.variants.items.len;for variant_index in 0..variant_count {let variant=work.variants.items[variant_index];work.children.clear();work.words.clear();work.ranges.clear();work.specialized.clear();var record_payload=blot_support::none<blot_check_types::Node>();match node.tag {
 nominal=>{let use_id,err=self_.constructorStorageType(variant);if err!=blot_error::Error.none {return false,err;}let use=self_.types.node(use_id);if use.tag==blot_check_types::Tag.function {let err=self_.constrain(use.b,ty,0);if err!=blot_error::Error.none {return false,err;}let payload,err=self_.types.resolve(use.a,0);if err!=blot_error::Error.none {return false,err;}let shape=self_.types.node(payload);if shape.tag==blot_check_types::Tag.record {record_payload=blot_support::some(shape);for index in 0..shape.b {let err=work.children.append(self_.types.recordField(shape,index).ty);if err!=blot_error::Error.none {return false,err;}}}else {let err=work.children.append(payload);if err!=blot_error::Error.none {return false,err;}}}},
 product=>{let err=blot_support_pooled_buffer::append(work.children,self_.types.list(blot_check_types::List{node.a,node.b, ..}),equation_type_ids);if err!=blot_error::Error.none {return false,err;}},
 record=>{for index in 0..node.b {let err=work.children.append(self_.types.recordField(node,index).ty);if err!=blot_error::Error.none {return false,err;}}},_=>{},}
 let arity=work.children.items.len;let err=blot_support_pooled_buffer::append(work.children,types[1..],equation_type_ids);if err!=blot_error::Error.none {return false,err;}let row_count=rows.len;for row_index in 0..row_count {let pattern=rows[row_index][0];let wildcard=self_.wildcard(pattern);var syntax=blot_parse_ast::Node{tag:blot_parse_ast::tag_pattern_name,a:0,b:0,c:0, ..};if pattern!=0 {syntax=self_.tree.node(pattern);}if !wildcard {var matches=false;match node.tag {boolean=>{matches=syntax.tag==blot_parse_ast::tag_pattern_boolean && syntax.a==variant;},unit=>{matches=syntax.tag==blot_parse_ast::tag_pattern_product && self_.tree.children(pattern).len==0;},nominal=>{matches=syntax.tag==blot_parse_ast::tag_pattern_constructor && self_.constructor_resolved[pattern]==variant;},product=>{matches=syntax.tag==blot_parse_ast::tag_pattern_product;},record=>{matches=syntax.tag==blot_parse_ast::tag_pattern_record;},_=>{},}if !matches {continue;}}if work.words.items.len>0xffffffff {return false,blot_error::Error.type_limit;}let start=work.words.items.len as u32;for index in 0..arity {let err=work.words.append(0);if err!=blot_error::Error.none {return false,err;}}
 if !wildcard {match node.tag {
 nominal=>{if arity!=0 {if record_payload.present {let record=record_payload.value;let payload=self_.tree.node(syntax.b);if payload.tag==blot_parse_ast::tag_pattern_record {let syntax_source_50=syntax.b;let syntax_count_50=self_.tree.children(syntax_source_50).len;for syntax_index_50 in 0..syntax_count_50 {let field=self_.tree.children(syntax_source_50)[syntax_index_50];let slot=self_.projections[field];if slot<arity {work.words.items[start+slot]=self_.tree.node(field).b;}}}else if record.b==1 {work.words.items[start]=syntax.b;}else if payload.tag==blot_parse_ast::tag_pattern_product {let fields=checkedAstChildren(self_.tree,syntax.b);if (fields.len as i64)!=arity {continue;}let ast_span_23=fields;for index in 0..(ast_span_23.len as i64) {let field=self_.tree.list(ast_span_23)[index];work.words.items[start+index]=field;}}}else {work.words.items[start]=syntax.b;}}},
 product=>{let fields=checkedAstChildren(self_.tree,pattern);if (fields.len as i64)!=arity {continue;}let ast_span_24=fields;for index in 0..(ast_span_24.len as i64) {let field=self_.tree.list(ast_span_24)[index];work.words.items[start+index]=field;}},
 record=>{let syntax_source_51=pattern;let syntax_count_51=self_.tree.children(syntax_source_51).len;for syntax_index_51 in 0..syntax_count_51 {let field=self_.tree.children(syntax_source_51)[syntax_index_51];let slot=self_.projections[field];if slot<arity {work.words.items[start+slot]=self_.tree.node(field).b;}}},_=>{},}}
 let err=blot_support_pooled_buffer::append(work.words,rows[row_index][1..],equation_type_ids);if err!=blot_error::Error.none {return false,err;}if arity+rows[row_index].len-1>0xffffffff {return false,blot_error::Error.type_limit;}let err=work.ranges.push(blot_check_types::List{start,(arity+rows[row_index].len-1) as u32, ..},coverage_ranges);if err!=blot_error::Error.none {return false,err;}}
 let owned_words:const u32[:]=equation_type_ids.realloc_slice(work.words.items,work.words.items.len);let range_count=work.ranges.items.len;for range_index in 0..range_count {let range=work.ranges.items[range_index];let err=work.specialized.push(owned_words[range.start..range.start+range.len],coverage_rows);if err!=blot_error::Error.none {return false,err;}}let covered,err=self_.covered(canonicalCoverageRows(work.specialized.items),canonicalCoverageTypes(work.children.items),depth+1,budget);if err!=blot_error::Error.none || !covered {return covered,err;}}
 return true,blot_error::Error.none;
}
fn sourceImportDiagnostic(tree:const blot_parse_ast::Tree&)->blot_support::Option<Diagnostic> {if tree.diagnostics.len!=0 {return blot_support::none<Diagnostic>();}let ast_walk_31_count=tree.roots.items.len;for ast_walk_31_index in 0..ast_walk_31_count {let id=tree.roots.items[ast_walk_31_index];if tree.node(id).tag==blot_parse_ast::tag_import_decl {let origin=tree.span(id).start;return blot_support::some(Diagnostic{ code:Code.module_loader_required, span:blot_parse_ast::Span{origin,origin, ..}, node:id, .. });}}return blot_support::none<Diagnostic>();}
fn hasNumericFailure(tree:const blot_parse_ast::Tree&)->bool {let ast_walk_32_count=tree.nodes.items.len;for ast_walk_32_index in 0..ast_walk_32_count {let node=tree.nodes.items[ast_walk_32_index];if node.tag==blot_parse_ast::tag_numeric_error {return true;}}return false;}
fn canonicalDiagnosticText(text:const u8[:])->const u8[:]{for run in diagnostic_runs {if run.live&&blot_support::same_slice_identity(run.bytes,text) {return diagnostic_text.realloc_slice(run.bytes,run.bytes.len);}}abort("diagnostic text is outside its owner");}
fn canonicalDiagnosticPurity(value:PurityWitness)->PurityWitness{var name=blot_support::none<const u8[:]>();if value.operation_name.present {name=blot_support::some<const u8[:]>(canonicalDiagnosticText(value.operation_name.value));}return PurityWitness{identity:value.identity,family:value.family,member:value.member,compound:value.compound,foreign:value.foreign,specialized:value.specialized,origin_unavailable:value.origin_unavailable,operation_name:name};}
fn canonicalDiagnostic(value:Diagnostic)->Diagnostic{var result=Diagnostic{origin_unit:value.origin_unit,code:value.code,span:value.span,node:value.node,type_application:value.type_application,symbol:value.symbol,implicit_type_witness:value.implicit_type_witness,source_terminator:value.source_terminator,numeric_literal:value.numeric_literal,contexts:value.contexts,context_len:value.context_len,..};if value.purity.present {result.purity=blot_support::Option<PurityWitness>{true,canonicalDiagnosticPurity(value.purity.value)};}if value.detail.present {result.detail=blot_support::some<const u8[:]>(canonicalDiagnosticText(value.detail.value));}if value.hole.present {result.hole=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,blot_reuse_hole_diagnostics::canonicalOwned(value.hole.value)};}if value.explanation.present {result.explanation=blot_support::Option<blot_reuse_dispatch_explanation::Explanation>{true,blot_reuse_dispatch_explanation::canonicalOwned(value.explanation.value)};}return result;}

fn deinitDiagnosticPayloads(diagnostics:const Diagnostic[:]) {for diagnostic in diagnostics {if diagnostic.purity.present && diagnostic.purity.value.operation_name.present {freeDiagnosticText(diagnostic.purity.value.operation_name.value);}if diagnostic.detail.present {freeDiagnosticText(diagnostic.detail.value);}if diagnostic.hole.present {var hole=diagnostic.hole.value;hole.deinit();}if diagnostic.explanation.present {var explanation=diagnostic.explanation.value;explanation.deinit();}}}
fn cloneDiagnostics(owner:CheckedOwner,diagnostics:const Diagnostic[:])->Diagnostic[:],blot_error::Error {let result=ownChecked_diagnostics(owner,diagnostics);let diagnostic_count=diagnostics.len;for index in 0..diagnostic_count {let diagnostic=diagnostics[index];let target .= result[index];if diagnostic.purity.present {target.purity=blot_support::Option<PurityWitness>{true,cloneDiagnosticPurity(diagnostic.purity.value)};}if diagnostic.detail.present {target.detail=blot_support::some<const u8[:]>(ownDiagnosticText(diagnostic.detail.value));}if diagnostic.hole.present {let hole,error=diagnostic.hole.value.clone();if error!=blot_error::Error.none {deinitDiagnosticPayloads(result[..index+1]);return default<Diagnostic[:]>(),error;}target.hole=blot_support::Option<blot_reuse_hole_diagnostics::Snapshot>{true,blot_reuse_hole_diagnostics::canonicalOwned(hole)};}if diagnostic.explanation.present {let explanation,error=diagnostic.explanation.value.clone();if error!=blot_error::Error.none {deinitDiagnosticPayloads(result[..index+1]);return default<Diagnostic[:]>(),error;}target.explanation=blot_support::Option<blot_reuse_dispatch_explanation::Explanation>{true,blot_reuse_dispatch_explanation::canonicalOwned(explanation)};}}return result,blot_error::Error.none;}
fn rejectedSource(diagnostics:const Diagnostic[:])->Checked,blot_error::Error {let initial,error=blot_check_types::init();if error!=blot_error::Error.none {return default<Checked>(),error;}var types=initial;let owner,error=newCheckedOwner();if error!=blot_error::Error.none {types.deinit();return default<Checked>(),error;}let bindings=ownChecked_bindings(owner,[Binding{name:0,declaration:0,owner:0,kind:blot_reuse_principal_interface::Kind.local,ty:0, ..}]);let owned,error=cloneDiagnostics(owner,diagnostics);if error!=blot_error::Error.none {var release=owner;release.deinit();types.deinit();return default<Checked>(),error;}let patterns,error=blot_check_parameter_patterns::initPooled();if error!=blot_error::Error.none {var release=owner;release.deinit();types.deinit();return default<Checked>(),error;}return Checked{owner:owner,types:types,parameter_patterns:patterns,expr_types:default<blot_check_types::Id[:]>(),resolved:default<blot_check_check::BindingId[:]>(),bindings:bindings,merges:default<blot_check_check::Merge[:]>(),obligations:default<blot_check_types::Obligation[:]>(),diagnostics:owned,body_elaborations:0, ..},blot_error::Error.none;}
fn rejectNumericSource(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],catalogs:const ImportedCatalog[:],unit:u32,options:ModuleOptions)->Checked,blot_error::Error {var headers:SourceHeader[>..]=[];for imported in imports {headers.push(SourceHeader{ capability_parameters:imported.interface.capability_parameters, name:imported.name, namespace_:imported.namespace_, member:imported.member, target:imported.target, named_function:imported.interface.named_function, origin:imported.origin, expose:imported.expose, .. });}var source_catalogs:SourceCatalog[>..]=[];var declarations:SourceDeclaration[>..]=[];var spans:blot_check_types::List[>..]=[];for imported in catalogs {if declarations.len>0xffffffff || imported.bindingCount()>0xffffffff-declarations.len {return default<Checked>(),blot_error::Error.type_limit;}let start=declarations.len as u32;for index in 0..imported.bindingCount() {declarations.push(imported.declaration(index as u32));}spans.push(blot_check_types::List{start,imported.bindingCount() as u32, ..});}for imported,index in catalogs {let span=spans[index];source_catalogs.push(SourceCatalog{producer:imported.catalog(),declarations:declarations[span.start..span.start+span.len],namespace_:imported.namespace_,name:imported.name,kind:imported.kind,index:imported.index,origin:imported.origin, ..});}let value,error=validateModuleSource(tree,pool,headers,source_catalogs,unit,options);if error!=blot_error::Error.none {return default<Checked>(),error;}var validation=value;if validation.diagnostics.len==0 {validation.deinit();return default<Checked>(),blot_error::Error.numeric_validation_incomplete;}let result,error=rejectedSource(validation.diagnostics);validation.deinit();return result,error;}
fn inferenceBudget(options:ModuleOptions)->i64 {
 if options.max_inference_transitions.present {return options.max_inference_transitions.value;}
 let configured=blot_inference_limits::configured();if configured>0x7fffffffffffffff {return 0x7fffffffffffffff;}return configured as i64;
}
fn check(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&)->Checked,blot_error::Error {let diagnostic=sourceImportDiagnostic(tree);if diagnostic.present {return rejectedSource([diagnostic.value]);}return checkInternal(tree,pool,[],[],[],[],1,false,ModuleOptions{..},false);}
fn checkPrivateExecution(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,execution:PrivateExecution)->Checked,blot_error::Error {let diagnostic=sourceImportDiagnostic(tree);if diagnostic.present {return rejectedSource([diagnostic.value]);}return checkInternalExecution(tree,pool,[],[],[],[],1,false,ModuleOptions{..},false,execution);}
fn checkWithImports(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:])->Checked,blot_error::Error {return checkInternal(tree,pool,imports,[],[],[],1,true,ModuleOptions{..},false);}
fn checkModule(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],catalogs:const ImportedCatalog[:],unit:u32)->Checked,blot_error::Error {return checkModuleWithOptions(tree,pool,imports,catalogs,unit,ModuleOptions{..});}
fn checkModuleWithOptions(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],catalogs:const ImportedCatalog[:],unit:u32,options:ModuleOptions)->Checked,blot_error::Error {return checkModuleWithPrivateExecution(tree,pool,imports,catalogs,unit,options,PrivateExecution{..});}
fn checkModuleWithPrivateExecution(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],catalogs:const ImportedCatalog[:],unit:u32,options:ModuleOptions,execution:PrivateExecution)->Checked,blot_error::Error {if unit==0 {return default<Checked>(),blot_error::Error.invalid_unit;}return checkInternalExecution(tree,pool,imports,[],catalogs,[],unit,true,options,false,execution);}
fn checkInternal(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],unit:u32,allow_imports:bool,options:ModuleOptions,source_validation:bool)->Checked,blot_error::Error {return checkInternalExecution(tree,pool,imports,headers,catalogs,source_catalogs,unit,allow_imports,options,source_validation,PrivateExecution{..});}
fn checkInternalExecution(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],unit:u32,allow_imports:bool,options:ModuleOptions,source_validation:bool,execution:PrivateExecution)->Checked,blot_error::Error {if !source_validation && hasNumericFailure(tree) {return rejectNumericSource(tree,pool,imports,catalogs,unit,options);}return checkInternalUnchecked(tree,pool,imports,headers,catalogs,source_catalogs,unit,allow_imports,options,source_validation,execution);}
fn checkInternalUnchecked(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],unit:u32,allow_imports:bool,options:ModuleOptions,source_validation:bool,execution:PrivateExecution)->Checked,blot_error::Error {var exhaustion=BudgetExhaustion{..};let result,error=checkEngine(tree,pool,imports,headers,catalogs,source_catalogs,unit,allow_imports,options,source_validation,execution,exhaustion);if error!=blot_error::Error.type_limit || !exhaustion.exhausted {return result,error;}return rejectExhaustedBudget(pool,unit,inferenceBudget(options),exhaustion);}
fn rejectExhaustedBudget(pool:const blot_parse_symbols::Pool&,unit:u32,limit:i64,exhaustion:BudgetExhaustion)->Checked,blot_error::Error {var label:const u8[:]="Type inference exceeded this module's budget";var exhausted_limit=limit;var code=Code.inference_budget;if exhaustion.associated {label="Associated type normalization exceeded its work budget";exhausted_limit=exhaustion.associated_limit;code=Code.associated_limit;}var detail:u8[>..]=[];if exhaustion.name!=0 {detail.append(str(label," of ",exhausted_limit," steps while checking `",pool.get(exhaustion.name),"`"));}else {detail.append(str(label," of ",exhausted_limit," steps"));}let result,error=rejectedSource([Diagnostic{code:code,span:exhaustion.span,node:exhaustion.node,symbol:exhaustion.name,detail:blot_support::some<const u8[:]>(detail[..]), ..}]);if error!=blot_error::Error.none {return default<Checked>(),error;}var checked=result;checked.unit=unit;return checked,blot_error::Error.none;}

fn validateModuleSource(tree:const blot_parse_ast::Tree&,pool:blot_parse_symbols::Pool&,headers:const SourceHeader[:],catalogs:const SourceCatalog[:],unit:u32,options:ModuleOptions)->SourceValidation,blot_error::Error {if unit==0 {return default<SourceValidation>(),blot_error::Error.invalid_unit;}let value,error=checkInternalUnchecked(tree,pool,[],headers,[],catalogs,unit,true,options,true,PrivateExecution{..});if error!=blot_error::Error.none {return default<SourceValidation>(),error;}var checked=value;var declarations:SourceDeclaration[>..]=[];for binding in checked.bindings {declarations.push(sourceDeclaration(binding));}let owned=ownChecked_declarations(checked.owner,declarations);var result=ownedSourceValidation(checked,owned);if checked.editor.present && checked.editor.value.context.present {checked.editor.value.context.value.deinit();}releaseCheckedBodies(checked.owner);checked.owner=CheckedOwner{..};return result,blot_error::Error.none;}
fn selectedTypeChildren<S>(source:const S&,node:blot_check_types::Node)->const u32[:] {if node.tag==blot_check_types::Tag.product {return source.list(blot_check_types::List{node.a,node.b});}return source.nominalArguments(node);}
fn selectedArgumentChildren(self_:const Engine&,source:u32,tag:blot_parse_ast::Tag)->blot_parse_ast::List {if tag!=blot_parse_ast::tag_unit {return checkedAstChildren(self_.tree,source);}return blot_parse_ast::List{..};}

fn selectedPurityDeclaration(self_:PuritySource&,identity:Identity,kind:blot_check_purity_type_key::Kind)->const u8[:],blot_error::Error {let engine .=self_.engine;match kind {
  nominal => {let index:u32={let scalar_lookup_99 .= engine.catalogs.nominal_identities.get(identity);if !scalar_lookup_99 {return default<const u8[:]>(),blot_error::Error.source_identity_unavailable;}let scalar_value_99:u32=scalar_lookup_99;scalar_value_99};return engine.pool.get(engine.nominals[index].name),blot_error::Error.none;},
  operation => {let index:u32={let scalar_lookup_100 .= engine.catalogs.effect_template_identities.get(identity);if !scalar_lookup_100 {return default<const u8[:]>(),blot_error::Error.source_identity_unavailable;}let scalar_value_100:u32=scalar_lookup_100;scalar_value_100};let template=engine.effect_templates[index];if template.family==0 {return default<const u8[:]>(),blot_error::Error.source_identity_unavailable;}let family=engine.effect_families[template.family];if family.callable {return engine.pool.get(family.name),blot_error::Error.none;}else {let text=str(engine.pool.get(family.name),".",engine.pool.get(template.name));let owned=ownDiagnosticText(text);let error=self_.texts.push(owned,purity_text_refs);if error!=blot_error::Error.none {freeDiagnosticText(owned);return default<const u8[:]>(),error;}return owned,blot_error::Error.none;}},
 }}

// Invocation-local borrowed contexts are constructed outside inference cycles.
fn makeVisibilityContext(engine:Engine&)->VisibilityContext {return VisibilityContext{engine,..};}
fn makeImplementationOrderContext(engine:Engine&)->ImplementationOrderContext {return ImplementationOrderContext{engine,..};}
fn makeReflectionOrder(engine:Engine&)->ReflectionOrder {return ReflectionOrder{engine,..};}
fn makePuritySource(engine:Engine&)->PuritySource {return PuritySource{engine:engine,..};}
fn makeDiscoveryResolver(engine:Engine&)->DiscoveryResolver {return DiscoveryResolver{engine,..};}
fn makeKeyFieldOrder(store:blot_check_types::Store,node:blot_check_types::Node,order:u32[:])->KeyFieldOrder {return KeyFieldOrder{store,node,order,..};}
fn makeKeyByteOrder(values:KeyBuffer[:])->KeyByteOrder {return KeyByteOrder{values,..};}
fn finishNamedExplanation(pool:const blot_parse_symbols::Pool&,builder:blot_reuse_dispatch_explanation::Builder&,member:u32,operator:blot_check_types::Operator)->blot_reuse_dispatch_explanation::Explanation,blot_error::Error {let spelled=blot_reuse_dispatch_explanation::operatorMember(operator);if member!=0 {return builder.finish(blot_reuse_dispatch_explanation::operatorSymbol(operator),blot_support::some<const u8[:]>(pool.get(member)));}return builder.finish(blot_reuse_dispatch_explanation::operatorSymbol(operator),spelled);}
fn addNamedExplanationStep(pool:const blot_parse_symbols::Pool&,builder:blot_reuse_dispatch_explanation::Builder&,symbol:u32,ty:const u8[:],outcome:blot_reuse_dispatch_explanation::Outcome)->blot_error::Error {if symbol!=0 {return builder.addStep(blot_support::some(pool.get(symbol)),blot_support::some<const u8[:]>(ty),outcome);}return builder.addStep(blot_support::none<const u8[:]>(),blot_support::some<const u8[:]>(ty),outcome);}
fn makeExplanationOrigin(builder:blot_reuse_dispatch_explanation::Builder&,name:const u8[:],path:const u8[:],path_error:blot_error::Error,span:blot_support::Option<blot_parse_ast::Span>)->blot_reuse_dispatch_explanation::Origin,blot_error::Error {if path_error==blot_error::Error.none {return builder.makeOrigin(name,blot_support::some(path),span);}return builder.makeOrigin(name,blot_support::none<const u8[:]>(),span);}

fn borrowedTypeSource(store:const blot_check_types::Store&)->blot_check_frozen_types::Source {return blot_check_frozen_types::fromStore(store);}
fn frozenTypeSource(graph:blot_check_frozen_types::Graph)->blot_check_frozen_types::Source {return blot_check_frozen_types::Source.frozen{graph,..};}

fn borrowedPatternSource(store:blot_check_parameter_patterns::Store)->blot_check_frozen_types::Patterns {return blot_check_frozen_types::fromPatterns(store);}
fn frozenPatternSource(graph:blot_check_frozen_types::PatternGraph)->blot_check_frozen_types::Patterns {return blot_check_frozen_types::Patterns.frozen{graph,..};}

// Immutable syntax traversals carry ranges across mutable checker calls.
fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {let count=tree.list(range).len;return range;}
fn checkedAstRange(tree:const blot_parse_ast::Tree&,start:u32,end:i64)->blot_parse_ast::List {let count=tree.extra.items[start..end].len;return blot_parse_ast::List{start:start,len:count as u32,..};}
fn checkedAstSubspan(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List,start:i64,end:i64)->blot_parse_ast::List {let count=tree.list(range)[start..end].len;return blot_parse_ast::List{start:range.start+start as u32,len:count as u32,..};}
fn checkedAstChildren(tree:const blot_parse_ast::Tree&,source:u32)->blot_parse_ast::List {let count=tree.children(source).len;let node=tree.node(source);if node.tag==blot_parse_ast::tag_record {return blot_parse_ast::List{start:node.b,len:count as u32,..};}if count!=0 {return blot_parse_ast::List{start:node.a,len:count as u32,..};}return blot_parse_ast::List{..};}

// Type graph list payloads remain stable while substitutions change their scalar members.
fn checkedTypeList(types:const blot_check_types::Store&,range:blot_check_types::List)->blot_check_types::List {let count=types.list(range).len;return range;}
fn checkedTypeSubspan(types:const blot_check_types::Store&,range:blot_check_types::List,start:i64,end:i64)->blot_check_types::List {let count=types.list(range)[start..end].len;return blot_check_types::List{start:range.start+start as u32,len:count as u32,..};}
fn checkedPatternList(patterns:const blot_check_parameter_patterns::Store&,range:blot_check_types::List)->blot_check_types::List {let count=patterns.list(range).len;return range;}
fn checkedNominalArguments(types:const blot_check_types::Store&,value:blot_check_types::Node)->blot_check_types::List {let count=types.nominalArguments(value).len;return blot_check_types::List{start:value.c+1,len:count as u32,..};}
fn checkedOperationArguments(types:const blot_check_types::Store&,label:u32)->blot_check_types::List {let operation=types.operation(label);return checkedTypeList(types,operation.arguments);}
fn checkedRowLabels(types:const blot_check_types::Store&,id:u32)->blot_check_effects::List {let row=types.row(id);let count=types.effects.list(row.labels).len;return row.labels;}
fn typeArgumentCount<A>(values:A)->i64 {return values.len as i64;}
fn typeArgumentAt(self_:const Engine&,values:const u32[:],index:i64)->u32 {return values[index];}
fn typeArgumentAt(self_:const Engine&,values:blot_check_types::List,index:i64)->u32 {return self_.types.list(values)[index];}
