const std = @import("std");
const types = @import("types.zig");
const capacity = @import("solver_capacity.zig");
const memory = @import("memory.zig");

fn history(store: *types.Store, first: types.Id, later: types.Id) !void {
    const child = try store.fresh();
    const root = try store.fresh();
    const row = try store.freshEffects();
    const variable = store.effects.node(row).tail.variable;
    try store.appendVersion(child, first);
    try store.effects.appendVersion(variable, try store.effects.row(&.{11}, .closed));
    try store.appendVersion(root, try store.functionWithEffects(try store.array(child), child, row));
    try store.appendVersion(child, later);
    try store.effects.appendVersion(variable, try store.effects.row(&.{22}, .closed));
    const resolved = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(later, store.node(resolved.a).a);
    try std.testing.expectEqual(later, resolved.b);
    try std.testing.expectEqualSlices(u32, &.{22}, store.rowLabels(resolved.c));
    try std.testing.expectEqual(first, try store.resolve(child, 0));
    try std.testing.expectEqual(later, try store.resolve(child, 1));
    try std.testing.expectEqual(later, try store.resolve(child, 3));
    const point = store.mark();
    const recycled = try store.fresh();
    try store.appendVersion(recycled, types.boolean);
    _ = try store.resolve(try store.array(recycled), 0);
    store.rollback(point);
    const replacement = try store.fresh();
    try std.testing.expectEqual(recycled, replacement);
    try store.appendVersion(replacement, types.unit);
    try std.testing.expectEqual(types.unit, try store.resolve(replacement, 0));
}

fn reuseScenario(backing: std.mem.Allocator) !void {
    var tracked: memory.TrackedAllocator = .{ .backing = backing };
    const a = tracked.allocator();
    var pool = capacity.Pool.init(a);
    var pool_alive = true;
    defer if (pool_alive) pool.deinit();
    var prior_nodes: ?[*]types.Node = null;
    for (0..3) |round| {
        var lease = try pool.take(a);
        var alive = true;
        defer if (alive) lease.solver.deinit();
        if (prior_nodes) |pointer| try std.testing.expect(lease.solver.nodes.items.ptr == pointer);
        try std.testing.expectEqualDeep(lease.initial, lease.solver.mark());
        try std.testing.expectEqual(@as(u32, 0), lease.solver.variable_views.count());
        try std.testing.expectEqual(@as(usize, 0), lease.solver.resolved.count);
        try std.testing.expectEqual(@as(usize, 0), lease.solver.resolved.high_water);
        try history(&lease.solver, if (round % 2 == 0) types.u32_type else types.boolean, if (round % 2 == 0) types.f32_type else types.unit);
        prior_nodes = lease.solver.nodes.items.ptr;
        const bound = capacity.storageBound(&lease.solver).?;
        try std.testing.expect(tracked.counts.live_bytes <= bound and bound <= capacity.limit);
        pool.give(lease);
        alive = false;
        try std.testing.expect(pool.slot != null);
        try std.testing.expect(tracked.counts.live_bytes <= capacity.storageBound(&pool.slot.?.solver).?);
    }
    pool.deinit();
    pool_alive = false;
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}
test "solver capacity resets chronological type and effect histories recycled IDs and cache admission through OOM" {
    try reuseScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, reuseScenario, .{});
}

