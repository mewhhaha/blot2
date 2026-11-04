const std = @import("std");
const failures = @import("allocation_failures.zig");

const SweepCounts = struct {
    runs: usize = 0,
    successes: usize = 0,
    failures: usize = 0,

    fn scenario(allocator: std.mem.Allocator, counts: *SweepCounts) anyerror!void {
        counts.runs += 1;
        errdefer counts.failures += 1;
        const first = try allocator.alloc(u8, 1);
        defer allocator.free(first);
        const second = try allocator.alloc(u8, 2);
        defer allocator.free(second);
        const third = try allocator.alloc(u8, 3);
        defer allocator.free(third);
        counts.successes += 1;
    }

    fn unexpected(_: std.mem.Allocator) anyerror!void {
        return error.UnexpectedScenarioError;
    }
};

test "allocation sweep covers every fault with exactly one discovery run" {
    var counts: SweepCounts = .{};
    try failures.checkAllAllocationFailures(std.testing.allocator, SweepCounts.scenario, .{&counts});
    try std.testing.expectEqual(@as(usize, 4), counts.runs);
    try std.testing.expectEqual(@as(usize, 1), counts.successes);
    try std.testing.expectEqual(@as(usize, 3), counts.failures);
}

test "concurrent allocation sweep retains four discoveries and every observed fault" {
    var counts: SweepCounts = .{};
    try failures.checkObservedConcurrentFailures(std.testing.allocator, SweepCounts.scenario, .{&counts});
    try std.testing.expectEqual(@as(usize, 7), counts.runs);
    try std.testing.expectEqual(@as(usize, 4), counts.successes);
    try std.testing.expectEqual(@as(usize, 3), counts.failures);
}

test "allocation sweeps preserve unexpected scenario errors" {
    try std.testing.expectError(error.UnexpectedScenarioError, failures.checkAllAllocationFailures(std.testing.allocator, SweepCounts.unexpected, .{}));
    try std.testing.expectError(error.UnexpectedScenarioError, failures.checkObservedConcurrentFailures(std.testing.allocator, SweepCounts.unexpected, .{}));
}
