//! Logical type equations normalize owned semantic graphs without selecting
//! an implementation or binding a hidden input from a wanted result.
const std = @import("std");
const T = @import("../check/types.zig");
pub const Equation = struct { left: T.Id, right: T.Id };
const Memo = struct {
    types: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
    rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.types.deinit(allocator);
        self.rows.deinit(allocator);
    }
};
pub const Rewrite = struct {
    store: *T.Store,
    equations: []const Equation,
    pub fn normalize(self: *@This(), root: T.Id) T.Error!T.Id {
        if (self.equations.len == 0) return self.store.resolve(root, 0);
        var memo: Memo = .{};
        defer memo.deinit(self.store.allocator);
        return self.ty(root, &memo, 0);
    }
    fn rank(self: *Rewrite, id: T.Id) u8 {
        return switch (self.store.node(id).tag) {
            .projection => 2,
            .variable => 1,
            else => 0,
        };
    }
    fn ty(self: *Rewrite, root: T.Id, memo: *Memo, depth: usize) T.Error!T.Id {
        if (memo.types.get(root)) |known| return known;
        if (depth >= 256) return error.TypeLimit;
        try self.store.chargeProjection();
        const original = try self.store.resolve(root, 0);
        try memo.types.put(self.store.allocator, root, original);
        var equations: std.ArrayList(Equation) = .empty;
        defer equations.deinit(self.store.allocator);
        for (self.equations) |equation| {
            try self.store.chargeProjection();
            const left = try self.node(try self.store.resolve(equation.left, 0), memo, depth + 1);
            const right = try self.node(try self.store.resolve(equation.right, 0), memo, depth + 1);
            try equations.append(self.store.allocator, .{ .left = left, .right = right });
        }
        var equivalent: std.ArrayList(T.Id) = .empty;
        defer equivalent.deinit(self.store.allocator);
        try equivalent.append(self.store.allocator, original);
        var index: usize = 0;
        var id = original;
        while (index < equivalent.items.len) : (index += 1) {
            const item = equivalent.items[index];
            for (equations.items) |equation| {
                try self.store.chargeProjection();
                var next: T.Id = undefined;
                if (try self.store.equalSymbolic(item, equation.left)) {
                    next = equation.right;
                } else if (try self.store.equalSymbolic(item, equation.right)) {
                    next = equation.left;
                } else continue;
                var seen = false;
                for (equivalent.items) |known| {
                    if (try self.store.equalSymbolic(known, next)) seen = true;
                }
                if (seen) continue;
                try equivalent.append(self.store.allocator, next);
                if (self.rank(next) < self.rank(id) or (self.rank(next) == self.rank(id) and next < id)) id = next;
            }
        }
        // The provisional entry breaks impossible recursive given equations.
        // Concrete use still has to discharge every original equation.
        try memo.types.put(self.store.allocator, root, id);
        var result = try self.node(id, memo, depth);
        if (result != id) result = try self.ty(result, memo, depth + 1);
        try memo.types.put(self.store.allocator, root, result);
        return result;
    }
    fn node(self: *Rewrite, id: T.Id, memo: *Memo, depth: usize) T.Error!T.Id {
        const n = self.store.node(id);
        switch (n.tag) {
            .scoped => {
                const descriptor = try self.ty(n.a, memo, depth + 1);
                const identity = if (n.b == 0) try self.ty(n.c, memo, depth + 1) else n.c;
                if (descriptor == n.a and identity == n.c) return id;
                return self.store.scoped(descriptor, .{ .unit = n.b, .decl = identity });
            },
            .function => {
                const a = try self.ty(n.a, memo, depth + 1);
                const b = try self.ty(n.b, memo, depth + 1);
                const row = try self.effectRow(n.c, memo, depth + 1);
                if (a == n.a and b == n.b and row == n.c) return id;
                return self.store.functionWithEffects(a, b, row);
            },
            .array, .list, .cursor, .resolver, .demand, .provider => {
                const a = try self.ty(n.a, memo, depth + 1);
                var row = n.c;
                if (n.tag == .demand or n.tag == .provider) row = try self.effectRow(n.c, memo, depth + 1);
                if (a == n.a and row == n.c) return id;
                return switch (n.tag) {
                    .resolver => self.store.resolver(a),
                    .demand => self.store.demandWithEffects(a, row),
                    .provider => self.store.provider(a, row),
                    else => self.store.sequence(n.tag, a),
                };
            },
            .product, .nominal, .projection => {
                var children: []const T.Id = undefined;
                if (n.tag == .nominal or n.tag == .projection) {
                    children = self.store.nominalArguments(n);
                } else children = self.store.list(.{ .start = n.a, .len = n.b });
                const old = try self.store.allocator.dupe(T.Id, children);
                defer self.store.allocator.free(old);
                var parts: std.ArrayList(T.Id) = .empty;
                defer parts.deinit(self.store.allocator);
                var changed = false;
                for (old) |child| {
                    const next = try self.ty(child, memo, depth + 1);
                    changed = changed or next != child;
                    try parts.append(self.store.allocator, next);
                }
                if (!changed) return id;
                if (n.tag == .projection) return self.store.projection(.{ .unit = n.a, .decl = n.b }, self.store.projectionMember(n), parts.items);
                if (n.tag == .nominal) return self.store.nominal(.{ .unit = n.a, .decl = n.b }, parts.items);
                return self.store.product(parts.items);
            },
            .record => {
                var parts: std.ArrayList(T.Field) = .empty;
                defer parts.deinit(self.store.allocator);
                var changed = false;
                for (0..n.b) |at| {
                    const field = self.store.recordField(n, at);
                    const next = try self.ty(field.ty, memo, depth + 1);
                    changed = changed or next != field.ty;
                    try parts.append(self.store.allocator, .{ .name = field.name, .ty = next });
                }
                if (!changed) return id;
                return self.store.record(parts.items);
            },
            .state_provider => {
                const a = try self.ty(n.a, memo, depth + 1);
                const b = try self.ty(n.b, memo, depth + 1);
                const c = try self.ty(n.c, memo, depth + 1);
                if (a == n.a and b == n.b and c == n.c) return id;
                return self.store.stateProvider(a, b, c);
            },
            else => return id,
        }
    }
    fn effectRow(self: *Rewrite, root: T.Effects.Id, memo: *Memo, depth: usize) T.Error!T.Effects.Id {
        if (memo.rows.get(root)) |known| return known;
        if (depth >= 256) return error.TypeLimit;
        const id = try self.store.resolveEffects(root, 0);
        const row = self.store.row(id);
        const labels = try self.store.allocator.dupe(T.Effects.Label, self.store.rowLabels(id));
        defer self.store.allocator.free(labels);
        var changed = false;
        for (labels) |*label| {
            try self.store.chargeProjection();
            const operation = self.store.operation(label.*);
            const arguments = try self.store.allocator.dupe(T.Id, self.store.operationArguments(label.*));
            defer self.store.allocator.free(arguments);
            for (arguments) |*argument| argument.* = try self.ty(argument.*, memo, depth + 1);
            var instance = operation.instance;
            if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.ty(instance.decl, memo, depth + 1);
            const next = try self.store.internScopedOperation(operation.identity, instance, arguments);
            changed = changed or next != label.*;
            label.* = next;
        }
        var result = id;
        if (changed) result = self.store.effects.rowAt(labels, row.tail, row.cursor) catch |err| return T.effectError(err);
        try memo.rows.put(self.store.allocator, root, result);
        return result;
    }
};
