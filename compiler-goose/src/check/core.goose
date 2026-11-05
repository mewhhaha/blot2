// Immutable typed Core. All slices borrow lexical compilation owners.
namespace blot_check_core;
import support.structural;
import std;
import support.error;
import support.option;
import support.native;
struct List {
    start: u32 = 0,
    len: u32 = 0
}
struct BindingRef {
    unit: u32 = 0,
    binding: BindingId
}
struct Name {
    start: u32 = 0,
    len: u32 = 0
}
struct FieldName {
    symbol: u32,
    spelling: Name
}
enum Tag { invalid, constant, reference, scalar, logical, call, if_value, block_, suite, bind, return_, if_stmt, product, record, construct, project, match_, pattern_bind, update, array, array_op, closure, apply, constructor_function, associated, primitive_function, panic, loop_, break_, type_same, result_associated, type_constructor, resolver_op, operation_value, effect_provider, state_provider, handle, effect_reflection, computation, request_loop, request_decision, record_merge, contract_method, effect_scope, proof_guard, package_pack, package_unpack, staging, usage_borrow, usage_read, resource_scope, usage_share, resource_acquire, resource_release, task, storage }
enum PrimitiveKind { scalar, array }
struct Primitive {
    kind: PrimitiveKind,
    op: Op = Op.none,
    array_op: ArrayOp = ArrayOp.length,
    arity: u8
}
enum Op { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right, and_, or_, neg, abs, ceil, floor, trunc, sqrt, convert_u32_f32, convert_f32_u32, shift_right_signed, min, max, bit_not, bit_andnot, any_true, all_true, select, shuffle, swizzle, broadcast, bits, from_bits, relaxed_madd, relaxed_nmadd, convert_i32_f32, convert_f32_i32, continue_ }
struct Node {
    tag: Tag,
    op: Op = Op.none,
    ty: blot_check_types::Id = 0,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0
}
struct Parameter {
    binding: BindingId,
    ty: blot_check_types::Id,
    span: Span,
    inferred: bool = false
}
struct Binding {
    capability_flow: blot_check_check::CapabilityFlow = blot_check_check::CapabilityFlow.unknown,
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {},
    private: bool = false,
    initializer: Id = 0,
    kind: blot_check_check::Kind,
    ty: blot_check_types::Id,
    scheme: blot_check_types::Scheme,
    public_variables: blot_check_types::List = blot_check_types::List {},
    public_rows: blot_check_types::List = blot_check_types::List {},
    has_explicit: bool = false,
    body_id: BodyId = 0,
    target: BindingRef,
    span: Span
}
struct RuntimeName {
    binding: BindingId,
    point: u32
}
struct DeclarationDependencies {
    references: List = List {},
    members: List = List {},
    runtime_metadata: Id = 0
}
struct DependencyMember {
    name: u32 = 0,
    operator: blot_check_types::Operator = blot_check_types::Operator.none
}
struct ErasedDeclarationReference {
    node: Id,
    target: BindingRef
}
struct Body {
    binding: BindingId = 0,
    root: Id = 0,
    parameters: List = List {},
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {},
    closed_rows: blot_check_types::List = blot_check_types::List {},
    span: Span = Span { start: 0, end: 0 },
    declaration_name: Name = Name {},
    export_name: Name = Name {},
    exported: bool = false,
    runtime: bool = false,
    is_function: bool = false
}
struct CallInfo {
    target: BindingRef,
    callee_type: blot_check_types::Id
}
struct DictionaryUse {
    node: Id,
    binding: BindingId,
    opening: BindingId,
    introduction: Id = 0,
    quantifier: blot_check_types::Id,
    goal: u32,
    member: u32
}
struct DictionaryGiven {
    opening: BindingId,
    introduction: Id = 0,
    quantifier: blot_check_types::Id,
    goal: u32,
    arguments: blot_check_types::List
}
enum DictionaryProof { selected { value: u32 }, given { value: DictionaryGiven } }
struct DictionarySelection {
    owner: Id,
    quantifier: blot_check_types::Id,
    goal: u32,
    proof: DictionaryProof,
    members: List = List {},
    contents: List = List {}
}
struct Call {
    target: BindingRef,
    callee_type: blot_check_types::Id,
    arguments: const Id[:]
}
struct Merge {
    node: Id,
    result: BindingId,
    then_binding: BindingId,
    else_binding: BindingId
}
struct Obligation {
    ty: blot_check_types::Id,
    kind: blot_check_types::ObligationKind,
    span: Span,
    name: u32 = 0,
    result: blot_check_types::Id = 0,
    other: blot_check_types::Id = 0,
    signature: blot_check_types::Id = 0,
    operator: blot_check_types::Operator = blot_check_types::Operator.none,
    identity: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { unit: 0, decl: 0 },
    explicit: bool = false,
    qualification_span: blot_support::Option<Span> = blot_support::Option<Span> { false, default<Span>() },
    qualification_unit: u32 = 0,
    diagnostic_name: Name = Name {}
}
struct Associated {
    identity: blot_check_types::NominalIdentity,
    member: u32,
    operator: blot_check_types::Operator,
    target: BindingRef
}
struct Nominal {
    affine: bool = false,
    has_usage: bool = false,
    closed_storage: bool = false,
    private: bool = false,
    is_opaque: bool = false,
    storage: blot_backend_opaque_storage::Storage = blot_backend_opaque_storage::Storage {},
    diagnostic_name: Name = Name {},
    diagnostic_origin: Name = Name {},
    identity: blot_check_types::NominalIdentity,
    parameters: blot_check_types::List,
    variables: blot_check_types::List,
    constructors: List
}
struct OperationName {
    identity: blot_check_types::NominalIdentity,
    diagnostic_name: Name = Name {},
    diagnostic_origin: Name = Name {},
    variables: blot_check_types::List = blot_check_types::List {},
    parameters: blot_check_types::List = blot_check_types::List {},
    parameter: blot_check_types::Id = 0,
    result: blot_check_types::Id = 0
}
struct Constructor {
    identity: blot_check_types::NominalIdentity,
    nominal: u32,
    tag: u32,
    scheme: blot_check_types::Scheme,
    payload: blot_check_types::Id
}
struct ProjectionVariant {
    tag: u32,
    field: u32
}
struct Projection {
    nominal: blot_check_types::NominalIdentity,
    field: u32 = 0,
    source_type: blot_check_types::Id,
    result_type: blot_check_types::Id,
    variants: List,
    diagnostic_point: u32 = 0
}
enum PatternTag { invalid, wildcard, bind, constant, value, product, constructor, record_payload }
struct Pattern {
    tag: PatternTag,
    ty: blot_check_types::Id = 0,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
    span: Span = Span { start: 0, end: 0 }
}
struct PatternRow {
    patterns: List
}
struct MatchArm {
    rows: List,
    guard: Id = 0,
    body: Id,
    span: Span
}
struct MatchInfo {
    inputs: List,
    arms: List,
    statement: bool = false
}
enum UpdateKind { field, index }
struct UpdateStep {
    kind: UpdateKind,
    projection: u32 = 0,
    index: Id = 0,
    source_type: blot_check_types::Id,
    result_type: blot_check_types::Id
}
struct UpdateInfo {
    root: Id,
    path: List,
    value: Id,
    self_binding: BindingId,
    selectors: List = List {}
}
struct ClosureInfo {
    qualifier: BindingId = 0,
    body: Id,
    parameter: Parameter,
    captures: List,
    function_type: blot_check_types::Id = 0,
    closed_rows: blot_check_types::List = blot_check_types::List {}
}
enum ResolverOperation { monad, pure, bind, forward, iterate, run }
struct ResolverInfo {
    operation: ResolverOperation,
    resolver: Id,
    arguments: List = List {},
    member: u32 = 0,
    method: BindingRef = BindingRef { binding: 0 },
    method_type: blot_check_types::Id = 0
}
struct OperationValue {
    identity: blot_check_types::NominalIdentity,
    arguments: blot_check_types::List,
    signature: blot_check_types::Id,
    witness: Id = 0,
    witness_result: blot_check_types::Id = 0,
    instance: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { unit: 0, decl: 0 },
    capability: Id = 0
}
struct HandleEffects {
    node: Id,
    first: blot_check_types::Id,
    second: blot_check_types::Id = 0,
    extended: blot_check_effects::Id,
    residual: blot_check_effects::Id
}
enum RequestDecisionKind { reply, cancel, break_ }
struct RequestArm {
    operation: blot_check_effects::Label,
    callback: Id,
    selector: Id = 0
}
struct RequestLoopInfo {
    computation: Id,
    action_type: blot_check_types::Id,
    value_type: blot_check_types::Id,
    result_type: blot_check_types::Id,
    state_type: blot_check_types::Id,
    arms: List = List {},
    completion_pattern: PatternId = 0,
    completion_body: Id = 0,
    completion_state_bindings: List = List {},
    carries: List = List {},
    return_target: Id = 0
}
enum LoopKind { forever, range, array }
struct LoopCarry {
    incoming: BindingId,
    iteration: BindingId,
    backedge: BindingId,
    outgoing: BindingId
}
struct LoopInfo {
    kind: LoopKind,
    first: Id = 0,
    end: Id = 0,
    pattern: PatternId = 0,
    body: Id,
    carries: List = List {},
    can_exit: bool = false
}
enum Code { unchecked, unsupported, unresolved_binding, invalid_call, complexity }
struct Diagnostic {
    code: Code,
    span: Span
}
struct EffectRows {
    rows: const blot_check_effects::Row[:] = [],
    labels: const blot_check_effects::Label[:] = [],
    variable_count: u32 = 0
}
struct Contract {
    private: bool,
    identity: blot_check_types::NominalIdentity,
    name: u32,
    parameters: blot_check_types::List,
    variables: blot_check_types::List,
    row_variables: blot_check_types::List,
    predicates: blot_check_types::List,
    members: blot_check_types::List,
    requires_implementation: bool,
    row_parameter_names: blot_check_types::List = blot_check_types::List {},
    row_parameters: blot_check_types::List = blot_check_types::List {}
}
struct SelectedUse {
    node: Id,
    proof: u32
}
struct Types {
    owner_id: u64 = 0,
    nodes: const blot_check_types::Node[:],
    extra: const blot_check_types::Id[:],
    effects: EffectRows = EffectRows {},
    operations: const blot_check_types::Operation[:] = [],
    quantifier_goals: const blot_check_types::QuantifierGoals[:] = [],
    quantifier_obligations: const blot_check_types::Obligation[:] = []
}
struct Module {
    owner_id: u64 = 0,
    has_rank_contracts: bool = false,
    has_usage_contracts: bool = false,
    has_numeric_proofs: bool = false,
    proof_contracts: ProofContract[:] = [],
    capability_contracts: blot_check_capability_contracts::Collection = blot_check_capability_contracts::Collection {},
    field_names: FieldName[:] = [],
    runtime_names: RuntimeName[:] = [],
    source_names: RuntimeName[:] = [],
    declaration_dependencies: DeclarationDependencies[:] = [],
    dependency_references: BindingRef[:] = [],
    dependency_members: DependencyMember[:] = [],
    erased_declaration_references: ErasedDeclarationReference[:] = [],
    request_loops: RequestLoopInfo[:] = [],
    request_arms: RequestArm[:] = [],
    tag_calls: Id[:] = [],
    unit: u32 = 0,
    types: Types,
    nodes: Node[:],
    spans: Span[:],
    extra: Id[:],
    bindings: Binding[:],
    bodies: Body[:],
    parameters: Parameter[:],
    references: BindingRef[:],
    calls: CallInfo[:],
    merges: Merge[:],
    merge_ranges: List[:],
    names: u8[:],
    obligations: Obligation[:],
    nominals: Nominal[:] = [],
    operation_names: OperationName[:] = [],
    constructors: Constructor[:] = [],
    projections: Projection[:] = [],
    projection_variants: ProjectionVariant[:] = [],
    patterns: Pattern[:] = [],
    pattern_rows: PatternRow[:] = [],
    match_arms: MatchArm[:] = [],
    matches: MatchInfo[:] = [],
    updates: UpdateInfo[:] = [],
    update_steps: UpdateStep[:] = [],
    closures: ClosureInfo[:] = [],
    associated: Associated[:] = [],
    contracts: Contract[:] = [],
    contract_members: ContractMember[:] = [],
    implementations: Implementation[:] = [],
    implementation_members: ImplementationMember[:] = [],
    member_templates: MemberTemplate[:] = [],
    selected_proofs: SelectedProof[:] = [],
    selected_members: ImplementationMember[:] = [],
    selected_edges: u32[:] = [],
    selected_uses: SelectedUse[:] = [],
    dictionary_selections: DictionarySelection[:] = [],
    dictionary_uses: DictionaryUse[:] = [],
    primitives: Primitive[:] = [],
    loops: LoopInfo[:] = [],
    loop_carries: LoopCarry[:] = [],
    resolver_ops: ResolverInfo[:] = [],
    operation_values: OperationValue[:] = [],
    handle_effects: HandleEffects[:] = [],
    dispatch_signatures: blot_check_types::Id[:] = [],
    diagnostics: Diagnostic[:],
    body_lowerings: i64,
    package_payloads: Id[:] = []
}
type Id = u32;
type BindingId = u32;
type BodyId = u32;
type PatternId = u32;
type Span = blot_parse_ast::Span;
type ProofContract = blot_check_numeric_proof_headers::Named;
type ArrayOp = blot_backend_collection_ops::Op;
type ContractMember = blot_reuse_principal_interface::ContractMember;
type Implementation = blot_reuse_principal_interface::Implementation;
type ImplementationMember = blot_reuse_principal_interface::ImplementationMember;
type MemberTemplate = blot_reuse_principal_interface::MemberTemplate;
type SelectedProof = blot_reuse_principal_interface::SelectedProof;
fn message(self: Diagnostic) -> const u8[:] {
    match self.code {
        unchecked => { return "Typed core requires successful semantic checking"; },
        unsupported => { return "This checked form is not implemented in the typed core"; },
        unresolved_binding => { return "Typed expression has no resolved binding identity"; },
        invalid_call => { return "Typed core requires a resolved named call or compiler primitive"; },
        complexity => { return "Typed core exceeds its nesting or table limit"; },
    }
}
fn node(self: const EffectRows&, id: blot_check_effects::Id) -> blot_check_effects::Row {
    if id == 0 && self.rows.len == 0 { return blot_check_effects::Row {}; }
    return self.rows[id];
}
fn list(self: const EffectRows&, span: blot_check_effects::List) -> const blot_check_effects::Label[:] { return self.labels[span.start..span.start + span.len]; }
fn quantifierGoals(self: const Types&, owner: blot_check_types::Id) -> const blot_check_types::Obligation[:] {
    return blot_check_quantifier_goals::get(self.quantifier_goals, self.quantifier_obligations, owner);
}
fn node(self: const Types&, id: blot_check_types::Id) -> blot_check_types::Node { return self.nodes[id]; }
fn withoutForall(self: const Types&, id: blot_check_types::Id) -> blot_check_types::Id, blot_error::Error {
    var current = id; var depth: i64 = 0;
    while self.node(current).tag == blot_check_types::Tag.forall || self.node(current).tag == blot_check_types::Tag.usage {
        if depth == 128 { return 0, blot_error::Error.core_limit; }
        depth += 1; current = self.node(current).a;
    }
    return current, blot_error::Error.none;
}
fn head(self: const Types&, id: blot_check_types::Id, at: blot_check_types::Cursor) -> blot_check_types::Id { return id; }
fn list(self: const Types&, span: blot_check_types::List) -> const blot_check_types::Id[:] { return self.extra[span.start..span.start + span.len]; }
fn projectionMember(self: const Types&, value: blot_check_types::Node) -> u32 { return self.extra[value.c + 1 + self.extra[value.c]]; }
fn nominalArguments(self: const Types&, value: blot_check_types::Node) -> const blot_check_types::Id[:] {
    assert(value.tag == blot_check_types::Tag.nominal || value.tag == blot_check_types::Tag.projection || value.tag == blot_check_types::Tag.instance_selection);
    return self.extra[value.c + 1..value.c + 1 + self.extra[value.c]];
}
fn recordField(self: const Types&, value: blot_check_types::Node, index: i64) -> blot_check_types::Field {
    assert(value.tag == blot_check_types::Tag.record && index < value.b);
    return blot_check_types::Field { self.extra[value.a + index * 2], self.extra[value.a + index * 2 + 1] };
}
fn row(self: const Types&, id: blot_check_effects::Id) -> blot_check_effects::Row { return self.effects.node(id); }
fn rowLabels(self: const Types&, id: blot_check_effects::Id) -> const blot_check_effects::Label[:] { return self.effects.list(self.row(id).labels); }
fn operation(self: const Types&, label: blot_check_effects::Label) -> blot_check_types::Operation { return self.operations[label]; }
fn operationArguments(self: const Types&, label: blot_check_effects::Label) -> const blot_check_types::Id[:] { return self.list(self.operation(label).arguments); }
fn node(self: const Module&, id: Id) -> Node { return self.nodes[id]; }
fn span(self: const Module&, id: Id) -> Span { return self.spans[id]; }
fn namePoint(values: const RuntimeName[:], id: BindingId) -> u32, bool {
    var low: i64 = 0; var high = values.len;
    while low < high {
        let middle = low + (high - low) / 2;
        let value = values[middle];
        if value.binding < id { low = middle + 1; }
        else if value.binding > id { high = middle; }
        else { return value.point, true; }
    }
    return 0, false;
}
fn sourceNamePoint(self: const Module&, binding_id: BindingId) -> u32 {
    let point, found = namePoint(self.source_names, binding_id);
    if found { return point; }
    return self.binding(binding_id).span.start;
}
fn runtimeNamePoint(self: const Module&, binding_id: BindingId) -> u32 {
    let point, found = namePoint(self.runtime_names, binding_id);
    if found { return point; }
    return self.binding(binding_id).span.start;
}
fn isTagCall(self: const Module&, id: Id) -> bool {
    var low: i64 = 0; var high = self.tag_calls.len;
    while low < high {
        let middle = low + (high - low) / 2; let value = self.tag_calls[middle];
        if value < id { low = middle + 1; } else if value > id { high = middle; } else { return true; }
    }
    return false;
}
struct PackageOpening { body: Id, binders: blot_check_types::List }
fn packageOpening(self: const Module&, id: Id) -> PackageOpening {
    let value = self.node(id); assert(value.tag == Tag.package_unpack);
    let metadata = self.extra[value.c..value.c + 3];
    return PackageOpening { metadata[0], blot_check_types::List { metadata[1], metadata[2] } };
}
fn typeOf(self: const Module&, id: Id) -> blot_check_types::Id { return self.nodes[id].ty; }
fn operationValue(self: const Module&, id: Id) -> OperationValue {
    assert(self.node(id).tag == Tag.operation_value); return self.operation_values[self.node(id).a];
}
fn operationValueArguments(self: const Module&, id: Id) -> const blot_check_types::Id[:] { return self.types.list(self.operationValue(id).arguments); }
fn handleEffects(self: const Module&, id: Id) -> blot_support::Option<HandleEffects> {
    let value = self.node(id); assert(value.tag == Tag.handle);
    if value.c == 0 { return blot_support::Option<HandleEffects> { false, default<HandleEffects>() }; }
    return blot_support::Option<HandleEffects> { true, self.handle_effects[value.c - 1] };
}
fn dispatchSignature(self: const Module&, id: Id) -> blot_check_types::Id {
    if self.dispatch_signatures.len == 0 { return 0; } return self.dispatch_signatures[id];
}
fn children(self: const Module&, id: Id) -> const Id[:] {
    let value = self.node(id);
    match value.tag {
        block_, suite, product, record, array, array_op, storage, task => { return self.extra[value.a..value.a + value.b]; },
        call, contract_method, break_ => { return self.extra[value.b..value.b + value.c]; },
        package_pack => {
            for selection in self.dictionary_selections {
                if selection.owner == id { return self.extra[selection.contents.start..selection.contents.start + selection.contents.len]; }
            }
            assert(id < self.package_payloads.len && self.package_payloads[id] == value.a);
            return self.package_payloads[id..id + 1];
        },
        _ => { return self.extra[..0]; },
    }
}
fn call(self: const Module&, id: Id) -> Call {
    let value = self.node(id); assert(value.tag == Tag.call); let target = self.calls[value.a];
    return Call { target.target, target.callee_type, self.children(id) };
}
fn dictionaryOffset(self: const Module&, quantifier: blot_check_types::Id, wanted_goal: u32, wanted_member: u32) -> i64, blot_error::Error {
    let goals = self.types.quantifierGoals(quantifier);
    if wanted_goal >= goals.len { return 0, blot_error::Error.core_limit; }
    var offset: i64 = 1;
    for goal, ordinal in goals {
        if goal.kind != blot_check_types::ObligationKind.contract {
            if ordinal == wanted_goal { return 0, blot_error::Error.core_limit; }
            continue;
        }
        var contract_index: i64 = -1;
        for candidate, index in self.contracts {
            if candidate.identity.unit == goal.identity.unit && candidate.identity.decl == goal.identity.decl { contract_index = index; break; }
        }
        if contract_index < 0 { return 0, blot_error::Error.core_limit; }
        let contract = self.contracts[contract_index];
        for member, member_ordinal in self.contract_members[contract.members.start..contract.members.start + contract.members.len] {
            if ordinal == wanted_goal && member_ordinal == wanted_member {
                if member.kind != blot_reuse_principal_interface::ContractMemberKind.value { return 0, blot_error::Error.core_limit; }
                return offset, blot_error::Error.none;
            }
            if member.kind == blot_reuse_principal_interface::ContractMemberKind.value { offset += 1; }
        }
    }
    return 0, blot_error::Error.core_limit;
}
fn reference(self: const Module&, id: Id) -> BindingRef { assert(self.node(id).tag == Tag.reference); return self.references[self.node(id).a]; }
fn binding(self: const Module&, id: BindingId) -> Binding { return self.bindings[id]; }
fn body(self: const Module&, id: BindingId) -> const Body? {
    let body_id = self.bindings[id].body_id; if body_id == 0 { return null; } return self.bodies[body_id];
}
fn bodyParameters(self: const Module&, value: const Body&) -> const Parameter[:] { return self.parameters[value.parameters.start..value.parameters.start + value.parameters.len]; }
fn branchMerges(self: const Module&, id: Id) -> const Merge[:] { let range = self.merge_ranges[id]; return self.merges[range.start..range.start + range.len]; }
fn requestLoopInfo(self: const Module&, id: Id) -> RequestLoopInfo { assert(self.node(id).tag == Tag.request_loop); return self.request_loops[self.node(id).a]; }
fn requestArms(self: const Module&, id: Id) -> const RequestArm[:] { let range = self.requestLoopInfo(id).arms; return self.request_arms[range.start..range.start + range.len]; }
fn requestLoopCarries(self: const Module&, id: Id) -> const LoopCarry[:] { let range = self.requestLoopInfo(id).carries; return self.loop_carries[range.start..range.start + range.len]; }
fn requestCompletionBindings(self: const Module&, id: Id) -> const BindingId[:] { let range = self.requestLoopInfo(id).completion_state_bindings; return self.extra[range.start..range.start + range.len]; }
fn loopInfo(self: const Module&, id: Id) -> LoopInfo { let value = self.node(id); assert(value.tag == Tag.loop_); return self.loops[value.a]; }
fn loopCarries(self: const Module&, id: Id) -> const LoopCarry[:] { let range = self.loopInfo(id).carries; return self.loop_carries[range.start..range.start + range.len]; }
fn breakValues(self: const Module&, id: Id) -> const Id[:] { assert(self.node(id).tag == Tag.break_); return self.children(id); }
fn name(self: const Module&, range: Name) -> const u8[:] { return self.names[range.start..range.start + range.len]; }
fn fieldSpelling(self: const Module&, symbol: u32) -> const u8[:], bool {
    var low: i64 = 0; var high = self.field_names.len;
    while low < high {
        let middle = low + (high - low) / 2; let value = self.field_names[middle];
        if value.symbol < symbol { low = middle + 1; } else if value.symbol > symbol { high = middle; }
        else { return self.name(value.spelling), true; }
    }
    return self.names[..0], false;
}
fn nominal(self: const Module&, index: u32) -> Nominal { return self.nominals[index]; }
fn nominalConstructors(self: const Module&, index: u32) -> const u32[:] { let range = self.nominals[index].constructors; return self.extra[range.start..range.start + range.len]; }
fn constructor(self: const Module&, index: u32) -> Constructor { return self.constructors[index]; }
fn recordDestinations(self: const Module&, id: Id) -> const u32[:] { let value = self.node(id); assert(value.tag == Tag.record); return self.extra[value.c..value.c + value.b]; }
fn projection(self: const Module&, index: u32) -> Projection { return self.projections[index]; }
fn projectionVariants(self: const Module&, index: u32) -> const ProjectionVariant[:] { let range = self.projections[index].variants; return self.projection_variants[range.start..range.start + range.len]; }
fn pattern(self: const Module&, id: PatternId) -> Pattern { return self.patterns[id]; }
fn patternChildren(self: const Module&, id: PatternId) -> const PatternId[:] { let value = self.pattern(id); assert(value.tag == PatternTag.product); return self.extra[value.a..value.a + value.b]; }
fn matchInfo(self: const Module&, id: Id) -> MatchInfo { let value = self.node(id); assert(value.tag == Tag.match_); return self.matches[value.a]; }
fn matchInputs(self: const Module&, id: Id) -> const Id[:] { let range = self.matchInfo(id).inputs; return self.extra[range.start..range.start + range.len]; }
fn matchArms(self: const Module&, id: Id) -> const MatchArm[:] { let range = self.matchInfo(id).arms; return self.match_arms[range.start..range.start + range.len]; }
fn armRows(self: const Module&, arm: MatchArm) -> const PatternRow[:] { return self.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len]; }
fn rowPatterns(self: const Module&, row: PatternRow) -> const PatternId[:] { return self.extra[row.patterns.start..row.patterns.start + row.patterns.len]; }
fn updateInfo(self: const Module&, id: Id) -> UpdateInfo { let value = self.node(id); assert(value.tag == Tag.update); return self.updates[value.a]; }
fn updatePath(self: const Module&, id: Id) -> const u32[:] { let range = self.updateInfo(id).path; return self.extra[range.start..range.start + range.len]; }
fn updateSelectors(self: const Module&, id: Id) -> const UpdateStep[:] { let range = self.updateInfo(id).selectors; return self.update_steps[range.start..range.start + range.len]; }
fn arrayOperation(self: const Module&, id: Id) -> ArrayOp {
    let value = self.node(id); assert(value.tag == Tag.array_op);
    let operation, error = blot_backend_collection_ops::opFromCode(value.c);
    assert(error == blot_error::Error.none); return operation;
}
fn closure(self: const Module&, id: Id) -> ClosureInfo { let value = self.node(id); assert(value.tag == Tag.closure); return self.closures[value.a]; }
fn closureCaptures(self: const Module&, id: Id) -> const BindingId[:] { let range = self.closure(id).captures; return self.extra[range.start..range.start + range.len]; }
fn resolverInfo(self: const Module&, id: Id) -> ResolverInfo { let value = self.node(id); assert(value.tag == Tag.resolver_op); return self.resolver_ops[value.a]; }
fn resolverArguments(self: const Module&, id: Id) -> const Id[:] { let range = self.resolverInfo(id).arguments; return self.extra[range.start..range.start + range.len]; }
fn primitive(self: const Module&, id: Id) -> Primitive { let value = self.node(id); assert(value.tag == Tag.primitive_function); return self.primitives[value.a]; }
fn panicMessage(self: const Module&, id: Id) -> const u8[:] { let value = self.node(id); assert(value.tag == Tag.panic); return self.name(Name { value.a, value.b }); }

