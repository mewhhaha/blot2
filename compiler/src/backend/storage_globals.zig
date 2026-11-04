//! Owned initialization evidence for separately named flat application pools.
//! Discovery follows function bodies conservatively and sorts pool dependencies;
//! payload layout/lifetime admission remains independent in the emitter.
const std = @import("std");
const core = @import("../check/core.zig");
const collections = @import("storage_collections.zig");
const Node = struct { unit: u32, id: core.Id };
pub const Limits = struct { nodes_per_module: usize = 100_000 };

fn discover(a: std.mem.Allocator, units: []const core.Module, roots: []const Node, follow_arrays: bool, limits: Limits) ![]core.BindingRef {
    var pending: std.ArrayList(Node) = .empty;
    defer pending.deinit(a);
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(a);
    var globals: std.ArrayList(core.BindingRef) = .empty;
    errdefer globals.deinit(a);
    const remaining = try a.alloc(usize, units.len);
    defer a.free(remaining);
    @memset(remaining, limits.nodes_per_module);
    try pending.appendSlice(a, roots);
    while (pending.pop()) |current| {
        if (current.id == 0) continue;
        if (current.unit == 0 or current.unit > units.len) return error.InvalidGlobal;
        const key = (@as(u64, current.unit) << 32) | current.id;
        if ((try seen.getOrPut(a, key)).found_existing) continue;
        if (remaining[current.unit - 1] == 0) return error.Limit;
        remaining[current.unit - 1] -= 1;
        const m = &units[current.unit - 1];
        if (current.id >= m.nodes.len) return error.InvalidGlobal;
        const n = m.node(current.id);
        for (m.children(current.id)) |child| try pending.append(a, .{ .unit = m.unit, .id = child });
        switch (n.tag) {
            .reference, .call => {
                var target = if (n.tag == .call) m.call(current.id).target else m.reference(current.id);
                if (target.unit == 0) target.unit = m.unit;
                if (target.unit > units.len) return error.InvalidGlobal;
                const owner = &units[target.unit - 1];
                if (target.binding == 0 or target.binding >= owner.bindings.len) return error.InvalidGlobal;
                const binding = owner.binding(target.binding);
                if (binding.kind != .global) continue;
                if (collections.element(owner, binding.ty) != null) {
                    var found = false;
                    for (globals.items) |prior| if (std.meta.eql(prior, target)) {
                        found = true;
                        break;
                    };
                    if (!found) try globals.append(a, target);
                    if (!follow_arrays) continue;
                }
                if (owner.body(target.binding)) |body| try pending.append(a, .{ .unit = owner.unit, .id = body.root });
            },
            .scalar, .associated, .logical, .apply, .record_merge, .proof_guard => {
                try pending.append(a, .{ .unit = m.unit, .id = n.a });
                try pending.append(a, .{ .unit = m.unit, .id = n.b });
            },
            .if_value, .if_stmt => {
                for ([_]core.Id{ n.a, n.b, n.c }) |id| try pending.append(a, .{ .unit = m.unit, .id = id });
            },
            .bind, .construct, .pattern_bind => try pending.append(a, .{ .unit = m.unit, .id = n.b }),
            .update => {
                const info = m.updateInfo(current.id);
                try pending.append(a, .{ .unit = m.unit, .id = info.root });
                for (m.updateSelectors(current.id)) |selector| if (selector.kind == .index) try pending.append(a, .{ .unit = m.unit, .id = selector.index });
                try pending.append(a, .{ .unit = m.unit, .id = info.value });
            },
            .return_, .project, .force, .usage_read, .usage_share => try pending.append(a, .{ .unit = m.unit, .id = n.a }),
            .closure, .suspend_ => try pending.append(a, .{ .unit = m.unit, .id = if (n.tag == .closure) m.closure(current.id).body else m.suspension(current.id).body }),
            .loop => {
                const loop = m.loopInfo(current.id);
                for ([_]core.Id{ loop.first, loop.end, loop.body }) |id| try pending.append(a, .{ .unit = m.unit, .id = id });
            },
            .match => {
                for (m.matchInputs(current.id)) |id| try pending.append(a, .{ .unit = m.unit, .id = id });
                for (m.matchArms(current.id)) |arm| {
                    try pending.append(a, .{ .unit = m.unit, .id = arm.guard });
                    try pending.append(a, .{ .unit = m.unit, .id = arm.body });
                }
            },
            else => {},
        }
    }
    return globals.toOwnedSlice(a);
}

