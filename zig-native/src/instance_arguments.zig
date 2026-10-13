//! Backend-local instance arguments in parameter order. These keys contain
//! source identity terms, never guest authority handles or active permission.
const std = @import("std");
const types = @import("types.zig");
pub const Identity = types.NominalIdentity;
pub const Span = struct { start: u32, len: u32 };
pub const Error = std.mem.Allocator.Error || error{InstanceLimit};
pub const Owned = struct {
    values: []const Identity = &.{},
    spans: []const Span = &.{},
    pub fn get(self: *const Owned, id: u32) []const Identity {
        if (id == 0) return &.{};
        const span = self.spans[id - 1];
        return self.values[span.start..][0..span.len];
    }
    pub fn deinit(self: *Owned, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.spans);
    }
};
pub const Store = struct {
    values: std.ArrayList(Identity) = .empty,
    spans: std.ArrayList(Span) = .empty,
    pub fn get(self: *const Store, id: u32) []const Identity {
        return (Owned{ .values = self.values.items, .spans = self.spans.items }).get(id);
    }
    pub fn intern(self: *Store, allocator: std.mem.Allocator, arguments: []const Identity) Error!u32 {
        var present = false;
        for (arguments) |identity| present = present or identity.decl != 0;
        if (!present) return 0;
        for (self.spans.items, 0..) |span, index| {
            if (span.len != arguments.len) continue;
            var equal = true;
            for (self.values.items[span.start..][0..span.len], arguments) |left, right| equal = equal and std.meta.eql(left, right);
            if (equal) return @intCast(index + 1);
        }
        if (arguments.len > 16 or self.spans.items.len >= 4096) return error.InstanceLimit;
        const start = self.values.items.len;
        errdefer self.values.shrinkRetainingCapacity(start);
        try self.values.appendSlice(allocator, arguments);
        try self.spans.append(allocator, .{ .start = @intCast(start), .len = @intCast(arguments.len) });
        return @intCast(self.spans.items.len);
    }
    pub fn copyOwned(self: *const Store, allocator: std.mem.Allocator) std.mem.Allocator.Error!Owned {
        const values = try allocator.dupe(Identity, self.values.items);
        errdefer allocator.free(values);
        return .{ .values = values, .spans = try allocator.dupe(Span, self.spans.items) };
    }
    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
        self.spans.deinit(allocator);
    }
};

fn orderedArguments(allocator: std.mem.Allocator) !void {
    var store: Store = .{};
    defer store.deinit(allocator);
    const left: Identity = .{ .unit = 1, .decl = 23 };
    const right: Identity = .{ .unit = 1, .decl = 24 };
    try std.testing.expectEqual(@as(u32, 0), try store.intern(allocator, &.{ .{ .unit = 0, .decl = 0 }, .{ .unit = 0, .decl = 0 } }));
    try std.testing.expectEqual(@as(usize, 0), store.values.capacity);
    const first = try store.intern(allocator, &.{ left, right });
    try std.testing.expectEqual(first, try store.intern(allocator, &.{ left, right }));
    try std.testing.expect(first != try store.intern(allocator, &.{ right, left }));
    try std.testing.expect(first != try store.intern(allocator, &.{ left, left }));
    var owned = try store.copyOwned(allocator);
    defer owned.deinit(allocator);
    store.values.items[0] = right;
    try std.testing.expectEqual(left, owned.get(first)[0]);
}
test "instance argument keys preserve position and own every copied term through OOM" {
    try orderedArguments(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, orderedArguments, .{});
}