fn tagCode(value: Tag) -> u32 {
    match value {
        invalid => { return 0; },
        constant => { return 1; },
        reference => { return 2; },
        scalar => { return 3; },
        logical => { return 4; },
        call => { return 5; },
        if_value => { return 6; },
        block_ => { return 7; },
        suite => { return 8; },
        bind => { return 9; },
        return_ => { return 10; },
        if_stmt => { return 11; },
        product => { return 12; },
        record => { return 13; },
        construct => { return 14; },
        project => { return 15; },
        match_ => { return 16; },
        pattern_bind => { return 17; },
        update => { return 18; },
        array => { return 19; },
        array_op => { return 20; },
        closure => { return 21; },
        apply => { return 22; },
        constructor_function => { return 23; },
        associated => { return 24; },
        primitive_function => { return 25; },
        panic => { return 26; },
        loop_ => { return 27; },
        break_ => { return 28; },
        type_same => { return 29; },
        result_associated => { return 30; },
        type_constructor => { return 31; },
        resolver_op => { return 32; },
        operation_value => { return 33; },
        effect_provider => { return 34; },
        state_provider => { return 35; },
        handle => { return 36; },
        effect_reflection => { return 37; },
        computation => { return 38; },
        request_loop => { return 39; },
        request_decision => { return 40; },
        record_merge => { return 41; },
        contract_method => { return 42; },
        effect_scope => { return 43; },
        proof_guard => { return 44; },
        package_pack => { return 45; },
        package_unpack => { return 46; },
        staging => { return 47; },
        usage_borrow => { return 48; },
        usage_read => { return 49; },
        resource_scope => { return 50; },
        usage_share => { return 51; },
        resource_acquire => { return 52; },
        resource_release => { return 53; },
        task => { return 54; },
        storage => { return 55; },
    }
}
fn tagFromCode(code: u32) -> Tag, blot_error::Error {
    match code {
        0 => { return Tag.invalid, blot_error::Error.none; },
        1 => { return Tag.constant, blot_error::Error.none; },
        2 => { return Tag.reference, blot_error::Error.none; },
        3 => { return Tag.scalar, blot_error::Error.none; },
        4 => { return Tag.logical, blot_error::Error.none; },
        5 => { return Tag.call, blot_error::Error.none; },
        6 => { return Tag.if_value, blot_error::Error.none; },
        7 => { return Tag.block_, blot_error::Error.none; },
        8 => { return Tag.suite, blot_error::Error.none; },
        9 => { return Tag.bind, blot_error::Error.none; },
        10 => { return Tag.return_, blot_error::Error.none; },
        11 => { return Tag.if_stmt, blot_error::Error.none; },
        12 => { return Tag.product, blot_error::Error.none; },
        13 => { return Tag.record, blot_error::Error.none; },
        14 => { return Tag.construct, blot_error::Error.none; },
        15 => { return Tag.project, blot_error::Error.none; },
        16 => { return Tag.match_, blot_error::Error.none; },
        17 => { return Tag.pattern_bind, blot_error::Error.none; },
        18 => { return Tag.update, blot_error::Error.none; },
        19 => { return Tag.array, blot_error::Error.none; },
        20 => { return Tag.array_op, blot_error::Error.none; },
        21 => { return Tag.closure, blot_error::Error.none; },
        22 => { return Tag.apply, blot_error::Error.none; },
        23 => { return Tag.constructor_function, blot_error::Error.none; },
        24 => { return Tag.associated, blot_error::Error.none; },
        25 => { return Tag.primitive_function, blot_error::Error.none; },
        26 => { return Tag.panic, blot_error::Error.none; },
        27 => { return Tag.loop_, blot_error::Error.none; },
        28 => { return Tag.break_, blot_error::Error.none; },
        29 => { return Tag.type_same, blot_error::Error.none; },
        30 => { return Tag.result_associated, blot_error::Error.none; },
        31 => { return Tag.type_constructor, blot_error::Error.none; },
        32 => { return Tag.resolver_op, blot_error::Error.none; },
        33 => { return Tag.operation_value, blot_error::Error.none; },
        34 => { return Tag.effect_provider, blot_error::Error.none; },
        35 => { return Tag.state_provider, blot_error::Error.none; },
        36 => { return Tag.handle, blot_error::Error.none; },
        37 => { return Tag.effect_reflection, blot_error::Error.none; },
        38 => { return Tag.computation, blot_error::Error.none; },
        39 => { return Tag.request_loop, blot_error::Error.none; },
        40 => { return Tag.request_decision, blot_error::Error.none; },
        41 => { return Tag.record_merge, blot_error::Error.none; },
        42 => { return Tag.contract_method, blot_error::Error.none; },
        43 => { return Tag.effect_scope, blot_error::Error.none; },
        44 => { return Tag.proof_guard, blot_error::Error.none; },
        45 => { return Tag.package_pack, blot_error::Error.none; },
        46 => { return Tag.package_unpack, blot_error::Error.none; },
        47 => { return Tag.staging, blot_error::Error.none; },
        48 => { return Tag.usage_borrow, blot_error::Error.none; },
        49 => { return Tag.usage_read, blot_error::Error.none; },
        50 => { return Tag.resource_scope, blot_error::Error.none; },
        51 => { return Tag.usage_share, blot_error::Error.none; },
        52 => { return Tag.resource_acquire, blot_error::Error.none; },
        53 => { return Tag.resource_release, blot_error::Error.none; },
        54 => { return Tag.task, blot_error::Error.none; },
        55 => { return Tag.storage, blot_error::Error.none; },
        _ => { return Tag.invalid, blot_error::Error.core_limit; },
    }
}

