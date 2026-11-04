//! Exact entry-value equality, independent of owner identity and runtime bits.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const Local = @import("runtime_code.zig").Local;

/// Encode equality using first-occurrence ordinals, never caller local IDs.
/// An empty partition means every logical input remains independent.
pub fn partition(a: std.mem.Allocator, words: []const Local) std.mem.Allocator.Error![]u32 {
    var positions: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer positions.deinit(a);
    const aliases = try a.alloc(u32, words.len);
    errdefer a.free(aliases);
    var repeated = false;
    for (words, aliases, 0..) |word, *alias, ordinal| {
        const entry = try positions.getOrPut(a, word.id);
        if (!entry.found_existing) entry.value_ptr.* = @intCast(ordinal) else repeated = true;
        alias.* = entry.value_ptr.*;
    }
    if (repeated) return aliases;
    a.free(aliases);
    return &.{};
}

/// Shared entry locals must remain immutable throughout the complete body.
/// Check before publishing any helper, including branches, loops and cleanup.
pub fn readOnly(a: std.mem.Allocator, function: *const ir.Function, first: u32, aliases: []const u32) std.mem.Allocator.Error!bool {
    if (aliases.len == 0) return true;
    for (function.instructions.items) |inst| {
        if (inst.op == .ownership or inst.op == .resource_retire or inst.table_reference or inst.table_kind != .unknown) return false;
    }
    const shared = try a.alloc(bool, aliases.len);
    defer a.free(shared);
    @memset(shared, false);
    for (aliases, 0..) |alias, ordinal| {
        std.debug.assert(alias <= ordinal and aliases[alias] == alias);
        if (alias != ordinal) shared[alias] = true;
    }
    for (function.instructions.items) |inst| {
        if (inst.op != .local_set and inst.op != .local_tee) continue;
        if (inst.operand >= first and inst.operand - first < shared.len and shared[inst.operand - first]) return false;
    }
    return true;
}

fn proof(a: std.mem.Allocator) !void {
    const aliases = try partition(a, &.{ .{ .id = 8 }, .{ .id = 91 }, .{ .id = 8 }, .{ .id = 91 }, .{ .id = 7 } });
    defer a.free(aliases);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 0, 1, 4 }, aliases);
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 5);
    try function.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = 3, .origin = 42 },
        .{ .op = .local_tee, .operand = 2 },
        .{ .op = .local_get, .operand = 4 },
        .{ .op = .local_get, .operand = 5 },
    });
    try std.testing.expect(!try readOnly(a, &function, 1, aliases));
    function.instructions.items[1].operand = 5;
    try std.testing.expect(try readOnly(a, &function, 1, aliases));
    try std.testing.expectEqual(@as(u32, 3), function.instructions.items[0].operand);
    try std.testing.expectEqual(@as(u21, 42), function.instructions.items[0].origin);
    try std.testing.expectEqual(@as(u32, 4), function.instructions.items[2].operand);
    try std.testing.expectEqual(@as(u32, 5), function.instructions.items[3].operand);
}
test "exact input aliases preserve independent writes and logical ordinals through full OOM" {
    try proof(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, proof, .{});
}
test "exact input partitions exclude local numbers and keep independent inputs and hidden operands" {
    const a = std.testing.allocator;
    const left = try partition(a, &.{ .{ .id = 3 }, .{ .id = 3 }, .{ .id = 7 } });
    defer a.free(left);
    const right = try partition(a, &.{ .{ .id = 92 }, .{ .id = 92 }, .{ .id = 0 } });
    defer a.free(right);
    try std.testing.expectEqualSlices(u32, left, right);
    const distinct = try partition(a, &.{ .{ .id = 3 }, .{ .id = 4 } });
    defer a.free(distinct);
    try std.testing.expectEqual(@as(usize, 0), distinct.len);
    var parameters = [_]ir.ValueType{ .i32, .i32, .i32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .i32_const, .table_reference = true }, .{ .op = .i32_const, .table_kind = .callable } }) |inst| {
        function.instructions.clearRetainingCapacity();
        try function.instructions.append(a, inst);
        try std.testing.expect(!try readOnly(failing.allocator(), &function, 0, left));
    }
}
