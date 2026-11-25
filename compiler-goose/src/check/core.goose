// Immutable typed Core. All slices borrow lexical compilation owners.
namespace blot_check_core;
import backend.collection_ops;
import backend.opaque_storage;
import check.capability_flow;
import check.check_packet_owner;
import check.effects;
import check.types;
import parse.ast;
import reuse.principal_interface;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
import std;
import support.native;
struct List {
    start: u32 = 0,
    len: u32 = 0
}
struct BindingRef {
    unit: u32 = 0,
    binding: BindingId
}
fn hash(value: BindingRef) -> u64 { return ::hash_combine(::hash(value.unit), ::hash(value.binding)); }
struct Name {
    start: u32 = 0,
    len: u32 = 0
}
struct FieldName {
    symbol: u32,
    spelling: Name
}
enum Tag { invalid, constant, reference, scalar, logical, call, if_value, block_, suite, bind, return_, if_stmt, product, record, construct, project, match_, pattern_bind, update, array, array_op, closure, apply, constructor_function, associated, primitive_function, panic, loop_, break_, type_same, result_associated, type_constructor, operation_value, effect_provider, state_provider, handle, effect_reflection, contract_method, staging, storage, fork_, with_handle, comptime_for, comptime_if, comptime_meta, spark, flat_op }
let flat_op_encode: u32 = 0;
let flat_op_decode: u32 = 1;
let flat_op_schema_hash: u32 = 2;
let flat_op_kernel_id: u32 = 3;
let flat_op_kernel_binding_hash: u32 = 4;
let flat_op_kernel_ctx_hash: u32 = 5;
let flat_op_kernel_io_hash: u32 = 6;
let flat_op_kernel_handle: u32 = 7;
let flat_op_process_handle: u32 = 8;
enum PrimitiveKind { scalar, array }
struct Primitive {
    kind: PrimitiveKind,
    op: Op = Op.none,
    array_op: ArrayOp = blot_backend_collection_ops::Op.length,
    arity: u8
}
enum Op { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right, and_, or_, neg, abs, ceil, floor, trunc, sqrt, convert_u32_f32, convert_f32_u32, shift_right_signed, min, max, bit_not, bit_andnot, any_true, all_true, select, shuffle, swizzle, broadcast, bits, from_bits, relaxed_madd, relaxed_nmadd, convert_i32_f32, convert_f32_i32, continue_, not_ }
// bind: a = the name's binding, b = its value, c = 1 when `:=` rebinds it.
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
    capability_parameters: blot_check_capability_flow::Parameters = blot_check_capability_flow::Parameters {..},
    private: bool = false,
    initializer: Id = 0,
    kind: blot_check_check::Kind,
    ty: blot_check_types::Id,
    scheme: blot_check_types::Scheme,
    public_variables: blot_check_types::List = blot_check_types::List {..},
    public_rows: blot_check_types::List = blot_check_types::List {..},
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
    references: List = List {..},
    members: List = List {..},
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
    parameters: List = List {..},
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..},
    closed_rows: blot_check_types::List = blot_check_types::List {..},
    span: Span = Span { start: 0, end: 0 , ..},
    declaration_name: Name = Name {..},
    export_name: Name = Name {..},
    exported: bool = false,
    runtime: bool = false,
    is_function: bool = false,
    is_kernel: bool = false,
    test_kind: u8 = 0,
    test_name: Name = Name {..},
    test_line: u32 = 0
}
struct CallInfo {
    target: BindingRef,
    callee_type: blot_check_types::Id,
    // Bit i: the callee takes over its parameter i (`own`).
    own: u32 = 0
}
struct Call {
    target: BindingRef,
    callee_type: blot_check_types::Id,
    arguments: const Id[:],
    own: u32 = 0
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
    identity: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { unit: 0, decl: 0 , ..},
    explicit: bool = false,
    qualification_span: blot_support::Option<Span>   = blot_support::Option<Span> { false, default<Span>() , ..},
    qualification_unit: u32 = 0,
    diagnostic_name: Name = Name {..}
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
    storage: blot_backend_opaque_storage::Storage = blot_backend_opaque_storage::Storage {..},
    diagnostic_name: Name = Name {..},
    diagnostic_origin: Name = Name {..},
    identity: blot_check_types::NominalIdentity,
    parameters: blot_check_types::List,
    variables: blot_check_types::List,
    constructors: List
}
struct OperationName {
    identity: blot_check_types::NominalIdentity,
    diagnostic_name: Name = Name {..},
    diagnostic_origin: Name = Name {..},
    variables: blot_check_types::List = blot_check_types::List {..},
    parameters: blot_check_types::List = blot_check_types::List {..},
    parameter: blot_check_types::Id = 0,
    result: blot_check_types::Id = 0
}
struct Constructor {
    identity: blot_check_types::NominalIdentity,
    nominal: u32,
    tag: u32,
    scheme: blot_check_types::Scheme,
    payload: blot_check_types::Id,
    name: u32 = 0
}
struct TypeTag {
    nominal: blot_check_types::NominalIdentity,
    constructor_tag: u32 = 0,
    field_name: u32 = 0,
    has_default: bool = false,
    value: Id = 0,
    ty: blot_check_types::Id = 0
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
    span: Span = Span { start: 0, end: 0 , ..}
}
struct PatternRow {
    patterns: List
}
struct MatchArm {
    rows: List,
    guard_: Id = 0,
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
    selectors: List = List {..}
}
struct ClosureInfo {
    qualifier: BindingId = 0,
    body: Id,
    parameter: Parameter,
    captures: List,
    function_type: blot_check_types::Id = 0,
    closed_rows: blot_check_types::List = blot_check_types::List {..}
}
struct OperationValue {
    identity: blot_check_types::NominalIdentity,
    arguments: blot_check_types::List,
    signature: blot_check_types::Id,
    witness: Id = 0,
    witness_result: blot_check_types::Id = 0,
    instance: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { unit: 0, decl: 0 , ..},
    capability: Id = 0
}
struct HandleEffects {
    node: Id,
    first: blot_check_types::Id,
    second: blot_check_types::Id = 0,
    extended: blot_check_effects::Id,
    residual: blot_check_effects::Id
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
    carries: List = List {..},
    can_exit: bool = false
}
struct SparkInfo {
    is_range: bool = false,
    source: Id = 0,
    end: Id = 0,
    pattern: PatternId = 0,
    body: Id = 0,
    captures: List = List {..}
}
struct KernelDecl {
    name: Name = Name {..},
    binding: BindingId = 0,
    has_context: bool = false,
    prepare_target: BindingRef = BindingRef { binding: 0, .. },
    run_target: BindingRef = BindingRef { binding: 0, .. },
    ctx_type: blot_check_types::Id = 0,
    prepared_type: blot_check_types::Id = 0,
    item_type: blot_check_types::Id = 0,
    out_type: blot_check_types::Id = 0,
    span: Span = Span { start: 0, end: 0, .. }
}
struct ProcessDecl {
    name: Name = Name {..},
    binding: BindingId = 0,
    init_target: BindingRef = BindingRef { binding: 0, .. },
    step_target: BindingRef = BindingRef { binding: 0, .. },
    config_type: blot_check_types::Id = 0,
    state_type: blot_check_types::Id = 0,
    cmd_type: blot_check_types::Id = 0,
    reply_type: blot_check_types::Id = 0,
    span: Span = Span { start: 0, end: 0, .. }
}
enum Code { unchecked, unsupported, unresolved_binding, invalid_call, complexity, aliased_update, spent_value, own_argument, own_function_value, result_not_owned, lent_result_value, kept_value }
struct Diagnostic {
    code: Code,
    span: Span
}
struct EffectRows {
    rows: const blot_check_effects::Row[:] = default<const blot_check_effects::Row[:]>(),
    labels: const blot_check_effects::Label[:] = default<const blot_check_effects::Label[:]>(),
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
    row_parameter_names: blot_check_types::List = blot_check_types::List {..},
    row_parameters: blot_check_types::List = blot_check_types::List {..}
}
struct Types {
    owner_id: u64 = 0,
    nodes: const blot_check_types::Node[:],
    extra: const blot_check_types::Id[:],
    effects: EffectRows = EffectRows {..},
    operations: const blot_check_types::Operation[:] = default<const blot_check_types::Operation[:]>(),
}
fn emptyTypes()->Types {return Types{nodes:default<const blot_check_types::Node[:]>(),extra:default<const blot_check_types::Id[:]>(), ..};}
struct Module {
    owner_id: u64 = 0,
    field_names: FieldName[:] = default<FieldName[:]>(),
    runtime_names: RuntimeName[:] = default<RuntimeName[:]>(),
    source_names: RuntimeName[:] = default<RuntimeName[:]>(),
    declaration_dependencies: DeclarationDependencies[:] = default<DeclarationDependencies[:]>(),
    dependency_references: BindingRef[:] = default<BindingRef[:]>(),
    dependency_members: DependencyMember[:] = default<DependencyMember[:]>(),
    erased_declaration_references: ErasedDeclarationReference[:] = default<ErasedDeclarationReference[:]>(),
    tag_calls: Id[:] = default<Id[:]>(),
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
    nominals: Nominal[:] = default<Nominal[:]>(),
    operation_names: OperationName[:] = default<OperationName[:]>(),
    constructors: Constructor[:] = default<Constructor[:]>(),
    projections: Projection[:] = default<Projection[:]>(),
    projection_variants: ProjectionVariant[:] = default<ProjectionVariant[:]>(),
    patterns: Pattern[:] = default<Pattern[:]>(),
    pattern_rows: PatternRow[:] = default<PatternRow[:]>(),
    match_arms: MatchArm[:] = default<MatchArm[:]>(),
    matches: MatchInfo[:] = default<MatchInfo[:]>(),
    updates: UpdateInfo[:] = default<UpdateInfo[:]>(),
    update_steps: UpdateStep[:] = default<UpdateStep[:]>(),
    closures: ClosureInfo[:] = default<ClosureInfo[:]>(),
    associated: Associated[:] = default<Associated[:]>(),
    contracts: Contract[:] = default<Contract[:]>(),
    contract_members: ContractMember[:] = default<ContractMember[:]>(),
    implementations: Implementation[:] = default<Implementation[:]>(),
    implementation_members: ImplementationMember[:] = default<ImplementationMember[:]>(),
    member_templates: MemberTemplate[:] = default<MemberTemplate[:]>(),
    primitives: Primitive[:] = default<Primitive[:]>(),
    loops: LoopInfo[:] = default<LoopInfo[:]>(),
    loop_carries: LoopCarry[:] = default<LoopCarry[:]>(),
    operation_values: OperationValue[:] = default<OperationValue[:]>(),
    handle_effects: HandleEffects[:] = default<HandleEffects[:]>(),
    dispatch_signatures: blot_check_types::Id[:] = default<blot_check_types::Id[:]>(),
    type_tags: TypeTag[:] = default<TypeTag[:]>(),
    sparks: SparkInfo[:] = default<SparkInfo[:]>(),
    kernels: KernelDecl[:] = default<KernelDecl[:]>(),
    processes: ProcessDecl[:] = default<ProcessDecl[:]>(),
    diagnostics: Diagnostic[:],
    body_lowerings: i64
}
type Id = u32;
type BindingId = u32;
type BodyId = u32;
type PatternId = u32;
type Span = blot_parse_ast::Span;
type ArrayOp = blot_backend_collection_ops::Op;
type ContractMember = blot_reuse_principal_interface::ContractMember;
type Implementation = blot_reuse_principal_interface::Implementation;
type ImplementationMember = blot_reuse_principal_interface::ImplementationMember;
type MemberTemplate = blot_reuse_principal_interface::MemberTemplate;
fn message(self_: Diagnostic) -> const u8[:] {
    match self_.code {
        unchecked => { return "Typed core requires successful semantic checking"; },
        unsupported => { return "This checked form is not implemented in the typed core"; },
        unresolved_binding => { return "Typed expression has no resolved binding identity"; },
        invalid_call => { return "Typed core requires a resolved named call or compiler primitive"; },
        complexity => { return "Typed core exceeds its nesting or table limit"; },
        aliased_update => { return "This := writes through storage that something else may still observe; take values.copy first to keep the old value, or end earlier borrows before updating"; },
        spent_value => { return "This value was given away, to an `own` parameter or into the function's result, so it is no longer this name's; use what the call returned, or give away values.copy of it to keep this one"; },
        own_argument => { return "An `own` parameter takes a value that nothing else holds: a fresh value, or a local that alone holds it and, inside a loop, was bound in the same iteration; pass values.copy of it otherwise"; },
        result_not_owned => { return "A function's result belongs to its caller alone, so it must be a fresh value or a local that alone holds its value; return values.copy of it, or take the parameter it comes from with `own`"; },
        lent_result_value => { return "This function may return what it was lent or still holds, which here holds an array, so it cannot be used as a value or partly applied: give it all its arguments in one call, or pass a function that copies the result"; },
        kept_value => { return "What is stored here is kept by something this function does not own, so it must be a value nothing else holds: store values.copy of it, or take the parameter it comes from with `own`"; },
        own_function_value => { return "A function that takes over a parameter must be given all its arguments in one call; given only some, it would hold that value for any number of calls"; },
    }
}
fn node(self_: const EffectRows&, id: blot_check_effects::Id) -> blot_check_effects::Row {
    if id == 0 && self_.rows.len == 0 { return blot_check_effects::Row {..}; }
    return self_.rows[id];
}
fn list(self_: const EffectRows&, span: blot_check_effects::List) -> const blot_check_effects::Label[:] { return self_.labels[span.start..span.start + span.len]; }
fn node(self_: const Types&, id: blot_check_types::Id) -> blot_check_types::Node { return self_.nodes[id]; }
fn withoutForall(self_: const Types&, id: blot_check_types::Id) -> blot_check_types::Id, blot_error::Error {
    var current = id; var depth: i64 = 0;
    while self_.node(current).tag == blot_check_types::Tag.forall || self_.node(current).tag == blot_check_types::Tag.usage {
        if depth == 128 { return 0, blot_error::Error.core_limit; }
        depth += 1; current = self_.node(current).a;
    }
    return current, blot_error::Error.none;
}
fn head(self_: const Types&, id: blot_check_types::Id, at: blot_check_types::Cursor) -> blot_check_types::Id { return id; }
fn list(self_: const Types&, span: blot_check_types::List) -> const blot_check_types::Id[:] { return self_.extra[span.start..span.start + span.len]; }
fn projectionMember(self_: const Types&, value: blot_check_types::Node) -> u32 { return self_.extra[value.c + 1 + self_.extra[value.c]]; }
fn nominalArguments(self_: const Types&, value: blot_check_types::Node) -> const blot_check_types::Id[:] {
    assert(value.tag == blot_check_types::Tag.nominal || value.tag == blot_check_types::Tag.projection || value.tag == blot_check_types::Tag.instance_selection);
    return self_.extra[value.c + 1..value.c + 1 + self_.extra[value.c]];
}
fn recordField(self_: const Types&, value: blot_check_types::Node, index: i64) -> blot_check_types::Field {
    assert(value.tag == blot_check_types::Tag.record && index < value.b);
    return blot_check_types::Field { self_.extra[value.a + index * 2], self_.extra[value.a + index * 2 + 1] , ..};
}
fn row(self_: const Types&, id: blot_check_effects::Id) -> blot_check_effects::Row { return self_.effects.node(id); }
fn rowLabels(self_: const Types&, id: blot_check_effects::Id) -> const blot_check_effects::Label[:] { return self_.effects.list(self_.row(id).labels); }
fn operation(self_: const Types&, label: blot_check_effects::Label) -> blot_check_types::Operation { return self_.operations[label]; }
fn operationArguments(self_: const Types&, label: blot_check_effects::Label) -> const blot_check_types::Id[:] { return self_.list(self_.operation(label).arguments); }
fn node(self_: const Module&, id: Id) -> Node { return self_.nodes[id]; }
fn span(self_: const Module&, id: Id) -> Span { return self_.spans[id]; }
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
fn sourceNamePoint(self_: const Module&, binding_id: BindingId) -> u32 {
    let point, found = namePoint(self_.source_names, binding_id);
    if found { return point; }
    return self_.binding(binding_id).span.start;
}
fn runtimeNamePoint(self_: const Module&, binding_id: BindingId) -> u32 {
    let point, found = namePoint(self_.runtime_names, binding_id);
    if found { return point; }
    return self_.binding(binding_id).span.start;
}
fn isTagCall(self_: const Module&, id: Id) -> bool {
    var low: i64 = 0; var high = self_.tag_calls.len;
    while low < high {
        let middle = low + (high - low) / 2; let value = self_.tag_calls[middle];
        if value < id { low = middle + 1; } else if value > id { high = middle; } else { return true; }
    }
    return false;
}
fn typeOf(self_: const Module&, id: Id) -> blot_check_types::Id { return self_.nodes[id].ty; }
fn operationValue(self_: const Module&, id: Id) -> OperationValue {
    assert(self_.node(id).tag == Tag.operation_value); return self_.operation_values[self_.node(id).a];
}
fn operationValueArguments(self_: const Module&, id: Id) -> const blot_check_types::Id[:] { return self_.types.list(self_.operationValue(id).arguments); }
fn handleEffects(self_: const Module&, id: Id) -> blot_support::Option<HandleEffects> {
    let value = self_.node(id); assert(value.tag == Tag.handle);
    if value.c == 0 { return blot_support::Option<HandleEffects> { false, default<HandleEffects>() , ..}; }
    return blot_support::Option<HandleEffects> { true, self_.handle_effects[value.c - 1] , ..};
}
fn dispatchSignature(self_: const Module&, id: Id) -> blot_check_types::Id {
    if self_.dispatch_signatures.len == 0 { return 0; } return self_.dispatch_signatures[id];
}
fn children(self_: const Module&, id: Id) -> const Id[:] {
    let value = self_.node(id);
    match value.tag {
        block_, suite, product, record, array, array_op, storage => { return self_.extra[value.a..value.a + value.b]; },
        call, contract_method, break_, with_handle => { return self_.extra[value.b..value.b + value.c]; },
        _ => { return self_.extra[..0]; },
    }
}
fn call(self_: const Module&, id: Id) -> Call {
    let value = self_.node(id); assert(value.tag == Tag.call); let target = self_.calls[value.a];
    return Call { target.target, target.callee_type, self_.children(id), target.own, ..};
}
fn reference(self_: const Module&, id: Id) -> BindingRef { assert(self_.node(id).tag == Tag.reference); return self_.references[self_.node(id).a]; }
fn binding(self_: const Module&, id: BindingId) -> Binding { return self_.bindings[id]; }
fn body(self_: const Module&, id: BindingId) -> const Body? {
    let body_id = self_.bindings[id].body_id; if body_id == 0 { return null; } return self_.bodies[body_id];
}
fn bodyParameters(self_: const Module&, value: const Body&) -> const Parameter[:] { return self_.parameters[value.parameters.start..value.parameters.start + value.parameters.len]; }
fn branchMerges(self_: const Module&, id: Id) -> const Merge[:] { let range = self_.merge_ranges[id]; return self_.merges[range.start..range.start + range.len]; }
fn loopInfo(self_: const Module&, id: Id) -> LoopInfo { let value = self_.node(id); assert(value.tag == Tag.loop_); return self_.loops[value.a]; }
fn loopCarries(self_: const Module&, id: Id) -> const LoopCarry[:] { let range = self_.loopInfo(id).carries; return self_.loop_carries[range.start..range.start + range.len]; }
fn sparkInfo(self_: const Module&, id: Id) -> SparkInfo { let value = self_.node(id); assert(value.tag == Tag.spark); return self_.sparks[value.a]; }
fn sparkCaptures(self_: const Module&, id: Id) -> const BindingId[:] { let range = self_.sparkInfo(id).captures; return self_.extra[range.start..range.start + range.len]; }
fn breakValues(self_: const Module&, id: Id) -> const Id[:] { assert(self_.node(id).tag == Tag.break_); return self_.children(id); }
fn name(self_: const Module&, range: Name) -> const u8[:] { return self_.names[range.start..range.start + range.len]; }
fn fieldSpelling(self_: const Module&, symbol: u32) -> blot_support::Option<const u8[:]> {
    var low: i64 = 0; var high = self_.field_names.len;
    while low < high {
        let middle = low + (high - low) / 2; let value = self_.field_names[middle];
        if value.symbol < symbol { low = middle + 1; } else if value.symbol > symbol { high = middle; }
        else { return blot_support::some<const u8[:]>(self_.name(value.spelling)); }
    }
    return blot_support::none<const u8[:]>();
}
fn nominal(self_: const Module&, index: u32) -> Nominal { return self_.nominals[index]; }
fn nominalConstructors(self_: const Module&, index: u32) -> const u32[:] { let range = self_.nominals[index].constructors; return self_.extra[range.start..range.start + range.len]; }
fn constructor(self_: const Module&, index: u32) -> Constructor { return self_.constructors[index]; }
fn recordDestinations(self_: const Module&, id: Id) -> const u32[:] { let value = self_.node(id); assert(value.tag == Tag.record); return self_.extra[value.c..value.c + value.b]; }
fn projection(self_: const Module&, index: u32) -> Projection { return self_.projections[index]; }
fn projectionVariants(self_: const Module&, index: u32) -> const ProjectionVariant[:] { let range = self_.projections[index].variants; return self_.projection_variants[range.start..range.start + range.len]; }
fn pattern(self_: const Module&, id: PatternId) -> Pattern { return self_.patterns[id]; }
fn patternChildren(self_: const Module&, id: PatternId) -> const PatternId[:] { let value = self_.pattern(id); assert(value.tag == PatternTag.product); return self_.extra[value.a..value.a + value.b]; }
fn matchInfo(self_: const Module&, id: Id) -> MatchInfo { let value = self_.node(id); assert(value.tag == Tag.match_); return self_.matches[value.a]; }
fn matchInputs(self_: const Module&, id: Id) -> const Id[:] { let range = self_.matchInfo(id).inputs; return self_.extra[range.start..range.start + range.len]; }
fn matchArms(self_: const Module&, id: Id) -> const MatchArm[:] { let range = self_.matchInfo(id).arms; return self_.match_arms[range.start..range.start + range.len]; }
fn armRows(self_: const Module&, arm: MatchArm) -> const PatternRow[:] { return self_.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len]; }
fn rowPatterns(self_: const Module&, row: PatternRow) -> const PatternId[:] { return self_.extra[row.patterns.start..row.patterns.start + row.patterns.len]; }
fn updateInfo(self_: const Module&, id: Id) -> UpdateInfo { let value = self_.node(id); assert(value.tag == Tag.update); return self_.updates[value.a]; }
fn updatePath(self_: const Module&, id: Id) -> const u32[:] { let range = self_.updateInfo(id).path; return self_.extra[range.start..range.start + range.len]; }
fn updateSelectors(self_: const Module&, id: Id) -> const UpdateStep[:] { let range = self_.updateInfo(id).selectors; return self_.update_steps[range.start..range.start + range.len]; }
fn arrayOperation(self_: const Module&, id: Id) -> ArrayOp {
    let value = self_.node(id); assert(value.tag == Tag.array_op);
    let operation, error = blot_backend_collection_ops::opFromCode(value.c);
    assert(error == blot_error::Error.none); return operation;
}
fn closure(self_: const Module&, id: Id) -> ClosureInfo { let value = self_.node(id); assert(value.tag == Tag.closure); return self_.closures[value.a]; }
fn closureCaptures(self_: const Module&, id: Id) -> const BindingId[:] { let range = self_.closure(id).captures; return self_.extra[range.start..range.start + range.len]; }
fn primitive(self_: const Module&, id: Id) -> Primitive { let value = self_.node(id); assert(value.tag == Tag.primitive_function); return self_.primitives[value.a]; }
fn panicMessage(self_: const Module&, id: Id) -> const u8[:] { let value = self_.node(id); assert(value.tag == Tag.panic); return self_.name(Name { value.a, value.b , ..}); }

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
        operation_value => { return 32; },
        effect_provider => { return 33; },
        state_provider => { return 34; },
        handle => { return 35; },
        effect_reflection => { return 36; },
        contract_method => { return 37; },
        staging => { return 38; },
        storage => { return 39; },
        fork_ => { return 40; },
        with_handle => { return 41; },
        comptime_for => { return 42; },
        comptime_if => { return 43; },
        comptime_meta => { return 44; },
        spark => { return 45; },
        flat_op => { return 46; },
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
        32 => { return Tag.operation_value, blot_error::Error.none; },
        33 => { return Tag.effect_provider, blot_error::Error.none; },
        34 => { return Tag.state_provider, blot_error::Error.none; },
        35 => { return Tag.handle, blot_error::Error.none; },
        36 => { return Tag.effect_reflection, blot_error::Error.none; },
        37 => { return Tag.contract_method, blot_error::Error.none; },
        38 => { return Tag.staging, blot_error::Error.none; },
        39 => { return Tag.storage, blot_error::Error.none; },
        40 => { return Tag.fork_, blot_error::Error.none; },
        41 => { return Tag.with_handle, blot_error::Error.none; },
        42 => { return Tag.comptime_for, blot_error::Error.none; },
        43 => { return Tag.comptime_if, blot_error::Error.none; },
        44 => { return Tag.comptime_meta, blot_error::Error.none; },
        45 => { return Tag.spark, blot_error::Error.none; },
        46 => { return Tag.flat_op, blot_error::Error.none; },
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
        not_ => { return 45; },
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
        45 => { return Op.not_, blot_error::Error.none; },
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
        aliased_update => { return 5; },
        spent_value => { return 6; },
        own_argument => { return 7; },
        own_function_value => { return 8; },
        result_not_owned => { return 9; },
        lent_result_value => { return 10; },
        kept_value => { return 11; },
    }
}
fn codeFromCode(code: u32) -> Code, blot_error::Error {
    match code {
        0 => { return Code.unchecked, blot_error::Error.none; },
        1 => { return Code.unsupported, blot_error::Error.none; },
        2 => { return Code.unresolved_binding, blot_error::Error.none; },
        3 => { return Code.invalid_call, blot_error::Error.none; },
        4 => { return Code.complexity, blot_error::Error.none; },
        5 => { return Code.aliased_update, blot_error::Error.none; },
        6 => { return Code.spent_value, blot_error::Error.none; },
        7 => { return Code.own_argument, blot_error::Error.none; },
        8 => { return Code.own_function_value, blot_error::Error.none; },
        9 => { return Code.result_not_owned, blot_error::Error.none; },
        10 => { return Code.lent_result_value, blot_error::Error.none; },
        11 => { return Code.kept_value, blot_error::Error.none; },
        _ => { return Code.unchecked, blot_error::Error.core_limit; },
    }
}