pub const Initializer = struct {
    target: core.BindingRef,
    root: core.Id,
    dependencies: []const core.BindingRef,
};
pub const Plan = struct {
    initializers: []Initializer,
    pub fn deinit(self: *Plan, a: std.mem.Allocator) void {
        for (self.initializers) |item| a.free(item.dependencies);
        a.free(self.initializers);
        self.* = undefined;
    }
};
fn indexOf(bindings: []const core.BindingRef, target: core.BindingRef) ?usize {
    for (bindings, 0..) |binding, index| if (std.meta.eql(binding, target)) return index;
    return null;
}
const Frame = struct { index: usize, next: usize = 0 };

/// Topological order is deterministic for the immutable reached source graph.
/// A cycle is rejected before any Wasm or initializer side effect is published.
pub fn plan(a: std.mem.Allocator, units: []const core.Module, entry: u32) !Plan {
    return planWithLimits(a, units, entry, .{});
}
/// Each immutable source module keeps its own bound. Importing another module
/// cannot consume its neighbor's allowance; repeated visits never renew one.
pub fn planWithLimits(a: std.mem.Allocator, units: []const core.Module, entry: u32, limits: Limits) !Plan {
    if (entry == 0 or entry > units.len) return error.InvalidGlobal;
    var roots: std.ArrayList(Node) = .empty;
    defer roots.deinit(a);
    for (units[entry - 1].bodies) |body| if (body.exported) {
        try roots.append(a, .{ .unit = entry, .id = body.root });
    };
    const bindings = try discover(a, units, roots.items, true, limits);
    defer a.free(bindings);
    const entries = try a.alloc(Initializer, bindings.len);
    defer a.free(entries);
    var initialized: usize = 0;
    defer for (entries[0..initialized]) |item| a.free(item.dependencies);
    for (bindings, entries) |target, *item| {
        const m = &units[target.unit - 1];
        const body = m.body(target.binding) orelse return error.InvalidGlobal;
        item.* = .{
            .target = target,
            .root = body.root,
            .dependencies = try discover(a, units, &.{.{ .unit = target.unit, .id = body.root }}, false, limits),
        };
        initialized += 1;
    }
    const states = try a.alloc(u8, bindings.len);
    defer a.free(states);
    @memset(states, 0);
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(a);
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(a);
    for (bindings, 0..) |_, start| {
        if (states[start] != 0) continue;
        states[start] = 1;
        try stack.append(a, .{ .index = start });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const dependencies = entries[top.index].dependencies;
            if (top.next == dependencies.len) {
                const done = top.index;
                _ = stack.pop();
                states[done] = 2;
                try order.append(a, done);
                continue;
            }
            const next = indexOf(bindings, dependencies[top.next]) orelse return error.InvalidGlobal;
            top.next += 1;
            if (states[next] == 1) return error.InitializationCycle;
            if (states[next] == 2) continue;
            states[next] = 1;
            try stack.append(a, .{ .index = next });
        }
    }
    const ordered = try a.alloc(Initializer, entries.len);
    for (order.items, ordered) |index, *item| item.* = entries[index];
    initialized = 0; // Dependency slices move to the published plan.
    return .{ .initializers = ordered };
}

/// Compatibility view: callers receive the same dependency-first inventory.
pub fn collect(a: std.mem.Allocator, units: []const core.Module, entry: u32) ![]core.BindingRef {
    var evidence = try plan(a, units, entry);
    defer evidence.deinit(a);
    const bindings = try a.alloc(core.BindingRef, evidence.initializers.len);
    for (evidence.initializers, bindings) |item, *binding| binding.* = item.target;
    return bindings;
}
