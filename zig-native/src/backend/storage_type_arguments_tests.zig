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

fn churnLaw(allocator: std.mem.Allocator, rounds: usize) !void {
    var stack: Stack(Argument) = .empty;
    defer stack.deinit(allocator);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const base: Argument = .{ .unit = 1, .parameter = 1, .argument = 7, .argument_unit = 2 };
    try stack.append(allocator, base);
    // First grow the table with live bindings, then leave a small active prefix.
    // Deleting later short-lived keys used to fill the large table with
    // tombstones without triggering growth, making misses probe every slot.
    for (0..256) |ordinal| try stack.append(allocator, .{ .unit = 2, .parameter = @intCast(ordinal), .argument = 9, .argument_unit = 3 });
    stack.shrinkRetainingCapacity(1);
    try std.testing.expectEqual(@as(usize, 1), stack.active_count);
    for (0..rounds) |ordinal| {
        const parameter: u32 = @intCast(ordinal);
        try stack.append(allocator, .{ .unit = 3, .parameter = parameter, .argument = 11, .argument_unit = 4 });
        try stack.append(allocator, .{ .unit = 3, .parameter = parameter, .argument = parameter, .argument_unit = 3 });
        try std.testing.expectEqual(@as(?usize, 2), stack.latestAny(3, parameter));
        try std.testing.expectEqual(@as(?usize, 1), stack.latestNonidentity(3, parameter));
        stack.shrinkRetainingCapacity(1);
        try std.testing.expect(stack.latestAny(3, parameter) == null);
        try std.testing.expect(stack.latestNonidentity(3, parameter) == null);
        try std.testing.expect(stack.latestNonidentity(4, parameter) == null);
        try std.testing.expectEqual(@as(?usize, 0), stack.latestNonidentity(1, 1));
        try std.testing.expectEqual(@as(usize, 1), stack.active_count);
        try std.testing.expectEqual(ordinal + 258, stack.positions.count());
    }
    const snapshot = try stack.capture(arena.allocator());
    try std.testing.expectEqual(@as(usize, 1), snapshot.len);
    try std.testing.expect(std.meta.eql(base, snapshot[0]));
    // Reusing an inactive key restores ordinary shadowing without adding a
    // table key; capture size counts live keys rather than retained history.
    const retained = stack.positions.count();
    try stack.append(allocator, .{ .unit = 3, .parameter = 0, .argument = 13, .argument_unit = 4 });
    try std.testing.expectEqual(retained, stack.positions.count());
    try std.testing.expectEqual(@as(usize, 2), (try stack.capture(arena.allocator())).len);
    stack.shrinkRetainingCapacity(0);
    try std.testing.expectEqual(@as(usize, 0), stack.active_count);
    try std.testing.expectEqual(@as(usize, 0), (try stack.capture(arena.allocator())).len);
    try std.testing.expect(stack.positions.count() != 0);
    stack.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), stack.positions.count());
    try std.testing.expectEqual(@as(usize, 0), stack.active_count);
    try stack.append(allocator, base);
    try std.testing.expectEqual(@as(?usize, 0), stack.latestAny(1, 1));
    try std.testing.expectEqual(@as(usize, 1), (try stack.capture(arena.allocator())).len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.len);
    try std.testing.expect(std.meta.eql(base, snapshot[0]));
}

test "refinement indexes retain inactive keys across sustained lexical churn and OOM" {
    try churnLaw(a, 16_384);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, churnLaw, .{@as(usize, 64)});
}

