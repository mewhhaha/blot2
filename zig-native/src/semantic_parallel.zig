//! Independent closed-call judgments. Workers borrow immutable source/inputs,
//! own their Session and solver, and return unpublished certificates in input
//! order. Only the backing allocator is shared; every job joins on failure.
const std = @import("std");
const independent = @import("independent_call_proof.zig");
const receipt = @import("specialization_receipt.zig");
const A = std.mem.Allocator;
pub const Request = struct { index: usize, read: receipt.CallRead, actual: u32 };
const Counts = struct { independent_rechecked: usize = 0, independent_reused: usize = 0, independent_declined: usize = 0 };
const Slot = struct { record: ?independent.Record = null, cached: ?usize = null, failed: bool = false, counts: Counts = .{} };
pub const Batch = struct {
    allocator: A,
    requests: []Request,
    slots: []Slot,
    workers: usize = 1,
    retained: ?*std.ArrayList(independent.Record) = null,
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
    /// Capacity is reserved before dispatch. Successful buffers transfer to the
    /// query owner without another allocation, even when a sibling failed.
    pub fn retainSuccesses(self: *Batch, owner: *std.ArrayList(independent.Record), words: *usize, limit: usize) void {
        self.retained = owner;
        for (self.slots) |*slot| if (slot.record) |record| {
            const cost = 16 + record.sources.len * 2 + record.scalar_reads.len * 6;
            if (cost > limit -| words.*) continue;
            slot.cached = owner.items.len;
            owner.appendAssumeCapacity(record);
            slot.record = null;
            words.* += cost;
        };
    }
    pub fn take(self: *Batch, index: usize, stats: anytype) A.Error!?independent.Record {
        for (self.requests, self.slots) |request, *slot| if (request.index == index) {
            stats.independent_rechecked += slot.counts.independent_rechecked;
            stats.independent_reused += slot.counts.independent_reused;
            stats.independent_declined += slot.counts.independent_declined;
            slot.counts = .{};
            if (slot.failed) return error.OutOfMemory;
            if (slot.cached) |cached| return try self.retained.?.items[cached].clone(self.allocator);
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
    const Result = struct {
        record: ?independent.Record = null,
        counts: Counts = .{},
        pub fn deinit(self: *@This(), allocator: A) void {
            if (self.record) |*record| record.deinit(allocator);
        }
    };
    const Context = struct {
        source: @TypeOf(state),
        generator: @TypeOf(g),
        fn execute(scratch: A, output: A, self: *@This(), request: Request) A.Error!?Result {
            var local: struct {
                allocator: A,
                old: @TypeOf(self.source.old),
                gate: @TypeOf(self.source.gate),
                completed_worker_proofs: @TypeOf(self.source.completed_worker_proofs),
                stats: Counts = .{},
            } = .{ .allocator = scratch, .old = self.source.old, .gate = self.source.gate, .completed_worker_proofs = self.source.completed_worker_proofs };
            const record = try independent.acquire(&local, self.generator, request.read, request.actual);
            return .{ .record = if (record) |owned| try owned.clone(output) else null, .counts = local.stats };
        }
    };
    const jobs = @import("semantic_job_batch.zig");
    // Cancellation is an inline atomic boolean and owns no allocation. Batch
    // cleanup owns requests/slots; the joined owner frees completed buffers.
    // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
    var cancellation: jobs.Cancellation = .{};
    var context: Context = .{ .source = state, .generator = g };
    var joined = try jobs.run(Result, a, io, batch.requests, requested, &cancellation, &context, Context.execute);
    defer joined.deinit();
    batch.workers = joined.workers;
    for (batch.slots, joined.outcomes) |*slot, *outcome| switch (outcome.*) {
        .complete => |result| {
            slot.record = result.record;
            slot.counts = result.counts;
            outcome.complete.record = null;
        },
        .out_of_memory => slot.failed = true,
        else => {},
    };
    return batch;
}
