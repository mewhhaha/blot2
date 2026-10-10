//! In-process checkpoint decode cost for task 019. Copy beside a compiler
//! tree's `src/backend_checkpoint.zig` and build with
//! `zig build-exe -OReleaseFast -fllvm src/portable_queries_decode_probe.zig`.
//!   probe CHECKPOINT COMPILER_HEX ITERATIONS
//! Prints one JSON line: process CPU nanoseconds per decode (sorted samples
//! summarized), requested bytes/allocations of one decode, and record counts.
const std = @import("std");
const checkpoint = @import("backend_checkpoint.zig");
const memory = @import("memory.zig");

fn principalRecords(decoded: anytype) usize {
    const snapshot = decoded.principal.snapshot;
    return if (comptime @hasField(@TypeOf(snapshot), "queries")) snapshot.queries.records.len else snapshot.proofs.len;
}
fn optimizerRecords(decoded: anytype) usize {
    return if (decoded.optimizer) |owner| owner.queries.records.items.len else 0;
}
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) return error.ExpectedCheckpointCompilerAndIterations;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], arena, .limited(64 * 1024 * 1024));
    var compiler: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&compiler, args[2]);
    const iterations = try std.fmt.parseInt(usize, args[3], 10);
    var tracked: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
    const a = tracked.allocator();
    var principal_records: usize = 0;
    var optimizer_records: usize = 0;
    {
        var decoded = try checkpoint.decode(a, compiler, bytes);
        defer decoded.deinit();
        principal_records = principalRecords(&decoded);
        optimizer_records = optimizerRecords(&decoded);
    }
    const once = tracked.counts;
    std.debug.assert(once.live_bytes == 0);
    const samples = try arena.alloc(u64, iterations);
    for (samples) |*sample| {
        const start = std.Io.Clock.cpu_process.now(init.io);
        var decoded = try checkpoint.decode(a, compiler, bytes);
        decoded.deinit();
        sample.* = @intCast(start.durationTo(std.Io.Clock.cpu_process.now(init.io)).toNanoseconds());
    }
    std.mem.sortUnstable(u64, samples, {}, std.sort.asc(u64));
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{
        .checkpoint_bytes = bytes.len,
        .iterations = iterations,
        .p25_ns = samples[iterations / 4],
        .median_ns = samples[iterations / 2],
        .p75_ns = samples[iterations * 3 / 4],
        .min_ns = samples[0],
        .requested_bytes = once.allocated_bytes,
        .allocations = once.allocations,
        .peak_bytes = once.peak_bytes,
        .principal_records = principal_records,
        .optimizer_records = optimizer_records,
    }, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}
