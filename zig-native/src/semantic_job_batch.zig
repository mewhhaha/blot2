//! Joined private jobs. Input is immutable until return; failures belong to
//! individual slots, and completed results survive cancellation of later work.
const std = @import("std");
const A = std.mem.Allocator;
pub const Cancellation = struct {
    stopped: std.atomic.Value(bool) = .init(false),
    pub fn cancel(self: *Cancellation) void {
        self.stopped.store(true, .release);
    }
    pub fn cancelled(self: *const Cancellation) bool {
        return self.stopped.load(.acquire);
    }
};
pub fn Outcome(comptime T: type) type {
    return union(enum) { pending, complete: T, declined, out_of_memory, cancelled };
}
pub fn Batch(comptime T: type) type {
    return struct {
        allocator: A,
        outcomes: []Outcome(T),
        workers: usize = 1,
        pub fn deinit(self: *@This()) void {
            for (self.outcomes) |*slot| if (slot.* == .complete) slot.complete.deinit(self.allocator);
            self.allocator.free(self.outcomes);
            self.* = undefined;
        }
    };
}
/// `execute` returns owned buffers without retaining either allocator adapter.
/// The coordinator owns all publication after this function joins every task.
pub fn run(comptime T: type, a: A, io: std.Io, requests: anytype, requested: u8, cancellation: *Cancellation, context: anytype, comptime execute: anytype) A.Error!Batch(T) {
    var result: Batch(T) = .{ .allocator = a, .outcomes = try a.alloc(Outcome(T), requests.len) };
    @memset(result.outcomes, .pending);
    var locked: @import("parallel_allocator.zig").LockedAllocator = .{ .backing = a, .io = io };
    const Work = struct {
        allocator: A,
        io: std.Io,
        requests: @TypeOf(requests),
        context: @TypeOf(context),
        slots: []Outcome(T),
        cancellation: *Cancellation,
        next: std.atomic.Value(usize) = .init(0),
        fn work(self: *@This()) void {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            while (!self.cancellation.cancelled()) {
                self.io.checkCancel() catch {
                    self.cancellation.cancel();
                    return;
                };
                const index = self.next.fetchAdd(1, .monotonic);
                if (index >= self.requests.len) return;
                if (self.cancellation.cancelled()) return;
                const value = execute(arena.allocator(), self.allocator, self.context, self.requests[index]) catch {
                    self.slots[index] = .out_of_memory;
                    _ = arena.reset(.{ .retain_with_limit = 512 * 1024 });
                    continue;
                };
                self.slots[index] = if (value) |owned| .{ .complete = owned } else .declined;
                _ = arena.reset(.{ .retain_with_limit = 512 * 1024 });
            }
        }
    };
    var work: Work = .{ .allocator = locked.allocator(), .io = io, .requests = requests, .context = context, .slots = result.outcomes, .cancellation = cancellation };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    const count = @min(@as(usize, requested), @min(requests.len, 16));
    for (1..@max(1, count)) |_| {
        group.concurrent(io, Work.work, .{&work}) catch break;
        result.workers += 1;
    }
    work.work();
    group.await(io) catch cancellation.cancel();
    // Await/cancel guarantees there are no writers before this final pass.
    for (result.outcomes) |*slot| if (slot.* == .pending) {
        slot.* = .cancelled;
    };
    return result;
}

const TestResult = struct {
    bytes: []u8,
    pub fn deinit(self: *TestResult, a: A) void {
        a.free(self.bytes);
    }
};
const TestContext = struct {
    cancellation: *Cancellation,
    fail: ?usize = null,
    cancel_after: ?usize = null,
    started: std.atomic.Value(usize) = .init(0),
    finished: std.atomic.Value(usize) = .init(0),
    fn execute(scratch: A, output: A, self: *TestContext, index: usize) A.Error!?TestResult {
        _ = self.started.fetchAdd(1, .monotonic);
        defer _ = self.finished.fetchAdd(1, .monotonic);
        const temporary = try scratch.alloc(u8, 2048);
        @memset(temporary, @intCast(index));
        if (self.fail == index) return error.OutOfMemory;
        if (index == 2) return null;
        const copied = try output.dupe(u8, temporary);
        if (self.cancel_after == index) self.cancellation.cancel();
        return .{ .bytes = copied };
    }
};
test "private semantic batch preserves successful jobs across failure and joins cancelled dispatch" {
    const requests = [_]usize{ 0, 1, 2, 3, 4, 5 };
    for ([_]u8{ 1, 2, 4 }) |workers| {
        var cancellation: Cancellation = .{};
        var context: TestContext = .{ .cancellation = &cancellation, .fail = 1 };
        var batch = try run(TestResult, std.testing.allocator, std.testing.io, &requests, workers, &cancellation, &context, TestContext.execute);
        defer batch.deinit();
        try std.testing.expect(batch.outcomes[1] == .out_of_memory);
        try std.testing.expect(batch.outcomes[2] == .declined);
        for ([_]usize{ 0, 3, 4, 5 }) |index| {
            try std.testing.expect(batch.outcomes[index] == .complete);
            for (batch.outcomes[index].complete.bytes) |byte| try std.testing.expectEqual(@as(u8, @intCast(index)), byte);
        }
        try std.testing.expectEqual(@as(usize, requests.len), context.finished.load(.acquire));
    }
    for ([_]u8{ 1, 4 }) |workers| {
        var cancellation: Cancellation = .{};
        var context: TestContext = .{ .cancellation = &cancellation, .cancel_after = 0 };
        var cancelled = try run(TestResult, std.testing.allocator, std.testing.io, &requests, workers, &cancellation, &context, TestContext.execute);
        defer cancelled.deinit();
        try std.testing.expect(cancelled.outcomes[0] == .complete);
        if (workers == 1) for (cancelled.outcomes[1..]) |slot| {
            try std.testing.expect(slot == .cancelled);
        };
        for (cancelled.outcomes) |slot| try std.testing.expect(slot != .pending);
        try std.testing.expectEqual(context.started.load(.acquire), context.finished.load(.acquire));
    }
    var stopped: Cancellation = .{};
    stopped.cancel();
    var context: TestContext = .{ .cancellation = &stopped };
    var before_dispatch = try run(TestResult, std.testing.allocator, std.testing.io, &requests, 4, &stopped, &context, TestContext.execute);
    defer before_dispatch.deinit();
    for (before_dispatch.outcomes) |slot| try std.testing.expect(slot == .cancelled);
    try std.testing.expectEqual(@as(usize, 0), context.started.load(.acquire));
}

fn allocationScenario(a: A, workers: u8) !void {
    const requests = [_]usize{ 0, 1, 2, 3, 4, 5 };
    var cancellation: Cancellation = .{};
    var context: TestContext = .{ .cancellation = &cancellation };
    var batch = try run(TestResult, a, std.testing.io, &requests, workers, &cancellation, &context, TestContext.execute);
    defer batch.deinit();
    try std.testing.expectEqual(context.started.load(.acquire), context.finished.load(.acquire));
    for (batch.outcomes) |slot| if (slot == .out_of_memory) return error.OutOfMemory;
    try std.testing.expect(batch.outcomes[2] == .declined);
}
test "private semantic batch releases every owner through dispatch work and completed result allocation failures" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{@as(u8, 1)});
    try @import("allocation_failures.zig").checkObservedConcurrentFailures(std.testing.allocator, allocationScenario, .{@as(u8, 4)});
}
