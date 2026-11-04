//! One immutable owner for auxiliary checked records. The schema names every
//! numeric edge; a new record field cannot silently inherit scalar semantics.
const std = @import("std");
const check = @import("../check/check.zig");
const T = @import("../check/types.zig");
const A = std.mem.Allocator;
const numeric = @import("../check/numeric_proof_bodies.zig");
const terms = @import("../check/numeric_proof_terms.zig");
comptime {
    for (@typeInfo(numeric.Owned).@"struct".field_names) |field| {
        if (!std.mem.eql(u8, field, "debits") and !std.mem.eql(u8, field, "operands") and !std.mem.eql(u8, field, "introductions") and !std.mem.eql(u8, field, "parameters") and !std.mem.eql(u8, field, "uses")) @compileError("Unregistered numeric body owner " ++ field);
    }
}
pub const fields = [_][]const u8{ "usage_loans", "rank_implementations", "generative_bindings", "dictionary_selections", "dictionary_uses", "computations", "request_loops", "request_arms", "request_controls", "reflections", "effect_scopes", "effect_runners", "provider_blocks", "resolver_blocks", "resolver_ops", "resolver_joins", "resolver_completions", "resolver_loops", "operation_uses", "statement_arms" };
fn tableType() type {
    var types: [fields.len]type = undefined;
    var attrs: [fields.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (fields, 0..) |field, index| {
        const Slice = @FieldType(check.Checked, field);
        types[index] = Slice;
        const initial: Slice = &.{};
        attrs[index] = .{ .default_value_ptr = @ptrCast(&initial) };
    }
    return @Struct(.auto, null, &fields, &types, &attrs);
}
pub const Tables = tableType();
pub const indexed_tables = [_][]const u8{ "effect_scopes", "effect_runners", "provider_blocks", "resolver_blocks", "resolver_ops", "resolver_joins", "resolver_loops", "operation_uses" };
pub const indexed_fields = [_][]const u8{ "effect_scope_ids", "effect_runner_ids", "provider_block_ids", "resolver_block_ids", "resolver_op_ids", "resolver_join_ids", "resolver_loop_ids", "operation_refs" };
pub const Route = enum { word, node, binding, ty, row, label, name, instance, scope, constructor, types, bindings, request_arms, resolver_ops, resolver_completions, carries, template, goal, proof, contract_identity, operation_identity, callee_identity, nodes_pair, proposition };
pub fn route(comptime Record: type, comptime field: []const u8) Route {
    if (Record == numeric.Introduction) return fieldRoute(field, .{ .source = .node, .owner = .node, .arguments = .nodes_pair, .proposition = .proposition });
    if (Record == numeric.Parameter) return fieldRoute(field, .{ .binding = .binding, .contract = .word, .proposition = .proposition });
    if (Record == numeric.Use) return fieldRoute(field, .{ .source = .node, .callee = .binding, .witness = .node, .proposition = .proposition });
    if (Record == check.UsageLoan) return fieldRoute(field, .{ .source = .node, .callback = .node, .parameter = .node, .region = .ty, .mutable = .word, .acquire = .node, .release = .node });
    if (Record == @import("../check/generative_schemes.zig").Binder) return fieldRoute(field, .{ .owner = .node, .origin = .node, .arrow = .ty, .selection = .ty });
    if (Record == check.RankImplementation) return fieldRoute(field, .{ .scope = .scope, .quantified = .ty, .node = .node });
    if (Record == check.DictionarySelection) return fieldRoute(field, .{ .source = .node, .quantifier = .ty, .goal = .goal, .proof = .proof });
    if (Record == check.DictionaryUse) return fieldRoute(field, .{ .source = .node, .opening = .binding, .introduction = .node, .quantifier = .ty, .goal = .goal, .member = .word });
    if (Record == check.DictionaryGiven) return fieldRoute(field, .{ .opening = .binding, .introduction = .node, .quantifier = .ty, .goal = .goal, .arguments = .types, .member_types = .types });
    if (Record == check.Computation) return fieldRoute(field, .{ .node = .node, .action = .node, .ty = .ty, .action_type = .ty });
    if (Record == check.RequestLoop) return fieldRoute(field, .{ .node = .node, .computation = .node, .value_type = .ty, .result_type = .ty, .state_type = .ty, .action_type = .ty, .arms = .request_arms, .completion = .node, .complete_pattern = .node, .complete_suite = .node, .complete_state_bindings = .bindings, .carried = .carries, .return_scope = .node });
    if (Record == check.RequestArm) return fieldRoute(field, .{ .node = .node, .loop = .node, .operation_source = .node, .operation = .label, .parameter_type = .ty, .reply_type = .ty, .signature = .ty, .pattern = .node, .suite = .node, .state_bindings = .bindings });
    if (Record == check.RequestControl) return fieldRoute(field, .{ .node = .node, .loop = .node, .kind = .word, .value_type = .ty, .bindings = .bindings, .target_scope = .node });
    if (Record == check.Reflection) return fieldRoute(field, .{ .node = .node, .kind = .word, .left = .node, .right = .node, .binding = .binding, .row = .row, .label = .label });
    if (Record == check.EffectScope) return fieldRoute(field, .{ .node = .node, .callback = .node, .parameter = .node, .capability = .ty, .result = .ty, .body_effects = .row });
    if (Record == check.EffectRunner) return fieldRoute(field, .{ .node = .node, .kind = .word, .read_token = .ty, .write_token = .ty, .initial = .node, .witness = .node, .implementation = .node, .action = .node, .state_type = .ty, .body_result = .ty, .result = .ty, .implementation_type = .ty, .action_type = .ty, .body_effects = .row, .outer_effects = .row });
    if (Record == check.ProviderBlock) return fieldRoute(field, .{ .node = .node, .provider = .node, .body_result = .ty, .result = .ty, .body_effects = .row, .outer_effects = .row });
    if (Record == check.ResolverBlock) return fieldRoute(field, .{ .node = .node, .resolver = .binding, .result = .ty, .body_effects = .row, .fallthrough = .resolver_completions });
    if (Record == check.ResolverOp) return fieldRoute(field, .{ .node = .node, .kind = .word, .member = .name, .resolver = .binding, .method = .binding, .method_type = .ty, .payload = .ty, .result = .ty, .continuation_parameter = .binding, .completed_types = .types, .done_constructor = .constructor, .completion = .resolver_completions });
    if (Record == check.ResolverJoin) return fieldRoute(field, .{ .node = .node, .parameter = .binding, .ty = .ty, .result = .ty });
    if (Record == check.ResolverCompletion) return fieldRoute(field, .{ .node = .node, .bind = .resolver_ops, .pure = .resolver_ops, .completed_types = .types, .done_constructor = .constructor });
    if (Record == check.ResolverLoop) return fieldRoute(field, .{ .node = .node, .cursor_parameter = .binding, .first_binding = .binding, .end_binding = .binding, .cursor = .ty, .step_result = .ty, .suffix_result = .ty, .iterate = .resolver_ops, .continued = .resolver_ops, .finish = .resolver_completions, .continue_constructor = .constructor, .done_constructor = .constructor });
    if (Record == check.StatementArm) return fieldRoute(field, .{ .node = .node });
    if (Record == check.OperationUse) return fieldRoute(field, .{ .node = .node, .template = .template, .arguments = .types, .signature = .ty, .instance = .instance, .capability = .node, .capability_binding = .binding, .call = .word, .operand = .node });
    @compileError("Unregistered checked auxiliary record " ++ @typeName(Record));
}
fn fieldRoute(comptime field: []const u8, comptime schema: anytype) Route {
    if (!@hasField(@TypeOf(schema), field)) @compileError("Unregistered checked auxiliary field " ++ field);
    return @field(schema, field);
}
pub fn mapRecord(value: anytype, mapper: anytype) !@TypeOf(value) {
    const Record = @TypeOf(value);
    var result = value;
    inline for (@typeInfo(Record).@"struct".field_names) |field| {
        const role = comptime route(Record, field);
        if (comptime role == .word) continue;
        @field(result, field) = try mapper.map(role, @field(value, field));
    }
    return result;
}
/// A saved selection owns a concrete query input, never the old proof graph.
/// Replaying it invokes the current ordinary evidence engine after its complete
/// implementation frontier and quantifier header have matched.
pub fn mapPredicate(value: T.Obligation, mapper: anytype) !T.Obligation {
    var result = value;
    inline for (@typeInfo(T.Obligation).@"struct".field_names) |field| {
        if (comptime std.mem.eql(u8, field, "ty") or std.mem.eql(u8, field, "other") or std.mem.eql(u8, field, "result") or std.mem.eql(u8, field, "signature")) {
            @field(result, field) = try mapper.map(.ty, @field(value, field));
        } else if (comptime std.mem.eql(u8, field, "source")) {
            result.source = try mapper.map(.node, value.source);
        } else if (comptime std.mem.eql(u8, field, "name")) {
            result.name = try mapper.map(.name, value.name);
        } else if (comptime std.mem.eql(u8, field, "identity")) {
            result.identity = switch (value.kind) {
                .contract => try mapper.map(.contract_identity, value.identity),
                .effect_operation => try mapper.map(.operation_identity, value.identity),
                .callee_use => try mapper.map(.callee_identity, value.identity),
                else => value.identity,
            };
        } else if (comptime std.mem.eql(u8, field, "kind") or std.mem.eql(u8, field, "operator") or std.mem.eql(u8, field, "explicit") or std.mem.eql(u8, field, "qualification_span") or std.mem.eql(u8, field, "qualification_unit")) {
            // Qualification-bearing inputs require their own declaration owner.
        } else @compileError("Unregistered selected predicate field " ++ field);
    }
    return result;
}
pub const Owner = struct {
    tables: Tables = .{},
    extra: []u32 = &.{},
    origins: []u32 = &.{},
    binding_origins: []u32 = &.{},
    dependencies: []u32 = &.{},
    iterators: []Iterator = &.{},
    constructors: []Constructor = &.{},
    indices: []Index = &.{},
    operation_bindings: []OperationBinding = &.{},
    selections: []Selection = &.{},
    numeric_body: numeric.Owned = .{},
    proof_parameters: []u32 = &.{},
    proof_debit: ?numeric.Debit = null,
    pub const Selection = struct { predicate: T.Obligation, arguments: T.List = .{}, implementation: bool };
    pub const Index = struct { node: u32, table: u32, value: u32 };
    pub const OperationBinding = struct { binding: u32, operation: u32 };
    pub const Constructor = struct { nominal: T.NominalIdentity, tag: u32 };
    pub const Iterator = struct { node: u32, body: u32 };
    // Table capture is unrolled; share cleanup across all its failure edges.
    pub noinline fn deinit(self: *Owner, a: A) void {
        inline for (fields) |field| a.free(@field(self.tables, field));
        a.free(self.extra);
        a.free(self.origins);
        a.free(self.binding_origins);
        a.free(self.dependencies);
        a.free(self.iterators);
        a.free(self.constructors);
        a.free(self.indices);
        a.free(self.operation_bindings);
        a.free(self.selections);
        self.numeric_body.deinit(a);
        a.free(self.proof_parameters);
        a.destroy(self);
    }
    pub fn bytes(self: *const Owner) usize {
        var result: usize = @sizeOf(Owner) + (self.extra.len + self.dependencies.len + self.origins.len + self.binding_origins.len) * 4 + self.iterators.len * @sizeOf(Iterator) + self.constructors.len * @sizeOf(Constructor);
        result += self.indices.len * @sizeOf(Index) + self.operation_bindings.len * @sizeOf(OperationBinding) + self.selections.len * @sizeOf(Selection);
        inline for (fields) |field| result += @field(self.tables, field).len * @sizeOf(@typeInfo(@FieldType(Tables, field)).pointer.child);
        result += self.numeric_body.operands.len * @sizeOf(terms.Term) + self.numeric_body.introductions.len * @sizeOf(numeric.Introduction) + self.numeric_body.parameters.len * @sizeOf(numeric.Parameter) + self.numeric_body.uses.len * @sizeOf(numeric.Use) + self.proof_parameters.len * 4;
        return result;
    }
    pub fn list(self: *const Owner, span: T.List) []const u32 {
        return self.extra[span.start..][0..span.len];
    }
    /// Lists have one owner and a declared element route. All phases walk the
    /// same schema, so nested roots cannot escape projection or relocation.
    pub fn transform(self: *Owner, mapper: anytype) !void {
        var visitor = Visitor(@TypeOf(mapper)){ .owner = self, .mapper = mapper };
        inline for (fields) |field| {
            for (@field(self.tables, field)) |*entry| entry.* = try mapRecord(entry.*, &visitor);
        }
        for (@constCast(self.numeric_body.operands)) |*operand| if (operand.tag == .version) {
            operand.a = switch (operand.b) {
                1 => try mapper.map(.binding, operand.a),
                2 => try mapper.map(.node, operand.a),
                else => return error.DependencyLimit,
            };
        };
        for (@constCast(self.numeric_body.introductions)) |*entry| entry.* = try mapRecord(entry.*, &visitor);
        for (@constCast(self.numeric_body.parameters)) |*entry| entry.* = try mapRecord(entry.*, &visitor);
        for (@constCast(self.numeric_body.uses)) |*entry| entry.* = try mapRecord(entry.*, &visitor);
        for (self.proof_parameters) |*binding| binding.* = try mapper.map(.binding, binding.*);
        for (self.selections) |*selection| {
            selection.predicate = try mapPredicate(selection.predicate, &visitor);
            selection.arguments = try visitor.map(.types, selection.arguments);
        }
    }
};
fn Visitor(comptime Mapper: type) type {
    return struct {
        owner: *Owner,
        mapper: Mapper,
        pub fn map(self: *@This(), comptime role: Route, value: anytype) !@TypeOf(value) {
            if (comptime role == .instance) {
                if (value.unit == 0 and value.decl != 0) return .{ .unit = 0, .decl = try self.mapper.map(.ty, value.decl) };
            }
            if (comptime role == .proposition) return value;
            if (comptime role == .nodes_pair) {
                var mapped = value;
                for (&mapped) |*node| node.* = try self.mapper.map(.node, node.*);
                return mapped;
            }
            if (comptime role == .proof) {
                return switch (value) {
                    .given => |given| .{ .given = try mapRecord(given, self) },
                    .selected => self.mapper.map(role, value),
                };
            }
            if (comptime role == .types or role == .bindings) {
                const element: Route = if (role == .types) .ty else .binding;
                for (self.owner.extra[value.start..][0..value.len]) |*item| item.* = try self.mapper.map(element, item.*);
                return value;
            }
            return self.mapper.map(role, value);
        }
    };
}
fn source(entry: anytype) u32 {
    if (comptime @hasField(@TypeOf(entry), "source")) return entry.source;
    if (comptime @hasField(@TypeOf(entry), "node")) return entry.node;
    return entry.owner;
}
pub fn nodePosition(ids: []const u32, id: u32) !u32 {
    if (id == 0) return 0;
    return @intCast((std.mem.findScalar(u32, ids, id) orelse return error.DependencyLimit) + 1);
}
pub fn recordIndex(checked: *const check.Checked, ids: []const u32, comptime field: []const u8, index: u32) !u32 {
    if (index == 0) return 0;
    const records = @field(checked, field);
    if (index > records.len) return error.DependencyLimit;
    var selected: u32 = 0;
    for (records, 0..) |entry, ordinal| {
        if (std.mem.findScalar(u32, ids, source(entry)) == null) continue;
        selected += 1;
        if (ordinal == index - 1) return selected;
    }
    return error.DependencyLimit;
}
/// Capture records selected by their actual parser owner, never by spans or
/// coincidental numeric identifiers. Binding/type ownership is supplied by the
/// enclosing checked fragment and projected once into its shared graph.
pub fn capture(a: A, checked: *const check.Checked, ids: []const u32) !?*Owner {
    if (ids.len == 0) return null;
    var count: usize = 0;
    inline for (fields) |field| for (@field(checked, field)) |entry| {
        if (std.mem.findScalar(u32, ids, source(entry)) != null) count += 1;
    };
    for (ids) |id| if (id < checked.iterator_bodies.len and checked.iterator_bodies[id] != 0) {
        count += 1;
    };
    const global = checked.resolved[ids[0]];
    if (count == 0) for (checked.types.nodes.items) |node| {
        if (node.tag != .scoped or node.b != checked.unit or std.mem.findScalar(u32, ids, node.c) == null) continue;
        count = 1;
        break;
    };
    for (checked.proof_bodies.introductions) |entry| if (std.mem.findScalar(u32, ids, entry.source) != null) {
        count += 1;
    };
    for (checked.proof_bodies.uses) |entry| if (std.mem.findScalar(u32, ids, entry.source) != null) {
        count += 1;
    };
    for (checked.proof_bodies.parameters) |entry| if (entry.contract == global) {
        count += 1;
    };
    for (checked.proof_contracts) |contract| if (contract.binding == global) {
        count += 1;
    };
    for (checked.proof_bodies.debits) |debit| if (debit.binding == global) {
        count += 1;
    };
    if (count == 0) return null;
    if (count > 4096) return error.DependencyLimit;
    const owner = try a.create(Owner);
    owner.* = .{};
    errdefer owner.deinit(a);
    var extra: std.ArrayList(u32) = .empty;
    defer extra.deinit(a);
    var selections: std.ArrayList(Owner.Selection) = .empty;
    defer selections.deinit(a);
    var mapper: Capture = .{ .allocator = a, .checked = checked, .ids = ids, .extra = &extra, .selections = &selections };
    inline for (fields) |field| {
        var entries: std.ArrayList(@typeInfo(@FieldType(Tables, field)).pointer.child) = .empty;
        defer entries.deinit(a);
        for (@field(checked, field)) |entry| {
            if (std.mem.findScalar(u32, ids, source(entry)) == null) continue;
            if (comptime @hasField(@TypeOf(entry), "quantifier") and @hasField(@TypeOf(entry), "goal")) {
                if (entry.goal >= checked.types.quantifierGoals(entry.quantifier).len) return error.DependencyLimit;
            }
            mapper.source = source(entry);
            try entries.append(a, try mapRecord(entry, &mapper));
        }
        @field(owner.tables, field) = try entries.toOwnedSlice(a);
    }
    var iterators: std.ArrayList(Owner.Iterator) = .empty;
    defer iterators.deinit(a);
    for (ids) |id| {
        if (id >= checked.iterator_bodies.len or checked.iterator_bodies[id] == 0) continue;
        try iterators.append(a, .{ .node = try nodePosition(ids, id), .body = try nodePosition(ids, checked.iterator_bodies[id]) });
    }
    var indices: std.ArrayList(Owner.Index) = .empty;
    defer indices.deinit(a);
    inline for (indexed_fields, indexed_tables, 0..) |field, table, slot| {
        for (ids) |id| {
            const values = @field(checked, field);
            if (id >= values.len or values[id] == 0) continue;
            const target = try recordIndex(checked, ids, table, values[id]);
            try indices.append(a, .{ .node = try nodePosition(ids, id), .table = @intCast(slot), .value = target });
        }
    }
    var numeric_builder: NumericCapture = .{ .allocator = a, .checked = checked, .ids = ids, .global = global };
    defer numeric_builder.deinit();
    owner.numeric_body = try numeric_builder.capture();
    for (checked.proof_bodies.debits) |debit| if (debit.binding == global) {
        if (owner.proof_debit != null) return error.DependencyLimit;
        owner.proof_debit = debit;
        owner.proof_debit.?.binding = 0;
    };
    if ((owner.numeric_body.operands.len != 0 or owner.numeric_body.parameters.len != 0) and owner.proof_debit == null) return error.DependencyLimit;
    for (checked.proof_contracts) |contract| if (contract.binding == global) {
        owner.proof_parameters = try a.dupe(u32, contract.parameters);
    };
    owner.indices = try indices.toOwnedSlice(a);
    owner.iterators = try iterators.toOwnedSlice(a);
    owner.extra = try extra.toOwnedSlice(a);
    owner.origins = try a.dupe(u32, ids);
    owner.selections = try selections.toOwnedSlice(a);
    return owner;
}
const Capture = struct {
    allocator: A,
    checked: *const check.Checked,
    ids: []const u32,
    extra: *std.ArrayList(u32),
    selections: *std.ArrayList(Owner.Selection),
    source: u32 = 0,
    pub fn map(self: *Capture, comptime role: Route, value: anytype) !@TypeOf(value) {
        switch (comptime role) {
            .node => return nodePosition(self.ids, value),
            .resolver_ops => return recordIndex(self.checked, self.ids, "resolver_ops", value),
            .resolver_completions => return recordIndex(self.checked, self.ids, "resolver_completions", value),
            .types, .bindings, .request_arms => {
                const start: u32 = @intCast(self.extra.items.len);
                const items = self.checked.types.list(value);
                if (items.len > 4096 - self.extra.items.len) return error.DependencyLimit;
                for (items) |item| {
                    var mapped = item;
                    if (comptime role == .request_arms) mapped = try recordIndex(self.checked, self.ids, "request_arms", item + 1);
                    try self.extra.append(self.allocator, mapped);
                }
                return .{ .start = start, .len = value.len };
            },
            .carries => {
                if (value.len == 0) return .{};
                if (value.start >= self.checked.loop_carries.len) return error.DependencyLimit;
                const node = self.checked.loop_carries[value.start].node;
                if (!std.meta.eql(value, self.checked.loop_ranges[node])) return error.DependencyLimit;
                return .{ .start = try nodePosition(self.ids, node), .len = value.len };
            },

            .proof => return switch (value) {
                .given => |given| blk: {
                    if (given.goal >= self.checked.types.quantifierGoals(given.quantifier).len) return error.DependencyLimit;
                    break :blk .{ .given = try mapRecord(given, self) };
                },
                .selected => |index| blk: {
                    if (index >= self.checked.selected_proofs.len or self.selections.items.len >= 4096) return error.DependencyLimit;
                    const old = self.checked.selected_proofs[index];
                    var predicate = old.predicate;
                    const implementation = old.kind == .implementation;
                    if (implementation) predicate = .{ .ty = 0, .kind = .contract, .identity = old.contract, .source = self.source };
                    predicate.source = self.source;
                    if (predicate.qualification_span != null or predicate.qualification_unit != 0) return error.DependencyLimit;
                    if (predicate.kind != .contract and predicate.kind != .effect_operation and predicate.kind != .callee_use and (predicate.identity.unit != 0 or predicate.identity.decl != 0)) return error.DependencyLimit;
                    const saved = try mapPredicate(predicate, self);
                    var arguments: T.List = .{};
                    if (implementation) arguments = try self.map(.types, old.arguments);
                    const slot: u32 = @intCast(self.selections.items.len);
                    try self.selections.append(self.allocator, .{ .predicate = saved, .arguments = arguments, .implementation = implementation });
                    break :blk .{ .selected = slot };
                },
            },
            else => return value,
        }
    }
};

// Numeric terms are projected by their actual DAG edges. A version's role is
// checked metadata (binding or AST evaluation), not a guessed integer range.
const NumericCapture = struct {
    allocator: A,
    checked: *const check.Checked,
    ids: []const u32,
    global: u32,
    body: numeric.Builder = .{},
    mapped: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fn deinit(self: *NumericCapture) void {
        self.body.deinit(self.allocator);
        self.mapped.deinit(self.allocator);
    }
    fn term(self: *NumericCapture, id: u32, depth: usize) !u32 {
        if (self.mapped.get(id)) |mapped| return mapped;
        if (depth >= 128 or self.mapped.count() >= 4096 or id == 0 or id > self.checked.proof_bodies.operands.len) return error.DependencyLimit;
        var value = self.checked.proof_bodies.operands[id - 1];
        switch (value.tag) {
            .length, .complement => value.a = try self.term(value.a, depth + 1),
            .version => switch (value.b) {
                1 => {
                    if (value.a == 0 or value.a >= self.checked.bindings.len) return error.DependencyLimit;
                    const binding = self.checked.bindings[value.a];
                    if (binding.kind == .parameter or binding.kind == .local) {
                        if (std.mem.findScalar(u32, self.ids, binding.declaration) == null or std.mem.findScalar(u32, self.ids, binding.owner) == null) return error.DependencyLimit;
                    } else if (binding.kind != .global and binding.kind != .external) return error.DependencyLimit;
                    const tag = self.checked.types.node(self.checked.types.head(binding.ty, 0)).tag;
                    const expected: T.Tag = switch (value.kind) {
                        .u32 => .u32,
                        .array => .array,
                        .list => .list,
                    };
                    if (tag != expected) return error.DependencyLimit;
                },
                2 => _ = try nodePosition(self.ids, value.a),
                else => return error.DependencyLimit,
            },
            .literal => {},
            .formal, .capture => return error.DependencyLimit,
        }
        const mapped = try self.body.values.intern(self.allocator, value);
        try self.mapped.put(self.allocator, id, mapped);
        return mapped;
    }
    fn proposition(self: *NumericCapture, value: terms.Proposition) !terms.Proposition {
        return .{ .relation = value.relation, .left = try self.term(value.left, 0), .right = try self.term(value.right, 0) };
    }
    fn capture(self: *NumericCapture) !numeric.Owned {
        for (self.checked.proof_bodies.introductions) |entry| {
            if (std.mem.findScalar(u32, self.ids, entry.source) == null) continue;
            var mapped = entry;
            mapped.proposition = try self.proposition(entry.proposition);
            // Source coordinates are normalized once, before any publication.
            mapped.source = try nodePosition(self.ids, entry.source);
            mapped.owner = try nodePosition(self.ids, entry.owner);
            for (&mapped.arguments) |*node| node.* = try nodePosition(self.ids, node.*);
            try self.body.introduce(self.allocator, mapped);
        }
        for (self.checked.proof_bodies.parameters) |entry| {
            if (entry.contract != self.global) continue;
            var mapped = entry;
            mapped.contract = 0;
            mapped.proposition = try self.proposition(entry.proposition);
            try self.body.parameter(self.allocator, mapped);
        }
        for (self.checked.proof_bodies.uses) |entry| {
            if (std.mem.findScalar(u32, self.ids, entry.source) == null) continue;
            var mapped = entry;
            mapped.source = try nodePosition(self.ids, entry.source);
            mapped.witness = try nodePosition(self.ids, entry.witness);
            mapped.proposition = try self.proposition(entry.proposition);
            try self.body.use(self.allocator, mapped);
        }
        for (self.checked.proof_bodies.debits) |debit| if (debit.binding == self.global) {
            if (debit.output.terms > self.checked.proof_bodies.operands.len or debit.frontier.terms > debit.output.terms) return error.DependencyLimit;
            for (debit.frontier.terms..debit.output.terms) |index| _ = self.term(@intCast(index + 1), 0) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
        };
        var owned = try self.body.take(self.allocator);
        errdefer owned.deinit(self.allocator);
        // The generic phases now see only owned AST positions. Binding edges
        // remain raw until the enclosing body has ordered its complete reads.
        for (@constCast(owned.operands)) |*operand| if (operand.tag == .version and operand.b == 2) {
            operand.a = try nodePosition(self.ids, operand.a);
        };
        return owned;
    }
};
