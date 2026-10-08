//! Independent closed-call judgments. Workers borrow immutable source/inputs,
//! own their Session and solver, and return unpublished certificates in input
//! order. Only the backing allocator is shared; every job joins on failure.
const std = @import("std");
const independent = @import("independent_call_proof.zig");
const receipt = @import("specialization_receipt.zig");
const A = std.mem.Allocator;
pub const Request = struct { index: usize, read: receipt.CallRead, actual: u32 };
const Counts = struct { independent_rechecked: usize = 0, independent_reused: usize = 0, independent_declined: usize = 0 };
const Slot = struct { record: ?independent.Record = null, failed: bool = false, counts: Counts = .{} };
pub const Batch = struct {
    allocator: A,
    requests: []Request,
    slots: []Slot,
    workers: usize = 1,
    pub fn deinit(self: *Batch) void {
        for (self.slots) |*slot| if (slot.record) |*record| record.deinit(self.allocator);
        self.allocator.free(self.slots);
        self.allocator.free(self.requests);
        self.* = undefined;
    }
    pub fn attempted(self: *const Batch, index: usize) bool {
        for (self.requests) |request| if (request.index == index) return true;
        return false;
    }
    pub fn take(self: *Batch, index: usize, stats: anytype) ?independent.Record {
        for (self.requests, self.slots) |request, *slot| if (request.index == index) {
            stats.independent_rechecked += slot.counts.independent_rechecked;
            stats.independent_reused += slot.counts.independent_reused;
            stats.independent_declined += slot.counts.independent_declined;
            slot.counts = .{};
            const record = slot.record;
            slot.record = null;
            return record;
        };
        return null;
    }
};

pub fn run(a: A, io: std.Io, state: anytype, g: anytype, requests: []const Request, requested: u8) A.Error!Batch {
    var batch: Batch = .{ .allocator = a, .requests = try a.dupe(Request, requests), .slots = &.{} };
    errdefer batch.deinit();
    batch.slots = try a.alloc(Slot, requests.len);
    @memset(batch.slots, .{});
    var locked: @import("parallel_allocator.zig").LockedAllocator = .{ .backing = a, .io = io };
    const Work = struct {
        allocator: A,
        source: @TypeOf(state),
        generator: @TypeOf(g),
        requests: []const Request,
        slots: []Slot,
        next: std.atomic.Value(usize) = .init(0),
        fn execute(self: *@This()) void {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            while (true) {
                const id = self.next.fetchAdd(1, .monotonic);
                if (id >= self.requests.len) return;
                const slot = &self.slots[id];
                const request = self.requests[id];
                var local: struct { allocator: A, old: @TypeOf(self.source.old), gate: @TypeOf(self.source.gate), stats: Counts = .{} } = .{ .allocator = arena.allocator(), .old = self.source.old, .gate = self.source.gate };
                const result = independent.acquire(&local, self.generator, request.read, request.actual) catch blk: {
                    slot.failed = true;
                    break :blk null;
                };
                slot.counts = local.stats;
                if (result) |record| slot.record = record.clone(self.allocator) catch blk: {
                    slot.failed = true;
                    break :blk null;
                };
                _ = arena.reset(.{ .retain_with_limit = 512 * 1024 });
            }
        }
    };
    var work: Work = .{ .allocator = locked.allocator(), .source = state, .generator = g, .requests = batch.requests, .slots = batch.slots };
    var group: std.Io.Group = .init;
    const protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(protection);
    defer group.cancel(io);
    const count = @min(@as(usize, requested), @min(requests.len, 16));
    for (1..@max(1, count)) |_| {
        group.concurrent(io, Work.execute, .{&work}) catch break;
        batch.workers += 1;
    }
    work.execute();
    group.await(io) catch unreachable;
    for (batch.slots) |slot| if (slot.failed) return error.OutOfMemory;
    return batch;
}
