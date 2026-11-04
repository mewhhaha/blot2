//! Deterministic allocation-failure coverage over Zig's validating allocator.
//! SafeAllocator growth depends on previous bucket occupancy. Force container
//! growth through allocate/copy/free so every required allocation is injectable
//! and the successful discovery run has the same indices as failure runs.
const std = @import("std");
const profile = @import("allocation_failure_profile.zig");
const policy = @import("root").native_test_policy;

/// Preserve existing std.testing sweep semantics in full mode. Development
/// sampling uses stable allocation indices just like deterministic sweeps.
pub fn checkStandardAllocationFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    if (policy.fault_mode == .sampled) {
        var adapter: Deterministic = .{ .backing = backing };
        return checkSampledFailures(adapter.allocator(), test_fn, extra_args, false);
    }
    policy.counts.full_sweeps += 1;
    try std.testing.checkAllAllocationFailures(backing, test_fn, extra_args);
}

pub fn checkAllAllocationFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    var adapter: Deterministic = .{ .backing = backing };
    if (policy.fault_mode == .sampled) return checkSampledFailures(adapter.allocator(), test_fn, extra_args, false);
    policy.counts.full_sweeps += 1;
    if (comptime profile.enabled) {
        var measurement = profile.Measurement.start("deterministic", @intFromPtr(&test_fn), @returnAddress());
        defer measurement.finish();
        const Args = @Tuple(@typeInfo(std.meta.ArgsTuple(@TypeOf(test_fn))).@"struct".field_types[1..]);
        const Measured = struct {
            fn run(allocator: std.mem.Allocator, args: Args, counters: *profile.Measurement) !void {
                counters.runs += 1;
                // std.testing supplies its FailingAllocator directly; observe
                // the existing discovery run without another scenario call.
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(allocator.ptr));
                defer if (counters.runs == 1) {
                    counters.allocations = failing.alloc_index;
                };
                try @call(.auto, test_fn, .{allocator} ++ args);
            }
        };
        try std.testing.checkAllAllocationFailures(adapter.allocator(), Measured.run, .{ extra_args, &measurement });
        measurement.completed = true;
        return;
    }
    try std.testing.checkAllAllocationFailures(adapter.allocator(), test_fn, extra_args);
}

/// Concurrent jobs can distribute scratch allocations differently on each run.
/// Sweep every index observed in successful schedules, without requiring an
/// unreached allocation to exist in every subsequent schedule. Reached faults
/// must propagate, and all paths must balance their complete allocation traffic.
pub fn checkObservedConcurrentFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    var adapter: Deterministic = .{ .backing = backing };
    if (policy.fault_mode == .sampled) return checkSampledFailures(adapter.allocator(), test_fn, extra_args, true);
    policy.counts.full_sweeps += 1;
    var measurement: profile.Measurement = undefined;
    if (comptime profile.enabled) measurement = profile.Measurement.start("concurrent", @intFromPtr(&test_fn), @returnAddress());
    defer if (comptime profile.enabled) measurement.finish();
    var observed: usize = 0;
    for (0..4) |_| {
        if (comptime profile.enabled) measurement.runs += 1;
        var probe = std.testing.FailingAllocator.init(adapter.allocator(), .{});
        try @call(.auto, test_fn, .{probe.allocator()} ++ extra_args);
        try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);
        observed = @max(observed, probe.alloc_index);
        if (comptime profile.enabled) measurement.allocations = observed;
    }
    for (0..observed) |index| {
        if (comptime profile.enabled) measurement.runs += 1;
        var probe = std.testing.FailingAllocator.init(adapter.allocator(), .{ .fail_index = index });
        if (@call(.auto, test_fn, .{probe.allocator()} ++ extra_args)) |_| {
            try std.testing.expect(!probe.has_induced_failure);
        } else |err| switch (err) {
            error.OutOfMemory => try std.testing.expect(probe.has_induced_failure),
            else => return err,
        }
        try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);
    }
    if (comptime profile.enabled) measurement.completed = true;
}