fn opCode(value: Op) -> u32 {
    match value {
        none => { return 0; },
        add => { return 1; },
        sub => { return 2; },
        mul => { return 3; },
        div => { return 4; },
        rem => { return 5; },
        equal => { return 6; },
        not_equal => { return 7; },
        less => { return 8; },
        less_equal => { return 9; },
        greater => { return 10; },
        greater_equal => { return 11; },
        bit_and => { return 12; },
        bit_or => { return 13; },
        bit_xor => { return 14; },
        shift_left => { return 15; },
        shift_right => { return 16; },
        and_ => { return 17; },
        or_ => { return 18; },
        neg => { return 19; },
        abs => { return 20; },
        ceil => { return 21; },
        floor => { return 22; },
        trunc => { return 23; },
        sqrt => { return 24; },
        convert_u32_f32 => { return 25; },
        convert_f32_u32 => { return 26; },
        shift_right_signed => { return 27; },
        min => { return 28; },
        max => { return 29; },
        bit_not => { return 30; },
        bit_andnot => { return 31; },
        any_true => { return 32; },
        all_true => { return 33; },
        select => { return 34; },
        shuffle => { return 35; },
        swizzle => { return 36; },
        broadcast => { return 37; },
        bits => { return 38; },
        from_bits => { return 39; },
        relaxed_madd => { return 40; },
        relaxed_nmadd => { return 41; },
        convert_i32_f32 => { return 42; },
        convert_f32_i32 => { return 43; },
        continue_ => { return 44; },
    }
}
fn opFromCode(code: u32) -> Op, blot_error::Error {
    match code {
        0 => { return Op.none, blot_error::Error.none; },
        1 => { return Op.add, blot_error::Error.none; },
        2 => { return Op.sub, blot_error::Error.none; },
        3 => { return Op.mul, blot_error::Error.none; },
        4 => { return Op.div, blot_error::Error.none; },
        5 => { return Op.rem, blot_error::Error.none; },
        6 => { return Op.equal, blot_error::Error.none; },
        7 => { return Op.not_equal, blot_error::Error.none; },
        8 => { return Op.less, blot_error::Error.none; },
        9 => { return Op.less_equal, blot_error::Error.none; },
        10 => { return Op.greater, blot_error::Error.none; },
        11 => { return Op.greater_equal, blot_error::Error.none; },
        12 => { return Op.bit_and, blot_error::Error.none; },
        13 => { return Op.bit_or, blot_error::Error.none; },
        14 => { return Op.bit_xor, blot_error::Error.none; },
        15 => { return Op.shift_left, blot_error::Error.none; },
        16 => { return Op.shift_right, blot_error::Error.none; },
        17 => { return Op.and_, blot_error::Error.none; },
        18 => { return Op.or_, blot_error::Error.none; },
        19 => { return Op.neg, blot_error::Error.none; },
        20 => { return Op.abs, blot_error::Error.none; },
        21 => { return Op.ceil, blot_error::Error.none; },
        22 => { return Op.floor, blot_error::Error.none; },
        23 => { return Op.trunc, blot_error::Error.none; },
        24 => { return Op.sqrt, blot_error::Error.none; },
        25 => { return Op.convert_u32_f32, blot_error::Error.none; },
        26 => { return Op.convert_f32_u32, blot_error::Error.none; },
        27 => { return Op.shift_right_signed, blot_error::Error.none; },
        28 => { return Op.min, blot_error::Error.none; },
        29 => { return Op.max, blot_error::Error.none; },
        30 => { return Op.bit_not, blot_error::Error.none; },
        31 => { return Op.bit_andnot, blot_error::Error.none; },
        32 => { return Op.any_true, blot_error::Error.none; },
        33 => { return Op.all_true, blot_error::Error.none; },
        34 => { return Op.select, blot_error::Error.none; },
        35 => { return Op.shuffle, blot_error::Error.none; },
        36 => { return Op.swizzle, blot_error::Error.none; },
        37 => { return Op.broadcast, blot_error::Error.none; },
        38 => { return Op.bits, blot_error::Error.none; },
        39 => { return Op.from_bits, blot_error::Error.none; },
        40 => { return Op.relaxed_madd, blot_error::Error.none; },
        41 => { return Op.relaxed_nmadd, blot_error::Error.none; },
        42 => { return Op.convert_i32_f32, blot_error::Error.none; },
        43 => { return Op.convert_f32_i32, blot_error::Error.none; },
        44 => { return Op.continue_, blot_error::Error.none; },
        _ => { return Op.none, blot_error::Error.core_limit; },
    }
}

