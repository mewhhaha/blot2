//! Requested live bytes, separate from allocator capacity and process RSS.
const std = @import("std");
const Alignment = std.mem.Alignment;
pub const Counts = struct { live_bytes: usize = 0, peak_bytes: usize = 0, allocated_bytes: usize = 0, allocations: usize = 0 };
pub const TrackedAllocator = struct {
    backing: std.mem.Allocator,
    counts: Counts = .{},
    pub fn allocator(self: *TrackedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn added(self: *TrackedAllocator, bytes: usize) void {
        self.counts.live_bytes += bytes;
        self.counts.allocated_bytes += bytes;
        self.counts.peak_bytes = @max(self.counts.peak_bytes, self.counts.live_bytes);
    }
    fn changed(self: *TrackedAllocator, old: usize, new: usize) void {
        if (new >= old) self.added(new - old) else self.counts.live_bytes -= old - new;
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: Alignment, ret: usize) ?[*]u8 {
        const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
        const result = self.backing.rawAlloc(len, alignment, ret) orelse return null;
        self.added(len);
        self.counts.allocations += 1;
        return result;
    }
    fn resize(raw: *anyopaque, old: []u8, alignment: Alignment, len: usize, ret: usize) bool {
        const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
        if (!self.backing.rawResize(old, alignment, len, ret)) return false;
        self.changed(old.len, len);
        return true;
    }
    fn remap(raw: *anyopaque, old: []u8, alignment: Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
        const result = self.backing.rawRemap(old, alignment, len, ret) orelse return null;
        self.changed(old.len, len);
        return result;
    }
    fn free(raw: *anyopaque, old: []u8, alignment: Alignment, ret: usize) void {
        const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
        self.backing.rawFree(old, alignment, ret);
        self.counts.live_bytes -= old.len;
    }
};

test "counts track live storage across array growth and teardown" {
    var tracked: TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var bytes: std.ArrayList(u8) = .empty;
    for (0..4096) |i| try bytes.append(a, @truncate(i));
    try std.testing.expectEqual(bytes.capacity, tracked.counts.live_bytes);
    try std.testing.expect(tracked.counts.peak_bytes >= bytes.capacity);
    bytes.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}
