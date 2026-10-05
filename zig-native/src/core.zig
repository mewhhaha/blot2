//! Immutable typed core. Source syntax, identifier strings and solver state
//! are consumed once at lowering; evaluators/code instances read only this IR.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
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
pub const Name = struct { start: u32 = 0, len: u32 = 0 };
pub const Tag = enum(u8) { invalid, constant, reference, scalar, logical, call, if_value, block, suite, bind, return_, if_stmt, product, record, construct, project, match, pattern_bind, update, array, array_op, closure, apply, constructor_function, associated, primitive_function, panic, loop, break_, type_same, result_associated, suspend_, force, type_constructor, resolver_op, operation_value, effect_provider, state_provider, handle, effect_reflection, computation, request_loop, request_decision };
pub const ArrayOp = @import("collection_ops.zig").Op;
pub const PrimitiveKind = enum(u8) { scalar, array };
pub const Primitive = struct { kind: PrimitiveKind, op: Op = .none, array_op: ArrayOp = .length, arity: u8 };
pub const Op = enum(u8) { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right, and_, or_, neg, abs, ceil, floor, trunc, sqrt, convert_u32_f32, convert_f32_u32 };
/// constant a=bits; reference a=references index; scalar a=left,b=right(0 unary),
/// c=1 for associated operator dispatch, c=0 for authoritative compiler primitives.
/// logical a=left,b=right,op=and_/or_; call a=call-info,b=args start,c=args len.
/// if_value/if_stmt a=condition,b=then,c=else(0 absent statement suite).
/// block/suite a=children start,b=len; block creates a do return boundary.
/// bind a=local BindingId,b=value; return_ a=value,b=target block Id.
/// product a=values start,b=len; record adds c=destination field-index start.
/// construct a=constructor catalog index,b=optional payload,c=1 for a canonical record argument.
/// c=0 retains the declared storage payload; project a=value,b=projection index.
/// match a=match-info index; pattern_bind a=pattern,b=value,c=exiting fallback suite.
/// update a=update-info index. Its self binding is assigned before the replacement.
/// array/array_op a=values start,b=len; array_op c=ArrayOp enum ordinal.
/// closure a=closure catalog; apply a=callee,b=one argument; constructor_function a=catalog.
/// associated a=left,b=right,c=member Symbol; op is its standard scalar operation or none.
/// primitive_function a=primitive catalog; panic a=owned message start,b=UTF8 byte length.
/// loop a=loop catalog; break_ a=target loop Id,b=current carried-value IR start,c=len.
/// result_associated a=operand,b=member Symbol; ty supplies the expected-result owner.
/// suspend_ a=closure catalog with Unit parameter; force a=demanded value.
/// type_constructor has its exact owner in ty; resolver_op a=owned protocol catalog.
/// effect_provider a=operation,b=callback; state_provider a=read,b=write,c=initial.
/// handle a=provider,b=inner expression,c=optional HandleEffects catalog index+1.
pub const Node = struct { tag: Tag, op: Op = .none, ty: T.Id = 0, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Parameter = struct { binding: BindingId, ty: T.Id, span: Span };
pub const Binding = struct { initializer: Id = 0, kind: checked_types.Kind, ty: T.Id, scheme: T.Scheme, body_id: BodyId = 0, target: BindingRef, span: Span };
pub const RuntimeName = struct { binding: BindingId, point: u32 };
/// Original declaration reads survive executable branch/value elimination.
pub const DeclarationDependencies = struct { references: List = .{}, members: List = .{}, runtime_metadata: Id = 0 };
pub const DependencyMember = struct { name: u32 = 0, operator: T.Operator = .none };
pub const ErasedDeclarationReference = struct { node: Id, target: BindingRef };
pub const Body = struct { binding: BindingId = 0, root: Id = 0, parameters: List = .{}, scheme: T.Scheme = .{}, closed_rows: T.List = .{}, span: Span = .{ .start = 0, .end = 0 }, export_name: Name = .{}, exported: bool = false, runtime: bool = false, is_function: bool = false };
pub const CallInfo = struct { target: BindingRef, callee_type: T.Id };
pub const Call = struct { target: BindingRef, callee_type: T.Id, arguments: []const Id };
pub const Merge = struct { node: Id, result: BindingId, then_binding: BindingId, else_binding: BindingId };
pub const Obligation = struct { ty: T.Id, kind: T.ObligationKind, span: Span, name: u32 = 0, result: T.Id = 0, other: T.Id = 0, signature: T.Id = 0, operator: T.Operator = .none, identity: T.NominalIdentity = .{ .unit = 0, .decl = 0 }, explicit: bool = false, qualification_span: ?Span = null, qualification_unit: u32 = 0, diagnostic_name: Name = .{} };
pub const Associated = struct { identity: T.NominalIdentity, member: u32, operator: T.Operator, target: BindingRef };
pub const Nominal = struct { diagnostic_name: Name = .{}, diagnostic_origin: Name = .{}, identity: T.NominalIdentity, parameters: T.List, variables: T.List, constructors: List };
/// Source operation names survive frontend teardown; identities still select
/// effects independently of these owned diagnostic strings.
pub const OperationName = struct { identity: T.NominalIdentity, diagnostic_name: Name = .{}, diagnostic_origin: Name = .{} };
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
pub const OperationValue = struct { identity: T.NominalIdentity, arguments: T.List, signature: T.Id, witness: Id = 0, witness_result: T.Id = 0 };
pub const HandleEffects = struct { node: Id, first: T.Id, second: T.Id = 0, extended: T.Effects.Id, residual: T.Effects.Id };
pub const RequestDecisionKind = enum(u32) { reply, cancel, break_ };
pub const RequestArm = struct { operation: T.Effects.Label, callback: Id };
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
pub const Types = struct {
    nodes: []T.Node,
    extra: []T.Id,
    effects: EffectRows = .{},
    operations: []T.Operation = &.{},
    pub fn node(self: *const Types, id: T.Id) T.Node {
        return self.nodes[id];
    }
    pub fn head(_: *const Types, id: T.Id, _: T.Cursor) T.Id {
        return id;
    }
    pub fn list(self: *const Types, span: T.List) []const T.Id {
        return self.extra[span.start..][0..span.len];
    }
    pub fn nominalArguments(self: *const Types, value: T.Node) []const T.Id {
        std.debug.assert(value.tag == .nominal);
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
            .block, .suite, .product, .record, .array, .array_op => self.extra[value.a..][0..value.b],
            .call, .break_ => self.extra[value.b..][0..value.c],
            else => &.{},
        };
    }
    pub fn call(self: *const Module, id: Id) Call {
        const value = self.node(id);
        std.debug.assert(value.tag == .call);
        const target = self.calls[value.a];
        return .{ .target = target.target, .callee_type = target.callee_type, .arguments = self.children(id) };
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

const Error = Allocator.Error || error{CoreLimit};
const ResolverLoopFrame = struct { source: ast.Id, cursor: T.Id, parameter: BindingId, finalizer: Id };
const RequestCallbackFrame = struct { loop: ast.Id, return_target: Id, decision_type: T.Id, state_type: T.Id };
const Builder = struct {
    request_loops: std.ArrayList(RequestLoopInfo) = .empty,
    request_arms: std.ArrayList(RequestArm) = .empty,
    request_callbacks: std.ArrayList(RequestCallbackFrame) = .empty,
    tag_calls: std.ArrayList(Id) = .empty,
    allocator: Allocator,
    tree: *const ast.Tree,
    names: *const symbols.Pool,
    checked: *const checked_types.Checked,
    diagnostic_origins: checked_types.ModuleOrigins = .{},
    nodes: std.ArrayList(Node) = .empty,
    spans: std.ArrayList(Span) = .empty,
    extra: std.ArrayList(Id) = .empty,
    type_nodes: std.ArrayList(T.Node) = .empty,
    type_extra: std.ArrayList(T.Id) = .empty,
    effect_rows: std.ArrayList(T.Effects.Row) = .empty,
    effect_labels: std.ArrayList(T.Effects.Label) = .empty,
    effect_operations: std.ArrayList(T.Operation) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    bodies: std.ArrayList(Body) = .empty,
    parameters: std.ArrayList(Parameter) = .empty,
    runtime_names: std.ArrayList(RuntimeName) = .empty,
    source_names: std.ArrayList(RuntimeName) = .empty,
    erased_declaration_references: std.ArrayList(ErasedDeclarationReference) = .empty,
    references: std.ArrayList(BindingRef) = .empty,
    calls: std.ArrayList(CallInfo) = .empty,
    merges: std.ArrayList(Merge) = .empty,
    merge_ranges: std.ArrayList(List) = .empty,
    name_bytes: std.ArrayList(u8) = .empty,
    obligations: std.ArrayList(Obligation) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    nominals: std.ArrayList(Nominal) = .empty,
    operation_names: std.ArrayList(OperationName) = .empty,
    constructors: std.ArrayList(Constructor) = .empty,
    projections: std.ArrayList(Projection) = .empty,
    projection_variants: std.ArrayList(ProjectionVariant) = .empty,
    patterns: std.ArrayList(Pattern) = .empty,
    pattern_rows: std.ArrayList(PatternRow) = .empty,
    match_arms: std.ArrayList(MatchArm) = .empty,
    matches: std.ArrayList(MatchInfo) = .empty,
    updates: std.ArrayList(UpdateInfo) = .empty,
    update_steps: std.ArrayList(UpdateStep) = .empty,
    closures: std.ArrayList(ClosureInfo) = .empty,
    visit_epochs: std.ArrayList(u32) = .empty,
    associated: std.ArrayList(Associated) = .empty,
    primitives: std.ArrayList(Primitive) = .empty,
    loops: std.ArrayList(LoopInfo) = .empty,
    loop_carries: std.ArrayList(LoopCarry) = .empty,
    resolver_ops: std.ArrayList(ResolverInfo) = .empty,
    operation_values: std.ArrayList(OperationValue) = .empty,
    handle_effects: std.ArrayList(HandleEffects) = .empty,
    dispatch_signatures: std.ArrayList(T.Id) = .empty,
    resolver_loop_frames: std.ArrayList(ResolverLoopFrame) = .empty,
    type_map: []T.Id = &.{},
    variable_map: []T.Id = &.{},
    effect_row_map: []u32 = &.{},
    effect_variable_map: []u32 = &.{},
    effect_operation_map: []u32 = &.{},
    ast_map: []Id = &.{},
    member_origin_heads: []u32 = &.{},
    member_origin_next: []u32 = &.{},
    signature_sources: []T.Id = &.{},
    merge_heads: []u32 = &.{},
    merge_next: []u32 = &.{},
    loop_exit_indices: []u32 = &.{},
    definition_epochs: []u32 = &.{},
    reference_epochs: []u32 = &.{},
    capture_epoch: u32 = 0,
    return_target: Id = 0,
    variable_count: u32 = 0,
    effect_variable_count: u32 = 0,
    body_lowerings: usize = 0,
    fn deinit(self: *Builder) void {
        inline for (.{ "request_loops", "request_arms", "request_callbacks", "runtime_names", "source_names", "erased_declaration_references", "tag_calls", "nodes", "spans", "extra", "type_nodes", "type_extra", "effect_rows", "effect_labels", "effect_operations", "bindings", "bodies", "parameters", "references", "calls", "merges", "merge_ranges", "name_bytes", "obligations", "diagnostics", "nominals", "operation_names", "constructors", "projections", "projection_variants", "patterns", "pattern_rows", "match_arms", "matches", "updates", "update_steps", "closures", "visit_epochs", "associated", "primitives", "loops", "loop_carries", "resolver_ops", "operation_values", "handle_effects", "dispatch_signatures", "resolver_loop_frames" }) |field| @field(self, field).deinit(self.allocator);
        self.allocator.free(self.type_map);
        self.allocator.free(self.variable_map);
        self.allocator.free(self.effect_row_map);
        self.allocator.free(self.effect_variable_map);
        self.allocator.free(self.effect_operation_map);
        self.allocator.free(self.ast_map);
        self.allocator.free(self.member_origin_heads);
        self.allocator.free(self.member_origin_next);
        self.allocator.free(self.signature_sources);
        self.allocator.free(self.merge_heads);
        self.allocator.free(self.merge_next);
        self.allocator.free(self.loop_exit_indices);
        self.allocator.free(self.definition_epochs);
        self.allocator.free(self.reference_epochs);
    }
    fn allocateEmpty(self: *Builder, destination: *[]u32, count: usize) Error!void {
        std.debug.assert(destination.*.len == 0);
        const buffer = try self.allocator.alloc(u32, count);
        @memset(buffer, 0);
        destination.* = buffer;
    }
    fn initialize(self: *Builder) Error!void {
        try self.allocateEmpty(&self.type_map, self.checked.types.nodes.items.len);
        try self.allocateEmpty(&self.variable_map, self.checked.types.variables.items.len);
        try self.allocateEmpty(&self.effect_row_map, self.checked.types.effects.rows.items.len);
        try self.allocateEmpty(&self.effect_variable_map, self.checked.types.effects.variables.items.len);
        try self.allocateEmpty(&self.effect_operation_map, self.checked.types.operations.items.len);
        try self.effect_rows.append(self.allocator, .{});
        try self.effect_operations.appendSlice(self.allocator, &.{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } });
        self.effect_operation_map[T.foreign_operation] = T.foreign_operation;
        try self.allocateEmpty(&self.ast_map, self.tree.nodes.items.len);
        const origins = self.tree.operator_origins.items;
        const has_member_origin = for (origins) |origin| {
            if (origin.member_point != 0 and origin.node < self.tree.nodes.items.len) break true;
        } else false;
        if (has_member_origin) {
            if (origins.len > std.math.maxInt(u32)) return error.CoreLimit;
            try self.allocateEmpty(&self.member_origin_heads, self.tree.nodes.items.len);
            try self.allocateEmpty(&self.member_origin_next, origins.len);
            for (origins, 0..) |origin, index| {
                // Invalid owner IDs could not match a valid lowered source in
                // the former scan. Keep that diagnostic-origin fallback.
                if (origin.member_point == 0 or origin.node >= self.member_origin_heads.len) continue;
                self.member_origin_next[index] = self.member_origin_heads[origin.node];
                self.member_origin_heads[origin.node] = @intCast(index + 1);
            }
        }
        if (self.checked.dispatch_signatures.len != 0) for (self.checked.dispatch_signatures, 0..) |signature, source| {
            if (signature == 0) continue;
            if (self.signature_sources.len == 0) try self.allocateEmpty(&self.signature_sources, self.tree.nodes.items.len);
            self.signature_sources[source] = signature;
        };
        for (self.checked.obligations) |obligation| if (obligation.signature != 0) {
            if (self.signature_sources.len == 0) try self.allocateEmpty(&self.signature_sources, self.tree.nodes.items.len);
            self.signature_sources[obligation.source] = obligation.signature;
        };
        if (self.checked.merges.len != 0) {
            try self.allocateEmpty(&self.merge_heads, self.tree.nodes.items.len);
            @memset(self.merge_heads, std.math.maxInt(u32));
            try self.allocateEmpty(&self.merge_next, self.checked.merges.len);
            // Prepending backwards preserves source merge order without
            // depending on nested conditionals having contiguous records.
            var index = self.checked.merges.len;
            while (index != 0) {
                index -= 1;
                const source = self.checked.merges[index].node;
                self.merge_next[index] = self.merge_heads[source];
                self.merge_heads[source] = @intCast(index);
            }
        }
        if (self.checked.loop_exits.len != 0) {
            try self.allocateEmpty(&self.loop_exit_indices, self.tree.nodes.items.len);
            for (self.checked.loop_exits, 0..) |exit, index| self.loop_exit_indices[exit.node] = @intCast(index + 1);
        }
        try self.type_nodes.appendSlice(self.allocator, self.checked.types.nodes.items[0..6]);
        for (0..6) |i| self.type_map[i] = @intCast(i);
        _ = try self.reserve(0);
        try self.bodies.append(self.allocator, .{});
    }
    fn diagnostic(self: *Builder, code: Code, source: ast.Id) Error!void {
        try self.diagnostics.append(self.allocator, .{ .code = code, .span = self.checked.diagnosticSpan(self.tree, source) });
    }
    fn addType(self: *Builder, value: T.Node) Error!T.Id {
        if (self.type_nodes.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: T.Id = @intCast(self.type_nodes.items.len);
        try self.type_nodes.append(self.allocator, value);
        return id;
    }
    fn projectType(self: *Builder, source: T.Id, depth: usize) Error!T.Id {
        if (source == 0) return 0;
        if (self.type_map[source] != 0) return self.type_map[source];
        if (depth >= 1024) return error.CoreLimit;
        const resolved = self.checked.types.head(source, 0);
        if (resolved != source) {
            const id = try self.projectType(resolved, depth + 1);
            self.type_map[source] = id;
            return id;
        }
        const original = self.checked.types.node(resolved);
        // A published root has already resolved all visible writes. Remaining
        // cursor views of one unbound variable therefore denote one principal
        // identity in the immutable artifact, with no future writes allowed.
        if (original.tag == .variable and self.variable_map[original.a] != 0) {
            const id = self.variable_map[original.a];
            self.type_map[source] = id;
            return id;
        }
        const value: T.Node = switch (original.tag) {
            .variable => blk: {
                const index = self.variable_count;
                self.variable_count += 1;
                break :blk .{ .tag = .variable, .a = index };
            },
            .function => .{ .tag = .function, .a = try self.projectType(original.a, depth + 1), .b = try self.projectType(original.b, depth + 1), .c = try self.projectRow(original.c, depth + 1) },
            .product => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (self.checked.types.list(.{ .start = original.a, .len = original.b })) |child| try fields.append(self.allocator, try self.projectType(child, depth + 1));
                const span = try self.saveTypes(fields.items);
                break :blk .{ .tag = .product, .a = span.start, .b = span.len };
            },
            .record => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (0..original.b) |index| {
                    const field = self.checked.types.recordField(original, index);
                    try fields.appendSlice(self.allocator, &.{ field.name, try self.projectType(field.ty, depth + 1) });
                }
                const span = try self.saveTypes(fields.items);
                break :blk .{ .tag = .record, .a = span.start, .b = original.b };
            },
            .nominal => blk: {
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(self.allocator);
                const source_arguments = self.checked.types.nominalArguments(original);
                try arguments.append(self.allocator, @intCast(source_arguments.len));
                for (source_arguments) |argument| try arguments.append(self.allocator, try self.projectType(argument, depth + 1));
                const span = try self.saveTypes(arguments.items);
                break :blk .{ .tag = .nominal, .a = original.a, .b = original.b, .c = span.start };
            },
            .array, .list, .resolver => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1) },
            .demand, .provider => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1), .c = try self.projectRow(original.c, depth + 1) },
            .state_provider => .{ .tag = .state_provider, .a = try self.projectType(original.a, depth + 1), .b = try self.projectType(original.b, depth + 1), .c = try self.projectType(original.c, depth + 1) },
            else => original,
        };
        const id = try self.addType(value);
        self.type_map[source] = id;
        if (original.tag == .variable) self.variable_map[original.a] = id;
        return id;
    }
    fn projectRowVariable(self: *Builder, variable: u32) Error!u32 {
        if (variable >= self.effect_variable_map.len) return error.CoreLimit;
        if (self.effect_variable_map[variable] != 0) return self.effect_variable_map[variable] - 1;
        if (self.effect_variable_count == std.math.maxInt(u32)) return error.CoreLimit;
        const id = self.effect_variable_count;
        self.effect_variable_count += 1;
        self.effect_variable_map[variable] = id + 1;
        return id;
    }
    fn projectOperation(self: *Builder, label: T.Effects.Label, depth: usize) Error!T.Effects.Label {
        if (depth >= 1024 or label == 0 or label >= self.effect_operation_map.len) return error.CoreLimit;
        if (self.effect_operation_map[label] != 0) return self.effect_operation_map[label];
        const source = self.checked.types.operations.items[label];
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(self.allocator);
        for (self.checked.types.list(source.arguments)) |argument| try values.append(self.allocator, try self.projectType(argument, depth + 1));
        const arguments = try self.saveTypes(values.items);
        if (self.effect_operations.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: u32 = @intCast(self.effect_operations.items.len);
        try self.effect_operations.append(self.allocator, .{ .identity = source.identity, .arguments = arguments });
        self.effect_operation_map[label] = id;
        return id;
    }
    fn projectRow(self: *Builder, source: T.Effects.Id, depth: usize) Error!T.Effects.Id {
        if (source == 0) return 0;
        if (depth >= 1024 or source >= self.effect_row_map.len) return error.CoreLimit;
        if (self.effect_row_map[source] != 0) return self.effect_row_map[source] - 1;
        // Checker publication resolves the complete type graph at its exact
        // chronological cursor. Frozen rows retain labels and principal tail
        // identity, with no further substitutions or historical cursor.
        const original = self.checked.types.effects.node(source);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for (self.checked.types.effects.list(original.labels)) |label| try labels.append(self.allocator, try self.projectOperation(label, depth + 1));
        const tail: T.Effects.Tail = switch (original.tail) {
            .closed => .closed,
            .variable => |variable| .{ .variable = try self.projectRowVariable(variable) },
            .parameter => |parameter| .{ .parameter = parameter },
        };
        if (labels.items.len == 0 and tail == .closed) {
            self.effect_row_map[source] = 1;
            return 0;
        }
        if (self.effect_rows.items.len == std.math.maxInt(u32) or labels.items.len > std.math.maxInt(u32) - self.effect_labels.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.effect_labels.items.len);
        try self.effect_labels.appendSlice(self.allocator, labels.items);
        const id: u32 = @intCast(self.effect_rows.items.len);
        try self.effect_rows.append(self.allocator, .{ .labels = .{ .start = start, .len = @intCast(labels.items.len) }, .tail = tail });
        self.effect_row_map[source] = id + 1;
        return id;
    }
    fn saveTypes(self: *Builder, values: []const T.Id) Error!T.List {
        if (values.len > std.math.maxInt(u32) - self.type_extra.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.type_extra.items.len);
        try self.type_extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn projectScheme(self: *Builder, scheme: T.Scheme) Error!T.Scheme {
        const root = try self.projectType(scheme.root, 0);
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(self.allocator);
        for (self.checked.types.list(scheme.variables)) |id| try variables.append(self.allocator, try self.projectType(id, 0));
        const span = try self.saveTypes(variables.items);
        var row_variables: std.ArrayList(T.Id) = .empty;
        defer row_variables.deinit(self.allocator);
        for (self.checked.types.list(scheme.row_variables)) |variable| try row_variables.append(self.allocator, try self.projectRowVariable(variable));
        const row_span = try self.saveTypes(row_variables.items);
        row_variables.clearRetainingCapacity();
        for (self.checked.types.list(scheme.closed_rows)) |variable| try row_variables.append(self.allocator, try self.projectRowVariable(variable));
        const closed_span = try self.saveTypes(row_variables.items);
        const start: u32 = @intCast(self.obligations.items.len);
        for (self.checked.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |value| try self.obligations.append(self.allocator, .{ .ty = try self.projectType(value.ty, 0), .kind = value.kind, .span = self.checked.diagnosticSpan(self.tree, value.source), .name = value.name, .result = try self.projectType(value.result, 0), .other = try self.projectType(value.other, 0), .signature = try self.projectType(value.signature, 0), .operator = value.operator, .identity = value.identity, .explicit = value.explicit, .qualification_span = value.qualification_span, .qualification_unit = value.qualification_unit, .diagnostic_name = if (value.explicit and value.name != 0) try self.saveName(self.names.get(value.name)) else .{} });
        return .{ .root = root, .variables = span, .row_variables = row_span, .closed_rows = closed_span, .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
    }
    fn reserve(self: *Builder, source: ast.Id) Error!Id {
        if (self.nodes.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.spans.ensureUnusedCapacity(self.allocator, 1);
        try self.merge_ranges.ensureUnusedCapacity(self.allocator, 1);
        try self.dispatch_signatures.ensureUnusedCapacity(self.allocator, 1);
        self.nodes.appendAssumeCapacity(.{ .tag = .invalid });
        self.spans.appendAssumeCapacity(self.checked.diagnosticSpan(self.tree, source));
        self.merge_ranges.appendAssumeCapacity(.{});
        self.dispatch_signatures.appendAssumeCapacity(0);
        return id;
    }
    fn make(self: *Builder, source: ast.Id, value: Node) Error!Id {
        const id = try self.reserve(source);
        self.nodes.items[id] = value;
        if (value.tag == .project and self.projections.items[value.b].diagnostic_point == 0) {
            const field = self.projections.items[value.b].field;
            var member_point: u32 = 0;
            var matches: usize = 0;
            var next = if (source < self.member_origin_heads.len) self.member_origin_heads[source] else 0;
            while (next != 0) {
                const index = next - 1;
                const origin = self.tree.operator_origins.items[index];
                next = self.member_origin_next[index];
                if (origin.member != field) continue;
                matches += 1;
                member_point = origin.member_point;
                if (matches == 2) break;
            }
            // Repeated same-name components require a path-level origin; do
            // not guess which source token produced a particular projection.
            if (matches == 1) {
                const ordinary = self.tree.span(source);
                const selected = self.checked.diagnosticSpan(self.tree, source);
                self.projections.items[value.b].diagnostic_point = if (selected.start != ordinary.start or selected.end != ordinary.end) selected.start else member_point;
            }
        }
        if (value.tag == .bind and value.a != 0 and value.a < self.bindings.items.len) {
            self.bindings.items[value.a].initializer = value.b;
            if (self.nodes.items[value.b].tag == .closure) {
                const template = &self.closures.items[self.nodes.items[value.b].a];
                if (template.qualifier == 0) template.qualifier = value.a;
            }
        }
        if (self.signature_sources.len != 0 and self.signature_sources[source] != 0) {
            const signature = try self.projectType(self.signature_sources[source], 0);
            const callable = self.type_nodes.items[signature];
            // One selector AST may publish several path projections. Each
            // method consumes its immediate receiver and produces this path
            // component; the enclosing selector's leaf is a different result.
            self.dispatch_signatures.items[id] = if (value.tag == .project and callable.tag == .function)
                try self.addType(.{ .tag = .function, .a = self.nodes.items[value.a].ty, .b = value.ty, .c = callable.c })
            else
                signature;
        }
        return id;
    }
    fn save(self: *Builder, values: []const Id) Error!List {
        if (values.len > std.math.maxInt(u32) - self.extra.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn unwrap(self: *const Builder, original: ast.Id) ast.Id {
        var source = original;
        while (self.tree.node(source).tag == .group) source = self.tree.node(source).a;
        return source;
    }
    fn target(self: *const Builder, binding: BindingId) BindingRef {
        if (binding >= self.checked.bindings.len) return .{ .binding = binding };
        const value = self.checked.bindings[binding];
        return if (value.external) |external| .{ .unit = external.unit, .binding = external.binding } else .{ .binding = binding };
    }
    fn typeOf(self: *Builder, source: ast.Id) Error!T.Id {
        return self.projectType(self.checked.expr_types[source], 0);
    }
    fn referenceNode(self: *Builder, source: ast.Id, binding: BindingId, ty: T.Id) Error!Id {
        const index: u32 = @intCast(self.references.items.len);
        try self.references.append(self.allocator, self.target(binding));
        return self.make(source, .{ .tag = .reference, .ty = ty, .a = index });
    }
    fn projectionIndex(self: *Builder, catalog: u32, source_type: T.Id, result_type: T.Id) Error!u32 {
        const metadata = self.checked.projection_catalog[catalog];
        const start: u32 = @intCast(self.projection_variants.items.len);
        const words = self.checked.types.list(metadata.variants);
        var offset: usize = 0;
        while (offset < words.len) : (offset += 2) try self.projection_variants.append(self.allocator, .{ .tag = words[offset], .field = words[offset + 1] });
        const index: u32 = @intCast(self.projections.items.len);
        try self.projections.append(self.allocator, .{ .nominal = metadata.nominal, .field = metadata.field, .source_type = source_type, .result_type = result_type, .variants = .{ .start = start, .len = @intCast(words.len / 2) } });
        return index;
    }
    fn directProjection(self: *Builder, source_type: T.Id, result_type: T.Id, field: u32) Error!u32 {
        const start: u32 = @intCast(self.projection_variants.items.len);
        try self.projection_variants.append(self.allocator, .{ .tag = 0, .field = field });
        const index: u32 = @intCast(self.projections.items.len);
        try self.projections.append(self.allocator, .{ .nominal = .{ .unit = 0, .decl = 0 }, .source_type = source_type, .result_type = result_type, .variants = .{ .start = start, .len = 1 } });
        return index;
    }
    fn resolvedReference(self: *Builder, source: ast.Id, ty: T.Id) Error!Id {
        const binding = self.checked.resolved[source];
        if (binding == 0) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        const path = if (source < self.checked.access_paths.len) self.checked.types.list(self.checked.access_paths[source]) else &.{};
        if (path.len == 0) return self.referenceNode(source, binding, ty);
        const type_path = self.checked.types.list(self.checked.access_types[source]);
        if (type_path.len != path.len + 1) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        var result = try self.referenceNode(source, binding, try self.projectType(type_path[0], 0));
        for (path, 0..) |catalog, index| {
            const result_ty = try self.projectType(type_path[index + 1], 0);
            const projection = try self.projectionIndex(catalog, self.nodes.items[result].ty, result_ty);
            result = try self.make(source, .{ .tag = .project, .ty = result_ty, .a = result, .b = projection });
        }
        return result;
    }
    fn productExpression(self: *Builder, source: ast.Id, ty: T.Id, tag: Tag, depth: usize) Error!Id {
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(scratch);
        try values.ensureTotalCapacityPrecise(scratch, @min(self.tree.children(source).len, 16));
        for (self.tree.children(source)) |child| try values.append(scratch, try self.expression(child, depth + 1));
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = tag, .ty = ty, .a = range.start, .b = range.len });
    }
    fn recordExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!Id {
        const catalog = if (source < self.checked.constructor_resolved.len) self.checked.constructor_resolved[source] else 0;
        if (catalog == 0) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        const fields = self.tree.children(source);
        if (fields.len == 0 and self.checked.constructors[catalog].payload == 0)
            return self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog });
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        var destinations: std.ArrayList(Id) = .empty;
        defer destinations.deinit(self.allocator);
        const field_words = std.math.mul(usize, fields.len, 2) catch return error.CoreLimit;
        const field_types = try self.allocator.alloc(T.Id, field_words);
        defer self.allocator.free(field_types);
        @memset(field_types, 0);
        for (fields) |field| {
            const syntax = self.tree.node(field);
            const destination = self.checked.projections[field];
            if (destination >= fields.len) {
                try self.diagnostic(.unresolved_binding, field);
                return 0;
            }
            const value = if (syntax.b == 0) try self.resolvedReference(field, try self.typeOf(field)) else try self.expression(syntax.b, depth + 1);
            try values.append(self.allocator, value);
            try destinations.append(self.allocator, destination);
            field_types[destination * 2] = syntax.a;
            field_types[destination * 2 + 1] = self.nodes.items[value].ty;
        }
        const type_range = try self.saveTypes(field_types);
        const payload_ty = try self.addType(.{ .tag = .record, .a = type_range.start, .b = @intCast(fields.len) });
        const value_range = try self.save(values.items);
        const destination_range = try self.save(destinations.items);
        const payload = try self.make(source, .{ .tag = .record, .ty = payload_ty, .a = value_range.start, .b = value_range.len, .c = destination_range.start });
        return self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog, .b = payload });
    }
    fn addPattern(self: *Builder, source: ast.Id, value: Pattern) Error!PatternId {
        if (self.patterns.items.len == 0) try self.patterns.append(self.allocator, .{ .tag = .invalid });
        const index: PatternId = @intCast(self.patterns.items.len);
        var owned = value;
        owned.span = self.tree.span(source);
        try self.patterns.append(self.allocator, owned);
        return index;
    }
    fn patternNode(self: *Builder, source: ast.Id, depth: usize) Error!PatternId {
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const syntax = self.tree.node(source);
        const ty = try self.typeOf(source);
        return switch (syntax.tag) {
            .pattern_name => blk: {
                if (std.mem.eql(u8, self.names.get(syntax.a), "_")) break :blk try self.addPattern(source, .{ .tag = .wildcard, .ty = ty });
                const binding = self.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                break :blk try self.addPattern(source, .{ .tag = .bind, .ty = ty, .a = binding });
            },
            .pattern_integer, .pattern_boolean => self.addPattern(source, .{ .tag = .constant, .ty = ty, .a = syntax.a }),
            .pattern_value => self.addPattern(source, .{ .tag = .value, .ty = ty, .a = try self.resolvedReference(source, ty) }),
            .pattern_constructor => blk: {
                const catalog = self.checked.constructor_resolved[source];
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                const metadata = self.checked.constructors[catalog];
                var payload: PatternId = 0;
                if (metadata.payload != 0 and syntax.b != 0) {
                    payload = try self.patternNode(syntax.b, depth + 1);
                    const record = self.checked.types.node(metadata.payload);
                    if (record.tag == .record and self.tree.node(syntax.b).tag != .pattern_record) {
                        const child_ty = self.patterns.items[payload].ty;
                        const child = self.type_nodes.items[child_ty];
                        if (record.b == 0 or (record.b != 1 and (child.tag != .product or child.b != record.b))) return error.CoreLimit;
                        var fields: std.ArrayList(T.Id) = .empty;
                        defer fields.deinit(self.allocator);
                        for (0..record.b) |index| {
                            const field = self.checked.types.recordField(record, index);
                            const field_ty = if (record.b == 1) child_ty else self.type_extra.items[child.a + index];
                            try fields.appendSlice(self.allocator, &.{ field.name, field_ty });
                        }
                        const range = try self.saveTypes(fields.items);
                        const record_ty = try self.addType(.{ .tag = .record, .a = range.start, .b = record.b });
                        payload = try self.addPattern(syntax.b, .{ .tag = .record_payload, .ty = record_ty, .a = record.b, .b = payload });
                    }
                }
                break :blk try self.addPattern(source, .{ .tag = .constructor, .ty = ty, .a = catalog, .b = payload });
            },
            .pattern_product => blk: {
                if (self.tree.children(source).len == 0 and ty == T.unit)
                    break :blk try self.addPattern(source, .{ .tag = .constant, .ty = T.unit });
                var children: std.ArrayList(Id) = .empty;
                defer children.deinit(self.allocator);
                for (self.tree.children(source)) |child| try children.append(self.allocator, try self.patternNode(child, depth + 1));
                const range = try self.save(children.items);
                break :blk try self.addPattern(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
            },
            .pattern_record => blk: {
                const record_ty = self.type_nodes.items[ty];
                if (record_ty.tag != .record) {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                }
                const children = try self.allocator.alloc(Id, record_ty.b);
                defer self.allocator.free(children);
                for (children, 0..) |*child, index| child.* = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.type_extra.items[record_ty.a + index * 2 + 1] });
                for (self.tree.children(source)) |field| {
                    const field_syntax = self.tree.node(field);
                    const destination = self.checked.projections[field];
                    if (destination >= children.len) {
                        try self.diagnostic(.unresolved_binding, field);
                        break :blk 0;
                    }
                    if (field_syntax.b != 0) {
                        children[destination] = try self.patternNode(field_syntax.b, depth + 1);
                    } else {
                        const binding = self.checked.resolved[field];
                        const field_ty = self.type_extra.items[record_ty.a + destination * 2 + 1];
                        children[destination] = try self.addPattern(field, .{ .tag = if (binding == 0) .wildcard else .bind, .ty = field_ty, .a = binding });
                    }
                }
                const range = try self.save(children);
                break :blk try self.addPattern(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
            },
            else => blk: {
                try self.diagnostic(.unsupported, source);
                break :blk 0;
            },
        };
    }
    fn addPatternRow(self: *Builder, patterns: []const PatternId) Error!u32 {
        const range = try self.save(patterns);
        const index: u32 = @intCast(self.pattern_rows.items.len);
        try self.pattern_rows.append(self.allocator, .{ .patterns = range });
        return index;
    }
    fn caseExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!Id {
        const syntax = self.tree.node(source);
        const source_inputs = self.tree.extra.items[syntax.a..][0..2];
        var inputs: std.ArrayList(Id) = .empty;
        defer inputs.deinit(self.allocator);
        for (self.tree.list(.{ .start = source_inputs[0], .len = source_inputs[1] })) |input| try inputs.append(self.allocator, try self.expression(input, depth + 1));
        const input_range = try self.save(inputs.items);
        var arms: std.ArrayList(MatchArm) = .empty;
        defer arms.deinit(self.allocator);
        for (self.tree.list(.{ .start = syntax.b, .len = syntax.c })) |arm_source| {
            const arm_syntax = self.tree.node(arm_source);
            const row_start: u32 = @intCast(self.pattern_rows.items.len);
            for (self.tree.list(.{ .start = arm_syntax.a, .len = arm_syntax.b })) |row_source| {
                var patterns: std.ArrayList(Id) = .empty;
                defer patterns.deinit(self.allocator);
                for (self.tree.children(row_source)) |pattern_source| try patterns.append(self.allocator, try self.patternNode(pattern_source, depth + 1));
                _ = try self.addPatternRow(patterns.items);
            }
            const row_range: List = .{ .start = row_start, .len = @intCast(self.pattern_rows.items.len - row_start) };
            const details = self.tree.extra.items[arm_syntax.c..][0..2];
            try arms.append(self.allocator, .{ .rows = row_range, .guard = try self.expression(details[0], depth + 1), .body = try self.expression(details[1], depth + 1), .span = self.tree.span(arm_source) });
        }
        const arm_start: u32 = @intCast(self.match_arms.items.len);
        try self.match_arms.appendSlice(self.allocator, arms.items);
        const index: u32 = @intCast(self.matches.items.len);
        try self.matches.append(self.allocator, .{ .inputs = input_range, .arms = .{ .start = arm_start, .len = @intCast(arms.items.len) } });
        return self.make(source, .{ .tag = .match, .ty = ty, .a = index });
    }
    fn noteCapture(self: *Builder, binding: BindingId, epoch: u32, captures: *std.ArrayList(BindingId)) Error!void {
        if (binding == 0 or self.bindings.items[binding].kind == .global or self.bindings.items[binding].kind == .external) return;
        if (self.reference_epochs[binding] == epoch) return;
        self.reference_epochs[binding] = epoch;
        try captures.append(self.allocator, binding);
    }
    fn patternCaptures(self: *Builder, id: PatternId, epoch: u32, captures: *std.ArrayList(BindingId), depth: usize) Error!void {
        if (id == 0) return;
        if (depth >= 1024) return error.CoreLimit;
        const value = self.patterns.items[id];
        switch (value.tag) {
            .bind => self.definition_epochs[value.a] = epoch,
            .value => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .product => for (self.extra.items[value.a..][0..value.b]) |child| try self.patternCaptures(child, epoch, captures, depth + 1),
            .constructor, .record_payload => try self.patternCaptures(value.b, epoch, captures, depth + 1),
            else => {},
        }
    }
    /// Walk each direct body graph once. A nested closure contributes only its
    /// capture list, so its bound locals cannot leak into an enclosing frame.
    fn nodeCaptures(self: *Builder, id: Id, epoch: u32, captures: *std.ArrayList(BindingId), depth: usize) Error!void {
        if (id == 0 or self.visit_epochs.items[id] == epoch) return;
        if (depth >= 1024) return error.CoreLimit;
        self.visit_epochs.items[id] = epoch;
        const value = self.nodes.items[id];
        switch (value.tag) {
            .effect_reflection => {
                const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(value.a));
                if (kind == .count or kind == .has or kind == .same) try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                if (value.c != 0) try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .computation => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .request_decision => {
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .request_loop => {
                const info = self.request_loops.items[value.a];
                try self.nodeCaptures(info.computation, epoch, captures, depth + 1);
                for (self.request_arms.items[info.arms.start..][0..info.arms.len]) |arm| try self.nodeCaptures(arm.callback, epoch, captures, depth + 1);
                for (self.loop_carries.items[info.carries.start..][0..info.carries.len]) |carry| {
                    try self.noteCapture(carry.incoming, epoch, captures);
                    self.definition_epochs[carry.outgoing] = epoch;
                }
                for (self.extra.items[info.completion_state_bindings.start..][0..info.completion_state_bindings.len]) |binding| self.definition_epochs[binding] = epoch;
                try self.patternCaptures(info.completion_pattern, epoch, captures, depth + 1);
                try self.nodeCaptures(info.completion_body, epoch, captures, depth + 1);
            },
            .reference => {
                const ref = self.references.items[value.a];
                if (ref.unit == 0) try self.noteCapture(ref.binding, epoch, captures);
            },
            .closure, .suspend_ => {
                const range = self.closures.items[value.a].captures;
                for (self.extra.items[range.start..][0..range.len]) |binding| try self.noteCapture(binding, epoch, captures);
            },
            .resolver_op => {
                const info = self.resolver_ops.items[value.a];
                try self.nodeCaptures(info.resolver, epoch, captures, depth + 1);
                for (self.extra.items[info.arguments.start..][0..info.arguments.len]) |argument| try self.nodeCaptures(argument, epoch, captures, depth + 1);
            },
            .bind => {
                self.definition_epochs[value.a] = epoch;
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .return_, .result_associated, .force => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .block, .suite, .product, .record, .array, .array_op => {
                for (self.extra.items[value.a..][0..value.b]) |child| try self.nodeCaptures(child, epoch, captures, depth + 1);
            },
            .call, .break_ => for (self.extra.items[value.b..][0..value.c]) |child| try self.nodeCaptures(child, epoch, captures, depth + 1),
            .loop => {
                const info = self.loops.items[value.a];
                try self.nodeCaptures(info.first, epoch, captures, depth + 1);
                try self.nodeCaptures(info.end, epoch, captures, depth + 1);
                const carries = self.loop_carries.items[info.carries.start..][0..info.carries.len];
                for (carries) |carry| {
                    try self.noteCapture(carry.incoming, epoch, captures);
                    self.definition_epochs[carry.iteration] = epoch;
                    self.definition_epochs[carry.outgoing] = epoch;
                }
                try self.patternCaptures(info.pattern, epoch, captures, depth + 1);
                try self.nodeCaptures(info.body, epoch, captures, depth + 1);
                for (carries) |carry| try self.noteCapture(carry.backedge, epoch, captures);
            },
            .scalar, .logical, .apply, .associated, .type_same, .effect_provider, .handle => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .if_value, .if_stmt, .state_provider => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .construct => try self.nodeCaptures(value.b, epoch, captures, depth + 1),
            .project => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .pattern_bind => {
                try self.patternCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .match => {
                const info = self.matches.items[value.a];
                for (self.extra.items[info.inputs.start..][0..info.inputs.len]) |input| try self.nodeCaptures(input, epoch, captures, depth + 1);
                for (self.match_arms.items[info.arms.start..][0..info.arms.len]) |arm| {
                    for (self.pattern_rows.items[arm.rows.start..][0..arm.rows.len]) |row| {
                        for (self.extra.items[row.patterns.start..][0..row.patterns.len]) |pattern| try self.patternCaptures(pattern, epoch, captures, depth + 1);
                    }
                    try self.nodeCaptures(arm.guard, epoch, captures, depth + 1);
                    try self.nodeCaptures(arm.body, epoch, captures, depth + 1);
                }
            },
            .update => {
                const info = self.updates.items[value.a];
                if (info.self_binding != 0) self.definition_epochs[info.self_binding] = epoch;
                try self.nodeCaptures(info.root, epoch, captures, depth + 1);
                for (self.update_steps.items[info.selectors.start..][0..info.selectors.len]) |step| try self.nodeCaptures(step.index, epoch, captures, depth + 1);
                try self.nodeCaptures(info.value, epoch, captures, depth + 1);
            },
            else => {},
        }
        const range = self.merge_ranges.items[id];
        for (self.merges.items[range.start..][0..range.len]) |merge| {
            self.definition_epochs[merge.result] = epoch;
            try self.noteCapture(merge.then_binding, epoch, captures);
            try self.noteCapture(merge.else_binding, epoch, captures);
        }
    }
    fn closureExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!Id {
        const syntax = self.tree.node(source);
        const parameter: Parameter = .{ .binding = self.checked.resolved[syntax.a], .ty = try self.typeOf(syntax.a), .span = self.checked.diagnosticSpan(self.tree, syntax.a) };
        const previous = self.return_target;
        self.return_target = 0;
        const body = self.expression(syntax.b, depth + 1) catch |err| {
            self.return_target = previous;
            return err;
        };
        self.return_target = previous;
        const index = try self.captureClosure(body, parameter, ty);
        if (source < self.checked.lambda_closed_rows.len)
            self.closures.items[index].closed_rows = try self.projectedRowVariables(self.checked.lambda_closed_rows[source]);
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    fn captureClosure(self: *Builder, body: Id, parameter: Parameter, function_type: T.Id) Error!u32 {
        if (self.definition_epochs.len == 0) {
            try self.allocateEmpty(&self.definition_epochs, self.bindings.items.len);
            try self.allocateEmpty(&self.reference_epochs, self.bindings.items.len);
        }
        try self.growCaptureEpochs(&self.definition_epochs);
        try self.growCaptureEpochs(&self.reference_epochs);
        const old_len = self.visit_epochs.items.len;
        try self.visit_epochs.resize(self.allocator, self.nodes.items.len);
        @memset(self.visit_epochs.items[old_len..], 0);
        if (self.capture_epoch == std.math.maxInt(u32)) return error.CoreLimit;
        self.capture_epoch += 1;
        const epoch = self.capture_epoch;
        if (parameter.binding != 0) self.definition_epochs[parameter.binding] = epoch;
        var captures: std.ArrayList(BindingId) = .empty;
        defer captures.deinit(self.allocator);
        try self.nodeCaptures(body, epoch, &captures, 0);
        var count: usize = 0;
        for (captures.items) |binding| {
            if (self.definition_epochs[binding] != epoch) {
                captures.items[count] = binding;
                count += 1;
            }
        }
        const range = try self.save(captures.items[0..count]);
        const index: u32 = @intCast(self.closures.items.len);
        try self.closures.append(self.allocator, .{ .body = body, .parameter = parameter, .captures = range, .function_type = function_type });
        return index;
    }
    fn growCaptureEpochs(self: *Builder, epochs: *[]u32) Error!void {
        const old_len = epochs.*.len;
        if (old_len >= self.bindings.items.len) return;
        epochs.* = try self.allocator.realloc(epochs.*, self.bindings.items.len);
        @memset(epochs.*[old_len..], 0);
    }
    fn suspensionExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!Id {
        if (self.type_nodes.items[ty].tag != .demand) return error.CoreLimit;
        const previous = self.return_target;
        self.return_target = 0;
        const body = self.expression(source, depth + 1) catch |err| {
            self.return_target = previous;
            return err;
        };
        self.return_target = previous;
        const demanded = self.type_nodes.items[ty];
        const function_type = try self.addType(.{ .tag = .function, .a = T.unit, .b = demanded.a, .c = demanded.c });
        const index = try self.captureClosure(body, .{ .binding = 0, .ty = T.unit, .span = self.tree.span(source) }, function_type);
        return self.make(source, .{ .tag = .suspend_, .ty = ty, .a = index });
    }
    fn taggedExpression(self: *Builder, attributes: []const ast.Id, source: ast.Id, depth: usize) Error!Id {
        if (depth >= 1024) return error.CoreLimit;
        if (attributes.len == 0) return self.expression(source, depth + 1);
        const attribute = attributes[0];
        const callee = try self.expression(self.tree.node(attribute).a, depth + 1);
        const argument = try self.taggedExpression(attributes[1..], source, depth + 1);
        const call = try self.make(attribute, .{ .tag = .apply, .ty = try self.typeOf(attribute), .a = callee, .b = argument });
        try self.tag_calls.append(self.allocator, call);
        return call;
    }
    fn selectorExpression(self: *Builder, source: ast.Id, ty: T.Id) Error!Id {
        const function = self.type_nodes.items[ty];
        if (function.tag != .function) return error.CoreLimit;
        const body = try self.resolvedReference(source, function.b);
        const index: u32 = @intCast(self.closures.items.len);
        try self.closures.append(self.allocator, .{ .body = body, .parameter = .{ .binding = self.checked.resolved[source], .ty = function.a, .span = self.tree.span(source) }, .captures = .{}, .function_type = ty });
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    fn primitiveExpression(self: *Builder, source: ast.Id, ty: T.Id) Error!Id {
        const text = self.names.get(self.tree.node(source).a);
        const metadata: Primitive = if (intrinsic(text)) |value| .{ .kind = .scalar, .op = value.op, .arity = value.arity } else if (arrayIntrinsic(text)) |value| .{ .kind = .array, .array_op = value.op, .arity = value.arity } else {
            try self.diagnostic(.unsupported, source);
            return 0;
        };
        var index: u32 = 0;
        while (index < self.primitives.items.len) : (index += 1) {
            const previous = self.primitives.items[index];
            if (previous.kind == metadata.kind and previous.op == metadata.op and previous.array_op == metadata.array_op and previous.arity == metadata.arity) break;
        }
        if (index == self.primitives.items.len) try self.primitives.append(self.allocator, metadata);
        return self.make(source, .{ .tag = .primitive_function, .ty = ty, .a = index });
    }
    fn expression(self: *Builder, original: ast.Id, depth: usize) Error!Id {
        if (original == 0) return 0;
        if (self.ast_map[original] != 0) return self.ast_map[original];
        if (depth >= 1024) {
            try self.diagnostic(.complexity, original);
            return 0;
        }
        const source = self.unwrap(original);
        if (source != original) {
            const id = try self.expression(source, depth + 1);
            self.ast_map[original] = id;
            return id;
        }
        const syntax = self.tree.node(source);
        const ty = try self.typeOf(source);
        const runner = if (source < self.checked.effect_runner_ids.len) self.checked.effect_runner_ids[source] else 0;
        if (runner != 0) {
            const result = try self.effectRunner(source, self.checked.effect_runners[runner - 1], depth + 1);
            self.ast_map[source] = result;
            return result;
        }
        if (self.checked.reflection(source)) |reflection| {
            const left = switch (reflection.kind) {
                .of => try self.projectRow(reflection.row, 0),
                .descriptor => try self.projectOperation(reflection.label, 0),
                .count, .has, .same => try self.expression(reflection.left, depth + 1),
            };
            const right = if (reflection.right == 0) 0 else try self.expression(reflection.right, depth + 1);
            const result = try self.make(source, .{ .tag = .effect_reflection, .ty = ty, .a = @backingInt(reflection.kind), .b = left, .c = right });
            if (reflection.kind == .of) try self.erased_declaration_references.append(self.allocator, .{ .node = result, .target = self.target(reflection.binding) });
            self.ast_map[source] = result;
            return result;
        }
        for (self.checked.computations) |computation| if (computation.node == source) {
            const result = try self.make(source, .{ .tag = .computation, .ty = ty, .a = try self.expression(computation.action, depth + 1) });
            self.ast_map[source] = result;
            return result;
        };
        const operation = if (source < self.checked.operation_refs.len) self.checked.operation_refs[source] else 0;
        if (operation != 0) {
            if (operation > self.checked.operation_uses.len) return error.CoreLimit;
            const use = self.checked.operation_uses[operation - 1];
            if (use.template == 0 or use.template >= self.checked.effect_templates.len) return error.CoreLimit;
            const catalog: u32 = @intCast(self.operation_values.items.len);
            const metadata: OperationValue = .{ .identity = self.checked.effect_templates[use.template].identity, .arguments = try self.projectedTypeList(use.arguments), .signature = try self.projectType(use.signature, 0) };
            try self.operation_values.append(self.allocator, metadata);
            const operation_ty = if (use.call == .value) ty else metadata.signature;
            const operation_node = try self.make(source, .{ .tag = .operation_value, .ty = operation_ty, .a = catalog });
            const result = if (use.call == .value) operation_node else blk: {
                var prefix: std.ArrayList(Id) = .empty;
                defer prefix.deinit(self.allocator);
                const operand = try self.runnerOperand(use.operand, try self.typeOf(use.operand), &prefix, depth + 1);
                if (use.call == .state_read) {
                    self.operation_values.items[catalog].witness = operand;
                    self.operation_values.items[catalog].witness_result = ty;
                }
                const argument = if (use.call == .state_read) try self.make(source, .{ .tag = .constant, .ty = T.unit }) else operand;
                const call = try self.make(source, .{ .tag = .apply, .ty = ty, .a = operation_node, .b = argument });
                break :blk try self.sequenceValue(source, prefix.items, call);
            };
            self.ast_map[source] = result;
            return result;
        }
        const result: Id = switch (syntax.tag) {
            .integer, .float, .boolean => try self.make(source, .{ .tag = .constant, .ty = ty, .a = syntax.a }),
            .unit => try self.make(source, .{ .tag = .constant, .ty = T.unit }),
            .name => if (self.type_nodes.items[ty].tag == .type_constructor and self.checked.resolved[source] == 0)
                try self.make(source, .{ .tag = .type_constructor, .ty = ty })
            else
                try self.resolvedReference(source, ty),
            .selector => try self.selectorExpression(source, ty),
            .intrinsic => try self.primitiveExpression(source, ty),
            .field_access => blk: {
                const catalog = if (source < self.checked.projection_resolved.len) self.checked.projection_resolved[source] else 0;
                if (catalog == 0) {
                    if (self.type_nodes.items[ty].tag == .type_constructor and self.checked.resolved[source] == 0)
                        break :blk try self.make(source, .{ .tag = .type_constructor, .ty = ty });
                    break :blk try self.resolvedReference(source, ty);
                }
                const owner = try self.expression(syntax.a, depth + 1);
                const projection = try self.projectionIndex(catalog, self.nodes.items[owner].ty, ty);
                break :blk try self.make(source, .{ .tag = .project, .ty = ty, .a = owner, .b = projection });
            },
            .product => try self.productExpression(source, ty, .product, depth + 1),
            .array => try self.productExpression(source, ty, .array, depth + 1),
            .index_access => blk: {
                const values = try self.save(&.{ try self.expression(syntax.a, depth + 1), try self.expression(syntax.b, depth + 1) });
                break :blk try self.make(source, .{ .tag = .array_op, .ty = ty, .a = values.start, .b = values.len, .c = @backingInt(ArrayOp.get) });
            },
            .record => try self.recordExpression(source, ty, depth + 1),
            .type_witness => blk: {
                const catalog = if (source < self.checked.constructor_resolved.len) self.checked.constructor_resolved[source] else 0;
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                break :blk try self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog, .b = try self.expression(syntax.a, depth + 1) });
            },
            .lambda => try self.closureExpression(source, ty, depth + 1),
            .case_expr => try self.caseExpression(source, ty, depth + 1),
            .constructor_ref => blk: {
                const catalog = if (source < self.checked.constructor_resolved.len) self.checked.constructor_resolved[source] else 0;
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                if (self.checked.constructors[catalog].payload != 0) break :blk try self.make(source, .{ .tag = .constructor_function, .ty = ty, .a = catalog });
                break :blk try self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog });
            },
            .apply => try self.application(source, depth + 1),
            .binary => blk: {
                const left = if (self.checked.demand_binary_left[source])
                    try self.suspensionExpression(syntax.b, try self.projectType(self.checked.demand_binary_left_types[source], 0), depth + 1)
                else
                    try self.expression(syntax.b, depth + 1);
                const right = if (self.checked.demand_calls[source])
                    try self.suspensionExpression(syntax.c, try self.projectType(self.checked.demand_types[source], 0), depth + 1)
                else
                    try self.expression(syntax.c, depth + 1);
                const binding = self.checked.resolved[source];
                if (binding != 0) break :blk try self.namedCall(source, binding, &.{ left, right }, ty);
                const op = binaryOp(self.names.get(syntax.a)) orelse {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                };
                break :blk try self.make(source, .{ .tag = if (op == .and_ or op == .or_) .logical else .scalar, .op = op, .ty = ty, .a = left, .b = right, .c = 1 });
            },
            .unary => blk: {
                if (!std.mem.eql(u8, self.names.get(syntax.a), "-")) {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                }
                break :blk try self.make(source, .{ .tag = .scalar, .op = .neg, .ty = ty, .a = try self.expression(syntax.b, depth + 1) });
            },
            .if_expr => try self.make(source, .{ .tag = .if_value, .ty = ty, .a = try self.expression(syntax.a, depth + 1), .b = try self.expression(syntax.b, depth + 1), .c = try self.expression(syntax.c, depth + 1) }),
            .block => blk: {
                if (syntax.c != 0) {
                    const provider = self.checked.provider_block_ids[source];
                    if (provider != 0) break :blk try self.providerBlock(source, self.checked.provider_blocks[provider - 1], depth + 1);
                    const index = self.checked.resolver_block_ids[source];
                    if (index == 0) {
                        try self.diagnostic(.unresolved_binding, source);
                        break :blk 0;
                    }
                    break :blk try self.resolverBlock(source, self.checked.resolver_blocks[index - 1], depth + 1);
                }
                const id = try self.reserve(source);
                const previous = self.return_target;
                self.return_target = id;
                defer self.return_target = previous;
                const children = try self.statements(source, depth + 1);
                self.nodes.items[id] = .{ .tag = .block, .ty = ty, .a = children.start, .b = children.len };
                break :blk id;
            },
            else => blk: {
                try self.diagnostic(.unsupported, source);
                break :blk 0;
            },
        };
        self.ast_map[source] = result;
        return result;
    }
    fn providerBlock(self: *Builder, source: ast.Id, metadata: checked_types.ProviderBlock, depth: usize) Error!Id {
        const provider = try self.expression(metadata.provider, depth + 1);
        const inner = try self.reserve(source);
        const previous = self.return_target;
        self.return_target = inner;
        defer self.return_target = previous;
        const children = try self.statements(source, depth + 1);
        self.nodes.items[inner] = .{ .tag = .block, .ty = try self.projectType(metadata.body_result, 0), .a = children.start, .b = children.len };
        return self.make(source, .{ .tag = .handle, .ty = try self.projectType(metadata.result, 0), .a = provider, .b = inner });
    }
    fn runnerOperand(self: *Builder, source: ast.Id, ty: T.Id, prefix: *std.ArrayList(Id), depth: usize) Error!Id {
        const value = try self.expression(source, depth + 1);
        if (self.bindings.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const binding: BindingId = @intCast(self.bindings.items.len);
        try self.bindings.append(self.allocator, .{ .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .target = .{ .binding = 0 }, .span = self.tree.span(source) });
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value }));
        return self.referenceNode(source, binding, ty);
    }
    fn runnerOperation(self: *Builder, source: ast.Id, token: T.Id, parameter: T.Id, result: T.Id, row: T.Effects.Id) Error!Id {
        const identity = self.type_nodes.items[token];
        if (identity.tag != .nominal) return error.CoreLimit;
        const count = self.type_extra.items[identity.c];
        const signature = try self.addType(.{ .tag = .function, .a = parameter, .b = result, .c = row });
        const index: u32 = @intCast(self.operation_values.items.len);
        try self.operation_values.append(self.allocator, .{ .identity = .{ .unit = identity.a, .decl = identity.b }, .arguments = .{ .start = identity.c + 1, .len = count }, .signature = signature });
        return self.make(source, .{ .tag = .operation_value, .ty = signature, .a = index });
    }
    fn effectRunner(self: *Builder, source: ast.Id, metadata: checked_types.EffectRunner, depth: usize) Error!Id {
        var prefix: std.ArrayList(Id) = .empty;
        defer prefix.deinit(self.allocator);
        const state = try self.projectType(metadata.state_type, 0);
        const result = try self.projectType(metadata.body_result, 0);
        const outer = try self.projectRow(metadata.outer_effects, 0);
        const extended = try self.projectRow(metadata.body_effects, 0);
        const read = try self.projectType(metadata.read_token, 0);
        const write = try self.projectType(metadata.write_token, 0);
        const initial = if (metadata.kind == .run) try self.runnerOperand(metadata.initial, state, &prefix, depth + 1) else 0;
        const witness = if (metadata.witness != 0) try self.runnerOperand(metadata.witness, try self.typeOf(metadata.witness), &prefix, depth + 1) else 0;
        const implementation = if (metadata.implementation != 0) try self.runnerOperand(metadata.implementation, try self.projectType(metadata.implementation_type, 0), &prefix, depth + 1) else 0;
        const action = try self.runnerOperand(metadata.action, try self.projectType(metadata.action_type, 0), &prefix, depth + 1);
        const first = if (read != 0) read else write;
        const provider = if (metadata.kind == .run) blk: {
            const reader = try self.runnerOperation(source, read, T.unit, state, extended);
            const writer = try self.runnerOperation(source, write, state, T.unit, extended);
            const ty = try self.addType(.{ .tag = .state_provider, .a = read, .b = write, .c = state });
            break :blk try self.make(source, .{ .tag = .state_provider, .ty = ty, .a = reader, .b = writer, .c = initial });
        } else blk: {
            const operation = try self.runnerOperation(source, first, if (read != 0) T.unit else state, if (read != 0) state else T.unit, extended);
            const operation_index = self.nodes.items[operation].a;
            self.operation_values.items[operation_index].witness = witness;
            self.operation_values.items[operation_index].witness_result = state;
            const ty = try self.addType(.{ .tag = .provider, .a = first, .c = outer });
            break :blk try self.make(source, .{ .tag = .effect_provider, .ty = ty, .a = operation, .b = implementation });
        };
        const unit = try self.make(source, .{ .tag = .constant, .ty = T.unit });
        const call = try self.make(source, .{ .tag = .apply, .ty = result, .a = action, .b = unit });
        const handler = try self.make(source, .{ .tag = .handle, .ty = try self.projectType(metadata.result, 0), .a = provider, .b = call, .c = @intCast(self.handle_effects.items.len + 1) });
        try self.handle_effects.append(self.allocator, .{ .node = handler, .first = first, .second = if (metadata.kind == .run) write else 0, .extended = extended, .residual = outer });
        return self.sequenceValue(source, prefix.items, handler);
    }
    fn namedCall(self: *Builder, source: ast.Id, binding: BindingId, arguments: []const Id, result: T.Id) Error!Id {
        var callee_type = result;
        if (self.signature_sources.len != 0 and self.signature_sources[source] != 0) {
            callee_type = try self.projectType(self.signature_sources[source], 0);
        } else {
            var i = arguments.len;
            while (i != 0) {
                i -= 1;
                callee_type = try self.addType(.{ .tag = .function, .a = self.nodes.items[arguments[i]].ty, .b = callee_type });
            }
        }
        const kind = self.checked.bindings[binding].kind;
        if (kind == .local or kind == .parameter) {
            // Backtick names resolve to this lexical binding version. Their
            // checked call signature belongs to this use, as ordinary apply.
            var value = try self.referenceNode(source, binding, callee_type);
            for (arguments) |argument| {
                const signature = self.type_nodes.items[self.nodes.items[value].ty];
                if (signature.tag != .function) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                value = try self.make(source, .{ .tag = .apply, .ty = signature.b, .a = value, .b = argument });
            }
            return value;
        }
        return self.typedNamedCall(source, binding, arguments, result, callee_type);
    }
    fn typedNamedCall(self: *Builder, source: ast.Id, binding: BindingId, arguments: []const Id, result: T.Id, callee_type: T.Id) Error!Id {
        const index: u32 = @intCast(self.calls.items.len);
        try self.calls.append(self.allocator, .{ .target = self.target(binding), .callee_type = callee_type });
        const values = try self.save(arguments);
        return self.make(source, .{ .tag = .call, .ty = result, .a = index, .b = values.start, .c = values.len });
    }
    fn directArity(self: *const Builder, original: BindingId) ?usize {
        var binding = original;
        for (0..256) |_| {
            const metadata = self.checked.bindings[binding];
            if (metadata.kind == .external) return null;
            if (metadata.kind != .global) return 0;
            var source = self.unwrap(self.tree.valueDecl(metadata.declaration).body);
            var count: usize = 0;
            while (self.tree.node(source).tag == .lambda) {
                count += 1;
                source = self.unwrap(self.tree.node(source).b);
            }
            if (count != 0) return count;
            if (self.tree.node(source).tag != .name or self.checked.resolved[source] == 0) return 0;
            binding = self.checked.resolved[source];
        }
        return 0;
    }
    const ApplicationArgument = struct { value: ast.Id, site: ast.Id };
    fn appliedValue(self: *Builder, source: ast.Id, callee: ast.Id, arguments: []const Id, sites: []const ApplicationArgument, depth: usize) Error!Id {
        if (arguments.len != sites.len) return error.CoreLimit;
        var value = try self.expression(callee, depth + 1);
        for (arguments, 0..) |argument, index| {
            if (value == 0) return 0;
            const signature = self.type_nodes.items[self.nodes.items[value].ty];
            if (signature.tag != .function and signature.tag != .never) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            // Preserve all checked operands and each application's semantic
            // result, including a callee that cannot produce a callable.
            const site = sites[sites.len - index - 1].site;
            value = try self.make(site, .{ .tag = .apply, .ty = try self.typeOf(site), .a = value, .b = argument });
        }
        return value;
    }
    fn application(self: *Builder, source: ast.Id, depth: usize) Error!Id {
        // Ordinary scalar calls fit in stack scratch; larger surface calls
        // retain the same heap-backed growth and explicit cleanup behavior.
        var backwards_storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var backwards_storage: std.heap.BufferFirstAllocator = .init(&backwards_storage_buffer, self.allocator);
        const backwards_allocator = backwards_storage.allocator();
        var backwards: std.ArrayList(ApplicationArgument) = .empty;
        defer backwards.deinit(backwards_allocator);
        // Zig's default growth starts above a cache line; precise initial
        // capacity prevents a one-argument call from bypassing stack scratch.
        try backwards.ensureTotalCapacityPrecise(backwards_allocator, 16);
        var callee = source;
        while (self.tree.node(callee).tag == .apply) {
            const value = self.tree.node(callee);
            try backwards.append(backwards_allocator, .{ .value = value.b, .site = callee });
            const inner = self.unwrap(value.a);
            if (inner < self.checked.operation_refs.len and self.checked.operation_refs[inner] != 0) {
                callee = inner;
                break;
            }
            // A grouped application may have already saturated a compiler
            // primitive and produced a callable. Preserve that call boundary
            // rather than counting its later runtime arguments as intrinsic
            // operands, as in (@array.get callbacks index) ().
            if (self.tree.node(value.a).tag == .group and self.tree.node(self.unwrap(value.a)).tag == .apply) {
                callee = value.a;
                break;
            }
            callee = self.unwrap(value.a);
        }
        const syntax = self.tree.node(callee);
        const result = try self.typeOf(source);
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@effect.provider")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operation = try self.expression(backwards.items[1].value, depth + 1);
            const implementation = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .effect_provider, .ty = result, .a = operation, .b = implementation });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@effect.state")) {
            if (backwards.items.len != 3) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const read = try self.expression(backwards.items[2].value, depth + 1);
            const write = try self.expression(backwards.items[1].value, depth + 1);
            const initial = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .state_provider, .ty = result, .a = read, .b = write, .c = initial });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@do.monad")) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            return self.resolverNode(source, .{ .operation = .monad, .resolver = operand }, &.{}, result);
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@panic")) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const literal = self.tree.node(self.unwrap(backwards.items[0].value));
            if (literal.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const message = self.names.get(literal.a);
            if (message.len > std.math.maxInt(u32) - self.name_bytes.items.len) return error.CoreLimit;
            const start: u32 = @intCast(self.name_bytes.items.len);
            try self.name_bytes.appendSlice(self.allocator, message);
            return self.make(source, .{ .tag = .panic, .ty = result, .a = start, .b = @intCast(message.len) });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@force")) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .force, .ty = result, .a = operand });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@type.same")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const left = try self.expression(backwards.items[1].value, depth + 1);
            const right = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .type_same, .ty = result, .a = left, .b = right });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@type.result")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const member = self.tree.node(self.unwrap(backwards.items[1].value));
            if (member.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            const binding = self.checked.resolved[source];
            if (binding != 0) return self.namedCall(source, binding, &.{operand}, result);
            return self.make(source, .{ .tag = .result_associated, .ty = result, .a = operand, .b = member.a });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.names.get(syntax.a), "@type.call")) {
            if (backwards.items.len != 3) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const member = self.tree.node(self.unwrap(backwards.items[2].value));
            if (member.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const left = try self.expression(backwards.items[1].value, depth + 1);
            const right = try self.expression(backwards.items[0].value, depth + 1);
            const binding = self.checked.resolved[source];
            if (binding != 0) return self.namedCall(source, binding, &.{ left, right }, result);
            return self.make(source, .{ .tag = .associated, .op = memberOp(self.names.get(member.a)), .ty = result, .a = left, .b = right, .c = member.a });
        }
        var arguments_storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var arguments_storage: std.heap.BufferFirstAllocator = .init(&arguments_storage_buffer, self.allocator);
        const arguments_allocator = arguments_storage.allocator();
        var arguments: std.ArrayList(Id) = .empty;
        defer arguments.deinit(arguments_allocator);
        try arguments.ensureTotalCapacityPrecise(arguments_allocator, @min(backwards.items.len, 16));
        var i = backwards.items.len;
        while (i != 0) {
            i -= 1;
            const argument = backwards.items[i];
            const value = if (self.checked.demand_calls[argument.site])
                try self.suspensionExpression(argument.value, try self.projectType(self.checked.demand_types[argument.site], 0), depth + 1)
            else
                try self.expression(argument.value, depth + 1);
            try arguments.append(arguments_allocator, value);
        }
        if (syntax.tag == .constructor_ref) {
            const catalog = if (callee < self.checked.constructor_resolved.len) self.checked.constructor_resolved[callee] else 0;
            if (catalog == 0 or arguments.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const payload = self.checked.constructors[catalog].payload;
            const record = payload != 0 and self.checked.types.node(payload).tag == .record;
            return self.make(source, .{ .tag = .construct, .ty = result, .a = catalog, .b = arguments.items[0], .c = @intFromBool(record) });
        }
        if (syntax.tag == .intrinsic) {
            if (arrayIntrinsic(self.names.get(syntax.a))) |primitive| {
                if (arguments.items.len < primitive.arity) return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
                if (arguments.items.len != primitive.arity) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                const values = try self.save(arguments.items);
                return self.make(source, .{ .tag = .array_op, .ty = result, .a = values.start, .b = values.len, .c = @backingInt(primitive.op) });
            }
            if (std.mem.eql(u8, self.names.get(syntax.a), "@product.get")) {
                if (arguments.items.len != 2 or self.tree.node(self.unwrap(backwards.items[0].value)).tag != .integer) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                const field = self.tree.node(self.unwrap(backwards.items[0].value)).a;
                const projection = try self.directProjection(self.nodes.items[arguments.items[0]].ty, result, field);
                return self.make(source, .{ .tag = .project, .ty = result, .a = arguments.items[0], .b = projection });
            }
            const primitive = intrinsic(self.names.get(syntax.a)) orelse {
                try self.diagnostic(.unsupported, source);
                return 0;
            };
            if (arguments.items.len < primitive.arity) return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
            if (arguments.items.len != primitive.arity) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            return self.make(source, .{ .tag = .scalar, .op = primitive.op, .ty = result, .a = arguments.items[0], .b = if (primitive.arity == 2) arguments.items[1] else 0 });
        }
        const binding = self.checked.resolved[callee];
        if (binding != 0 and self.checked.operation_refs[callee] == 0 and (syntax.tag == .name or syntax.tag == .field_access) and
            (self.checked.bindings[binding].kind == .global or self.checked.bindings[binding].kind == .external) and
            (callee >= self.checked.access_paths.len or self.checked.access_paths[callee].len == 0) and
            self.type_nodes.items[result].tag != .function)
        {
            const arity = self.directArity(binding);
            if (arity == null or arity.? == arguments.items.len) return self.typedNamedCall(source, binding, arguments.items, result, try self.typeOf(callee));
        }
        return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
    }
    fn resolverNode(self: *Builder, source: ast.Id, original: ResolverInfo, arguments: []const Id, result: T.Id) Error!Id {
        var info = original;
        info.arguments = try self.save(arguments);
        if (self.resolver_ops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const index: u32 = @intCast(self.resolver_ops.items.len);
        try self.resolver_ops.append(self.allocator, info);
        return self.make(source, .{ .tag = .resolver_op, .ty = result, .a = index });
    }
    fn checkedResolverNode(self: *Builder, info: checked_types.ResolverOp, arguments: []const Id) Error!Id {
        const resolver = try self.referenceNode(info.node, info.resolver, self.bindings.items[info.resolver].ty);
        const operation: ResolverOperation = switch (info.kind) {
            .monad => .monad,
            .pure => .pure,
            .bind => .bind,
            .forward => .forward,
            .iterate => .iterate,
        };
        return self.resolverNode(info.node, .{
            .operation = operation,
            .resolver = resolver,
            .member = info.member,
            .method = if (info.method == 0) .{ .binding = 0 } else self.target(info.method),
            .method_type = try self.projectType(info.method_type, 0),
        }, arguments, try self.projectType(info.result, 0));
    }
    fn closureNode(self: *Builder, source: ast.Id, body: Id, parameter: Parameter, ty: T.Id) Error!Id {
        const index = try self.captureClosure(body, parameter, ty);
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    /// Source statements remain ordinary owned IR. A private value block makes
    /// their final expression explicit without a return crossing a callback.
    fn sequenceValue(self: *Builder, source: ast.Id, prefix: []const Id, value: Id) Error!Id {
        if (prefix.len == 0) return value;
        const id = try self.reserve(source);
        var children: std.ArrayList(Id) = .empty;
        defer children.deinit(self.allocator);
        try children.appendSlice(self.allocator, prefix);
        try children.append(self.allocator, try self.make(source, .{ .tag = .return_, .ty = T.never, .a = value, .b = id }));
        const range = try self.save(children.items);
        self.nodes.items[id] = .{ .tag = .block, .ty = self.nodes.items[value].ty, .a = range.start, .b = range.len };
        return id;
    }
    fn resolverBlock(self: *Builder, source: ast.Id, info: checked_types.ResolverBlock, depth: usize) Error!Id {
        const previous = self.return_target;
        self.return_target = 0;
        defer self.return_target = previous;
        const syntax = self.tree.node(source);
        const provider = try self.expression(syntax.c, depth + 1);
        const binding = try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.resolver, .b = provider });
        var tail: Id = 0;
        if (info.fallthrough != 0) {
            const unit_value = try self.make(source, .{ .tag = .constant, .ty = T.unit });
            tail = try self.checkedResolverNode(self.checked.resolver_ops[info.fallthrough - 1], &.{unit_value});
        }
        const body = try self.resolverStatements(source, self.tree.children(source), tail, depth + 1);
        const result = try self.projectType(info.result, 0);
        const fn_type = try self.addType(.{ .tag = .function, .a = T.unit, .b = result });
        const action = try self.closureNode(source, body, .{ .binding = 0, .ty = T.unit, .span = self.tree.span(source) }, fn_type);
        const resolver = try self.referenceNode(source, info.resolver, self.bindings.items[info.resolver].ty);
        const run = try self.resolverNode(source, .{ .operation = .run, .resolver = resolver }, &.{action}, result);
        return self.sequenceValue(source, &.{binding}, run);
    }
    fn resolverStatements(self: *Builder, source: ast.Id, statements_: []const ast.Id, tail: Id, depth: usize) Error!Id {
        if (depth >= 1024) return error.CoreLimit;
        if (statements_.len == 0) return tail;
        // Ordinary statements do not introduce a continuation. Retain them in
        // one ordered block instead of making source length become IR nesting
        // and recursively lowering an identical suffix for every statement.
        var ordinary: usize = 0;
        while (ordinary < statements_.len) {
            const child = statements_[ordinary];
            const simple = switch (self.tree.node(child).tag) {
                .return_stmt,
                .break_stmt,
                .use_stmt,
                .if_stmt,
                .if_let_stmt,
                .for_stmt,
                .range_stmt,
                .forever_stmt,
                => false,
                .let_stmt => self.tree.binding(child).fallback == 0,
                else => true,
            };
            if (!simple) break;
            ordinary += 1;
        }
        if (ordinary != 0) {
            var prefix: std.ArrayList(Id) = .empty;
            defer prefix.deinit(self.allocator);
            for (statements_[0..ordinary]) |child| try prefix.append(self.allocator, try self.statement(child, depth + 1));
            const next = try self.resolverStatements(source, statements_[ordinary..], tail, depth + 1);
            return self.sequenceValue(statements_[0], prefix.items, next);
        }
        const statement_source = statements_[0];
        const syntax = self.tree.node(statement_source);
        if (syntax.tag == .return_stmt) {
            const index = self.checked.resolver_op_ids[statement_source];
            if (index == 0) return error.CoreLimit;
            const info = self.checked.resolver_ops[index - 1];
            var value = try self.expression(syntax.a, depth + 1);
            if (info.completion != 0) return self.resolverComplete(info.completion, value);
            value = try self.completedValue(statement_source, value, info.completed_types, info.done_constructor);
            return self.checkedResolverNode(info, &.{value});
        }
        if (syntax.tag == .break_stmt) return self.resolverBreak(statement_source);
        const next = try self.resolverStatements(source, statements_[1..], tail, depth + 1);
        switch (syntax.tag) {
            .use_stmt => {
                const index = self.checked.resolver_op_ids[statement_source];
                if (index == 0) return error.CoreLimit;
                const info = self.checked.resolver_ops[index - 1];
                const candidate = try self.expression(syntax.b, depth + 1);
                const method_type = self.type_nodes.items[try self.projectType(info.method_type, 0)];
                if (method_type.tag != .function) return error.CoreLimit;
                const after_candidate = self.type_nodes.items[method_type.b];
                if (after_candidate.tag != .function) return error.CoreLimit;
                const fn_type = after_candidate.a;
                const signature = self.type_nodes.items[fn_type];
                if (signature.tag != .function) return error.CoreLimit;
                const continuation = try self.closureNode(statement_source, next, .{
                    .binding = info.continuation_parameter,
                    .ty = signature.a,
                    .span = self.tree.span(statement_source),
                }, fn_type);
                return self.checkedResolverNode(info, &.{ candidate, continuation });
            },
            .if_stmt, .if_let_stmt => return self.resolverConditional(statement_source, next, depth + 1),
            .let_stmt => {
                const binding = self.tree.binding(statement_source);
                if (binding.fallback != 0) return self.resolverGuard(statement_source, binding.pattern, binding.value, binding.fallback, next, depth + 1);
            },
            .for_stmt, .range_stmt, .forever_stmt => return self.resolverLoop(statement_source, next, depth + 1),
            else => {},
        }
        return error.CoreLimit;
    }
    fn resolverJoin(self: *Builder, source: ast.Id, body: Id) Error!Id {
        const index = self.checked.resolver_join_ids[source];
        if (index == 0) return error.CoreLimit;
        const info = self.checked.resolver_joins[index - 1];
        const ty = try self.projectType(info.ty, 0);
        var prefix: std.ArrayList(Id) = .empty;
        defer prefix.deinit(self.allocator);
        var merge = if (self.merge_heads.len == 0) std.math.maxInt(u32) else self.merge_heads[source];
        var field: u32 = 0;
        while (merge != std.math.maxInt(u32)) : (merge = self.merge_next[merge]) {
            const result = self.checked.merges[merge].result;
            const result_type = self.bindings.items[result].ty;
            const parameter = try self.referenceNode(source, info.parameter, ty);
            const projection = try self.directProjection(ty, result_type, field);
            const value = try self.make(source, .{ .tag = .project, .ty = result_type, .a = parameter, .b = projection });
            try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = result, .b = value }));
            field += 1;
        }
        const fn_type = try self.addType(.{ .tag = .function, .a = ty, .b = try self.projectType(info.result, 0) });
        return self.closureNode(source, try self.sequenceValue(source, prefix.items, body), .{ .binding = info.parameter, .ty = ty, .span = self.tree.span(source) }, fn_type);
    }
    fn resolverBranchTail(self: *Builder, source: ast.Id, join: Id, selected: bool) Error!Id {
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        var merge = if (self.merge_heads.len == 0) std.math.maxInt(u32) else self.merge_heads[source];
        while (merge != std.math.maxInt(u32)) : (merge = self.merge_next[merge]) {
            const info = self.checked.merges[merge];
            const binding = if (selected) info.then_binding else info.else_binding;
            try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
        }
        const fn_type = self.type_nodes.items[self.nodes.items[join].ty];
        const argument = if (values.items.len == 0 and fn_type.a == T.unit)
            try self.make(source, .{ .tag = .constant, .ty = T.unit })
        else blk: {
            const range = try self.save(values.items);
            break :blk try self.make(source, .{ .tag = .product, .ty = fn_type.a, .a = range.start, .b = range.len });
        };
        return self.make(source, .{ .tag = .apply, .ty = fn_type.b, .a = join, .b = argument });
    }
    fn resolverConditional(self: *Builder, source: ast.Id, next: Id, depth: usize) Error!Id {
        const syntax = self.tree.node(source);
        const join = try self.resolverJoin(source, next);
        const yes_tail = try self.resolverBranchTail(source, join, true);
        const no_tail = try self.resolverBranchTail(source, join, false);
        if (syntax.tag == .if_stmt) {
            const yes = try self.resolverStatements(syntax.b, self.tree.children(syntax.b), yes_tail, depth + 1);
            const no = if (syntax.c == 0) no_tail else try self.resolverStatements(syntax.c, self.tree.children(syntax.c), no_tail, depth + 1);
            const ty = if (self.nodes.items[yes].ty == T.never) self.nodes.items[no].ty else self.nodes.items[yes].ty;
            return self.make(source, .{ .tag = .if_value, .ty = ty, .a = try self.expression(syntax.a, depth + 1), .b = yes, .c = no });
        }
        const suites = self.tree.extra.items[syntax.c..][0..2];
        const yes = try self.resolverStatements(suites[0], self.tree.children(suites[0]), yes_tail, depth + 1);
        const no = if (suites[1] == 0) no_tail else try self.resolverStatements(suites[1], self.tree.children(suites[1]), no_tail, depth + 1);
        return self.resolverMatch(source, syntax.a, try self.expression(syntax.b, depth + 1), yes, no, depth + 1);
    }
    fn resolverGuard(self: *Builder, source: ast.Id, pattern: ast.Id, candidate: ast.Id, fallback: ast.Id, next: Id, depth: usize) Error!Id {
        const alternative = try self.resolverStatements(fallback, self.tree.children(fallback), next, depth + 1);
        return self.resolverMatch(source, pattern, try self.expression(candidate, depth + 1), next, alternative, depth + 1);
    }
    fn resolverMatch(self: *Builder, source: ast.Id, pattern_source: ast.Id, candidate: Id, yes: Id, no: Id, depth: usize) Error!Id {
        const inputs = try self.save(&.{candidate});
        const pattern = try self.patternNode(pattern_source, depth + 1);
        const yes_row = try self.addPatternRow(&.{pattern});
        const wildcard = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.nodes.items[candidate].ty });
        const no_row = try self.addPatternRow(&.{wildcard});
        const start: u32 = @intCast(self.match_arms.items.len);
        try self.match_arms.appendSlice(self.allocator, &.{
            .{ .rows = .{ .start = yes_row, .len = 1 }, .body = yes, .span = self.tree.span(source) },
            .{ .rows = .{ .start = no_row, .len = 1 }, .body = no, .span = self.tree.span(source) },
        });
        const index: u32 = @intCast(self.matches.items.len);
        try self.matches.append(self.allocator, .{ .inputs = inputs, .arms = .{ .start = start, .len = 2 } });
        const ty = if (self.nodes.items[yes].ty == T.never) self.nodes.items[no].ty else self.nodes.items[yes].ty;
        return self.make(source, .{ .tag = .match, .ty = ty, .a = index });
    }
    fn completedValue(self: *Builder, source: ast.Id, original: Id, types: T.List, constructor: u32) Error!Id {
        var value = original;
        for (self.checked.types.list(types)) |ty| {
            if (constructor == 0) return error.CoreLimit;
            value = try self.make(source, .{ .tag = .construct, .ty = try self.projectType(ty, 0), .a = constructor, .b = value });
        }
        return value;
    }
    fn resolverComplete(self: *Builder, index: u32, candidate: Id) Error!Id {
        const info = self.checked.resolver_completions[index - 1];
        const bind = self.checked.resolver_ops[info.bind - 1];
        const pure = self.checked.resolver_ops[info.pure - 1];
        const method = self.type_nodes.items[try self.projectType(bind.method_type, 0)];
        if (method.tag != .function) return error.CoreLimit;
        const after_candidate = self.type_nodes.items[method.b];
        if (after_candidate.tag != .function) return error.CoreLimit;
        const fn_type = after_candidate.a;
        const signature = self.type_nodes.items[fn_type];
        if (signature.tag != .function) return error.CoreLimit;
        const payload = try self.referenceNode(info.node, bind.continuation_parameter, signature.a);
        const completed = try self.completedValue(info.node, payload, info.completed_types, info.done_constructor);
        const body = try self.checkedResolverNode(pure, &.{completed});
        const continuation = try self.closureNode(info.node, body, .{ .binding = bind.continuation_parameter, .ty = signature.a, .span = self.tree.span(info.node) }, fn_type);
        return self.checkedResolverNode(bind, &.{ candidate, continuation });
    }
    fn productValue(self: *Builder, source: ast.Id, ty: T.Id, values: []const Id) Error!Id {
        if (ty == T.unit and values.len == 0) return self.make(source, .{ .tag = .constant, .ty = T.unit });
        const range = try self.save(values);
        return self.make(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
    }
    fn productField(self: *Builder, source: ast.Id, owner: Id, field: u32) Error!Id {
        const owner_type = self.nodes.items[owner].ty;
        const ty = self.type_nodes.items[owner_type];
        if (ty.tag != .product or field >= ty.b) return error.CoreLimit;
        const result_type = self.type_extra.items[ty.a + field];
        const projection = try self.directProjection(owner_type, result_type, field);
        return self.make(source, .{ .tag = .project, .ty = result_type, .a = owner, .b = projection });
    }
    fn cursorValue(self: *Builder, source: ast.Id, ty: T.Id, index: Id, bindings: []const BindingId) Error!Id {
        const cursor = self.type_nodes.items[ty];
        if (cursor.tag != .product or cursor.b != 2) return error.CoreLimit;
        const state_type = self.type_extra.items[cursor.a + 1];
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
        const state = try self.productValue(source, state_type, values.items);
        return self.productValue(source, ty, &.{ index, state });
    }
    fn resolverBreak(self: *Builder, source: ast.Id) Error!Id {
        const exit_index = if (self.loop_exit_indices.len == 0) 0 else self.loop_exit_indices[source];
        if (exit_index == 0) return error.CoreLimit;
        const exit = self.checked.loop_exits[exit_index - 1];
        // A resolver opened inside another loop returns its current carried
        // state from that resolver. The surrounding loop continues after the
        // nested do's value has been consumed or ignored.
        const operation = self.checked.resolver_op_ids[source];
        if (operation != 0) {
            const info = self.checked.resolver_ops[operation - 1];
            if (info.kind != .pure) return error.CoreLimit;
            var values: std.ArrayList(Id) = .empty;
            defer values.deinit(self.allocator);
            for (self.checked.types.list(exit.bindings)) |binding| {
                try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
            }
            const value = try self.productValue(source, try self.projectType(info.payload, 0), values.items);
            return self.checkedResolverNode(info, &.{value});
        }
        var index = self.resolver_loop_frames.items.len;
        while (index != 0) {
            index -= 1;
            const frame = self.resolver_loop_frames.items[index];
            if (frame.source != exit.loop) continue;
            const current = try self.referenceNode(source, frame.parameter, frame.cursor);
            const cursor = try self.cursorValue(source, frame.cursor, try self.productField(source, current, 0), self.checked.types.list(exit.bindings));
            const signature = self.type_nodes.items[self.nodes.items[frame.finalizer].ty];
            return self.make(source, .{ .tag = .apply, .ty = signature.b, .a = frame.finalizer, .b = cursor });
        }
        return error.CoreLimit;
    }
    fn resolverLoop(self: *Builder, source: ast.Id, next: Id, depth: usize) Error!Id {
        const index = self.checked.resolver_loop_ids[source];
        if (index == 0) return error.CoreLimit;
        const info = self.checked.resolver_loops[index - 1];
        const syntax = self.tree.node(source);
        const range = self.checked.loop_ranges[source];
        const carries = self.checked.loop_carries[range.start..][0..range.len];
        const cursor_type = try self.projectType(info.cursor, 0);
        const step_result = try self.projectType(info.step_result, 0);
        var first_source: ast.Id = 0;
        var end_source: ast.Id = 0;
        var pattern_source: ast.Id = 0;
        var body_source: ast.Id = syntax.a;
        var array = false;
        if (syntax.tag == .range_stmt) {
            first_source = syntax.a;
            end_source = syntax.b;
            body_source = syntax.c;
        } else if (syntax.tag == .for_stmt) {
            const parts = self.tree.extra.items[syntax.c..][0..3];
            first_source = syntax.b;
            end_source = parts[0];
            body_source = parts[1];
            pattern_source = syntax.a;
            array = end_source == 0;
        }
        var prefix: std.ArrayList(Id) = .empty;
        defer prefix.deinit(self.allocator);
        const first = if (first_source == 0) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else try self.expression(first_source, depth + 1);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.first_binding, .b = first }));
        const first_ref = try self.referenceNode(source, info.first_binding, self.bindings.items[info.first_binding].ty);
        const end = if (array) blk: {
            const values = try self.save(&.{first_ref});
            break :blk try self.make(source, .{ .tag = .array_op, .ty = T.u32_type, .a = values.start, .b = values.len, .c = @backingInt(ArrayOp.length) });
        } else if (end_source == 0) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else try self.expression(end_source, depth + 1);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.end_binding, .b = end }));
        const cursor = try self.referenceNode(source, info.cursor_parameter, cursor_type);
        const counter = try self.productField(source, cursor, 0);
        const state = try self.productField(source, cursor, 1);
        var incoming: std.ArrayList(BindingId) = .empty;
        defer incoming.deinit(self.allocator);
        var backedge: std.ArrayList(BindingId) = .empty;
        defer backedge.deinit(self.allocator);
        var finalize_prefix: std.ArrayList(Id) = .empty;
        defer finalize_prefix.deinit(self.allocator);
        var step_prefix: std.ArrayList(Id) = .empty;
        defer step_prefix.deinit(self.allocator);
        for (carries, 0..) |carry, field| {
            try incoming.append(self.allocator, carry.incoming);
            try backedge.append(self.allocator, carry.backedge);
            const value = try self.productField(source, state, @intCast(field));
            try finalize_prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = carry.outgoing, .b = value }));
            try step_prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = carry.iteration, .b = value }));
        }
        const finalized = try self.resolverComplete(info.finish, next);
        const fn_type = try self.addType(.{ .tag = .function, .a = cursor_type, .b = step_result });
        const parameter: Parameter = .{ .binding = info.cursor_parameter, .ty = cursor_type, .span = self.tree.span(source) };
        const finalizer = try self.closureNode(source, try self.sequenceValue(source, finalize_prefix.items, finalized), parameter, fn_type);
        const exit = try self.make(source, .{ .tag = .apply, .ty = step_result, .a = finalizer, .b = cursor });
        const one = try self.make(source, .{ .tag = .constant, .ty = T.u32_type, .a = 1 });
        const successor = try self.make(source, .{ .tag = .scalar, .op = .add, .ty = T.u32_type, .a = counter, .b = one });
        const next_cursor = try self.cursorValue(source, cursor_type, successor, backedge.items);
        const continued = self.checked.resolver_ops[info.continued - 1];
        const progress = try self.make(source, .{ .tag = .construct, .ty = try self.projectType(continued.payload, 0), .a = info.continue_constructor, .b = next_cursor });
        const progress_tail = try self.checkedResolverNode(continued, &.{progress});
        if (pattern_source != 0) {
            const iterator = if (!array) counter else blk: {
                const values = try self.save(&.{ first_ref, counter });
                break :blk try self.make(source, .{ .tag = .array_op, .ty = try self.typeOf(pattern_source), .a = values.start, .b = values.len, .c = @backingInt(ArrayOp.get) });
            };
            try step_prefix.append(self.allocator, try self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(pattern_source, depth + 1), .b = iterator }));
        }
        const stack_mark = self.resolver_loop_frames.items.len;
        try self.resolver_loop_frames.append(self.allocator, .{ .source = source, .cursor = cursor_type, .parameter = info.cursor_parameter, .finalizer = finalizer });
        const iteration = self.resolverStatements(body_source, self.tree.children(body_source), progress_tail, depth + 1) catch |err| {
            self.resolver_loop_frames.shrinkRetainingCapacity(stack_mark);
            return err;
        };
        self.resolver_loop_frames.shrinkRetainingCapacity(stack_mark);
        // Iterator binding and array access happen only for an actual body
        // invocation, after the one-time bound check has selected this arm.
        const iteration_body = try self.sequenceValue(source, step_prefix.items, iteration);
        const step_body = if (syntax.tag == .forever_stmt) iteration_body else blk: {
            const end_ref = try self.referenceNode(source, info.end_binding, T.u32_type);
            const condition = try self.make(source, .{ .tag = .scalar, .op = .less, .ty = T.boolean, .a = counter, .b = end_ref });
            break :blk try self.make(source, .{ .tag = .if_value, .ty = step_result, .a = condition, .b = iteration_body, .c = exit });
        };
        const step = try self.closureNode(source, step_body, parameter, fn_type);
        const first_index = if (array) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else first_ref;
        const initial = try self.cursorValue(source, cursor_type, first_index, incoming.items);
        const iterate = try self.checkedResolverNode(self.checked.resolver_ops[info.iterate - 1], &.{ initial, step });
        return self.sequenceValue(source, prefix.items, iterate);
    }
    fn statements(self: *Builder, source: ast.Id, depth: usize) Error!List {
        var children: std.ArrayList(Id) = .empty;
        defer children.deinit(self.allocator);
        for (self.tree.children(source)) |child| try children.append(self.allocator, try self.statement(child, depth + 1));
        return self.save(children.items);
    }
    fn suite(self: *Builder, source: ast.Id, depth: usize) Error!Id {
        if (source == 0) return 0;
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const children = try self.statements(source, depth + 1);
        const id = try self.make(source, .{ .tag = .suite, .ty = T.unit, .a = children.start, .b = children.len });
        self.ast_map[source] = id;
        return id;
    }
    fn requestState(self: *Builder, source: ast.Id, state_type: T.Id, bindings: []const BindingId) Error!Id {
        if (bindings.len == 0) return self.make(source, .{ .tag = .constant, .ty = T.unit });
        if (bindings.len == 1) return self.referenceNode(source, bindings[0], self.bindings.items[bindings[0]].ty);
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = .product, .ty = state_type, .a = range.start, .b = range.len });
    }
    fn requestControl(self: *Builder, source: ast.Id, info: checked_types.RequestControl, depth: usize) Error!Id {
        var frame_index = self.request_callbacks.items.len;
        while (frame_index != 0) {
            frame_index -= 1;
            const frame = self.request_callbacks.items[frame_index];
            if (frame.loop != info.loop) continue;
            const kind: RequestDecisionKind = switch (info.kind) {
                .reply => .reply,
                .cancel => .cancel,
                .break_ => .break_,
            };
            const value = if (kind == .break_) 0 else try self.expression(self.tree.node(source).a, depth + 1);
            const state = if (kind == .cancel) 0 else try self.requestState(source, frame.state_type, self.checked.types.list(info.bindings));
            const decision = try self.make(source, .{ .tag = .request_decision, .ty = frame.decision_type, .a = @backingInt(kind), .b = value, .c = state });
            return self.make(source, .{ .tag = .return_, .ty = T.never, .a = decision, .b = frame.return_target });
        }
        // Completion executes in the surrounding block, without an operation
        // callback frame. Its return/break targets retain their source owners.
        if (info.kind == .cancel) return self.make(source, .{ .tag = .return_, .ty = T.never, .a = try self.expression(self.tree.node(source).a, depth + 1), .b = if (self.ast_map[info.target_scope] != 0) self.ast_map[info.target_scope] else self.return_target });
        if (info.kind == .break_) {
            var values: std.ArrayList(Id) = .empty;
            defer values.deinit(self.allocator);
            for (self.checked.types.list(info.bindings)) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
            const range = try self.save(values.items);
            return self.make(source, .{ .tag = .break_, .ty = T.never, .a = self.ast_map[info.loop], .b = range.start, .c = range.len });
        }
        try self.diagnostic(.unresolved_binding, source);
        return 0;
    }
    fn requestCallback(self: *Builder, source: ast.Id, loop_source: ast.Id, info: checked_types.RequestArm, state_type: T.Id, depth: usize) Error!Id {
        const signature = try self.projectType(info.signature, 0);
        const arrow = self.type_nodes.items[signature];
        if (arrow.tag != .function) return error.CoreLimit;
        if (self.bindings.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const parameter_id: BindingId = @intCast(self.bindings.items.len);
        const parameter: Parameter = .{ .binding = parameter_id, .ty = arrow.a, .span = self.tree.span(source) };
        try self.bindings.append(self.allocator, .{ .kind = .parameter, .ty = arrow.a, .scheme = .{ .root = arrow.a }, .target = .{ .binding = parameter_id }, .span = parameter.span });
        const argument = try self.referenceNode(source, parameter_id, arrow.a);
        const operation_argument = try self.productField(source, argument, 0);
        const state = try self.productField(source, argument, 1);
        var prefix: std.ArrayList(Id) = .empty;
        defer prefix.deinit(self.allocator);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(info.pattern, depth + 1), .b = operation_argument }));
        const bindings = self.checked.types.list(info.state_bindings);
        for (bindings, 0..) |binding, index| {
            const value = if (bindings.len == 1) state else try self.productField(source, state, @intCast(index));
            try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value }));
        }
        const block = try self.reserve(source);
        const saved_return = self.return_target;
        self.return_target = block;
        defer self.return_target = saved_return;
        const stack_mark = self.request_callbacks.items.len;
        try self.request_callbacks.append(self.allocator, .{ .loop = loop_source, .return_target = block, .decision_type = arrow.b, .state_type = state_type });
        defer self.request_callbacks.shrinkRetainingCapacity(stack_mark);
        const callback_suite = try self.suite(info.suite, depth + 1);
        try prefix.append(self.allocator, callback_suite);
        const range = try self.save(prefix.items);
        self.nodes.items[block] = .{ .tag = .block, .ty = arrow.b, .a = range.start, .b = range.len };
        return self.closureNode(source, block, parameter, signature);
    }
    fn requestLoop(self: *Builder, source: ast.Id, checked: checked_types.RequestLoop, depth: usize) Error!Id {
        const id = try self.reserve(source);
        self.ast_map[source] = id;
        if (self.request_loops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const catalog: u32 = @intCast(self.request_loops.items.len);
        var info: RequestLoopInfo = .{
            .computation = 0,
            .action_type = try self.projectType(checked.action_type, 0),
            .value_type = try self.projectType(checked.value_type, 0),
            .result_type = try self.projectType(checked.result_type, 0),
            .state_type = try self.projectType(checked.state_type, 0),
            .return_target = if (self.ast_map[checked.return_scope] != 0) self.ast_map[checked.return_scope] else self.return_target,
        };
        try self.request_loops.append(self.allocator, info);
        self.nodes.items[id] = .{ .tag = .request_loop, .ty = T.unit, .a = catalog };
        const carries = self.checked.loop_carries[checked.carried.start..][0..checked.carried.len];
        if (carries.len > std.math.maxInt(u32) - self.loop_carries.items.len) return error.CoreLimit;
        info.carries = .{ .start = @intCast(self.loop_carries.items.len), .len = @intCast(carries.len) };
        for (carries) |carry| try self.loop_carries.append(self.allocator, .{ .incoming = carry.incoming, .iteration = carry.iteration, .backedge = carry.backedge, .outgoing = carry.outgoing });
        info.computation = try self.expression(checked.computation, depth + 1);
        var arms: std.ArrayList(RequestArm) = .empty;
        defer arms.deinit(self.allocator);
        for (self.checked.types.list(checked.arms)) |index| {
            const arm = self.checked.request_arms[index];
            try arms.append(self.allocator, .{ .operation = try self.projectOperation(arm.operation, 0), .callback = try self.requestCallback(arm.node, source, arm, info.state_type, depth + 1) });
        }
        if (arms.items.len > std.math.maxInt(u32) - self.request_arms.items.len) return error.CoreLimit;
        info.arms = .{ .start = @intCast(self.request_arms.items.len), .len = @intCast(arms.items.len) };
        try self.request_arms.appendSlice(self.allocator, arms.items);
        info.completion_pattern = try self.patternNode(checked.complete_pattern, depth + 1);
        info.completion_body = try self.suite(checked.complete_suite, depth + 1);
        info.completion_state_bindings = try self.save(self.checked.types.list(checked.complete_state_bindings));
        self.request_loops.items[catalog] = info;
        return id;
    }
    fn loopStatement(self: *Builder, source: ast.Id, checked_carries: anytype, depth: usize) Error!Id {
        const syntax = self.tree.node(source);
        var info: LoopInfo = .{ .kind = .forever, .body = 0 };
        var first_source: ast.Id = 0;
        var end_source: ast.Id = 0;
        var pattern_source: ast.Id = 0;
        const body_source: ast.Id = switch (syntax.tag) {
            .forever_stmt => syntax.a,
            .range_stmt => blk: {
                info.kind = .range;
                first_source = syntax.a;
                end_source = syntax.b;
                break :blk syntax.c;
            },
            .for_stmt => blk: {
                const details = self.tree.extra.items[syntax.c..][0..3];
                info.kind = if (details[0] == 0) .array else .range;
                first_source = syntax.b;
                end_source = details[0];
                pattern_source = syntax.a;
                break :blk details[1];
            },
            else => unreachable,
        };
        // Publish the numeric target before lowering its body, so a break
        // inside a nested do can reference the surrounding loop without a
        // backpointer into the source tree or a mutable lexical environment.
        const id = try self.reserve(source);
        if (self.loops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const catalog: u32 = @intCast(self.loops.items.len);
        try self.loops.append(self.allocator, info);
        self.nodes.items[id] = .{ .tag = .loop, .ty = T.unit, .a = catalog };
        self.ast_map[source] = id;
        if (checked_carries.len > std.math.maxInt(u32) - self.loop_carries.items.len) return error.CoreLimit;
        info.carries = .{ .start = @intCast(self.loop_carries.items.len), .len = @intCast(checked_carries.len) };
        for (checked_carries) |carry| try self.loop_carries.append(self.allocator, .{ .incoming = carry.incoming, .iteration = carry.iteration, .backedge = carry.backedge, .outgoing = carry.outgoing });
        info.first = try self.expression(first_source, depth + 1);
        info.end = try self.expression(end_source, depth + 1);
        info.pattern = if (pattern_source == 0) 0 else try self.patternNode(pattern_source, depth + 1);
        info.body = try self.suite(body_source, depth + 1);
        info.can_exit = self.loops.items[catalog].can_exit;
        self.loops.items[catalog] = info;
        return id;
    }
    fn breakStatement(self: *Builder, source: ast.Id, target_source: ast.Id, bindings: []const BindingId) Error!Id {
        const target_id = self.ast_map[target_source];
        if (target_id == 0 or self.nodes.items[target_id].tag != .loop) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        self.loops.items[self.nodes.items[target_id].a].can_exit = true;
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| {
            if (binding == 0 or binding >= self.bindings.items.len) {
                try self.diagnostic(.unresolved_binding, source);
                return 0;
            }
            try values.append(self.allocator, try self.referenceNode(source, binding, self.bindings.items[binding].ty));
        }
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = .break_, .ty = T.never, .a = target_id, .b = range.start, .c = range.len });
    }
    fn statement(self: *Builder, source: ast.Id, depth: usize) Error!Id {
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const syntax = self.tree.node(source);
        for (self.checked.request_controls) |control| if (control.node == source) return self.requestControl(source, control, depth + 1);
        for (self.checked.request_loops) |info| if (info.node == source) return self.requestLoop(source, info, depth + 1);
        switch (syntax.tag) {
            .for_stmt, .range_stmt, .forever_stmt => {
                const range = self.checked.loop_ranges[source];
                return self.loopStatement(source, self.checked.loop_carries[range.start..][0..range.len], depth + 1);
            },
            .break_stmt => {
                const index = if (self.loop_exit_indices.len == 0) 0 else self.loop_exit_indices[source];
                if (index == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                const exit = self.checked.loop_exits[index - 1];
                return self.breakStatement(source, exit.loop, self.checked.types.list(exit.bindings));
            },
            .let_stmt => {
                const value = self.tree.binding(source);
                const binding = self.checked.resolved[source];
                if (self.tree.node(value.pattern).tag != .pattern_name or value.fallback != 0 or binding == 0) {
                    return self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(value.pattern, depth + 1), .b = try self.expression(value.value, depth + 1), .c = try self.suite(value.fallback, depth + 1) });
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = try self.expression(value.value, depth + 1) });
            },
            .use_stmt => {
                const value = try self.expression(syntax.b, depth + 1);
                if (syntax.a == 0 or std.mem.eql(u8, self.names.get(syntax.a), "_")) return value;
                const binding = self.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value });
            },
            .rebind_stmt => {
                const binding = self.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                if (source < self.checked.rebindings.len and self.checked.rebindings[source].path.len != 0) {
                    const metadata = self.checked.rebindings[source];
                    const type_path = self.checked.types.list(self.checked.access_types[source]);
                    const source_path = self.checked.types.list(metadata.path);
                    if (type_path.len != source_path.len + 1) {
                        try self.diagnostic(.unresolved_binding, source);
                        return 0;
                    }
                    const root = try self.referenceNode(source, metadata.root, try self.projectType(type_path[0], 0));
                    var path: std.ArrayList(Id) = .empty;
                    defer path.deinit(self.allocator);
                    var selectors: std.ArrayList(UpdateStep) = .empty;
                    defer selectors.deinit(self.allocator);
                    var mixed = false;
                    for (source_path) |catalog| if (catalog == 0) {
                        mixed = true;
                        break;
                    };
                    if (mixed) {
                        const access_nodes = self.checked.types.list(self.checked.access_nodes[source]);
                        if (access_nodes.len != source_path.len) {
                            try self.diagnostic(.unresolved_binding, source);
                            return 0;
                        }
                        for (source_path, access_nodes, 0..) |catalog, access_id, index| {
                            const access = self.tree.node(access_id);
                            const owner_type = try self.projectType(type_path[index], 0);
                            const result_type = try self.projectType(type_path[index + 1], 0);
                            if (access.tag == .index_access and catalog == 0) {
                                try selectors.append(self.allocator, .{ .kind = .index, .index = try self.expression(access.b, depth + 1), .source_type = owner_type, .result_type = result_type });
                            } else if (access.tag == .field_access and catalog != 0) {
                                try selectors.append(self.allocator, .{ .kind = .field, .projection = try self.projectionIndex(catalog, owner_type, result_type), .source_type = owner_type, .result_type = result_type });
                            } else {
                                try self.diagnostic(.unresolved_binding, access_id);
                                return 0;
                            }
                        }
                    } else for (source_path, 0..) |catalog, index| try path.append(self.allocator, try self.projectionIndex(catalog, try self.projectType(type_path[index], 0), try self.projectType(type_path[index + 1], 0)));
                    const range = try self.save(path.items);
                    if (selectors.items.len > std.math.maxInt(u32) - self.update_steps.items.len) return error.CoreLimit;
                    const selector_range: List = .{ .start = @intCast(self.update_steps.items.len), .len = @intCast(selectors.items.len) };
                    try self.update_steps.appendSlice(self.allocator, selectors.items);
                    const value = try self.expression(syntax.b, depth + 1);
                    const index: u32 = @intCast(self.updates.items.len);
                    try self.updates.append(self.allocator, .{ .root = root, .path = range, .value = value, .self_binding = metadata.self_binding, .selectors = selector_range });
                    const updated = try self.make(source, .{ .tag = .update, .ty = try self.projectType(self.checked.bindings[binding].ty, 0), .a = index });
                    return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = updated });
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = try self.expression(syntax.b, depth + 1) });
            },
            .return_stmt => {
                if (syntax.b != 0 or self.return_target == 0) {
                    try self.diagnostic(.unsupported, source);
                    return 0;
                }
                return self.make(source, .{ .tag = .return_, .ty = T.never, .a = try self.expression(syntax.a, depth + 1), .b = self.return_target });
            },
            .if_stmt => {
                const id = try self.make(source, .{ .tag = .if_stmt, .ty = T.unit, .a = try self.expression(syntax.a, depth + 1), .b = try self.suite(syntax.b, depth + 1), .c = try self.suite(syntax.c, depth + 1) });
                try self.copyMerges(source, id);
                return id;
            },
            .if_let_stmt => {
                const input = try self.expression(syntax.b, depth + 1);
                const input_range = try self.save(&.{input});
                const pattern = try self.patternNode(syntax.a, depth + 1);
                const success_row = try self.addPatternRow(&.{pattern});
                const wildcard = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.nodes.items[input].ty });
                const fallback_row = try self.addPatternRow(&.{wildcard});
                const suites = self.tree.extra.items[syntax.c..][0..2];
                const then_body = try self.suite(suites[0], depth + 1);
                const else_body = try self.suite(suites[1], depth + 1);
                const arm_start: u32 = @intCast(self.match_arms.items.len);
                try self.match_arms.appendSlice(self.allocator, &.{
                    .{ .rows = .{ .start = success_row, .len = 1 }, .body = then_body, .span = self.tree.span(source) },
                    .{ .rows = .{ .start = fallback_row, .len = 1 }, .body = else_body, .span = self.tree.span(source) },
                });
                const index: u32 = @intCast(self.matches.items.len);
                try self.matches.append(self.allocator, .{ .inputs = input_range, .arms = .{ .start = arm_start, .len = 2 }, .statement = true });
                const id = try self.make(source, .{ .tag = .match, .ty = T.unit, .a = index });
                try self.copyMerges(source, id);
                return id;
            },
            else => return self.expression(source, depth + 1),
        }
    }
    fn copyMerges(self: *Builder, source: ast.Id, id: Id) Error!void {
        const start: u32 = @intCast(self.merges.items.len);
        var index = if (self.merge_heads.len == 0) std.math.maxInt(u32) else self.merge_heads[source];
        while (index != std.math.maxInt(u32)) : (index = self.merge_next[index]) {
            const merge = self.checked.merges[index];
            try self.merges.append(self.allocator, .{ .node = id, .result = merge.result, .then_binding = merge.then_binding, .else_binding = merge.else_binding });
        }
        self.merge_ranges.items[id] = .{ .start = start, .len = @intCast(self.merges.items.len - start) };
    }
    fn allBindings(self: *Builder) Error!void {
        for (self.checked.bindings, 0..) |value, i| try self.bindings.append(self.allocator, .{ .kind = value.kind, .ty = try self.projectType(value.ty, 0), .scheme = try self.projectScheme(value.scheme), .target = if (i == 0) .{ .binding = 0 } else self.target(@intCast(i)), .span = self.tree.span(value.declaration) });
    }
    fn projectedTypeList(self: *Builder, source: T.List) Error!T.List {
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(self.allocator);
        for (self.checked.types.list(source)) |id| try values.append(self.allocator, try self.projectType(id, 0));
        return self.saveTypes(values.items);
    }
    fn projectedRowVariables(self: *Builder, source: T.List) Error!T.List {
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        for (self.checked.types.list(source)) |variable| try values.append(self.allocator, try self.projectRowVariable(variable));
        return self.saveTypes(values.items);
    }
    fn allCatalogs(self: *Builder) Error!void {
        for (self.checked.nominals) |metadata| {
            const constructors = try self.save(self.checked.types.list(metadata.constructors));
            const display = try self.nominalDiagnosticNames(metadata);
            try self.nominals.append(self.allocator, .{ .diagnostic_name = display.name, .diagnostic_origin = display.origin, .identity = metadata.identity, .parameters = try self.projectedTypeList(metadata.parameters), .variables = try self.projectedTypeList(metadata.variables), .constructors = constructors });
        }
        for (self.checked.effect_templates) |metadata| {
            if (metadata.identity.decl == 0 or metadata.family == 0) continue;
            const family = self.checked.effect_families[metadata.family];
            if (family.name == 0 or (!family.callable and metadata.name == 0)) continue;
            const origin = self.diagnostic_origins.name(self.allocator, metadata.identity.unit, self.checked.unit) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            defer self.allocator.free(origin);
            const name = if (family.callable) try self.allocator.dupe(u8, self.names.get(family.name)) else try self.allocator.print("{s}.{s}", .{ self.names.get(family.name), self.names.get(metadata.name) });
            defer self.allocator.free(name);
            try self.operation_names.append(self.allocator, .{ .identity = metadata.identity, .diagnostic_name = try self.saveName(name), .diagnostic_origin = try self.saveName(origin) });
        }
        for (self.checked.constructors) |metadata| try self.constructors.append(self.allocator, .{ .identity = metadata.identity, .nominal = metadata.nominal, .tag = metadata.tag, .scheme = try self.projectScheme(metadata.scheme), .payload = try self.projectType(metadata.payload, 0) });
        for (self.checked.associated) |metadata| try self.associated.append(self.allocator, .{ .identity = metadata.identity, .member = metadata.member, .operator = metadata.operator, .target = self.target(metadata.binding) });
    }
    fn saveName(self: *Builder, text: []const u8) Error!Name {
        if (text.len > std.math.maxInt(u32) -| self.name_bytes.items.len) return error.CoreLimit;
        const result: Name = .{ .start = @intCast(self.name_bytes.items.len), .len = @intCast(text.len) };
        try self.name_bytes.appendSlice(self.allocator, text);
        return result;
    }
    fn nominalDiagnosticNames(self: *Builder, nominal: checked_types.Nominal) Error!struct { name: Name = .{}, origin: Name = .{} } {
        if (nominal.name == 0 or nominal.identity.decl == 0) return .{};
        const owner = self.diagnostic_origins.name(self.allocator, nominal.identity.unit, self.checked.unit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{},
        };
        defer self.allocator.free(owner);
        return .{ .name = try self.saveName(self.names.get(nominal.name)), .origin = try self.saveName(owner) };
    }
    fn allBodies(self: *Builder) Error!void {
        // Group certificates once by owning body. Recursive inference may append
        // decisions out of declaration order, so a per-body full scan would
        // make publication quadratic in the number of bodies and row tails.
        const certificates = try self.allocator.alloc(T.List, self.checked.bindings.len);
        defer self.allocator.free(certificates);
        @memset(certificates, .{});
        if (self.checked.body_closed_rows.len > std.math.maxInt(u32) - self.type_extra.items.len) return error.CoreLimit;
        for (self.checked.body_closed_rows) |decision| {
            if (decision.owner >= certificates.len) return error.CoreLimit;
            certificates[decision.owner].len += 1;
        }
        var certificate_start: u32 = @intCast(self.type_extra.items.len);
        for (certificates) |*range| {
            range.start = certificate_start;
            certificate_start += range.len;
        }
        try self.type_extra.appendNTimes(self.allocator, 0, self.checked.body_closed_rows.len);
        for (self.checked.body_closed_rows) |decision| {
            const range = &certificates[decision.owner];
            self.type_extra.items[range.start] = try self.projectRowVariable(decision.variable);
            range.start += 1;
        }
        for (certificates) |*range| range.start -= range.len;
        for (self.checked.bindings, 0..) |value, index| {
            if (index == 0 or value.kind != .global) continue;
            const declaration = self.tree.valueDecl(value.declaration);
            self.body_lowerings += 1;
            const body_id: BodyId = @intCast(self.bodies.items.len);
            const start: u32 = @intCast(self.parameters.items.len);
            var source = self.unwrap(declaration.body);
            const function = declaration.attributes.len == 0 and self.tree.node(source).tag == .lambda;
            while (declaration.attributes.len == 0 and self.tree.node(source).tag == .lambda) {
                const lambda = self.tree.node(source);
                try self.parameters.append(self.allocator, .{ .binding = self.checked.resolved[lambda.a], .ty = try self.typeOf(lambda.a), .span = self.tree.span(lambda.a) });
                source = self.unwrap(lambda.b);
            }
            const root = try self.taggedExpression(self.tree.list(declaration.attributes), source, 0);
            var export_name: Name = .{};
            if (declaration.exported) {
                const bytes = self.names.get(value.name);
                export_name = .{ .start = @intCast(self.name_bytes.items.len), .len = @intCast(bytes.len) };
                try self.name_bytes.appendSlice(self.allocator, bytes);
            }
            try self.bodies.append(self.allocator, .{ .binding = @intCast(index), .root = root, .parameters = .{ .start = start, .len = @intCast(self.parameters.items.len - start) }, .scheme = self.bindings.items[index].scheme, .closed_rows = certificates[index], .span = self.tree.span(value.declaration), .export_name = export_name, .exported = declaration.exported, .runtime = declaration.runtime, .is_function = function });
            self.bindings.items[index].body_id = body_id;
            try self.source_names.append(self.allocator, .{ .binding = @intCast(index), .point = self.tree.valueNamePoint(value.declaration) orelse self.tree.span(value.declaration).start });
            if (declaration.runtime) try self.runtime_names.append(self.allocator, .{ .binding = @intCast(index), .point = self.tree.runtimeNamePoint(value.declaration) orelse self.tree.span(value.declaration).start });
        }
    }
    fn finish(self: *Builder) Allocator.Error!Module {
        var result: Module = .{ .types = .{ .nodes = &.{}, .extra = &.{} }, .nodes = &.{}, .spans = &.{}, .extra = &.{}, .bindings = &.{}, .bodies = &.{}, .parameters = &.{}, .references = &.{}, .calls = &.{}, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = self.body_lowerings };
        errdefer result.deinit(self.allocator);
        result.types.nodes = try self.type_nodes.toOwnedSlice(self.allocator);
        result.types.extra = try self.type_extra.toOwnedSlice(self.allocator);
        result.types.effects.rows = try self.effect_rows.toOwnedSlice(self.allocator);
        result.types.effects.labels = try self.effect_labels.toOwnedSlice(self.allocator);
        result.types.effects.variable_count = self.effect_variable_count;
        result.types.operations = try self.effect_operations.toOwnedSlice(self.allocator);
        inline for (.{ "request_loops", "request_arms", "runtime_names", "source_names", "erased_declaration_references", "tag_calls", "nodes", "spans", "extra", "bindings", "bodies", "parameters", "references", "calls", "merges", "merge_ranges", "obligations", "diagnostics", "nominals", "operation_names", "constructors", "projections", "projection_variants", "patterns", "pattern_rows", "match_arms", "matches", "updates", "update_steps", "closures", "associated", "primitives", "loops", "loop_carries", "resolver_ops", "operation_values", "handle_effects", "dispatch_signatures" }) |field| @field(result, field) = try @field(self, field).toOwnedSlice(self.allocator);
        result.names = try self.name_bytes.toOwnedSlice(self.allocator);
        return result;
    }
};

