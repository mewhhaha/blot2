//! Owned syntax tables. All edges are numeric IDs; every list is a side-array span.
//! Id 0 is absent. Source bytes and the symbol pool are owned by the caller.
const std = @import("std");
const symbols = @import("symbols.zig");
const token = @import("token.zig");
pub const Id = u32;
pub const Span = struct { start: u32, end: u32 };
pub const List = struct { start: u32 = 0, len: u32 = 0 };
pub const Tag = enum(u32) {
    invalid,
    // Declaration metadata schemas are exposed by the helpers below.
    value_decl,
    import_decl,
    export_decl,
    import_binding,
    data_decl,
    // type_alias_decl(a=name,b=type body,c=[params start,len,attrs start,len]).
    type_alias_decl,
    // contract_decl(a=name,b=where_clause body,c=[params start,len,attrs start,len]).
    contract_decl,
    // Contract members: a=name,b=type equation or value signature (0 abstract).
    contract_type_member,
    contract_value_member,
    // implementation_decl(a=name,b=members list,c=[params start,len,head,where start,len,where node]).
    implementation_decl,
    effect_decl,
    effect_type_decl,
    fixity_decl,
    attribute,
    constraint,
    where_clause,
    constructors,
    effect_operations,
    effect_operation,
    // Names/literals: a = symbol or exact U32/F32 bits (boolean 0/1).
    name,
    intrinsic,
    integer,
    float,
    string,
    boolean,
    unit,
    // lambda(a=parameter,b=body,c=result annotation); apply(a=callee,b=argument).
    lambda,
    parameter,
    apply,
    group,
    // unary(a=operator,b=operand); binary(a=operator,b=left,c=right).
    unary,
    binary,
    // Unresolved operators retain a head and a list of operator_tail nodes.
    infix_chain,
    operator_tail,
    // product/array/block: a=list start,b=list len; block c=resolver or0.
    product,
    array,
    block,
    // record(a=optional constructor symbol,b=list start,c=list len).
    record,
    field,
    selector,
    constructor_ref,
    type_witness,
    field_access,
    index_access,
    let_stmt,
    rebind_stmt,
    use_stmt,
    // Generated iteration setup/step: a=binder symbol,b=expression. Executes
    // normally even inside a monadic do; it is not that monad's bind.
    iterator_bind,
    function_return_stmt,
    return_stmt,
    yield_stmt,
    break_stmt,
    continue_stmt,
    if_expr,
    if_stmt,
    if_let_stmt,
    // a=pattern,b=source,c=[range end,body,explicit let,iterator expansion].
    // The expansion is a transparent suite, selected only for user iterators.
    for_stmt,
    range_stmt,
    forever_stmt,
    case_expr,
    case_arm,
    pattern_row,
    request_case,
    request_arm,
    // Pattern children are syntax nodes, not bindings resolved by the parser.
    pattern_name,
    pattern_integer,
    pattern_boolean,
    pattern_product,
    pattern_constructor,
    pattern_record,
    pattern_field,
    pattern_value,
    // Types: type_name(a=symbol), type_apply/function(a=left,b=right),
    // type_function c=effect row; type_effect a=base,b=row (no arrow).
    // Products/arrays/records use a/b list spans.
    type_name,
    type_apply,
    type_function,
    type_effect,
    type_product,
    type_array,
    type_record,
    type_field,
    type_demand,
    // effect_row a/b=label list,c=optional type_name source node for its tail.
    effect_row,
    // Grammar-valid numeric text that cannot be decoded. a=NumericCode,
    // b/c=raw token start/end. This is never an executable numeric payload.
    numeric_error,
    // A dependent arrow input: a=value binder name, b=family annotation.
    type_binder,
    // a=UsageKind, b=qualified type, c=borrow region symbol or0.
    type_usage,
    // a/b=quantified_binder list; c=[body type,where_clause or0].
    type_forall,
    type_exists,
    // a=name,b=BinderSort,c=0. Distinct from dependent-arrow type_binder.
    quantified_binder,
    // a/b=witness type list,c=[value,package annotation].
    package_pack,
    // a=package expression,b=binder list start,c=[list len,value name,body].
    package_unpack,
    // Compile-time code: a=result type,b=latent effect row,c=0.
    type_code,
    // Immutable descriptor: a=described type,b/c=0.
    type_descriptor,
};
pub const BinderSort = enum(u32) { type_, row, region };
pub const UsageKind = enum(u32) { unique, shared, borrow, borrow_mut, once, many, cleanup, concurrent };
pub const NumericCode = enum(u32) { integer_range, float_range, float_literal };
pub const NumericFault = struct { node: Id, code: NumericCode, span: Span, actual_token: token.Tag };
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
comptime {
    std.debug.assert(@sizeOf(Node) == 16);
}

