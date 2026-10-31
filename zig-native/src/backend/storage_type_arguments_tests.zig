const std = @import("std");
const Index = @import("storage_type_arguments.zig").Index;
const a = std.testing.allocator;
const Argument = struct { unit: u32, parameter: u32, argument: u32, argument_unit: u32, environment: ?[]const u32 = null };
fn original(arguments: []const Argument, unit: u32, parameter: u32) ?usize {
    var at = arguments.len;
    while (at != 0) {
        at -= 1;
        const item = arguments[at];
        if (item.unit == unit and item.parameter == parameter and (item.argument_unit != unit or item.argument != parameter)) return at;
    }
    return null;
}
fn lookupLaw(allocator: std.mem.Allocator) !void {
    var arguments: std.ArrayList(Argument) = .empty;
    defer arguments.deinit(allocator);
    var index: Index = .{ .allocator = allocator, .minimum_bindings = 0 };
    defer index.deinit();
    const environment = [_]u32{ 91, 92 };
    for (0..256) |ordinal| {
        const unit: u32 = @intCast(ordinal % 3 + 1);
        const parameter: u32 = @intCast(ordinal % 7);
        try arguments.append(allocator, .{ .unit = unit, .parameter = parameter, .argument = @intCast(ordinal + 20), .argument_unit = 4, .environment = &environment });
        try arguments.append(allocator, .{ .unit = unit, .parameter = parameter, .argument = parameter, .argument_unit = unit, .environment = &environment });
        for (1..5) |queried_unit| for (0..8) |queried_parameter| {
            try std.testing.expectEqual(original(arguments.items, @intCast(queried_unit), @intCast(queried_parameter)), try index.find(arguments.items, @intCast(queried_unit), @intCast(queried_parameter)));
        };
    }
    try std.testing.expectEqual(@as(u64, 512), index.stats.synchronized);
    try std.testing.expectEqual(@as(u64, 0), index.stats.linear);
}
test "refinement indexes preserve last nonidentity shadowing environments and reallocations through OOM" {
    try lookupLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lookupLaw, .{});
}
test "refinement index saturation and scope shrink use the exact reverse scan" {
    var arguments = [_]Argument{
        .{ .unit = 1, .parameter = 1, .argument = 2, .argument_unit = 1 },
        .{ .unit = 2, .parameter = 1, .argument = 9, .argument_unit = 2 },
        .{ .unit = 1, .parameter = 1, .argument = 3, .argument_unit = 1 },
        .{ .unit = 1, .parameter = 1, .argument = 4, .argument_unit = 1 },
    };
    var saturated: Index = .{ .allocator = a, .minimum_bindings = 0, .maximum_bindings = 2 };
    defer saturated.deinit();
    try std.testing.expectEqual(@as(?usize, 0), try saturated.find(arguments[0..2], 1, 1));
    try std.testing.expectEqual(@as(?usize, 2), try saturated.find(arguments[0..3], 1, 1));
    try std.testing.expectEqual(@as(?usize, 3), try saturated.find(&arguments, 1, 1));
    try std.testing.expect(saturated.disabled);
    var shrunk: Index = .{ .allocator = a, .minimum_bindings = 0 };
    defer shrunk.deinit();
    try std.testing.expectEqual(@as(?usize, 3), try shrunk.find(&arguments, 1, 1));
    try std.testing.expectEqual(@as(?usize, 0), try shrunk.find(arguments[0..2], 1, 1));
    try std.testing.expect(shrunk.disabled);
    arguments[1] = .{ .unit = 1, .parameter = 1, .argument = 5, .argument_unit = 1 };
    // Shrink/reappend between two refinement scopes requires a new index.
    var fresh: Index = .{ .allocator = a, .minimum_bindings = 0 };
    defer fresh.deinit();
    try std.testing.expectEqual(@as(?usize, 1), try fresh.find(arguments[0..2], 1, 1));
}
test "refinement indexes synchronize wide bindings once for repeated lookups" {
    var arguments: [512]Argument = undefined;
    for (&arguments, 0..) |*item, ordinal| item.* = .{ .unit = 1, .parameter = @intCast(ordinal), .argument = @intCast(ordinal + 1), .argument_unit = 1 };
    var index: Index = .{ .allocator = a };
    defer index.deinit();
    for (0..1000) |_| try std.testing.expectEqual(@as(?usize, 0), try index.find(&arguments, 1, 0));
    try std.testing.expectEqual(@as(u64, 1000), index.stats.lookups);
    try std.testing.expectEqual(@as(u64, 512), index.stats.synchronized);
    try std.testing.expectEqual(@as(u64, 0), index.stats.linear);
}
