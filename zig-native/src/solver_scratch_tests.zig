const std = @import("std");
const types = @import("types.zig");
const effects = @import("effects.zig");

fn wideConstraints(allocator: std.mem.Allocator) !void {
    var store = try types.Store.init(allocator);
    defer store.deinit();
    var left: [192]types.Id = undefined;
    var right: [192]types.Id = @splat(types.u32_type);
    for (&left) |*item| item.* = try store.fresh();
    left[left.len - 1] = types.u32_type;
    right[right.len - 1] = types.f32_type;
    const pattern = try store.product(&left);
    const mismatch = try store.product(&right);
    const point = store.mark();
    if (store.unify(pattern, mismatch)) |_| return error.TestExpectedError else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.TypeMismatch);
    }
    try std.testing.expectEqual(point, store.mark());
    right[right.len - 1] = types.u32_type;
    const concrete = try store.product(&right);
    try store.unify(pattern, concrete);
    const resolved = try store.resolve(pattern, 0);
    try std.testing.expect(try store.equalClosed(resolved, concrete));
    try std.testing.expect(!try store.equalClosed(resolved, mismatch));
    const recursive = try store.fresh();
    right[right.len - 1] = recursive;
    const infinite = try store.product(&right);
    const before_occurs = store.mark();
    if (store.unify(recursive, infinite)) |_| return error.TestExpectedError else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InfiniteType);
    }
    try std.testing.expectEqual(before_occurs, store.mark());
    right[right.len - 1] = types.u32_type;
    const operation = try store.internOperation(.{ .unit = 7, .decl = 9 }, &right);
    const arguments = store.operationArguments(operation);
    try std.testing.expectEqual(operation, try store.internOperation(.{ .unit = 7, .decl = 9 }, arguments));
    try std.testing.expectEqualSlices(types.Id, &right, store.operationArguments(operation));
}

test "wide type walks preserve rollback and borrowed operation arguments across scratch fallback" {
    try wideConstraints(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wideConstraints, .{});
}

fn wideRows(allocator: std.mem.Allocator) !void {
    var store = try effects.Store.init(allocator);
    defer store.deinit();
    var labels: [192]effects.Label = undefined;
    var reverse: [192]effects.Label = undefined;
    for (&labels, &reverse, 0..) |*label, *other, index| {
        label.* = @intCast(index + 1);
        other.* = @intCast(labels.len - index);
    }
    const first = try store.fresh();
    const second = try store.fresh();
    const prefix = try store.row(&labels, store.node(second).tail);
    const suffix = try store.row(&.{999}, .closed);
    try store.appendVersionAt(store.node(first).tail.variable, prefix, 2);
    try store.appendVersionAt(store.node(second).tail.variable, suffix, 5);
    const resolved = try store.resolve(first, 0);
    try std.testing.expectEqual(@as(u32, 193), store.node(resolved).labels.len);
    try std.testing.expectEqualSlices(effects.Label, &labels, store.list(store.node(resolved).labels)[0..labels.len]);
    try std.testing.expectEqual(@as(effects.Label, 999), store.list(store.node(resolved).labels)[labels.len]);
    const future = try store.resolve(first, 3);
    try std.testing.expectEqual(store.node(first).tail.variable, store.node(future).tail.variable);
    const left = try store.row(&labels, .closed);
    const right = try store.row(&reverse, .closed);
    try store.unify(left, right);
    const shorter = try store.row(labels[0 .. labels.len - 1], .closed);
    const before = store.mark();
    if (store.unify(left, shorter)) |_| return error.TestExpectedError else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.EffectMismatch);
    }
    try std.testing.expectEqual(before, store.mark());
    const substituted = try store.substitute(prefix, store.node(second).tail.variable, right);
    try std.testing.expectEqual(@as(u32, 384), store.node(substituted).labels.len);
}

test "wide effect rows preserve chronological resolution multiplicity and failed revision recovery" {
    try wideRows(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wideRows, .{});
}