pub const Code = enum {
    expected_token,
    expected_expression,
    expected_type,
    expected_pattern,
    unexpected_token,
    task_spark_scope,
    task_spark_call,
    task_receive_tuple,
    invalid_literal,
    operator_associativity,
    fixity_order,
    duplicate_fixity,
    invalid_precedence,
    nesting_limit,
    table_limit,
    private_marker,
    GPU_FRONTEND_SYNTAX_ERROR,
};
pub const Diagnostic = struct {
    code: Code,
    start: u32,
    end: u32,
    // Raw details and source handles remain byte offsets. The containing
    // top-level attempt is independent from the token where parsing stopped.
    declaration_origin: ?Span = null,
    detail_span: ?Span = null,
    actual_token: ?token.Tag = null,
    expected_token: ?token.Tag = null,
    pub fn message(self: Diagnostic) []const u8 {
        return switch (self.code) {
            .GPU_FRONTEND_SYNTAX_ERROR => "This syntax is not allowed in this position",
            .expected_token => "Expected a syntax token",
            .expected_expression => "Expected an expression",
            .expected_type => "Expected a type",
            .expected_pattern => "Expected a pattern",
            .unexpected_token => "Unexpected syntax token",
            .task_spark_scope => "A sparked call needs an enclosing task group",
            .task_spark_call => "Spark needs a parenthesized function call",
            .task_receive_tuple => "Tuple receive is not available yet; join each handle explicitly",
            .invalid_literal => "Invalid literal",
            .operator_associativity => "Equal-precedence operators need compatible associativity or parentheses",
            .fixity_order => "Fixity declarations must precede other declarations",
            .duplicate_fixity => "An operator fixity was declared more than once",
            .invalid_precedence => "Operator precedence must be between 0 and 255",
            .nesting_limit => "Syntax nesting exceeds the parser limit",
            .table_limit => "Syntax exceeds the 32-bit table limit",
            .private_marker => "Private frontend markers are not source syntax",
        };
    }
};
pub const ValueDecl = struct {
    name: symbols.Symbol,
    body: Id,
    annotation: Id,
    modifier: symbols.Symbol,
    runtime: bool,
    exported: bool,
    where: List,
    where_node: Id,
    attributes: List,
};
pub const ImplementationDecl = struct { name: symbols.Symbol, parameters: List, head: Id, members: List, where: List, where_node: Id };
pub const Parameter = struct {
    name: symbols.Symbol,
    annotation: Id,
    demanded: bool,
    demand: bool,
    is_unit: bool,
    where: List,
    where_node: Id,
};
pub const Binding = struct { pattern: Id, value: Id, annotation: Id, where: List, where_node: Id, fallback: Id };
pub const ImportDecl = struct { path: symbols.Symbol, namespace: symbols.Symbol, bindings: List, path_span: Span, namespace_span: Span };
pub const ImportBinding = struct { name: symbols.Symbol, alias: symbols.Symbol };
pub const Fixity = struct { operator: symbols.Symbol, target: symbols.Symbol, precedence: u32, association: u32, named: bool, attributes: List, literal_error: Id = 0 };

pub const DeclarationTraits = struct { declaration: Id, private: bool = false, is_opaque: bool = false };

