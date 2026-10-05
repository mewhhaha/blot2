//! Deterministic allocation-failure coverage over Zig's validating allocator.
//! SafeAllocator growth depends on previous bucket occupancy. Force container
//! growth through allocate/copy/free so every required allocation is injectable
//! and the successful discovery run has the same indices as failure runs.
const std = @import("std");

pub fn checkAllAllocationFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    var adapter: Deterministic = .{ .backing = backing };
    try std.testing.checkAllAllocationFailures(adapter.allocator(), test_fn, extra_args);
}

const Deterministic = struct {
    backing: std.mem.Allocator,
    fn allocator(self: *Deterministic) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Deterministic = @ptrCast(@alignCast(ctx));
        return self.backing.rawAlloc(len, alignment, ra);
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *Deterministic = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, ra);
    }
};
