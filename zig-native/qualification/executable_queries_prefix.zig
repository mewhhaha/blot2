//! Qualification against the frozen task-018 library: a real published prefix
//! must never authorize reuse after a later record saturates the whole table.
const std = @import("std");
const wasm = @import("wasm.zig");
const optimized = @import("optimized_bodies.zig");
const retained = @import("retained_revision.zig");
const memory = @import("memory.zig");
const A = std.mem.Allocator;

fn require(value: bool) !void {
    if (!value) return error.QualificationFailed;
}

fn optimizerPrefix(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    for (0..2) |ordinal| {
        const id = try module.addFunction(&.{.i32}, .i32);
        try module.emitSlice(id, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = @intCast(ordinal) }, .{ .op = .i32_add } });
    }
    var old: optimized.Capture = .{ .allocator = a };
    defer old.deinit();
    old.queries.limits.records = 1;
    const before = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(before);
    try require(old.queries.records.items.len == 1 and !old.queries_complete);
    try require(old.entries.items[0].output_ready and old.entries.items[1].output_ready);
    var current: optimized.Capture = .{ .allocator = a };
    defer current.deinit();
    var stats: optimized.Stats = .{};
    const next = try module.assembleWithOptions(.{ .previous = &old, .current = &current, .stats = &stats });
    defer a.free(next);
    try require(stats.reused == 0 and stats.optimized == 2);
    try require(std.mem.eql(u8, before, next));
    var matcher = try optimized.Matcher.init(a, &old, &current);
    defer matcher.deinit();
    try require(!matcher.matches(0) and !matcher.matches(1));
}

fn fragmentPrefix(a: A, io: std.Io, entry: []const u8) !void {
    const original = try std.Io.Dir.cwd().readFileAlloc(io, entry, a, .limited(1024 * 1024));
    defer a.free(original);
    const changed = try a.dupe(u8, original);
    defer a.free(changed);
    const prefix = "const changed = ";
    const point = std.mem.find(u8, changed, prefix) orelse return error.MissingEditPoint;
    changed[point + prefix.len] = '3';
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var population = try session.prepareRevisionWithSources(io, entry, null, .{}, &.{.{ .path = entry, .contents = original }});
    defer population.deinit();
    const first = switch (population) {
        .ready => |candidate| candidate,
        .rejected => return error.UnexpectedRejection,
    };
    try require(session.commit(first));
    const capture = &session.current.?.artifacts;
    try require(capture.executable_queries_complete and capture.executable_queries.records.items.len > 1);
    capture.executable_queries.deinit(a);
    capture.executable_queries = .{ .limits = .{ .records = 1 } };
    capture.executable_queries_complete = false;
    try capture.sealExecutableQueries();
    try require(capture.executable_queries.records.items.len == 1 and !capture.executable_queries_complete);
    var edited = try session.prepareRevisionWithSources(io, entry, null, .{}, &.{.{ .path = entry, .contents = changed }});
    defer edited.deinit();
    const result = switch (edited) {
        .ready => |candidate| candidate.result().?.result.compiled,
        .rejected => return error.UnexpectedRejection,
    };
    try require(result.reuse.reused_named == 0 and result.reuse.reused_closures == 0);
    var fresh = try retained.Session.initEmpty(a, .{});
    defer fresh.deinit();
    var rebuilt = try fresh.prepareRevisionWithSources(io, entry, null, .{}, &.{.{ .path = entry, .contents = changed }});
    defer rebuilt.deinit();
    const expected = switch (rebuilt) {
        .ready => |candidate| candidate.result().?.result.compiled,
        .rejected => return error.UnexpectedRejection,
    };
    try require(std.mem.eql(u8, expected.bytes, result.bytes));
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedPositiveFixtureEntry;
    var tracked: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
    try optimizerPrefix(tracked.allocator());
    try require(tracked.counts.live_bytes == 0);
    try fragmentPrefix(tracked.allocator(), init.io, args[1]);
    try require(tracked.counts.live_bytes == 0);
    std.debug.print("{{\"optimizer_partial_records\":1,\"fragment_partial_records\":1,\"optimizer_reused\":0,\"fragment_reused\":0,\"fresh_wasm_parity\":true,\"teardown_live_bytes\":0}}\n", .{});
}