fn patternTagCode(value: PatternTag) -> u32 {
    match value {
        invalid => { return 0; },
        wildcard => { return 1; },
        bind => { return 2; },
        constant => { return 3; },
        value => { return 4; },
        product => { return 5; },
        constructor => { return 6; },
        record_payload => { return 7; },
    }
}
fn patternTagFromCode(code: u32) -> PatternTag, blot_error::Error {
    match code {
        0 => { return PatternTag.invalid, blot_error::Error.none; },
        1 => { return PatternTag.wildcard, blot_error::Error.none; },
        2 => { return PatternTag.bind, blot_error::Error.none; },
        3 => { return PatternTag.constant, blot_error::Error.none; },
        4 => { return PatternTag.value, blot_error::Error.none; },
        5 => { return PatternTag.product, blot_error::Error.none; },
        6 => { return PatternTag.constructor, blot_error::Error.none; },
        7 => { return PatternTag.record_payload, blot_error::Error.none; },
        _ => { return PatternTag.invalid, blot_error::Error.core_limit; },
    }
}

fn primitiveKindCode(value: PrimitiveKind) -> u32 {
    match value {
        scalar => { return 0; },
        array => { return 1; },
    }
}
fn primitiveKindFromCode(code: u32) -> PrimitiveKind, blot_error::Error {
    match code {
        0 => { return PrimitiveKind.scalar, blot_error::Error.none; },
        1 => { return PrimitiveKind.array, blot_error::Error.none; },
        _ => { return PrimitiveKind.scalar, blot_error::Error.core_limit; },
    }
}

