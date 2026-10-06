//! Persistent collection spans with private space for growth. Extending the
//! latest span writes only outside every published span. Branching from an
//! older version copies it into a new buffer; old values never change.
const std = @import("std");
pub const Span = struct { start: u32, len: u32 };
pub const Error = std.mem.Allocator.Error || error{Limit};
pub const Store = struct {
    // Only the latest span in each buffer can extend into its unused slots.
    // Keys are spans, so typed views of the same value need no side metadata.
    buffers: std.AutoHashMapUnmanaged(Span, Span) = .empty,

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        self.buffers.deinit(allocator);
        self.* = .{};
    }

    pub fn extend(self: *Store, allocator: std.mem.Allocator, children: *std.ArrayList(u32), before: Span, value: u32, front: bool, maximum: usize) Error!Span {
        const limit = @min(maximum, std.math.maxInt(u32));
        if (children.items.len > limit or before.len == std.math.maxInt(u32)) return error.Limit;
        const length = before.len + 1;
        if (self.buffers.get(before)) |buffer| {
            const offset = before.start - buffer.start;
            std.debug.assert(offset <= buffer.len and before.len <= buffer.len - offset);
            const room = if (front) offset != 0 else before.len < buffer.len - offset;
            if (room) {
                const after: Span = .{ .start = before.start - @intFromBool(front), .len = length };
                // Reserve before writing even an unpublished slot. Failure
                // leaves the buffer's current growth frontier unchanged.
                try self.buffers.ensureUnusedCapacity(allocator, 1);
                _ = self.buffers.remove(before);
                children.items[if (front) after.start else before.start + before.len] = value;
                self.buffers.putAssumeCapacity(after, buffer);
                return after;
            }
        }
        const available = limit - children.items.len;
        if (length > available) return error.Limit;
        // Leave room at both ends, so alternating append/prepend also grows
        // geometrically. Unused slots count against the evaluator's budget.
        const capacity: u32 = @intCast(@min(available, @max(16, @as(u64, length) * 2)));
        const buffer: Span = .{ .start = @intCast(children.items.len), .len = capacity };
        const after: Span = .{ .start = buffer.start + (capacity - length) / 2, .len = length };
        try children.ensureUnusedCapacity(allocator, capacity);
        try self.buffers.ensureUnusedCapacity(allocator, 1);
        children.items.len += capacity;
        @memset(children.items[buffer.start..][0..capacity], 0);
        // Reacquire the source after growth; the new buffer cannot overlap it.
        @memcpy(children.items[after.start + @intFromBool(front) ..][0..before.len], children.items[before.start..][0..before.len]);
        children.items[if (front) after.start else after.start + before.len] = value;
        self.buffers.putAssumeCapacity(after, buffer);
        return after;
    }
};

test "persistent span growth is linear at either end with interleaved allocations" {
    const a = std.testing.allocator;
    for (0..3) |mode| {
        var store: Store = .{};
        defer store.deinit(a);
        var children: std.ArrayList(u32) = .empty;
        defer children.deinit(a);
        var versions: std.ArrayList(Span) = .empty;
        defer versions.deinit(a);
        var current: Span = .{ .start = 0, .len = 0 };
        for (0..4096) |i| {
            try versions.append(a, current);
            // Element aggregates and other builders share the child arena.
            try children.append(a, 123456);
            current = try store.extend(a, &children, current, @intCast(i), mode == 1 or (mode == 2 and i % 2 == 1), 100000);
        }
        try versions.append(a, current);
        try std.testing.expect(children.items.len < 4096 * 10);
        for (versions.items, 0..) |span, count| {
            const front_count = if (mode == 1) count else if (mode == 2) count / 2 else 0;
            for (children.items[span.start..][0..span.len], 0..) |actual, i| {
                const expected = if (mode == 1) count - 1 - i else if (mode == 0) i else if (i < front_count) (front_count - 1 - i) * 2 + 1 else (i - front_count) * 2;
                try std.testing.expectEqual(@as(u32, @intCast(expected)), actual);
            }
        }
    }
}

fn branchScenario(a: std.mem.Allocator) !void {
    var store: Store = .{};
    defer store.deinit(a);
    var children: std.ArrayList(u32) = .empty;
    defer children.deinit(a);
    const first = try store.extend(a, &children, .{ .start = 0, .len = 0 }, 20, false, 100);
    const second = try store.extend(a, &children, first, 22, false, 100);
    const branch = try store.extend(a, &children, first, 99, false, 100);
    const prefixed = try store.extend(a, &children, second, 10, true, 100);
    try std.testing.expectEqualSlices(u32, &.{20}, children.items[first.start..][0..first.len]);
    try std.testing.expectEqualSlices(u32, &.{ 20, 22 }, children.items[second.start..][0..second.len]);
    try std.testing.expectEqualSlices(u32, &.{ 20, 99 }, children.items[branch.start..][0..branch.len]);
    try std.testing.expectEqualSlices(u32, &.{ 10, 20, 22 }, children.items[prefixed.start..][0..prefixed.len]);
}

test "branched spans preserve earlier versions and release every allocation failure" {
    try branchScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, branchScenario, .{});
}

test "growth respects the remaining child budget without reserving extra space" {
    const a = std.testing.allocator;
    var store: Store = .{};
    defer store.deinit(a);
    var children: std.ArrayList(u32) = .empty;
    defer children.deinit(a);
    const one = try store.extend(a, &children, .{ .start = 0, .len = 0 }, 42, false, 1);
    try std.testing.expectEqual(@as(usize, 1), children.items.len);
    try std.testing.expectError(error.Limit, store.extend(a, &children, one, 99, false, 1));
    try std.testing.expectEqualSlices(u32, &.{42}, children.items);
}
