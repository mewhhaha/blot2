//! Requested live bytes, separate from allocator capacity and process RSS.
const std = @import("std");
const builtin = @import("builtin");
const Alignment = std.mem.Alignment;
pub const Counts = struct { live_bytes: usize = 0, peak_bytes: usize = 0, allocated_bytes: usize = 0, allocations: usize = 0 };
/// A single meter keeps plain counters for one thread. A shared meter updates
/// the same fields atomically, so concurrent jobs may allocate through it
/// without an outer lock. Either way `counts` is read only after every job
/// using the meter has joined.
pub const Sharing = enum { single, shared };
pub const TrackedAllocator = struct {
    backing: std.mem.Allocator,
    counts: Counts = .{},
    sharing: Sharing = .single,
    pub fn allocator(self: *TrackedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = switch (self.sharing) {
            .single => &Meter(.single).vtable,
            .shared => &Meter(.shared).vtable,
        } };
    }
};

/// True when concurrent jobs may call `a` directly. Unknown allocators answer
/// false and keep their caller's lock; a shared meter is only as safe as its
/// backing allocator.
pub fn shareable(a: std.mem.Allocator) bool {
    if (a.vtable == std.heap.smp_allocator.vtable or a.vtable == std.heap.page_allocator.vtable) return true;
    if (builtin.is_test and a.vtable == std.testing.allocator.vtable) return true;
    if (a.vtable == &Meter(.shared).vtable) return shareable(@as(*TrackedAllocator, @ptrCast(@alignCast(a.ptr))).backing);
    return false;
}

fn Meter(comptime sharing: Sharing) type {
    return struct {
        const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };
        fn add(field: *usize, bytes: usize) usize {
            if (sharing == .single) {
                field.* += bytes;
                return field.*;
            }
            return @atomicRmw(usize, field, .Add, bytes, .monotonic) + bytes;
        }
        fn sub(field: *usize, bytes: usize) void {
            if (sharing == .single) field.* -= bytes else _ = @atomicRmw(usize, field, .Sub, bytes, .monotonic);
        }
        fn added(self: *TrackedAllocator, bytes: usize) void {
            const live = add(&self.counts.live_bytes, bytes);
            _ = add(&self.counts.allocated_bytes, bytes);
            if (sharing == .single) {
                self.counts.peak_bytes = @max(self.counts.peak_bytes, live);
            } else if (live > @atomicLoad(usize, &self.counts.peak_bytes, .monotonic)) {
                _ = @atomicRmw(usize, &self.counts.peak_bytes, .Max, live, .monotonic);
            }
        }
        fn changed(self: *TrackedAllocator, old: usize, new: usize) void {
            if (new >= old) added(self, new - old) else sub(&self.counts.live_bytes, old - new);
        }
        fn alloc(raw: *anyopaque, len: usize, alignment: Alignment, ret: usize) ?[*]u8 {
            const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
            const result = self.backing.rawAlloc(len, alignment, ret) orelse return null;
            added(self, len);
            _ = add(&self.counts.allocations, 1);
            return result;
        }
        fn resize(raw: *anyopaque, old: []u8, alignment: Alignment, len: usize, ret: usize) bool {
            const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
            if (!self.backing.rawResize(old, alignment, len, ret)) return false;
            changed(self, old.len, len);
            return true;
        }
        fn remap(raw: *anyopaque, old: []u8, alignment: Alignment, len: usize, ret: usize) ?[*]u8 {
            const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
            const result = self.backing.rawRemap(old, alignment, len, ret) orelse return null;
            changed(self, old.len, len);
            return result;
        }
        fn free(raw: *anyopaque, old: []u8, alignment: Alignment, ret: usize) void {
            const self: *TrackedAllocator = @ptrCast(@alignCast(raw));
            self.backing.rawFree(old, alignment, ret);
            sub(&self.counts.live_bytes, old.len);
        }
    };
}

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

test "a shared meter counts concurrent jobs exactly once they join" {
    var tracked: TrackedAllocator = .{ .backing = std.testing.allocator, .sharing = .shared };
    const Job = struct {
        fn run(backing: std.mem.Allocator, seed: usize, counts: *Counts) void {
            var local: TrackedAllocator = .{ .backing = backing };
            const a = local.allocator();
            var kept: [64][]u8 = undefined;
            const offset = std.math.mul(usize, seed, 7) catch @panic("seed overflow");
            for (&kept, 0..) |*slot, index| {
                const mixed = std.math.add(usize, offset, index) catch @panic("seed overflow");
                slot.* = a.alloc(u8, 1 + mixed % 97) catch @panic("out of memory");
            }
            for (kept[0..32]) |*slot| slot.* = a.realloc(slot.*, slot.len + 300) catch @panic("out of memory");
            for (kept) |slot| a.free(slot);
            counts.* = local.counts;
        }
    };
    var threads: [4]std.Thread = undefined;
    var jobs: [threads.len + 1]Counts = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Job.run, .{ tracked.allocator(), index, &jobs[index] });
    Job.run(tracked.allocator(), threads.len, &jobs[threads.len]);
    for (threads) |thread| thread.join();
    // Concurrent allocation order can change whether a remap grows in place.
    // Sum plain per-job meters over the same operations the shared meter saw.
    var expected: Counts = .{};
    for (jobs) |counts| {
        try std.testing.expectEqual(@as(usize, 0), counts.live_bytes);
        expected.allocations += counts.allocations;
        expected.allocated_bytes += counts.allocated_bytes;
    }
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
    try std.testing.expectEqual(expected.allocations, tracked.counts.allocations);
    try std.testing.expectEqual(expected.allocated_bytes, tracked.counts.allocated_bytes);
    try std.testing.expect(tracked.counts.peak_bytes > 0 and tracked.counts.peak_bytes <= tracked.counts.allocated_bytes);
}

test "only lock-free-safe allocators are shareable" {
    try std.testing.expect(shareable(std.heap.smp_allocator));
    try std.testing.expect(shareable(std.testing.allocator));
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try std.testing.expect(!shareable(failing.allocator()));
    var single: TrackedAllocator = .{ .backing = std.heap.smp_allocator };
    try std.testing.expect(!shareable(single.allocator()));
    var shared: TrackedAllocator = .{ .backing = std.heap.smp_allocator, .sharing = .shared };
    try std.testing.expect(shareable(shared.allocator()));
    var over_failing: TrackedAllocator = .{ .backing = failing.allocator(), .sharing = .shared };
    try std.testing.expect(!shareable(over_failing.allocator()));
}
