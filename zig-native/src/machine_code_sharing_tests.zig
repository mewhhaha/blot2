const std = @import("std");
const wasm = @import("wasm.zig");
const sharing = @import("machine_code_sharing.zig");
const retained = @import("optimized_bodies.zig");

test "machine body sharing preserves exported identities and exact immediates signatures and calls" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    const public = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second, public }) |id| try module.emit(id, .{ .op = .local_get });
    try module.exportFunction(public, "public", .u32, .u32);
    const positive = try module.addFunction(&.{}, .f32);
    const negative = try module.addFunction(&.{}, .f32);
    try module.emit(positive, .{ .op = .f32_const, .operand = 0 });
    try module.emit(negative, .{ .op = .f32_const, .operand = 0x80000000 });
    const caller1 = try module.addFunction(&.{.i32}, .i32);
    const caller2 = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(caller1, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = first } });
    try module.emitSlice(caller2, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = second } });
    var index = try sharing.Index.init(a, &module, true);
    defer index.deinit();
    try std.testing.expectEqual(@as(usize, 6), index.unique);
    try std.testing.expectEqual(index.function(first), index.function(second));
    try std.testing.expect(index.function(public) != index.function(first));
    try std.testing.expect(index.function(positive) != index.function(negative));
    // No normalization guesses across distinct call identities.
    try std.testing.expect(index.function(caller1) != index.function(caller2));
    try std.testing.expect(index.emits(first) and !index.emits(second));
}

fn sharingScenario(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second }) |id| {
        const local = try module.addLocal(id, .i32);
        try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = local }, .{ .op = .i32_load } });
    }
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try module.assembleWithOptions(.{ .share_machine_code = true, .current = &old, .stats = &stats });
    defer a.free(before);
    try std.testing.expect(stats.shared >= 1);
    try std.testing.expect(old.output(first) != null);
    try std.testing.expect(old.output(second) == null);
    try module.emitSlice(first, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var changed: retained.Capture = .{ .allocator = a };
    defer changed.deinit();
    stats = .{};
    const after = try module.assembleWithOptions(.{ .share_machine_code = true, .previous = &old, .current = &changed, .stats = &stats });
    defer a.free(after);
    // The old duplicate never had an optimized output. Its new independent
    // body must run cleanup analysis even though its source is unchanged.
    try std.testing.expect(changed.output(second) != null);
    const fresh = try module.assembleWithOptions(.{ .share_machine_code = true });
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, after);
    try std.testing.expectEqual(module.functions.items.len, stats.shared + stats.reused + stats.optimized);
}

test "machine body sharing rebuilds separated retained bodies and releases failed allocations" {
    try sharingScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharingScenario, .{});
}
