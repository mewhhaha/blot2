//! Exact cache identities for substitutions in one explicit variable namespace.
//! Values may be zero (the closed empty row); this is not a semantic type graph.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const Entry = extern struct {
    variable: u32,
    value: u32,
    fn less(_: void, left: Entry, right: Entry) bool {
        return left.variable < right.variable;
    }
};
const Span = struct { start: u32, len: u32 };
pub const Error = Allocator.Error || error{ KeyLimit, ConflictingSubstitution };
pub const Store = struct {
    allocator: Allocator,
    entries: std.ArrayList(Entry) = .empty,
    spans: std.ArrayList(Span) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    pub fn init(allocator: Allocator) Store {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Store) void {
        self.entries.deinit(self.allocator);
        self.spans.deinit(self.allocator);
        self.next.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn get(self: *const Store, id: Id) []const Entry {
        if (id == 0) return &.{};
        const span = self.spans.items[id - 1];
        return self.entries.items[span.start..][0..span.len];
    }
    pub fn intern(self: *Store, values: []const Entry) Error!Id {
        if (values.len == 0) return 0;
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        const owned = try allocator.dupe(Entry, values);
        defer allocator.free(owned);
        std.mem.sortUnstable(Entry, owned, {}, Entry.less);
        if (owned.len > 1) for (owned[1..], owned[0 .. owned.len - 1]) |entry, prior| if (entry.variable == prior.variable) return error.ConflictingSubstitution;
        return self.internHashed(owned, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(owned)));
    }
    fn internHashed(self: *Store, values: []const Entry, fingerprint: u64) Error!Id {
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate - 1]) {
            const old = self.get(candidate);
            if (old.len != values.len) continue;
            var same = true;
            for (old, values) |left, right| same = same and left.variable == right.variable and left.value == right.value;
            if (same) return candidate;
        }
        if (self.spans.items.len >= std.math.maxInt(u32) - 1 or values.len > std.math.maxInt(u32) or self.entries.items.len > std.math.maxInt(u32) - values.len) return error.KeyLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.entries.ensureUnusedCapacity(self.allocator, values.len);
        try self.spans.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        const id: Id = @intCast(self.spans.items.len + 1);
        self.spans.appendAssumeCapacity(.{ .start = @intCast(self.entries.items.len), .len = @intCast(values.len) });
        self.entries.appendSliceAssumeCapacity(values);
        self.next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
};

fn allocationScenario(allocator: Allocator) !void {
    var store = Store.init(allocator);
    defer store.deinit();
    const first = try store.intern(&.{ .{ .variable = 9, .value = 3 }, .{ .variable = 0, .value = 0 } });
    const reordered = try store.intern(&.{ .{ .variable = 0, .value = 0 }, .{ .variable = 9, .value = 3 } });
    try std.testing.expectEqual(first, reordered);
    try std.testing.expect(first != try store.intern(&.{.{ .variable = 9, .value = 3 }}));
    const borrowed = try store.intern(store.get(first));
    try std.testing.expectEqual(first, borrowed);
    try std.testing.expectError(error.ConflictingSubstitution, store.intern(&.{ .{ .variable = 9, .value = 3 }, .{ .variable = 9, .value = 4 } }));
    for (0..64) |i| _ = try store.intern(&.{.{ .variable = 4, .value = @intCast(i) }});
    try std.testing.expectEqual(@as(u32, 0), store.get(first)[0].value);
}
test "substitution keys retain closed empty facts without conflating namespaces or missing facts" {
    try allocationScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
test "substitution hashes check exact values after collision" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const first = try store.internHashed(&.{.{ .variable = 0, .value = 0 }}, 0);
    const other = try store.internHashed(&.{.{ .variable = 0, .value = 1 }}, 0);
    try std.testing.expect(first != other);
    try std.testing.expectEqual(first, try store.internHashed(&.{.{ .variable = 0, .value = 0 }}, 0));
}