fn deinit(self_: Module&) {
    self_.field_names = default<blot_check_core::FieldName[:]>();
    self_.runtime_names = default<blot_check_core::RuntimeName[:]>();
    self_.source_names = default<blot_check_core::RuntimeName[:]>();
    self_.declaration_dependencies = default<blot_check_core::DeclarationDependencies[:]>();
    self_.dependency_references = default<blot_check_core::BindingRef[:]>();
    self_.dependency_members = default<blot_check_core::DependencyMember[:]>();
    self_.erased_declaration_references = default<blot_check_core::ErasedDeclarationReference[:]>();
    self_.tag_calls = default<blot_check_core::Id[:]>();
    self_.nodes = default<blot_check_core::Node[:]>();
    self_.spans = default<blot_check_core::Span[:]>();
    self_.extra = default<blot_check_core::Id[:]>();
    self_.bindings = default<blot_check_core::Binding[:]>();
    self_.bodies = default<blot_check_core::Body[:]>();
    self_.parameters = default<blot_check_core::Parameter[:]>();
    self_.references = default<blot_check_core::BindingRef[:]>();
    self_.calls = default<blot_check_core::CallInfo[:]>();
    self_.merges = default<blot_check_core::Merge[:]>();
    self_.merge_ranges = default<blot_check_core::List[:]>();
    self_.names = default<u8[:]>();
    self_.obligations = default<blot_check_core::Obligation[:]>();
    self_.nominals = default<blot_check_core::Nominal[:]>();
    self_.operation_names = default<blot_check_core::OperationName[:]>();
    self_.constructors = default<blot_check_core::Constructor[:]>();
    self_.projections = default<blot_check_core::Projection[:]>();
    self_.projection_variants = default<blot_check_core::ProjectionVariant[:]>();
    self_.patterns = default<blot_check_core::Pattern[:]>();
    self_.pattern_rows = default<blot_check_core::PatternRow[:]>();
    self_.match_arms = default<blot_check_core::MatchArm[:]>();
    self_.matches = default<blot_check_core::MatchInfo[:]>();
    self_.updates = default<blot_check_core::UpdateInfo[:]>();
    self_.update_steps = default<blot_check_core::UpdateStep[:]>();
    self_.closures = default<blot_check_core::ClosureInfo[:]>();
    self_.associated = default<blot_check_core::Associated[:]>();
    self_.contracts = default<blot_check_core::Contract[:]>();
    self_.contract_members = default<blot_check_core::ContractMember[:]>();
    self_.implementations = default<blot_check_core::Implementation[:]>();
    self_.implementation_members = default<blot_check_core::ImplementationMember[:]>();
    self_.member_templates = default<blot_check_core::MemberTemplate[:]>();
    self_.primitives = default<blot_check_core::Primitive[:]>();
    self_.loops = default<blot_check_core::LoopInfo[:]>();
    self_.loop_carries = default<blot_check_core::LoopCarry[:]>();
    self_.operation_values = default<blot_check_core::OperationValue[:]>();
    self_.handle_effects = default<blot_check_core::HandleEffects[:]>();
    self_.dispatch_signatures = default<blot_check_types::Id[:]>();
    self_.type_tags = default<blot_check_core::TypeTag[:]>();
    self_.sparks = default<blot_check_core::SparkInfo[:]>();
    self_.kernels = default<blot_check_core::KernelDecl[:]>();
    self_.processes = default<blot_check_core::ProcessDecl[:]>();
    self_.diagnostics = default<blot_check_core::Diagnostic[:]>();
    self_.types.nodes = default<const blot_check_types::Node[:]>(); self_.types.extra = default<const blot_check_types::Id[:]>(); self_.types.effects.rows = default<const blot_check_effects::Row[:]>(); self_.types.effects.labels = default<const blot_check_effects::Label[:]>();
    self_.types.operations = default<const blot_check_types::Operation[:]>();
    self_.owner_id = 0; self_.types.owner_id = 0;
}