fn updateKindCode(value: UpdateKind) -> u32 {
    match value {
        field => { return 0; },
        index => { return 1; },
    }
}
fn updateKindFromCode(code: u32) -> UpdateKind, blot_error::Error {
    match code {
        0 => { return UpdateKind.field, blot_error::Error.none; },
        1 => { return UpdateKind.index, blot_error::Error.none; },
        _ => { return UpdateKind.field, blot_error::Error.core_limit; },
    }
}

fn resolverOperationCode(value: ResolverOperation) -> u32 {
    match value {
        monad => { return 0; },
        pure => { return 1; },
        bind => { return 2; },
        forward => { return 3; },
        iterate => { return 4; },
        run => { return 5; },
    }
}
fn resolverOperationFromCode(code: u32) -> ResolverOperation, blot_error::Error {
    match code {
        0 => { return ResolverOperation.monad, blot_error::Error.none; },
        1 => { return ResolverOperation.pure, blot_error::Error.none; },
        2 => { return ResolverOperation.bind, blot_error::Error.none; },
        3 => { return ResolverOperation.forward, blot_error::Error.none; },
        4 => { return ResolverOperation.iterate, blot_error::Error.none; },
        5 => { return ResolverOperation.run, blot_error::Error.none; },
        _ => { return ResolverOperation.monad, blot_error::Error.core_limit; },
    }
}

