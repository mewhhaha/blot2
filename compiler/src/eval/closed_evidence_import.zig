//! Exact closed semantic types enter inference without consulting a layout.
//! The destination owns every copied node, row and operation argument.
const std = @import("std");
const T = @import("../check/types.zig");
const E = @import("type_evidence.zig");
pub const Importer = struct {
    allocator: std.mem.Allocator,
    source: E.View,
    destination: *T.Store,
    types: std.AutoHashMapUnmanaged(E.Id, T.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(E.Effects.Id, T.Effects.Id) = .empty,
    frames: [128][]const T.Id = undefined,
    scope_count: usize = 0,
    pub fn deinit(self: *Importer) void {
        self.types.deinit(self.allocator);
        self.rows.deinit(self.allocator);
    }
    pub fn ty(self: *Importer, id: E.Id, depth: usize) T.Error!T.Id {
        if (id <= 5) return id;
        if (depth >= 256) return error.TypeLimit;
        if (self.scope_count == 0) if (self.types.get(id)) |known| return known;
        try self.destination.chargeProjection();
        const node = self.source.node(id);
        const result: T.Id = switch (node.tag) {
            .scoped => try self.destination.scoped(try self.ty(node.a, depth + 1), .{ .unit = node.b, .decl = node.c }),
            .erased_proof => try self.destination.proofKind(),
            .projection => result: {
                const descriptor = self.source.projection(id);
                if (descriptor.scope >= self.scope_count) return error.TypeMismatch;
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(self.allocator);
                for (self.source.children(id)) |argument| try arguments.append(self.allocator, try self.ty(argument, depth + 1));
                break :result try self.destination.projection(.{ .unit = node.a, .decl = node.b }, descriptor.member, arguments.items);
            },
            .bound => result: {
                if (node.c >= self.scope_count) return error.TypeMismatch;
                const binders = self.frames[self.scope_count - 1 - node.c];
                if (node.a >= binders.len) return error.TypeMismatch;
                const binder = binders[node.a];
                if (self.destination.node(binder).b != node.b) return error.TypeMismatch;
                break :result binder;
            },
            .forall, .existential => result: {
                if (node.b == 0 or node.b > 128 or self.scope_count == self.frames.len) return error.TypeLimit;
                var binders: [128]T.Id = undefined;
                for (self.source.children(id), binders[0..node.b], 0..) |formal, *binder, ordinal| {
                    const leaf = self.source.node(formal);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.TypeMismatch;
                    binder.* = try self.destination.boundType(@intCast(ordinal), leaf.b);
                }
                self.frames[self.scope_count] = binders[0..node.b];
                self.scope_count += 1;
                defer self.scope_count -= 1;
                var tag: T.Tag = .existential;
                if (node.tag == .forall) tag = .forall;
                var goals: std.ArrayList(T.Obligation) = .empty;
                defer goals.deinit(self.allocator);
                for (self.source.quantifierGoals(id)) |goal| {
                    try self.destination.chargeProjection();
                    var value: T.Obligation = .{ .ty = 0, .kind = goal.kind, .source = 0, .name = goal.name, .operator = goal.operator, .identity = goal.identity, .explicit = goal.explicit };
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) @field(value, field) = try self.ty(endpoint, depth + 1);
                    }
                    try goals.append(self.allocator, value);
                }
                break :result try self.destination.quantifiedWithGoals(tag, try self.ty(node.a, depth + 1), binders[0..node.b], goals.items);
            },
            .usage => try self.destination.usage(try self.ty(node.a, depth + 1), @fromBackingInt(@intCast(node.b)), if (node.c == 0) 0 else try self.ty(node.c, depth + 1)),
            .function => try self.destination.functionWithEffects(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.row(node.c, depth + 1)),
            .array, .list, .cursor => try self.destination.sequence(switch (node.tag) {
                .array => .array,
                .list => .list,
                else => .cursor,
            }, try self.ty(node.a, depth + 1)),
            .demand => try self.destination.demandWithEffects(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
            .resolver => try self.destination.resolver(try self.ty(node.a, depth + 1)),
            .provider => try self.destination.provider(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
            .state_provider => try self.destination.stateProvider(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.ty(node.c, depth + 1)),
            .type_constructor => try self.destination.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .product, .nominal => result: {
                var children: std.ArrayList(T.Id) = .empty;
                defer children.deinit(self.allocator);
                for (self.source.children(id)) |child| try children.append(self.allocator, try self.ty(child, depth + 1));
                if (node.tag == .nominal) break :result try self.destination.nominal(.{ .unit = node.a, .decl = node.b }, children.items);
                break :result try self.destination.product(children.items);
            },
            .record => result: {
                var fields: std.ArrayList(T.Field) = .empty;
                defer fields.deinit(self.allocator);
                const children = self.source.children(id);
                var at: usize = 0;
                while (at < children.len) : (at += 2) try fields.append(self.allocator, .{ .name = children[at], .ty = try self.ty(children[at + 1], depth + 1) });
                break :result try self.destination.record(fields.items);
            },
            else => unreachable,
        };
        if (self.scope_count == 0) try self.types.put(self.allocator, id, result);
        // quantified copies the local binders into destination.extra. This
        // scalar type ID contains no reference to the temporary stack slice.
        // zig-analyzer: disable-next-line returning-local-slice
        return result;
    }
    pub fn row(self: *Importer, id: E.Effects.Id, depth: usize) T.Error!T.Effects.Id {
        if (id == 0) return 0;
        if (depth >= 256) return error.TypeLimit;
        if (self.scope_count == 0) if (self.rows.get(id)) |known| return known;
        try self.destination.chargeProjection();
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        for (self.source.effects.rowLabels(id)) |label| {
            try self.destination.chargeProjection();
            const operation = self.source.effects.operation(label);
            var arguments: std.ArrayList(T.Id) = .empty;
            defer arguments.deinit(self.allocator);
            for (self.source.effects.operationArguments(label)) |argument| try arguments.append(self.allocator, try self.ty(argument, depth + 1));
            try labels.append(self.allocator, try self.destination.internScopedOperation(operation.identity, operation.instance, arguments.items));
        }
        var tail: T.Effects.Tail = .closed;
        const formal = self.source.effects.rows[id].formal;
        if (formal != 0) tail = .{ .formal = try self.ty(formal, depth + 1) };
        const result = self.destination.effects.row(labels.items, tail) catch |err| return T.effectError(err);
        if (self.scope_count == 0) try self.rows.put(self.allocator, id, result);
        return result;
    }
};