fn parentSnapshotLaw(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var stack: Stack(Argument) = .empty;
    defer stack.deinit(allocator);
    const first_environment = [_]u32{ 91, 92 };
    const second_environment = [_]u32{ 91, 92 };
    const base = [_]Argument{
        .{ .unit = 1, .parameter = 7, .argument = 11, .argument_unit = 4, .environment = &first_environment },
        .{ .unit = 2, .parameter = 8, .argument = 13, .argument_unit = 4, .environment = &second_environment },
    };
    try stack.appendSlice(allocator, &base);
    const parent = try stack.capture(arena.allocator());
    try stack.append(allocator, .{ .unit = 1, .parameter = 7, .argument = 7, .argument_unit = 1, .environment = &second_environment });
    const child = try stack.capture(arena.allocator());
    try std.testing.expectEqual(@as(?usize, 2), stack.latestAny(1, 7));
    try std.testing.expectEqual(@as(?usize, 0), stack.latestNonidentity(1, 7));
    try std.testing.expectEqual(second_environment[0..].ptr, child[1].environment.?.ptr);
    try stack.append(allocator, .{ .unit = 3, .parameter = 9, .argument = 19, .argument_unit = 4, .environment = &first_environment });
    const grandchild = try stack.capture(arena.allocator());
    try stack.append(allocator, .{ .unit = 2, .parameter = 8, .argument = 23, .argument_unit = 4 });
    // Pop a mutation with no capture, then two captured scopes. Every restored
    // pointer belongs to that exact prefix, including identity/environment data.
    stack.shrinkRetainingCapacity(4);
    try std.testing.expectEqual(grandchild.ptr, (try stack.capture(arena.allocator())).ptr);
    stack.shrinkRetainingCapacity(3);
    try std.testing.expectEqual(child.ptr, (try stack.capture(arena.allocator())).ptr);
    stack.shrinkRetainingCapacity(2);
    try std.testing.expectEqual(parent.ptr, (try stack.capture(arena.allocator())).ptr);
    try std.testing.expectEqual(@as(u64, 3), stack.stats.captures);
    try std.testing.expectEqual(@as(u64, 3), stack.stats.capture_hits);
    for (parent, base) |restored, original_| try std.testing.expect(std.meta.eql(restored, original_));
    try std.testing.expectEqual(first_environment[0..].ptr, parent[0].environment.?.ptr);
    // Reappend at the same length with different contents must not resurrect
    // the old child snapshot; older returned environments stay immutable.
    try stack.append(allocator, .{ .unit = 1, .parameter = 7, .argument = 29, .argument_unit = 4, .environment = &first_environment });
    const replacement = try stack.capture(arena.allocator());
    try std.testing.expectEqual(@as(u32, 29), replacement[1].argument);
    try std.testing.expectEqual(@as(u32, 7), child[1].argument);
    stack.shrinkRetainingCapacity(2);
    try std.testing.expectEqual(parent.ptr, (try stack.capture(arena.allocator())).ptr);
}

test "refinement indexes restore exact captured parent prefixes across nested rollback and OOM" {
    try parentSnapshotLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parentSnapshotLaw, .{});
}

fn verifyCapturedPrefix(stack: *Stack(Argument), arena: std.mem.Allocator) ![]const Argument {
    const captured = try stack.capture(arena);
    var at: usize = 0;
    for (stack.items, 0..) |argument, index| {
        if (original(stack.items, argument.unit, argument.parameter, false) != index) continue;
        try std.testing.expect(at < captured.len);
        try std.testing.expect(std.meta.eql(argument, captured[at]));
        at += 1;
    }
    try std.testing.expectEqual(at, captured.len);
    try verify(stack);
    return captured;
}
fn activeCaptureLaw(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var stack: Stack(Argument) = .empty;
    defer stack.deinit(allocator);
    var prefixes: std.ArrayList([]const Argument) = .empty;
    defer prefixes.deinit(allocator);
    try prefixes.append(allocator, try verifyCapturedPrefix(&stack, arena.allocator()));
    const left_environment = [_]u32{ 11, 19 };
    const right_environment = [_]u32{ 11, 19 };
    for (0..128) |step| {
        if (step % 5 == 4 and stack.items.len != 0) {
            const length = stack.items.len * 3 / 5;
            stack.shrinkRetainingCapacity(length);
            prefixes.shrinkRetainingCapacity(length + 1);
            const captured = try verifyCapturedPrefix(&stack, arena.allocator());
            try std.testing.expectEqual(prefixes.items[length].ptr, captured.ptr);
        } else {
            const unit: u32 = @intCast(step % 3 + 1);
            const parameter: u32 = @intCast(step % 7);
            var argument: Argument = .{ .unit = unit, .parameter = parameter, .argument = @intCast(step + 40), .argument_unit = 4, .environment = &left_environment };
            if (step % 4 == 0) {
                argument.argument = parameter;
                argument.argument_unit = unit;
                argument.environment = &right_environment;
            }
            try stack.append(allocator, argument);
            try prefixes.append(allocator, try verifyCapturedPrefix(&stack, arena.allocator()));
        }
    }
    while (stack.items.len != 0) {
        const length = stack.items.len - 1;
        stack.shrinkRetainingCapacity(length);
        prefixes.shrinkRetainingCapacity(length + 1);
        const captured = try verifyCapturedPrefix(&stack, arena.allocator());
        try std.testing.expectEqual(prefixes.items[length].ptr, captured.ptr);
    }
    stack.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), (try verifyCapturedPrefix(&stack, arena.allocator())).len);
}

test "refinement active captures match linear order and exact prefixes after every mutation through OOM" {
    try activeCaptureLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, activeCaptureLaw, .{});
}
