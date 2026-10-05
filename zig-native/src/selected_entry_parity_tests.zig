const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

const entry_cycle = "type Box is data = #Box U32\nconst Box.read = fn value => second\nconst pick = fn value => value.read\nlet second: U32 = second\nentry const answer: Unit -> U32 = fn () => pick (#Box 1)\n";
const entry_valid = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Left.read = fn value => second\nconst Right.read = fn value => first\nconst pick = fn value => value.read\nlet first: U32 = pick (#Left 1)\nlet second: U32 = 42\nentry const answer: Unit -> U32 = fn () => pick (#Left 1)\n";

fn selectedEntry(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try eval.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.options.trace_runtime_dependencies = true;
    const before = session.steps;
    for (module.bodies[1..]) |body| {
        if (!body.exported or !body.is_function) continue;
        var facts = try session.startupDependencies(.{ .unit = 1, .binding = body.binding });
        defer facts.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), facts.selected.len);
        const target = facts.selected[0];
        try std.testing.expectEqual(@as(u32, 1), target.unit);
        try std.testing.expectEqual(module.associated[0].target.binding, target.binding);
    }
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}

fn emit(allocator: std.mem.Allocator, module: *const core.Module, code: ?backend.Code, point: ?u32) !void {
    var artifact = try backend.compile(allocator, &.{module.*}, 1);
    defer artifact.deinit(allocator);
    try std.testing.expectEqual(code, if (artifact.diagnostic) |d| d.code else null);
    if (point) |p| try std.testing.expectEqual(core.Span{ .start = p, .end = p }, artifact.diagnostic.?.span);
    if (code == null) try std.testing.expect(artifact.bytes.len > 8) else try std.testing.expectEqual(@as(usize, 0), artifact.bytes.len);
}

test "startup residual entry selected method owns exact numeric target without runtime values" {
    var module = try lower(a, entry_valid);
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try selectedEntry(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, selectedEntry, .{&module});
    try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
}

test "startup residual entry-only method exposes cell cycle at frozen name point" {
    var module = try lower(a, entry_cycle);
    defer module.deinit(a);
    try emit(a, &module, .initialization_cycle, 104);
}

test "startup residual unselected entry candidate never introduces initializer cycle" {
    var module = try lower(a, entry_valid);
    defer module.deinit(a);
    try emit(a, &module, null, null);
}

test "startup residual selected entry reach remains immutable and releases backend OOM" {
    for ([_][]const u8{ entry_valid, entry_cycle }, [_]?backend.Code{ null, .initialization_cycle }, [_]?u32{ null, 104 }) |source, code, point| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const before = @import("core_snapshot_tests.zig").stamp(module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, code, point });
        try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
    }
}
