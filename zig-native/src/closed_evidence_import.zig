//! Exact closed semantic types enter inference without consulting a layout.
//! The destination owns every copied node, row and operation argument.
const std = @import("std");
const T = @import("types.zig");
const E = @import("type_evidence.zig");
pub const Importer = struct {
    allocator: std.mem.Allocator,
    source: E.View,
    destination: *T.Store,
    types: std.AutoHashMapUnmanaged(E.Id, T.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(E.Effects.Id, T.Effects.Id) = .empty,
    pub fn deinit(self: *Importer) void {
        self.types.deinit(self.allocator);
        self.rows.deinit(self.allocator);
    }
    pub fn ty(self: *Importer, id: E.Id, depth: usize) T.Error!T.Id {
        if (id <= 5) return id;
        if (depth >= 256) return error.TypeLimit;
        if (self.types.get(id)) |known| return known;
        try self.destination.chargeProjection();
        const node = self.source.node(id);
        const result = switch (node.tag) {
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
        try self.types.put(self.allocator, id, result);
        return result;
    }
    pub fn row(self: *Importer, id: E.Effects.Id, depth: usize) T.Error!T.Effects.Id {
        if (id == 0) return 0;
        if (depth >= 256) return error.TypeLimit;
        if (self.rows.get(id)) |known| return known;
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
        const result = self.destination.effects.row(labels.items, .closed) catch |err| return T.effectError(err);
        try self.rows.put(self.allocator, id, result);
        return result;
    }
};
