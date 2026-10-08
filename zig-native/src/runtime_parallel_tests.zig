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
    try @import("allocation_failures.zig").checkObservedConcurrentFailures(a, failureScenario, .{&module});
}