/// Produce immutable typed bodies without evaluating, specializing or emitting
/// any source constant. Dead constants and dead branches remain ordinary IR.
pub fn lower(allocator: Allocator, tree: *const ast.Tree, names: *const symbols.Pool, checked: *const checked_types.Checked) !Module {
    return lowerWithOrigins(allocator, tree, names, checked, .{});
}

/// Capture diagnostic spellings alongside immutable Core before source owners end.
pub fn lowerWithOrigins(allocator: Allocator, tree: *const ast.Tree, names: *const symbols.Pool, checked: *const checked_types.Checked, diagnostic_origins: checked_types.ModuleOrigins) !Module {
    var builder: Builder = .{ .allocator = allocator, .tree = tree, .names = names, .checked = checked, .diagnostic_origins = diagnostic_origins };
    defer builder.deinit();
    try builder.initialize();
    if (checked.diagnostics.len != 0) {
        try builder.diagnostic(.unchecked, 0);
    } else {
        try builder.allBindings();
        try builder.allCatalogs();
        try builder.allBodies();
    }
    var result = try builder.finish();
    errdefer result.deinit(allocator);
    result.unit = checked.unit;
    // Capture before source/checker teardown. All arrays publish together.
    try @import("declaration_dependencies.zig").capture(allocator, &result);
    return result;
}