test "solver capacity accounts every backing buffer and rejects overcap or overflow without changing solver limits" {
    var tracked: memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var pool = capacity.Pool.init(a);
    defer pool.deinit();
    var lease = try pool.take(a);
    var alive = true;
    defer if (alive) lease.solver.deinit();
    try history(&lease.solver, types.u32_type, types.f32_type);
    try lease.solver.nodes.ensureTotalCapacity(a, 77);
    try lease.solver.extra.ensureTotalCapacity(a, 93);
    try lease.solver.variables.ensureTotalCapacity(a, 43);
    try lease.solver.versions.ensureTotalCapacity(a, 45);
    try lease.solver.operations.ensureTotalCapacity(a, 29);
    try lease.solver.effects.rows.ensureTotalCapacity(a, 49);
    try lease.solver.effects.labels.ensureTotalCapacity(a, 31);
    try lease.solver.effects.variables.ensureTotalCapacity(a, 27);
    try lease.solver.effects.versions.ensureTotalCapacity(a, 39);
    try std.testing.expect(tracked.counts.live_bytes <= capacity.storageBound(&lease.solver).?);
    const original_capacity = lease.solver.extra.capacity;
    lease.solver.extra.capacity = std.math.maxInt(usize);
    const overflow = capacity.storageBound(&lease.solver);
    lease.solver.extra.capacity = original_capacity;
    try std.testing.expect(overflow == null);
    try lease.solver.extra.ensureTotalCapacity(a, capacity.limit / @sizeOf(types.Id) + 1);
    try std.testing.expect(capacity.storageBound(&lease.solver).? > capacity.limit);
    pool.give(lease);
    alive = false;
    try std.testing.expect(pool.slot == null);
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "solver capacity refuses changed modes and exhausted certificate mutation physical and lookup generations" {
    var tracked: memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var pool = capacity.Pool.init(a);
    defer pool.deinit();
    for (0..9) |kind| {
        var lease = try pool.take(a);
        switch (kind) {
            0 => lease.solver.closed_generation = std.math.maxInt(u16),
            1 => lease.solver.mutation_epoch = std.math.maxInt(u32),
            2 => lease.solver.effects.mutation_epoch = std.math.maxInt(u32),
            3 => lease.solver.effects.physical_epoch = std.math.maxInt(u64),
            4 => lease.solver.resolved.generation = std.math.maxInt(u32),
            5 => lease.solver.effects.resolved.generation = std.math.maxInt(u32),
            6 => lease.solver.use_closed_graphs = false,
            7 => lease.solver.use_resolution_cache = false,
            8 => lease.solver.effects.use_resolution_cache = false,
            else => unreachable,
        }
        pool.give(lease);
        try std.testing.expect(pool.slot == null);
        try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
    }
}

test "solver capacity has one movable slot and cannot share active or nested stores" {
    var tracked: memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var pool = capacity.Pool.init(a);
    var pool_alive = true;
    defer if (pool_alive) pool.deinit();
    var outer = try pool.take(a);
    var outer_alive = true;
    defer if (outer_alive) outer.solver.deinit();
    const outer_root = try outer.solver.fresh();
    try outer.solver.appendVersion(outer_root, types.u32_type);
    var inner = try pool.take(a);
    var inner_alive = true;
    defer if (inner_alive) inner.solver.deinit();
    try std.testing.expect(inner.solver.nodes.items.ptr != outer.solver.nodes.items.ptr);
    const inner_nodes = inner.solver.nodes.items.ptr;
    pool.give(inner);
    inner_alive = false;
    try std.testing.expectEqual(types.u32_type, try outer.solver.resolve(outer_root, 0));
    pool.give(outer);
    outer_alive = false;
    try std.testing.expect(pool.slot.?.solver.nodes.items.ptr == inner_nodes);
    var moved = pool;
    pool.slot = null;
    pool.deinit();
    pool_alive = false;
    moved.deinit();
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "solver capacity anchors durable allocator identity and never retains a temporary wrapper" {
    var tracked: memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var pool = capacity.Pool.init(a);
    defer pool.deinit();
    pool.give(try pool.take(a));
    const retained_nodes = pool.slot.?.solver.nodes.items.ptr;
    const before = tracked.counts.live_bytes;
    var wrapper = std.testing.FailingAllocator.init(a, .{});
    var temporary = try pool.take(wrapper.allocator());
    try std.testing.expect(temporary.solver.nodes.items.ptr != retained_nodes);
    pool.give(temporary);
    try std.testing.expect(pool.slot.?.solver.nodes.items.ptr == retained_nodes);
    try std.testing.expectEqual(before, tracked.counts.live_bytes);
    var empty = capacity.Pool.init(a);
    defer empty.deinit();
    temporary = try empty.take(wrapper.allocator());
    empty.give(temporary);
    try std.testing.expect(empty.slot == null);
    try std.testing.expectEqual(before, tracked.counts.live_bytes);
}
