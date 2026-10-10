//! Retained-revision metadata cost for task 021. Copy beside a compiler tree's
//! `src/retained_revision.zig` and build with
//! `zig build-exe -OReleaseFast -fllvm src/revision_deltas_probe.zig`.
//!   probe ENTRY PRELUDE STD_ROOT SEARCH REPLACE ROUNDS
//! Each round runs edit, revert, a rejected edit and a no-op correction after
//! one population.
//! Prints one JSON line per phase: requested bytes, allocations, peak and
//! retained live requested bytes, process CPU, Wasm digest and work counters.
const std = @import("std");
const retained = @import("retained_revision.zig");
const memory = @import("memory.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 7) return error.ExpectedEntryPreludeStdSearchReplaceRounds;
    const original = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], arena, .limited(1024 * 1024));
    const edited = try std.mem.replaceOwned(u8, arena, original, args[4], args[5]);
    if (std.mem.eql(u8, edited, original)) return error.EditNotFound;
    const rounds = try std.fmt.parseInt(usize, args[6], 10);
    const broken = try std.mem.concat(arena, u8, &.{ original, "\nconst broken_probe: U32 = #Wrong\n" });
    const options: @import("project.zig").Options = .{ .prelude_path = args[2], .std_root = args[3] };
    var tracked: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
    var buffer: [1 << 16]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    {
        var session = try retained.Session.initEmpty(tracked.allocator(), options);
        defer session.deinit();
        for (0..rounds) |round| {
            const phases = [_][]const u8{ "population", "edit", "revert", "failed", "noop" };
            for (phases, 0..) |phase, step| {
                if (step == 0 and round != 0) continue;
                const text = switch (step) {
                    1 => edited,
                    3 => broken,
                    else => original,
                };
                const before = tracked.counts;
                tracked.counts.peak_bytes = tracked.counts.live_bytes;
                const cpu = std.Io.Clock.cpu_process.now(init.io);
                var prepared = try session.prepareRevisionWithSources(init.io, args[1], null, options, &.{.{ .path = args[1], .contents = text }});
                const candidate = switch (prepared) {
                    .ready => |candidate| candidate,
                    .rejected => {
                        prepared.deinit();
                        if (step != 3) return error.UnexpectedRejectedRevision;
                        try std.json.Stringify.value(.{
                            .round = round,
                            .phase = phase,
                            .reused_output = false,
                            .cpu_ns = @as(u64, @intCast(cpu.durationTo(std.Io.Clock.cpu_process.now(init.io)).toNanoseconds())),
                            .requested_bytes = tracked.counts.allocated_bytes - before.allocated_bytes,
                            .allocations = tracked.counts.allocations - before.allocations,
                            .peak_bytes = tracked.counts.peak_bytes,
                            .retained_live_bytes = tracked.counts.live_bytes,
                            .wasm = "rejected",
                            .snapshot_copy_bytes = 0,
                            .metadata_shared_bytes = 0,
                            .metadata_copied_bytes = 0,
                            .metadata_shared_fields = 0,
                            .metadata_copied_fields = 0,
                            .reused_named = 0,
                            .reused_closures = 0,
                            .reused_scalar_constants = 0,
                            .reused_aggregate_constants = 0,
                        }, .{}, &writer.interface);
                        try writer.interface.writeByte('\n');
                        continue;
                    },
                };
                if (step == 3) return error.ExpectedRejectedRevision;
                const compiled = candidate.result().?.result.compiled;
                var digest: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(compiled.bytes, &digest, .{});
                const counters = compiled.counters;
                const reuse = compiled.reuse;
                const reused = candidate.stats.reused_output;
                if (!session.commit(candidate)) return error.CommitFailed;
                candidate.deinit();
                const cpu_ns: u64 = @intCast(cpu.durationTo(std.Io.Clock.cpu_process.now(init.io)).toNanoseconds());
                try std.json.Stringify.value(.{
                    .round = round,
                    .phase = phase,
                    .reused_output = reused,
                    .cpu_ns = cpu_ns,
                    .requested_bytes = tracked.counts.allocated_bytes - before.allocated_bytes,
                    .allocations = tracked.counts.allocations - before.allocations,
                    .peak_bytes = tracked.counts.peak_bytes,
                    .retained_live_bytes = tracked.counts.live_bytes,
                    .wasm = std.fmt.bytesToHex(digest, .lower),
                    .snapshot_copy_bytes = counters.snapshot_copy_bytes,
                    .metadata_shared_bytes = if (@hasField(@TypeOf(counters), "metadata_shared_bytes")) counters.metadata_shared_bytes else 0,
                    .metadata_copied_bytes = if (@hasField(@TypeOf(counters), "metadata_copied_bytes")) counters.metadata_copied_bytes else 0,
                    .metadata_shared_fields = if (@hasField(@TypeOf(counters), "metadata_shared_fields")) counters.metadata_shared_fields else 0,
                    .metadata_copied_fields = if (@hasField(@TypeOf(counters), "metadata_copied_fields")) counters.metadata_copied_fields else 0,
                    .reused_named = reuse.reused_named,
                    .reused_closures = reuse.reused_closures,
                    .reused_scalar_constants = reuse.reused_scalar_constants,
                    .reused_aggregate_constants = if (@hasField(@TypeOf(reuse), "reused_aggregate_constants")) reuse.reused_aggregate_constants else 0,
                }, .{}, &writer.interface);
                try writer.interface.writeByte('\n');
            }
        }
    }
    try writer.interface.flush();
    if (tracked.counts.live_bytes != 0) return error.TeardownLeak;
}
