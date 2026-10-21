//! One compiled artifact supports inventories and isolated execution shards.
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
pub const native_test_policy = @import("native_test_policy.zig");
const policy = native_test_policy;

pub const std_options: std.Options = .{ .logFn = log };
var logged_errors: usize = 0;
pub fn log(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (level == .err) logged_errors += 1;
    if (@backingInt(level) <= @backingInt(testing.log_level)) {
        std.debug.print("[" ++ @tagName(scope) ++ "] (" ++ @tagName(level) ++ "): " ++ format ++ "\n", args);
    }
}

pub fn main(init: std.process.Init) !void {
    const Outcome = struct {
        result: anyerror!void = {},
        fn execute(self: *@This(), started: std.process.Init) void {
            self.result = run(started);
        }
    };
    var outcome: Outcome = .{};
    // Match src/main.zig: evaluator recursion limits assume the compiler's
    // reserved stack, not the host's 8 MiB main stack. Pages commit on demand.
    const thread = try std.Thread.spawn(.{ .stack_size = 1 << 30 }, Outcome.execute, .{ &outcome, init });
    thread.join();
    return outcome.result;
}

fn run(init: std.process.Init) !void {
    @disableInstrumentation();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var shard: usize = 0;
    var shards: usize = 1;
    var list = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--list")) {
            list = true;
        } else if (std.mem.startsWith(u8, arg, "--shard=")) {
            shard = try std.fmt.parseInt(usize, arg[8..], 10);
        } else if (std.mem.startsWith(u8, arg, "--shards=")) {
            shards = try std.fmt.parseInt(usize, arg[9..], 10);
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            testing.random_seed = try std.fmt.parseInt(u32, arg[7..], 0);
        } else if (std.mem.startsWith(u8, arg, "--test=")) {
            var found = false;
            for (builtin.test_functions) |test_fn| {
                if (std.mem.eql(u8, test_fn.name, arg[7..])) found = true;
            }
            if (!found) return error.UnknownNativeTest;
        } else if (std.mem.startsWith(u8, arg, "--allocation-failures=")) {
            policy.fault_mode = std.meta.stringToEnum(policy.FaultMode, arg[22..]) orelse return error.InvalidAllocationFailureMode;
        } else return error.InvalidTestRunnerArgument;
    }
    if (shards == 0 or shard >= shards) return error.InvalidTestShard;
    if (builtin.test_functions.len == 0) {
        std.debug.print("No matching native tests; check the filter and suite imports.\n", .{});
        std.process.exit(1);
    }
    const started = std.Io.Clock.Timestamp.now(init.io, .awake);
    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var leaks: usize = 0;
    var selected: usize = 0;
    for (builtin.test_functions, 0..) |test_fn, index| {
        if (index % shards != shard) continue;
        var has_selection = false;
        var matches = false;
        for (args[1..]) |arg| {
            if (!std.mem.startsWith(u8, arg, "--test=")) continue;
            has_selection = true;
            if (std.mem.eql(u8, test_fn.name, arg[7..])) matches = true;
        }
        if (has_selection and !matches) continue;
        selected += 1;
        if (list) {
            try std.Io.File.stdout().writeStreamingAll(init.io, test_fn.name);
            try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
            continue;
        }
        const test_started = std.Io.Clock.Timestamp.now(init.io, .awake);
        const errors_before = logged_errors;
        var test_leaks: usize = 0;
        var status: enum { passed, skipped, failed } = .passed;
        policy.counts = .{};
        {
            testing.allocator_instance = .init(std.heap.page_allocator, .{
                .canary = 0xc3a701ba,
                .check_write_after_free = true,
            });
            testing.io_instance = .init(testing.allocator, .{
                .argv0 = .init(init.minimal.args),
                .environ = init.minimal.environ,
            });
            testing.environ = init.minimal.environ;
            testing.log_level = .warn;
            defer {
                testing.io_instance.deinit();
                if (testing.allocator_instance.deinit() != 0) test_leaks += 1;
            }
            std.debug.print("{d}/{d} {s}...", .{ index + 1, builtin.test_functions.len, test_fn.name });
            if (test_fn.func()) |_| {
                passed += 1;
                std.debug.print("OK\n", .{});
            } else |err| {
                if (err == error.SkipZigTest) {
                    skipped += 1;
                    status = .skipped;
                    std.debug.print("SKIP\n", .{});
                } else {
                    failed += 1;
                    status = .failed;
                    std.debug.print("FAIL ({t})\n", .{err});
                    if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
                }
            }
        }
        leaks += test_leaks;
        const test_finished = std.Io.Clock.Timestamp.now(init.io, .awake);
        std.debug.print("BLOT_NATIVE_TEST\t{f}\n", .{std.json.fmt(.{
            .name = test_fn.name,
            .duration_ns = test_finished.raw.nanoseconds - test_started.raw.nanoseconds,
            .status = @tagName(status),
            .leaks = test_leaks,
            .logged_errors = logged_errors - errors_before,
            .allocation_failures = @tagName(policy.fault_mode),
            .sweeps = policy.counts,
        }, .{})});
    }
    if (list) return;
    const finished = std.Io.Clock.Timestamp.now(init.io, .awake);
    std.debug.print("BLOT_NATIVE_SHARD\t{{\"shard\":{d},\"shards\":{d},\"start_ns\":{d},\"end_ns\":{d},\"selected\":{d}}}\n", .{ shard, shards, started.raw.nanoseconds, finished.raw.nanoseconds, selected });
    std.debug.print("Shard {d}/{d}: {d} selected; {d} passed; {d} skipped; {d} failed; {d} leaks; {d} logged errors.\n", .{ shard, shards, selected, passed, skipped, failed, leaks, logged_errors });
    if (failed != 0 or leaks != 0 or logged_errors != 0) std.process.exit(1);
}
