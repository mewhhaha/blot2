// Source inference. Tables borrow explicit compilation owners.
namespace blot_check_check;
import support.error;
import support.option;
import support.structural;
import support.native;
import std;
import dictionary;
struct ProofContract {
    binding: BindingId,
    header: blot_check_numeric_proof_headers::Owned,
    parameters: BindingId[:]
}
struct ImportedFixity {
    operator: blot_parse_symbols::Symbol,
    target: blot_parse_symbols::Symbol,
    named: bool,
    external: blot_support::Option<ExternalTarget> = blot_support::none<ExternalTarget>(),
    origin: blot_parse_ast::Id = 0
}
struct EditorMarker {
    span: blot_parse_ast::Span,
    kind: blot_reuse_completion_probe::Kind,
    prefix: const u8[:] = ""
}
enum EditorName_kind { value, function, type_, constructor, field, member, module }
struct EditorName {
    name: blot_parse_symbols::Symbol,
    kind: EditorName_kind,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {},
    distance: u32 = 0,
    identity: Identity = Identity { unit: 0, decl: 0 },
    external: blot_support::Option<ExternalTarget> = blot_support::none<ExternalTarget>(),
    ambiguous: bool = false,
    receiver: bool = false
}
struct EditorCapture {
    names: EditorName[:] = [],
    kind: blot_reuse_completion_probe::Kind,
    node: blot_parse_ast::Id,
    scope: blot_check_types::List,
    visible: blot_check_types::List = blot_check_types::List {},
    visible_names: blot_check_types::List = blot_check_types::List {},
    scope_names: blot_check_types::List = blot_check_types::List {},
    type_scope: blot_check_types::List = blot_check_types::List {},
    truncated: bool = false,
    owner: BindingId,
    receiver: blot_check_types::Id = 0,
    namespace: blot_parse_symbols::Symbol = 0,
    context: blot_support::Option<blot_reuse_hole_diagnostics::Snapshot> = blot_support::none<blot_reuse_hole_diagnostics::Snapshot>()
}
struct ModuleOptions {
    editor: blot_support::Option<EditorMarker> = blot_support::none<EditorMarker>(),
    purity_origins: ModuleOrigins = ModuleOrigins {},
    builtin_catalog: bool = false,
    prelude_unit: u32 = 0,
    inherited_fixities: const ImportedFixity[:] = [],
    max_inference_transitions: blot_support::Option<i64> = blot_support::none<i64>(),
    associated_remaining: i64? = null,
    body_source: const u8[:] = [],
    retained_bodies: blot_reuse_body_check_cache::Cache? = null,
    previous_bodies: const blot_reuse_body_check_cache::Cache? = null,
    body_external_names: blot_support::Option<blot_reuse_body_check_cache::ExternalNames> = blot_support::none<blot_reuse_body_check_cache::ExternalNames>(),
    producer_capabilities: blot_support::Option<ProducerCapabilities> = blot_support::none<ProducerCapabilities>(),
    producer_storage: blot_support::Option<ProducerStorage> = blot_support::none<ProducerStorage>()
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
    instance: Identity = Identity { unit: 0, decl: 0 },
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
struct EffectMember {
    family: u32,
    member: blot_parse_symbols::Symbol
}
struct Rebinding {
    root: BindingId = 0,
    self_binding: BindingId = 0,
    path: blot_check_types::List = blot_check_types::List {}
}
struct Projection {
    nominal: Identity,
    field: blot_parse_symbols::Symbol,
    variants: blot_check_types::List
}
enum ImportedCatalog_kind { catalog, nominal, constructor, effect_family, contract, implementation }
struct ImportedCatalog {
    producer: const Checked? = null,
    frozen: const blot_reuse_principal_interface::Interface? = null,
    namespace: blot_parse_symbols::Symbol = 0,
    name: blot_parse_symbols::Symbol = 0,
    kind: ImportedCatalog_kind,
    index: u32,
    origin: blot_parse_ast::Id
}
struct SourceCatalog {
    producer: DeclarationCatalog,
    declarations: const SourceDeclaration[:],
    namespace: blot_parse_symbols::Symbol = 0,
    name: blot_parse_symbols::Symbol = 0,
    kind: ImportedCatalog_kind,
    index: u32,
    origin: blot_parse_ast::Id
}
struct SchemeSummary {
    flat_size: u32 = 0,
    public_variables: blot_check_types::List = blot_check_types::List {},
    public_rows: blot_check_types::List = blot_check_types::List {},
    public_inputs: blot_check_types::List = blot_check_types::List {},
    public_outputs: blot_check_types::List = blot_check_types::List {},
    only_result_selected: bool = false,
    requirement_variables: blot_check_types::List = blot_check_types::List {},
    requirement_rows: blot_check_types::List = blot_check_types::List {},
    has_explicit: bool = false,
    shareable: bool = false
}
struct Binding {
    read: bool = false,
    capability_flow: CapabilityFlow = CapabilityFlow.unknown,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    operation_ref: u32 = 0,
    private: bool = false,
    name: blot_parse_symbols::Symbol,
    declaration: blot_parse_ast::Id,
    owner: blot_parse_ast::Id,
    kind: Kind,
    named_function: bool = false,
    ty: blot_check_types::Id,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {},
    external: blot_support::Option<ExternalTarget> = blot_support::none<ExternalTarget>(),
    predecessor: BindingId = 0,
    summary: SchemeSummary = SchemeSummary {}
}
struct SchemeInterface {
    summary: blot_support::Option<SchemeSummary> = blot_support::none<SchemeSummary>(),
    producer_binding: BindingId = 0,
    proof_contract: const blot_check_numeric_proof_headers::Owned? = null,
    capability_flow: CapabilityFlow = CapabilityFlow.unknown,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    named_function: bool = false,
    types: blot_check_frozen_types::Source,
    scheme: blot_check_types::Scheme,
    obligations: const blot_check_types::Obligation[:],
    callees: Callees = Callees.none,
    capability_source: blot_support::Option<CapabilitySource> = blot_support::none<CapabilitySource>()
}
enum Callees { none, live { value: const Checked& }, frozen { value: const blot_reuse_principal_interface::Interface& } }
struct ImportedBinding {
    name: blot_parse_symbols::Symbol = 0,
    namespace: blot_parse_symbols::Symbol = 0,
    member: blot_parse_symbols::Symbol = 0,
    target: ExternalTarget,
    interface: SchemeInterface,
    origin: blot_parse_ast::Id,
    expose: bool = true
}
struct SourceHeader {
    capability_flow: CapabilityFlow = CapabilityFlow.unknown,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    name: blot_parse_symbols::Symbol = 0,
    namespace: blot_parse_symbols::Symbol = 0,
    member: blot_parse_symbols::Symbol = 0,
    target: ExternalTarget,
    named_function: bool = false,
    origin: blot_parse_ast::Id,
    expose: bool = true
}
struct SourceDeclaration {
    capability_flow: CapabilityFlow = CapabilityFlow.unknown,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    private: bool = false,
    name: blot_parse_symbols::Symbol,
    declaration: blot_parse_ast::Id,
    kind: Kind,
    named_function: bool,
    external: blot_support::Option<ExternalTarget>
}
struct ProducerCapability {
    flow: CapabilityFlow = CapabilityFlow.unknown,
    parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    recipe: blot_support::Option<CapabilitySource> = blot_support::none<CapabilitySource>()
}
struct CapabilitySource {
    callees: Callees,
    binding: BindingId
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
    contracts: const Contract[:] = [],
    contract_predicates: const blot_check_types::Obligation[:] = [],
    contract_members: const ContractMember[:] = [],
    implementations: const Implementation[:] = [],
    implementation_predicates: const blot_check_types::Obligation[:] = [],
    implementation_members: const ImplementationMember[:] = []
}
enum ResolverKind { monad, pure, bind, forward, iterate }
struct ResolverBlock {
    node: blot_parse_ast::Id,
    resolver: BindingId,
    result: blot_check_types::Id,
    body_effects: blot_check_effects::Id = 0,
    fallthrough: u32 = 0
}
struct EffectScope {
    node: blot_parse_ast::Id,
    callback: blot_parse_ast::Id,
    parameter: blot_parse_ast::Id,
    capability: blot_check_types::Id,
    result: blot_check_types::Id,
    body_effects: blot_check_effects::Id
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
struct ResolverOp {
    node: blot_parse_ast::Id,
    kind: ResolverKind,
    member: blot_parse_symbols::Symbol = 0,
    resolver: BindingId = 0,
    method: BindingId = 0,
    method_type: blot_check_types::Id = 0,
    payload: blot_check_types::Id = 0,
    result: blot_check_types::Id = 0,
    continuation_parameter: BindingId = 0,
    completed_types: blot_check_types::List = blot_check_types::List {},
    done_constructor: u32 = 0,
    completion: u32 = 0
}
struct ResolverJoin {
    node: blot_parse_ast::Id,
    parameter: BindingId,
    ty: blot_check_types::Id,
    result: blot_check_types::Id
}
struct ResolverCompletion {
    node: blot_parse_ast::Id,
    bind: u32,
    pure: u32,
    completed_types: blot_check_types::List,
    done_constructor: u32
}
struct ResolverLoop {
    node: blot_parse_ast::Id,
    cursor_parameter: BindingId,
    first_binding: BindingId,
    end_binding: BindingId,
    cursor: blot_check_types::Id,
    step_result: blot_check_types::Id,
    suffix_result: blot_check_types::Id,
    iterate: u32,
    continued: u32,
    finish: u32,
    continue_constructor: u32,
    done_constructor: u32
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
    loop: blot_parse_ast::Id,
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
enum Code { function_return_required, task_escape, task_handle_consumed, task_capture_transfer, task_capability_shared, task_regions_overlap, task_host_contract, task_budget, invalid_proof_operand, proof_scope_escape, proof_runtime_use, proof_mismatch, contradictory_proof, proof_analysis_limit, effect_identity_scope, capability_escape, capability_analysis_limit, undetermined_implementation, orphan_implementation, overlapping_implementation, incompatible_implementation, recursive_evidence, missing_type_member, associated_arity, recursive_associated_type, associated_limit, missing_implementation, private_access, private_identity_escape, unbound_alias_row, recursive_contract, contract_arity, recursive_type_alias, typed_hole, effect_member, integer_range, float_range, float_literal, module_loader_required, intrinsic_arity, requests_scope, yield_scope, request_loop_scope, request_loop_body, request_loop_range, request_binding, request_completion, request_clause_fallthrough, request_completion_fallthrough, duplicate_request_handler, request_case_scope, unknown_value, syntax, duplicate_name, unknown_name, type_mismatch, infinite_type, effect_mismatch, infinite_effect, const_effect, initializer_effect, let_effect, sealed_effect, effect_arity, effect_family, unknown_effect, invalid_effect_annotation, invalid_constraint, higher_rank_constraint, missing_predicate, ambiguous_qualified, annotation_kind_mismatch, unsupported_polymorphic_effect_label, operation_signature, type_arity, operation_target, invalid_state_provider, unsupported, unsupported_attribute, recursive_tag, function_target, open_effect_descriptor, unsupported_expression, unsupported_type, ambiguous_operator, ambiguous_associated, missing_associated, ambiguous_member, missing_member, type_constructor_required, invalid_provider, resolver_required, literal_required, call_arity, break_scope, continue_scope, invalid_return, unreachable_statement, invalid_operator, return_outside_block, return_outside_function, return_across_continuation, unknown_rebinding, dead_rebinding, case_arm_return, nesting_limit, unknown_constructor, constructor_marker, type_parameter, type_argument, duplicate_type_parameter, duplicate_type_field, unknown_field, duplicate_field, missing_field, non_exhaustive_match, refutable_pattern, constructor_arity, unknown_product_shape, product_index, product_index_literal, pattern_arity, pattern_bindings, value_pattern_type, non_exiting_fallback, unknown_operator, operator_associativity, operator_header_order, operator_precedence, duplicate_operator, unsupported_prefix, unknown_intrinsic, alternative_bindings, duplicate_pattern_binding, duplicate_record_field, unknown_record_field, record_constructor, missing_record_field, unknown_modifier, guard_fallthrough, product_arity, inference_budget, skolem_escape, rank_mismatch, package_expected, package_witness_mismatch, package_escape, abstract_representation_access, use_after_move, duplicate_owner, borrow_conflict, borrow_escape, once_reused, multiplicity_unknown, cleanup_not_safe, usage_evidence_mismatch, usage_analysis_limit, code_shape_mismatch, stage_unavailable, cross_stage_authority, descriptor_private, generated_binding_escape, staging_budget }
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
struct RequestArm {
    node: blot_parse_ast::Id,
    loop: blot_parse_ast::Id,
    operation_source: blot_parse_ast::Id = 0,
    operation: blot_check_effects::Label,
    parameter_type: blot_check_types::Id,
    reply_type: blot_check_types::Id,
    signature: blot_check_types::Id,
    pattern: blot_parse_ast::Id,
    suite: blot_parse_ast::Id,
    state_bindings: blot_check_types::List
}
struct RequestLoop {
    node: blot_parse_ast::Id,
    computation: blot_parse_ast::Id,
    value_type: blot_check_types::Id,
    result_type: blot_check_types::Id,
    state_type: blot_check_types::Id,
    action_type: blot_check_types::Id,
    arms: blot_check_types::List,
    completion: blot_parse_ast::Id,
    complete_pattern: blot_parse_ast::Id,
    complete_suite: blot_parse_ast::Id,
    complete_state_bindings: blot_check_types::List,
    carried: blot_check_types::List,
    return_scope: blot_parse_ast::Id
}
enum RequestControl_kind { reply, cancel, break_ }
struct RequestControl {
    node: blot_parse_ast::Id,
    loop: blot_parse_ast::Id,
    kind: RequestControl_kind,
    value_type: blot_check_types::Id,
    bindings: blot_check_types::List = blot_check_types::List {},
    target_scope: blot_parse_ast::Id
}
struct UsageLoan {
    source: blot_parse_ast::Id,
    callback: blot_parse_ast::Id,
    parameter: blot_parse_ast::Id,
    region: blot_check_types::Id,
    mutable: bool,
    acquire: blot_parse_ast::Id = 0,
    release: blot_parse_ast::Id = 0
}
struct DictionaryUse {
    source: blot_parse_ast::Id,
    opening: BindingId,
    introduction: blot_parse_ast::Id = 0,
    quantifier: blot_check_types::Id,
    goal: u32,
    member: u32
}
struct DictionaryGiven {
    opening: BindingId,
    introduction: blot_parse_ast::Id = 0,
    quantifier: blot_check_types::Id,
    goal: u32,
    arguments: blot_check_types::List,
    member_types: blot_check_types::List
}
enum DictionaryProof { selected { value: u32 }, given { value: DictionaryGiven } }
struct DictionarySelection {
    source: blot_parse_ast::Id,
    quantifier: blot_check_types::Id,
    goal: u32,
    proof: DictionaryProof
}
struct RankImplementation {
    scope: u32,
    quantified: blot_check_types::Id,
    node: blot_parse_ast::Id = 0
}
struct CoveredRequirement {
    scope: blot_parse_ast::Id,
    value: blot_check_types::Obligation
}
struct Checked {
    function_exit_lambdas: blot_parse_ast::Id[:] = [],
    usage_loans: UsageLoan[:] = [],
    proof_contracts: ProofContract[:] = [],
    proof_bodies: blot_check_numeric_proof_bodies::Owned = blot_check_numeric_proof_bodies::Owned {},
    rank_implementations: RankImplementation[:] = [],
    generative_bindings: blot_check_generative_schemes::Binder[:] = [],
    dictionary_selections: DictionarySelection[:] = [],
    dictionary_uses: DictionaryUse[:] = [],
    capability_contracts: blot_check_capability_contracts::Collection = blot_check_capability_contracts::Collection {},
    editor: blot_support::Option<EditorCapture> = blot_support::none<EditorCapture>(),
    iterator_bodies: blot_parse_ast::Id[:] = [],
    initializer_rejected: bool = false,
    computations: Computation[:] = [],
    request_loops: RequestLoop[:] = [],
    request_arms: RequestArm[:] = [],
    request_controls: RequestControl[:] = [],
    reflections: Reflection[:] = [],
    tag_origins: TagOrigin[:] = [],
    effect_scopes: EffectScope[:] = [],
    effect_scope_ids: u32[:] = [],
    effect_runners: EffectRunner[:] = [],
    effect_runner_ids: u32[:] = [],
    provider_blocks: ProviderBlock[:] = [],
    provider_block_ids: u32[:] = [],
    body_closed_rows: ClosedRow[:] = [],
    lambda_closed_rows: blot_check_types::List[:] = [],
    dispatch_signatures: blot_check_types::Id[:] = [],
    covered_requirements: CoveredRequirement[:] = [],
    effect_families: EffectFamily[:] = [],
    effect_templates: EffectTemplate[:] = [],
    operation_uses: OperationUse[:] = [],
    operation_refs: u32[:] = [],
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
    counters: Counters = Counters {},
    unit: u32 = 1,
    associated: Associated[:] = [],
    nominals: Nominal[:] = [],
    contracts: Contract[:] = [],
    contract_predicates: blot_check_types::Obligation[:] = [],
    contract_members: ContractMember[:] = [],
    implementations: Implementation[:] = [],
    implementation_predicates: blot_check_types::Obligation[:] = [],
    implementation_members: ImplementationMember[:] = [],
    member_templates: blot_reuse_principal_interface::MemberTemplate[:] = [],
    selected_proofs: blot_reuse_principal_interface::SelectedProof[:] = [],
    selected_members: ImplementationMember[:] = [],
    selected_edges: u32[:] = [],
    selected_uses: blot_reuse_principal_interface::SelectedUse[:] = [],
    constructors: Constructor[:] = [],
    constructor_resolved: u32[:] = [],
    projections: u32[:] = [],
    access_paths: blot_check_types::List[:] = [],
    access_nodes: blot_check_types::List[:] = [],
    access_types: blot_check_types::List[:] = [],
    projection_resolved: u32[:] = [],
    projection_catalog: Projection[:] = [],
    rebindings: Rebinding[:] = [],
    resolver_blocks: ResolverBlock[:] = [],
    resolver_ops: ResolverOp[:] = [],
    resolver_joins: ResolverJoin[:] = [],
    resolver_completions: ResolverCompletion[:] = [],
    resolver_loops: ResolverLoop[:] = [],
    resolver_block_ids: u32[:] = [],
    resolver_op_ids: u32[:] = [],
    resolver_join_ids: u32[:] = [],
    resolver_loop_ids: u32[:] = [],
    loop_carries: LoopCarry[:] = [],
    loop_ranges: blot_check_types::List[:] = [],
    loop_exits: LoopExit[:] = [],
    statement_arms: StatementArm[:] = []
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
    expansion: u32 = 0
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
struct SelectedGlobal {
    binding: BindingId,
    owner: BindingId,
    diagnostic_at: i64
}
struct LoopFrame {
    node: blot_parse_ast::Id,
    carries: const Entry[:],
    iterations: const BindingId[:],
    resolver_block: blot_parse_ast::Id = 0,
    exits: i64 = 0
}
struct ResolverScope {
    block: blot_parse_ast::Id = 0,
    resolver: BindingId = 0,
    owner_type: blot_check_types::Id = 0,
    result: blot_check_types::Id = 0,
    progress_depth: u32 = 0
}
struct RequestScope {
    loop: blot_parse_ast::Id = 0,
    reply: blot_check_types::Id = 0,
    target: blot_check_types::Id = 0,
    completion: bool = false,
    return_scope: blot_parse_ast::Id = 0,
    arm: u32 = 0,
    state_bindings: blot_check_types::List = blot_check_types::List {},
    invalid_outer_return: bool = false
}
struct Flow {
    ty: blot_check_types::Id = blot_check_types::unit,
    exits: bool = false,
    returns: bool = false,
    breaks: bool = false
}
struct Qualified {
    namespace: blot_parse_symbols::Symbol,
    member: blot_parse_symbols::Symbol
}
struct QualifiedResolution {
    namespace: blot_parse_symbols::Symbol,
    binding: BindingId
}
struct OperatorOverride {
    target: blot_parse_symbols::Symbol,
    named: bool,
    external: blot_support::Option<ExternalTarget> = blot_support::none<ExternalTarget>()
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
    constructor_identities: dictionary<Identity,u32>&,
    nominal_names: dictionary<Qualified,u32>&,
    constructor_names: dictionary<Qualified,u32>&,
    associated_ops: dictionary<AssociatedKey,u32>&,
    associated_members: dictionary<AssociatedMember,u32>&,
    qualified: dictionary<Qualified,BindingId>&,
    external_targets: dictionary<ExternalTarget,BindingId>&,
    globals: dictionary<blot_parse_symbols::Symbol,BindingId>&,
    overrides: dictionary<blot_parse_symbols::Symbol,OperatorOverride>&
}
struct ArmCapture {
    block: blot_parse_ast::Id,
    versions: BindingId[:],
    carrying: bool = false
}
struct Engine {
    import_callees: u32[>..<]&,
    import_variables: u32[>..<]&,
    import_tables: blot_check_check_scheme_import::Tables,
    proof_header_owned: blot_check_numeric_proof_headers::OwnedTables,
    name_bytes: u8[>..<]&,
    diagnostic_bytes: u8[>..<]&,
    expected_bytes: u8[>..<]&,
    actual_bytes: u8[>..<]&,
    header_diagnostics: Diagnostic[>..<]&,
    frontend_work: blot_work_counters::Frontend = blot_work_counters::Frontend {},
    catalogs: CatalogIndex,
    associated_usage_work: blot_check_usage_check::Work = blot_check_usage_check::Work {},
    usage_loans: UsageLoan[>..<]&,
    staging_depth: u32 = 0,
    staging_bindings: dictionary<BindingId,u32>&,
    proof_contracts: ProofContract[>..<]&,
    proof_body: blot_check_numeric_proof_bodies::Builder,
    proof_visits: i64 = 0,
    proof_header_active: bool = false,
    body_external_names: blot_support::Option<blot_reuse_body_check_cache::ExternalNames> = blot_support::none<blot_reuse_body_check_cache::ExternalNames>(),
    body_source: const u8[:] = [],
    retained_bodies: blot_reuse_body_check_cache::Cache? = null,
    previous_bodies: const blot_reuse_body_check_cache::Cache? = null,
    editor_marker: blot_support::Option<EditorMarker> = blot_support::none<EditorMarker>(),
    editor_capture: blot_support::Option<EditorCapture> = blot_support::none<EditorCapture>(),
    scratch_pool: blot_eval_region_arena::Pool,
    pending_arena: blot_eval_region_arena::Arena? = null,
    active_aliases: dictionary<u32,bool>&,
    holes: Engine_holes[>..<]&,
    execution: PrivateExecution = PrivateExecution {},
    inference_limit: i64 = 1_000_000,
    inference_transitions: i64 = 0,
    budget_exhaustion: BudgetExhaustion? = null,
    root_global: BindingId = 0,
    finishing_group: const BindingId[:] = [],
    dependency_owner: blot_support::Option<BindingId> = blot_support::none<BindingId>(),
    exact_argument_types: bool = false,
    implementation_trace: blot_eval_implementation_trace::Record = blot_eval_implementation_trace::Record {},
    proved_predicate_target: ExternalTarget = ExternalTarget { unit: 0, binding: 0 },
    proved_predicate_prerequisites: blot_check_types::List = blot_check_types::List {},
    active_predicates: Engine_active_predicates[>..<]&,
    computations: Computation[>..<]&,
    request_loops: RequestLoop[>..<]&,
    request_arms: RequestArm[>..<]&,
    request_controls: RequestControl[>..<]&,
    reflections: Reflection[>..<]&,
    case_pattern_source: blot_parse_ast::Id = 0,
    let_pattern_source: blot_parse_ast::Id = 0,
    tag_origins: TagOrigin[:] = [],
    effect_scopes: EffectScope[>..<]&,
    effect_scope_ids: u32[:] = [],
    scoped_parameter: blot_parse_ast::Id = 0,
    scoped_parameter_type: blot_check_types::Id = 0,
    active_effect_scopes: i64 = 0,
    has_tasks: bool = false,
    task_region_parameter: blot_parse_ast::Id = 0,
    expected_lambda_source: blot_parse_ast::Id = 0,
    expected_lambda_type: blot_check_types::Id = 0,
    scope_lifetimes: blot_check_types::Id[>..<]&,
    capability_store: blot_check_capability_contracts::Store,
    generative_owner: blot_parse_ast::Id = 0,
    generative_bindings: blot_check_generative_schemes::Binder[>..<]&,
    has_input_invocations: bool = false,
    capability_roots: blot_check_capability_contracts::Binding[>..<]&,
    storage_frames: Engine_storage_frames[>..<]&,
    effect_runners: EffectRunner[>..<]&,
    effect_runner_ids: u32[:] = [],
    provider_blocks: ProviderBlock[>..<]&,
    provider_block_ids: u32[:] = [],
    body_closed_rows: ClosedRow[>..<]&,
    covered_requirements: CoveredRequirement[>..<]&,
    rank_implementations: RankImplementation[>..<]&,
    dictionary_selections: DictionarySelection[>..<]&,
    dictionary_uses: DictionaryUse[>..<]&,
    dictionary_givens: Engine_dictionary_givens[>..<]&,
    annotation_givens: blot_check_types::Obligation[>..<]&,
    closed_row_keys: dictionary<ClosedRow,bool>&,
    row_sources: dictionary<u32,blot_parse_ast::Id>&,
    purity_origins: ModuleOrigins = ModuleOrigins {},
    initializer_rejected: bool = false,
    lambda_closed_rows: blot_check_types::List[:] = [],
    dispatch_signatures: blot_check_types::Id[:] = [],
    effect_families: EffectFamily[>..<]&,
    effect_templates: EffectTemplate[>..<]&,
    operation_uses: OperationUse[>..<]&,
    operation_refs: u32[:] = [],
    tree: const blot_parse_ast::Tree&,
    pool: blot_parse_symbols::Pool&,
    types: blot_check_types::Store,
    parameter_patterns: blot_check_parameter_patterns::Store,
    expr_types: blot_check_types::Id[:],
    resolved: BindingId[:],
    bindings: Binding[>..<]&,
    imported_values: dictionary<ExternalTarget,ImportedBinding>&,
    imported_globals: dictionary<blot_parse_symbols::Symbol,ExternalTarget>&,
    imported_qualified: dictionary<Qualified,ExternalTarget>&,
    merges: Merge[>..<]&,
    obligations: blot_check_types::Obligation[>..<]&,
    pending: PendingObligation[>..<]&,
    pending_queue: blot_check_solver_worklist::Queue = blot_check_solver_worklist::Queue {},
    scheme_dependencies: blot_check_scheme_dependencies::Cache = blot_check_scheme_dependencies::Cache {},
    counters: Counters = Counters {},
    callee_memo: dictionary<const u8[:],CalleeOutcome>&,
    mark_depth: u32 = 0,
    dispatch_side: blot_reuse_dispatch_explanation::Side = blot_reuse_dispatch_explanation::Side.left,
    expansion_serial: u32 = 0,
    expansion_depth: u32 = 0,
    qualification_scope: blot_parse_ast::Id = 0,
    request_scope: RequestScope = RequestScope {},
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
    arm_capture: ArmCapture? = null,
    arm_block: blot_parse_ast::Id = 0,
    arm_nested_return: blot_parse_ast::Id = 0,
    current: BindingId = 0,
    pending_start: i64 = 0,
    owner: blot_parse_ast::Id = 0,
    proof_owner: blot_parse_ast::Id = 0,
    return_target: blot_check_types::Id = 0,
    ambient: blot_check_effects::Id = 0,
    resolver_scope: ResolverScope = ResolverScope {},
    counter: u32 = 0,
    depth: i64 = 0,
    permitted_intrinsic: blot_parse_ast::Id = 0,
    closed_type_variables: bool = false,
    implicit_row_parameters: bool = false,
    body_elaborations: i64 = 0,
    self_name: blot_parse_symbols::Symbol,
    unit: u32 = 1,
    builtin_catalog: bool = false,
    source_validation: bool = false,
    producer_capabilities: blot_support::Option<ProducerCapabilities> = blot_support::none<ProducerCapabilities>(),
    producer_storage: blot_support::Option<ProducerStorage> = blot_support::none<ProducerStorage>(),
    source_annotation_failed: bool = false,
    source_header_diagnostics: Diagnostic[:] = [],
    prelude_unit: u32 = 0,
    nominals: Nominal[>..<]&,
    contracts: Contract[>..<]&,
    contract_predicates: blot_check_types::Obligation[>..<]&,
    contract_members: ContractMember[>..<]&,
    implementations: Implementation[>..<]&,
    implementation_predicates: blot_check_types::Obligation[>..<]&,
    implementation_members: ImplementationMember[>..<]&,
    member_templates: blot_reuse_principal_interface::MemberTemplate[>..<]&,
    selected_proofs: blot_reuse_principal_interface::SelectedProof[>..<]&,
    selected_members: ImplementationMember[>..<]&,
    selected_edges: u32[>..<]&,
    selected_uses: blot_reuse_principal_interface::SelectedUse[>..<]&,
    checking_implementation: blot_support::Option<u32> = blot_support::none<u32>(),
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
    constructors: Constructor[>..<]&,
    type_env: TypeEnvironment = TypeEnvironment {},
    row_env: RowEnvironment = RowEnvironment {},
    computation_annotations: blot_check_types::Id[>..<]&,
    annotation_binding: blot_parse_ast::Id = 0,
    inherited_types: i64 = 0,
    inherited_rows: i64 = 0,
    constructor_resolved: u32[:] = [],
    projections: u32[:] = [],
    access_paths: blot_check_types::List[:] = [],
    access_nodes: blot_check_types::List[:] = [],
    access_types: blot_check_types::List[:] = [],
    projection_resolved: u32[:] = [],
    projection_catalog: Projection[>..<]&,
    rebindings: Rebinding[:] = [],
    resolver_blocks: ResolverBlock[>..<]&,
    resolver_ops: ResolverOp[>..<]&,
    resolver_joins: ResolverJoin[>..<]&,
    resolver_completions: ResolverCompletion[>..<]&,
    resolver_loops: ResolverLoop[>..<]&,
    resolver_block_ids: u32[:] = [],
    resolver_op_ids: u32[:] = [],
    resolver_join_ids: u32[:] = [],
    resolver_loop_ids: u32[:] = [],
    loop_carries: LoopCarry[>..<]&,
    iterator_bodies: blot_parse_ast::Id[:] = [],
    loop_ranges: blot_check_types::List[:] = [],
    loop_exits: LoopExit[>..<]&,
    statement_arms: StatementArm[>..<]&,
    loop_stack: LoopFrame[>..<]&,
    cases: blot_parse_ast::Id[>..<]&,
    associated: Associated[>..<]&
}
struct AuxiliaryReplay {
    engine: Engine&,
    owner: const blot_reuse_body_auxiliary::Owner&,
    ids: const blot_parse_ast::Id[:],
    bindings: const BindingId[:],
    copier: SchemeCopier&,
    fields: const blot_parse_symbols::Symbol[:],
    identities: const dictionary<Identity,Identity>&&,
    operations: const dictionary<Identity,Identity>&&,
    request_arms: u32,
    resolver_ops: u32,
    resolver_completions: u32,
    operation_uses: u32
}
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
type CapabilityFlow = blot_check_capability_flow::Contract;
type PurityWitness = blot_reuse_purity_diagnostics::Witness;
fn reflectionKindCode(value: ReflectionKind) -> u32 { match value { ReflectionKind.of => {return 0;}, ReflectionKind.descriptor => {return 1;}, ReflectionKind.count => {return 2;}, ReflectionKind.has => {return 3;}, ReflectionKind.same => {return 4;}, } }
fn reflectionKindFromCode(code: u32) -> ReflectionKind,bool { match code { 0 => {return ReflectionKind.of,true;}, 1 => {return ReflectionKind.descriptor,true;}, 2 => {return ReflectionKind.count,true;}, 3 => {return ReflectionKind.has,true;}, 4 => {return ReflectionKind.same,true;}, _ => {return ReflectionKind.of,false;}, } }
fn blot_structural::equal(left: blot_check_check::ReflectionKind,right: blot_check_check::ReflectionKind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::ReflectionKind) {blot_structural::hash(sink,blot_check_check::reflectionKindCode(value));}
// Source identity and producer lookups are explicit immutable catalogs.
struct ModuleOrigin {unit:u32,name:const u8[:],source_available:bool=true}
struct ModuleOrigins {entries:const ModuleOrigin[:]=[],has_source_available:bool=false}
fn ModuleOrigins::name(self:ModuleOrigins,unit:u32,current_unit:u32)->const u8[:],blot_error::Error {for entry in self.entries {if entry.unit==unit {return entry.name,blot_error::Error.none;}}if self.entries.len!=0 || unit!=current_unit {return [],blot_error::Error.source_identity_unavailable;}return "main",blot_error::Error.none;}
fn ModuleOrigins::sourceAvailable(self:ModuleOrigins,unit:u32)->bool {for entry in self.entries {if entry.unit==unit {return entry.source_available;}}return false;}
struct TraceSink {events:GlobalTrace[>..<]&}
fn TraceSink::observe(self:TraceSink&,value:GlobalTrace) {self.events.append(value);}
struct PrivateExecution {parallel_min_nodes:i64=4096,scheme_dependency_reuse:bool=true,indexed_scheme_membership:bool=true,closed_array_locals:bool=true,eager_scheme_summaries:bool=false,imported_summary_reuse:bool=true,alias_globals:bool=false,schedule_globals:bool=true,stats:AliasGlobalStats?=null,observe:TraceSink?=null}
struct ProducerCapabilityEntry {target:ExternalTarget,value:ProducerCapability}
struct ProducerCapabilities {entries:const ProducerCapabilityEntry[:]}
fn ProducerCapabilities::lookup(self:ProducerCapabilities,target:ExternalTarget)->blot_support::Option<ProducerCapability> {for entry in self.entries {if entry.target==target {return blot_support::some(entry.value);}}return blot_support::none<ProducerCapability>();}
struct ProducerStorageEntry {identity:Identity,value:blot_backend_opaque_storage::Storage}
struct ProducerStorage {entries:const ProducerStorageEntry[:]}
fn ProducerStorage::lookup(self:ProducerStorage,identity:Identity)->blot_support::Option<blot_backend_opaque_storage::Storage> {for entry in self.entries {if entry.identity==identity {return blot_support::some(entry.value);}}return blot_support::none<blot_backend_opaque_storage::Storage>();}

struct Engine_holes {  node: blot_parse_ast::Id, scope: blot_check_types::List, owner: BindingId  }
struct Engine_active_predicates {  binding: BindingId, value: blot_check_types::Obligation  }
struct Engine_storage_frames {  read: blot_check_effects::Label, write: blot_check_effects::Label = 0, depth: i64  }
struct Engine_dictionary_givens {  opening: BindingId, introduction: blot_parse_ast::Id = 0, quantifier: blot_check_types::Id, goal: u32, predicate: blot_check_types::Obligation  }
struct Engine_active_evidence {  contract: Identity, arguments: blot_check_types::List  }
struct Engine_provisional_equations {  declaration: u32, arguments: blot_check_types::List, variables: []const blot_check_types::Id, rows: []const blot_check_effects::Id  }
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
    type_application:blot_support::Option<TypeApplication> = blot_support::none<TypeApplication>(),symbol:u32=0,implicit_type_witness:bool=false,
    source_terminator:blot_parse_source_operators::Terminator=blot_parse_source_operators::terminator_none,
    numeric_literal:blot_support::Option<blot_parse_ast::NumericFault> = blot_support::none<blot_parse_ast::NumericFault>(),
    purity:blot_support::Option<PurityWitness> = blot_support::none<PurityWitness>(),
    detail:blot_support::Option<const u8[:]> = blot_support::none<const u8[:]>(),
    hole:blot_support::Option<blot_reuse_hole_diagnostics::Snapshot> = blot_support::none<blot_reuse_hole_diagnostics::Snapshot>(),
    explanation:blot_support::Option<blot_reuse_dispatch_explanation::Explanation> = blot_support::none<blot_reuse_dispatch_explanation::Explanation>(),
    contexts:DiagnosticContext[2]=[DiagnosticContext{DiagnosticContextKind.callee,blot_parse_ast::Span{0,0}},DiagnosticContext{DiagnosticContextKind.argument,blot_parse_ast::Span{0,0}}],context_len:u8=0
}
struct BudgetExhaustion {associated:bool=false,associated_limit:i64=0,exhausted:bool=false,name:u32=0,node:u32=0,span:blot_parse_ast::Span=blot_parse_ast::Span{0,0}}
struct SourceValidation {
    types:blot_check_types::Store,parameter_patterns:blot_check_parameter_patterns::Store,declarations:SourceDeclaration[:],resolved:u32[:],nominals:Nominal[:],contracts:Contract[:],contract_predicates:blot_check_types::Obligation[:],contract_members:ContractMember[:],implementations:Implementation[:],implementation_predicates:blot_check_types::Obligation[:],implementation_members:ImplementationMember[:],member_templates:blot_reuse_principal_interface::MemberTemplate[:],selected_proofs:blot_reuse_principal_interface::SelectedProof[:],selected_members:ImplementationMember[:],selected_edges:u32[:],selected_uses:blot_reuse_principal_interface::SelectedUse[:],constructors:Constructor[:],effect_families:EffectFamily[:],effect_templates:EffectTemplate[:],associated:Associated[:],diagnostics:Diagnostic[:],unit:u32
}

fn Diagnostic::message(self:Diagnostic)->const u8[:] {
    if self.detail.present {return self.detail.value;}
    if self.type_application.present {match self.type_application.value {TypeApplication.missing_array=>{return "Array requires one element type";},TypeApplication.missing_nominal=>{return "partially applied type constructor requires another argument";},TypeApplication.extra=>{return "type does not accept another argument; currying must be explicit in its declaration";},}}
    match self.code {
        Code.task_escape => {return "A task handle, group or loan outlives its task scope";},
        Code.task_handle_consumed => {return "The task handle was already joined, cancelled or moved";},
        Code.task_capture_transfer => {return "Task captures require an owning transfer or checked immutable sharing";},
        Code.task_capability_shared => {return "A task capture shares a writable or scoped capability";},
        Code.task_regions_overlap => {return "Task regions need one owner version and proved disjoint ranges";},
        Code.task_host_contract => {return "Task host execution requires an explicit concurrent capability contract";},
        Code.task_budget => {return "Task analysis exceeds its bounded state budget";},
        Code.invalid_proof_operand => {return "A proof operand must name a preceding value of the required kind";},
        Code.proof_scope_escape => {return "The proof refers to a value outside its complete contract";},
        Code.proof_runtime_use => {return "An erased proof cannot be used as an ordinary runtime value";},
        Code.proof_mismatch => {return "The witness does not establish this exact value proposition";},
        Code.contradictory_proof => {return "The required proof contract contains contradictory facts";},
        Code.proof_analysis_limit => {return "The required proof contract exceeds the analysis limit";},
        Code.skolem_escape => {return "A rigid type escapes its quantified scope";},
        Code.rank_mismatch => {return "The value does not satisfy the quantified annotation";},
        Code.use_after_move => {return "This owning binding version was already moved";},
        Code.duplicate_owner => {return "An affine owner cannot be copied";},
        Code.borrow_conflict => {return "This owner has a conflicting live loan";},
        Code.borrow_escape => {return "This loan outlives its owner scope";},
        Code.once_reused => {return "This once callable may already have been invoked or moved";},
        Code.multiplicity_unknown => {return "This callable has no checked affine invocation contract";},
        Code.cleanup_not_safe => {return "Cleanup needs a finite non-suspending adapter contract";},
        Code.usage_evidence_mismatch => {return "Usage evidence does not match the checked value";},
        Code.usage_analysis_limit => {return "Usage analysis exceeds its bounded state budget";},
        Code.package_expected => {return "An explicit existential package type is required";},
        Code.package_witness_mismatch => {return "Package witnesses and opened binders must match the existential declaration";},
        Code.package_escape => {return "An opened package identity escapes its lexical scope";},
        Code.abstract_representation_access => {return "Reflection cannot inspect an abstract type witness";},
        Code.code_shape_mismatch => {return "The value does not have the required typed code or descriptor shape";},
        Code.stage_unavailable => {return "The value is unavailable at this stage; use explicit lift or splice";},
        Code.cross_stage_authority => {return "The value carries authority that cannot cross a stage boundary";},
        Code.descriptor_private => {return "The descriptor cannot expose this abstract or private shape";},
        Code.generated_binding_escape => {return "A generated binding escapes its checked scope";},
        Code.staging_budget => {return "Typed staging exceeds the analysis budget";},
        Code.unbound_alias_row => {return "A data or effect declaration must carry an open alias row in an explicit type parameter";},
        Code.undetermined_implementation => {return "The implementation head does not determine every declared parameter";},
        Code.orphan_implementation => {return "The implementation producer owns neither the contract nor its anchor nominal";},
        Code.overlapping_implementation => {return "Visible implementation heads have a common instantiation";},
        Code.incompatible_implementation => {return "The matching implementation cannot satisfy its prerequisites";},
        Code.recursive_evidence => {return "Implementation prerequisites repeat an active application";},
        Code.missing_type_member => {return "The contract has no associated type member with this name";},
        Code.associated_arity => {return "An associated projection requires the contract's complete argument shapes";},
        Code.recursive_associated_type => {return "Associated type equations cannot recurse";},
        Code.associated_limit => {return "Associated type normalization exceeded its work or depth limit";},
        Code.missing_implementation => {return "This contract application requires an explicit implementation";},
        Code.recursive_contract => {return "Contracts cannot include themselves recursively";},
        Code.contract_arity => {return "A contract requires its declared type argument shapes";},
        Code.recursive_type_alias => {return "Type aliases cannot refer to themselves recursively";},
        Code.typed_hole => {return "Unfilled expression; expected";},
        Code.effect_identity_scope => {return "A scoped effect requires a direct callback with one family annotation";},
        Code.capability_escape => {return "A scoped capability or unknown authority footprint cannot cross its owner boundary";},
        Code.capability_analysis_limit => {return "Scoped capability analysis exceeded its bound";},
        Code.effect_member => {return "effect family requires an operation member";},
        Code.integer_range => {return "integer literal exceeds U32 (4294967295)";},
        Code.float_range => {return "floating-point literal exceeds finite F32 range";},
        Code.float_literal => {return "invalid F32 literal";},
        Code.duplicate_type_parameter => {return "Duplicate type parameter";},
        Code.duplicate_type_field => {if self.symbol != 0 {return "duplicate type argument field";}return "Duplicate type argument field";},
        Code.type_parameter => {return "A type parameter pattern binds lowercase names";},
        Code.type_argument => {return "A type argument must match its parameter pattern";},
        Code.intrinsic_arity => {return "Invalid request intrinsic arity";},
        Code.requests_scope => {return "@requests is only available as a request loop input";},
        Code.yield_scope => {return "yield requires an operation clause in a request loop";},
        Code.request_loop_scope => {return "A request loop requires an enclosing do block";},
        Code.request_loop_body => {return "A request loop requires one effect/complete case";},
        Code.request_loop_range => {return "A request loop cannot have a range endpoint";},
        Code.request_binding => {return "The request case must match the loop binding";},
        Code.request_completion => {return "A request loop requires exactly one complete clause";},
        Code.request_clause_fallthrough => {return "An operation clause must reply or exit on each path";},
        Code.request_completion_fallthrough => {return "A completion clause must return or break";},
        Code.duplicate_request_handler => {return "An operation can have only one request clause";},
        Code.request_case_scope => {return "Request cases require a request loop";},
        Code.record_constructor => {return "named fields require a declared record constructor";},
        Code.missing_record_field => {return "missing record field";},
        Code.unknown_modifier => {return "only `entry` may precede `const` or `let`";},
        Code.guard_fallthrough => {return "let-else fallback must exit its enclosing do block";},
        Code.product_arity => {return "cannot unify products with different element counts";},
        Code.unknown_value => {if self.implicit_type_witness {return "unknown value: Type";}return "unknown value";},
        Code.unknown_operator => {return "operator has no source fixity declaration";},
        Code.operator_associativity => {return "operators at equal precedence need compatible associativity or explicit parentheses";},
        Code.operator_header_order => {return "operator declarations must precede values and data declarations";},
        Code.operator_precedence => {return "operator precedence must be between 0 and 255";},
        Code.duplicate_operator => {return "duplicate operator fixity declaration";},
        Code.unsupported_prefix => {return "only F32 prefix negation (-) is supported";},
        Code.unknown_intrinsic => {return "unknown compiler intrinsic";},
        Code.product_index_literal => {return "product projection requires a literal zero-based index";},
        Code.syntax => {return "Invalid syntax prevents semantic checking";},
        Code.duplicate_name => {return "duplicate value or constructor declaration";},
        Code.unknown_name => {return "Unknown value name";},
        Code.type_mismatch => {return "Types do not match";},
        Code.infinite_type => {return "A type contains itself";},
        Code.effect_mismatch => {return "Effect rows do not match";},
        Code.infinite_effect => {return "An effect row contains itself";},
        Code.const_effect => {return "A constant initializer must be pure";},
        Code.initializer_effect => {return "A runtime initializer must be pure";},
        Code.let_effect => {return "A let or rebinding initializer must be pure";},
        Code.sealed_effect => {return "Foreign is a compiler effect label, not a callable or providable operation";},
        Code.effect_arity => {return "An effect operation has the wrong number of type arguments";},
        Code.effect_family => {return "Read and write operations must belong to the same declared effect family";},
        Code.unknown_effect => {return "Effect rows require Foreign or a declared effect operation or family";},
        Code.invalid_effect_annotation => {return "A latent effect row annotates a function arrow";},
        Code.invalid_constraint => {return "A where predicate has the wrong kind or argument shape";},
        Code.higher_rank_constraint => {return "Parameter annotations cannot contain where clauses";},
        Code.missing_predicate => {return "inferred requirement is absent from the explicit where clause";},
        Code.ambiguous_qualified => {return "Qualified evidence still has unconstrained type or effect variables";},
        Code.annotation_kind_mismatch => {return "One annotation name cannot be both a type and an effect-row variable";},
        Code.unsupported_polymorphic_effect_label => {return "Open rows currently require concrete effect operation labels";},
        Code.operation_signature => {return "An operation declaration specifies a unary parameter and result without an outer effect row";},
        Code.type_arity => {return "A type application has the wrong number of arguments";},
        Code.operation_target => {return "Expected the name of a declared effect operation";},
        Code.invalid_state_provider => {return "State read and write must be distinct operations";},
        Code.module_loader_required => {return "compile a source project to resolve file imports";},
        Code.unsupported => {return "This semantic form is not implemented in the native compiler";},
        Code.unsupported_attribute => {return "Tags are allowed only on const and let declarations";},
        Code.function_target => {return "Effect reflection requires a statically named top-level function";},
        Code.open_effect_descriptor => {return "Effect reflection requires a closed checked effect row";},
        Code.recursive_tag => {return "A tagged declaration cannot refer to its own bound name";},
        Code.unsupported_expression => {return "This expression is not implemented in the executable core";},
        Code.unsupported_type => {return "This annotation type is not implemented in the native compiler";},
        Code.ambiguous_operator => {return "Numeric operation has no admitted U32 or F32 evidence";},
        Code.ambiguous_associated => {return "The expected result type does not identify an associated implementation";},
        Code.missing_associated => {return "No compatible associated implementation exists";},
        Code.ambiguous_member => {return "A field and associated function share this name";},
        Code.missing_member => {return "This receiver has no associated member with this name";},
        Code.type_constructor_required => {return "Monad requires a nominal type constructor value";},
        Code.invalid_provider => {return "Do requires an effect provider or monad resolver";},
        Code.resolver_required => {return "Break $ requires a monad resolver";},
        Code.literal_required => {return "This compiler primitive requires a literal string argument";},
        Code.call_arity => {return "This compiler primitive requires its exact literal and operand arguments";},
        Code.break_scope => {return "Break requires an enclosing loop in this function";},
        Code.continue_scope => {return "Continue requires an enclosing loop in this function";},
        Code.function_return_required => {return "Every path through a function do block must return explicitly";},
        Code.invalid_return => {return "Control cannot cross an enclosing computation boundary";},
        Code.unreachable_statement => {if self.source_terminator!=blot_parse_source_operators::terminator_none {return "statement after return in the same suite";}return "A statement follows an unconditional return or break";},
        Code.invalid_operator => {return "This operator is not declared or supported";},
        Code.return_outside_block => {return "Break with a value requires an enclosing do block in this function";},
        Code.return_outside_function => {return "Return requires an enclosing function; use break with a value to finish a do block";},
        Code.return_across_continuation => {return "Return cannot cross a monadic continuation or a nested request callback; finish that do block with break value instead";},
        Code.unknown_rebinding => {if self.symbol != 0 {return ":= requires an existing local binding";}return "Rebinding requires an existing lexical name";},
        Code.dead_rebinding => {return "This := inside a nested do: block is never read and leaves the enclosing binding unchanged; rebind it with if/else or a statement case, or assign a case expression";},
        Code.case_arm_return => {return "This break would leave only its case arm and skip the rebinding the arm carries out; break directly in the arm's do: block or restructure with if/else";},
        Code.nesting_limit => {return "Semantic nesting exceeds the compiler limit";},
        Code.inference_budget => {return "Type inference exceeded this module's work budget";},
        Code.constructor_marker => {return "Record constructors require # before the name";},
        Code.private_access => {return "Private declaration or opaque representation is unavailable here";},
        Code.private_identity_escape => {return "Public signature exposes a private declaration";},
        Code.unknown_constructor => {if self.symbol != 0 {return "unknown record constructor";}return "Unknown data constructor";},
        Code.unknown_field => {return "This value has no such named field";},
        Code.duplicate_field => {return "A field was supplied more than once";},
        Code.missing_field => {return "A required record field is missing";},
        Code.non_exhaustive_match => {return "Case patterns do not cover every possible value";},
        Code.refutable_pattern => {return "A refutable let pattern requires an exiting else branch";},
        Code.constructor_arity => {return "Constructor payload does not match its declared arity";},
        Code.unknown_product_shape => {return "projection requires a known product arity; annotate the parameter with a product type";},
        Code.product_index => {return "product projection index is outside its fixed arity";},
        Code.pattern_arity => {return "Pattern shape does not match the scrutinee shape";},
        Code.alternative_bindings => {return "alternative patterns must bind the same names";},
        Code.duplicate_pattern_binding => {return "a pattern cannot bind the same name more than once";},
        Code.duplicate_record_field => {return "record field is supplied more than once";},
        Code.unknown_record_field => {return "record has no field named";},
        Code.pattern_bindings => {return "Pattern alternatives must bind the same names";},
        Code.value_pattern_type => {return "Value patterns require U32 or Bool";},
        Code.non_exiting_fallback => {return "A refutable let failure branch must exit";},
    }
}
fn sourceDeclaration(binding:Binding)->SourceDeclaration {return SourceDeclaration{binding.capability_flow,binding.capability_parameters,binding.private,binding.name,binding.declaration,binding.kind,binding.named_function,binding.external};}
fn declarationCatalog(producer)->DeclarationCatalog {return DeclarationCatalog {types:blot_check_frozen_types::Source.store{producer.types},parameter_patterns:blot_check_frozen_types::Patterns.store{producer.parameter_patterns},nominals:producer.nominals,constructors:producer.constructors,effect_families:producer.effect_families,effect_templates:producer.effect_templates,associated:producer.associated,unit:producer.unit,contracts:producer.contracts,contract_predicates:producer.contract_predicates,contract_members:producer.contract_members,implementations:producer.implementations,implementation_predicates:producer.implementation_predicates,implementation_members:producer.implementation_members};}
fn ImportedCatalog::catalog(self:ImportedCatalog)->DeclarationCatalog {
    let owner .= self.frozen;if owner {return DeclarationCatalog {types:blot_check_frozen_types::Source.frozen{owner.graph},parameter_patterns:blot_check_frozen_types::Patterns.frozen{owner.patterns},nominals:owner.nominals,constructors:owner.constructors,effect_families:owner.effect_families,effect_templates:owner.effect_templates,associated:owner.associated,unit:owner.unit,contracts:owner.contracts,contract_predicates:owner.contract_predicates,contract_members:owner.contract_members,implementations:owner.implementations,implementation_predicates:owner.implementation_predicates,implementation_members:owner.implementation_members};}
    return declarationCatalog(self.producer);
}
fn ImportedCatalog::bindingCount(self:ImportedCatalog)->i64 {let owner .= self.frozen;if owner {return owner.bindings.len;}return self.producer.bindings.len;}
fn ImportedCatalog::declaration(self:ImportedCatalog,id:u32)->SourceDeclaration {let owner .= self.frozen;if owner {let value=owner.bindings[id];return SourceDeclaration {capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,private:value.private,name:value.name,declaration:0,kind:value.kind,named_function:value.named_function,external:value.external};}return sourceDeclaration(self.producer.bindings[id]);}
fn ImportedCatalog::interface(self:ImportedCatalog,id:u32)->SchemeInterface {let owner .= self.frozen;if owner {let value=owner.bindings[id];return SchemeInterface{producer_binding:id,proof_contract:blot_check_numeric_proof_headers::find(owner.proof_contracts,id),types:blot_check_frozen_types::Source.frozen{owner.graph},scheme:value.scheme,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,named_function:value.named_function,obligations:owner.obligations,callees:Callees.frozen{owner}};}
    let producer .= self.producer;let value=producer.bindings[id];var summary=blot_support::none<SchemeSummary>();if value.summary.shareable {summary=blot_support::some(value.summary);}return SchemeInterface{producer_binding:id,proof_contract:checkedProofContract(producer,id),types:blot_check_frozen_types::Source.store{producer.types},scheme:value.scheme,summary:summary,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,named_function:value.named_function,obligations:producer.obligations,callees:Callees.live{producer}};
}
fn Callees::capabilityContract(self:Callees,binding:u32,arity:u32)->blot_support::Option<blot_check_capability_contracts::Recipe> {match self {Callees.none=>{return blot_support::none<blot_check_capability_contracts::Recipe>();},Callees.live owner=>{return owner.value.capability_contracts.header(binding,arity);},Callees.frozen owner=>{return owner.value.capability_contracts.header(binding,arity);},}}
fn Callees::interface(self:Callees,binding:u32)->blot_support::Option<SchemeInterface> {match self {
    Callees.none=>{return blot_support::none<SchemeInterface>();},
    Callees.live selected=>{let owner .= selected.value;if binding==0 || binding>=owner.bindings.len {return blot_support::none<SchemeInterface>();}let value=owner.bindings[binding];var summary=blot_support::none<SchemeSummary>();if value.summary.shareable {summary=blot_support::some(value.summary);}return blot_support::some(SchemeInterface{producer_binding:binding,proof_contract:checkedProofContract(owner,binding),types:blot_check_frozen_types::Source.store{owner.types},scheme:value.scheme,summary:summary,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,named_function:value.named_function,obligations:owner.obligations,callees:self});},
    Callees.frozen selected=>{let owner .= selected.value;if binding==0 || binding>=owner.bindings.len {return blot_support::none<SchemeInterface>();}let value=owner.bindings[binding];return blot_support::some(SchemeInterface{producer_binding:binding,proof_contract:blot_check_numeric_proof_headers::find(owner.proof_contracts,binding),types:blot_check_frozen_types::Source.frozen{owner.graph},scheme:value.scheme,capability_flow:value.capability_flow,capability_parameters:value.capability_parameters,named_function:value.named_function,obligations:owner.obligations,callees:self});},
}}
fn checkedProofContract(owner:const Checked&,binding:u32)->const blot_check_numeric_proof_headers::Owned? {for &value in owner.proof_contracts {if value.binding==binding {return value.header;}}return null;}
fn tagOrigin(origins:const TagOrigin[:],span:blot_parse_ast::Span)->u32 {var low:i64=0;var high=origins.len;while low<high {let middle=low+(high-low)/2;if origins[middle].span.start<=span.start {low=middle+1;}else {high=middle;}}if low==0 {return 0;}let candidate=origins[low-1];if span.end<=candidate.span.end {return candidate.attribute;}return 0;}
fn Checked::reflection(self:const Checked&,id:u32)->blot_support::Option<Reflection> {var low:i64=0;var high=self.reflections.len;while low<high {let middle=low+(high-low)/2;if self.reflections[middle].node<id {low=middle+1;}else {high=middle;}}if low<self.reflections.len && self.reflections[low].node==id {return blot_support::some(self.reflections[low]);}return blot_support::none<Reflection>();}
fn Checked::diagnosticSpan(self:const Checked&,tree:const blot_parse_ast::Tree&,source:u32)->blot_parse_ast::Span {let span=tree.span(source);let origin=tagOrigin(self.tag_origins,span);if origin==0 {return span;}return tree.span(origin);}
fn Counters::add(self:Counters&,other:Counters) {self.obligations_appended+=other.obligations_appended;self.pending_peak=max(self.pending_peak,other.pending_peak);self.instantiations+=other.instantiations;self.shared_uses+=other.shared_uses;self.use_expansions+=other.use_expansions;self.memo_hits+=other.memo_hits;self.memo_misses+=other.memo_misses;self.memo_declined+=other.memo_declined;self.inference_steps+=other.inference_steps;self.associated_steps+=other.associated_steps;self.projection_memo_hits+=other.projection_memo_hits;}
fn prepareQualifiedName(pool:blot_parse_symbols::Pool&,namespace:u32,owner:u32,member:u32)->blot_error::Error {if owner==0 || member==0 {return blot_error::Error.none;}var text:u8[>..<];if namespace!=0 {text.append(pool.get(namespace));text.append('.' as u8);}text.append(pool.get(owner));text.append('.' as u8);text.append(pool.get(member));let symbol,err=pool.intern(text);return err;}
fn prepareGeneratedNames(pool:blot_parse_symbols::Pool&,tree:const blot_parse_ast::Tree&,catalogs:const ImportedCatalog[:])->blot_error::Error {let result,err=pool.intern("result");if err!=blot_error::Error.none {return err;}let effects,err=pool.intern("effects");if err!=blot_error::Error.none {return err;}for root in tree.roots {let node=tree.node(root);if node.tag==blot_parse_ast::tag_implementation_decl {let declaration=tree.implementation(root);for member in tree.list(declaration.members) {let err=prepareQualifiedName(pool,0,declaration.name,tree.node(member).a);if err!=blot_error::Error.none {return err;}}}else if node.tag==blot_parse_ast::tag_contract_decl {for member in tree.children(node.b) {let err=prepareQualifiedName(pool,0,node.a,tree.node(member).a);if err!=blot_error::Error.none {return err;}}}}
    for imported in catalogs {if imported.kind!=ImportedCatalog_kind.contract {continue;}let producer=imported.catalog();let contract=producer.contracts[imported.index];for member in producer.contract_members[contract.members.start..contract.members.start+contract.members.len] {if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {let err=prepareQualifiedName(pool,imported.namespace,imported.name,member.name);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;
}
fn Engine::collectModuleHeaders(self:Engine&,imports:const ImportedBinding[:],headers:const SourceHeader[:],catalogs:const ImportedCatalog[:],source_catalogs:const SourceCatalog[:],allow_imports:bool,inherited_fixities:const ImportedFixity[:])->blot_error::Error {
    let tree .= self.tree;let pool .= self.pool;let unit=self.unit;let err=self.dataHeaders();if err!=blot_error::Error.none {return err;}let err=self.contractHeaders();if err!=blot_error::Error.none {return err;}var local_fixities:dictionary<u32,bool>;
    for fixity in inherited_fixities {self.catalogs.overrides.insert(fixity.operator,OperatorOverride{fixity.target,fixity.named,fixity.external});}
    for id in tree.roots {let tag=tree.node(id).tag;if tag==blot_parse_ast::tag_data_decl || tag==blot_parse_ast::tag_type_alias_decl || tag==blot_parse_ast::tag_contract_decl || tag==blot_parse_ast::tag_implementation_decl || tag==blot_parse_ast::tag_effect_decl || tag==blot_parse_ast::tag_effect_type_decl {continue;}if allow_imports && (tag==blot_parse_ast::tag_import_decl || tag==blot_parse_ast::tag_export_decl) {continue;}
        if tag==blot_parse_ast::tag_fixity_decl {let fixity=tree.fixity(id);if fixity.attributes.len!=0 {let err=self.diagnostic(Code.unsupported_attribute,id);if err!=blot_error::Error.none {return err;}}if local_fixities.contains(fixity.operator) {let err=self.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}}else {local_fixities.insert(fixity.operator,true);self.catalogs.overrides.insert(fixity.operator,OperatorOverride{target:fixity.target,named:fixity.named});}continue;}
        if tag!=blot_parse_ast::tag_value_decl {let err=self.diagnostic(Code.unsupported,id);if err!=blot_error::Error.none {return err;}continue;}let declaration=tree.value_decl(id);if self.hasGlobal(declaration.name) {let err=self.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}continue;}
        var flow=CapabilityFlow.unknown;let named=tree.node(declaration.body).tag==blot_parse_ast::tag_lambda && declaration.attributes.len==0;if named {flow=blot_check_capability_flow::source(tree,declaration.body);}let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return err;}let binding,err=self.addBinding(Binding{private:tree.declaration_traits(id).private,name:declaration.name,declaration:id,owner:id,kind:Kind.global,capability_flow:flow,named_function:named,ty:fresh});if err!=blot_error::Error.none {return err;}self.catalogs.globals.insert(declaration.name,binding);self.global_states.insert(binding,Global{});self.resolved[id]=binding;
    }
    for imported in catalogs {let err=self.importCatalog(imported);if err!=blot_error::Error.none {return err;}}for imported in source_catalogs {let err=self.importCatalog(imported);if err!=blot_error::Error.none {return err;}}
    for imported in imports {var err=blot_error::Error.none;if self.source_validation {err=self.importHeader(SourceHeader{name:imported.name,namespace:imported.namespace,member:imported.member,target:imported.target,capability_flow:imported.interface.capability_flow,capability_parameters:imported.interface.capability_parameters,named_function:imported.interface.named_function,origin:imported.origin,expose:imported.expose});}else {err=self.importBinding(imported);}if err!=blot_error::Error.none {return err;}}
    for imported in headers {let err=self.importHeader(imported);if err!=blot_error::Error.none {return err;}}let err=self.effectHeaders();if err!=blot_error::Error.none {return err;}
    for &binding in self.bindings {if binding.kind==Kind.global && binding.named_function {let declaration=tree.value_decl(binding.declaration);binding.capability_flow=self.capabilityFlowContract(declaration.body,declaration.annotation);let parameters=self.capabilityParameters(declaration.body,declaration.annotation);if binding.capability_flow==CapabilityFlow.unknown || parameters.kind==blot_check_capability_flow::ParameterResult.product {binding.capability_parameters=parameters;}if binding.capability_parameters.inputInvokes() {self.has_input_invocations=true;}}}
    for binding in self.bindings {if binding.capability_flow==CapabilityFlow.scope_task {self.has_tasks=true;}}
    for binding,index in self.bindings {if binding.kind!=Kind.global || !binding.named_function || !binding.capability_parameters.present() {continue;}let root,err=blot_check_capability_contract_source::derive(self.capability_store,tree,pool,tree.value_decl(binding.declaration).body,binding.capability_parameters);if err!=blot_error::Error.none {if err==blot_error::Error.out_of_memory {return err;}continue;}if root.present {self.capability_roots.append(blot_check_capability_contracts::Binding{index as u32,root.value});}}
    let err=self.dataBodies();if err!=blot_error::Error.none {return err;}self.prepareOpaqueStorage();for index in 0..self.contracts.len {let err=self.resolveContract(index as u32);if err!=blot_error::Error.none {return err;}}
    for member,index in self.contract_members {if member.contract.unit!=unit || member.root==0 {continue;}let source .= self.member_sources.get(index as u32);assert(source!=null);let normalized,err=self.normalizeAssociated(member.root,source,false);if err!=blot_error::Error.none {return err;}let err=self.validateMemberRequirements(index as u32);if err!=blot_error::Error.none {return err;}if member.kind==blot_reuse_principal_interface::ContractMemberKind.value {if self.types.node(self.types.head(normalized,0)).tag!=blot_check_types::Tag.function {let err=self.diagnostic(Code.annotation_kind_mismatch,source);if err!=blot_error::Error.none {return err;}}else {self.contract_members[index].root=normalized;}}}
    for id in tree.roots {if tree.node(id).tag!=blot_parse_ast::tag_value_decl {continue;}let text=pool.get(tree.value_decl(id).name);var dot=blot_support::none<i64>();for character,index in text {if character=='.' as u8 {dot=blot_support::some(index);}}if !dot.present {continue;}let path=self.textCatalogKey(text[..dot.value]);if !path.present {continue;}let contract_index .= self.catalogs.contract_names.get(path.value);if !contract_index {continue;}let member_name,present=pool.lookup(text[dot.value+1..]);if !present {continue;}if self.memberIndex(self.contracts[contract_index],member_name).present {let err=self.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}}}
    let err=self.implementationHeaders();if err!=blot_error::Error.none {return err;}let err=self.implementationCoherence();if err!=blot_error::Error.none {return err;}let err=self.implementationBodies();if err!=blot_error::Error.none {return err;}let err=self.memberTemplates();if err!=blot_error::Error.none {return err;}let err=self.indexAssociated();if err!=blot_error::Error.none {return err;}
    for fixity in inherited_fixities {if local_fixities.contains(fixity.operator) {continue;}var present=false;if fixity.external.present {present=self.catalogs.external_targets.contains(fixity.external.value) || self.imported_values.contains(fixity.external.value);}else {present=self.hasCatalogBinding(fixity.target);}if !present {let err=self.diagnostic(Code.unknown_name,fixity.origin);if err!=blot_error::Error.none {return err;}}}
    for id in tree.roots {if tree.node(id).tag==blot_parse_ast::tag_value_decl {let key=self.qualifiedKey(tree.value_decl(id).name);if key.present && self.hasQualified(key.value) {let err=self.diagnostic(Code.duplicate_name,id);if err!=blot_error::Error.none {return err;}}}}return blot_error::Error.none;
}
fn sourceIssueCode(value:u32)->Code {match value {
    blot_parse_source_operators::c_effect_member=>{return Code.effect_member;},blot_parse_source_operators::c_constructor_marker=>{return Code.constructor_marker;},blot_parse_source_operators::c_integer_range=>{return Code.integer_range;},blot_parse_source_operators::c_float_range=>{return Code.float_range;},blot_parse_source_operators::c_float_literal=>{return Code.float_literal;},
    blot_parse_source_operators::c_duplicate_name=>{return Code.duplicate_name;},blot_parse_source_operators::c_alternative_bindings=>{return Code.alternative_bindings;},blot_parse_source_operators::c_duplicate_pattern_binding=>{return Code.duplicate_pattern_binding;},blot_parse_source_operators::c_duplicate_record_field=>{return Code.duplicate_record_field;},blot_parse_source_operators::c_unknown_record_field=>{return Code.unknown_record_field;},blot_parse_source_operators::c_record_constructor=>{return Code.record_constructor;},blot_parse_source_operators::c_missing_record_field=>{return Code.missing_record_field;},blot_parse_source_operators::c_unknown_modifier=>{return Code.unknown_modifier;},blot_parse_source_operators::c_unknown_operator=>{return Code.unknown_operator;},blot_parse_source_operators::c_unknown_value=>{return Code.unknown_value;},blot_parse_source_operators::c_unknown_rebinding=>{return Code.unknown_rebinding;},blot_parse_source_operators::c_unreachable_statement=>{return Code.unreachable_statement;},
    blot_parse_source_operators::c_operator_associativity=>{return Code.operator_associativity;},blot_parse_source_operators::c_operator_header_order=>{return Code.operator_header_order;},blot_parse_source_operators::c_operator_precedence=>{return Code.operator_precedence;},blot_parse_source_operators::c_duplicate_operator=>{return Code.duplicate_operator;},blot_parse_source_operators::c_unsupported_prefix=>{return Code.unsupported_prefix;},blot_parse_source_operators::c_unknown_intrinsic=>{return Code.unknown_intrinsic;},blot_parse_source_operators::c_unsupported_expression=>{return Code.unsupported_expression;},blot_parse_source_operators::c_private_access=>{return Code.private_access;},blot_parse_source_operators::c_unknown_constructor=>{return Code.unknown_constructor;},blot_parse_source_operators::c_sealed_effect=>{return Code.sealed_effect;},blot_parse_source_operators::c_call_arity=>{return Code.call_arity;},blot_parse_source_operators::c_requests_scope=>{return Code.requests_scope;},blot_parse_source_operators::c_yield_scope=>{return Code.yield_scope;},blot_parse_source_operators::c_break_scope=>{return Code.break_scope;},blot_parse_source_operators::c_continue_scope=>{return Code.continue_scope;},blot_parse_source_operators::c_literal_required=>{return Code.literal_required;},blot_parse_source_operators::c_product_index_literal=>{return Code.product_index_literal;},blot_parse_source_operators::c_nesting_limit=>{return Code.nesting_limit;},
    _=>{return Code.unsupported;},
}}
fn Engine::validateModuleBodies(self:Engine&)->blot_error::Error {
    let tree .= self.tree;let pool .= self.pool;let unit=self.unit;if self.source_validation {let start=self.header_diagnostics.len;self.header_diagnostics.append(self.diagnostics);self.source_header_diagnostics=self.header_diagnostics[start..];self.diagnostics.clear();}
    var source_issue=blot_parse_source_operators::Issue{};var has_issue=false;
    if tree.diagnostics.len==0 {let issue,present,err=blot_parse_source_operators::validate(tree,pool,self);if err!=blot_error::Error.none {return err;}source_issue=issue;has_issue=present;}
    if has_issue {deinitDiagnosticPayloads(self.diagnostics);self.diagnostics.clear();var numeric=blot_support::none<blot_parse_ast::NumericFault>();if source_issue.has_numeric_literal {numeric=blot_support::some(source_issue.numeric_literal);}self.diagnostics.append(Diagnostic{code:sourceIssueCode(source_issue.code),node:source_issue.node,span:blot_parse_ast::Span{source_issue.point,source_issue.point},symbol:source_issue.symbol,implicit_type_witness:source_issue.implicit_type_witness,source_terminator:source_issue.terminator,numeric_literal:numeric});}
    if tree.diagnostics.len==0 && !has_issue && !self.source_annotation_failed {for id in tree.roots {if tree.node(id).tag!=blot_parse_ast::tag_fixity_decl {continue;}let binding,err=self.catalogBinding(tree.fixity(id).target);if err!=blot_error::Error.none {return err;}if binding.present {self.resolved[id]=binding.value;}else {let err=self.diagnostic(Code.unknown_name,id);if err!=blot_error::Error.none {return err;}}}}
    if !self.source_validation && tree.diagnostics.len==0 && !has_issue {
        for id in tree.roots {if tree.node(id).tag==blot_parse_ast::tag_value_decl && self.resolved[id]!=0 {self.root_global=self.resolved[id];let err=self.inferGlobal(self.resolved[id]);if err!=blot_error::Error.none {return err;}}}
        for declaration in self.implementations {if declaration.identity.unit!=unit {continue;}for member in self.implementation_members[declaration.members.start..declaration.members.start+declaration.members.len] {if member.kind!=blot_reuse_principal_interface::ImplementationMemberKind.value {continue;}self.root_global=member.target.binding;let err=self.inferGlobal(member.target.binding);if err!=blot_error::Error.none {return err;}}}self.root_global=0;
        for id in tree.roots {if tree.node(id).tag!=blot_parse_ast::tag_value_decl || !tree.value_decl(id).exported || self.resolved[id]==0 {continue;}let principal=self.bindings[self.resolved[id]].scheme;for constraint in self.obligations[principal.obligations.start..principal.obligations.start+principal.obligations.len] {if constraint.kind!=blot_check_types::ObligationKind.resolver_dispatch {continue;}let resolved,err=self.types.resolve(constraint.ty,0);if err!=blot_error::Error.none {return err;}let owner=self.types.node(resolved);if owner.tag!=blot_check_types::Tag.resolver {continue;}let resolved,err=self.types.resolve(owner.a,0);if err!=blot_error::Error.none {return err;}let token=self.types.node(resolved);if token.tag!=blot_check_types::Tag.type_constructor {continue;}if !self.catalogs.associated_members.contains(AssociatedMember{Identity{token.a,token.b},constraint.name}) {let err=self.diagnostic(Code.missing_member,constraint.source);if err!=blot_error::Error.none {return err;}}}}
        let err=self.finish();if err!=blot_error::Error.none {return err;}let err=self.finishSelectedUses();if err!=blot_error::Error.none {return err;}let err=self.finishReflection();if err!=blot_error::Error.none {return err;}let err=self.finishHoles();if err!=blot_error::Error.none {return err;}
        var scoped_types=false;for node in self.types.nodes {if node.tag==blot_check_types::Tag.scoped {scoped_types=true;break;}}
        if scoped_types && self.diagnostics.len==0 {for index in 0..self.bindings.len {let binding=self.bindings[index];if binding.kind!=Kind.global || !binding.named_function || binding.capability_flow!=CapabilityFlow.unknown || binding.declaration==0 || (binding.capability_parameters.present() && binding.capability_parameters.kind!=blot_check_capability_flow::ParameterResult.product) {continue;}if tree.node(binding.declaration).tag!=blot_parse_ast::tag_value_decl {continue;}let declaration=tree.value_decl(binding.declaration);let arity=blot_check_capability_flow::parameterArity(tree,declaration.body,declaration.annotation);if arity!=0 {let published,err=self.publishInputFunction(index as u32,arity);if err!=blot_error::Error.none {return err;}}}}
        if self.types.has_usage_types && self.diagnostics.len==0 {let err=blot_check_usage_check::validate(self);if err!=blot_error::Error.none {return err;}}if self.diagnostics.len==0 {let err=self.validateVisibility();if err!=blot_error::Error.none {return err;}}
    }return blot_error::Error.none;
}
fn firstDot(text:const u8[:])->blot_support::Option<i64> {for value,index in text {if value=='.' as u8 {return blot_support::some(index);}}return blot_support::none<i64>();}
fn lastDot(text:const u8[:])->blot_support::Option<i64> {var index=text.len;while index!=0 {index-=1;if text[index]=='.' as u8 {return blot_support::some(index);}}return blot_support::none<i64>();}
fn Engine::qualifiedKey(self:const Engine&,name:u32)->blot_support::Option<Qualified> {let text=self.pool.get(name);let separator=firstDot(text);if !separator.present {return blot_support::none<Qualified>();}let namespace,ns_present=self.pool.lookup(text[..separator.value]);if !ns_present {return blot_support::none<Qualified>();}let member,present=self.pool.lookup(text[separator.value+1..]);if !present {return blot_support::none<Qualified>();}return blot_support::some(Qualified{namespace,member});}
fn Engine::qualifiedBinding(self:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let found .= self.catalogs.qualified_symbols.get(name);if found {return blot_support::some(found.binding),blot_error::Error.none;}let key=self.qualifiedKey(name);if !key.present {return blot_support::none<u32>(),blot_error::Error.none;}let binding,err=self.qualifiedImportBinding(key.value);if err!=blot_error::Error.none || !binding.present {return binding,err;}self.catalogs.qualified_symbols.insert(name,QualifiedResolution{key.value.namespace,binding.value});return binding,blot_error::Error.none;}
fn Engine::globalBinding(self:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let text=self.pool.get(name);let separator=firstDot(text);if separator.present {let root,present=self.pool.lookup(text[..separator.value]);if present && self.lookup(root).present {return blot_support::none<u32>(),blot_error::Error.none;}}return self.catalogBinding(name);}
fn Engine::catalogBinding(self:Engine&,name:u32)->blot_support::Option<u32>,blot_error::Error {let binding .= self.catalogs.globals.get(name);if binding {return blot_support::some(binding),blot_error::Error.none;}let target .= self.imported_globals.get(name);if target {return self.importedBinding(target);}return self.qualifiedBinding(name);}
fn Engine::sourceDuplicateName(self:const Engine&)->blot_support::Option<u32> {if self.source_validation {for constructor in self.constructors[1..] {if constructor.identity.unit!=self.unit {continue;}let binding .= self.catalogs.globals.get(constructor.name);if binding {let declaration=self.bindings[binding].declaration;if self.tree.span(declaration).start<self.tree.span(constructor.identity.decl).start {return blot_support::some(declaration);}return blot_support::some(constructor.identity.decl);}let target .= self.imported_globals.get(constructor.name);if target {let imported .= self.imported_values.get(target);assert(imported!=null);return blot_support::some(imported.origin);}}}
    var diagnostics:const Diagnostic[:]=self.diagnostics;if self.source_validation {diagnostics=self.source_header_diagnostics;}for issue in diagnostics {if issue.code!=Code.duplicate_name || self.tree.node(issue.node).tag!=blot_parse_ast::tag_value_decl {continue;}let name=self.tree.value_decl(issue.node).name;let binding .= self.catalogs.globals.get(name);if binding {return blot_support::some(self.bindings[binding].declaration);}let target .= self.imported_globals.get(name);if target {let imported .= self.imported_values.get(target);assert(imported!=null);return blot_support::some(imported.origin);}}return blot_support::none<u32>();
}
fn Engine::sourceTypeApplication(self:const Engine&,symbol:u32)->bool {let nominal .= self.catalogs.nominal_names.get(self.catalogKey(symbol));if nominal {return self.nominals[nominal].patterns.len!=0;}let template=self.catalogOperationTemplate(symbol);if template.present {return self.effect_families[self.effect_templates[template.value].family].patterns.len!=0;}return false;}
fn Engine::sourceNonCallableEffect(self:const Engine&,symbol:u32)->bool {let family .= self.catalogs.effect_family_names.get(self.catalogKey(symbol));if family {return !self.effect_families[family].callable;}if self.hasGlobal(symbol) || self.hasQualified(self.catalogKey(symbol)) || self.catalogOperationTemplate(symbol).present {return false;}let text=self.pool.get(symbol);var prefix_end=text.len;
    while true {let separator=lastDot(text[..prefix_end]);if !separator.present {break;}prefix_end=separator.value;let prefix=text[..prefix_end];let dot=firstDot(prefix);var namespace:u32=0;var member:u32=0;if dot.present {let ns,present=self.pool.lookup(prefix[..dot.value]);if !present {continue;}namespace=ns;let value,present=self.pool.lookup(prefix[dot.value+1..]);if !present {continue;}member=value;}else {let value,present=self.pool.lookup(prefix);if !present {continue;}member=value;}let family .= self.catalogs.effect_family_names.get(Qualified{namespace,member});if family {return !self.effect_families[family].callable;}}
    return false;
}
fn Engine::sourceParameterMatches(self:Engine&,param_pattern:u32,argument:u32)->bool,blot_error::Error {let point=self.types.mark();let diagnostic_count=self.diagnostics.len;let type_names=self.type_env.items.len;let row_names=self.row_env.items.len;self.mark_depth+=1;let converted,err=self.parameterArgument(param_pattern,argument,false,0);let result=self.diagnostics.len==diagnostic_count;self.mark_depth-=1;self.types.rollback(point);deinitDiagnosticPayloads(self.diagnostics[diagnostic_count..]);self.diagnostics.resize(diagnostic_count);self.type_env.resize(type_names);self.row_env.resize(row_names);return result,err;}
fn Engine::sourceArgumentIsType(self:Engine&,original:u32,argument:u32)->bool,blot_error::Error {var head=original;var consumed:i64=0;while true {let node=self.tree.node(head);if node.tag==blot_parse_ast::tag_group {head=node.a;}else if node.tag==blot_parse_ast::tag_apply {consumed+=1;head=node.a;}else {break;}}let node=self.tree.node(head);if node.tag!=blot_parse_ast::tag_name {return false,blot_error::Error.none;}let template=self.catalogOperationTemplate(node.a);if !template.present {return false,blot_error::Error.none;}let patterns=self.effect_families[self.effect_templates[template.value].family].patterns;if consumed>=patterns.len {return false,blot_error::Error.none;}let param_pattern=self.parameter_patterns.list(patterns)[consumed];let possible,err=self.possibleParameterArgument(param_pattern,argument,true,0);if err!=blot_error::Error.none || !possible {return possible,err;}return self.sourceParameterMatches(param_pattern,argument);}
fn Engine::sourcePrivateConstructor(self:const Engine&,symbol:u32)->bool {let nominal .= self.catalogs.nominal_names.get(self.catalogKey(symbol));if !nominal {return false;}return self.nominals[nominal].is_opaque && self.nominals[nominal].identity.unit!=self.unit;}
fn Engine::sourceConstructorExists(self:const Engine&,symbol:u32)->bool {return self.catalogs.constructor_names.contains(self.catalogKey(symbol));}
fn Engine::sourceRecordFieldExists(self:const Engine&,symbol:u32,field:u32)->blot_support::Option<bool> {let constructor .= self.catalogs.constructor_names.get(self.catalogKey(symbol));if !constructor {return blot_support::none<bool>();}let definition=self.constructors[constructor];if !definition.declared_record {return blot_support::none<bool>();}if definition.payload==0 {return blot_support::some(false);}let record=self.types.node(definition.payload);if record.tag!=blot_check_types::Tag.record {return blot_support::none<bool>();}for index in 0..record.b {if self.types.recordField(record,index).name==field {return blot_support::some(true);}}return blot_support::some(false);}
fn Engine::sourceRecordTarget(self:Engine&,symbol:u32)->u32,blot_error::Error {let constructor .= self.catalogs.constructor_names.get(self.catalogKey(symbol));if constructor {let definition=self.constructors[constructor];if definition.declared_record || (self.nominals[definition.nominal].is_opaque && self.types.node(definition.payload).tag==blot_check_types::Tag.record) {return blot_parse_source_operators::record_target_record,blot_error::Error.none;}return blot_parse_source_operators::record_target_other,blot_error::Error.none;}let value=self.hasCatalogBinding(symbol) || self.catalogOperationTemplate(symbol).present || self.catalogs.effect_family_names.contains(self.catalogKey(symbol));if value {return blot_parse_source_operators::record_target_other,blot_error::Error.none;}return blot_parse_source_operators::record_target_missing,blot_error::Error.none;}
fn Engine::sourceMissingRecordField(self:const Engine&,symbol:u32,fields:const u32[:])->blot_support::Option<u32> {let constructor .= self.catalogs.constructor_names.get(self.catalogKey(symbol));if !constructor {return blot_support::none<u32>();}let payload=self.constructors[constructor].payload;if payload==0 {return blot_support::none<u32>();}let record=self.types.node(payload);if record.tag!=blot_check_types::Tag.record {return blot_support::none<u32>();}for index in 0..record.b {let field=self.types.recordField(record,index).name;var supplied=false;for id in fields {if self.tree.node(id).a==field {supplied=true;break;}}if !supplied {return blot_support::some(field);}}return blot_support::none<u32>();}
fn Engine::sourceIntrinsicArity(self:const Engine&,symbol:u32)->blot_support::Option<i64> {let text=self.pool.get(symbol);if text=="@requests" || text=="@computation" {return blot_support::some(1 as i64);}return exactIntrinsicArity(text);}
fn Engine::sourceIntrinsicKnown(self:const Engine&,symbol:u32)->bool {let text=self.pool.get(symbol);return intrinsicArity(text).present || text=="@requests" || text=="@computation";}
fn Engine::sourceSymbolicDeclared(self:const Engine&,symbol:u32)->bool {let fixity .= self.catalogs.overrides.get(symbol);if !fixity {return false;}return !fixity.named;}
fn Engine::sourceOperatorTargetExists(self:Engine&,name:u32)->bool,blot_error::Error {if self.hasCatalogBinding(name) {return true,blot_error::Error.none;}let key=self.catalogKey(name);return self.catalogs.constructor_names.contains(key) || self.catalogOperationTemplate(name).present,blot_error::Error.none;}
fn Engine::sourceQualifiedExists(self:const Engine&,namespace:u32,member:u32)->bool {let key=Qualified{namespace,member};return self.hasQualified(key) || self.catalogs.nominal_names.contains(key) || self.catalogs.effect_family_names.contains(key) || self.catalogs.effect_operation_names.contains(key);}
fn Engine::sourceValueExists(self:Engine&,name:u32)->bool,blot_error::Error {let exists,err=self.sourceOperatorTargetExists(name);if err!=blot_error::Error.none || exists {return exists,err;}let key=self.catalogKey(name);if self.catalogs.nominal_names.contains(key) || self.catalogs.effect_family_names.contains(key) {return true,blot_error::Error.none;}let text=self.pool.get(name);let separator=firstDot(text);var root=name;if separator.present {let value,present=self.pool.lookup(text[..separator.value]);if !present {return false,blot_error::Error.none;}root=value;}if root!=name {let suffix=text[self.pool.get(root).len+1..];let dot=firstDot(suffix);var end=suffix.len;if dot.present {end=dot.value;}let member,present=self.pool.lookup(suffix[..end]);if present && self.hasQualified(Qualified{root,member}) {return true,blot_error::Error.none;}}
    if root!=name {let exists,err=self.sourceOperatorTargetExists(root);if err!=blot_error::Error.none || exists {return exists,err;}}return self.catalogs.nominal_names.contains(Qualified{0,root}) || self.catalogs.effect_family_names.contains(Qualified{0,root}),blot_error::Error.none;
}
struct SourceAnnotationScope {types:i64,rows:i64,computations:i64,binding:u32,inherited_types:i64,inherited_rows:i64}
struct SourceImplementationScope {implementation:blot_support::Option<u32>,closed:bool,implicit_rows:bool}
fn Engine::sourceLiteralPoint(self:const Engine&,id:u32)->u32 {let span=self.tree.span(id);let attribute=tagOrigin(self.tag_origins,span);if attribute==0 {return span.start;}return self.tree.span(attribute).start;}
fn Engine::sourceAnnotationsStopped(self:const Engine&)->bool {return self.source_annotation_failed;}
fn Engine::sourceControlValidation(self:const Engine&)->bool {return self.source_validation;}
fn Engine::sourceDeclarationHeader(self:Engine&,id:u32)->blot_error::Error {if !self.source_validation || self.source_annotation_failed {return blot_error::Error.none;}let span=self.tree.span(id);for diagnostic in self.source_header_diagnostics {let node_span=self.tree.span(diagnostic.node);if node_span.start<span.start || node_span.end>span.end {continue;}self.diagnostics.append(diagnostic);self.source_annotation_failed=true;return blot_error::Error.none;}return blot_error::Error.none;}
fn Engine::sourceImplementationStart(self:Engine&,id:u32)->SourceImplementationScope,blot_error::Error {let saved=SourceImplementationScope{self.checking_implementation,self.closed_type_variables,self.implicit_row_parameters};if !self.source_validation {return saved,blot_error::Error.none;}let index .= self.catalogs.implementation_names.get(Qualified{0,self.tree.node(id).a});if !index {return saved,blot_error::Error.none;}let err=self.implementationScope(self.implementations[index]);if err!=blot_error::Error.none {return saved,err;}self.checking_implementation=blot_support::some(index);self.closed_type_variables=true;self.implicit_row_parameters=false;return saved,blot_error::Error.none;}
fn Engine::sourceImplementationEnd(self:Engine&,saved:SourceImplementationScope) {if !self.source_validation {return;}self.type_env.clear();self.row_env.clear();self.checking_implementation=saved.implementation;self.closed_type_variables=saved.closed;self.implicit_row_parameters=saved.implicit_rows;}
fn Engine::sourceBindingStart(self:Engine&,id:u32)->SourceAnnotationScope,blot_error::Error {let saved=SourceAnnotationScope{self.type_env.items.len,self.row_env.items.len,self.computation_annotations.len,self.annotation_binding,self.inherited_types,self.inherited_rows};if !self.source_validation {return saved,blot_error::Error.none;}let before=self.diagnostics.len;self.annotation_binding=0;if self.tree.node(id).tag==blot_parse_ast::tag_let_stmt {self.annotation_binding=id;}self.inherited_types=saved.types;self.inherited_rows=saved.rows;
    if self.tree.node(id).tag==blot_parse_ast::tag_value_decl {let declaration=self.tree.value_decl(id);for source in [declaration.annotation,declaration.where_node,declaration.body] {let err=self.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return saved,err;}}for attribute in self.tree.list(declaration.attributes) {let err=self.collectAnnotationNames(self.tree.node(attribute).a,0);if err!=blot_error::Error.none {return saved,err;}}}
    else {let binding=self.tree.binding(id);for source in [binding.annotation,binding.where_node,binding.value,binding.fallback] {let err=self.collectAnnotationNames(source,0);if err!=blot_error::Error.none {return saved,err;}}}self.source_annotation_failed=self.source_annotation_failed || self.diagnostics.len!=before;return saved,blot_error::Error.none;
}
fn Engine::sourceBindingAnnotation(self:Engine&,id:u32)->blot_error::Error {if !self.source_validation || self.source_annotation_failed {return blot_error::Error.none;}let before=self.diagnostics.len;var annotation:u32=0;if self.tree.node(id).tag==blot_parse_ast::tag_value_decl {annotation=self.tree.value_decl(id).annotation;}else {annotation=self.tree.binding(id).annotation;}if annotation!=0 {let value,err=self.annotation(annotation);if err!=blot_error::Error.none {return err;}}self.source_annotation_failed=self.diagnostics.len!=before;return blot_error::Error.none;}
fn Engine::sourceBindingFinish(self:Engine&,id:u32)->blot_error::Error {if !self.source_validation || self.source_annotation_failed {return blot_error::Error.none;}let before=self.diagnostics.len;var err=blot_error::Error.none;if self.tree.node(id).tag==blot_parse_ast::tag_value_decl {let declaration=self.tree.value_decl(id);err=self.beginQualification(id,declaration.where_node,declaration.annotation,declaration.body);}else {let binding=self.tree.binding(id);err=self.beginQualification(id,binding.where_node,binding.annotation,binding.value);}if err!=blot_error::Error.none {return err;}self.source_annotation_failed=self.diagnostics.len!=before;return blot_error::Error.none;}
fn Engine::sourceBindingEnd(self:Engine&,saved:SourceAnnotationScope) {if !self.source_validation {return;}self.type_env.resize(saved.types);self.row_env.resize(saved.rows);self.computation_annotations.resize(saved.computations);self.annotation_binding=saved.binding;self.inherited_types=saved.inherited_types;self.inherited_rows=saved.inherited_rows;}
fn Engine::sourceExpressionAnnotations(self:Engine&,id:u32)->blot_error::Error {if !self.source_validation || self.source_annotation_failed {return blot_error::Error.none;}let before=self.diagnostics.len;let node=self.tree.node(id);if node.tag==blot_parse_ast::tag_lambda {let parameter=self.tree.parameter(node.a);if parameter.where_node!=0 {let err=self.diagnostic(Code.higher_rank_constraint,parameter.where_node);if err!=blot_error::Error.none {return err;}}if parameter.annotation!=0 {let value,err=self.annotation(parameter.annotation);if err!=blot_error::Error.none {return err;}}if node.c!=0 {let value,err=self.annotation(node.c);if err!=blot_error::Error.none {return err;}}}else if node.tag==blot_parse_ast::tag_use_stmt && node.c!=0 {let value,err=self.annotation(node.c);if err!=blot_error::Error.none {return err;}}self.source_annotation_failed=self.diagnostics.len!=before;return blot_error::Error.none;}
fn Engine::producerCapability(self:const Engine&,target:ExternalTarget)->blot_support::Option<ProducerCapability> {if !self.producer_capabilities.present {return blot_support::none<ProducerCapability>();}return self.producer_capabilities.value.lookup(target);}
fn Engine::importHeader(self:Engine&,imported:SourceHeader)->blot_error::Error {assert(self.source_validation);let key=Qualified{imported.namespace,imported.member};if imported.expose && ((imported.namespace==0 && self.hasGlobal(imported.name)) || (imported.namespace!=0 && self.hasQualified(key))) {return self.diagnostic(Code.duplicate_name,imported.origin);}let existing .= self.catalogs.external_targets.get(imported.target);var binding:u32=0;if existing {binding=existing;}else {var name=imported.name;if imported.namespace!=0 {name=imported.member;}let ty,err=self.types.fresh();if err!=blot_error::Error.none {return err;}let fresh,err=self.addBinding(Binding{name:name,declaration:imported.origin,owner:imported.origin,kind:Kind.external,ty:ty,capability_flow:imported.capability_flow,capability_parameters:imported.capability_parameters,named_function:imported.named_function,external:blot_support::some(imported.target)});if err!=blot_error::Error.none {return err;}self.catalogs.external_targets.insert(imported.target,fresh);binding=fresh;}if !imported.expose {return blot_error::Error.none;}if imported.namespace==0 {self.catalogs.globals.insert(imported.name,binding);}else {self.catalogs.qualified.insert(key,binding);}return blot_error::Error.none;}
fn Engine::hasGlobal(self:const Engine&,name:u32)->bool {return self.catalogs.globals.contains(name) || self.imported_globals.contains(name);}
fn Engine::hasQualified(self:const Engine&,key:Qualified)->bool {return self.catalogs.qualified.contains(key) || self.imported_qualified.contains(key);}
fn Engine::hasCatalogBinding(self:const Engine&,name:u32)->bool {return self.hasGlobal(name) || self.hasQualified(self.catalogKey(name));}
fn Engine::importedBinding(self:Engine&,target:ExternalTarget)->blot_support::Option<u32>,blot_error::Error {let binding .= self.catalogs.external_targets.get(target);if binding {return blot_support::some(binding),blot_error::Error.none;}let imported .= self.imported_values.get(target);if !imported {return blot_support::none<u32>(),blot_error::Error.none;}var name=imported.name;if imported.namespace!=0 {name=imported.member;}return self.importScheme(imported.interface,target,name,imported.origin,0);}
fn Engine::qualifiedImportBinding(self:Engine&,key:Qualified)->blot_support::Option<u32>,blot_error::Error {let binding .= self.catalogs.qualified.get(key);if binding {return blot_support::some(binding),blot_error::Error.none;}let target .= self.imported_qualified.get(key);if !target {return blot_support::none<u32>(),blot_error::Error.none;}return self.importedBinding(target);}
// Explicit parser context adapters retain all source authority hooks.
fn Engine::source_duplicate_name(self:const Engine&)->u32,bool {let value=self.sourceDuplicateName();return value.value,value.present;}
fn Engine::source_operator_target_exists(self:Engine&,name:u32)->bool,blot_error::Error {return self.sourceOperatorTargetExists(name);}
fn Engine::source_value_exists(self:Engine&,name:u32)->bool,blot_error::Error {return self.sourceValueExists(name);}
fn Engine::source_record_target(self:Engine&,name:u32)->u32,blot_error::Error {return self.sourceRecordTarget(name);}
fn Engine::source_argument_is_type(self:Engine&,source:u32,argument:u32)->bool,blot_error::Error {return self.sourceArgumentIsType(source,argument);}
fn Engine::source_declaration_header(self:Engine&,source:u32)->blot_error::Error {return self.sourceDeclarationHeader(source);}
fn Engine::source_request_header(self:Engine&,source:u32)->blot_error::Error {return self.sourceRequestHeader(source);}
fn Engine::source_binding_annotation(self:Engine&,source:u32)->blot_error::Error {return self.sourceBindingAnnotation(source);}
fn Engine::source_binding_finish(self:Engine&,source:u32)->blot_error::Error {return self.sourceBindingFinish(source);}
fn Engine::source_expression_annotations(self:Engine&,source:u32)->blot_error::Error {return self.sourceExpressionAnnotations(source);}
fn Engine::source_binding_start(self:Engine&,source:u32)->SourceAnnotationScope,blot_error::Error {return self.sourceBindingStart(source);}
fn Engine::source_binding_end(self:Engine&,scope:SourceAnnotationScope) {self.sourceBindingEnd(scope);}
fn Engine::source_implementation_start(self:Engine&,source:u32)->SourceImplementationScope,blot_error::Error {return self.sourceImplementationStart(source);}
fn Engine::source_implementation_end(self:Engine&,scope:SourceImplementationScope) {self.sourceImplementationEnd(scope);}
fn Engine::source_annotations_stopped(self:const Engine&)->bool {return self.sourceAnnotationsStopped();}
fn Engine::source_control_validation(self:const Engine&)->bool {return self.sourceControlValidation();}
fn Engine::source_literal_point(self:const Engine&,source:u32)->u32 {return self.sourceLiteralPoint(source);}
fn Engine::source_editor_probe(self:const Engine&,source:u32)->bool {return self.sourceEditorProbe(source);}
fn Engine::source_private_constructor(self:const Engine&,name:u32)->bool {return self.sourcePrivateConstructor(name);}
fn Engine::source_type_application(self:const Engine&,name:u32)->bool {return self.sourceTypeApplication(name);}
fn Engine::source_record_field_exists(self:const Engine&,name:u32,field:u32)->bool,bool {let value=self.sourceRecordFieldExists(name,field);return value.value,value.present;}
fn Engine::source_missing_record_field(self:const Engine&,name:u32,fields:const u32[:])->u32,bool {let value=self.sourceMissingRecordField(name,fields);return value.value,value.present;}
fn Engine::source_symbolic_declared(self:const Engine&,name:u32)->bool {return self.sourceSymbolicDeclared(name);}
fn Engine::source_intrinsic_known(self:const Engine&,name:u32)->bool {return self.sourceIntrinsicKnown(name);}
fn Engine::source_intrinsic_arity(self:const Engine&,name:u32)->i64,bool {let value=self.sourceIntrinsicArity(name);return value.value,value.present;}
fn Engine::source_non_callable_effect(self:const Engine&,name:u32)->bool {return self.sourceNonCallableEffect(name);}
fn Engine::source_qualified_exists(self:const Engine&,namespace:u32,member:u32)->bool {return self.sourceQualifiedExists(namespace,member);}
fn Engine::source_constructor_exists(self:const Engine&,name:u32)->bool {return self.sourceConstructorExists(name);}

fn editorName_kindCode(value:EditorName_kind)->u32 {match value {EditorName_kind.value=>{return 0;},EditorName_kind.function=>{return 1;},EditorName_kind.type_=>{return 2;},EditorName_kind.constructor=>{return 3;},EditorName_kind.field=>{return 4;},EditorName_kind.member=>{return 5;},EditorName_kind.module=>{return 6;},}}
fn editorName_kindFromCode(code:u32)->EditorName_kind,blot_error::Error {match code {0=>{return EditorName_kind.value,blot_error::Error.none;},1=>{return EditorName_kind.function,blot_error::Error.none;},2=>{return EditorName_kind.type_,blot_error::Error.none;},3=>{return EditorName_kind.constructor,blot_error::Error.none;},4=>{return EditorName_kind.field,blot_error::Error.none;},5=>{return EditorName_kind.member,blot_error::Error.none;},6=>{return EditorName_kind.module,blot_error::Error.none;},_=>{return EditorName_kind.value,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::EditorName_kind,right:blot_check_check::EditorName_kind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::EditorName_kind) {blot_structural::hash(sink,blot_check_check::editorName_kindCode(value) as! u8);}
fn globalTrace_kindCode(value:GlobalTrace_kind)->u32 {match value {GlobalTrace_kind.begun=>{return 0;},GlobalTrace_kind.finished=>{return 1;},}}
fn globalTrace_kindFromCode(code:u32)->GlobalTrace_kind,blot_error::Error {match code {0=>{return GlobalTrace_kind.begun,blot_error::Error.none;},1=>{return GlobalTrace_kind.finished,blot_error::Error.none;},_=>{return GlobalTrace_kind.begun,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::GlobalTrace_kind,right:blot_check_check::GlobalTrace_kind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::GlobalTrace_kind) {blot_structural::hash(sink,blot_check_check::globalTrace_kindCode(value) as! u8);}
fn operationUse_callCode(value:OperationUse_call)->u32 {match value {OperationUse_call.value=>{return 0;},OperationUse_call.state_read=>{return 1;},OperationUse_call.state_write=>{return 2;},}}
fn operationUse_callFromCode(code:u32)->OperationUse_call,blot_error::Error {match code {0=>{return OperationUse_call.value,blot_error::Error.none;},1=>{return OperationUse_call.state_read,blot_error::Error.none;},2=>{return OperationUse_call.state_write,blot_error::Error.none;},_=>{return OperationUse_call.value,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::OperationUse_call,right:blot_check_check::OperationUse_call)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::OperationUse_call) {blot_structural::hash(sink,blot_check_check::operationUse_callCode(value) as! u8);}
fn importedCatalog_kindCode(value:ImportedCatalog_kind)->u32 {match value {ImportedCatalog_kind.catalog=>{return 0;},ImportedCatalog_kind.nominal=>{return 1;},ImportedCatalog_kind.constructor=>{return 2;},ImportedCatalog_kind.effect_family=>{return 3;},ImportedCatalog_kind.contract=>{return 4;},ImportedCatalog_kind.implementation=>{return 5;},}}
fn importedCatalog_kindFromCode(code:u32)->ImportedCatalog_kind,blot_error::Error {match code {0=>{return ImportedCatalog_kind.catalog,blot_error::Error.none;},1=>{return ImportedCatalog_kind.nominal,blot_error::Error.none;},2=>{return ImportedCatalog_kind.constructor,blot_error::Error.none;},3=>{return ImportedCatalog_kind.effect_family,blot_error::Error.none;},4=>{return ImportedCatalog_kind.contract,blot_error::Error.none;},5=>{return ImportedCatalog_kind.implementation,blot_error::Error.none;},_=>{return ImportedCatalog_kind.catalog,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::ImportedCatalog_kind,right:blot_check_check::ImportedCatalog_kind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::ImportedCatalog_kind) {blot_structural::hash(sink,blot_check_check::importedCatalog_kindCode(value) as! u8);}
fn resolverKindCode(value:ResolverKind)->u32 {match value {ResolverKind.monad=>{return 0;},ResolverKind.pure=>{return 1;},ResolverKind.bind=>{return 2;},ResolverKind.forward=>{return 3;},ResolverKind.iterate=>{return 4;},}}
fn resolverKindFromCode(code:u32)->ResolverKind,blot_error::Error {match code {0=>{return ResolverKind.monad,blot_error::Error.none;},1=>{return ResolverKind.pure,blot_error::Error.none;},2=>{return ResolverKind.bind,blot_error::Error.none;},3=>{return ResolverKind.forward,blot_error::Error.none;},4=>{return ResolverKind.iterate,blot_error::Error.none;},_=>{return ResolverKind.monad,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::ResolverKind,right:blot_check_check::ResolverKind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::ResolverKind) {blot_structural::hash(sink,blot_check_check::resolverKindCode(value) as! u8);}
fn effectRunnerKindCode(value:EffectRunnerKind)->u32 {match value {EffectRunnerKind.run=>{return 0;},EffectRunnerKind.reader=>{return 1;},EffectRunnerKind.writer=>{return 2;},}}
fn effectRunnerKindFromCode(code:u32)->EffectRunnerKind,blot_error::Error {match code {0=>{return EffectRunnerKind.run,blot_error::Error.none;},1=>{return EffectRunnerKind.reader,blot_error::Error.none;},2=>{return EffectRunnerKind.writer,blot_error::Error.none;},_=>{return EffectRunnerKind.run,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::EffectRunnerKind,right:blot_check_check::EffectRunnerKind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::EffectRunnerKind) {blot_structural::hash(sink,blot_check_check::effectRunnerKindCode(value) as! u8);}
fn codeCode(value:Code)->u32 {match value {Code.function_return_required=>{return 0;},Code.task_escape=>{return 1;},Code.task_handle_consumed=>{return 2;},Code.task_capture_transfer=>{return 3;},Code.task_capability_shared=>{return 4;},Code.task_regions_overlap=>{return 5;},Code.task_host_contract=>{return 6;},Code.task_budget=>{return 7;},Code.invalid_proof_operand=>{return 8;},Code.proof_scope_escape=>{return 9;},Code.proof_runtime_use=>{return 10;},Code.proof_mismatch=>{return 11;},Code.contradictory_proof=>{return 12;},Code.proof_analysis_limit=>{return 13;},Code.effect_identity_scope=>{return 14;},Code.capability_escape=>{return 15;},Code.capability_analysis_limit=>{return 16;},Code.undetermined_implementation=>{return 17;},Code.orphan_implementation=>{return 18;},Code.overlapping_implementation=>{return 19;},Code.incompatible_implementation=>{return 20;},Code.recursive_evidence=>{return 21;},Code.missing_type_member=>{return 22;},Code.associated_arity=>{return 23;},Code.recursive_associated_type=>{return 24;},Code.associated_limit=>{return 25;},Code.missing_implementation=>{return 26;},Code.private_access=>{return 27;},Code.private_identity_escape=>{return 28;},Code.unbound_alias_row=>{return 29;},Code.recursive_contract=>{return 30;},Code.contract_arity=>{return 31;},Code.recursive_type_alias=>{return 32;},Code.typed_hole=>{return 33;},Code.effect_member=>{return 34;},Code.integer_range=>{return 35;},Code.float_range=>{return 36;},Code.float_literal=>{return 37;},Code.module_loader_required=>{return 38;},Code.intrinsic_arity=>{return 39;},Code.requests_scope=>{return 40;},Code.yield_scope=>{return 41;},Code.request_loop_scope=>{return 42;},Code.request_loop_body=>{return 43;},Code.request_loop_range=>{return 44;},Code.request_binding=>{return 45;},Code.request_completion=>{return 46;},Code.request_clause_fallthrough=>{return 47;},Code.request_completion_fallthrough=>{return 48;},Code.duplicate_request_handler=>{return 49;},Code.request_case_scope=>{return 50;},Code.unknown_value=>{return 51;},Code.syntax=>{return 52;},Code.duplicate_name=>{return 53;},Code.unknown_name=>{return 54;},Code.type_mismatch=>{return 55;},Code.infinite_type=>{return 56;},Code.effect_mismatch=>{return 57;},Code.infinite_effect=>{return 58;},Code.const_effect=>{return 59;},Code.initializer_effect=>{return 60;},Code.let_effect=>{return 61;},Code.sealed_effect=>{return 62;},Code.effect_arity=>{return 63;},Code.effect_family=>{return 64;},Code.unknown_effect=>{return 65;},Code.invalid_effect_annotation=>{return 66;},Code.invalid_constraint=>{return 67;},Code.higher_rank_constraint=>{return 68;},Code.missing_predicate=>{return 69;},Code.ambiguous_qualified=>{return 70;},Code.annotation_kind_mismatch=>{return 71;},Code.unsupported_polymorphic_effect_label=>{return 72;},Code.operation_signature=>{return 73;},Code.type_arity=>{return 74;},Code.operation_target=>{return 75;},Code.invalid_state_provider=>{return 76;},Code.unsupported=>{return 77;},Code.unsupported_attribute=>{return 78;},Code.recursive_tag=>{return 79;},Code.function_target=>{return 80;},Code.open_effect_descriptor=>{return 81;},Code.unsupported_expression=>{return 82;},Code.unsupported_type=>{return 83;},Code.ambiguous_operator=>{return 84;},Code.ambiguous_associated=>{return 85;},Code.missing_associated=>{return 86;},Code.ambiguous_member=>{return 87;},Code.missing_member=>{return 88;},Code.type_constructor_required=>{return 89;},Code.invalid_provider=>{return 90;},Code.resolver_required=>{return 91;},Code.literal_required=>{return 92;},Code.call_arity=>{return 93;},Code.break_scope=>{return 94;},Code.continue_scope=>{return 95;},Code.invalid_return=>{return 96;},Code.unreachable_statement=>{return 97;},Code.invalid_operator=>{return 98;},Code.return_outside_block=>{return 99;},Code.return_outside_function=>{return 100;},Code.return_across_continuation=>{return 101;},Code.unknown_rebinding=>{return 102;},Code.dead_rebinding=>{return 103;},Code.case_arm_return=>{return 104;},Code.nesting_limit=>{return 105;},Code.unknown_constructor=>{return 106;},Code.constructor_marker=>{return 107;},Code.type_parameter=>{return 108;},Code.type_argument=>{return 109;},Code.duplicate_type_parameter=>{return 110;},Code.duplicate_type_field=>{return 111;},Code.unknown_field=>{return 112;},Code.duplicate_field=>{return 113;},Code.missing_field=>{return 114;},Code.non_exhaustive_match=>{return 115;},Code.refutable_pattern=>{return 116;},Code.constructor_arity=>{return 117;},Code.unknown_product_shape=>{return 118;},Code.product_index=>{return 119;},Code.product_index_literal=>{return 120;},Code.pattern_arity=>{return 121;},Code.pattern_bindings=>{return 122;},Code.value_pattern_type=>{return 123;},Code.non_exiting_fallback=>{return 124;},Code.unknown_operator=>{return 125;},Code.operator_associativity=>{return 126;},Code.operator_header_order=>{return 127;},Code.operator_precedence=>{return 128;},Code.duplicate_operator=>{return 129;},Code.unsupported_prefix=>{return 130;},Code.unknown_intrinsic=>{return 131;},Code.alternative_bindings=>{return 132;},Code.duplicate_pattern_binding=>{return 133;},Code.duplicate_record_field=>{return 134;},Code.unknown_record_field=>{return 135;},Code.record_constructor=>{return 136;},Code.missing_record_field=>{return 137;},Code.unknown_modifier=>{return 138;},Code.guard_fallthrough=>{return 139;},Code.product_arity=>{return 140;},Code.inference_budget=>{return 141;},Code.skolem_escape=>{return 142;},Code.rank_mismatch=>{return 143;},Code.package_expected=>{return 144;},Code.package_witness_mismatch=>{return 145;},Code.package_escape=>{return 146;},Code.abstract_representation_access=>{return 147;},Code.use_after_move=>{return 148;},Code.duplicate_owner=>{return 149;},Code.borrow_conflict=>{return 150;},Code.borrow_escape=>{return 151;},Code.once_reused=>{return 152;},Code.multiplicity_unknown=>{return 153;},Code.cleanup_not_safe=>{return 154;},Code.usage_evidence_mismatch=>{return 155;},Code.usage_analysis_limit=>{return 156;},Code.code_shape_mismatch=>{return 157;},Code.stage_unavailable=>{return 158;},Code.cross_stage_authority=>{return 159;},Code.descriptor_private=>{return 160;},Code.generated_binding_escape=>{return 161;},Code.staging_budget=>{return 162;},}}
fn codeFromCode(code:u32)->Code,blot_error::Error {match code {0=>{return Code.function_return_required,blot_error::Error.none;},1=>{return Code.task_escape,blot_error::Error.none;},2=>{return Code.task_handle_consumed,blot_error::Error.none;},3=>{return Code.task_capture_transfer,blot_error::Error.none;},4=>{return Code.task_capability_shared,blot_error::Error.none;},5=>{return Code.task_regions_overlap,blot_error::Error.none;},6=>{return Code.task_host_contract,blot_error::Error.none;},7=>{return Code.task_budget,blot_error::Error.none;},8=>{return Code.invalid_proof_operand,blot_error::Error.none;},9=>{return Code.proof_scope_escape,blot_error::Error.none;},10=>{return Code.proof_runtime_use,blot_error::Error.none;},11=>{return Code.proof_mismatch,blot_error::Error.none;},12=>{return Code.contradictory_proof,blot_error::Error.none;},13=>{return Code.proof_analysis_limit,blot_error::Error.none;},14=>{return Code.effect_identity_scope,blot_error::Error.none;},15=>{return Code.capability_escape,blot_error::Error.none;},16=>{return Code.capability_analysis_limit,blot_error::Error.none;},17=>{return Code.undetermined_implementation,blot_error::Error.none;},18=>{return Code.orphan_implementation,blot_error::Error.none;},19=>{return Code.overlapping_implementation,blot_error::Error.none;},20=>{return Code.incompatible_implementation,blot_error::Error.none;},21=>{return Code.recursive_evidence,blot_error::Error.none;},22=>{return Code.missing_type_member,blot_error::Error.none;},23=>{return Code.associated_arity,blot_error::Error.none;},24=>{return Code.recursive_associated_type,blot_error::Error.none;},25=>{return Code.associated_limit,blot_error::Error.none;},26=>{return Code.missing_implementation,blot_error::Error.none;},27=>{return Code.private_access,blot_error::Error.none;},28=>{return Code.private_identity_escape,blot_error::Error.none;},29=>{return Code.unbound_alias_row,blot_error::Error.none;},30=>{return Code.recursive_contract,blot_error::Error.none;},31=>{return Code.contract_arity,blot_error::Error.none;},32=>{return Code.recursive_type_alias,blot_error::Error.none;},33=>{return Code.typed_hole,blot_error::Error.none;},34=>{return Code.effect_member,blot_error::Error.none;},35=>{return Code.integer_range,blot_error::Error.none;},36=>{return Code.float_range,blot_error::Error.none;},37=>{return Code.float_literal,blot_error::Error.none;},38=>{return Code.module_loader_required,blot_error::Error.none;},39=>{return Code.intrinsic_arity,blot_error::Error.none;},40=>{return Code.requests_scope,blot_error::Error.none;},41=>{return Code.yield_scope,blot_error::Error.none;},42=>{return Code.request_loop_scope,blot_error::Error.none;},43=>{return Code.request_loop_body,blot_error::Error.none;},44=>{return Code.request_loop_range,blot_error::Error.none;},45=>{return Code.request_binding,blot_error::Error.none;},46=>{return Code.request_completion,blot_error::Error.none;},47=>{return Code.request_clause_fallthrough,blot_error::Error.none;},48=>{return Code.request_completion_fallthrough,blot_error::Error.none;},49=>{return Code.duplicate_request_handler,blot_error::Error.none;},50=>{return Code.request_case_scope,blot_error::Error.none;},51=>{return Code.unknown_value,blot_error::Error.none;},52=>{return Code.syntax,blot_error::Error.none;},53=>{return Code.duplicate_name,blot_error::Error.none;},54=>{return Code.unknown_name,blot_error::Error.none;},55=>{return Code.type_mismatch,blot_error::Error.none;},56=>{return Code.infinite_type,blot_error::Error.none;},57=>{return Code.effect_mismatch,blot_error::Error.none;},58=>{return Code.infinite_effect,blot_error::Error.none;},59=>{return Code.const_effect,blot_error::Error.none;},60=>{return Code.initializer_effect,blot_error::Error.none;},61=>{return Code.let_effect,blot_error::Error.none;},62=>{return Code.sealed_effect,blot_error::Error.none;},63=>{return Code.effect_arity,blot_error::Error.none;},64=>{return Code.effect_family,blot_error::Error.none;},65=>{return Code.unknown_effect,blot_error::Error.none;},66=>{return Code.invalid_effect_annotation,blot_error::Error.none;},67=>{return Code.invalid_constraint,blot_error::Error.none;},68=>{return Code.higher_rank_constraint,blot_error::Error.none;},69=>{return Code.missing_predicate,blot_error::Error.none;},70=>{return Code.ambiguous_qualified,blot_error::Error.none;},71=>{return Code.annotation_kind_mismatch,blot_error::Error.none;},72=>{return Code.unsupported_polymorphic_effect_label,blot_error::Error.none;},73=>{return Code.operation_signature,blot_error::Error.none;},74=>{return Code.type_arity,blot_error::Error.none;},75=>{return Code.operation_target,blot_error::Error.none;},76=>{return Code.invalid_state_provider,blot_error::Error.none;},77=>{return Code.unsupported,blot_error::Error.none;},78=>{return Code.unsupported_attribute,blot_error::Error.none;},79=>{return Code.recursive_tag,blot_error::Error.none;},80=>{return Code.function_target,blot_error::Error.none;},81=>{return Code.open_effect_descriptor,blot_error::Error.none;},82=>{return Code.unsupported_expression,blot_error::Error.none;},83=>{return Code.unsupported_type,blot_error::Error.none;},84=>{return Code.ambiguous_operator,blot_error::Error.none;},85=>{return Code.ambiguous_associated,blot_error::Error.none;},86=>{return Code.missing_associated,blot_error::Error.none;},87=>{return Code.ambiguous_member,blot_error::Error.none;},88=>{return Code.missing_member,blot_error::Error.none;},89=>{return Code.type_constructor_required,blot_error::Error.none;},90=>{return Code.invalid_provider,blot_error::Error.none;},91=>{return Code.resolver_required,blot_error::Error.none;},92=>{return Code.literal_required,blot_error::Error.none;},93=>{return Code.call_arity,blot_error::Error.none;},94=>{return Code.break_scope,blot_error::Error.none;},95=>{return Code.continue_scope,blot_error::Error.none;},96=>{return Code.invalid_return,blot_error::Error.none;},97=>{return Code.unreachable_statement,blot_error::Error.none;},98=>{return Code.invalid_operator,blot_error::Error.none;},99=>{return Code.return_outside_block,blot_error::Error.none;},100=>{return Code.return_outside_function,blot_error::Error.none;},101=>{return Code.return_across_continuation,blot_error::Error.none;},102=>{return Code.unknown_rebinding,blot_error::Error.none;},103=>{return Code.dead_rebinding,blot_error::Error.none;},104=>{return Code.case_arm_return,blot_error::Error.none;},105=>{return Code.nesting_limit,blot_error::Error.none;},106=>{return Code.unknown_constructor,blot_error::Error.none;},107=>{return Code.constructor_marker,blot_error::Error.none;},108=>{return Code.type_parameter,blot_error::Error.none;},109=>{return Code.type_argument,blot_error::Error.none;},110=>{return Code.duplicate_type_parameter,blot_error::Error.none;},111=>{return Code.duplicate_type_field,blot_error::Error.none;},112=>{return Code.unknown_field,blot_error::Error.none;},113=>{return Code.duplicate_field,blot_error::Error.none;},114=>{return Code.missing_field,blot_error::Error.none;},115=>{return Code.non_exhaustive_match,blot_error::Error.none;},116=>{return Code.refutable_pattern,blot_error::Error.none;},117=>{return Code.constructor_arity,blot_error::Error.none;},118=>{return Code.unknown_product_shape,blot_error::Error.none;},119=>{return Code.product_index,blot_error::Error.none;},120=>{return Code.product_index_literal,blot_error::Error.none;},121=>{return Code.pattern_arity,blot_error::Error.none;},122=>{return Code.pattern_bindings,blot_error::Error.none;},123=>{return Code.value_pattern_type,blot_error::Error.none;},124=>{return Code.non_exiting_fallback,blot_error::Error.none;},125=>{return Code.unknown_operator,blot_error::Error.none;},126=>{return Code.operator_associativity,blot_error::Error.none;},127=>{return Code.operator_header_order,blot_error::Error.none;},128=>{return Code.operator_precedence,blot_error::Error.none;},129=>{return Code.duplicate_operator,blot_error::Error.none;},130=>{return Code.unsupported_prefix,blot_error::Error.none;},131=>{return Code.unknown_intrinsic,blot_error::Error.none;},132=>{return Code.alternative_bindings,blot_error::Error.none;},133=>{return Code.duplicate_pattern_binding,blot_error::Error.none;},134=>{return Code.duplicate_record_field,blot_error::Error.none;},135=>{return Code.unknown_record_field,blot_error::Error.none;},136=>{return Code.record_constructor,blot_error::Error.none;},137=>{return Code.missing_record_field,blot_error::Error.none;},138=>{return Code.unknown_modifier,blot_error::Error.none;},139=>{return Code.guard_fallthrough,blot_error::Error.none;},140=>{return Code.product_arity,blot_error::Error.none;},141=>{return Code.inference_budget,blot_error::Error.none;},142=>{return Code.skolem_escape,blot_error::Error.none;},143=>{return Code.rank_mismatch,blot_error::Error.none;},144=>{return Code.package_expected,blot_error::Error.none;},145=>{return Code.package_witness_mismatch,blot_error::Error.none;},146=>{return Code.package_escape,blot_error::Error.none;},147=>{return Code.abstract_representation_access,blot_error::Error.none;},148=>{return Code.use_after_move,blot_error::Error.none;},149=>{return Code.duplicate_owner,blot_error::Error.none;},150=>{return Code.borrow_conflict,blot_error::Error.none;},151=>{return Code.borrow_escape,blot_error::Error.none;},152=>{return Code.once_reused,blot_error::Error.none;},153=>{return Code.multiplicity_unknown,blot_error::Error.none;},154=>{return Code.cleanup_not_safe,blot_error::Error.none;},155=>{return Code.usage_evidence_mismatch,blot_error::Error.none;},156=>{return Code.usage_analysis_limit,blot_error::Error.none;},157=>{return Code.code_shape_mismatch,blot_error::Error.none;},158=>{return Code.stage_unavailable,blot_error::Error.none;},159=>{return Code.cross_stage_authority,blot_error::Error.none;},160=>{return Code.descriptor_private,blot_error::Error.none;},161=>{return Code.generated_binding_escape,blot_error::Error.none;},162=>{return Code.staging_budget,blot_error::Error.none;},_=>{return Code.function_return_required,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Code,right:blot_check_check::Code)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::Code) {blot_structural::hash(sink,blot_check_check::codeCode(value) as! u8);}
fn requestControl_kindCode(value:RequestControl_kind)->u32 {match value {RequestControl_kind.reply=>{return 0;},RequestControl_kind.cancel=>{return 1;},RequestControl_kind.break_=>{return 2;},}}
fn requestControl_kindFromCode(code:u32)->RequestControl_kind,blot_error::Error {match code {0=>{return RequestControl_kind.reply,blot_error::Error.none;},1=>{return RequestControl_kind.cancel,blot_error::Error.none;},2=>{return RequestControl_kind.break_,blot_error::Error.none;},_=>{return RequestControl_kind.reply,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::RequestControl_kind,right:blot_check_check::RequestControl_kind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::RequestControl_kind) {blot_structural::hash(sink,blot_check_check::requestControl_kindCode(value) as! u8);}
fn stateCode(value:State)->u32 {match value {State.pending=>{return 0;},State.active=>{return 1;},State.complete=>{return 2;},}}
fn stateFromCode(code:u32)->State,blot_error::Error {match code {0=>{return State.pending,blot_error::Error.none;},1=>{return State.active,blot_error::Error.none;},2=>{return State.complete,blot_error::Error.none;},_=>{return State.pending,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::State,right:blot_check_check::State)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::State) {blot_structural::hash(sink,blot_check_check::stateCode(value) as! u8);}
fn engine_implementation_member_states_stateCode(value:Engine_implementation_member_states_state)->u32 {match value {Engine_implementation_member_states_state.visiting=>{return 0;},Engine_implementation_member_states_state.ready=>{return 1;},}}
fn engine_implementation_member_states_stateFromCode(code:u32)->Engine_implementation_member_states_state,blot_error::Error {match code {0=>{return Engine_implementation_member_states_state.visiting,blot_error::Error.none;},1=>{return Engine_implementation_member_states_state.ready,blot_error::Error.none;},_=>{return Engine_implementation_member_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_implementation_member_states_state,right:blot_check_check::Engine_implementation_member_states_state)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::Engine_implementation_member_states_state) {blot_structural::hash(sink,blot_check_check::engine_implementation_member_states_stateCode(value) as! u8);}
fn engine_member_states_stateCode(value:Engine_member_states_state)->u32 {match value {Engine_member_states_state.visiting=>{return 0;},Engine_member_states_state.ready=>{return 1;},}}
fn engine_member_states_stateFromCode(code:u32)->Engine_member_states_state,blot_error::Error {match code {0=>{return Engine_member_states_state.visiting,blot_error::Error.none;},1=>{return Engine_member_states_state.ready,blot_error::Error.none;},_=>{return Engine_member_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_member_states_state,right:blot_check_check::Engine_member_states_state)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::Engine_member_states_state) {blot_structural::hash(sink,blot_check_check::engine_member_states_stateCode(value) as! u8);}
fn engine_contract_states_stateCode(value:Engine_contract_states_state)->u32 {match value {Engine_contract_states_state.visiting=>{return 0;},Engine_contract_states_state.ready=>{return 1;},}}
fn engine_contract_states_stateFromCode(code:u32)->Engine_contract_states_state,blot_error::Error {match code {0=>{return Engine_contract_states_state.visiting,blot_error::Error.none;},1=>{return Engine_contract_states_state.ready,blot_error::Error.none;},_=>{return Engine_contract_states_state.visiting,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::Engine_contract_states_state,right:blot_check_check::Engine_contract_states_state)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::Engine_contract_states_state) {blot_structural::hash(sink,blot_check_check::engine_contract_states_stateCode(value) as! u8);}
fn typeApplicationCode(value:TypeApplication)->u32 {match value {TypeApplication.missing_array=>{return 0;},TypeApplication.missing_nominal=>{return 1;},TypeApplication.extra=>{return 2;},}}
fn typeApplicationFromCode(code:u32)->TypeApplication,blot_error::Error {match code {0=>{return TypeApplication.missing_array,blot_error::Error.none;},1=>{return TypeApplication.missing_nominal,blot_error::Error.none;},2=>{return TypeApplication.extra,blot_error::Error.none;},_=>{return TypeApplication.missing_array,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::TypeApplication,right:blot_check_check::TypeApplication)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::TypeApplication) {blot_structural::hash(sink,blot_check_check::typeApplicationCode(value) as! u8);}
fn diagnosticContextKindCode(value:DiagnosticContextKind)->u32 {match value {DiagnosticContextKind.callee=>{return 0;},DiagnosticContextKind.argument=>{return 1;},DiagnosticContextKind.left_operand=>{return 2;},DiagnosticContextKind.right_operand=>{return 3;},}}
fn diagnosticContextKindFromCode(code:u32)->DiagnosticContextKind,blot_error::Error {match code {0=>{return DiagnosticContextKind.callee,blot_error::Error.none;},1=>{return DiagnosticContextKind.argument,blot_error::Error.none;},2=>{return DiagnosticContextKind.left_operand,blot_error::Error.none;},3=>{return DiagnosticContextKind.right_operand,blot_error::Error.none;},_=>{return DiagnosticContextKind.callee,blot_error::Error.invalid_artifact;},}}
fn blot_structural::equal(left:blot_check_check::DiagnosticContextKind,right:blot_check_check::DiagnosticContextKind)->bool {return left==right;}
fn blot_structural::hash<S>(sink:S&,value:blot_check_check::DiagnosticContextKind) {blot_structural::hash(sink,blot_check_check::diagnosticContextKindCode(value) as! u8);}
fn Engine::importBinding(self:Engine&,imported:ImportedBinding)->blot_error::Error {let key=Qualified{imported.namespace,imported.member};if imported.expose && ((imported.namespace==0 && self.hasGlobal(imported.name)) || (imported.namespace!=0 && self.hasQualified(key))) {return self.diagnostic(Code.duplicate_name,imported.origin);}self.frontend_work.import_requests+=1;if imported.interface.capability_flow==CapabilityFlow.scope_task {self.has_tasks=true;}if imported.interface.capability_parameters.inputInvokes() {self.has_input_invocations=true;}if !self.imported_values.contains(imported.target) {self.imported_values.insert(imported.target,imported);}if !imported.expose {return blot_error::Error.none;}if imported.namespace==0 {self.imported_globals.insert(imported.name,imported.target);}else {self.imported_qualified.insert(key,imported.target);}return blot_error::Error.none;}
fn Engine::importScheme(self:Engine&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,depth:i64)->blot_support::Option<u32>,blot_error::Error {let callee_mark=self.import_callees.len;let variable_mark=self.import_variables.len;let result,err=importSchemeBody(self,interface,target,name,origin,depth,callee_mark,variable_mark);self.import_callees.resize(callee_mark);self.import_variables.resize(variable_mark);return result,err;}
fn importSchemeBody(self:Engine&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,depth:i64,callee_mark:i64,variable_mark:i64)->blot_support::Option<u32>,blot_error::Error {
    self.frontend_work.import_requests+=1;let existing .= self.catalogs.external_targets.get(target);if existing {return blot_support::some(existing),blot_error::Error.none;}self.frontend_work.imported_schemes+=1;let range=interface.scheme.obligations;let constraints=interface.obligations[range.start..range.start+range.len];
    for constraint in constraints {if constraint.kind!=blot_check_types::ObligationKind.callee_use {continue;}let callee_interface=interface.callees.interface(constraint.identity.decl);if !callee_interface.present || depth>=256 {let err=self.diagnostic(Code.nesting_limit,origin);return blot_support::none<u32>(),err;}let callee,err=self.importScheme(callee_interface.value,ExternalTarget{target.unit,constraint.identity.decl},0,origin,depth+1);if err!=blot_error::Error.none || !callee.present {return callee,err;}self.import_callees.append(callee.value);}
    var copier=blot_check_check_scheme_import::init(interface.types,self.types,self.import_tables);let result,err=importSchemeCopied(self,copier,interface,target,name,origin,callee_mark,variable_mark);copier.deinit();return result,err;
}
fn importSchemeCopied(self:Engine&,copier:blot_check_check_scheme_import::Copier&,interface:SchemeInterface,target:ExternalTarget,name:u32,origin:u32,callee_mark:i64,variable_mark:i64)->blot_support::Option<u32>,blot_error::Error {
    for old in copier.source.list(interface.scheme.variables) {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}copier.mapping.insert(copier.source.head(old,0),fresh);self.import_variables.append(fresh);}
    let row_variables,err=copier.quantifiedRows(interface.scheme.row_variables);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let closed_rows,err=copier.quantifiedRows(interface.scheme.closed_rows);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let root,err=copier.copy(interface.scheme.root,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let start=self.obligations.len as u32;var shared:i64=0;let range=interface.scheme.obligations;
    for constraint in interface.obligations[range.start..range.start+range.len] {var value=constraint;value.source=origin;if constraint.kind==blot_check_types::ObligationKind.callee_use {value.identity=Identity{self.unit,self.import_callees[callee_mark+shared]};shared+=1;}let ty,err=copier.copy(constraint.ty,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.ty=ty;if constraint.result!=0 {let copied,err=copier.copy(constraint.result,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.result=copied;}if constraint.other!=0 {let copied,err=copier.copy(constraint.other,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.other=copied;}if constraint.signature!=0 {let copied,err=copier.copy(constraint.signature,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}value.signature=copied;}self.obligations.append(value);}
    let variables,err=self.types.saveList(self.import_variables[variable_mark..]);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let generative,err=copier.copyGenerative(interface.scheme.generative);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let principal=blot_check_types::Scheme{root:root,variables:variables,row_variables:row_variables,closed_rows:closed_rows,generative:generative,obligations:blot_check_types::List{start,(self.obligations.len-start) as u32}};
    let binding,err=self.addBinding(Binding{name:name,declaration:origin,owner:origin,kind:Kind.external,ty:root,scheme:principal,capability_flow:interface.capability_flow,capability_parameters:interface.capability_parameters,named_function:interface.named_function,external:blot_support::some(target)});if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}
    let source_header .= interface.proof_contract;if source_header {let err=source_header.signature().validate(self.proof_body.values.limits);if err!=blot_error::Error.none {let accepted,error=self.proofHeaderFailure(err,origin);return blot_support::none<u32>(),error;}let header,err=source_header.clone(self.proof_header_owned);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self.proof_contracts.append(ProofContract{binding,header,[]});}
    var recipe_source=CapabilitySource{interface.callees,interface.producer_binding};if interface.capability_source.present {recipe_source=interface.capability_source.value;}let header=recipe_source.callees.capabilityContract(recipe_source.binding,interface.capability_parameters.arity());if header.present {let err=self.importCapabilityRecipe(binding,header.value);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}}
    if self.execution.imported_summary_reuse && interface.summary.present {let summary,err=self.relocateSummary(copier,interface.summary.value);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self.bindings[binding].summary=summary;self.frontend_work.imported_summary_reuses+=1;}else {let summary,err=self.summarize(principal);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self.bindings[binding].summary=summary;}
    self.catalogs.external_targets.insert(target,binding);return blot_support::some(binding),blot_error::Error.none;
}
fn Engine::importCapabilityRecipe(self:Engine&,binding:u32,header:blot_check_capability_contracts::Recipe)->blot_error::Error {let checkpoint=self.capability_store.mark();let committed,err=importCapabilityRecipeBody(self,binding,header);if !committed {self.capability_store.rollback(checkpoint);}return err;}
fn importCapabilityRecipeBody(self:Engine&,binding:u32,header:blot_check_capability_contracts::Recipe)->bool,blot_error::Error {var arguments:u32[16];for index in 0..header.arity {let value,err=self.capability_store.append(blot_check_capability_contracts::Term{tag:blot_check_capability_contracts::Tag.parameter,a:index as u32});if err!=blot_error::Error.none {if err==blot_error::Error.out_of_memory {return false,err;}if err==blot_error::Error.capability_analysis_limit {return false,blot_error::Error.none;}return false,blot_error::Error.type_limit;}arguments[index]=value;}let root,err=self.capability_store.instantiate(header,arguments[..header.arity]);if err!=blot_error::Error.none {if err==blot_error::Error.out_of_memory {return false,err;}if err==blot_error::Error.capability_analysis_limit {return false,blot_error::Error.none;}return false,blot_error::Error.type_limit;}let err=self.capability_store.view().validate(root,header.arity,true);if err!=blot_error::Error.none {return false,blot_error::Error.none;}self.capability_roots.append(blot_check_capability_contracts::Binding{binding,root});return true,blot_error::Error.none;}
fn Engine::relocateSummary(self:Engine&,copier:blot_check_check_scheme_import::Copier&,source:SchemeSummary)->SchemeSummary,blot_error::Error {var result=source;let start=self.import_variables.len;for variable in copier.source.list(source.public_variables) {let copied,err=copier.copy(variable,0);if err!=blot_error::Error.none {self.import_variables.resize(start);return result,err;}self.import_variables.append(copied);}let variables,err=self.types.saveList(self.import_variables[start..]);self.import_variables.resize(start);if err!=blot_error::Error.none {return result,err;}result.public_variables=variables;let rows,err=copier.relocatedRows(copier.source.list(source.public_rows));if err!=blot_error::Error.none {return result,err;}result.public_rows=rows;
    let inputs,err=self.types.saveList(copier.source.list(source.public_inputs));if err!=blot_error::Error.none {return result,err;}result.public_inputs=inputs;let outputs,err=self.types.saveList(copier.source.list(source.public_outputs));if err!=blot_error::Error.none {return result,err;}result.public_outputs=outputs;let requirements,err=self.types.saveList(copier.source.list(source.requirement_variables));if err!=blot_error::Error.none {return result,err;}result.requirement_variables=requirements;let row_requirements,err=self.types.saveList(copier.source.list(source.requirement_rows));if err!=blot_error::Error.none {return result,err;}result.requirement_rows=row_requirements;return result,blot_error::Error.none;
}
fn Engine::appendPending(self:Engine&,item:PendingObligation)->blot_error::Error {self.scheme_dependencies.truncate(self.pending.len);var value=item;value.scope=self.qualification_scope;value.method_member=value.method_member || (value.value.kind==blot_check_types::ObligationKind.receiver && !value.value.explicit);self.pending.append(value);self.counters.obligations_appended+=1;self.counters.pending_peak=max(self.counters.pending_peak,self.pending.len as u64);return blot_error::Error.none;}
// Exact owned diagnostic bytes are tracked by their typed slice boundaries.
struct DetailRun {bytes:const u8[:]=[],live:bool=false}
reusable[] var diagnostic_text:u8[>..];
var diagnostic_runs:DetailRun[>..<];
fn ownDiagnosticText(text:const u8[:])->const u8[:] {let bytes=diagnostic_text.alloc_slice(text.len);for byte,index in text {bytes[index]=byte;}var index:i64=0;while index<diagnostic_runs.len && diagnostic_runs[index].live {index+=1;}if index==diagnostic_runs.len {diagnostic_runs.append(DetailRun{});}diagnostic_runs[index]=DetailRun{bytes,true};return bytes;}
fn freeDiagnosticText(text:const u8[:]) {for &run in diagnostic_runs {if run.live && run.bytes .== text {diagnostic_text.free_slice(run.bytes);run.bytes=[];run.live=false;return;}}}
fn decimal(out:u8[>..<]&,value:u32) {var digits:u8[10];var remaining=value;var count:i64=0;while true {digits[count]=('0' as u8)+(remaining%10) as u8;count+=1;remaining/=10;if remaining==0 {break;}}while count!=0 {count-=1;out.append(digits[count]);}}
fn Engine::usageConflict(self:Engine&,code:Code,id:u32,first:u32,declaration:u32)->blot_error::Error {let err=self.diagnostic(code,id);if err!=blot_error::Error.none {return err;}let index=self.diagnostics.len-1;self.diagnostic_bytes.clear();self.diagnostic_bytes.append(self.diagnostics[index].message());self.diagnostic_bytes.append("; first conflicting use at byte ");decimal(self.diagnostic_bytes,self.tree.span(first).start);self.diagnostic_bytes.append(", owner declared at byte ");decimal(self.diagnostic_bytes,self.tree.span(declaration).start);self.diagnostics[index].detail=blot_support::some(ownDiagnosticText(self.diagnostic_bytes));return blot_error::Error.none;}
fn Engine::usageLoanFootprint(self:Engine&,source:u32,region:u32)->bool,blot_error::Error {var remaining:i64=65536;let footprint,err=self.valueFootprint(source,FootprintBoundary{loan:region},[],remaining,0);if err!=blot_error::Error.none {return false,err;}if footprint.present {return footprint.value,blot_error::Error.none;}return self.scopeFootprintDepth(self.expr_types[source],0,remaining,[],FootprintBoundary{loan:region});}
fn Engine::usageDiagnostic(self:Engine&,code:Code,id:u32)->blot_error::Error {return self.diagnostic(code,id);}
fn Engine::diagnostic(self:Engine&,code:Code,id:u32)->blot_error::Error {
    let origin=tagOrigin(self.tag_origins,self.tree.span(id));var source=id;if origin!=0 {source=origin;}var span=self.tree.span(source);
    if origin==0 && self.tree.node(id).tag==blot_parse_ast::tag_binary && (code==Code.type_mismatch || code==Code.effect_mismatch || code==Code.infinite_type || code==Code.infinite_effect) {let point=blot_parse_source_operators::origin(self.tree,id);span=blot_parse_ast::Span{point,point};}
    self.diagnostics.append(Diagnostic{code:code,span:span,node:source});if origin==0 && (code==Code.type_mismatch || code==Code.effect_mismatch || code==Code.missing_associated) {let issue .= self.diagnostics[self.diagnostics.len-1];let node=self.tree.node(id);if node.tag==blot_parse_ast::tag_apply {issue.contexts=[DiagnosticContext{DiagnosticContextKind.callee,self.tree.span(node.a)},DiagnosticContext{DiagnosticContextKind.argument,self.tree.span(node.b)}];issue.context_len=2;}else if node.tag==blot_parse_ast::tag_binary {issue.contexts=[DiagnosticContext{DiagnosticContextKind.left_operand,self.tree.span(node.b)},DiagnosticContext{DiagnosticContextKind.right_operand,self.tree.span(node.c)}];issue.context_len=2;}}
    match code {Code.missing_implementation,Code.incompatible_implementation,Code.recursive_evidence,Code.recursive_associated_type,Code.associated_limit,Code.overlapping_implementation,Code.ambiguous_qualified=>{return self.explainImplementation(id);},_=>{},}return blot_error::Error.none;
}
fn Engine::constrain(self:Engine&,a:u32,b:u32,id:u32)->blot_error::Error {var left=a;var right=b;if self.implementations.len!=0 && self.types.has_projections {let normalized,err=self.normalizeAssociated(left,id,false);if err!=blot_error::Error.none {return err;}left=normalized;let normalized,err=self.normalizeAssociated(right,id,false);if err!=blot_error::Error.none {return err;}right=normalized;}if self.has_associated_types && self.qualifications.len!=0 {let rewritten,err=self.rewriteGiven(left,0);if err!=blot_error::Error.none {return err;}left=rewritten;let rewritten,err=self.rewriteGiven(right,0);if err!=blot_error::Error.none {return err;}right=rewritten;}return self.constrainRaw(left,right,id);}
fn Engine::constrainRaw(self:Engine&,left:u32,right:u32,id:u32)->blot_error::Error {let err=self.constrainEquationRoot(left,right,id);match err {
    blot_error::Error.none=>{return blot_error::Error.none;},blot_error::Error.out_of_memory=>{return err;},blot_error::Error.infinite_type=>{return self.diagnostic(Code.infinite_type,id);},blot_error::Error.infinite_effect=>{return self.diagnostic(Code.infinite_effect,id);},blot_error::Error.type_limit=>{return self.diagnostic(Code.nesting_limit,id);},
    blot_error::Error.type_mismatch,blot_error::Error.effect_mismatch=>{var code=Code.effect_mismatch;if err==blot_error::Error.type_mismatch {code=Code.type_mismatch;}let error=self.diagnostic(code,id);if error!=blot_error::Error.none {return error;}let application=self.tree.node(id).tag==blot_parse_ast::tag_apply;let first=self.types.node(self.types.head(left,0));let second=self.types.node(self.types.head(right,0));self.expected_bytes.clear();self.actual_bytes.clear();var arguments=application && first.tag==blot_check_types::Tag.function && second.tag==blot_check_types::Tag.function;
        if arguments {let error=blot_reuse_type_display::append(self,self.expected_bytes,first.a);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::append(self,self.actual_bytes,second.a);if error!=blot_error::Error.none {return error;}if self.expected_bytes==self.actual_bytes {arguments=false;}}
        if !arguments {self.expected_bytes.clear();self.actual_bytes.clear();let error=blot_reuse_type_display::append(self,self.expected_bytes,left);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::append(self,self.actual_bytes,right);if error!=blot_error::Error.none {return error;}}
        self.diagnostic_bytes.clear();var prefix="Effect rows do not match; ";if err==blot_error::Error.type_mismatch {prefix="Types do not match; ";}let error=blot_reuse_type_display::text(self,self.diagnostic_bytes,prefix);if error!=blot_error::Error.none {return error;}var expected="one side: ";if arguments {expected="expected argument: ";}let error=blot_reuse_type_display::text(self,self.diagnostic_bytes,expected);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::text(self,self.diagnostic_bytes,self.expected_bytes);if error!=blot_error::Error.none {return error;}var actual="; other side: ";if arguments {actual="; actual argument: ";}let error=blot_reuse_type_display::text(self,self.diagnostic_bytes,actual);if error!=blot_error::Error.none {return error;}let error=blot_reuse_type_display::text(self,self.diagnostic_bytes,self.actual_bytes);if error!=blot_error::Error.none {return error;}self.diagnostics[self.diagnostics.len-1].detail=blot_support::some(ownDiagnosticText(self.diagnostic_bytes));return blot_error::Error.none;
    },_=>{return err;},
}}
struct FootprintBoundary {rank_scope:u32=0,exiting:blot_support::Option<Identity> = blot_support::none<Identity>(),storage_depth:blot_support::Option<i64> = blot_support::none<i64>(),loan:u32=0,capture_usage:bool=false,task_group:u32=0}
type EquationPairs=blot_support_pooled_map::Map<u64,bool>;
reusable[] var equation_pair_slots:dictionary_slot<u64,bool>[>..];
reusable[] var equation_type_ids:u32[>..];
reusable[] var given_equation_values:blot_eval_given_equations::Equation[>..];
fn Engine::constrainEquationRoot(self:Engine&,left:u32,right:u32,source:u32)->blot_error::Error {if self.implementations.len==0 || !self.types.has_projections {return self.types.unify(left,right);}var pairs=EquationPairs{};let err=self.constrainEquation(left,right,source,0,pairs);blot_support_pooled_map::deinit(pairs,equation_pair_slots);return err;}
fn Engine::constrainEquation(self:Engine&,left:u32,right:u32,source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {let first=self.types.head(left,0);let second=self.types.head(right,0);if first==second {return blot_error::Error.none;}let key=((first as u64)<<32)|second;if blot_support_pooled_map::contains(pairs,key) {return blot_error::Error.none;}let err=self.constrainEquationPair(left,right,source,depth,pairs);if err!=blot_error::Error.none {return err;}blot_support_pooled_map::insert(pairs,key,true,equation_pair_slots);return blot_error::Error.none;}
fn Engine::constrainEquationPair(self:Engine&,left:u32,right:u32,source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {
    if self.implementations.len==0 || !self.types.has_projections {return self.types.unify(left,right);}if depth>=256 {return blot_error::Error.type_limit;}let allowed,err=self.associatedStep(source);if err!=blot_error::Error.none {return err;}if !allowed {return blot_error::Error.type_limit;}let first=self.types.node(self.types.head(left,0));let second=self.types.node(self.types.head(right,0));
    if first.tag==blot_check_types::Tag.function && second.tag==blot_check_types::Tag.function {let err=self.constrainEquation(first.a,second.a,source,depth+1,pairs);if err!=blot_error::Error.none {return err;}let err=self.constrainEquation(first.b,second.b,source,depth+1,pairs);if err!=blot_error::Error.none {return err;}return self.types.unifyEffects(first.c,second.c);}
    if first.tag==second.tag {match first.tag {
        blot_check_types::Tag.array,blot_check_types::Tag.list,blot_check_types::Tag.cursor=>{return self.constrainEquation(first.a,second.a,source,depth+1,pairs);},
        blot_check_types::Tag.product=>{if first.b!=second.b {return blot_error::Error.type_mismatch;}let old=equation_type_ids.alloc_slice(first.b);let actuals=equation_type_ids.alloc_slice(second.b);for value,index in self.types.list(blot_check_types::List{first.a,first.b}) {old[index]=value;}for value,index in self.types.list(blot_check_types::List{second.a,second.b}) {actuals[index]=value;}let err=constrainProduct(self,old,actuals,source,depth,pairs);equation_type_ids.free_slice(actuals);equation_type_ids.free_slice(old);return err;},_=>{},
    }}
    var before,err=self.normalizeAssociated(left,source,false);if err!=blot_error::Error.none {return err;}var after,err=self.normalizeAssociated(right,source,false);if err!=blot_error::Error.none {return err;}if self.qualifications.len!=0 {let rewritten,err=self.rewriteGiven(before,0);if err!=blot_error::Error.none {return err;}before=rewritten;let rewritten,err=self.rewriteGiven(after,0);if err!=blot_error::Error.none {return err;}after=rewritten;}return self.types.unify(before,after);
}
fn constrainProduct(self:Engine&,old:const u32[:],actuals:const u32[:],source:u32,depth:i64,pairs:EquationPairs&)->blot_error::Error {for before,index in old {let err=self.constrainEquation(before,actuals[index],source,depth+1,pairs);if err!=blot_error::Error.none {return err;}}return blot_error::Error.none;}
fn Engine::rewriteGiven(self:Engine&,root:u32,depth:i64)->u32,blot_error::Error {if depth>=256 {return 0,blot_error::Error.type_limit;}var capacity:i64=0;for boundary in self.qualifications {if boundary.owner==self.current {capacity+=boundary.clauses.len;}}let equations=given_equation_values.alloc_slice(capacity);let result,err=rewriteGivenBody(self,root,equations);given_equation_values.free_slice(equations);return result,err;}
fn rewriteGivenBody(self:Engine&,root:u32,equations:blot_eval_given_equations::Equation[:])->u32,blot_error::Error {var count:i64=0;for boundary in self.qualifications {if boundary.owner!=self.current {continue;}for equation in self.declared_obligations[boundary.clauses.start..boundary.clauses.start+boundary.clauses.len] {if equation.kind!=blot_check_types::ObligationKind.type_eq {continue;}let err=self.types.chargeProjection();if err!=blot_error::Error.none {return 0,err;}equations[count]=blot_eval_given_equations::Equation{equation.ty,equation.result};count+=1;}}var rewrite=blot_eval_given_equations::Rewrite{store:self.types,equations:equations[..count]};return rewrite.normalize(root);}
fn Engine::constrainEffects(self:Engine&,left:u32,right:u32,source:u32)->blot_error::Error {let err=self.types.unifyEffects(left,right);if err==blot_error::Error.effect_mismatch {return self.diagnostic(Code.effect_mismatch,source);}if err==blot_error::Error.infinite_effect {return self.diagnostic(Code.infinite_effect,source);}return err;}
fn Engine::stagingEffects(self:Engine&,row:u32,source:u32)->blot_error::Error {let arrow,err=self.types.functionWithEffects(blot_check_types::unit,blot_check_types::unit,row);if err!=blot_error::Error.none {return err;}let opened,err=self.types.openCovariant(arrow);if err!=blot_error::Error.none {return err;}return self.constrainEffects(self.types.node(opened).c,self.ambient,source);}
fn Engine::invocation(self:Engine&,parameter:u32,result:u32)->u32,blot_error::Error {return self.types.functionWithEffects(parameter,result,self.ambient);}
fn Engine::invocationBinary(self:Engine&,left:u32,right:u32,result:u32)->u32,blot_error::Error {let inner,err=self.invocation(right,result);if err!=blot_error::Error.none {return 0,err;}return self.invocation(left,inner);}
fn Engine::pureExpression(self:Engine&,id:u32,required:u32)->u32,blot_error::Error {let saved=self.ambient;let ambient,err=self.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}self.ambient=ambient;let result,err=pureExpressionBody(self,id,required);self.ambient=saved;return result,err;}
fn pureExpressionBody(self:Engine&,id:u32,required:u32)->u32,blot_error::Error {var result:u32=0;if required!=0 {let value,err=self.contextualLambda(id,required);if err!=blot_error::Error.none {return 0,err;}result=value;}else {let value,err=self.expression(id);if err!=blot_error::Error.none {return 0,err;}result=value;}let err=self.types.unifyEffects(self.ambient,0);if err==blot_error::Error.effect_mismatch {let error=self.diagnostic(Code.let_effect,id);return result,error;}if err==blot_error::Error.infinite_effect {let error=self.diagnostic(Code.infinite_effect,id);return result,error;}return result,err;}
fn Engine::recordClosedRows(self:Engine&,owner:u32,rows:blot_check_types::List)->blot_error::Error {for variable in self.types.list(rows) {let key=ClosedRow{owner,variable};if !self.closed_row_keys.contains(key) {self.closed_row_keys.insert(key,true);self.body_closed_rows.append(key);}}return blot_error::Error.none;}
fn Engine::certifyLambda(self:Engine&,source:u32,raw_type:u32,parent_row:u32)->blot_error::Error {let result,err=self.certifiedLambdaType(source,raw_type,parent_row);return err;}
fn Engine::certifiedLambdaType(self:Engine&,source:u32,raw_type:u32,parent_row:u32)->u32,blot_error::Error {let resolved,err=self.types.resolve(raw_type,0);if err!=blot_error::Error.none {return 0,err;}let function=self.types.node(resolved);let tail=self.types.row(function.c).tail;var variable:u32=0;match tail {blot_check_effects::Tail.variable payload=>{variable=payload.value;},_=>{return raw_type,blot_error::Error.none;},}
    var protected:u32[>..<];let environment,err=self.environmentRows();if err!=blot_error::Error.none {return 0,err;}protected.append(environment);let parent,err=self.types.effects.freeVariables(parent_row);if err!=blot_error::Error.none {return 0,blot_check_types::effectError(err);}for variable in parent {if !inList(protected,variable) {protected.append(variable);}}
    for pending in self.pending[self.pending_start..] {if pending.solved || pending.owner!=self.current {continue;}for part in [pending.value.ty,pending.value.other,pending.value.result,pending.value.signature] {if part==0 {continue;}let free,err=self.types.freeRowVariables(part);if err!=blot_error::Error.none {return 0,err;}for variable in free {if !inList(protected,variable) {protected.append(variable);}}}}
    let root,err=self.types.resolve(raw_type,0);if err!=blot_error::Error.none {return 0,err;}let decision,err=self.types.closeCovariantCertified(root,[variable],protected);if err!=blot_error::Error.none {return 0,err;}if decision.closed_rows.len==0 {return decision.root,blot_error::Error.none;}self.row_sources.insert(variable,source);let err=self.recordClosedRows(self.current,decision.closed_rows);return decision.root,err;
}
fn Engine::addBinding(self:Engine&,value:Binding)->u32,blot_error::Error {if value.capability_parameters.inputInvokes() {self.has_input_invocations=true;}let id=self.bindings.len as u32;self.bindings.append(value);if self.tree.has_typed_staging && (value.kind==Kind.local || value.kind==Kind.parameter) {self.staging_bindings.insert(id,self.staging_depth);}return id,blot_error::Error.none;}
fn Engine::lookup(self:const Engine&,name:u32)->blot_support::Option<u32> {var index=self.env.len;while index!=0 {index-=1;if self.env[index].name==name {return blot_support::some(self.env[index].binding);}}return blot_support::none<u32>();}
fn inList(values:const u32[:],wanted:u32)->bool {for value in values {if value==wanted {return true;}}return false;}
fn Engine::catalogKey(self:const Engine&,name:u32)->Qualified {let qualified=self.qualifiedKey(name);if qualified.present {return qualified.value;}return Qualified{0,name};}
fn memberOperator(name:const u8[:])->blot_check_types::Operator {if name=="add" {return blot_check_types::Operator.add;}if name=="sub" {return blot_check_types::Operator.sub;}if name=="mul" {return blot_check_types::Operator.mul;}if name=="div" {return blot_check_types::Operator.div;}if name=="rem" {return blot_check_types::Operator.rem;}if name=="eq" {return blot_check_types::Operator.equal;}if name=="ne" {return blot_check_types::Operator.not_equal;}if name=="lt" {return blot_check_types::Operator.less;}if name=="le" {return blot_check_types::Operator.less_equal;}if name=="gt" {return blot_check_types::Operator.greater;}if name=="ge" {return blot_check_types::Operator.greater_equal;}if name=="bit_and" {return blot_check_types::Operator.bit_and;}if name=="bit_or" {return blot_check_types::Operator.bit_or;}if name=="bit_xor" {return blot_check_types::Operator.bit_xor;}if name=="shl" {return blot_check_types::Operator.shift_left;}if name=="shr" {return blot_check_types::Operator.shift_right;}return blot_check_types::Operator.none;}
fn symbolOperator(name:const u8[:])->blot_check_types::Operator {if name=="+" {return blot_check_types::Operator.add;}if name=="-" {return blot_check_types::Operator.sub;}if name=="*" {return blot_check_types::Operator.mul;}if name=="/" {return blot_check_types::Operator.div;}if name=="%" {return blot_check_types::Operator.rem;}if name=="==" {return blot_check_types::Operator.equal;}if name=="!=" {return blot_check_types::Operator.not_equal;}if name=="<" {return blot_check_types::Operator.less;}if name=="<=" {return blot_check_types::Operator.less_equal;}if name==">" {return blot_check_types::Operator.greater;}if name==">=" {return blot_check_types::Operator.greater_equal;}if name=="&" {return blot_check_types::Operator.bit_and;}if name=="|" {return blot_check_types::Operator.bit_or;}if name=="^" {return blot_check_types::Operator.bit_xor;}if name=="<<" {return blot_check_types::Operator.shift_left;}if name==">>" {return blot_check_types::Operator.shift_right;}return blot_check_types::Operator.none;}
fn Engine::identityOf(self:const Engine&,ty:u32)->blot_support::Option<Identity> {return blot_check_types::receiverIdentity(self.types.node(self.types.head(ty,0)));}
fn Engine::indexAssociated(self:Engine&)->blot_error::Error {
    for entry in self.imported_globals.slots {if entry.tag==0 {continue;}let text=self.pool.get(entry.key);let dot=lastDot(text);if !dot.present {continue;}let head=text[..dot.value];let name,present=self.pool.lookup(head);if !present {continue;}if self.builtin_catalog || self.catalogs.nominal_names.contains(Qualified{0,name}) {let binding,err=self.importedBinding(entry.val);if err!=blot_error::Error.none {return err;}if binding.present {self.catalogs.globals.insert(entry.key,binding.value);}}}
    for entry in self.catalogs.globals.slots {if entry.tag==0 {continue;}let text=self.pool.get(entry.key);let dot=lastDot(text);if !dot.present {continue;}let head=text[..dot.value];let member,present=self.pool.lookup(text[dot.value+1..]);if !present {continue;}var identity=blot_support::none<Identity>();let name,present=self.pool.lookup(head);if present {let index .= self.catalogs.nominal_names.get(Qualified{0,name});if index && self.nominals[index].alias==0 {identity=blot_support::some(self.nominals[index].identity);}}
        if !identity.present && self.builtin_catalog {if head=="U32" {identity=blot_support::some(Identity{0,blot_check_types::u32_type});}else if head=="F32" {identity=blot_support::some(Identity{0,blot_check_types::f32_type});}else if head=="Bool" {identity=blot_support::some(Identity{0,blot_check_types::boolean});}else if head=="Unit" {identity=blot_support::some(Identity{0,blot_check_types::unit});}else if head=="Array" {identity=blot_support::some(Identity{0,0xffffffff});}else if head=="List" {identity=blot_support::some(Identity{0,0xfffffffe});}else if head=="Cursor" {identity=blot_support::some(Identity{0,0xfffffffd});}else {let kind=blot_check_storage_types::named(head);if kind.present {identity=blot_support::some(Identity{0xffffffff,kind.value});}}}
        if identity.present {let owner=identity.value;if owner.unit!=0 && owner.unit!=self.unit && !(self.builtin_catalog && blot_check_storage_types::identity(owner.unit,owner.decl).present) {continue;}let operator=memberOperator(text[dot.value+1..]);let index=self.associated.len as u32;self.associated.append(Associated{owner,member,operator,entry.val});self.catalogs.associated_members.insert(AssociatedMember{owner,member},index);if operator!=blot_check_types::Operator.none {self.catalogs.associated_ops.insert(AssociatedKey{owner,operator},index);}}
    }return blot_error::Error.none;
}
enum AssociatedChoice {absent,waiting,selected {ty:u32,binding:u32}}
fn Engine::tryAssociated(self:Engine&,identity:Identity,member:u32,operator:blot_check_types::Operator,left:u32,right:u32,source:u32)->AssociatedChoice,blot_error::Error {var index:u32=0;if member==0 {let found .= self.catalogs.associated_ops.get(AssociatedKey{identity,operator});if !found {return AssociatedChoice.absent,blot_error::Error.none;}index=found;}else {let found .= self.catalogs.associated_members.get(AssociatedMember{identity,member});if !found {return AssociatedChoice.absent,blot_error::Error.none;}index=found;}let binding=self.associated[index].binding;let prepared,err=self.prepareSelectedGlobal(binding);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}if !prepared {return AssociatedChoice.waiting,blot_error::Error.none;}let point=self.types.mark();let pending=self.pending.len;self.mark_depth+=1;let choice,err=tryAssociatedBody(self,binding,left,right,source,point,pending);self.mark_depth-=1;return choice,err;}
fn tryAssociatedBody(self:Engine&,binding:u32,left:u32,right:u32,source:u32,point:blot_check_types::Mark,pending:i64)->AssociatedChoice,blot_error::Error {let function,err=self.instantiate(binding,source);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let result,err=self.types.fresh();if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let expected,err=self.invocationBinary(left,right,result);if err!=blot_error::Error.none {return AssociatedChoice.absent,err;}let err=self.types.unify(function,expected);if err!=blot_error::Error.none {if err==blot_error::Error.type_mismatch || err==blot_error::Error.infinite_type || err==blot_error::Error.effect_mismatch || err==blot_error::Error.infinite_effect {self.types.rollback(point);self.pending.resize(pending);return AssociatedChoice.absent,blot_error::Error.none;}return AssociatedChoice.absent,err;}self.dispatch_signatures[source]=expected;return AssociatedChoice.selected{result,binding},blot_error::Error.none;}
fn Engine::dispatch(self:Engine&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,source:u32,direct:bool)->blot_support::Option<u32>,blot_error::Error {let a,err=self.types.resolve(left,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let b,err=self.types.resolve(right,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let an=self.types.node(a);let bn=self.types.node(b);if an.tag==blot_check_types::Tag.variable || bn.tag==blot_check_types::Tag.variable {return blot_support::none<u32>(),blot_error::Error.none;}
    let identity=self.identityOf(a);if identity.present {let choice,err=self.tryAssociated(identity.value,member,operator,a,b,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}match choice {AssociatedChoice.absent=>{},AssociatedChoice.waiting=>{return blot_support::none<u32>(),blot_error::Error.none;},AssociatedChoice.selected value=>{if direct {self.resolved[source]=value.binding;}self.dispatch_side=blot_reuse_dispatch_explanation::Side.left;return blot_support::some(value.ty),blot_error::Error.none;},}}
    let scalar_a=an.tag==blot_check_types::Tag.unsigned32 || an.tag==blot_check_types::Tag.floating32 || an.tag==blot_check_types::Tag.boolean;let scalar_b=bn.tag==blot_check_types::Tag.unsigned32 || bn.tag==blot_check_types::Tag.floating32 || bn.tag==blot_check_types::Tag.boolean;
    if member==0 && scalar_a && scalar_b && an.tag==bn.tag {let comparison=operator==blot_check_types::Operator.equal || operator==blot_check_types::Operator.not_equal || operator==blot_check_types::Operator.less || operator==blot_check_types::Operator.less_equal || operator==blot_check_types::Operator.greater || operator==blot_check_types::Operator.greater_equal;let equality=operator==blot_check_types::Operator.equal || operator==blot_check_types::Operator.not_equal;let integer=operator==blot_check_types::Operator.rem || operator==blot_check_types::Operator.bit_and || operator==blot_check_types::Operator.bit_or || operator==blot_check_types::Operator.bit_xor || operator==blot_check_types::Operator.shift_left || operator==blot_check_types::Operator.shift_right;
        if (an.tag==blot_check_types::Tag.boolean && !equality) || (an.tag==blot_check_types::Tag.floating32 && integer) {let err=self.diagnostic(Code.ambiguous_operator,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self.explainDispatch(a,b,member,operator,true);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self.types.fresh();return blot_support::some(result),err;}self.dispatch_side=blot_reuse_dispatch_explanation::Side.builtin;if comparison {return blot_support::some(blot_check_types::boolean),blot_error::Error.none;}return blot_support::some(a),blot_error::Error.none;
    }
    let identity=self.identityOf(b);if identity.present {let choice,err=self.tryAssociated(identity.value,member,operator,a,b,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}match choice {AssociatedChoice.absent=>{},AssociatedChoice.waiting=>{return blot_support::none<u32>(),blot_error::Error.none;},AssociatedChoice.selected value=>{if direct {self.resolved[source]=value.binding;}self.dispatch_side=blot_reuse_dispatch_explanation::Side.right;return blot_support::some(value.ty),blot_error::Error.none;},}}
    if member!=0 {return blot_support::none<u32>(),blot_error::Error.none;}let err=self.diagnostic(Code.ambiguous_operator,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self.explainDispatch(a,b,member,operator,false);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let result,err=self.types.fresh();return blot_support::some(result),err;
}
fn Engine::sameOwner(self:Engine&,left:u32,right:u32)->bool,blot_error::Error {let left,err=self.types.resolve(left,0);if err!=blot_error::Error.none {return false,err;}let a=self.identityOf(left);if !a.present {return false,blot_error::Error.none;}let right,err=self.types.resolve(right,0);if err!=blot_error::Error.none {return false,err;}let b=self.identityOf(right);if !b.present {return false,blot_error::Error.none;}return a.value==b.value,blot_error::Error.none;}
fn Engine::spellType(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,ty:u32)->const u8[:],blot_error::Error {self.diagnostic_bytes.clear();let resolved,err=self.types.resolve(ty,0);if err!=blot_error::Error.none {return [],err;}let err=blot_reuse_type_display::append(self,self.diagnostic_bytes,resolved);if err!=blot_error::Error.none {return [],err;}return builder.own(self.diagnostic_bytes);}
fn Engine::spellStable(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,root:u32)->const u8[:],blot_error::Error {self.diagnostic_bytes.clear();let err=blot_reuse_type_display::appendStable(self,self.diagnostic_bytes,root);if err==blot_error::Error.out_of_memory {return [],err;}if err!=blot_error::Error.none {builder.truncated=true;}return builder.own(self.diagnostic_bytes);}
fn Engine::explainOperand(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,side:blot_reuse_dispatch_explanation::Side,ty:u32,member:u32,operator:blot_check_types::Operator)->blot_error::Error {let resolved,err=self.types.resolve(ty,0);if err!=blot_error::Error.none {return err;}var outcome=blot_reuse_dispatch_explanation::Outcome.no_member;if self.types.node(resolved).tag==blot_check_types::Tag.variable {outcome=blot_reuse_dispatch_explanation::Outcome.unknown_operand;}else {let identity=self.identityOf(resolved);if identity.present {var present=false;if member==0 {present=self.catalogs.associated_ops.contains(AssociatedKey{identity.value,operator});}else {present=self.catalogs.associated_members.contains(AssociatedMember{identity.value,member});}if present {outcome=blot_reuse_dispatch_explanation::Outcome.incompatible;}}}let operand,err=self.spellType(builder,resolved);if err!=blot_error::Error.none {return err;}builder.add(side,blot_support::some(operand),outcome);return blot_error::Error.none;}
fn Engine::attachExplanation(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,member:u32,operator:blot_check_types::Operator)->blot_error::Error {var spelled=blot_reuse_dispatch_explanation::operatorMember(operator);if member!=0 {spelled=blot_support::some(self.pool.get(member));}let explanation,err=builder.finish(blot_reuse_dispatch_explanation::operatorSymbol(operator),spelled);if err!=blot_error::Error.none {return err;}let issue .= self.diagnostics[self.diagnostics.len-1];if issue.explanation.present {issue.explanation.value.deinit();}issue.explanation=blot_support::some(explanation);return blot_error::Error.none;}
fn Engine::explainDispatch(self:Engine&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,scalar_rejected:bool)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{};let err=explainDispatchBody(self,builder,left,right,member,operator,scalar_rejected);builder.deinit();return err;}
fn explainDispatchBody(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,scalar_rejected:bool)->blot_error::Error {let err=self.explainOperand(builder,blot_reuse_dispatch_explanation::Side.left,left,member,operator);if err!=blot_error::Error.none {return err;}if scalar_rejected {builder.add(blot_reuse_dispatch_explanation::Side.builtin,blot_support::none<const u8[:]>(),blot_reuse_dispatch_explanation::Outcome.unsupported_scalar);}else {let same,err=self.sameOwner(left,right);if err!=blot_error::Error.none {return err;}if !same {let err=self.explainOperand(builder,blot_reuse_dispatch_explanation::Side.right,right,member,operator);if err!=blot_error::Error.none {return err;}}}return self.attachExplanation(builder,member,operator);}
fn Engine::explainSelected(self:Engine&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,side:blot_reuse_dispatch_explanation::Side)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{};let err=explainSelectedBody(self,builder,left,right,member,operator,side);builder.deinit();return err;}
fn explainSelectedBody(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,left:u32,right:u32,member:u32,operator:blot_check_types::Operator,side:blot_reuse_dispatch_explanation::Side)->blot_error::Error {if side==blot_reuse_dispatch_explanation::Side.right {let err=self.explainOperand(builder,blot_reuse_dispatch_explanation::Side.left,left,member,operator);if err!=blot_error::Error.none {return err;}}var ty=left;if side==blot_reuse_dispatch_explanation::Side.right {ty=right;}let spelled,err=self.spellType(builder,ty);if err!=blot_error::Error.none {return err;}builder.add(side,blot_support::some(spelled),blot_reuse_dispatch_explanation::Outcome.result_mismatch);return self.attachExplanation(builder,member,operator);}
fn Engine::explainResult(self:Engine&,destination:u32,member:u32)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{};var err=self.explainOperand(builder,blot_reuse_dispatch_explanation::Side.destination,destination,member,blot_check_types::Operator.none);if err==blot_error::Error.none {err=self.attachExplanation(builder,member,blot_check_types::Operator.none);}builder.deinit();return err;}
fn Engine::explainReceiver(self:Engine&,receiver:u32,member:u32)->blot_error::Error {var builder=blot_reuse_dispatch_explanation::Builder{};let spelling,err=self.spellType(builder,receiver);if err!=blot_error::Error.none {builder.deinit();return err;}builder.add(blot_reuse_dispatch_explanation::Side.receiver,blot_support::some(spelling),blot_reuse_dispatch_explanation::Outcome.no_member);let err=self.attachExplanation(builder,member,blot_check_types::Operator.none);builder.deinit();return err;}
fn Engine::resultDispatch(self:Engine&,input:u32,expected:u32,member:u32,source:u32,direct:bool)->blot_support::Option<u32>,blot_error::Error {let destination,err=self.types.resolve(expected,0);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let identity=self.identityOf(destination);if !identity.present {return blot_support::none<u32>(),blot_error::Error.none;}let index .= self.catalogs.associated_members.get(AssociatedMember{identity.value,member});if !index {return blot_support::none<u32>(),blot_error::Error.none;}let binding=self.associated[index].binding;let prepared,err=self.prepareSelectedGlobal(binding);if err!=blot_error::Error.none || !prepared {return blot_support::none<u32>(),err;}let function,err=self.instantiate(binding,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let expected_function,err=self.invocation(input,destination);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}let err=self.constrain(function,expected_function,source);if err!=blot_error::Error.none {return blot_support::none<u32>(),err;}self.dispatch_signatures[source]=expected_function;if direct {self.resolved[source]=binding;}return blot_support::some(destination),blot_error::Error.none;}
fn Engine::resolverDispatch(self:Engine&,pending:PendingObligation)->bool,blot_error::Error {let constraint=pending.value;let resolved,err=self.types.resolve(constraint.ty,0);if err!=blot_error::Error.none {return false,err;}let owner=self.types.node(resolved);if owner.tag==blot_check_types::Tag.variable {return false,blot_error::Error.none;}if owner.tag!=blot_check_types::Tag.resolver {let err=self.diagnostic(Code.invalid_provider,constraint.source);return true,err;}let resolved,err=self.types.resolve(owner.a,0);if err!=blot_error::Error.none {return false,err;}let token=self.types.node(resolved);if token.tag==blot_check_types::Tag.variable {return false,blot_error::Error.none;}if token.tag!=blot_check_types::Tag.type_constructor {let err=self.diagnostic(Code.type_constructor_required,constraint.source);return true,err;}let selected .= self.catalogs.associated_members.get(AssociatedMember{Identity{token.a,token.b},constraint.name});if !selected {return false,blot_error::Error.none;}let binding=self.associated[selected].binding;let prepared,err=self.prepareSelectedGlobal(binding);if err!=blot_error::Error.none || !prepared {return false,err;}let function,err=self.instantiate(binding,constraint.source);if err!=blot_error::Error.none {return false,err;}let err=self.constrain(function,constraint.other,constraint.source);if err!=blot_error::Error.none {return false,err;}if pending.metadata!=0 {self.resolver_ops[pending.metadata-1].method=binding;}return true,blot_error::Error.none;}
fn Engine::explainImplementation(self:Engine&,source:u32)->blot_error::Error {let trace=self.implementation_trace;if trace.contract.unit==0 || trace.request!=source {return blot_error::Error.none;}var builder=blot_reuse_dispatch_explanation::Builder{truncated:trace.truncated};let err=explainImplementationBody(self,builder,trace);builder.deinit();return err;}
fn explainImplementationBody(self:Engine&,builder:blot_reuse_dispatch_explanation::Builder&,trace:blot_eval_implementation_trace::Record)->blot_error::Error {
    for candidate in trace.candidates[..trace.len] {var declaration=blot_support::none<Implementation>();for known in self.implementations {if known.identity==candidate.identity {declaration=blot_support::some(known);break;}}if !declaration.present {continue;}let value=declaration.value;let path,path_error=self.purity_origins.name(value.identity.unit,self.unit);if path_error==blot_error::Error.out_of_memory {return path_error;}var owned_path=blot_support::none<const u8[:]>();if path_error==blot_error::Error.none {owned_path=blot_support::some(path);}var span=value.origin_span;if self.purity_origins.has_source_available {if !self.purity_origins.sourceAvailable(value.identity.unit) {span=blot_support::none<blot_parse_ast::Span>();}}else if value.identity.unit!=self.unit {span=blot_support::none<blot_parse_ast::Span>();}let origin,err=builder.makeOrigin(self.pool.get(value.name),owned_path,span);if err!=blot_error::Error.none {return err;}builder.addOrigin(blot_support::none<const u8[:]>(),candidate.outcome,origin);}
    for step in trace.steps[..trace.step_len] {var member=blot_support::none<const u8[:]>();if step.member!=0 {member=blot_support::some(self.pool.get(step.member));}let ty,err=self.spellStable(builder,step.ty);if err!=blot_error::Error.none {return err;}let err=builder.addStep(member,blot_support::some(ty),step.outcome);if err!=blot_error::Error.none {return err;}}
    let index .= self.catalogs.contract_identities.get(trace.contract);if !index {return blot_error::Error.none;}let contract=self.contracts[index];let result,err=builder.finish(blot_support::none<const u8[:]>(),blot_support::some(self.pool.get(contract.name)));if err!=blot_error::Error.none {return err;}let issue .= self.diagnostics[self.diagnostics.len-1];if issue.explanation.present {issue.explanation.value.deinit();}issue.explanation=blot_support::some(result);return blot_error::Error.none;
}
fn Engine::typeVariable(self:Engine&,name:u32,source:u32)->u32,blot_error::Error {for entry,index in self.row_env.items {if entry.name==name {var point=source;if index<self.inherited_rows {point=self.annotation_binding;}let err=self.diagnostic(Code.annotation_kind_mismatch,point);if err!=blot_error::Error.none {return 0,err;}return self.types.fresh();}}var index=self.type_env.items.len;while index!=0 {index-=1;if self.type_env.items[index].name==name {return self.type_env.items[index].ty,blot_error::Error.none;}}let ty,err=self.types.fresh();if err!=blot_error::Error.none {return 0,err;}if self.closed_type_variables {let err=self.diagnostic(Code.unsupported_type,source);return ty,err;}let growth=self.type_env.append(Engine_type_env{name,ty});return ty,growth;}
fn Engine::rowVariable(self:Engine&,name:u32,source:u32)->u32,blot_error::Error {var type_index=self.type_env.items.len;while type_index!=0 {type_index-=1;let entry=self.type_env.items[type_index];if entry.name!=name {continue;}let leaf=self.types.node(self.types.head(entry.ty,0));if (leaf.tag==blot_check_types::Tag.bound && leaf.b==1) || (leaf.tag==blot_check_types::Tag.rigid && leaf.c==1) {break;}var point=source;if type_index<self.inherited_types {point=self.annotation_binding;}let err=self.diagnostic(Code.annotation_kind_mismatch,point);if err!=blot_error::Error.none {return 0,err;}return self.types.freshEffects();}var index=self.row_env.items.len;while index!=0 {index-=1;if self.row_env.items[index].name==name {return self.row_env.items[index].row,blot_error::Error.none;}}let row,err=self.types.freshEffects();if err!=blot_error::Error.none {return 0,err;}if self.closed_type_variables && !self.implicit_row_parameters {let err=self.diagnostic(Code.invalid_effect_annotation,source);return row,err;}let growth=self.row_env.append(Engine_row_env{name,row});return row,growth;}
fn Engine::collectAnnotationNames(self:Engine&,id:u32,depth:i64)->blot_error::Error {if id==0 {return blot_error::Error.none;}if depth>=1024 {return blot_error::Error.type_limit;}let node=self.tree.node(id);match node.tag {
    blot_parse_ast::tag_let_stmt=>{if self.source_validation {let binding=self.tree.binding(id);for child in [binding.annotation,binding.where_node,binding.value,binding.fallback] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}}},
    blot_parse_ast::tag_type_name=>{let name=self.pool.get(node.a);if blot_check_storage_types::named(name).present {return blot_error::Error.none;}if name.len!=0 && ((name[0]>='a' as u8 && name[0]<='z' as u8) || name[0]=='_' as u8) && !firstDot(name).present {let ty,err=self.typeVariable(node.a,id);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_effect_row=>{if node.c!=0 {let row,err=self.rowVariable(self.tree.node(node.c).a,node.c);if err!=blot_error::Error.none {return err;}}for label in self.tree.list(blot_parse_ast::List{node.a,node.b}) {let err=self.collectEffectArgumentNames(label,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_where_clause=>{for child in self.tree.list(blot_parse_ast::List{node.a,node.b}) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_constraint=>{let details=self.tree.extra[node.c..node.c+3];let arguments=self.tree.list(blot_parse_ast::List{details[0],details[1]});var skip:i64=0;if self.pool.get(node.a)=="operation" && arguments.len!=0 {skip=1;}for child in arguments[skip..] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}let err=self.collectAnnotationNames(details[2],depth+1);if err!=blot_error::Error.none {return err;}},
    blot_parse_ast::tag_lambda=>{for child in [self.tree.parameter(node.a).annotation,node.c,node.b] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_group,blot_parse_ast::tag_type_witness,blot_parse_ast::tag_field_access,blot_parse_ast::tag_return_stmt,blot_parse_ast::tag_yield_stmt,blot_parse_ast::tag_forever_stmt=>{return self.collectAnnotationNames(node.a,depth+1);},
    blot_parse_ast::tag_field,blot_parse_ast::tag_unary,blot_parse_ast::tag_operator_tail,blot_parse_ast::tag_type_usage=>{return self.collectAnnotationNames(node.b,depth+1);},
    blot_parse_ast::tag_type_field,blot_parse_ast::tag_type_binder=>{if node.b==0 {let value,err=self.typeVariable(node.a,id);return err;}return self.collectAnnotationNames(node.b,depth+1);},
    blot_parse_ast::tag_apply,blot_parse_ast::tag_index_access,blot_parse_ast::tag_rebind_stmt,blot_parse_ast::tag_type_apply,blot_parse_ast::tag_type_effect=>{for child in [node.a,node.b] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_binary=>{for child in [node.b,node.c] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_type_function,blot_parse_ast::tag_if_expr,blot_parse_ast::tag_if_stmt,blot_parse_ast::tag_range_stmt=>{for child in [node.a,node.b,node.c] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_use_stmt,blot_parse_ast::tag_iterator_bind=>{for child in [node.c,node.b] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_product,blot_parse_ast::tag_array,blot_parse_ast::tag_record,blot_parse_ast::tag_type_product,blot_parse_ast::tag_type_array,blot_parse_ast::tag_type_record=>{for child in self.tree.children(id) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_block=>{let err=self.collectAnnotationNames(node.c,depth+1);if err!=blot_error::Error.none {return err;}for child in self.tree.children(id) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_infix_chain=>{let err=self.collectAnnotationNames(node.a,depth+1);if err!=blot_error::Error.none {return err;}for child in self.tree.list(blot_parse_ast::List{node.b,node.c}) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_if_let_stmt,blot_parse_ast::tag_for_stmt=>{let err=self.collectAnnotationNames(node.b,depth+1);if err!=blot_error::Error.none {return err;}let metadata=self.tree.extra[node.c..];for child in metadata[..2] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_case_expr,blot_parse_ast::tag_request_case=>{let inputs=self.tree.extra[node.a..node.a+2];for child in self.tree.list(blot_parse_ast::List{inputs[0],inputs[1]}) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}for child in self.tree.list(blot_parse_ast::List{node.b,node.c}) {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_case_arm=>{for child in self.tree.extra[node.c..node.c+2] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_request_arm=>{for child in [node.a,node.c] {let err=self.collectAnnotationNames(child,depth+1);if err!=blot_error::Error.none {return err;}}},_=>{},
    }return blot_error::Error.none;
}
fn Engine::collectEffectArgumentNames(self:Engine&,id:u32,depth:i64)->blot_error::Error {if depth>=1024 {return blot_error::Error.type_limit;}let node=self.tree.node(id);if node.tag==blot_parse_ast::tag_type_apply {let err=self.collectEffectArgumentNames(node.a,depth+1);if err!=blot_error::Error.none {return err;}return self.collectAnnotationNames(node.b,depth+1);}return blot_error::Error.none;}
fn Engine::nominalIndex(self:const Engine&,identity:Identity)->blot_support::Option<u32> {let value .= self.catalogs.nominal_identities.get(identity);if value {return blot_support::some(value);}return blot_support::none<u32>();}
fn Engine::copyNominal(self:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {var source=producer.nominals[source_index];if source.is_opaque && self.producer_storage.present {let storage=self.producer_storage.value.lookup(source.identity);if storage.present {source.storage=storage.value;}}let known=self.nominalIndex(source.identity);if known.present {return known.value,blot_error::Error.none;}var copier=blot_check_check_scheme_import::init(producer.types,self.types,self.import_tables);let result,err=copyNominalBody(self,copier,producer,source);copier.deinit();return result,err;}
fn copyNominalBody(self:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Nominal)->u32,blot_error::Error {
    var variables:u32[>..<];for old in producer.types.list(source.variables) {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.append(fresh);}var parameters:u32[>..<];for old in producer.types.list(source.parameters) {let parameter,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.append(parameter);}
    let index=self.nominals.len as u32;let quantified,err=self.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let names,err=self.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let patterns,err=self.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let alias_rows,err=copier.quantifiedRows(source.alias_rows);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}var alias:u32=0;if source.alias!=0 {let value,err=copier.copy(source.alias,0);if err!=blot_error::Error.none {return 0,err;}alias=value;}
    self.nominals.append(Nominal{affine:source.affine,has_usage:source.has_usage,closed_storage:source.closed_storage,private:source.private,is_opaque:source.is_opaque,storage:source.storage,identity:source.identity,name:source.name,variables:quantified,parameters:parameter_list,patterns:patterns,parameter_names:names,alias_rows:alias_rows,alias:alias});if source.has_usage {self.types.has_usage_types=true;}self.catalogs.nominal_identities.insert(source.identity,index);
    var constructors:u32[>..<];for old in producer.types.list(source.constructors) {if source.is_opaque {continue;}let ctor=producer.constructors[old];let own=self.constructors.len as u32;let root,err=copier.copy(ctor.scheme.root,0);if err!=blot_error::Error.none {return 0,err;}var payload:u32=0;if ctor.payload!=0 {let value,err=copier.copy(ctor.payload,0);if err!=blot_error::Error.none {return 0,err;}payload=value;}self.constructors.append(Constructor{identity:ctor.identity,nominal:index,tag:ctor.tag,name:ctor.name,scheme:blot_check_types::Scheme{root:root,variables:quantified},payload:payload,declared_record:ctor.declared_record});self.catalogs.constructor_identities.insert(ctor.identity,own);constructors.append(own);}
    let catalog,err=self.types.saveList(constructors);if err!=blot_error::Error.none {return 0,err;}self.nominals[index].constructors=catalog;return index,blot_error::Error.none;
}
fn Engine::copyEffectFamily(self:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.effect_families[source_index];let known .= self.catalogs.effect_family_identities.get(source.identity);if known {return known,blot_error::Error.none;}var copier=blot_check_check_scheme_import::init(producer.types,self.types,self.import_tables);let family,err=copyEffectFamilyBody(self,copier,producer,source);copier.deinit();return family,err;}
fn copyEffectFamilyBody(self:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:EffectFamily)->u32,blot_error::Error {
    var variables:u32[>..<];for old in producer.types.list(source.variables) {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.append(fresh);}var parameters:u32[>..<];for old in producer.types.list(source.parameters) {let copied,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.append(copied);}if self.effect_families.len==0xffffffff {return 0,blot_error::Error.type_limit;}let family=self.effect_families.len as u32;let patterns,err=self.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}let names,err=self.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}
    self.effect_families.append(EffectFamily{private:source.private,identity:source.identity,name:source.name,callable:source.callable,variables:quantified,parameters:parameter_list,patterns:patterns,parameter_names:names});self.catalogs.effect_family_identities.insert(source.identity,family);
    var operations:u32[>..<];for old in producer.types.list(source.operations) {let template=producer.effect_templates[old];if self.effect_templates.len==0xffffffff {return 0,blot_error::Error.type_limit;}let index=self.effect_templates.len as u32;let parameter,err=copier.copy(template.parameter,0);if err!=blot_error::Error.none {return 0,err;}let result,err=copier.copy(template.result,0);if err!=blot_error::Error.none {return 0,err;}self.effect_templates.append(EffectTemplate{template.identity,family,template.name,parameter,result});self.catalogs.effect_members.insert(EffectMember{family,template.name},index);self.catalogs.effect_template_identities.insert(template.identity,index);operations.append(index);}let catalog,err=self.types.saveList(operations);if err!=blot_error::Error.none {return 0,err;}self.effect_families[family].operations=catalog;return family,blot_error::Error.none;
}
fn SourceCatalog::catalog(self:SourceCatalog)->DeclarationCatalog {return self.producer;}
fn SourceCatalog::declaration(self:SourceCatalog,id:u32)->SourceDeclaration {return self.declarations[id];}
fn Engine::importAssociatedHeader(self:Engine&,definition:SourceDeclaration,target:ExternalTarget,origin:u32,owned:blot_support::Option<ProducerCapability>)->blot_error::Error {var flow=definition.capability_flow;var parameters=definition.capability_parameters;if owned.present {flow=owned.value.flow;parameters=owned.value.parameters;}return self.importHeader(SourceHeader{target:target,capability_flow:flow,capability_parameters:parameters,named_function:definition.named_function,origin:origin,expose:false});}
fn SourceCatalog::importMethod(self:SourceCatalog,engine:Engine&,definition:SourceDeclaration,target:ExternalTarget,owned:blot_support::Option<ProducerCapability>,binding:u32)->blot_error::Error {return engine.importAssociatedHeader(definition,target,self.origin,owned);}
fn ImportedCatalog::importMethod(self:ImportedCatalog,engine:Engine&,definition:SourceDeclaration,target:ExternalTarget,owned:blot_support::Option<ProducerCapability>,binding:u32)->blot_error::Error {if engine.source_validation {return engine.importAssociatedHeader(definition,target,self.origin,owned);}var interface=self.interface(binding);if owned.present {let facts=owned.value;interface.capability_flow=facts.flow;interface.capability_parameters=facts.parameters;if facts.recipe.present {interface.capability_source=facts.recipe;}else {interface.capability_source=blot_support::some(CapabilitySource{Callees.none,0});}}return engine.importBinding(ImportedBinding{target:target,interface:interface,origin:self.origin,expose:false});}
fn Engine::importCatalog(self:Engine&,imported)->blot_error::Error {
    let producer=imported.catalog();if imported.kind==ImportedCatalog_kind.catalog {
        for index in 1..producer.nominals.len {if producer.nominals[index].private {continue;}let copied,err=self.copyNominal(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for index in 1..producer.effect_families.len {if producer.effect_families[index].private {continue;}let copied,err=self.copyEffectFamily(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for index in 0..producer.contracts.len {if producer.contracts[index].private {continue;}let copied,err=self.copyContract(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for implementation,index in producer.implementations {if implementation.private {continue;}let copied,err=self.copyImplementation(producer,index as u32);if err!=blot_error::Error.none {return err;}}
        for method in producer.associated {let definition=imported.declaration(method.binding);if definition.private {continue;}var target=ExternalTarget{producer.unit,method.binding};if definition.external.present {target=definition.external.value;}var owned=blot_support::none<ProducerCapability>();if definition.external.present {owned=self.producerCapability(target);}let err=imported.importMethod(self,definition,target,owned,method.binding);if err!=blot_error::Error.none {return err;}let binding,err=self.importedBinding(target);if err!=blot_error::Error.none {return err;}assert(binding.present);var present=false;for prior in self.associated {if prior.identity.unit==method.identity.unit && prior.identity.decl==method.identity.decl && prior.member==method.member && prior.binding==binding.value {present=true;break;}}
            if !present {let index=self.associated.len as u32;self.associated.append(Associated{method.identity,method.member,method.operator,binding.value});self.catalogs.associated_members.insert(AssociatedMember{method.identity,method.member},index);if method.operator!=blot_check_types::Operator.none {self.catalogs.associated_ops.insert(AssociatedKey{method.identity,method.operator},index);}}
        }return blot_error::Error.none;
    }
    if imported.kind==ImportedCatalog_kind.effect_family {let family,err=self.copyEffectFamily(producer,imported.index);if err!=blot_error::Error.none {return err;}let key=Qualified{imported.namespace,imported.name};if self.catalogs.effect_family_names.contains(key) || self.catalogs.nominal_names.contains(key) {let err=self.diagnostic(Code.duplicate_name,imported.origin);if err!=blot_error::Error.none {return err;}}else {self.catalogs.effect_family_names.insert(key,family);}if self.effect_families[family].callable {let operations=self.types.list(self.effect_families[family].operations);if operations.len!=1 {return blot_error::Error.type_limit;}self.catalogs.effect_operation_names.insert(key,operations[0]);}return blot_error::Error.none;}
    let key=Qualified{imported.namespace,imported.name};if imported.kind==ImportedCatalog_kind.contract {let index,err=self.copyContract(producer,imported.index);if err!=blot_error::Error.none {return err;}if self.catalogs.contract_names.contains(key) || self.catalogs.nominal_names.contains(key) {return self.diagnostic(Code.duplicate_name,imported.origin);}self.catalogs.contract_names.insert(key,index);return blot_error::Error.none;}
    if imported.kind==ImportedCatalog_kind.implementation {let index,err=self.copyImplementation(producer,imported.index);if err!=blot_error::Error.none {return err;}if self.catalogs.implementation_names.contains(key) {return self.diagnostic(Code.duplicate_name,imported.origin);}self.catalogs.implementation_names.insert(key,index);return blot_error::Error.none;}
    if imported.kind==ImportedCatalog_kind.nominal {let index,err=self.copyNominal(producer,imported.index);if err!=blot_error::Error.none {return err;}if self.catalogs.nominal_names.contains(key) {return self.diagnostic(Code.duplicate_name,imported.origin);}self.catalogs.nominal_names.insert(key,index);}
    else {let source=producer.constructors[imported.index];let copied,err=self.copyNominal(producer,source.nominal);if err!=blot_error::Error.none {return err;}let index .= self.catalogs.constructor_identities.get(source.identity);assert(index!=null);if self.catalogs.constructor_names.contains(key) {return self.diagnostic(Code.duplicate_name,imported.origin);}self.catalogs.constructor_names.insert(key,index);}return blot_error::Error.none;
}
fn Engine::prepareOpaqueStorage(self:Engine&) {var remaining:i64=1000000;for nominal,index in self.nominals {if !nominal.is_opaque || nominal.identity.unit!=self.unit {continue;}self.nominals[index].storage=blot_backend_opaque_storage::infer(blot_check_frozen_types::Source.store{self.types},self.nominals,self.constructors,index as u32,remaining);}}
fn Engine::constructorDiagnostic(self:Engine&,symbol:u32,source:u32)->blot_error::Error {let index .= self.catalogs.nominal_names.get(self.catalogKey(symbol));if index && self.nominals[index].is_opaque && self.nominals[index].identity.unit!=self.unit {return self.diagnostic(Code.private_access,source);}return self.diagnostic(Code.unknown_constructor,source);}
fn Engine::constructorType(self:Engine&,index:u32)->u32,blot_error::Error {return self.constructorUse(index,false);}
struct VisibilityContext {engine:Engine&}
fn Engine::validateVisibility(self:Engine&)->blot_error::Error {var private=false;for binding in self.bindings {private=private || binding.private;}for nominal in self.nominals {private=private || nominal.private;}for family in self.effect_families {private=private || family.private;}for contract in self.contracts {private=private || contract.private;}if !private {return blot_error::Error.none;}var context=VisibilityContext{self};return blot_reuse_module_visibility::withScan<VisibilityContext,visibilityBody>(blot_check_frozen_types::Source.store{self.types},self.nominals,self.effect_families,self.effect_templates,context);}
fn visibilityBody(context:VisibilityContext&,scan:blot_reuse_module_visibility::Scan&)->blot_error::Error {
    let self .= context.engine;for contract in self.contracts {if contract.private {scan.blocked.insert(contract.identity,true);}}
    for binding in self.bindings {if binding.kind!=Kind.global || binding.private {continue;}var allowed,err=scan.allowed(binding.scheme.root);if err!=blot_error::Error.none {return err;}if self.tree.node(binding.declaration).tag!=blot_parse_ast::tag_value_decl {continue;}for predicate in self.tree.list(self.tree.value_decl(binding.declaration).where) {let name=self.tree.node(predicate).a;let index .= self.catalogs.contract_names.get(self.catalogKey(name));if index && self.contracts[index].private {allowed=false;}}
        for requirement in self.obligations[binding.scheme.obligations.start..binding.scheme.obligations.start+binding.scheme.obligations.len] {if requirement.kind==blot_check_types::ObligationKind.callee_use && requirement.identity.decl<self.bindings.len && self.bindings[requirement.identity.decl].private {allowed=false;}for root in [requirement.ty,requirement.result,requirement.other,requirement.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}if !allowed {let err=self.diagnostic(Code.private_identity_escape,binding.declaration);if err!=blot_error::Error.none {return err;}}
    }
    for nominal in self.nominals {if nominal.identity.unit!=self.unit || nominal.private {continue;}var allowed,err=scan.allowed(nominal.alias);if err!=blot_error::Error.none {return err;}for parameter in self.types.list(nominal.parameters) {let valid,err=scan.allowed(parameter);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}if nominal.is_opaque {if !allowed {let err=self.diagnostic(Code.private_identity_escape,nominal.declaration);if err!=blot_error::Error.none {return err;}}continue;}for index in self.types.list(nominal.constructors) {let valid,err=scan.allowed(self.constructors[index].payload);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}if !allowed {let err=self.diagnostic(Code.private_identity_escape,nominal.declaration);if err!=blot_error::Error.none {return err;}}}
    for contract in self.contracts {if contract.identity.unit!=self.unit || contract.private {continue;}var allowed=true;for requirement in self.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {for root in [requirement.ty,requirement.result,requirement.other,requirement.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}for member in self.contract_members[contract.members.start..contract.members.start+contract.members.len] {let valid,err=scan.allowed(member.root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}let body=self.tree.node(self.tree.node(contract.declaration).b);for predicate in self.tree.list(blot_parse_ast::List{body.a,body.b}) {let index .= self.catalogs.contract_names.get(self.catalogKey(self.tree.node(predicate).a));if index && self.contracts[index].private {allowed=false;}}if !allowed {let err=self.diagnostic(Code.private_identity_escape,contract.declaration);if err!=blot_error::Error.none {return err;}}}
    for implementation in self.implementations {if implementation.identity.unit!=self.unit || implementation.private {continue;}var allowed=!scan.blocked.contains(implementation.contract);for root in self.types.list(implementation.head) {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}for member in self.implementation_members[implementation.members.start..implementation.members.start+implementation.members.len] {let valid,err=scan.allowed(member.root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}for predicate in self.implementation_predicates[implementation.predicates.start..implementation.predicates.start+implementation.predicates.len] {if scan.blocked.contains(predicate.identity) {allowed=false;}for root in [predicate.ty,predicate.other,predicate.result,predicate.signature] {let valid,err=scan.allowed(root);if err!=blot_error::Error.none {return err;}if !valid {allowed=false;}}}if !allowed {let err=self.diagnostic(Code.private_identity_escape,implementation.declaration);if err!=blot_error::Error.none {return err;}}}
    for family in self.effect_families {if family.identity.unit!=self.unit || family.private {continue;}var allowed=true;for index in self.types.list(family.operations) {let operation=self.effect_templates[index];let parameter,err=scan.allowed(operation.parameter);if err!=blot_error::Error.none {return err;}if !parameter {allowed=false;}else {let result,err=scan.allowed(operation.result);if err!=blot_error::Error.none {return err;}if !result {allowed=false;}}}if !allowed {let err=self.diagnostic(Code.private_identity_escape,family.identity.decl);if err!=blot_error::Error.none {return err;}}}
    return blot_error::Error.none;
}
fn copyPredicate(copier:blot_check_check_scheme_import::Copier&,old:blot_check_types::Obligation)->blot_check_types::Obligation,blot_error::Error {var value=old;let ty,err=copier.copy(old.ty,0);if err!=blot_error::Error.none {return value,err;}value.ty=ty;let other,err=copier.copy(old.other,0);if err!=blot_error::Error.none {return value,err;}value.other=other;let result,err=copier.copy(old.result,0);if err!=blot_error::Error.none {return value,err;}value.result=result;let signature,err=copier.copy(old.signature,0);if err!=blot_error::Error.none {return value,err;}value.signature=signature;value.source=0;return value,blot_error::Error.none;}
fn Engine::copyContract(self:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.contracts[source_index];self.has_associated_types=self.has_associated_types || source.members.len!=0;let known .= self.catalogs.contract_identities.get(source.identity);if known {return known,blot_error::Error.none;}var copier=blot_check_check_scheme_import::init(producer.types,self.types,self.import_tables);copier.associated=source.members.len!=0;let result,err=copyContractBody(self,copier,producer,source);copier.deinit();return result,err;}
fn copyContractBody(self:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Contract)->u32,blot_error::Error {
    var variables:u32[>..<];for old in producer.types.list(source.variables) {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.append(fresh);}let rows,err=copier.quantifiedRows(source.row_variables);if err!=blot_error::Error.none {return 0,err;}var parameters:u32[>..<];for old in producer.types.list(source.parameters) {let copied,err=copier.copy(old,0);if err!=blot_error::Error.none {return 0,err;}parameters.append(copied);}let start=self.contract_predicates.len as u32;for old in producer.contract_predicates[source.predicates.start..source.predicates.start+source.predicates.len] {let predicate,err=copyPredicate(copier,old);if err!=blot_error::Error.none {return 0,err;}self.contract_predicates.append(predicate);}
    var row_parameters:u32[>..<];for old in producer.types.list(source.row_parameters) {let copied,err=copier.copyRow(old,0);if err!=blot_error::Error.none {return 0,err;}row_parameters.append(copied);}let member_start=self.contract_members.len as u32;for old in producer.contract_members[source.members.start..source.members.start+source.members.len] {var member=old;let root,err=copier.copy(old.root,0);if err!=blot_error::Error.none {return 0,err;}member.root=root;self.contract_members.append(member);}
    let index=self.contracts.len as u32;let patterns,err=self.copyParameterPatterns(producer.parameter_patterns,source.patterns,copier);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let parameter_list,err=self.types.saveList(parameters);if err!=blot_error::Error.none {return 0,err;}let names,err=self.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_names,err=self.types.saveList(producer.types.list(source.row_parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_list,err=self.types.saveList(row_parameters);if err!=blot_error::Error.none {return 0,err;}
    self.contracts.append(Contract{private:source.private,identity:source.identity,name:source.name,variables:quantified,parameters:parameter_list,patterns:patterns,parameter_names:names,row_variables:rows,predicates:blot_check_types::List{start,source.predicates.len},members:blot_check_types::List{member_start,source.members.len},requires_implementation:source.requires_implementation,row_parameter_names:row_names,row_parameters:row_list});self.catalogs.contract_identities.insert(source.identity,index);return index,blot_error::Error.none;
}
fn Engine::copyImplementation(self:Engine&,producer:DeclarationCatalog,source_index:u32)->u32,blot_error::Error {let source=producer.implementations[source_index];for prior,index in self.implementations {if prior.identity==source.identity {return index as u32,blot_error::Error.none;}}if self.implementations.len>=4096 {return 0,blot_error::Error.type_limit;}for contract,index in producer.contracts {if contract.identity==source.contract {let copied,err=self.copyContract(producer,index as u32);if err!=blot_error::Error.none {return 0,err;}break;}}var copier=blot_check_check_scheme_import::init(producer.types,self.types,self.import_tables);copier.associated=true;let result,err=copyImplementationBody(self,copier,producer,source);copier.deinit();return result,err;}
fn copyImplementationBody(self:Engine&,copier:blot_check_check_scheme_import::Copier&,producer:DeclarationCatalog,source:Implementation)->u32,blot_error::Error {
    var variables:u32[>..<];for old in producer.types.list(source.variables) {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return 0,err;}copier.mapping.insert(producer.types.head(old,0),fresh);variables.append(fresh);}let rows,err=copier.quantifiedRows(source.row_variables);if err!=blot_error::Error.none {return 0,err;}var head:u32[>..<];for root in producer.types.list(source.head) {let copied,err=copier.copy(root,0);if err!=blot_error::Error.none {return 0,err;}head.append(copied);}var row_parameters:u32[>..<];for row in producer.types.list(source.row_parameters) {let copied,err=copier.copyRow(row,0);if err!=blot_error::Error.none {return 0,err;}row_parameters.append(copied);}let predicate_start=self.implementation_predicates.len as u32;
    for old in producer.implementation_predicates[source.predicates.start..source.predicates.start+source.predicates.len] {let predicate,err=copyPredicate(copier,old);if err!=blot_error::Error.none {return 0,err;}self.implementation_predicates.append(predicate);}let member_start=self.implementation_members.len as u32;for old in producer.implementation_members[source.members.start..source.members.start+source.members.len] {var value=old;let root,err=copier.copy(old.root,0);if err!=blot_error::Error.none {return 0,err;}value.root=root;self.implementation_members.append(value);}
    let index=self.implementations.len as u32;let head_list,err=self.types.saveList(head);if err!=blot_error::Error.none {return 0,err;}let quantified,err=self.types.saveList(variables);if err!=blot_error::Error.none {return 0,err;}let names,err=self.types.saveList(producer.types.list(source.parameter_names));if err!=blot_error::Error.none {return 0,err;}let row_list,err=self.types.saveList(row_parameters);if err!=blot_error::Error.none {return 0,err;}let row_names,err=self.types.saveList(producer.types.list(source.row_parameter_names));if err!=blot_error::Error.none {return 0,err;}
    self.implementations.append(Implementation{origin_span:source.origin_span,private:source.private,identity:source.identity,name:source.name,contract:source.contract,head:head_list,variables:quantified,parameter_names:names,row_variables:rows,row_parameters:row_list,row_parameter_names:row_names,predicates:blot_check_types::List{predicate_start,source.predicates.len},members:blot_check_types::List{member_start,source.members.len}});return index,blot_error::Error.none;
}
fn Engine::implementationRowNames(self:Engine&,id:u32,names:u32[>..<]&,depth:i64)->blot_error::Error {if id==0 {return blot_error::Error.none;}if depth>=256 {return blot_error::Error.type_limit;}let allowed,err=self.associatedStep(id);if err!=blot_error::Error.none || !allowed {return err;}let node=self.tree.node(id);match node.tag {
    blot_parse_ast::tag_type_function,blot_parse_ast::tag_type_effect=>{let err=self.implementationRowNames(node.a,names,depth+1);if err!=blot_error::Error.none {return err;}let err=self.implementationRowNames(node.b,names,depth+1);if err!=blot_error::Error.none {return err;}if node.tag==blot_parse_ast::tag_type_function {return self.implementationRowNames(node.c,names,depth+1);}},
    blot_parse_ast::tag_type_apply=>{let err=self.implementationRowNames(node.a,names,depth+1);if err!=blot_error::Error.none {return err;}return self.implementationRowNames(node.b,names,depth+1);},
    blot_parse_ast::tag_group=>{return self.implementationRowNames(node.a,names,depth+1);},
    blot_parse_ast::tag_type_product,blot_parse_ast::tag_type_array,blot_parse_ast::tag_type_record=>{for child in self.tree.children(id) {let err=self.implementationRowNames(child,names,depth+1);if err!=blot_error::Error.none {return err;}}},
    blot_parse_ast::tag_type_field=>{return self.implementationRowNames(node.b,names,depth+1);},
    blot_parse_ast::tag_effect_row=>{if node.c!=0 {let name=self.tree.node(node.c).a;if !inList(names,name) {names.append(name);}}for label in self.tree.list(blot_parse_ast::List{node.a,node.b}) {let err=self.implementationRowNames(label,names,depth+1);if err!=blot_error::Error.none {return err;}}},_=>{},
    }return blot_error::Error.none;
}
fn Engine::implementationScope(self:Engine&,declaration:Implementation)->blot_error::Error {let variables=self.types.list(declaration.variables);for name,index in self.types.list(declaration.parameter_names) {let growth=self.type_env.append(Engine_type_env{name,variables[index]});if growth!=blot_error::Error.none {return growth;}}let rows=self.types.list(declaration.row_parameters);for name,index in self.types.list(declaration.row_parameter_names) {let growth=self.row_env.append(Engine_row_env{name,rows[index]});if growth!=blot_error::Error.none {return growth;}}return blot_error::Error.none;}
fn Engine::implementationHeaders(self:Engine&)->blot_error::Error {let saved=self.defer_associated;self.defer_associated=true;let err=implementationHeadersBody(self);self.defer_associated=saved;return err;}
fn implementationHeadersBody(self:Engine&)->blot_error::Error {
    for id in self.tree.roots {if self.tree.node(id).tag!=blot_parse_ast::tag_implementation_decl {continue;}let allowed,err=self.associatedStep(id);if err!=blot_error::Error.none || !allowed {return err;}if self.implementations.len>=4096 {return self.diagnostic(Code.associated_limit,id);}let err=implementationHeader(self,id);if err!=blot_error::Error.none {return err;}}
    self.type_env.clear();self.row_env.clear();return blot_error::Error.none;
}
fn implementationHeader(self:Engine&,id:u32)->blot_error::Error {
    let syntax=self.tree.implementation(id);let key=Qualified{0,syntax.name};var duplicate=self.hasGlobal(syntax.name) || self.catalogs.nominal_names.contains(key) || self.catalogs.contract_names.contains(key) || self.catalogs.implementation_names.contains(key);for prior in self.implementations {if prior.identity.unit==self.unit && prior.name==syntax.name {duplicate=true;}}if duplicate {return self.diagnostic(Code.duplicate_name,id);}let predicate=self.tree.node(syntax.head);let contract_index .= self.catalogs.contract_names.get(self.catalogKey(predicate.a));if !contract_index {return self.diagnostic(Code.unknown_name,syntax.head);}let contract=self.contracts[contract_index];if !contract.requires_implementation {return self.diagnostic(Code.invalid_constraint,id);}
    self.type_env.clear();self.row_env.clear();for parameter in self.tree.list(syntax.parameters) {let annotation,err=self.parameterAnnotation(parameter,0);if err!=blot_error::Error.none {return err;}}let details=self.tree.extra[predicate.c..predicate.c+3];let arguments=self.tree.list(blot_parse_ast::List{details[0],details[1]});if predicate.b!=0 || details[2]!=0 || arguments.len!=contract.parameters.len {return self.diagnostic(Code.associated_arity,syntax.head);}
    var row_names:u32[>..<];for argument in arguments {let err=self.implementationRowNames(argument,row_names,0);if err!=blot_error::Error.none {return err;}}var at:i64=0;while at<self.type_env.items.len {let entry=self.type_env.items[at];if !inList(row_names,entry.name) {at+=1;continue;}for index in at+1..self.type_env.items.len {self.type_env.items[index-1]=self.type_env.items[index];}self.type_env.resize(self.type_env.items.len-1);let row,err=self.types.freshEffects();if err!=blot_error::Error.none {return err;}let growth=self.row_env.append(Engine_row_env{entry.name,row});if growth!=blot_error::Error.none {return growth;}}
    var variables:u32[>..<];var names:u32[>..<];var row_parameters:u32[>..<];var declared_row_names:u32[>..<];for entry in self.type_env.items {variables.append(entry.ty);names.append(entry.name);}for entry in self.row_env.items {row_parameters.append(entry.row);declared_row_names.append(entry.name);}
    let saved_closed=self.closed_type_variables;let saved_implicit=self.implicit_row_parameters;let saved_defer=self.defer_associated;self.closed_type_variables=true;self.implicit_row_parameters=false;self.defer_associated=true;
    let err=implementationHeaderOwned(self,id,syntax,contract,arguments,variables,names,row_parameters,declared_row_names);self.closed_type_variables=saved_closed;self.implicit_row_parameters=saved_implicit;self.defer_associated=saved_defer;return err;
}
fn implementationHeaderOwned(self:Engine&,id:u32,syntax:blot_parse_ast::ImplementationDecl,contract:Contract,arguments:const u32[:],variables:u32[>..<]&,names:const u32[:],row_parameters:const u32[:],declared_row_names:const u32[:])->blot_error::Error {
    var head:u32[>..<];var contract_old:u32[>..<];contract_old.append(self.types.list(contract.variables));var contract_fresh:u32[>..<];for ignored in 0..contract_old.len {let fresh,err=self.types.fresh();if err!=blot_error::Error.none {return err;}contract_fresh.append(fresh);}var old_rows:u32[>..<];old_rows.append(self.types.list(contract.row_variables));var new_rows:u32[>..<];for ignored in 0..old_rows.len {let fresh,err=self.types.freshEffects();if err!=blot_error::Error.none {return err;}new_rows.append(fresh);}
    for argument,ordinal in arguments {let actual,err=self.parameterArgument(self.parameter_patterns.list(contract.patterns)[ordinal],argument,true,0);if err!=blot_error::Error.none {return err;}let projection,err=self.types.containsProjection(actual);if err!=blot_error::Error.none {return err;}if projection {let err=self.diagnostic(Code.invalid_constraint,argument);if err!=blot_error::Error.none {return err;}}let expected,err=self.types.substituteWithRows(self.types.list(contract.parameters)[ordinal],contract_old,contract_fresh,old_rows,new_rows);if err!=blot_error::Error.none {return err;}let err=self.constrainRaw(expected,actual,argument);if err!=blot_error::Error.none {return err;}head.append(actual);}
    let product,err=self.types.product(head);if err!=blot_error::Error.none {return err;}let free,err=self.types.freeVariables(product);if err!=blot_error::Error.none {return err;}let rows,err=self.types.freeRowVariables(product);if err!=blot_error::Error.none {return err;}for &variable in variables {variable=self.types.head(variable,0);if !inList(free,variable) {let err=self.diagnostic(Code.undetermined_implementation,id);if err!=blot_error::Error.none {return err;}}}
    for row in row_parameters {var determined=false;match self.types.row(row).tail {blot_check_effects::Tail.variable payload=>{determined=inList(rows,payload.value);},_=>{},}if !determined {let err=self.diagnostic(Code.undetermined_implementation,id);if err!=blot_error::Error.none {return err;}}}
    let member_start=self.implementation_members.len as u32;let index=self.implementations.len as u32;
    for child in self.tree.list(syntax.members) {let item=self.tree.node(child);let member_index=self.memberIndex(contract,item.a);if !member_index.present {let err=self.diagnostic(Code.missing_type_member,child);if err!=blot_error::Error.none {return err;}continue;}let required=self.contract_members[member_index.value];if required.kind==blot_reuse_principal_interface::ContractMemberKind.defined_type {let err=self.diagnostic(Code.duplicate_name,child);if err!=blot_error::Error.none {return err;}continue;}let is_type=item.tag==blot_parse_ast::tag_contract_type_member;if is_type!=(required.kind==blot_reuse_principal_interface::ContractMemberKind.abstract_type) {let err=self.diagnostic(Code.type_mismatch,child);if err!=blot_error::Error.none {return err;}continue;}var repeated=false;for prior in self.implementation_members[member_start..] {if prior.name==item.a {repeated=true;}}if repeated {let err=self.diagnostic(Code.duplicate_name,child);if err!=blot_error::Error.none {return err;}continue;}
        let owned=self.implementation_members.len as u32;var member=ImplementationMember{name:item.a,kind:blot_reuse_principal_interface::ImplementationMemberKind.type_};if !is_type {member.kind=blot_reuse_principal_interface::ImplementationMemberKind.value;self.name_bytes.clear();self.name_bytes.append(self.pool.get(syntax.name));self.name_bytes.append('.' as u8);self.name_bytes.append(self.pool.get(item.a));let name,err=self.pool.intern(self.name_bytes);if err!=blot_error::Error.none {if err==blot_error::Error.symbol_limit {return blot_error::Error.type_limit;}return err;}let ty,err=self.types.fresh();if err!=blot_error::Error.none {return err;}let binding,err=self.addBinding(Binding{private:true,name:name,declaration:child,owner:child,kind:Kind.global,named_function:true,ty:ty});if err!=blot_error::Error.none {return err;}self.resolved[child]=binding;self.implementation_bindings.insert(binding,index);self.global_states.insert(binding,Global{});member.target=ExternalTarget{self.unit,binding};}self.implementation_members.append(member);self.implementation_member_sources.insert(owned,child);
    }
    let members=blot_check_types::List{member_start,(self.implementation_members.len-member_start) as u32};for required in self.contract_members[contract.members.start..contract.members.start+contract.members.len] {if required.kind==blot_reuse_principal_interface::ContractMemberKind.defined_type {continue;}var present=false;for member in self.implementation_members[members.start..members.start+members.len] {if member.name==required.name {present=true;break;}}if !present {var code=Code.missing_type_member;if required.kind==blot_reuse_principal_interface::ContractMemberKind.value {code=Code.missing_member;}let err=self.diagnostic(code,id);if err!=blot_error::Error.none {return err;}}}
    let head_list,err=self.types.saveList(head);if err!=blot_error::Error.none {return err;}let variable_list,err=self.types.saveList(variables);if err!=blot_error::Error.none {return err;}let name_list,err=self.types.saveList(names);if err!=blot_error::Error.none {return err;}let row_list,err=self.types.saveList(rows);if err!=blot_error::Error.none {return err;}let row_names,err=self.types.saveList(declared_row_names);if err!=blot_error::Error.none {return err;}let row_parameter_list,err=self.types.saveList(row_parameters);if err!=blot_error::Error.none {return err;}
    self.implementations.append(Implementation{origin_span:blot_support::some(self.tree.span(id)),declaration:id,private:self.tree.declaration_traits(id).private,identity:Identity{self.unit,blot_check_types::opaque_name_bit|syntax.name},name:syntax.name,contract:contract.identity,head:head_list,variables:variable_list,parameter_names:name_list,row_variables:row_list,row_parameter_names:row_names,row_parameters:row_parameter_list,members:members});self.catalogs.implementation_names.insert(Qualified{0,syntax.name},index);
    var owner=contract.identity.unit==self.unit;if !owner && contract_old.len!=0 {let resolved,err=self.types.resolve(contract_fresh[0],0);if err!=blot_error::Error.none {return err;}let anchor=self.types.node(resolved);owner=anchor.tag==blot_check_types::Tag.nominal && anchor.a==self.unit;}if !owner {let err=self.diagnostic(Code.orphan_implementation,id);if err!=blot_error::Error.none {return err;}}
    var predicates:blot_check_types::Obligation[>..<];for predicate_source in self.tree.list(syntax.where) {let err=self.lowerPredicates(predicate_source,syntax.where_node,predicates);if err!=blot_error::Error.none {return err;}}for old in self.contract_predicates[contract.predicates.start..contract.predicates.start+contract.predicates.len] {let requirement,err=substitutePredicate(self,old,contract_old,contract_fresh,old_rows,new_rows);if err!=blot_error::Error.none {return err;}var value=requirement;value.source=id;predicates.append(value);}let predicate_start=self.implementation_predicates.len as u32;self.implementation_predicates.append(predicates);self.implementations[index].predicates=blot_check_types::List{predicate_start,predicates.len as u32};return blot_error::Error.none;
}
fn substitutePredicate(self:Engine&,old:blot_check_types::Obligation,variables:const u32[:],fresh:const u32[:],rows:const u32[:],new_rows:const u32[:])->blot_check_types::Obligation,blot_error::Error {var result=old;let ty,err=self.types.substituteWithRows(old.ty,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.ty=ty;let other,err=self.types.substituteWithRows(old.other,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.other=other;let value,err=self.types.substituteWithRows(old.result,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.result=value;let signature,err=self.types.substituteWithRows(old.signature,variables,fresh,rows,new_rows);if err!=blot_error::Error.none {return result,err;}result.signature=signature;return result,blot_error::Error.none;}

type TypeEnvironment=blot_support_pooled_buffer::Buffer<Engine_type_env>;
type RowEnvironment=blot_support_pooled_buffer::Buffer<Engine_row_env>;
reusable[] var type_environment_values:Engine_type_env[>..];
reusable[] var row_environment_values:Engine_row_env[>..];
fn blot_support_pooled_buffer::append(self:blot_check_check::TypeEnvironment&,value:blot_check_check::Engine_type_env)->blot_error::Error {return blot_support_pooled_buffer::push(self,value,blot_check_check::type_environment_values);}
fn blot_support_pooled_buffer::append(self:blot_check_check::RowEnvironment&,value:blot_check_check::Engine_row_env)->blot_error::Error {return blot_support_pooled_buffer::push(self,value,blot_check_check::row_environment_values);}
fn blot_support_pooled_buffer::deinit(self:blot_check_check::TypeEnvironment&) {blot_support_pooled_buffer::deinit(self,blot_check_check::type_environment_values);}
fn blot_support_pooled_buffer::deinit(self:blot_check_check::RowEnvironment&) {blot_support_pooled_buffer::deinit(self,blot_check_check::row_environment_values);}
