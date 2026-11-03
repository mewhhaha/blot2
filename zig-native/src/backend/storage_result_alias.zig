//! Completed helper results may forward an unchanged logical input word.
//! Recipes contain input ordinals, never child locals or owner identities.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const Local = @import("runtime_code.zig").Local;
pub const absent = std.math.maxInt(u32);

pub fn analyze(a: std.mem.Allocator, function: *const ir.Function, first: u32, words: usize, output: []const Local) std.mem.Allocator.Error![]u32 {
    const end = std.math.add(usize, first, words) catch return &.{};
    const locals = std.math.add(usize, function.parameters.len, function.locals.items.len) catch return &.{};
    if (end > std.math.maxInt(u32) or end > locals) return &.{};
    var candidate = false;
    for (output) |word| if (word.id >= first and word.id < end) {
        candidate = true;
        break;
    };
    if (!candidate) return &.{};
    for (function.instructions.items) |inst| if (inst.op == .ownership or inst.op == .resource_retire) return &.{};
    const written = try a.alloc(bool, words);
    defer a.free(written);
    @memset(written, false);
    for (function.instructions.items) |inst| {
        if ((inst.op == .local_set or inst.op == .local_tee) and inst.operand >= first and inst.operand < end) written[inst.operand - first] = true;
    }
    var count: usize = 0;
    for (output) |word| if (word.id >= first and word.id < end and !written[word.id - first]) {
        count += 1;
    };
    if (count == 0) return &.{};
    const result = try a.alloc(u32, output.len);
    for (result, output) |*alias, word| {
        alias.* = absent;
        if (word.id >= first and word.id < end and !written[word.id - first]) alias.* = word.id - first;
    }
    return result;
}

fn forwarding(a: std.mem.Allocator) !void {
    var parameters = [_]ir.ValueType{ .i32, .i32, .i32 };
    var source: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer source.deinit(a);
    try source.instructions.appendSlice(a, &.{ .{ .op = .i32_const }, .{ .op = .local_set, .operand = 1 }, .{ .op = .local_get, .operand = 0 } });
    const aliases = try analyze(a, &source, 0, 3, &.{ .{ .id = 2 }, .{ .id = 1 }, .{ .id = 0 }, .{ .id = 4 } });
    defer a.free(aliases);
    try std.testing.expectEqualSlices(u32, &.{ 2, absent, 0, absent }, aliases);
    try std.testing.expectEqual(@as(usize, 3), source.instructions.items.len);
}
test "result aliases retain only unchanged formal words through full OOM" {
    try forwarding(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, forwarding, .{});
}
test "result aliases preserve packed ordinals and reject writes hidden operands and empty candidates" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var source: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer source.deinit(a);
    try source.locals.appendNTimes(a, .i32, 600);
    const aliases = try analyze(a, &source, 1, 600, &.{ .{ .id = 1 }, .{ .id = 600 }, .{ .id = 0 } });
    defer a.free(aliases);
    try std.testing.expectEqualSlices(u32, &.{ 0, 599, absent }, aliases);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(usize, 0), (try analyze(failing.allocator(), &source, 1, 600, &.{.{ .id = 0 }})).len);
    for ([_]ir.Op{ .ownership, .resource_retire }) |op| {
        source.instructions.clearRetainingCapacity();
        try source.instructions.append(a, .{ .op = op });
        try std.testing.expectEqual(@as(usize, 0), (try analyze(failing.allocator(), &source, 1, 600, &.{.{ .id = 1 }})).len);
    }
    source.instructions.clearRetainingCapacity();
    try source.instructions.appendSlice(a, &.{ .{ .op = .i32_const }, .{ .op = .local_tee, .operand = 600 }, .{ .op = .drop } });
    const changed = try analyze(a, &source, 1, 600, &.{.{ .id = 600 }});
    defer a.free(changed);
    try std.testing.expectEqual(@as(usize, 0), changed.len);
}
