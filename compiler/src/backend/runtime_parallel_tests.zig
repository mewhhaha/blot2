const std = @import("std");
const wasm = @import("wasm.zig");
const retained = @import("optimized_bodies.zig");

fn workload(a: std.mem.Allocator) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    const arena = try module.ensureArena();
    for (0..32) |index| {
        const id = try module.addFunction(&.{.i32}, .i32);
        const local = try module.addLocal(id, .i32);
        try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = local }, .{ .op = .i32_load } });
        for (0..64) |_| try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = @intCast(index) }, .{ .op = .i32_add } });
    }
    return module;
}

test "coarse optimizer jobs preserve deterministic bytes and keep small edits serial" {
    const a = std.testing.allocator;
    var module = try workload(a);
    defer module.deinit();
    const serial = try module.assemble();
    defer a.free(serial);
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const parallel = try module.assembleWithOptions(.{ .io = std.testing.io, .workers = 4, .current = &old, .stats = &stats });
    defer a.free(parallel);
    try std.testing.expectEqualSlices(u8, serial, parallel);
    try std.testing.expectEqual(module.functions.items.len, stats.parallel_jobs);
    try std.testing.expect(stats.workers > 1);
    try module.emitSlice(@intCast(module.functions.items.len - 1), &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var next: retained.Capture = .{ .allocator = a };
    defer next.deinit();
    stats = .{};
    const edited = try module.assembleWithOptions(.{ .io = std.testing.io, .workers = 4, .previous = &old, .current = &next, .stats = &stats });
    defer a.free(edited);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expectEqual(@as(usize, 1), stats.workers);
    try std.testing.expectEqual(@as(usize, 0), stats.parallel_jobs);
    try std.testing.expect(stats.reused > 0);
}

fn failureScenario(a: std.mem.Allocator, original: *const wasm.Module) !void {
    // Inputs stay borrowed/immutable; only this candidate's scratch uses the
    // failing allocator. Worker allocations still pass through that allocator.
    var module = original.*;
    module.allocator = a;
    var capture: retained.Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .io = std.testing.io, .workers = 2, .current = &capture });
    defer a.free(bytes);
}
test "coarse optimizer jobs join and release outputs across allocation failures" {
    const a = std.testing.allocator;
    var module = try workload(a);
    defer module.deinit();
    try failureScenario(a, &module);
    try @import("../allocation_failures.zig").checkObservedConcurrentFailures(a, failureScenario, .{&module});
}

/// The first twenty functions publish nothing; the rest return an
/// allocation the reference-count plan leaves uncounted.
fn rcWorkload(a: std.mem.Allocator, first_unproven: *u32) !wasm.Module {
    var module = wasm.Module.init(a);
    errdefer module.deinit();
    const arena = try module.ensureArena();
    for (0..32) |index| {
        const id = try module.addFunction(&.{.i32}, .i32);
        if (index < 20) {
            try module.emit(id, .{ .op = .local_get });
        } else {
            if (index == 20) first_unproven.* = id;
            const local = try module.addLocal(id, .i32);
            try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = local } });
        }
        for (0..64) |_| try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = @intCast(index) }, .{ .op = .i32_add } });
    }
    return module;
}

test "parallel reference-count plans reject at the serial first unproven function" {
    const a = std.testing.allocator;
    var first: u32 = 0;
    var module = try rcWorkload(a, &first);
    defer module.deinit();
    var serial: wasm.OwnershipFailure = .{};
    try std.testing.expectError(error.IncompleteOwnership, module.assembleCheckedWithOptions(.{ .rejection = &serial }));
    try std.testing.expectEqual(wasm.OwnershipFallback.unproven_body, serial.fallback);
    try std.testing.expectEqual(@as(?u32, first), serial.function);
    for ([_]u8{ 2, 4 }) |workers| {
        var parallel: wasm.OwnershipFailure = .{};
        var stats: retained.Stats = .{};
        try std.testing.expectError(error.IncompleteOwnership, module.assembleCheckedWithOptions(.{ .rejection = &parallel, .io = std.testing.io, .workers = workers, .stats = &stats }));
        try std.testing.expect(stats.workers > 1);
        try std.testing.expectEqual(serial, parallel);
    }
}
