//! Membership beside an append-only ordered ID list. The list still determines
//! traversal and diagnostic order; only repeated membership gains an index.
const std = @import("std");
const A = std.mem.Allocator;
pub const Index = struct {
    enabled: bool = true,
    covered: usize = 0,
    members: std.AutoHashMapUnmanaged(u32, void) = .empty,

    pub fn deinit(self: *Index, a: A) void {
        self.members.deinit(a);
        self.* = undefined;
    }
    pub fn contains(self: *Index, a: A, values: []const u32, value: u32) A.Error!bool {
        // Zig's scalar-search primitive uses SIMD where the target supports it.
        // Small lists avoid a hash allocation, and keep their original order.
        if (!self.enabled or values.len < 64) return std.mem.findScalar(u32, values, value) != null;
        std.debug.assert(values.len >= self.covered);
        while (self.covered < values.len) : (self.covered += 1) try self.members.put(a, values[self.covered], {});
        return self.members.contains(value);
    }
};

fn scenario(a: A) !void {
    var index: Index = .{};
    defer index.deinit(a);
    var values: [160]u32 = undefined;
    for (&values, 0..) |*value, i| value.* = @as(u32, @intCast(i / 2)) *% 0x9e3779b9;
    for ([_]usize{ 0, 1, 8, 63, 64, 65, 128, 160 }) |len| {
        for (values) |value| try std.testing.expectEqual(std.mem.findScalar(u32, values[0..len], value) != null, try index.contains(a, values[0..len], value));
        try std.testing.expect(!try index.contains(a, values[0..len], 0xffffffff));
    }
}
test "ordered scheme membership preserves sparse IDs duplicates and append order through OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}
