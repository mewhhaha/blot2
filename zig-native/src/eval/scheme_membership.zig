//! Region-local membership indexes for immutable Core lists. Unit owner and
//! exact list span are both part of identity. Tiny lists stay allocation-free.
const std = @import("std");
const List = @import("../check/types.zig").List;
const Key = struct { owner: usize, span: List };
pub const View = struct {
    values: []const u32,
    sorted: bool = false,
    pub fn contains(self: View, value: u32) bool {
        if (!self.sorted) return std.mem.findScalar(u32, self.values, value) != null;
        var low: usize = 0;
        var high = self.values.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.values[middle] < value) low = middle + 1 else high = middle;
        }
        return low < self.values.len and self.values[low] == value;
    }
};
pub const Cache = struct {
    const Storage = struct {
        entries: std.AutoHashMapUnmanaged(Key, []u32) = .empty,
        items: usize = 0,
    };
    // Most regions never prepare a large list. Keep only a nullable handle in
    // their pooled header; counters belong to the existing session aggregate.
    storage: ?*Storage = null,
    pub fn deinit(self: *Cache, a: std.mem.Allocator) void {
        if (self.storage) |storage| {
            var values = storage.entries.valueIterator();
            while (values.next()) |value| a.free(value.*);
            storage.entries.deinit(a);
            a.destroy(storage);
        }
        self.* = undefined;
    }
    pub fn prepare(self: *Cache, a: std.mem.Allocator, stats: *@import("../work_counters.zig").SchemeMembership, owner: usize, span: List, values: []const u32) std.mem.Allocator.Error!View {
        std.debug.assert(values.len == span.len);
        stats.prepares += 1;
        if (values.len <= 16) {
            stats.small += 1;
            return .{ .values = values };
        }
        if (values.len > 16384) {
            stats.saturated += 1;
            return .{ .values = values };
        }
        if (self.storage == null) {
            const storage = try a.create(Storage);
            storage.* = .{};
            self.storage = storage;
        }
        const storage = self.storage.?;
        const key: Key = .{ .owner = owner, .span = span };
        if (storage.entries.get(key)) |sorted| {
            stats.hits += 1;
            return .{ .values = sorted, .sorted = true };
        }
        if (storage.entries.count() >= 64 or values.len > 16384 - storage.items) {
            stats.saturated += 1;
            return .{ .values = values };
        }
        const sorted = try a.dupe(u32, values);
        errdefer a.free(sorted);
        std.mem.sort(u32, sorted, {}, std.sort.asc(u32));
        try storage.entries.put(a, key, sorted);
        storage.items += sorted.len;
        stats.publications += 1;
        stats.indexed_items += sorted.len;
        return .{ .values = sorted, .sorted = true };
    }
};
fn scenario(a: std.mem.Allocator) !void {
    var cache: Cache = .{};
    defer cache.deinit(a);
    var stats: @import("../work_counters.zig").SchemeMembership = .{};
    const small = try cache.prepare(a, &stats, 2, .{ .start = 100, .len = 3 }, &.{ 30, 3, 30 });
    try std.testing.expect(!small.sorted and small.contains(3) and !small.contains(4));
    try std.testing.expect(cache.storage == null);
    const oversized: [16385]u32 = @splat(77);
    const linear = try cache.prepare(a, &stats, 2, .{ .start = 103, .len = oversized.len }, &oversized);
    try std.testing.expect(!linear.sorted and linear.contains(77) and !linear.contains(78));
    try std.testing.expect(cache.storage == null);
    var values: [40]u32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast((39 - i) / 2);
    const span: List = .{ .start = 17, .len = values.len };
    const first = try cache.prepare(a, &stats, 2, span, &values);
    try std.testing.expect(first.sorted);
    for (0..42) |id| try std.testing.expectEqual(std.mem.findScalar(u32, &values, @intCast(id)) != null, first.contains(@intCast(id)));
    const again = try cache.prepare(a, &stats, 2, span, &values);
    try std.testing.expect(first.values.ptr == again.values.ptr);
    var other: [40]u32 = @splat(91);
    const separate = try cache.prepare(a, &stats, 3, span, &other);
    try std.testing.expect(separate.contains(91) and !separate.contains(0));
    for (4..68) |owner| _ = try cache.prepare(a, &stats, owner, span, &values);
    try std.testing.expectEqual(@as(u32, 64), cache.storage.?.entries.count());
    const declined = try cache.prepare(a, &stats, 1000, span, &other);
    try std.testing.expect(!declined.sorted and declined.contains(91) and !declined.contains(0));
}
test "large scheme memberships preserve owner identity duplicates bounds and allocation failures" {
    try scenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}
