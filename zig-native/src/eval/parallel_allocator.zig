//! Short allocator critical sections for otherwise independently owned jobs.
//! Allocators already safe for concurrent use are handed to jobs unwrapped.
const std = @import("std");
const shareable = @import("../runtime/memory.zig").shareable;
const A = std.mem.Allocator;
pub const LockedAllocator = struct {
    backing: A,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    pub fn allocator(self: *LockedAllocator) A {
        if (shareable(self.backing)) return self.backing;
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.backing.rawAlloc(len, alignment, ret);
    }
    fn resize(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.backing.rawResize(old, alignment, len, ret);
    }
    fn remap(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.backing.rawRemap(old, alignment, len, ret);
    }
    fn free(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.backing.rawFree(old, alignment, ret);
    }
};

test "jobs share a concurrent allocator directly and lock any other" {
    var shared: LockedAllocator = .{ .backing = std.heap.smp_allocator, .io = std.testing.io };
    try std.testing.expectEqual(std.heap.smp_allocator.vtable, shared.allocator().vtable);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var locked: LockedAllocator = .{ .backing = failing.allocator(), .io = std.testing.io };
    const a = locked.allocator();
    try std.testing.expect(a.ptr == @as(*anyopaque, @ptrCast(&locked)));
    const bytes = try a.alloc(u8, 16);
    a.free(bytes);
    try std.testing.expectEqual(@as(usize, 1), failing.allocations);
}