fn requestDecisionKindCode(value: RequestDecisionKind) -> u32 {
    match value {
        reply => { return 0; },
        cancel => { return 1; },
        break_ => { return 2; },
    }
}
fn requestDecisionKindFromCode(code: u32) -> RequestDecisionKind, blot_error::Error {
    match code {
        0 => { return RequestDecisionKind.reply, blot_error::Error.none; },
        1 => { return RequestDecisionKind.cancel, blot_error::Error.none; },
        2 => { return RequestDecisionKind.break_, blot_error::Error.none; },
        _ => { return RequestDecisionKind.reply, blot_error::Error.core_limit; },
    }
}

fn loopKindCode(value: LoopKind) -> u32 {
    match value {
        forever => { return 0; },
        range => { return 1; },
        array => { return 2; },
    }
}
fn loopKindFromCode(code: u32) -> LoopKind, blot_error::Error {
    match code {
        0 => { return LoopKind.forever, blot_error::Error.none; },
        1 => { return LoopKind.range, blot_error::Error.none; },
        2 => { return LoopKind.array, blot_error::Error.none; },
        _ => { return LoopKind.forever, blot_error::Error.core_limit; },
    }
}

fn codeCode(value: Code) -> u32 {
    match value {
        unchecked => { return 0; },
        unsupported => { return 1; },
        unresolved_binding => { return 2; },
        invalid_call => { return 3; },
        complexity => { return 4; },
    }
}
fn codeFromCode(code: u32) -> Code, blot_error::Error {
    match code {
        0 => { return Code.unchecked, blot_error::Error.none; },
        1 => { return Code.unsupported, blot_error::Error.none; },
        2 => { return Code.unresolved_binding, blot_error::Error.none; },
        3 => { return Code.invalid_call, blot_error::Error.none; },
        4 => { return Code.complexity, blot_error::Error.none; },
        _ => { return Code.unchecked, blot_error::Error.core_limit; },
    }
}

