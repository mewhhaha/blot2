//! Copy an open type graph between owners, preserving sharing inside one
//! import while freshening every type and row binder. Published templates have
//! no substitution history and are immutable throughout import.
const std = @import("std");
const T = @import("types.zig");

/// True only when every data endpoint is an unconstrained binder and no
/// operation or rigid row is already selected. A callee relationship with any
/// concrete or partially structured endpoint still needs ordinary inference.
pub fn allUnknown(source: *const T.Store, root: T.Id, max_depth: usize) bool {
    var cursor = root;
    for (0..max_depth) |_| {
        const node = source.node(cursor);
        if (node.tag != .function) return node.tag == .variable;
        if (source.node(node.a).tag != .variable) return false;
        const row = source.row(node.c);
        if (row.labels.len != 0 or row.tail == .parameter) return false;
        cursor = node.b;
    }
    return false;
}

pub const Copy = struct {
    allocator: std.mem.Allocator,
    source: *const T.Store,
    destination: *T.Store,
    max_depth: usize,
    max_nodes: usize,
    types: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
    variables: std.AutoHashMapUnmanaged(u32, T.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
    row_variables: std.AutoHashMapUnmanaged(u32, T.Effects.Id) = .empty,
    labels: std.AutoHashMapUnmanaged(T.Effects.Label, T.Effects.Label) = .empty,

    pub fn deinit(self: *Copy) void {
        self.types.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.row_variables.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn ty(self: *Copy, original: T.Id, depth: usize) T.Error!T.Id {
        std.debug.assert(self.source.versions.items.len == 0 and self.source.effects.versions.items.len == 0);
        if (original <= T.never) return original;
        if (depth >= self.max_depth or self.types.count() >= self.max_nodes) return error.TypeLimit;
        if (self.types.get(original)) |known| return known;
        const root = self.source.head(original, 0);
        if (root != original) {
            const result = try self.ty(root, depth + 1);
            try self.types.put(self.allocator, original, result);
            return result;
        }
        const node = self.source.node(root);
        const result = switch (node.tag) {
            .variable => blk: {
                if (self.variables.get(node.a)) |known| break :blk known;
                const fresh = try self.destination.fresh();
                try self.variables.put(self.allocator, node.a, fresh);
                break :blk fresh;
            },
            .function => try self.destination.functionWithEffects(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.row(node.c, depth + 1)),
            .array, .list, .cursor => try self.destination.sequence(node.tag, try self.ty(node.a, depth + 1)),
            .demand => try self.destination.demandWithEffects(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
            .provider => try self.destination.provider(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
            .resolver => try self.destination.resolver(try self.ty(node.a, depth + 1)),
            .state_provider => try self.destination.stateProvider(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.ty(node.c, depth + 1)),
            .type_constructor => try self.destination.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                const fields = try self.allocator.alloc(T.Field, node.b);
                defer self.allocator.free(fields);
                for (fields, 0..) |*field, index| {
                    const old = self.source.recordField(node, index);
                    field.* = .{ .name = old.name, .ty = try self.ty(old.ty, depth + 1) };
                }
                break :blk try self.destination.record(fields);
            },
            .product, .nominal => blk: {
                const children = if (node.tag == .nominal) self.source.nominalArguments(node) else self.source.list(.{ .start = node.a, .len = node.b });
                const copied = try self.allocator.alloc(T.Id, children.len);
                defer self.allocator.free(copied);
                for (children, copied) |child, *value| value.* = try self.ty(child, depth + 1);
                break :blk if (node.tag == .nominal) try self.destination.nominal(.{ .unit = node.a, .decl = node.b }, copied) else try self.destination.product(copied);
            },
            .absent, .unit, .boolean, .u32, .f32, .never => unreachable,
        };
        try self.types.put(self.allocator, original, result);
        return result;
    }

    pub fn rowVariable(self: *Copy, variable: u32) T.Error!T.Effects.Id {
        if (self.row_variables.get(variable)) |known| return known;
        if (self.row_variables.count() >= self.max_nodes) return error.TypeLimit;
        const fresh = try self.destination.freshEffects();
        try self.row_variables.put(self.allocator, variable, fresh);
        return fresh;
    }

    pub fn row(self: *Copy, original: T.Effects.Id, depth: usize) T.Error!T.Effects.Id {
        if (original == 0) return 0;
        if (depth >= self.max_depth or self.rows.count() >= self.max_nodes) return error.TypeLimit;
        if (self.rows.get(original)) |known| return known;
        const root = original;
        const source = self.source.row(root);
        const old_labels = self.source.rowLabels(root);
        const copied = try self.allocator.alloc(T.Effects.Label, old_labels.len);
        defer self.allocator.free(copied);
        for (old_labels, copied) |operation_label, *value| value.* = try self.label(operation_label, depth + 1);
        const tail: T.Effects.Tail = switch (source.tail) {
            .closed => .closed,
            .variable => |variable| self.destination.row(try self.rowVariable(variable)).tail,
            // Rigid row parameters require their source-owner identity. They
            // remain on ordinary collection until that boundary is represented.
            .parameter => return error.TypeLimit,
        };
        const result = self.destination.effects.row(copied, tail) catch |err| return T.effectError(err);
        try self.rows.put(self.allocator, original, result);
        return result;
    }

    fn label(self: *Copy, original: T.Effects.Label, depth: usize) T.Error!T.Effects.Label {
        if (depth >= self.max_depth or self.labels.count() >= self.max_nodes) return error.TypeLimit;
        if (self.labels.get(original)) |known| return known;
        const operation = self.source.operation(original);
        const old = self.source.operationArguments(original);
        const arguments = try self.allocator.alloc(T.Id, old.len);
        defer self.allocator.free(arguments);
        for (old, arguments) |argument, *value| value.* = try self.ty(argument, depth + 1);
        const result = try self.destination.internOperation(operation.identity, arguments);
        try self.labels.put(self.allocator, original, result);
        return result;
    }
};

test "principal type graph imports fresh binders and preserves nested aliases and effect identities" {
    const a = std.testing.allocator;
    var source = try T.Store.init(a);
    defer source.deinit();
    const shared = try source.fresh();
    const row = try source.freshEffects();
    const label = try source.internOperation(.{ .unit = 12, .decl = 9 }, &.{T.f32_type});
    const effect = source.effects.row(&.{label}, source.row(row).tail) catch |err| return T.effectError(err);
    const payload = try source.product(&.{ shared, shared });
    const root = try source.functionWithEffects(payload, shared, effect);
    var template = try T.Store.init(a);
    defer template.deinit();
    var describe: Copy = .{ .allocator = a, .source = &source, .destination = &template, .max_depth = 64, .max_nodes = 1024 };
    defer describe.deinit();
    const principal = try describe.ty(root, 0);
    var caller = try T.Store.init(a);
    defer caller.deinit();
    var first: Copy = .{ .allocator = a, .source = &template, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer first.deinit();
    var second: Copy = .{ .allocator = a, .source = &template, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer second.deinit();
    const integer = caller.node(try first.ty(principal, 0));
    const floating = caller.node(try second.ty(principal, 0));
    const integer_fields = caller.node(integer.a);
    const values = caller.list(.{ .start = integer_fields.a, .len = integer_fields.b });
    try std.testing.expectEqual(integer.b, values[0]);
    try std.testing.expectEqual(integer.b, values[1]);
    try std.testing.expect(integer.b != floating.b);
    try caller.unify(integer.b, T.u32_type);
    try caller.unify(floating.b, T.f32_type);
    try std.testing.expectEqual(T.u32_type, try caller.resolve(integer.b, 0));
    try std.testing.expectEqual(T.f32_type, try caller.resolve(floating.b, 0));
    try std.testing.expect(caller.row(integer.c).tail.variable != caller.row(floating.c).tail.variable);
    try std.testing.expectEqualDeep(caller.rowLabels(integer.c), caller.rowLabels(floating.c));
    try std.testing.expectEqualDeep(T.NominalIdentity{ .unit = 12, .decl = 9 }, caller.operation(caller.rowLabels(integer.c)[0]).identity);
    try std.testing.expectEqual(@as(usize, 0), template.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), template.effects.versions.items.len);
}
