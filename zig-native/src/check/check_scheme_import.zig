//! Copies immutable principal types and rows into the current checker.
//! Relocation maps and private scopes belong to this transaction, never Source.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const Allocator = std.mem.Allocator;
const Identity = T.NominalIdentity;

pub const Copier = struct {
    private_namespace: u32 = 0,
    private_qualifications: []const ast.Span = &.{},
    private_unit: u32 = 0,
    private_nodes: []const ast.Id = &.{},
    private_bindings: []const u32 = &.{},
    private_tree: ?*const ast.Tree = null,
    private_scopes: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    operation_mapping: ?*const std.AutoHashMapUnmanaged(Identity, Identity) = null,
    field_mapping: ?[]const symbols.Symbol = null,
    nominal_mapping: ?*const std.AutoHashMapUnmanaged(Identity, Identity) = null,
    fresh_variables: bool = false,
    fresh_rows: bool = false,
    allocator: Allocator,
    source: F.Source,
    destination: *T.Store,
    associated: bool = false,
    mapping: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
    row_variables: std.AutoHashMapUnmanaged(u32, T.Effects.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
    labels: std.AutoHashMapUnmanaged(T.Effects.Label, T.Effects.Label) = .empty,
    pub fn copyPhysical(self: *Copier, identity: Identity) T.Error!Identity {
        if (self.private_namespace == 0 or identity.unit != self.private_namespace or identity.decl == 0 or identity.decl > self.private_nodes.len) return error.TypeLimit;
        return .{ .unit = self.private_unit, .decl = self.private_nodes[identity.decl - 1] };
    }
    pub fn copyVersion(self: *Copier, node: T.Node) T.Error!T.Id {
        if (self.private_namespace == 0) return self.destination.instanceVersion(.{ .unit = node.a, .decl = node.b }, node.c);
        if ((node.a & 0x7fffffff) != self.private_namespace or node.b == 0) return error.TypeLimit;
        var declaration: u32 = undefined;
        if (node.a & 0x80000000 != 0) {
            if (node.b > self.private_bindings.len) return error.TypeLimit;
            declaration = self.private_bindings[node.b - 1];
        } else {
            if (node.b > self.private_nodes.len) return error.TypeLimit;
            const end = self.private_tree.?.span(self.private_nodes[node.b - 1]).end;
            if (end == std.math.maxInt(u32)) return error.TypeLimit;
            declaration = end + 1;
        }
        return self.destination.instanceVersion(.{ .unit = self.private_unit, .decl = declaration }, node.c);
    }
    pub fn copyScope(self: *Copier, source: u32) T.Error!u32 {
        if (self.private_namespace == 0 or source == 0) return error.TypeLimit;
        const entry = try self.private_scopes.getOrPut(self.allocator, source);
        if (!entry.found_existing) entry.value_ptr.* = try self.destination.rigidScope();
        return entry.value_ptr.*;
    }
    pub fn deinit(self: *Copier) void {
        self.private_scopes.deinit(self.allocator);
        self.mapping.deinit(self.allocator);
        self.row_variables.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }
    // Body facts may already have copied a row through a type. Keep that same
    // fresh identity when restoring its quantifier or covariance certificate.
    pub fn relocatedRows(self: *Copier, source: []const u32) T.Error!T.List {
        var rows: std.ArrayList(u32) = .empty;
        defer rows.deinit(self.allocator);
        for (source) |old| {
            if (T.rowKeyFormal(old)) |formal| {
                try rows.append(self.allocator, try T.formalRowKey(try self.copy(formal, 0)));
                continue;
            }
            const entry = try self.row_variables.getOrPut(self.allocator, old);
            if (!entry.found_existing) entry.value_ptr.* = try self.destination.freshEffects();
            try rows.append(self.allocator, self.destination.effects.node(entry.value_ptr.*).tail.variable);
        }
        return self.destination.saveList(rows.items);
    }
    pub fn quantifiedRows(self: *Copier, span: T.List) T.Error!T.List {
        var variables: std.ArrayList(u32) = .empty;
        defer variables.deinit(self.allocator);
        for (self.source.list(span)) |index| {
            const fresh = try self.destination.freshEffects();
            try self.row_variables.put(self.allocator, index, fresh);
            try variables.append(self.allocator, self.destination.effects.node(fresh).tail.variable);
        }
        return self.destination.saveList(variables.items);
    }
    pub fn copyGenerative(self: *Copier, source: T.List) T.Error!T.List {
        if (source.len > 32 or source.len % 2 != 0) return error.TypeLimit;
        var roots: std.ArrayList(T.Id) = .empty;
        defer roots.deinit(self.allocator);
        for (self.source.list(source)) |root| try roots.append(self.allocator, try self.copy(root, 0));
        return self.destination.saveList(roots.items);
    }
    pub fn copyLabel(self: *Copier, label: T.Effects.Label, depth: usize) T.Error!T.Effects.Label {
        if (depth >= 1024 or label == 0 or label >= self.source.operationCount()) return error.TypeLimit;
        if (self.labels.get(label)) |known| return known;
        if (self.associated) try self.destination.chargeProjection();
        const operation = self.source.operation(label);
        var args: std.ArrayList(T.Id) = .empty;
        defer args.deinit(self.allocator);
        for (self.source.list(operation.arguments)) |arg| try args.append(self.allocator, try self.copy(arg, depth + 1));
        var instance = operation.instance;
        if (instance.unit != 0 and self.private_namespace != 0) {
            instance = try self.copyPhysical(instance);
        } else if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.copy(instance.decl, depth + 1);
        var identity = operation.identity;
        if (self.operation_mapping) |mapping| {
            if (label != T.foreign_operation) identity = mapping.get(identity) orelse return error.TypeLimit;
        }
        const result = try self.destination.internScopedOperation(identity, instance, args.items);
        try self.labels.put(self.allocator, label, result);
        return result;
    }
    pub fn copyRow(self: *Copier, source_row: T.Effects.Id, depth: usize) T.Error!T.Effects.Id {
        if (depth >= 1024) return error.TypeLimit;
        if (source_row == 0) return 0;
        if (self.rows.get(source_row)) |known| return known;
        if (self.associated) try self.destination.chargeProjection();
        const row = self.source.row(source_row);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for (self.source.rowLabels(row.labels)) |label| try labels.append(self.allocator, try self.copyLabel(label, depth + 1));
        const tail: T.Effects.Tail = switch (row.tail) {
            .closed => .closed,
            .parameter => |index| .{ .parameter = index },
            .formal => |formal| .{ .formal = try self.copy(formal, depth + 1) },
            .variable => |index| blk: {
                var mapped = self.row_variables.get(index);
                if (mapped == null and self.fresh_rows) {
                    mapped = try self.destination.freshEffects();
                    try self.row_variables.put(self.allocator, index, mapped.?);
                }
                break :blk self.destination.effects.node(mapped orelse return error.TypeLimit).tail;
            },
        };
        const result = self.destination.effects.row(labels.items, tail) catch |err| return T.effectError(err);
        try self.rows.put(self.allocator, source_row, result);
        return result;
    }

    fn quantifier(self: *Copier, node: T.Node, depth: usize, id: T.Id) T.Error!T.Id {
        const binders = try self.allocator.alloc(T.Id, node.c);
        defer self.allocator.free(binders);
        for (binders, 0..) |*binder, index| {
            const original = self.source.list(.{ .start = node.b, .len = node.c })[index];
            const leaf = self.source.node(original);
            if (leaf.tag != .bound) return error.TypeLimit;
            binder.* = self.mapping.get(original) orelse try self.destination.boundType(leaf.a, leaf.b);
            try self.mapping.put(self.allocator, original, binder.*);
        }
        const body = try self.copy(node.a, depth + 1);
        const goals = try self.allocator.dupe(T.Obligation, self.source.quantifierGoals(id));
        defer self.allocator.free(goals);
        for (goals) |*goal| {
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(goal.*, field) = try self.copy(@field(goal.*, field), depth + 1);
            goal.source = 0;
            if (self.private_namespace != 0) {
                if (goal.qualification_span) |origin| {
                    if (goal.qualification_unit != 0 or origin.start == 0 or origin.start > self.private_qualifications.len or origin.end != 0) return error.TypeLimit;
                    goal.qualification_span = self.private_qualifications[origin.start - 1];
                    goal.qualification_unit = self.private_unit;
                }
                if (goal.name != 0) goal.name = self.field_mapping.?[goal.name - 1];
                if (goal.kind == .contract) goal.identity = self.nominal_mapping.?.get(goal.identity) orelse return error.TypeLimit;
                if (goal.kind == .effect_operation) goal.identity = self.operation_mapping.?.get(goal.identity) orelse return error.TypeLimit;
            }
        }
        return try self.destination.quantifiedWithGoals(node.tag, body, binders, goals);
    }
    fn nominal(self: *Copier, node: T.Node, depth: usize) T.Error!T.Id {
        var args: std.ArrayList(T.Id) = .empty;
        defer args.deinit(self.allocator);
        for (self.source.nominalArguments(node)) |arg| try args.append(self.allocator, try self.copy(arg, depth + 1));
        var identity: Identity = .{ .unit = node.a, .decl = node.b };
        if (T.compilerNominalArity(identity) == null) if (self.nominal_mapping) |mapping| {
            if (mapping.get(identity)) |relocated| {
                identity = relocated;
            } else {
                const operations = self.operation_mapping orelse return error.TypeLimit;
                identity = operations.get(identity) orelse return error.TypeLimit;
            }
        };
        if (node.tag == .projection) {
            var name = self.source.projectionMember(node);
            if (self.field_mapping) |mapping| name = mapping[name];
            return try self.destination.projection(identity, name, args.items);
        }
        return try self.destination.nominal(identity, args.items);
    }
    pub fn copy(self: *Copier, source_id: T.Id, depth: usize) T.Error!T.Id {
        if (depth >= 1024) return error.TypeLimit;
        const id = self.source.head(source_id, 0);
        if (self.mapping.get(id)) |known| return known;
        if (self.associated) try self.destination.chargeProjection();
        const node = self.source.node(id);
        const result = switch (node.tag) {
            .bound => if (self.private_namespace != 0) try self.destination.boundType(node.a, node.b) else return error.TypeLimit,
            .rigid => try self.destination.rigid(try self.copyScope(node.a), node.b, node.c),
            .forall, .existential => try self.quantifier(node, depth, id),
            .instance_version => try self.copyVersion(node),
            .instance_selection => blk: {
                var choices: std.ArrayList(T.Id) = .empty;
                defer choices.deinit(self.allocator);
                const original = self.source.nominalArguments(node);
                if (original.len != 2 and original.len != 3) return error.TypeLimit;
                for (original) |choice| try choices.append(self.allocator, try self.copy(choice, depth + 1));
                const owned: T.Id = try self.destination.instanceSelection(if (self.private_namespace == 0) .{ .unit = node.a, .decl = node.b } else try self.copyPhysical(.{ .unit = node.a, .decl = node.b }), choices.items);
                break :blk owned;
            },
            .usage => try self.destination.usage(try self.copy(node.a, depth + 1), @fromBackingInt(@intCast(node.b)), if (node.c == 0) 0 else try self.copy(node.c, depth + 1)),
            .erased_proof => try self.destination.proofKind(),
            .scoped => try self.destination.scoped(try self.copy(node.a, depth + 1), if (node.b == 0) .{ .unit = 0, .decl = try self.copy(node.c, depth + 1) } else try self.copyPhysical(.{ .unit = node.b, .decl = node.c })),
            .absent, .unit, .boolean, .u32, .f32, .never => id,
            .array, .list, .cursor => try self.destination.sequence(node.tag, try self.copy(node.a, depth + 1)),
            .demand => try self.destination.demandWithEffects(try self.copy(node.a, depth + 1), try self.copyRow(node.c, depth + 1)),
            .provider => try self.destination.provider(try self.copy(node.a, depth + 1), try self.copyRow(node.c, depth + 1)),
            .state_provider => try self.destination.stateProvider(try self.copy(node.a, depth + 1), try self.copy(node.b, depth + 1), try self.copy(node.c, depth + 1)),
            .resolver => try self.destination.resolver(try self.copy(node.a, depth + 1)),
            .type_constructor => blk: {
                var identity: Identity = .{ .unit = node.a, .decl = node.b };
                if (self.nominal_mapping) |mapping| identity = mapping.get(identity) orelse return error.TypeLimit;
                break :blk try self.destination.typeConstructor(identity);
            },
            .record => blk: {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..node.b) |i| {
                    const f = self.source.recordField(node, i);
                    var name = f.name;
                    if (self.field_mapping) |mapping| name = mapping[f.name];
                    try fields.append(self.allocator, .{ .name = name, .ty = try self.copy(f.ty, depth + 1) });
                }
                break :blk try self.destination.record(fields.items);
            },
            .nominal, .projection => try self.nominal(node, depth),
            // Every external variable must have been quantified in the
            // producer's principal scheme. No caller solver state is imported.
            .variable => blk: {
                if (!self.fresh_variables) return error.TypeLimit;
                break :blk try self.destination.fresh();
            },
            .function => try self.destination.functionWithEffects(try self.copy(node.a, depth + 1), try self.copy(node.b, depth + 1), try self.copyRow(node.c, depth + 1)),
            .product => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(self.allocator);
                for (self.source.list(.{ .start = node.a, .len = node.b })) |child|
                    try fields.append(self.allocator, try self.copy(child, depth + 1));
                break :blk try self.destination.product(fields.items);
            },
        };
        try self.mapping.put(self.allocator, id, result);
        return result;
    }
};