fn deinit(self: Module&) {
    self.proof_contracts = [];
    self.field_names = [];
    self.runtime_names = [];
    self.source_names = [];
    self.declaration_dependencies = [];
    self.dependency_references = [];
    self.dependency_members = [];
    self.erased_declaration_references = [];
    self.request_loops = [];
    self.request_arms = [];
    self.tag_calls = [];
    self.nodes = [];
    self.spans = [];
    self.extra = [];
    self.bindings = [];
    self.bodies = [];
    self.parameters = [];
    self.references = [];
    self.calls = [];
    self.merges = [];
    self.merge_ranges = [];
    self.names = [];
    self.obligations = [];
    self.nominals = [];
    self.operation_names = [];
    self.constructors = [];
    self.projections = [];
    self.projection_variants = [];
    self.patterns = [];
    self.pattern_rows = [];
    self.match_arms = [];
    self.matches = [];
    self.updates = [];
    self.update_steps = [];
    self.closures = [];
    self.associated = [];
    self.contracts = [];
    self.contract_members = [];
    self.implementations = [];
    self.implementation_members = [];
    self.member_templates = [];
    self.selected_proofs = [];
    self.selected_members = [];
    self.selected_edges = [];
    self.selected_uses = [];
    self.dictionary_selections = [];
    self.dictionary_uses = [];
    self.primitives = [];
    self.loops = [];
    self.loop_carries = [];
    self.resolver_ops = [];
    self.operation_values = [];
    self.handle_effects = [];
    self.dispatch_signatures = [];
    self.diagnostics = [];
    self.package_payloads = [];
    self.types.nodes = []; self.types.extra = []; self.types.effects.rows = []; self.types.effects.labels = [];
    self.types.operations = []; self.types.quantifier_goals = []; self.types.quantifier_obligations = [];
    self.owner_id = 0; self.types.owner_id = 0;
}

fn lower(tree, names, checked, tables) -> Module, blot_error::Error { return blot_check_core_builder::lower(tree, names, checked, tables); }
fn lowerWithOrigins(tree, names, checked, diagnostic_origins, tables) -> Module, blot_error::Error { return blot_check_core_builder::lowerWithOrigins(tree, names, checked, diagnostic_origins, tables); }