pub const RuntimeName = struct { declaration: Id, point: u32 };
pub const Tree = struct {
    has_typed_staging: bool = false,
    has_numeric_proofs: bool = false,
    nodes: std.ArrayList(Node) = .empty,
    spans: std.ArrayList(Span) = .empty,
    extra: std.ArrayList(u32) = .empty,
    roots: std.ArrayList(Id) = .empty,
    runtime_names: std.ArrayList(RuntimeName) = .empty,
    constant_names: std.ArrayList(RuntimeName) = .empty,
    declaration_traits: std.ArrayList(DeclarationTraits) = .empty,
    /// Parser-owned allocations, including synthetic and shared-span nodes.
    declaration_nodes: std.ArrayList(struct { root: Id, first: Id, end: Id }) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    operator_origins: std.ArrayList(struct { node: Id, span: Span, member: symbols.Symbol = 0, member_point: u32 = 0 }) = .empty,
    // Singleton type groups share a semantic node but retain the source
    // origin where a constructor value is converted to a concrete type.
    type_conversion_origins: std.ArrayList(struct { node: Id, point: u32 }) = .empty,
    pub fn init(allocator: std.mem.Allocator) !Tree {
        var self: Tree = .{};
        errdefer self.deinit(allocator);
        try self.nodes.append(allocator, .{ .tag = .invalid });
        try self.spans.append(allocator, .{ .start = 0, .end = 0 });
        return self;
    }
    pub fn deinit(self: *Tree, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.spans.deinit(allocator);
        self.extra.deinit(allocator);
        self.roots.deinit(allocator);
        self.runtime_names.deinit(allocator);
        self.constant_names.deinit(allocator);
        self.declaration_traits.deinit(allocator);
        self.declaration_nodes.deinit(allocator);
        self.diagnostics.deinit(allocator);
        self.operator_origins.deinit(allocator);
        self.type_conversion_origins.deinit(allocator);
        self.* = .{};
    }
    pub fn declarationNodes(self: *const Tree, root: Id) ?List {
        for (self.declaration_nodes.items) |owner| if (owner.root == root) {
            if (owner.first == 0 or owner.first >= owner.end or owner.end > self.nodes.items.len or root < owner.first or root >= owner.end) return null;
            return .{ .start = owner.first, .len = owner.end - owner.first };
        };
        return null;
    }
    pub fn declarationTraits(self: *const Tree, id: Id) DeclarationTraits {
        const index = std.sort.binarySearch(DeclarationTraits, self.declaration_traits.items, id, struct {
            fn compare(key: Id, value: DeclarationTraits) std.math.Order {
                return std.math.order(key, value.declaration);
            }
        }.compare) orelse return .{ .declaration = id };
        return self.declaration_traits.items[index];
    }
    pub fn node(self: *const Tree, id: Id) Node {
        return self.nodes.items[id];
    }
    pub fn span(self: *const Tree, id: Id) Span {
        return self.spans.items[id];
    }
    pub fn runtimeNamePoint(self: *const Tree, declaration: Id) ?u32 {
        const index = std.sort.binarySearch(RuntimeName, self.runtime_names.items, declaration, struct {
            fn compare(key: Id, value: RuntimeName) std.math.Order {
                return std.math.order(key, value.declaration);
            }
        }.compare) orelse return null;
        return self.runtime_names.items[index].point;
    }
    pub fn valueNamePoint(self: *const Tree, declaration: Id) ?u32 {
        if (self.runtimeNamePoint(declaration)) |point| return point;
        const index = std.sort.binarySearch(RuntimeName, self.constant_names.items, declaration, struct {
            fn compare(key: Id, value: RuntimeName) std.math.Order {
                return std.math.order(key, value.declaration);
            }
        }.compare) orelse return null;
        return self.constant_names.items[index].point;
    }
    pub fn numericFault(self: *const Tree, id: Id) NumericFault {
        const n = self.node(id);
        std.debug.assert(n.tag == .numeric_error);
        const code: NumericCode = @fromBackingInt(@intCast(n.a));
        return .{ .node = id, .code = code, .span = .{ .start = n.b, .end = n.c }, .actual_token = if (code == .integer_range) .integer else .float };
    }
    pub fn typeConversionOrigin(self: *const Tree, id: Id) u32 {
        var point = self.span(id).start;
        for (self.type_conversion_origins.items) |origin| if (origin.node == id) {
            point = @min(point, origin.point);
        };
        return point;
    }
    pub fn list(self: *const Tree, range: List) []const u32 {
        return self.extra.items[range.start..][0..range.len];
    }
    pub fn children(self: *const Tree, id: Id) []const Id {
        const n = self.node(id);
        return switch (n.tag) {
            .record => self.list(.{ .start = n.b, .len = n.c }),
            .product, .array, .block, .constructors, .effect_operations, .pattern_product, .pattern_record, .pattern_row, .type_product, .type_array, .type_record => self.list(.{ .start = n.a, .len = n.b }),
            else => &.{},
        };
    }
    pub fn quantifierPredicates(self: *const Tree, id: Id) Id {
        const value = self.node(id);
        return self.extra.items[value.c + 1];
    }
    // value_decl c points to [annotation,modifier,kind,where start,len,
    // attributes start,len,flags,where node]. flags bit0=entry; kind 0=const,1=let.
    pub fn valueDecl(self: *const Tree, id: Id) ValueDecl {
        const n = self.node(id);
        std.debug.assert(n.tag == .value_decl);
        const x = self.extra.items[n.c..][0..9];
        return .{ .name = n.a, .body = n.b, .annotation = x[0], .modifier = x[1], .runtime = x[2] == 1, .exported = x[7] & 1 != 0, .where = .{ .start = x[3], .len = x[4] }, .where_node = x[8], .attributes = .{ .start = x[5], .len = x[6] } };
    }
    pub fn implementation(self: *const Tree, id: Id) ImplementationDecl {
        const n = self.node(id);
        std.debug.assert(n.tag == .implementation_decl);
        const x = self.extra.items[n.c..][0..6];
        const members = self.node(n.b);
        return .{ .name = n.a, .parameters = .{ .start = x[0], .len = x[1] }, .head = x[2], .members = .{ .start = members.a, .len = members.b }, .where = .{ .start = x[3], .len = x[4] }, .where_node = x[5] };
    }
    // parameter c points to [flags,where start,len,node]; flags bit0=demand,bit1=unit.
    pub fn parameter(self: *const Tree, id: Id) Parameter {
        const n = self.node(id);
        std.debug.assert(n.tag == .parameter);
        const x = self.extra.items[n.c..][0..4];
        return .{ .name = n.a, .annotation = n.b, .demanded = x[0] & 1 != 0, .demand = x[0] & 1 != 0, .is_unit = x[0] & 2 != 0, .where = .{ .start = x[1], .len = x[2] }, .where_node = x[3] };
    }
    // let_stmt c points to [annotation,where start,len,fallback block,where node].
    pub fn binding(self: *const Tree, id: Id) Binding {
        const n = self.node(id);
        std.debug.assert(n.tag == .let_stmt);
        const x = self.extra.items[n.c..][0..5];
        return .{ .pattern = n.a, .value = n.b, .annotation = x[0], .where = .{ .start = x[1], .len = x[2] }, .where_node = x[4], .fallback = x[3] };
    }
    // import_decl a=decoded path symbol,b=bindings start,c=metadata:
    // [bindings len,namespace symbol,path start,end,namespace start,end].
    pub fn importDecl(self: *const Tree, id: Id) ImportDecl {
        const n = self.node(id);
        std.debug.assert(n.tag == .import_decl or n.tag == .export_decl);
        const x = self.extra.items[n.c..][0..6];
        return .{ .path = n.a, .namespace = x[1], .bindings = .{ .start = n.b, .len = x[0] }, .path_span = .{ .start = x[2], .end = x[3] }, .namespace_span = .{ .start = x[4], .end = x[5] } };
    }
    pub fn importBinding(self: *const Tree, id: Id) ImportBinding {
        const n = self.node(id);
        std.debug.assert(n.tag == .import_binding);
        return .{ .name = n.a, .alias = n.b };
    }
    // fixity_decl a=operator,b=target,c=[precedence,association,flags,
    // optional attributes start,len]. flags bit0=named,bit1=attributes present.
    // Association 0=left,1=right,2=nonassociative. Targets are never discarded.
    pub fn fixity(self: *const Tree, id: Id) Fixity {
        const n = self.node(id);
        std.debug.assert(n.tag == .fixity_decl);
        const x = self.extra.items[n.c..][0..3];
        return .{ .operator = n.a, .target = n.b, .precedence = x[0], .association = x[1], .named = x[2] & 1 != 0, .attributes = if (x[2] & 2 != 0) .{ .start = self.extra.items[n.c + 3], .len = self.extra.items[n.c + 4] } else .{}, .literal_error = if (x[2] & 4 != 0) self.extra.items[n.c + 5] else 0 };
    }
};
