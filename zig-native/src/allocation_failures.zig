//! Deterministic allocation-failure coverage over Zig's validating allocator.
//! SafeAllocator growth depends on previous bucket occupancy. Force container
//! growth through allocate/copy/free so every required allocation is injectable
//! and the successful discovery run has the same indices as failure runs.
const std = @import("std");

pub fn checkAllAllocationFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    var adapter: Deterministic = .{ .backing = backing };
    try std.testing.checkAllAllocationFailures(adapter.allocator(), test_fn, extra_args);
}

/// Concurrent jobs can distribute scratch allocations differently on each run.
/// Sweep every index observed in successful schedules, without requiring an
/// unreached allocation to exist in every subsequent schedule. Reached faults
/// must propagate, and all paths must balance their complete allocation traffic.
pub fn checkObservedConcurrentFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    var adapter: Deterministic = .{ .backing = backing };
    var observed: usize = 0;
    for (0..4) |_| {
        var probe = std.testing.FailingAllocator.init(adapter.allocator(), .{});
        try @call(.auto, test_fn, .{probe.allocator()} ++ extra_args);
        try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);
        observed = @max(observed, probe.alloc_index);
    }
    for (0..observed) |index| {
        var probe = std.testing.FailingAllocator.init(adapter.allocator(), .{ .fail_index = index });
        if (@call(.auto, test_fn, .{probe.allocator()} ++ extra_args)) |_| {
            try std.testing.expect(!probe.has_induced_failure);
        } else |err| switch (err) {
            error.OutOfMemory => try std.testing.expect(probe.has_induced_failure),
            else => return err,
        }
        try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);
    }
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