fn blot_structural::equal(left: blot_check_core::Tag, right: blot_check_core::Tag) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::Tag) { blot_structural::hash(sink, blot_check_core::tagCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::PrimitiveKind, right: blot_check_core::PrimitiveKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::PrimitiveKind) { blot_structural::hash(sink, blot_check_core::primitiveKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::Op, right: blot_check_core::Op) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::Op) { blot_structural::hash(sink, blot_check_core::opCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::PatternTag, right: blot_check_core::PatternTag) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::PatternTag) { blot_structural::hash(sink, blot_check_core::patternTagCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::UpdateKind, right: blot_check_core::UpdateKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::UpdateKind) { blot_structural::hash(sink, blot_check_core::updateKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::ResolverOperation, right: blot_check_core::ResolverOperation) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::ResolverOperation) { blot_structural::hash(sink, blot_check_core::resolverOperationCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::RequestDecisionKind, right: blot_check_core::RequestDecisionKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::RequestDecisionKind) { blot_structural::hash(sink, blot_check_core::requestDecisionKindCode(value) as! u32); }

fn blot_structural::equal(left: blot_check_core::LoopKind, right: blot_check_core::LoopKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::LoopKind) { blot_structural::hash(sink, blot_check_core::loopKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::Code, right: blot_check_core::Code) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::Code) { blot_structural::hash(sink, blot_check_core::codeCode(value) as! u8); }
fn blot_structural::equal(left: blot_check_core::DictionaryProof, right: blot_check_core::DictionaryProof) -> bool {
    match left {
        selected l => { match right { selected r => { return l.value == r.value; }, _ => { return false; }, } },
        given l => { match right { given r => { return blot_structural::equal(l.value, r.value); }, _ => { return false; }, } },
    }
}
fn blot_structural::hash<S>(sink: S&, value: blot_check_core::DictionaryProof) {
    match value {
        selected v => { blot_structural::hash(sink, 0 as u8); blot_structural::hash(sink, v.value); },
        given v => { blot_structural::hash(sink, 1 as u8); blot_structural::hash(sink, v.value); },
    }
}

struct TypesStampView {
    nodes: blot_check_types::Node[:],
    extra: blot_check_types::Id[:],
    effects: EffectRows = EffectRows {},
    operations: blot_check_types::Operation[:] = [],
    quantifier_goals: blot_check_types::QuantifierGoals[:] = [],
    quantifier_obligations: blot_check_types::Obligation[:] = []
}
fn typesStampView(self: const Types&) -> TypesStampView {
    return TypesStampView { self.nodes, self.extra, self.effects, self.operations, self.quantifier_goals, self.quantifier_obligations };
}

struct StampView {
    has_rank_contracts: bool = false,
    has_usage_contracts: bool = false,
    has_numeric_proofs: bool = false,
    proof_contracts: ProofContract[:] = [],
    capability_contracts: blot_check_capability_contracts::Collection = blot_check_capability_contracts::Collection {},
    field_names: FieldName[:] = [],
    runtime_names: RuntimeName[:] = [],
    source_names: RuntimeName[:] = [],
    declaration_dependencies: DeclarationDependencies[:] = [],
    dependency_references: BindingRef[:] = [],
    dependency_members: DependencyMember[:] = [],
    erased_declaration_references: ErasedDeclarationReference[:] = [],
    request_loops: RequestLoopInfo[:] = [],
    request_arms: RequestArm[:] = [],
    tag_calls: Id[:] = [],
    unit: u32 = 0,
    types: TypesStampView,
    nodes: Node[:],
    spans: Span[:],
    extra: Id[:],
    bindings: Binding[:],
    bodies: Body[:],
    parameters: Parameter[:],
    references: BindingRef[:],
    calls: CallInfo[:],
    merges: Merge[:],
    merge_ranges: List[:],
    names: u8[:],
    obligations: Obligation[:],
    nominals: Nominal[:] = [],
    operation_names: OperationName[:] = [],
    constructors: Constructor[:] = [],
    projections: Projection[:] = [],
    projection_variants: ProjectionVariant[:] = [],
    patterns: Pattern[:] = [],
    pattern_rows: PatternRow[:] = [],
    match_arms: MatchArm[:] = [],
    matches: MatchInfo[:] = [],
    updates: UpdateInfo[:] = [],
    update_steps: UpdateStep[:] = [],
    closures: ClosureInfo[:] = [],
    associated: Associated[:] = [],
    contracts: Contract[:] = [],
    contract_members: ContractMember[:] = [],
    implementations: Implementation[:] = [],
    implementation_members: ImplementationMember[:] = [],
    member_templates: MemberTemplate[:] = [],
    selected_proofs: SelectedProof[:] = [],
    selected_members: ImplementationMember[:] = [],
    selected_edges: u32[:] = [],
    selected_uses: SelectedUse[:] = [],
    dictionary_selections: DictionarySelection[:] = [],
    dictionary_uses: DictionaryUse[:] = [],
    primitives: Primitive[:] = [],
    loops: LoopInfo[:] = [],
    loop_carries: LoopCarry[:] = [],
    resolver_ops: ResolverInfo[:] = [],
    operation_values: OperationValue[:] = [],
    handle_effects: HandleEffects[:] = [],
    dispatch_signatures: blot_check_types::Id[:] = [],
    diagnostics: Diagnostic[:],
    body_lowerings: i64
}
fn stampView(self: const Module&) -> StampView {
    return StampView { self.has_rank_contracts, self.has_usage_contracts, self.has_numeric_proofs, self.proof_contracts, self.capability_contracts, self.field_names, self.runtime_names, self.source_names, self.declaration_dependencies, self.dependency_references, self.dependency_members, self.erased_declaration_references, self.request_loops, self.request_arms, self.tag_calls, self.unit, typesStampView(self.types), self.nodes, self.spans, self.extra, self.bindings, self.bodies, self.parameters, self.references, self.calls, self.merges, self.merge_ranges, self.names, self.obligations, self.nominals, self.operation_names, self.constructors, self.projections, self.projection_variants, self.patterns, self.pattern_rows, self.match_arms, self.matches, self.updates, self.update_steps, self.closures, self.associated, self.contracts, self.contract_members, self.implementations, self.implementation_members, self.member_templates, self.selected_proofs, self.selected_members, self.selected_edges, self.selected_uses, self.dictionary_selections, self.dictionary_uses, self.primitives, self.loops, self.loop_carries, self.resolver_ops, self.operation_values, self.handle_effects, self.dispatch_signatures, self.diagnostics, self.body_lowerings };
}

type ImplementationMemberKind = blot_reuse_principal_interface::ImplementationMemberKind;
type ContractMemberKind = blot_reuse_principal_interface::ContractMemberKind;

type SelectedProofKind = blot_reuse_principal_interface::SelectedProofKind;
// Named binding classification is shared by all immutable consumers.
type BindingKind = blot_check_check::Kind;
