//! Immutable typed core. Source syntax, identifier strings and solver state
//! are consumed once at lowering; evaluators/code instances read only this IR.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const checked_types = @import("check.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const BindingId = u32;
pub const BodyId = u32;
pub const PatternId = u32;
pub const List = struct { start: u32 = 0, len: u32 = 0 };
pub const Span = ast.Span;
pub const BindingRef = struct { unit: u32 = 0, binding: BindingId };
pub const ProofContract = @import("numeric_proof_headers.zig").Named;
pub const Name = struct { start: u32 = 0, len: u32 = 0 };
/// Only record field spellings survive in this compact symbol projection.
/// Physical layouts use spelling, never the incidental interning order.
pub const FieldName = struct { symbol: u32, spelling: Name };
pub const Tag = enum(u8) { invalid, constant, reference, scalar, logical, call, if_value, block, suite, bind, return_, if_stmt, product, record, construct, project, match, pattern_bind, update, array, array_op, closure, apply, constructor_function, associated, primitive_function, panic, loop, break_, type_same, result_associated, suspend_, force, type_constructor, resolver_op, operation_value, effect_provider, state_provider, handle, effect_reflection, computation, request_loop, request_decision, record_merge, contract_method, effect_scope, proof_guard, package_pack, package_unpack, staging, usage_borrow, usage_read, resource_scope, usage_share, resource_acquire, resource_release, task };
pub const ArrayOp = @import("../backend/collection_ops.zig").Op;
pub const PrimitiveKind = enum(u8) { scalar, array };
pub const Primitive = struct { kind: PrimitiveKind, op: Op = .none, array_op: ArrayOp = .length, arity: u8 };
pub const Op = enum(u8) { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right, and_, or_, neg, abs, ceil, floor, trunc, sqrt, convert_u32_f32, convert_f32_u32 };
/// constant a=bits; reference a=references index; scalar a=left,b=right(0 unary),
/// c=1 for associated operator dispatch, c=0 for authoritative compiler primitives.
/// logical a=left,b=right,op=and_/or_; call a=call-info,b=args start,c=args len.
/// if_value/if_stmt a=condition,b=then,c=else(0 absent statement suite).
/// block/suite a=children start,b=len; block creates a do return boundary.
/// bind a=local BindingId,b=value; return_ a=value,b=target block Id.
/// record_merge a=left,b=right; right fields replace left fields.
/// product a=values start,b=len; record adds c=destination field-index start.
/// construct a=constructor catalog index,b=optional payload,c=1 for a canonical record argument.
/// c=0 retains the declared storage payload; project a=value,b=projection index.
/// match a=match-info index; pattern_bind a=pattern,b=value,c=exiting fallback suite.
/// update a=update-info index. Its self binding is assigned before the replacement.
/// array/array_op a=values start,b=len; array_op c=ArrayOp enum ordinal.
/// closure a=closure catalog; apply a=callee,b=one argument,c=checked per-use
/// type instance when the stored callee is universal (otherwise zero).
/// This private type edge is not admitted by frozen portable Core validation.
/// constructor_function a=catalog.
/// associated a=left,b=right,c=member Symbol; op is its standard scalar operation or none.
/// primitive_function a=primitive catalog; panic a=owned message start,b=UTF8 byte length.
/// loop a=loop catalog; break_ a=target loop Id,b=current carried-value IR start,c=len.
/// result_associated a=operand,b=member Symbol; ty supplies the expected-result owner.
/// suspend_ a=closure catalog with Unit parameter; force a=demanded value.
/// type_constructor has its exact owner in ty; resolver_op a=owned protocol catalog.
/// effect_provider a=operation,b=callback; state_provider a=read,b=write,c=initial.
/// handle a=provider,b=inner expression,c=optional HandleEffects catalog index+1.
/// proof_guard a=left,b=right,c=numeric proof Relation. Both operands evaluate
/// once in order, followed by the required trap check, even if the proof is unused.
/// package_pack a=payload,b/c=owned type witness list in Types.extra.
/// package_unpack a=package,b=lexical payload binding,c=extra[body,binders start,binders len].
/// usage_borrow a=owner,b=direct once callback,c=0 read loan or1 exclusive loan.
/// resource_acquire a=direct acquisition,b=verified cleanup,c=0; unique result.
/// resource_release a=unique owner,b=c=0; consumes owner and returns Unit.
/// usage_share a=unique operand,b=c=0; result is shared with the same payload.
/// usage_read a=loan/shared operand,b=0 scalar,1 Array length,2 List length,c=0.
/// The callback owns the lexical region binder; no live scope nonce is portable.
/// staging a=first operand,b=optional second,c=typed_staging.Op. A quote's
/// operand belongs to its future stage; it is not a runtime initializer.
pub const Node = struct { tag: Tag, op: Op = .none, ty: T.Id = 0, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
/// Keep source inference provenance after callback inputs are concretized.
pub const Parameter = struct { binding: BindingId, ty: T.Id, span: Span, inferred: bool = false };
pub const Binding = struct { capability_flow: checked_types.CapabilityFlow = .unknown, capability_parameters: @import("capability_flow.zig").Parameters = .{}, private: bool = false, initializer: Id = 0, kind: checked_types.Kind, ty: T.Id, scheme: T.Scheme, public_variables: T.List = .{}, public_rows: T.List = .{}, has_explicit: bool = false, body_id: BodyId = 0, target: BindingRef, span: Span };
pub const RuntimeName = struct { binding: BindingId, point: u32 };
/// Original declaration reads survive executable branch/value elimination.
pub const DeclarationDependencies = struct { references: List = .{}, members: List = .{}, runtime_metadata: Id = 0 };
pub const DependencyMember = struct { name: u32 = 0, operator: T.Operator = .none };
pub const ErasedDeclarationReference = struct { node: Id, target: BindingRef };
pub const Body = struct { binding: BindingId = 0, root: Id = 0, parameters: List = .{}, scheme: T.Scheme = .{}, closed_rows: T.List = .{}, span: Span = .{ .start = 0, .end = 0 }, export_name: Name = .{}, exported: bool = false, runtime: bool = false, is_function: bool = false };
pub const CallInfo = struct { target: BindingRef, callee_type: T.Id };
pub const DictionaryUse = struct { node: Id, binding: BindingId, opening: BindingId, introduction: Id = 0, quantifier: T.Id, goal: u32, member: u32 };
pub const DictionaryGiven = struct { opening: BindingId, introduction: Id = 0, quantifier: T.Id, goal: u32, arguments: T.List };
pub const DictionaryProof = union(enum) { selected: u32, given: DictionaryGiven };
pub const DictionarySelection = struct { owner: Id, quantifier: T.Id, goal: u32, proof: DictionaryProof, members: List = .{}, contents: List = .{} };
pub const Call = struct { target: BindingRef, callee_type: T.Id, arguments: []const Id };
pub const Merge = struct { node: Id, result: BindingId, then_binding: BindingId, else_binding: BindingId };
pub const Obligation = struct { ty: T.Id, kind: T.ObligationKind, span: Span, name: u32 = 0, result: T.Id = 0, other: T.Id = 0, signature: T.Id = 0, operator: T.Operator = .none, identity: T.NominalIdentity = .{ .unit = 0, .decl = 0 }, explicit: bool = false, qualification_span: ?Span = null, qualification_unit: u32 = 0, diagnostic_name: Name = .{} };
pub const Associated = struct { identity: T.NominalIdentity, member: u32, operator: T.Operator, target: BindingRef };
pub const Nominal = struct { affine: bool = false, has_usage: bool = false, closed_storage: bool = false, private: bool = false, is_opaque: bool = false, storage: @import("../backend/opaque_storage.zig").Storage = .{}, diagnostic_name: Name = .{}, diagnostic_origin: Name = .{}, identity: T.NominalIdentity, parameters: T.List, variables: T.List, constructors: List };
/// Source operation names survive frontend teardown; identities still select
/// effects independently of these owned diagnostic strings.
pub const OperationName = struct {
    identity: T.NominalIdentity,
    diagnostic_name: Name = .{},
    diagnostic_origin: Name = .{},
    /// The declaration owns this template independently of any selected use or
    /// handler callback. Variables are instantiated by the family arguments.
    variables: T.List = .{},
    parameters: T.List = .{},
    parameter: T.Id = 0,
    result: T.Id = 0,
};
pub const Constructor = struct { identity: T.NominalIdentity, nominal: u32, tag: u32, scheme: T.Scheme, payload: T.Id };
pub const ProjectionVariant = struct { tag: u32, field: u32 };
pub const Projection = struct { nominal: T.NominalIdentity, field: u32 = 0, source_type: T.Id, result_type: T.Id, variants: List, diagnostic_point: u32 = 0 };
pub const PatternTag = enum(u8) { invalid, wildcard, bind, constant, value, product, constructor, record_payload };
/// product a=canonical children start,b=len; constructor a=catalog index,b=payload pattern.
/// record_payload ty=record storage,a=field count,b=canonical child pattern.
/// bind a=BindingId; value a=existing scalar-reference IR Id; constant a=exact bits.
pub const Pattern = struct { tag: PatternTag, ty: T.Id = 0, a: u32 = 0, b: u32 = 0, c: u32 = 0, span: Span = .{ .start = 0, .end = 0 } };
pub const PatternRow = struct { patterns: List };
pub const MatchArm = struct { rows: List, guard: Id = 0, body: Id, span: Span };
/// Statement matches have two suite arms (success, fallback), whose returns
/// target the surrounding actual block. Expression arms retain their own form.
pub const MatchInfo = struct { inputs: List, arms: List, statement: bool = false };
pub const UpdateKind = enum(u8) { field, index };
/// Mixed update paths retain each index expression as owned IR. A field step
/// uses a projection catalog; an index step uses its array/element type pair.
pub const UpdateStep = struct { kind: UpdateKind, projection: u32 = 0, index: Id = 0, source_type: T.Id, result_type: T.Id };
pub const UpdateInfo = struct { root: Id, path: List, value: Id, self_binding: BindingId, selectors: List = .{} };
/// Captures name immutable lexical binding versions, in first-reference order.
/// Nested closures propagate their free local requirements to this body.
pub const ClosureInfo = struct { qualifier: BindingId = 0, body: Id, parameter: Parameter, captures: List, function_type: T.Id = 0, closed_rows: T.List = .{} };
pub const ResolverOperation = enum { monad, pure, bind, forward, iterate, run };
/// Deferred resolver operations retain the complete ordinary source method
/// signature. Bind and iterate callbacks are normal captured unary closures.
pub const ResolverInfo = struct {
    operation: ResolverOperation,
    resolver: Id,
    arguments: List = .{},
    member: u32 = 0,
    method: BindingRef = .{ .binding = 0 },
    method_type: T.Id = 0,
};
/// An operation is an ordinary callable value with an exact producer identity.
/// Its closed or principal argument types live in this module's frozen graph;
/// runtime handler selection never compares frontend-local operation labels.
pub const OperationValue = struct { identity: T.NominalIdentity, arguments: T.List, signature: T.Id, witness: Id = 0, witness_result: T.Id = 0, instance: T.NominalIdentity = .{ .unit = 0, .decl = 0 }, capability: Id = 0 };
pub const HandleEffects = struct { node: Id, first: T.Id, second: T.Id = 0, extended: T.Effects.Id, residual: T.Effects.Id };
pub const RequestDecisionKind = enum(u32) { reply, cancel, break_ };
pub const RequestArm = struct { operation: T.Effects.Label, callback: Id, selector: Id = 0 };
pub const RequestLoopInfo = struct {
    computation: Id,
    action_type: T.Id,
    value_type: T.Id,
    result_type: T.Id,
    state_type: T.Id,
    arms: List = .{},
    completion_pattern: PatternId = 0,
    completion_body: Id = 0,
    completion_state_bindings: List = .{},
    carries: List = .{},
    return_target: Id = 0,
};
pub const LoopKind = enum(u8) { forever, range, array };
/// Immutable lexical versions make the incoming value, each iteration's seed,
/// normal backedge and suffix result distinct identities. Breaks carry their
/// exact current values separately, since they may precede the normal backedge.
pub const LoopCarry = struct { incoming: BindingId, iteration: BindingId, backedge: BindingId, outgoing: BindingId };
/// Range bounds and array expressions are evaluated exactly once before the
/// body. A forever loop has no first/end expression and no iterator pattern.
pub const LoopInfo = struct { kind: LoopKind, first: Id = 0, end: Id = 0, pattern: PatternId = 0, body: Id, carries: List = .{}, can_exit: bool = false };
pub const Code = enum { unchecked, unsupported, unresolved_binding, invalid_call, complexity };
pub const Diagnostic = struct {
    code: Code,
    span: Span,
    pub fn message(self: Diagnostic) []const u8 {
        return switch (self.code) {
            .unchecked => "Typed core requires successful semantic checking",
            .unsupported => "This checked form is not implemented in the typed core",
            .unresolved_binding => "Typed expression has no resolved binding identity",
            .invalid_call => "Typed core requires a resolved named call or compiler primitive",
            .complexity => "Typed core exceeds its nesting or table limit",
        };
    }
};
/// All roots are normalized before projection. Frozen variables are principal
/// identities, with no mutable substitution history retained in the artifact.
pub const EffectRows = struct {
    rows: []T.Effects.Row = &.{},
    labels: []T.Effects.Label = &.{},
    variable_count: u32 = 0,
    pub fn node(self: *const EffectRows, id: T.Effects.Id) T.Effects.Row {
        if (id == 0 and self.rows.len == 0) return .{};
        return self.rows[id];
    }
    pub fn list(self: *const EffectRows, span: T.Effects.List) []const T.Effects.Label {
        return self.labels[span.start..][0..span.len];
    }
};
/// Owned associated declaration recipes. Principal and selected types share
/// these identities; runtime layout never interprets a residual projection.
pub const Contract = struct { private: bool, identity: T.NominalIdentity, name: u32, parameters: T.List, variables: T.List, row_variables: T.List, predicates: T.List, members: T.List, requires_implementation: bool, row_parameter_names: T.List = .{}, row_parameters: T.List = .{} };
pub const ContractMember = @import("../reuse/principal_interface.zig").ContractMember;
pub const Implementation = @import("../reuse/principal_interface.zig").Implementation;
pub const ImplementationMember = @import("../reuse/principal_interface.zig").ImplementationMember;
pub const MemberTemplate = @import("../reuse/principal_interface.zig").MemberTemplate;
pub const SelectedProof = @import("../reuse/principal_interface.zig").SelectedProof;
pub const SelectedUse = struct { node: Id, proof: u32 };
/// Source quantifier leaves use bound.c=0. A nonzero Core bound.c is an
/// owned lexical opening BindingId, paired with packageOpening's binder list.
/// It is never the checker's request-local rigid scope nonce.
pub const Types = struct {
    nodes: []T.Node,
    extra: []T.Id,
    effects: EffectRows = .{},
    operations: []T.Operation = &.{},
    quantifier_goals: []T.QuantifierGoals = &.{},
    quantifier_obligations: []T.Obligation = &.{},
    pub fn quantifierGoals(self: *const Types, owner: T.Id) []const T.Obligation {
        return @import("quantifier_goals.zig").get(self.quantifier_goals, self.quantifier_obligations, owner);
    }
    pub fn node(self: *const Types, id: T.Id) T.Node {
        return self.nodes[id];
    }
    /// Universal introduction owns its binders; monomorphic specialization
    /// consumes the body only after supplying concrete endpoint evidence.
    pub fn withoutForall(self: *const Types, id: T.Id) error{CoreLimit}!T.Id {
        var current = id;
        var depth: usize = 0;
        while (self.node(current).tag == .forall or self.node(current).tag == .usage) {
            if (depth == 128) return error.CoreLimit;
            depth += 1;
            current = self.node(current).a;
        }
        return current;
    }

    pub fn head(_: *const Types, id: T.Id, _: T.Cursor) T.Id {
        return id;
    }
    pub fn list(self: *const Types, span: T.List) []const T.Id {
        return self.extra[span.start..][0..span.len];
    }
    pub fn projectionMember(self: *const Types, value: T.Node) u32 {
        return self.extra[value.c + 1 + self.extra[value.c]];
    }
    pub fn nominalArguments(self: *const Types, value: T.Node) []const T.Id {
        std.debug.assert(value.tag == .nominal or value.tag == .projection or value.tag == .instance_selection);
        return self.extra[value.c + 1 ..][0..self.extra[value.c]];
    }
    pub fn recordField(self: *const Types, value: T.Node, index: usize) T.Field {
        std.debug.assert(value.tag == .record and index < value.b);
        return .{ .name = self.extra[value.a + index * 2], .ty = self.extra[value.a + index * 2 + 1] };
    }
    pub fn row(self: *const Types, id: T.Effects.Id) T.Effects.Row {
        return self.effects.node(id);
    }
    pub fn rowLabels(self: *const Types, id: T.Effects.Id) []const T.Effects.Label {
        return self.effects.list(self.row(id).labels);
    }
    pub fn operation(self: *const Types, label: T.Effects.Label) T.Operation {
        return self.operations[label];
    }
    pub fn operationArguments(self: *const Types, label: T.Effects.Label) []const T.Id {
        return self.list(self.operation(label).arguments);
    }
};
pub const Module = struct {
    has_rank_contracts: bool = false,
    has_usage_contracts: bool = false,
    has_numeric_proofs: bool = false,
    proof_contracts: []ProofContract = &.{},
    capability_contracts: @import("capability_contracts.zig").Collection = .{},
    field_names: []FieldName = &.{},
    runtime_names: []RuntimeName = &.{},
    source_names: []RuntimeName = &.{},
    declaration_dependencies: []DeclarationDependencies = &.{},
    dependency_references: []BindingRef = &.{},
    dependency_members: []DependencyMember = &.{},
    erased_declaration_references: []ErasedDeclarationReference = &.{},
    request_loops: []RequestLoopInfo = &.{},
    request_arms: []RequestArm = &.{},
    tag_calls: []Id = &.{},
    unit: u32 = 0,
    types: Types,
    nodes: []Node,
    spans: []Span,
    extra: []Id,
    bindings: []Binding,
    bodies: []Body,
    parameters: []Parameter,
    references: []BindingRef,
    calls: []CallInfo,
    merges: []Merge,
    merge_ranges: []List,
    names: []u8,
    obligations: []Obligation,
    nominals: []Nominal = &.{},
    operation_names: []OperationName = &.{},
    constructors: []Constructor = &.{},
    projections: []Projection = &.{},
    projection_variants: []ProjectionVariant = &.{},
    patterns: []Pattern = &.{},
    pattern_rows: []PatternRow = &.{},
    match_arms: []MatchArm = &.{},
    matches: []MatchInfo = &.{},
    updates: []UpdateInfo = &.{},
    update_steps: []UpdateStep = &.{},
    closures: []ClosureInfo = &.{},
    associated: []Associated = &.{},
    contracts: []Contract = &.{},
    contract_members: []ContractMember = &.{},
    implementations: []Implementation = &.{},
    implementation_members: []ImplementationMember = &.{},
    member_templates: []MemberTemplate = &.{},
    selected_proofs: []SelectedProof = &.{},
    selected_members: []ImplementationMember = &.{},
    selected_edges: []u32 = &.{},
    selected_uses: []SelectedUse = &.{},
    dictionary_selections: []DictionarySelection = &.{},
    dictionary_uses: []DictionaryUse = &.{},
    primitives: []Primitive = &.{},
    loops: []LoopInfo = &.{},
    loop_carries: []LoopCarry = &.{},
    resolver_ops: []ResolverInfo = &.{},
    operation_values: []OperationValue = &.{},
    handle_effects: []HandleEffects = &.{},
    dispatch_signatures: []T.Id = &.{},
    diagnostics: []Diagnostic,
    body_lowerings: usize,
    pub fn deinit(self: *Module, allocator: Allocator) void {
        for (self.proof_contracts) |*contract| contract.header.deinit(allocator);
        allocator.free(self.proof_contracts);
        self.capability_contracts.deinit(allocator);
        allocator.free(self.field_names);
        allocator.free(self.runtime_names);
        allocator.free(self.source_names);
        allocator.free(self.declaration_dependencies);
        allocator.free(self.dependency_references);
        allocator.free(self.dependency_members);
        allocator.free(self.erased_declaration_references);
        allocator.free(self.request_loops);
        allocator.free(self.request_arms);
        allocator.free(self.types.nodes);
        allocator.free(self.types.extra);
        allocator.free(self.types.effects.rows);
        allocator.free(self.types.effects.labels);
        allocator.free(self.types.operations);
        allocator.free(self.types.quantifier_goals);
        allocator.free(self.types.quantifier_obligations);
        allocator.free(self.nodes);
        allocator.free(self.spans);
        allocator.free(self.extra);
        allocator.free(self.bindings);
        allocator.free(self.bodies);
        allocator.free(self.parameters);
        allocator.free(self.references);
        allocator.free(self.calls);
        allocator.free(self.merges);
        allocator.free(self.merge_ranges);
        allocator.free(self.names);
        allocator.free(self.obligations);
        allocator.free(self.diagnostics);
        allocator.free(self.nominals);
        allocator.free(self.operation_names);
        allocator.free(self.constructors);
        allocator.free(self.projections);
        allocator.free(self.projection_variants);
        allocator.free(self.patterns);
        allocator.free(self.pattern_rows);
        allocator.free(self.match_arms);
        allocator.free(self.matches);
        allocator.free(self.updates);
        allocator.free(self.update_steps);
        allocator.free(self.closures);
        allocator.free(self.associated);
        allocator.free(self.contracts);
        allocator.free(self.contract_members);
        allocator.free(self.implementations);
        allocator.free(self.implementation_members);
        allocator.free(self.member_templates);
        allocator.free(self.selected_proofs);
        allocator.free(self.selected_members);
        allocator.free(self.selected_edges);
        allocator.free(self.selected_uses);
        allocator.free(self.dictionary_selections);
        allocator.free(self.dictionary_uses);
        allocator.free(self.primitives);
        allocator.free(self.loops);
        allocator.free(self.loop_carries);
        allocator.free(self.resolver_ops);
        allocator.free(self.operation_values);
        allocator.free(self.handle_effects);
        allocator.free(self.dispatch_signatures);
        allocator.free(self.tag_calls);
        self.* = undefined;
    }
    pub fn node(self: *const Module, id: Id) Node {
        return self.nodes[id];
    }
    pub fn span(self: *const Module, id: Id) Span {
        return self.spans[id];
    }
    pub fn sourceNamePoint(self: *const Module, binding_id: BindingId) u32 {
        const index = std.sort.binarySearch(RuntimeName, self.source_names, binding_id, struct {
            fn compare(key: BindingId, value: RuntimeName) std.math.Order {
                return std.math.order(key, value.binding);
            }
        }.compare) orelse return self.binding(binding_id).span.start;
        return self.source_names[index].point;
    }
    pub fn runtimeNamePoint(self: *const Module, binding_id: BindingId) u32 {
        const index = std.sort.binarySearch(RuntimeName, self.runtime_names, binding_id, struct {
            fn compare(key: BindingId, value: RuntimeName) std.math.Order {
                return std.math.order(key, value.binding);
            }
        }.compare) orelse return self.binding(binding_id).span.start;
        return self.runtime_names[index].point;
    }
    pub fn isTagCall(self: *const Module, id: Id) bool {
        return std.sort.binarySearch(Id, self.tag_calls, id, struct {
            fn compare(key: Id, value: Id) std.math.Order {
                return std.math.order(key, value);
            }
        }.compare) != null;
    }
    pub fn packageOpening(self: *const Module, id: Id) struct { body: Id, binders: T.List } {
        const node_ = self.node(id);
        std.debug.assert(node_.tag == .package_unpack);
        const metadata = self.extra[node_.c..][0..3];
        return .{ .body = metadata[0], .binders = .{ .start = metadata[1], .len = metadata[2] } };
    }
    pub fn typeOf(self: *const Module, id: Id) T.Id {
        return self.nodes[id].ty;
    }
    pub fn operationValue(self: *const Module, id: Id) OperationValue {
        std.debug.assert(self.node(id).tag == .operation_value);
        return self.operation_values[self.node(id).a];
    }
    pub fn operationValueArguments(self: *const Module, id: Id) []const T.Id {
        return self.types.list(self.operationValue(id).arguments);
    }
    pub fn handleEffects(self: *const Module, id: Id) ?HandleEffects {
        const value = self.node(id);
        std.debug.assert(value.tag == .handle);
        return if (value.c == 0) null else self.handle_effects[value.c - 1];
    }
    pub fn dispatchSignature(self: *const Module, id: Id) T.Id {
        return if (self.dispatch_signatures.len == 0) 0 else self.dispatch_signatures[id];
    }
    pub fn children(self: *const Module, id: Id) []const Id {
        const value = self.node(id);
        return switch (value.tag) {
            .block, .suite, .product, .record, .array, .array_op, .task => self.extra[value.a..][0..value.b],
            .call, .contract_method, .break_ => self.extra[value.b..][0..value.c],
            .package_pack => blk: {
                for (self.dictionary_selections) |selection| {
                    if (selection.owner == id) break :blk self.extra[selection.contents.start..][0..selection.contents.len];
                }
                break :blk @as([*]const Id, @ptrCast(&self.nodes[id].a))[0..1];
            },
            else => &.{},
        };
    }
    pub fn call(self: *const Module, id: Id) Call {
        const value = self.node(id);
        std.debug.assert(value.tag == .call);
        const target = self.calls[value.a];
        return .{ .target = target.target, .callee_type = target.callee_type, .arguments = self.children(id) };
    }
    pub fn dictionaryOffset(self: *const Module, quantifier: T.Id, wanted_goal: u32, wanted_member: u32) error{CoreLimit}!usize {
        const goals = self.types.quantifierGoals(quantifier);
        if (wanted_goal >= goals.len) return error.CoreLimit;
        var offset: usize = 1;
        for (goals, 0..) |goal, ordinal| {
            if (goal.kind != .contract) {
                if (ordinal == wanted_goal) return error.CoreLimit;
                continue;
            }
            const contract = for (self.contracts) |candidate| {
                if (candidate.identity.unit == goal.identity.unit and candidate.identity.decl == goal.identity.decl) break candidate;
            } else return error.CoreLimit;
            for (self.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, member_ordinal| {
                if (ordinal == wanted_goal and member_ordinal == wanted_member) {
                    if (member.kind != .value) return error.CoreLimit;
                    return offset;
                }
                if (member.kind == .value) offset += 1;
            }
        }
        return error.CoreLimit;
    }
    pub fn reference(self: *const Module, id: Id) BindingRef {
        std.debug.assert(self.node(id).tag == .reference);
        return self.references[self.node(id).a];
    }
    pub fn binding(self: *const Module, id: BindingId) Binding {
        return self.bindings[id];
    }
    pub fn body(self: *const Module, id: BindingId) ?*const Body {
        const body_id = self.bindings[id].body_id;
        return if (body_id == 0) null else &self.bodies[body_id];
    }
    pub fn bodyParameters(self: *const Module, value: *const Body) []const Parameter {
        return self.parameters[value.parameters.start..][0..value.parameters.len];
    }
    pub fn branchMerges(self: *const Module, id: Id) []const Merge {
        const range = self.merge_ranges[id];
        return self.merges[range.start..][0..range.len];
    }
    pub fn requestLoopInfo(self: *const Module, id: Id) RequestLoopInfo {
        std.debug.assert(self.node(id).tag == .request_loop);
        return self.request_loops[self.node(id).a];
    }
    pub fn requestArms(self: *const Module, id: Id) []const RequestArm {
        const range = self.requestLoopInfo(id).arms;
        return self.request_arms[range.start..][0..range.len];
    }
    pub fn requestLoopCarries(self: *const Module, id: Id) []const LoopCarry {
        const range = self.requestLoopInfo(id).carries;
        return self.loop_carries[range.start..][0..range.len];
    }
    pub fn requestCompletionBindings(self: *const Module, id: Id) []const BindingId {
        const range = self.requestLoopInfo(id).completion_state_bindings;
        return self.extra[range.start..][0..range.len];
    }
    pub fn loopInfo(self: *const Module, id: Id) LoopInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .loop);
        return self.loops[value.a];
    }
    pub fn loopCarries(self: *const Module, id: Id) []const LoopCarry {
        const range = self.loopInfo(id).carries;
        return self.loop_carries[range.start..][0..range.len];
    }
    pub fn breakValues(self: *const Module, id: Id) []const Id {
        std.debug.assert(self.node(id).tag == .break_);
        return self.children(id);
    }
    pub fn name(self: *const Module, range: Name) []const u8 {
        return self.names[range.start..][0..range.len];
    }
    pub fn fieldSpelling(self: *const Module, symbol: u32) ?[]const u8 {
        const index = std.sort.binarySearch(FieldName, self.field_names, symbol, struct {
            fn compare(key: u32, value: FieldName) std.math.Order {
                return std.math.order(key, value.symbol);
            }
        }.compare) orelse return null;
        return self.name(self.field_names[index].spelling);
    }
    pub fn nominal(self: *const Module, index: u32) Nominal {
        return self.nominals[index];
    }
    pub fn nominalConstructors(self: *const Module, index: u32) []const u32 {
        const range = self.nominals[index].constructors;
        return self.extra[range.start..][0..range.len];
    }
    pub fn constructor(self: *const Module, index: u32) Constructor {
        return self.constructors[index];
    }
    pub fn recordDestinations(self: *const Module, id: Id) []const u32 {
        const value = self.node(id);
        std.debug.assert(value.tag == .record);
        return self.extra[value.c..][0..value.b];
    }
    pub fn projection(self: *const Module, index: u32) Projection {
        return self.projections[index];
    }
    pub fn projectionVariants(self: *const Module, index: u32) []const ProjectionVariant {
        const range = self.projections[index].variants;
        return self.projection_variants[range.start..][0..range.len];
    }
    pub fn pattern(self: *const Module, id: PatternId) Pattern {
        return self.patterns[id];
    }
    pub fn patternChildren(self: *const Module, id: PatternId) []const PatternId {
        const value = self.pattern(id);
        std.debug.assert(value.tag == .product);
        return self.extra[value.a..][0..value.b];
    }
    pub fn matchInfo(self: *const Module, id: Id) MatchInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .match);
        return self.matches[value.a];
    }
    pub fn matchInputs(self: *const Module, id: Id) []const Id {
        const range = self.matchInfo(id).inputs;
        return self.extra[range.start..][0..range.len];
    }
    pub fn matchArms(self: *const Module, id: Id) []const MatchArm {
        const range = self.matchInfo(id).arms;
        return self.match_arms[range.start..][0..range.len];
    }
    pub fn armRows(self: *const Module, arm: MatchArm) []const PatternRow {
        return self.pattern_rows[arm.rows.start..][0..arm.rows.len];
    }
    pub fn rowPatterns(self: *const Module, row: PatternRow) []const PatternId {
        return self.extra[row.patterns.start..][0..row.patterns.len];
    }
    pub fn updateInfo(self: *const Module, id: Id) UpdateInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .update);
        return self.updates[value.a];
    }
    pub fn updatePath(self: *const Module, id: Id) []const u32 {
        const range = self.updateInfo(id).path;
        return self.extra[range.start..][0..range.len];
    }
    pub fn updateSelectors(self: *const Module, id: Id) []const UpdateStep {
        const range = self.updateInfo(id).selectors;
        return self.update_steps[range.start..][0..range.len];
    }
    pub fn arrayOperation(self: *const Module, id: Id) ArrayOp {
        const value = self.node(id);
        std.debug.assert(value.tag == .array_op);
        return @fromBackingInt(@intCast(value.c));
    }
    pub fn closure(self: *const Module, id: Id) ClosureInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .closure);
        return self.closures[value.a];
    }
    pub fn closureCaptures(self: *const Module, id: Id) []const BindingId {
        const range = self.closure(id).captures;
        return self.extra[range.start..][0..range.len];
    }
    pub fn suspension(self: *const Module, id: Id) ClosureInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .suspend_);
        return self.closures[value.a];
    }
    pub fn suspensionCaptures(self: *const Module, id: Id) []const BindingId {
        const range = self.suspension(id).captures;
        return self.extra[range.start..][0..range.len];
    }
    pub fn resolverInfo(self: *const Module, id: Id) ResolverInfo {
        const value = self.node(id);
        std.debug.assert(value.tag == .resolver_op);
        return self.resolver_ops[value.a];
    }
    pub fn resolverArguments(self: *const Module, id: Id) []const Id {
        const range = self.resolverInfo(id).arguments;
        return self.extra[range.start..][0..range.len];
    }
    pub fn primitive(self: *const Module, id: Id) Primitive {
        const value = self.node(id);
        std.debug.assert(value.tag == .primitive_function);
        return self.primitives[value.a];
    }
    pub fn panicMessage(self: *const Module, id: Id) []const u8 {
        const value = self.node(id);
        std.debug.assert(value.tag == .panic);
        return self.name(.{ .start = value.a, .len = value.b });
    }
};

/// Source construction lives with its mutable owners. These entry aliases
/// retain the established API for consumers that also read immutable Core.
pub const lower = @import("core_builder.zig").lower;
pub const lowerWithOrigins = @import("core_builder.zig").lowerWithOrigins;
