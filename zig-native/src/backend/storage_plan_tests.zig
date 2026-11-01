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

const RootFacts = struct {
    root: ?usize = null,
    other_roots: []const usize = &.{},
    fields: []const @This() = &.{},
    depth: usize = 0,
    variant_index: ?usize = null,
    variant_possible: []const bool = &.{},
};

test "owned root metadata sparse union matches dense order filtering and field boundary" {
    const roots = [_]?usize{ null, 0, 1, 4, 5, std.math.maxInt(usize) };
    const alternatives = [_][]const usize{ &.{}, &.{ 0, 2 }, &.{ 4, 1, 4, 9 }, &.{99} };
    const children = [_]RootFacts{.{ .root = 3, .depth = 11 }};
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    for (roots) |left| for (roots) |right| for (alternatives) |left_others| for (alternatives) |right_others| {
        var target: RootFacts = .{ .root = left, .other_roots = left_others, .fields = &children, .depth = 2 };
        const value: RootFacts = .{ .root = right, .other_roots = right_others, .fields = &children, .depth = 7 };
        var expected: [5]usize = undefined;
        var count: usize = 0;
        for (0..5) |owner| {
            if (left == owner or right == owner or std.mem.findScalar(usize, left_others, owner) != null or std.mem.findScalar(usize, right_others, owner) != null) {
                expected[count] = owner;
                count += 1;
            }
        }
        try plan.unionRootMetadata(a, arena.allocator(), 5, &target, value);
        if (count == 0) {
            try std.testing.expectEqual(left, target.root);
            try std.testing.expectEqual(left_others.ptr, target.other_roots.ptr);
            try std.testing.expectEqualSlices(usize, left_others, target.other_roots);
        } else {
            try std.testing.expectEqual(@as(?usize, expected[0]), target.root);
            try std.testing.expectEqualSlices(usize, expected[1..count], target.other_roots);
        }
        try std.testing.expectEqual(@as(usize, 7), target.depth);
        try std.testing.expectEqual(children[0..].ptr, target.fields.ptr);
        // The metadata join ignores fields; recursive lifetime queries do not.
        try std.testing.expect(plan.hasRoot(target, 3));
        try std.testing.expectEqual(@as(usize, 11), target.fields[0].depth);
    };
}

fn sparseRootOwnership(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var left = [_]usize{ 8, 2, 8, 4096 };
    var right = [_]usize{ 4, 2, 0, 8192 };
    var target: RootFacts = .{ .root = 8, .other_roots = &left, .depth = 9 };
    try plan.unionRootMetadata(allocator, arena.allocator(), 4096, &target, RootFacts{ .root = 4, .other_roots = &right, .depth = 3 });
    @memset(&left, 7777);
    @memset(&right, 8888);
    try std.testing.expectEqual(@as(?usize, 0), target.root);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4, 8 }, target.other_roots);
    try std.testing.expectEqual(@as(usize, 9), target.depth);
}

test "owned root metadata sparse union owns sorted tails through OOM" {
    try sparseRootOwnership(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sparseRootOwnership, .{});
}

test "owned root metadata rootless union skips inventory and allocation while retaining depth" {
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    const children = [_]RootFacts{.{ .root = 123 }};
    var target: RootFacts = .{ .fields = &children, .depth = 2 };
    try plan.unionRootMetadata(failing.allocator(), failing.allocator(), 1_000_000, &target, RootFacts{ .depth = 9 });
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), failing.alloc_index);
    try std.testing.expectEqual(@as(usize, 9), target.depth);
    try std.testing.expect(target.root == null);
    try std.testing.expectEqual(@as(usize, 0), target.other_roots.len);
    try std.testing.expect(plan.hasRoot(target, 123));
}

test "owned root metadata sparse traversal matches dense membership order across every variant field" {
    const roots = [_]?usize{ null, 0, 1, 4, 5, std.math.maxInt(usize) };
    const alternatives = [_][]const usize{ &.{}, &.{ 0, 2 }, &.{ 4, 1, 4, 9 }, &.{99} };
    const inner = [_]RootFacts{ .{ .root = 1 }, .{ .root = 4, .other_roots = &.{ 0, 1, 5 } } };
    const fields = [_]RootFacts{ .{ .root = 3 }, .{ .fields = &inner, .variant_index = 0, .variant_possible = &.{ true, false } } };
    for (roots) |root| for (alternatives) |others| {
        const value: RootFacts = .{ .root = root, .other_roots = others, .fields = &fields, .variant_index = 0, .variant_possible = &.{ true, false } };
        for (0..7) |owner_count| {
            for (0..9) |start| {
                var expected: ?usize = null;
                var owner = start;
                while (owner < owner_count) : (owner += 1) {
                    if (plan.hasRoot(value, owner)) {
                        expected = owner;
                        break;
                    }
                }
                try std.testing.expectEqual(expected, plan.nextRoot(value, start, owner_count));
            }
            // This is also the old diagnostic/recursive-owner visitation order.
            var cursor: usize = 0;
            for (0..owner_count) |owner| {
                if (!plan.hasRoot(value, owner)) continue;
                try std.testing.expectEqual(@as(?usize, owner), plan.nextRoot(value, cursor, owner_count));
                cursor = owner + 1;
            }
            try std.testing.expect(plan.nextRoot(value, cursor, owner_count) == null);
        }
    };
    const empty: RootFacts = .{};
    try std.testing.expect(plan.nextRoot(empty, 0, 1_000_000) == null);
    const maximum: RootFacts = .{ .root = std.math.maxInt(usize) - 1, .other_roots = &.{std.math.maxInt(usize)} };
    try std.testing.expectEqual(maximum.root, plan.nextRoot(maximum, 0, std.math.maxInt(usize)));
    try std.testing.expect(plan.nextRoot(maximum, std.math.maxInt(usize), std.math.maxInt(usize)) == null);
}
