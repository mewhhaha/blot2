//! Copies immutable principal types and rows into the current checker.
//! Relocation maps belong to this transaction, never Source.
const std = @import("std");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const Allocator = std.mem.Allocator;
const Identity = T.NominalIdentity;

pub const Copier = struct {
    allocator: Allocator,
    source: F.Source,
    destination: *T.Store,
    associated: bool = false,
    mapping: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
    row_variables: std.AutoHashMapUnmanaged(u32, T.Effects.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
    labels: std.AutoHashMapUnmanaged(T.Effects.Label, T.Effects.Label) = .empty,
    pub fn deinit(self: *Copier) void {
        self.mapping.deinit(self.allocator);
        self.row_variables.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }
    // A type may already have copied a row. Keep that same fresh identity when
    // restoring its quantifier or covariance certificate.
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
        if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.copy(instance.decl, depth + 1);
        const result = try self.destination.internScopedOperation(operation.identity, instance, args.items);
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
                const replacement = self.destination.effects.node(self.row_variables.get(index) orelse return error.TypeLimit);
                // A row substitution carries its destination operation labels
                // as well as its tail. Copying only the tail erased a closed
                // Foreign substitution into the empty row. These labels are
                // already interned in the destination; do not relocate them.
                for (self.destination.effects.list(replacement.labels)) |label| {
                    if (self.associated) try self.destination.chargeProjection();
                    var present = false;
                    for (labels.items) |existing| {
                        if (self.associated) try self.destination.chargeProjection();
                        if (existing == label) {
                            present = true;
                            break;
                        }
                    }
                    if (!present) try labels.append(self.allocator, label);
                }
                break :blk replacement.tail;
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
        }
        return try self.destination.quantifiedWithGoals(node.tag, body, binders, goals);
    }
    fn nominal(self: *Copier, node: T.Node, depth: usize) T.Error!T.Id {
        var args: std.ArrayList(T.Id) = .empty;
        defer args.deinit(self.allocator);
        for (self.source.nominalArguments(node)) |arg| try args.append(self.allocator, try self.copy(arg, depth + 1));
        const identity: Identity = .{ .unit = node.a, .decl = node.b };
        if (node.tag == .projection) return try self.destination.projection(identity, self.source.projectionMember(node), args.items);
        return try self.destination.nominal(identity, args.items);
    }
    pub fn copy(self: *Copier, source_id: T.Id, depth: usize) T.Error!T.Id {
        self.destination.normalization.import_depth_entries +|= 1;
        const attribution_start = self.destination.nodes.items.len;
        defer if (depth == 0) {
            self.destination.normalization.import_nodes_added +|= @intCast(self.destination.nodes.items.len -| attribution_start);
        };
        if (depth >= 1024) return error.TypeLimit;
        const id = self.source.head(source_id, 0);
        if (self.mapping.get(id)) |known| return known;
        if (self.associated) try self.destination.chargeProjection();
        const node = self.source.node(id);
        const result = switch (node.tag) {
            // Bound leaves are copied through their quantifier's binders; a
            // free bound or rigid leaf has no destination scope.
            .bound, .rigid => return error.TypeLimit,
            .forall, .existential => try self.quantifier(node, depth, id),
            .instance_version => try self.destination.instanceVersion(.{ .unit = node.a, .decl = node.b }, node.c),
            .instance_selection => blk: {
                var choices: std.ArrayList(T.Id) = .empty;
                defer choices.deinit(self.allocator);
                const original = self.source.nominalArguments(node);
                if (original.len != 2 and original.len != 3) return error.TypeLimit;
                for (original) |choice| try choices.append(self.allocator, try self.copy(choice, depth + 1));
                const owned: T.Id = try self.destination.instanceSelection(.{ .unit = node.a, .decl = node.b }, choices.items);
                break :blk owned;
            },
            .usage => try self.destination.usage(try self.copy(node.a, depth + 1), @fromBackingInt(@intCast(node.b)), if (node.c == 0) 0 else try self.copy(node.c, depth + 1)),
            .erased_proof => try self.destination.proofKind(),
            .scoped => if (node.b == 0) try self.destination.scoped(try self.copy(node.a, depth + 1), .{ .unit = 0, .decl = try self.copy(node.c, depth + 1) }) else return error.TypeLimit,
            .absent, .unit, .boolean, .u32, .f32, .never => id,
            .array, .list, .cursor => try self.destination.sequence(node.tag, try self.copy(node.a, depth + 1)),
            .provider => try self.destination.provider(try self.copy(node.a, depth + 1), try self.copyRow(node.c, depth + 1)),
            .state_provider => try self.destination.stateProvider(try self.copy(node.a, depth + 1), try self.copy(node.b, depth + 1), try self.copy(node.c, depth + 1)),
            .resolver => try self.destination.resolver(try self.copy(node.a, depth + 1)),
            .type_constructor => try self.destination.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..node.b) |i| {
                    const f = self.source.recordField(node, i);
                    try fields.append(self.allocator, .{ .name = f.name, .ty = try self.copy(f.ty, depth + 1) });
                }
                break :blk try self.destination.record(fields.items);
            },
            .nominal, .projection => try self.nominal(node, depth),
            // Every external variable must have been quantified in the
            // producer's principal scheme. No caller solver state is imported.
            .variable => return error.TypeLimit,
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
