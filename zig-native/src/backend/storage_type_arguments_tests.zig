const std = @import("std");
const Stack = @import("storage_type_arguments.zig").Stack;
const a = std.testing.allocator;
const Argument = struct { unit: u32, parameter: u32, argument: u32, argument_unit: u32, environment: ?[]const u32 = null };

fn original(arguments: []const Argument, unit: u32, parameter: u32, nonidentity: bool) ?usize {
    var at = arguments.len;
    while (at != 0) {
        at -= 1;
        const item = arguments[at];
        if (item.unit != unit or item.parameter != parameter) continue;
        if (nonidentity and item.argument_unit == unit and item.argument == parameter) continue;
        return at;
    }
    return null;
}
fn verify(stack: *Stack(Argument)) !void {
    for (1..5) |unit| for (0..8) |parameter| {
        try std.testing.expectEqual(original(stack.items, @intCast(unit), @intCast(parameter), false), stack.latestAny(@intCast(unit), @intCast(parameter)));
        try std.testing.expectEqual(original(stack.items, @intCast(unit), @intCast(parameter), true), stack.latestNonidentity(@intCast(unit), @intCast(parameter)));
    };
}
fn rollbackLaw(allocator: std.mem.Allocator) !void {
    var stack: Stack(Argument) = .empty;
    defer stack.deinit(allocator);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const environment = [_]u32{ 91, 92 };
    const other_environment = [_]u32{ 91, 92 };
    for (0..96) |ordinal| {
        const unit: u32 = @intCast(ordinal % 3 + 1);
        const parameter: u32 = @intCast(ordinal % 7);
        try stack.append(allocator, .{ .unit = unit, .parameter = parameter, .argument = @intCast(ordinal + 20), .argument_unit = 4, .environment = &environment });
        try stack.append(allocator, .{ .unit = unit, .parameter = parameter, .argument = parameter, .argument_unit = unit, .environment = &other_environment });
        try verify(&stack);
    }
    const snapshot = try stack.capture(arena.allocator());
    const again = try stack.capture(arena.allocator());
    try std.testing.expectEqual(snapshot.ptr, again.ptr);
    try std.testing.expectEqual(@as(u64, 1), stack.stats.captures);
    for (snapshot) |item| try std.testing.expectEqual(other_environment[0..].ptr, item.environment.?.ptr);
    // Latest entries retain source order, even when earlier entries are shadowed.
    var expected: usize = 0;
    for (stack.items, 0..) |item, index| {
        if (original(stack.items, item.unit, item.parameter, false) != index) continue;
        try std.testing.expect(std.meta.eql(item, snapshot[expected]));
        expected += 1;
    }
    try std.testing.expectEqual(snapshot.len, expected);
    stack.shrinkRetainingCapacity(2);
    try verify(&stack);
    const shortened = try stack.capture(arena.allocator());
    try std.testing.expectEqual(@as(usize, 1), shortened.len);
    try std.testing.expectEqual(@as(u32, 0), shortened[0].argument);
    stack.shrinkRetainingCapacity(1);
    try stack.append(allocator, .{ .unit = 1, .parameter = 0, .argument = 77, .argument_unit = 4, .environment = &environment });
    try verify(&stack);
    const replaced = try stack.capture(arena.allocator());
    try std.testing.expectEqual(@as(u32, 77), replaced[0].argument);
    try std.testing.expectEqual(@as(u32, 0), shortened[0].argument);
    // Shrink/reappend returned to the same length and buffer, but cannot reuse
    // the old snapshot or the popped nonidentity position.
    try std.testing.expect(replaced.ptr != shortened.ptr);
    var child: Stack(Argument) = .empty;
    defer child.deinit(allocator);
    try child.appendSlice(allocator, stack.items);
    try verify(&child);
    const inherited = try child.capture(arena.allocator());
    try std.testing.expectEqual(replaced.len, inherited.len);
    for (replaced, inherited) |left, right| try std.testing.expect(std.meta.eql(left, right));
    // A generator can temporarily move its complete stack aside for an isolated
    // layout and restore it afterward, retaining the original snapshot cache.
    const caller = stack;
    stack = .empty;
    try std.testing.expectEqual(@as(usize, 0), (try stack.capture(arena.allocator())).len);
    stack.deinit(allocator);
    stack = caller;
    try std.testing.expectEqual(replaced.ptr, (try stack.capture(arena.allocator())).ptr);
    stack.clearRetainingCapacity();
    try verify(&stack);
    try std.testing.expectEqual(@as(usize, 0), (try stack.capture(arena.allocator())).len);
    try std.testing.expectEqual(@as(u32, 77), inherited[0].argument);
}

test "refinement indexes preserve identity captures environments and lexical rollback through OOM" {
    try rollbackLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rollbackLaw, .{});
}

test "refinement indexes keep inherited captures immutable after source stack destruction" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var source: Stack(Argument) = .empty;
    try source.append(a, .{ .unit = 1, .parameter = 7, .argument = 11, .argument_unit = 2 });
    const snapshot = source.capture(arena.allocator()) catch |err| {
        source.deinit(a);
        return err;
    };
    source.deinit(a);
    var child: Stack(Argument) = .empty;
    defer child.deinit(a);
    try child.appendSlice(a, snapshot);
    try std.testing.expectEqual(@as(?usize, 0), child.latestAny(1, 7));
    try std.testing.expectEqual(@as(?usize, 0), child.latestNonidentity(1, 7));
    try std.testing.expectEqual(@as(u32, 11), child.items[0].argument);
}

test "refinement indexes synchronize wide bindings once for repeated lookups" {
    var stack: Stack(Argument) = .empty;
    defer stack.deinit(a);
    for (0..512) |ordinal| try stack.append(a, .{ .unit = 1, .parameter = @intCast(ordinal), .argument = @intCast(ordinal + 1), .argument_unit = 1 });
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const snapshot = try stack.capture(arena.allocator());
    for (0..1000) |_| {
        try std.testing.expectEqual(@as(?usize, 0), stack.latestNonidentity(1, 0));
        try std.testing.expectEqual(snapshot.ptr, (try stack.capture(arena.allocator())).ptr);
    }
    try std.testing.expectEqual(@as(u64, 1000), stack.stats.lookups);
    try std.testing.expectEqual(@as(u64, 512), stack.stats.synchronized);
    try std.testing.expectEqual(@as(u64, 1), stack.stats.captures);
    try std.testing.expectEqual(@as(u64, 1000), stack.stats.capture_hits);
}