fn binaryOp(text: []const u8) ?Op {
    const names = [_][]const u8{ "+", "-", "*", "/", "%", "==", "!=", "<", "<=", ">", ">=", "&", "|", "^", "<<", ">>", "&&", "||" };
    const ops = [_]Op{ .add, .sub, .mul, .div, .rem, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .and_, .or_ };
    for (names, ops) |name, op| if (std.mem.eql(u8, text, name)) return op;
    return null;
}
fn memberOp(text: []const u8) Op {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem", "eq", "ne", "lt", "le", "gt", "ge", "bit_and", "bit_or", "bit_xor", "shl", "shr" };
    const ops = [_]Op{ .add, .sub, .mul, .div, .rem, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right };
    for (names, ops) |name, op| if (std.mem.eql(u8, text, name)) return op;
    return .none;
}
const Intrinsic = struct { op: Op, arity: u8 };
const ArrayIntrinsic = struct { op: ArrayOp, arity: u8 };
fn arrayIntrinsic(text: []const u8) ?ArrayIntrinsic {
    const value = @import("collection_ops.zig").lookup(text) orelse return null;
    return .{ .op = value.op, .arity = value.arity };
}
fn intrinsic(text: []const u8) ?Intrinsic {
    const entries = .{
        .{ "@u32.add", Op.add, 2 },        .{ "@u32.sub", Op.sub, 2 },         .{ "@u32.mul", Op.mul, 2 },                .{ "@u32.div", Op.div, 2 },       .{ "@u32.rem", Op.rem, 2 },
        .{ "@u32.eq", Op.equal, 2 },       .{ "@u32.lt", Op.less, 2 },         .{ "@u32.bit_and", Op.bit_and, 2 },        .{ "@u32.bit_or", Op.bit_or, 2 }, .{ "@u32.bit_xor", Op.bit_xor, 2 },
        .{ "@u32.shl", Op.shift_left, 2 }, .{ "@u32.shr", Op.shift_right, 2 }, .{ "@u32.to_f32", Op.convert_u32_f32, 1 }, .{ "@f32.add", Op.add, 2 },       .{ "@f32.sub", Op.sub, 2 },
        .{ "@f32.mul", Op.mul, 2 },        .{ "@f32.div", Op.div, 2 },         .{ "@f32.eq", Op.equal, 2 },               .{ "@f32.ne", Op.not_equal, 2 },  .{ "@f32.lt", Op.less, 2 },
        .{ "@f32.le", Op.less_equal, 2 },  .{ "@f32.gt", Op.greater, 2 },      .{ "@f32.ge", Op.greater_equal, 2 },       .{ "@f32.abs", Op.abs, 1 },       .{ "@f32.neg", Op.neg, 1 },
        .{ "@f32.ceil", Op.ceil, 1 },      .{ "@f32.floor", Op.floor, 1 },     .{ "@f32.trunc", Op.trunc, 1 },            .{ "@f32.sqrt", Op.sqrt, 1 },     .{ "@f32.to_u32", Op.convert_f32_u32, 1 },
    };
    inline for (entries) |entry| if (std.mem.eql(u8, text, entry[0])) return .{ .op = entry[1], .arity = entry[2] };
    return null;
}
