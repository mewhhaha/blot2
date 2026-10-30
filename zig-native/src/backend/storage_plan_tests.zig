const std = @import("std");
const plan = @import("storage_plan.zig");
const calls = @import("storage_calls.zig");
const a = std.testing.allocator;

test "owned storage evidence copies layout and exit slices" {
    var evidence: plan.Plan = .{ .allocator = a };
    defer evidence.deinit();
    const scalar = try evidence.layout(.{ .kind = .scalar, .words = 1 });
    var fields = [_]plan.LayoutId{scalar};
    const record = try evidence.layout(.{ .kind = .aggregate, .words = 1, .fields = &fields });
    fields[0] = record;
    try std.testing.expectEqual(scalar, evidence.layouts.items[@backingInt(record)].fields[0]);
    var owners = [_]plan.OwnerId{@fromBackingInt(@intCast(7))};
    const exit = try evidence.exit(.{ .kind = .return_, .cleanup = &owners });
    owners[0] = @fromBackingInt(@intCast(9));
    try std.testing.expectEqual(@as(u32, 7), @backingInt(evidence.exits.items[@backingInt(exit)].cleanup[0]));
    try std.testing.expectError(error.InvalidExit, evidence.exit(.{ .kind = .trap, .value = @fromBackingInt(@intCast(1)) }));
}

test "owned call cache compares complete evidence and owns its key" {
    var cache: calls.Cache = .{ .allocator = a };
    defer cache.deinit();
    var evidence = [_]u32{ 1, 2, 3, 4 };
    const key: calls.Key = .{ .unit = 1, .binding = 7, .evidence = &evidence };
    _ = try cache.insert(key, 21, false);
    evidence[3] = 5;
    try std.testing.expect(cache.find(key) == null);
    try std.testing.expectEqual(@as(?usize, 0), cache.find(.{ .unit = 1, .binding = 7, .evidence = &.{ 1, 2, 3, 4 } }));
    try std.testing.expect(cache.find(.{ .unit = 2, .binding = 7, .evidence = &.{ 1, 2, 3, 4 } }) == null);
    try std.testing.expectEqual(@as(u64, 0x1_0000_0000), try plan.nextEpoch(0xffff_ffff));
    try std.testing.expectError(error.Exhausted, plan.nextEpoch(std.math.maxInt(u64)));
}

test "owned root evidence retains joined and nested borrow origins" {
    const Value = struct {
        tag: enum { scalar, array, aggregate, ref, view, link } = .scalar,
        root: ?usize = null,
        other_roots: []const usize = &.{},
        fields: []const @This() = &.{},
    };
    const pool: Value = .{ .tag = .array, .root = 2, .other_roots = &.{5} };
    const alternative = [_]Value{.{ .tag = .link, .root = 5 }};
    const nested = [_]Value{.{ .tag = .aggregate, .fields = &alternative }};
    const result: Value = .{ .tag = .aggregate, .fields = &nested };
    try std.testing.expect(plan.borrows(result, pool));
    try std.testing.expect(plan.hasRoot(result, 5));
    try std.testing.expect(!plan.borrows(result, Value{ .tag = .array, .root = 7 }));
}
