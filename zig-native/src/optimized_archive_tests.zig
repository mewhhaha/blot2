const std = @import("std");
const wasm = @import("wasm.zig");
const bodies = @import("optimized_bodies.zig");
const archive = @import("optimized_archive.zig");
const compiler: [32]u8 = @splat(17);

fn module(a: std.mem.Allocator) !wasm.Module {
    var result = wasm.Module.init(a);
    errdefer result.deinit();
    for (0..2) |id| {
        _ = try result.addFunction(&.{.i32}, .i32);
        try result.emitSlice(@intCast(id), &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = @intCast(id) }, .{ .op = .i32_add } });
    }
    return result;
}
fn scenario(a: std.mem.Allocator) !void {
    var original = try module(a);
    defer original.deinit();
    const saved = blk: {
        var old: bodies.Capture = .{ .allocator = a };
        defer old.deinit();
        const first = try original.assembleWithOptions(.{ .current = &old });
        errdefer a.free(first);
        break :blk .{ .wasm = first, .archive = try archive.encode(a, compiler, &old) };
    };
    const first = saved.wasm;
    defer a.free(first);
    var loaded = blk: {
        defer a.free(saved.archive);
        break :blk try archive.decode(a, compiler, saved.archive);
    };
    defer loaded.deinit();
    var current: bodies.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: bodies.Stats = .{};
    const reused = try original.assembleWithOptions(.{ .previous = &loaded, .current = &current, .stats = &stats });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, first, reused);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
    original.functions.items[0].instructions.items[1].operand = 99;
    var changed: bodies.Capture = .{ .allocator = a };
    defer changed.deinit();
    stats = .{};
    const edited = try original.assembleWithOptions(.{ .previous = &loaded, .current = &changed, .stats = &stats });
    defer a.free(edited);
    const fresh = try original.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expectEqual(@as(usize, 1), stats.reused);
}
test "portable optimizer captures outlive producers and preserve exact per-body admission through failures" {
    try scenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}
test "portable optimizer captures reject stale compilers corrupt bytes and truncated owners" {
    const a = std.testing.allocator;
    var original = try module(a);
    defer original.deinit();
    var capture: bodies.Capture = .{ .allocator = a };
    defer capture.deinit();
    const wasm_bytes = try original.assembleWithOptions(.{ .current = &capture });
    defer a.free(wasm_bytes);
    const bytes = try archive.encode(a, compiler, &capture);
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(18), bytes));
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes[0 .. bytes.len - 1]));
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes));
}
