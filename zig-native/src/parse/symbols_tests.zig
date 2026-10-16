const std = @import("std");
const production = @import("symbols.zig");
const Pool = production.Pool;
const Symbol = production.Symbol;

test "symbol handles survive growth and exact hash collisions" {
    const a = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(a);
    const alpha = try pool.internHashed(a, "alpha", 7);
    const beta = try pool.internHashed(a, "beta", 7);
    try std.testing.expect(alpha != beta);
    try std.testing.expectEqual(alpha, try pool.internHashed(a, "alpha", 7));
    for (0..2048) |i| {
        var buffer: [32]u8 = undefined;
        const text = try std.mem.print(&buffer, "symbol_{d}", .{i});
        _ = try pool.intern(a, text);
    }
    try std.testing.expectEqualStrings("alpha", pool.get(alpha));
    try std.testing.expectEqualStrings("beta", pool.get(beta));
    const unicode = try pool.intern(a, "π😀");
    try std.testing.expectEqualStrings("π😀", pool.get(unicode));
    const slice = pool.get(alpha)[1..];
    const suffix = try pool.intern(a, slice);
    try std.testing.expectEqualStrings("lpha", pool.get(suffix));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var pool: Pool = .{};
    defer pool.deinit(allocator);
    const first = try pool.intern(allocator, "stable");
    for (0..40) |i| {
        var buffer: [64]u8 = undefined;
        _ = try pool.intern(allocator, try std.mem.print(&buffer, "other_symbol_{d}", .{i}));
    }
    try std.testing.expectEqualStrings("stable", pool.get(first));
}

test "symbol allocation failures release every owned buffer" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "a declined insertion keeps every published symbol valid" {
    for (0..3) |failure| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const a = failing.allocator();
        var pool: Pool = .{};
        defer pool.deinit(a);
        var ids: [8]Symbol = undefined;
        for (&ids, 0..) |*id, index| {
            var text: [16]u8 = undefined;
            id.* = try pool.intern(a, try std.mem.print(&text, "entry_{d}", .{index}));
        }
        try pool.entries.shrinkAndFreePrecise(a, pool.entries.items.len);
        try pool.bytes.shrinkAndFreePrecise(a, pool.bytes.items.len);
        failing.resize_fail_index = failing.resize_index;
        failing.fail_index = failing.alloc_index + failure;
        try std.testing.expectError(error.OutOfMemory, pool.intern(a, "a_new_symbol_that_requires_growing_all_three_storage_tables"));
        try std.testing.expectEqual(@as(usize, 8), pool.entries.items.len);
        for (ids, 0..) |id, index| {
            var text: [16]u8 = undefined;
            const original = try std.mem.print(&text, "entry_{d}", .{index});
            try std.testing.expectEqualStrings(original, pool.get(id));
            try std.testing.expectEqual(id, try pool.intern(a, original));
        }
        failing.fail_index = std.math.maxInt(usize);
        failing.resize_fail_index = std.math.maxInt(usize);
        _ = try pool.intern(a, "recovery");
    }
}

test "interning a borrowed substring survives relocation of the byte buffer" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const a = failing.allocator();
    var pool: Pool = .{};
    defer pool.deinit(a);
    const original = try pool.intern(a, "abcdefghijklmnopqrstuvwxyz");
    try pool.bytes.shrinkAndFreePrecise(a, pool.bytes.items.len);
    const old_pointer = pool.bytes.items.ptr;
    const borrowed = pool.get(original)[1..];
    // Disabling remap forces reserve to allocate a different buffer.
    failing.resize_fail_index = failing.resize_index;
    const suffix = try pool.intern(a, borrowed);
    try std.testing.expect(old_pointer != pool.bytes.items.ptr);
    try std.testing.expectEqualStrings("bcdefghijklmnopqrstuvwxyz", pool.get(suffix));
    try std.testing.expectEqualStrings("abcdefghijklmnopqrstuvwxyz", pool.get(original));
}
