//! Freeze principal source interfaces with the same chronological projection
//! rules as owned Core. Nothing borrows syntax or a mutable Store afterward.
const std = @import("std");
const check = @import("check.zig");
const ast = @import("ast.zig");
const T = @import("types.zig");
const PI = @import("principal_interface.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{DependencyLimit};

const Projector = struct {
    allocator: Allocator,
    checked: *const check.Checked,
    tree: *const ast.Tree,
    type_nodes: std.ArrayList(T.Node) = .empty,
    type_extra: std.ArrayList(T.Id) = .empty,
    effect_rows: std.ArrayList(T.Effects.Row) = .empty,
    effect_labels: std.ArrayList(T.Effects.Label) = .empty,
    effect_operations: std.ArrayList(T.Operation) = .empty,
    obligations: std.ArrayList(T.Obligation) = .empty,
    obligation_spans: std.ArrayList(ast.Span) = .empty,
    pattern_nodes: std.ArrayList(@import("parameter_patterns.zig").Node) = .empty,
    pattern_extra: std.ArrayList(u32) = .empty,
    pattern_map: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    type_map: []T.Id = &.{},
    variable_map: []T.Id = &.{},
    effect_row_map: []u32 = &.{},
    effect_variable_map: []u32 = &.{},
    effect_operation_map: []u32 = &.{},
    variable_count: u32 = 0,
    effect_variable_count: u32 = 0,

    fn allocateMap(self: *Projector, target: *[]u32, count: usize) Error!void {
        target.* = try self.allocator.alloc(u32, count);
        @memset(target.*, 0);
    }
    fn initialize(self: *Projector) Error!void {
        try self.allocateMap(&self.type_map, self.checked.types.nodes.items.len);
        try self.allocateMap(&self.variable_map, self.checked.types.variables.items.len);
        try self.allocateMap(&self.effect_row_map, self.checked.types.effects.rows.items.len);
        try self.allocateMap(&self.effect_variable_map, self.checked.types.effects.variables.items.len);
        try self.allocateMap(&self.effect_operation_map, self.checked.types.operations.items.len);
        for (self.checked.types.nodes.items[0..6]) |node| try self.type_nodes.append(self.allocator, .{ .tag = node.tag, .a = node.a, .b = node.b, .c = node.c });
        for (0..6) |i| self.type_map[i] = @intCast(i);
        try self.effect_rows.append(self.allocator, .{});
        try self.effect_operations.appendSlice(self.allocator, &.{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } });
        self.effect_operation_map[T.foreign_operation] = T.foreign_operation;
    }
    fn deinit(self: *Projector) void {
        self.pattern_nodes.deinit(self.allocator);
        self.pattern_extra.deinit(self.allocator);
        self.pattern_map.deinit(self.allocator);
        inline for (.{ "type_nodes", "type_extra", "effect_rows", "effect_labels", "effect_operations", "obligations", "obligation_spans" }) |field| @field(self, field).deinit(self.allocator);
        inline for (.{ "type_map", "variable_map", "effect_row_map", "effect_variable_map", "effect_operation_map" }) |field| self.allocator.free(@field(self, field));
    }
    fn addType(self: *Projector, value: T.Node) Error!T.Id {
        if (self.type_nodes.items.len == std.math.maxInt(u32)) return error.DependencyLimit;
        const id: T.Id = @intCast(self.type_nodes.items.len);
        try self.type_nodes.append(self.allocator, value);
        return id;
    }
    fn projectType(self: *Projector, source: T.Id, depth: usize) Error!T.Id {
        if (source == 0) return 0;
        if (self.type_map[source] != 0) return self.type_map[source];
        if (depth >= 1024) return error.DependencyLimit;
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
            .nominal, .projection => blk: {
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(self.allocator);
                const source_arguments = self.checked.types.nominalArguments(original);
                try arguments.append(self.allocator, @intCast(source_arguments.len));
                for (source_arguments) |argument| try arguments.append(self.allocator, try self.projectType(argument, depth + 1));
                if (original.tag == .projection) try arguments.append(self.allocator, self.checked.types.projectionMember(original));
                const span = try self.saveTypes(arguments.items);
                break :blk .{ .tag = original.tag, .a = original.a, .b = original.b, .c = span.start };
            },
            .array, .list, .cursor, .resolver => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1) },
            .demand, .provider => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1), .c = try self.projectRow(original.c, depth + 1) },
            .state_provider => .{ .tag = .state_provider, .a = try self.projectType(original.a, depth + 1), .b = try self.projectType(original.b, depth + 1), .c = try self.projectType(original.c, depth + 1) },
            else => .{ .tag = original.tag, .a = original.a, .b = original.b, .c = original.c },
        };
        const id = try self.addType(value);
        self.type_map[source] = id;
        if (original.tag == .variable) self.variable_map[original.a] = id;
        return id;
    }
    fn projectRowVariable(self: *Projector, variable: u32) Error!u32 {
        if (variable >= self.effect_variable_map.len) return error.DependencyLimit;
        if (self.effect_variable_map[variable] != 0) return self.effect_variable_map[variable] - 1;
        if (self.effect_variable_count == std.math.maxInt(u32)) return error.DependencyLimit;
        const id = self.effect_variable_count;
        self.effect_variable_count += 1;
        self.effect_variable_map[variable] = id + 1;
        return id;
    }
    fn projectOperation(self: *Projector, label: T.Effects.Label, depth: usize) Error!T.Effects.Label {
        if (depth >= 1024 or label == 0 or label >= self.effect_operation_map.len) return error.DependencyLimit;
        if (self.effect_operation_map[label] != 0) return self.effect_operation_map[label];
        const source = self.checked.types.operations.items[label];
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(self.allocator);
        for (self.checked.types.list(source.arguments)) |argument| try values.append(self.allocator, try self.projectType(argument, depth + 1));
        const arguments = try self.saveTypes(values.items);
        if (self.effect_operations.items.len == std.math.maxInt(u32)) return error.DependencyLimit;
        const id: u32 = @intCast(self.effect_operations.items.len);
        try self.effect_operations.append(self.allocator, .{ .identity = source.identity, .arguments = arguments });
        self.effect_operation_map[label] = id;
        return id;
    }
    fn projectRow(self: *Projector, source: T.Effects.Id, depth: usize) Error!T.Effects.Id {
        if (source == 0) return 0;
        if (depth >= 1024 or source >= self.effect_row_map.len) return error.DependencyLimit;
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
        if (self.effect_rows.items.len == std.math.maxInt(u32) or labels.items.len > std.math.maxInt(u32) - self.effect_labels.items.len) return error.DependencyLimit;
        const start: u32 = @intCast(self.effect_labels.items.len);
        try self.effect_labels.appendSlice(self.allocator, labels.items);
        const id: u32 = @intCast(self.effect_rows.items.len);
        try self.effect_rows.append(self.allocator, .{ .labels = .{ .start = start, .len = @intCast(labels.items.len) }, .tail = tail });
        self.effect_row_map[source] = id + 1;
        return id;
    }
    fn saveTypes(self: *Projector, values: []const T.Id) Error!T.List {
        if (values.len > std.math.maxInt(u32) - self.type_extra.items.len) return error.DependencyLimit;
        const start: u32 = @intCast(self.type_extra.items.len);
        try self.type_extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn projectScheme(self: *Projector, scheme: T.Scheme) Error!T.Scheme {
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
        for (self.checked.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |value| {
            try self.obligations.append(self.allocator, .{ .ty = try self.projectType(value.ty, 0), .kind = value.kind, .source = 0, .name = value.name, .result = try self.projectType(value.result, 0), .other = try self.projectType(value.other, 0), .signature = try self.projectType(value.signature, 0), .operator = value.operator, .identity = value.identity, .explicit = value.explicit, .qualification_span = value.qualification_span, .qualification_unit = value.qualification_unit });
            try self.obligation_spans.append(self.allocator, self.checked.diagnosticSpan(self.tree, value.source));
        }
        return .{ .root = root, .variables = span, .row_variables = row_span, .closed_rows = closed_span, .obligations = .{ .start = start, .len = @intCast(self.obligations.items.len - start) } };
    }
    fn projectedList(self: *Projector, source: T.List) Error!T.List {
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(self.allocator);
        for (self.checked.types.list(source)) |id| try values.append(self.allocator, try self.projectType(id, 0));
        return self.saveTypes(values.items);
    }
    fn parameterPattern(self: *Projector, id: u32, depth: usize) Error!u32 {
        if (depth >= 256) return error.DependencyLimit;
        if (self.pattern_map.get(id)) |known| return known;
        const source = self.checked.parameter_patterns.node(id);
        var result = source;
        if (source.kind == .binding) {
            result.a = try self.projectType(source.a, 0);
        } else {
            var children: std.ArrayList(u32) = .empty;
            defer children.deinit(self.allocator);
            if (source.kind == .record) {
                for (0..source.b) |index| {
                    const field = self.checked.parameter_patterns.field(source, index);
                    try children.appendSlice(self.allocator, &.{ field.name, try self.parameterPattern(field.pattern, depth + 1) });
                }
            } else for (self.checked.parameter_patterns.list(.{ .start = source.a, .len = source.b })) |child| try children.append(self.allocator, try self.parameterPattern(child, depth + 1));
            result.a = @intCast(self.pattern_extra.items.len);
            try self.pattern_extra.appendSlice(self.allocator, children.items);
        }
        const index: u32 = @intCast(self.pattern_nodes.items.len);
        try self.pattern_nodes.append(self.allocator, result);
        try self.pattern_map.put(self.allocator, id, index);
        return index;
    }
    fn parameterPatterns(self: *Projector, source: T.List) Error!T.List {
        var nodes: std.ArrayList(u32) = .empty;
        defer nodes.deinit(self.allocator);
        for (self.checked.parameter_patterns.list(source)) |id| try nodes.append(self.allocator, try self.parameterPattern(id, 0));
        const start: u32 = @intCast(self.pattern_extra.items.len);
        try self.pattern_extra.appendSlice(self.allocator, nodes.items);
        return .{ .start = start, .len = @intCast(nodes.items.len) };
    }
    fn copiedList(self: *Projector, source: T.List) Error!T.List {
        return self.saveTypes(self.checked.types.list(source));
    }
};

pub fn deinit(allocator: Allocator, owner: *PI.Interface) void {
    inline for (.{ "nodes", "extra", "rows", "labels", "operations" }) |field| allocator.free(@field(owner.graph, field));
    allocator.free(owner.patterns.nodes);
    allocator.free(owner.patterns.extra);
    inline for (.{ "bindings", "obligations", "obligation_spans", "nominals", "constructors", "effect_families", "effect_templates", "associated", "contracts", "contract_predicates", "contract_members" }) |field| allocator.free(@field(owner, field));
    owner.* = undefined;
}

pub fn freeze(allocator: Allocator, tree: *const ast.Tree, checked: *const check.Checked) Error!PI.Interface {
    return freezeMode(allocator, tree, checked, false);
}

/// A module interface publishes reusable producer principals, not local facts
/// later constrained by that module's own body. Keep original binding slots for
/// numeric catalogs; executable locals remain fully represented in owned Core.
pub fn freezePrincipal(allocator: Allocator, tree: *const ast.Tree, checked: *const check.Checked) Error!PI.Interface {
    return freezeMode(allocator, tree, checked, true);
}

/// Publish a shared immutable graph for checked body facts. The caller owns
/// roots and the returned graph; no solver substitution or scratch view escapes.
pub fn freezeRoots(allocator: Allocator, tree: *const ast.Tree, checked: *const check.Checked, roots: []T.Id, row_variables: []u32) Error!@import("frozen_types.zig").Graph {
    var projector: Projector = .{ .allocator = allocator, .checked = checked, .tree = tree };
    defer projector.deinit();
    try projector.initialize();
    for (roots) |*root| root.* = try projector.projectType(root.*, 0);
    for (row_variables) |*variable| variable.* = try projector.projectRowVariable(variable.*);
    var graph: @import("frozen_types.zig").Graph = .{ .nodes = &.{}, .extra = &.{}, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = projector.effect_variable_count };
    errdefer deinitGraph(allocator, &graph);
    graph.nodes = try projector.type_nodes.toOwnedSlice(allocator);
    graph.extra = try projector.type_extra.toOwnedSlice(allocator);
    graph.rows = try projector.effect_rows.toOwnedSlice(allocator);
    graph.labels = try projector.effect_labels.toOwnedSlice(allocator);
    graph.operations = try projector.effect_operations.toOwnedSlice(allocator);
    return graph;
}

pub fn deinitGraph(allocator: Allocator, graph: *@import("frozen_types.zig").Graph) void {
    inline for (.{ "nodes", "extra", "rows", "labels", "operations" }) |field| allocator.free(@field(graph, field));
}

fn freezeMode(allocator: Allocator, tree: *const ast.Tree, checked: *const check.Checked, comptime principal_only: bool) Error!PI.Interface {
    var projector: Projector = .{ .allocator = allocator, .checked = checked, .tree = tree };
    defer projector.deinit();
    try projector.initialize();
    var result: PI.Interface = .{
        .unit = checked.unit,
        .graph = .{ .nodes = &.{}, .extra = &.{}, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &.{},
        .obligations = &.{},
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
    };
    errdefer deinit(allocator, &result);
    result.bindings = try allocator.alloc(PI.Binding, checked.bindings.len);
    const retained = if (principal_only) try allocator.alloc(bool, checked.bindings.len) else &.{};
    defer if (principal_only) allocator.free(retained);
    if (principal_only) {
        for (checked.bindings, retained) |b, *keep| keep.* = (b.kind == .global and !b.private) or b.kind == .external;
        for (checked.associated) |method| if (!checked.bindings[method.binding].private) {
            retained[method.binding] = true;
        };
    }
    for (checked.bindings, result.bindings, 0..) |old, *value, id| {
        value.* = if (!principal_only or retained[id])
            .{ .private = old.private, .name = old.name, .kind = old.kind, .named_function = old.named_function, .ty = try projector.projectType(old.ty, 0), .scheme = try projector.projectScheme(old.scheme), .external = old.external }
        else
            .{ .private = old.private, .name = 0, .kind = old.kind, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    }
    result.nominals = try allocator.alloc(PI.Nominal, checked.nominals.len);
    for (checked.nominals, result.nominals) |old, *value| {
        value.* = old;
        value.declaration = 0;
        if (principal_only and old.private) {
            value.storage = .{};
            value.name = 0;
            value.parameters = .{};
            value.variables = .{};
            value.patterns = .{};
            value.parameter_names = .{};
            value.constructors = .{};
            value.alias = 0;
            value.alias_rows = .{};
            continue;
        }
        value.alias = try projector.projectType(old.alias, 0);
        var alias_rows: std.ArrayList(T.Id) = .empty;
        defer alias_rows.deinit(allocator);
        for (checked.types.list(old.alias_rows)) |row| try alias_rows.append(allocator, try projector.projectRowVariable(row));
        value.alias_rows = try projector.saveTypes(alias_rows.items);
        value.parameters = try projector.projectedList(old.parameters);
        value.variables = try projector.projectedList(old.variables);
        value.parameter_names = try projector.copiedList(old.parameter_names);
        value.patterns = try projector.parameterPatterns(old.patterns);
        value.constructors = .{};
        if (!principal_only or !old.is_opaque) value.constructors = try projector.copiedList(old.constructors);
    }
    result.constructors = try allocator.alloc(PI.Constructor, checked.constructors.len);
    for (checked.constructors, result.constructors) |old, *value| {
        value.* = old;
        if (principal_only and old.private) {
            value.name = 0;
            value.scheme = .{};
            value.payload = 0;
            continue;
        }
        value.scheme = try projector.projectScheme(old.scheme);
        value.payload = try projector.projectType(old.payload, 0);
    }
    result.effect_families = try allocator.alloc(PI.EffectFamily, checked.effect_families.len);
    for (checked.effect_families, result.effect_families) |old, *value| {
        value.* = old;
        if (principal_only and old.private) {
            value.name = 0;
            value.parameters = .{};
            value.variables = .{};
            value.patterns = .{};
            value.parameter_names = .{};
            value.operations = .{};
            continue;
        }
        value.parameters = try projector.projectedList(old.parameters);
        value.variables = try projector.projectedList(old.variables);
        value.parameter_names = try projector.copiedList(old.parameter_names);
        value.patterns = try projector.parameterPatterns(old.patterns);
        value.operations = try projector.copiedList(old.operations);
    }
    result.effect_templates = try allocator.alloc(PI.EffectTemplate, checked.effect_templates.len);
    for (checked.effect_templates, result.effect_templates) |old, *value| {
        value.* = old;
        if (principal_only and checked.effect_families[old.family].private) {
            value.name = 0;
            value.parameter = 0;
            value.result = 0;
            continue;
        }
        value.parameter = try projector.projectType(old.parameter, 0);
        value.result = try projector.projectType(old.result, 0);
    }
    var associated: std.ArrayList(PI.Associated) = .empty;
    defer associated.deinit(allocator);
    for (checked.associated) |method| {
        if (principal_only and checked.bindings[method.binding].private) continue;
        try associated.append(allocator, method);
    }
    result.associated = try associated.toOwnedSlice(allocator);
    result.contracts = try allocator.alloc(PI.Contract, checked.contracts.len);
    for (checked.contracts, result.contracts) |old, *value| {
        value.* = old;
        value.declaration = 0;
        if (principal_only and old.private) {
            value.name = 0;
            value.parameters = .{};
            value.variables = .{};
            value.patterns = .{};
            value.parameter_names = .{};
            value.row_variables = .{};
            value.row_parameter_names = .{};
            value.row_parameters = .{};
            value.predicates = .{};
            value.members = .{};
            value.requires_implementation = false;
            continue;
        }
        value.parameters = try projector.projectedList(old.parameters);
        value.variables = try projector.projectedList(old.variables);
        value.parameter_names = try projector.copiedList(old.parameter_names);
        value.patterns = try projector.parameterPatterns(old.patterns);
        var rows: std.ArrayList(T.Id) = .empty;
        defer rows.deinit(allocator);
        for (checked.types.list(old.row_variables)) |row| try rows.append(allocator, try projector.projectRowVariable(row));
        value.row_variables = try projector.saveTypes(rows.items);
        value.row_parameter_names = try projector.copiedList(old.row_parameter_names);
        var row_parameters: std.ArrayList(T.Id) = .empty;
        defer row_parameters.deinit(allocator);
        for (checked.types.list(old.row_parameters)) |row| try row_parameters.append(allocator, try projector.projectRow(row, 0));
        value.row_parameters = try projector.saveTypes(row_parameters.items);
    }
    result.contract_members = try allocator.alloc(PI.ContractMember, checked.contract_members.len);
    for (checked.contract_members, result.contract_members) |old, *value| {
        value.* = old;
        const private = for (checked.contracts) |contract| {
            if (std.meta.eql(contract.identity, old.contract)) break contract.private;
        } else true;
        if (principal_only and private) {
            value.name = 0;
            value.root = 0;
            continue;
        }
        value.root = try projector.projectType(old.root, 0);
    }
    const public_predicates = try allocator.alloc(bool, checked.contract_predicates.len);
    defer allocator.free(public_predicates);
    @memset(public_predicates, true);
    if (principal_only) for (checked.contracts) |contract| {
        if (!contract.private) continue;
        @memset(public_predicates[contract.predicates.start..][0..contract.predicates.len], false);
    };
    result.contract_predicates = try allocator.alloc(T.Obligation, checked.contract_predicates.len);
    for (checked.contract_predicates, result.contract_predicates, public_predicates) |old, *value, public| {
        if (!public) {
            value.* = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true };
            continue;
        }
        value.* = old;
        inline for (.{ "ty", "other", "result", "signature" }) |field| @field(value, field) = try projector.projectType(@field(old, field), 0);
        value.source = 0;
    }
    result.patterns.nodes = try projector.pattern_nodes.toOwnedSlice(allocator);
    result.patterns.extra = try projector.pattern_extra.toOwnedSlice(allocator);
    result.obligations = try projector.obligations.toOwnedSlice(allocator);
    result.obligation_spans = try projector.obligation_spans.toOwnedSlice(allocator);
    result.graph.nodes = try projector.type_nodes.toOwnedSlice(allocator);
    result.graph.extra = try projector.type_extra.toOwnedSlice(allocator);
    result.graph.rows = try projector.effect_rows.toOwnedSlice(allocator);
    result.graph.labels = try projector.effect_labels.toOwnedSlice(allocator);
    result.graph.operations = try projector.effect_operations.toOwnedSlice(allocator);
    result.graph.row_variable_count = projector.effect_variable_count;
    return result;
}
