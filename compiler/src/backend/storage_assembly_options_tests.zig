const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const Tier = @import("../compilation_tier.zig").Tier;
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModule(a, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn workload() !core.Module {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    for (0..24) |function| {
        const header = try a.print("const f{d} = func (input: U32): U32 => return do:\n  let value = input\n", .{function});
        defer a.free(header);
        try source.appendSlice(a, header);
        const step = try a.print("  value := @u32.add value {d}\n", .{function + 1});
        defer a.free(step);
        for (0..64) |_| try source.appendSlice(a, step);
        try source.appendSlice(a, "  return value\n");
    }
    try source.appendSlice(a, "entry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  let value = marker[0]\n");
    for (0..24) |function| {
        const call = try a.print("  value := f{d} value\n", .{function});
        defer a.free(call);
        try source.appendSlice(a, call);
    }
    try source.appendSlice(a, "  return value\n");
    return lower(source.items);
}

fn compile(module: *const core.Module, tier: Tier, workers: u8, profile: bool) !backend.Result {
    var result = try backend.compileWithOptions(a, &.{module.*}, 1, .{
        .io = std.testing.io,
        .profile_backend = profile,
        .policy = .{ .codegen_tier = tier, .codegen_workers = workers },
    });
    errdefer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(tier, result.runtime_optimization.tier);
    try std.testing.expect(result.runtime_optimization.functions > 0);
    return result;
}

test "owned public compilation forwards tiers workers and profiling" {
    var module = try workload();
    defer module.deinit(a);
    try std.testing.expect(try @import("scoped_backend.zig").required(a, &.{module}, 1));
    for ([_]Tier{ .development, .optimized }) |tier| {
        var serial = try compile(&module, tier, 1, false);
        defer serial.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), serial.runtime_optimization.workers);
        try std.testing.expectEqual(@as(usize, 0), serial.runtime_optimization.parallel_jobs);
        var parallel = try compile(&module, tier, 4, false);
        defer parallel.deinit(a);
        try std.testing.expectEqualSlices(u8, serial.bytes, parallel.bytes);
        try std.testing.expect(parallel.runtime_optimization.workers > 1 and parallel.runtime_optimization.workers <= 4);
        try std.testing.expect(parallel.runtime_optimization.parallel_jobs >= 4);
        try std.testing.expect(parallel.runtime_optimization.worker_timings == null);
        var profiled = try compile(&module, tier, 4, true);
        defer profiled.deinit(a);
        try std.testing.expectEqualSlices(u8, serial.bytes, profiled.bytes);
        const timings = profiled.runtime_optimization.worker_timings orelse return error.TestUnexpectedResult;
        var jobs: usize = 0;
        var instructions: usize = 0;
        var elapsed: u64 = 0;
        for (timings) |timing| {
            try std.testing.expect(timing.finished_us >= timing.started_us);
            jobs += timing.jobs;
            instructions += timing.instructions;
            elapsed += timing.finished_us - timing.started_us;
        }
        try std.testing.expectEqual(profiled.runtime_optimization.parallel_jobs, jobs);
        try std.testing.expect(instructions >= 4096);
        try std.testing.expect(elapsed > 0);
    }
}

test "owned public compilation keeps tiny worker requests serial" {
    var module = try lower("entry const answer = func (input: U32): U32 => return do:\n  let rows: GrowArray U32 = #[input]\n  return rows[0]\n");
    defer module.deinit(a);
    for ([_]Tier{ .development, .optimized }) |tier| {
        var result = try compile(&module, tier, 4, true);
        defer result.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), result.runtime_optimization.workers);
        try std.testing.expectEqual(@as(usize, 0), result.runtime_optimization.parallel_jobs);
        try std.testing.expect(result.runtime_optimization.worker_timings == null);
    }
}

test "owned public compilation forwards physical machine code sharing" {
    var module = try lower(
        \\const left = func (input: U32): U32 => return @u32.add input 7
        \\const right = func (input: U32): U32 => return @u32.add input 7
        \\entry const answer = func (input: U32): U32 => return do:
        \\  let marker: GrowArray U32 = #[input]
        \\  return @u32.add (left marker[0]) (right marker[0])
    );
    defer module.deinit(a);
    var separate = try backend.compileWithOptions(a, &.{module}, 1, .{});
    defer separate.deinit(a);
    var shared = try backend.compileWithOptions(a, &.{module}, 1, .{ .policy = .{ .share_machine_code = true } });
    defer shared.deinit(a);
    try std.testing.expect(separate.diagnostic == null and shared.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), separate.runtime_optimization.shared);
    try std.testing.expect(shared.runtime_optimization.shared > 0);
    try std.testing.expectEqual(shared.runtime_optimization.functions - shared.runtime_optimization.shared, shared.emitted_functions);
    try std.testing.expect(shared.bytes.len < separate.bytes.len);
}