/// Development checks still execute the successful scenario and inject faults
/// at the first, middle and last discovered allocations. Full is the default;
/// sampled results cannot qualify exhaustive allocation-failure coverage.
fn checkSampledFailures(backing: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype, concurrent: bool) !void {
    policy.counts.sampled_sweeps += 1;
    var observed: usize = 0;
    const probes: usize = if (concurrent) 4 else 1;
    for (0..probes) |_| {
        var probe = std.testing.FailingAllocator.init(backing, .{});
        try @call(.auto, test_fn, .{probe.allocator()} ++ extra_args);
        try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);
        observed = @max(observed, probe.alloc_index);
    }
    policy.counts.discovered_allocations += observed;
    if (observed == 0) return;
    const indices = [_]usize{ 0, observed / 2, observed - 1 };
    for (indices, 0..) |index, position| {
        var duplicate = false;
        for (indices[0..position]) |previous| {
            if (previous == index) duplicate = true;
        }
        if (duplicate) continue;
        policy.counts.fault_runs += 1;
        var probe = std.testing.FailingAllocator.init(backing, .{ .fail_index = index });
        if (@call(.auto, test_fn, .{probe.allocator()} ++ extra_args)) |_| {
            if (probe.has_induced_failure) return error.SwallowedOutOfMemoryError;
            if (!concurrent) return error.NondeterministicMemoryUsage;
        } else |err| {
            const failure: anyerror = err;
            if (failure == error.OutOfMemory) {
                try std.testing.expect(probe.has_induced_failure);
            } else return failure;
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

test "sampled allocation failures check bounded indices while full mode stays exhaustive" {
    const Scenario = struct {
        fn run(allocator: std.mem.Allocator, calls: *usize) !void {
            calls.* += 1;
            var values: [9][]u8 = undefined;
            var initialized: usize = 0;
            defer for (values[0..initialized]) |value| allocator.free(value);
            for (&values) |*value| {
                value.* = try allocator.alloc(u8, 8);
                initialized += 1;
            }
        }
    };
    const saved_mode = policy.fault_mode;
    const saved_counts = policy.counts;
    defer {
        policy.fault_mode = saved_mode;
        policy.counts = saved_counts;
    }
    var calls: usize = 0;
    policy.fault_mode = .sampled;
    policy.counts = .{};
    try checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{&calls});
    try std.testing.expectEqual(4, calls);
    try std.testing.expectEqual(9, policy.counts.discovered_allocations);
    try std.testing.expectEqual(3, policy.counts.fault_runs);
    try std.testing.expectEqual(1, policy.counts.sampled_sweeps);
    policy.fault_mode = .full;
    calls = 0;
    try checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{&calls});
    try std.testing.expectEqual(10, calls);
    try std.testing.expectEqual(1, policy.counts.full_sweeps);
    // The legacy std wrapper must retain the same exhaustive behavior too.
    calls = 0;
    try checkStandardAllocationFailures(std.testing.allocator, Scenario.run, .{&calls});
    try std.testing.expectEqual(10, calls);
    calls = 0;
    policy.fault_mode = .sampled;
    try checkStandardAllocationFailures(std.testing.allocator, Scenario.run, .{&calls});
    try std.testing.expectEqual(4, calls);
}

test "sampled allocation failures reject swallowed faults and propagate scenario failures" {
    const Scenario = struct {
        fn swallowed(allocator: std.mem.Allocator) !void {
            const bytes = allocator.alloc(u8, 8) catch return;
            allocator.free(bytes);
        }
        fn rejected(_: std.mem.Allocator) !void {
            return error.ScenarioFailure;
        }
    };
    const saved_counts = policy.counts;
    defer policy.counts = saved_counts;
    try std.testing.expectError(error.SwallowedOutOfMemoryError, checkSampledFailures(std.testing.allocator, Scenario.swallowed, .{}, false));
    try std.testing.expectError(error.ScenarioFailure, checkSampledFailures(std.testing.allocator, Scenario.rejected, .{}, false));
}
