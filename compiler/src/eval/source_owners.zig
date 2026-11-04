//! Immutable source containment for principal read observations. This index
//! grants no equality or executable authority: replay still checks the exact
//! containing declaration, catalogs and all dynamic inputs.
const std = @import("std");
const core = @import("../check/core.zig");
const recipe = @import("body_recipe.zig");
const A = std.mem.Allocator;
const ambiguous = std.math.maxInt(u32);

const Index = struct {
    nodes: []u32 = &.{},
    bindings: []u32 = &.{},
    complete: bool = false,
    fn deinit(self: *Index, a: A) void {
        a.free(self.nodes);
        a.free(self.bindings);
    }
    fn record(slots: []u32, id: u32, owner: u32) void {
        if (id == 0 or id >= slots.len) return;
        if (slots[id] == 0) slots[id] = owner else if (slots[id] != owner) slots[id] = ambiguous;
    }
    fn result(self: *const Index, slots: []const u32, id: u32) ?u32 {
        if (!self.complete or id == 0 or id >= slots.len or slots[id] == 0 or slots[id] == ambiguous) return null;
        return slots[id];
    }
    fn build(a: A, module: *const core.Module, limit: usize) A.Error!Index {
        if (module.nodes.len > limit or module.bindings.len > limit) return .{};
        var result_: Index = .{};
        errdefer result_.deinit(a);
        result_.nodes = try a.alloc(u32, module.nodes.len);
        @memset(result_.nodes, 0);
        result_.bindings = try a.alloc(u32, module.bindings.len);
        @memset(result_.bindings, 0);
        const seen = try a.alloc(u32, module.nodes.len);
        defer a.free(seen);
        @memset(seen, 0);
        var work: recipe.Pending = .{ .limit = limit };
        defer work.items.deinit(a);
        var remaining = limit;
        for (module.bodies) |*body| {
            if (body.binding == 0 or body.binding >= module.bindings.len or module.bindings[body.binding].kind != .global) continue;
            if (work.items.items.len == limit) return result_;
            try work.items.append(a, body.root);
            Index.record(result_.bindings, body.binding, body.binding);
            for (module.bodyParameters(body)) |parameter| Index.record(result_.bindings, parameter.binding, body.binding);
            while (work.pop()) |id| {
                if (id == 0) continue;
                if (id >= module.nodes.len or remaining == 0) return result_;
                if (seen[id] == body.binding) continue;
                seen[id] = body.binding;
                remaining -= 1;
                Index.record(result_.nodes, id, body.binding);
                const node = module.node(id);
                if (node.tag == .closure or node.tag == .suspend_) {
                    const closure = if (node.tag == .closure) module.closure(id) else module.suspension(id);
                    Index.record(result_.bindings, closure.parameter.binding, body.binding);
                    work.append(a, closure.body) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.PlanLimit => return result_,
                    };
                }
                if (node.tag == .bind) Index.record(result_.bindings, node.a, body.binding);
                recipe.appendChildren(&work, a, module, id, false) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.PlanLimit => return result_,
                };
            }
        }
        for (module.bindings, 0..) |binding, id| {
            if (binding.kind != .local or binding.initializer == 0 or binding.initializer >= result_.nodes.len) continue;
            const owner = result_.nodes[binding.initializer];
            if (owner != 0) Index.record(result_.bindings, @intCast(id), owner);
        }
        result_.complete = true;
        return result_;
    }
};

pub const Cache = struct {
    units: std.AutoHashMapUnmanaged(usize, Index) = .empty,
    pub fn deinit(self: *Cache, a: A) void {
        var values = self.units.valueIterator();
        while (values.next()) |value| value.deinit(a);
        self.units.deinit(a);
    }
    fn index(self: *Cache, a: A, units: []const core.Module, owner: usize, limit: usize) A.Error!?*const Index {
        if (owner >= units.len) return null;
        if (self.units.getPtr(owner)) |known| return known;
        var created = try Index.build(a, &units[owner], limit);
        errdefer created.deinit(a);
        try self.units.put(a, owner, created);
        return self.units.getPtr(owner).?;
    }
    pub fn binding(self: *Cache, a: A, units: []const core.Module, owner: usize, id: u32, limit: usize) A.Error!?u32 {
        const view = (try self.index(a, units, owner, limit)) orelse return null;
        return view.result(view.bindings, id);
    }
    pub fn node(self: *Cache, a: A, units: []const core.Module, owner: usize, id: u32, limit: usize) A.Error!?u32 {
        const view = (try self.index(a, units, owner, limit)) orelse return null;
        return view.result(view.nodes, id);
    }
};
