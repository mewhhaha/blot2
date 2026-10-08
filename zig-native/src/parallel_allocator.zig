//! Short allocator critical sections for otherwise independently owned jobs.
const std = @import("std");
const A = std.mem.Allocator;
pub const LockedAllocator = struct {
    backing: A,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    pub fn allocator(self: *LockedAllocator) A {
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