fn blot_structural::equal(left: blot_check_core::Tag, right: blot_check_core::Tag) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::Tag,sink: S&) { blot_structural::hash(sink, blot_check_core::tagCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::PrimitiveKind, right: blot_check_core::PrimitiveKind) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::PrimitiveKind,sink: S&) { blot_structural::hash(sink, blot_check_core::primitiveKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::Op, right: blot_check_core::Op) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::Op,sink: S&) { blot_structural::hash(sink, blot_check_core::opCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::PatternTag, right: blot_check_core::PatternTag) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::PatternTag,sink: S&) { blot_structural::hash(sink, blot_check_core::patternTagCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::UpdateKind, right: blot_check_core::UpdateKind) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::UpdateKind,sink: S&) { blot_structural::hash(sink, blot_check_core::updateKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::LoopKind, right: blot_check_core::LoopKind) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::LoopKind,sink: S&) { blot_structural::hash(sink, blot_check_core::loopKindCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_core::Code, right: blot_check_core::Code) -> bool { return left == right; }
fn blot_check_core::blotStructuralHash<S>(value: blot_check_core::Code,sink: S&) { blot_structural::hash(sink, blot_check_core::codeCode(value) as! u8); }

struct TypesStampView {
    nodes: const blot_check_types::Node[:],
    extra: const blot_check_types::Id[:],
    effects: EffectRows = EffectRows {..},
    operations: const blot_check_types::Operation[:] = default<const blot_check_types::Operation[:]>(),
}
fn typesStampView(self_: const Types&) -> TypesStampView {
    return TypesStampView { self_.nodes, self_.extra, self_.effects, self_.operations , ..};
}

struct StampView {
    field_names: const FieldName[:] = default<const FieldName[:]>(),
    runtime_names: const RuntimeName[:] = default<const RuntimeName[:]>(),
    source_names: const RuntimeName[:] = default<const RuntimeName[:]>(),
    declaration_dependencies: const DeclarationDependencies[:] = default<const DeclarationDependencies[:]>(),
    dependency_references: const BindingRef[:] = default<const BindingRef[:]>(),
    dependency_members: const DependencyMember[:] = default<const DependencyMember[:]>(),
    erased_declaration_references: const ErasedDeclarationReference[:] = default<const ErasedDeclarationReference[:]>(),
    tag_calls: const Id[:] = default<const Id[:]>(),
    unit: u32 = 0,
    types: TypesStampView,
    nodes: const Node[:],
    spans: const Span[:],
    extra: const Id[:],
    bindings: const Binding[:],
    bodies: const Body[:],
    parameters: const Parameter[:],
    references: const BindingRef[:],
    calls: const CallInfo[:],
    merges: const Merge[:],
    merge_ranges: const List[:],
    names: const u8[:],
    obligations: const Obligation[:],
    nominals: const Nominal[:] = default<const Nominal[:]>(),
    operation_names: const OperationName[:] = default<const OperationName[:]>(),
    constructors: const Constructor[:] = default<const Constructor[:]>(),
    projections: const Projection[:] = default<const Projection[:]>(),
    projection_variants: const ProjectionVariant[:] = default<const ProjectionVariant[:]>(),
    patterns: const Pattern[:] = default<const Pattern[:]>(),
    pattern_rows: const PatternRow[:] = default<const PatternRow[:]>(),
    match_arms: const MatchArm[:] = default<const MatchArm[:]>(),
    matches: const MatchInfo[:] = default<const MatchInfo[:]>(),
    updates: const UpdateInfo[:] = default<const UpdateInfo[:]>(),
    update_steps: const UpdateStep[:] = default<const UpdateStep[:]>(),
    closures: const ClosureInfo[:] = default<const ClosureInfo[:]>(),
    associated: const Associated[:] = default<const Associated[:]>(),
    contracts: const Contract[:] = default<const Contract[:]>(),
    contract_members: const ContractMember[:] = default<const ContractMember[:]>(),
    implementations: const Implementation[:] = default<const Implementation[:]>(),
    implementation_members: const ImplementationMember[:] = default<const ImplementationMember[:]>(),
    member_templates: const MemberTemplate[:] = default<const MemberTemplate[:]>(),
    primitives: const Primitive[:] = default<const Primitive[:]>(),
    loops: const LoopInfo[:] = default<const LoopInfo[:]>(),
    loop_carries: const LoopCarry[:] = default<const LoopCarry[:]>(),
    operation_values: const OperationValue[:] = default<const OperationValue[:]>(),
    handle_effects: const HandleEffects[:] = default<const HandleEffects[:]>(),
    dispatch_signatures: const blot_check_types::Id[:] = default<const blot_check_types::Id[:]>(),
    type_tags: const TypeTag[:] = default<const TypeTag[:]>(),
    sparks: const SparkInfo[:] = default<const SparkInfo[:]>(),
    kernels: const KernelDecl[:] = default<const KernelDecl[:]>(),
    processes: const ProcessDecl[:] = default<const ProcessDecl[:]>(),
    diagnostics: const Diagnostic[:],
    body_lowerings: i64
}
fn stampView(self_: const Module&) -> StampView {
    return StampView { self_.field_names, self_.runtime_names, self_.source_names, self_.declaration_dependencies, self_.dependency_references, self_.dependency_members, self_.erased_declaration_references, self_.tag_calls, self_.unit, typesStampView(self_.types), self_.nodes, self_.spans, self_.extra, self_.bindings, self_.bodies, self_.parameters, self_.references, self_.calls, self_.merges, self_.merge_ranges, self_.names, self_.obligations, self_.nominals, self_.operation_names, self_.constructors, self_.projections, self_.projection_variants, self_.patterns, self_.pattern_rows, self_.match_arms, self_.matches, self_.updates, self_.update_steps, self_.closures, self_.associated, self_.contracts, self_.contract_members, self_.implementations, self_.implementation_members, self_.member_templates, self_.primitives, self_.loops, self_.loop_carries, self_.operation_values, self_.handle_effects, self_.dispatch_signatures, self_.type_tags, self_.sparks, self_.kernels, self_.processes, self_.diagnostics, self_.body_lowerings , ..};
}

type ImplementationMemberKind = blot_reuse_principal_interface::ImplementationMemberKind;
type ContractMemberKind = blot_reuse_principal_interface::ContractMemberKind;

// Named binding classification is shared by all immutable consumers.
type BindingKind = blot_check_check::Kind;
