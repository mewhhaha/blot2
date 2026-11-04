//! Final physical demand for a checked helper's private packed input packet.
const std = @import("std");
const ir = @import("runtime_ir.zig");
pub const Result = struct { used: []bool, omitted: usize };
pub fn materialize(a: std.mem.Allocator, function: *ir.Function, words: usize) std.mem.Allocator.Error!Result {
    std.debug.assert(function.parameters.len == 1 and function.locals.items.len >= words);
    const used = try a.alloc(bool, words);
    errdefer a.free(used);
    @memset(used, false);
    // Include output serialization and cleanup in the final read set.
    for (function.instructions.items) |inst| {
        if (inst.op == .local_get and inst.operand > 0 and inst.operand <= words) used[inst.operand - 1] = true;
    }
    var prefix: std.ArrayList(ir.Instruction) = .empty;
    defer prefix.deinit(a);
    var omitted: usize = 0;
    for (used, 0..) |read, index| {
        if (!read) {
            omitted += 1;
            continue;
        }
        // Read before all callee code, never across scratch allocation/rewind.
        try prefix.appendSlice(a, &.{
            .{ .op = .local_get, .operand = 0 },
            .{ .op = .i32_load, .operand = @intCast(index * 4) },
            .{ .op = .local_set, .operand = @intCast(index + 1) },
        });
    }
    try function.instructions.insertSlice(a, 0, prefix.items);
    return .{ .used = used, .omitted = omitted };
}
test "packed input demand loads only read words before complete unchanged body" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 601);
    try function.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = 1, .origin = 42 },
        .{ .op = .local_get, .operand = 600 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = 601 },
        .{ .op = .local_get, .operand = 601 },
    });
    const result = try materialize(a, &function, 600);
    defer a.free(result.used);
    try std.testing.expectEqual(@as(usize, 598), result.omitted);
    try std.testing.expect(result.used[0] and result.used[599]);
    try std.testing.expectEqual(@as(u32, 0), function.instructions.items[1].operand);
    try std.testing.expectEqual(@as(u32, 2396), function.instructions.items[4].operand);
    try std.testing.expectEqual(@as(u21, 42), function.instructions.items[6].origin);
}
test "packed input demand includes result serialization and keeps full packet result offset" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 600);
    try function.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = 0 },    .{ .op = .local_get, .operand = 600 },
        .{ .op = .i32_store, .operand = 2400 }, .{ .op = .i32_const },
    });
    const result = try materialize(a, &function, 600);
    defer a.free(result.used);
    try std.testing.expectEqual(@as(usize, 599), result.omitted);
    try std.testing.expect(result.used[599]);
    try std.testing.expectEqual(@as(u32, 2400), function.instructions.items[5].operand);
}
fn materializeWithFailures(a: std.mem.Allocator) !void {
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 600);
    try function.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .local_get, .operand = 600 },
        .{ .op = .i32_add },
    });
    const result = try materialize(a, &function, 600);
    defer a.free(result.used);
    try std.testing.expectEqual(@as(usize, 598), result.omitted);
    try std.testing.expectEqual(@as(usize, 9), function.instructions.items.len);
}
test "packed input materialization retains owned buffers through full OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, materializeWithFailures, .{});
}
