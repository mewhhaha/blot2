//! Complete current-epoch resolution cache. Exact numeric roots retain their
//! chronological lower bounds; entries from older epochs occupy no live slots.
const std = @import("std");
pub const Cache = struct {
    pub const Entry = struct { generation: u32 = 0, root: u32 = 0, result: u32 = 0 };
    entries: []Entry = &.{},
    generation: u32 = 0,
    mutation: u32 = 0,
    other: u32 = 0,
    count: usize = 0,
    // Preserve dense-cache admission of unchanged roots below a previously
    // retained numerical root, without allocating all intervening slots.
    high_water: usize = 0,
    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = undefined;
    }
    pub fn activate(self: *Cache, mutation: u32, other: u32) bool {
        if (self.generation == std.math.maxInt(u32)) return false;
        if (self.generation != 0 and self.mutation == mutation and self.other == other) return true;
        self.generation += 1;
        self.mutation = mutation;
        self.other = other;
        self.count = 0;
        return self.generation != std.math.maxInt(u32);
    }
    fn index(root: u32, mask: usize) usize {
        var mixed = root;
        mixed ^= mixed >> 16;
        mixed *%= 0x7feb352d;
        mixed ^= mixed >> 15;
        mixed *%= 0x846ca68b;
        mixed ^= mixed >> 16;
        return @as(usize, mixed) & mask;
    }
    pub fn get(self: *const Cache, root: u32) ?u32 {
        if (self.entries.len == 0) return null;
        var slot = index(root, self.entries.len - 1);
        while (true) {
            const entry = self.entries[slot];
            if (entry.generation != self.generation) return null;
            if (entry.root == root) return entry.result;
            slot = (slot + 1) & (self.entries.len - 1);
        }
    }
    fn place(entries: []Entry, entry: Entry) void {
        var slot = index(entry.root, entries.len - 1);
        while (entries[slot].generation == entry.generation) slot = (slot + 1) & (entries.len - 1);
        entries[slot] = entry;
    }
    fn grow(self: *Cache, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        const capacity = if (self.entries.len == 0) 8 else std.math.mul(usize, self.entries.len, 2) catch return error.OutOfMemory;
        const replacement = try allocator.alloc(Entry, capacity);
        @memset(replacement, .{});
        for (self.entries) |entry| if (entry.generation == self.generation) place(replacement, entry);
        allocator.free(self.entries);
        self.entries = replacement;
    }
    pub fn put(self: *Cache, allocator: std.mem.Allocator, root: u32, result: u32) std.mem.Allocator.Error!void {
        std.debug.assert(self.generation != 0 and self.generation != std.math.maxInt(u32));
        // No current-epoch result is evicted. Retain a spare quarter of slots
        // so probing always reaches an empty slot, including after rollback.
        if (self.count >= self.entries.len - self.entries.len / 4) try self.grow(allocator);
        var slot = index(root, self.entries.len - 1);
        while (self.entries[slot].generation == self.generation) {
            if (self.entries[slot].root == root) {
                self.entries[slot].result = result;
                return;
            }
            slot = (slot + 1) & (self.entries.len - 1);
        }
        self.entries[slot] = .{ .generation = self.generation, .root = root, .result = result };
        self.count += 1;
        self.high_water = @max(self.high_water, @as(usize, root) + 1);
    }
};

fn completeScenario(allocator: std.mem.Allocator) !void {
    var cache: Cache = .{};
    defer cache.deinit(allocator);
    for (0..5) |epoch| {
        try std.testing.expect(cache.activate(@intCast(epoch), @intCast(epoch % 2)));
        for (0..193) |index_| {
            const root: u32 = @intCast(index_ * 65536 + 17);
            const result: u32 = if (index_ == 0) 0 else @intCast(index_ + epoch);
            try cache.put(allocator, root, result);
            // Growth must preserve every earlier answer, including pure row0.
            for (0..index_ + 1) |prior| {
                const expected: u32 = if (prior == 0) 0 else @intCast(prior + epoch);
                try std.testing.expectEqual(@as(?u32, expected), cache.get(@intCast(prior * 65536 + 17)));
            }
        }
        try std.testing.expect(cache.get(18) == null);
    }
    cache.generation = std.math.maxInt(u32) - 1;
    try std.testing.expect(!cache.activate(11, 12));
    try std.testing.expect(!cache.activate(11, 12));
}
test "complete epoch cache retains sparse colliding results through growth and allocation failure" {
    try completeScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, completeScenario, .{});
}
test "failed cache growth preserves all published answers and allows a later successful retry" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var cache: Cache = .{};
    defer cache.deinit(failing.allocator());
    try std.testing.expect(cache.activate(3, 7));
    for (0..6) |index_| try cache.put(failing.allocator(), @intCast(index_), @intCast(index_ + 1));
    const high_water = cache.high_water;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, cache.put(failing.allocator(), 1000000, 0));
    try std.testing.expectEqual(high_water, cache.high_water);
    for (0..6) |index_| try std.testing.expectEqual(@as(?u32, @intCast(index_ + 1)), cache.get(@intCast(index_)));
    failing.fail_index = std.math.maxInt(usize);
    try cache.put(failing.allocator(), 1000000, 0);
    try std.testing.expectEqual(@as(?u32, 0), cache.get(1000000));
}
