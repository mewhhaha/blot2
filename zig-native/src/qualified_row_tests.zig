const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

fn compile(allocator: std.mem.Allocator, module: *const core.Module, valid: bool) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (valid) {
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
        try std.testing.expect(result.bytes.len > 8);
    } else {
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(backend.Code.effect_mismatch, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}

test "qualified implementation rows remain distinct from surrounding body effects" {
    for ([_]struct { source: []const u8, valid: bool }{
        .{ .source = @embedFile("qualified-row-fixtures/associated.blot"), .valid = true },
        .{ .source = @embedFile("qualified-row-fixtures/associated-direct.blot"), .valid = true },
        .{ .source = @embedFile("qualified-row-fixtures/reject-effectful.blot"), .valid = false },
        .{ .source = @embedFile("qualified-row-fixtures/reject-pure.blot"), .valid = false },
    }) |case| {
        var module = try lower(a, case.source);
        defer module.deinit(a);
        const nodes = try a.dupe(types.Node, module.types.nodes);
        defer a.free(nodes);
        const extra = try a.dupe(types.Id, module.types.extra);
        defer a.free(extra);
        const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
        defer a.free(labels);
        const operations = try a.dupe(types.Operation, module.types.operations);
        defer a.free(operations);
        try compile(a, &module, case.valid);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, compile, .{ &module, case.valid });
        try std.testing.expectEqualSlices(types.Node, nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
        try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
        try std.testing.expectEqualSlices(types.Operation, operations, module.types.operations);
    }
}

fn checkRows(allocator: std.mem.Allocator, source: []const u8) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

test "qualified source schemes release every failed allocation before implementation specialization" {
    for ([_][]const u8{
        @embedFile("qualified-row-fixtures/associated.blot"),
        @embedFile("qualified-row-fixtures/associated-direct.blot"),
        @embedFile("qualified-row-fixtures/reject-effectful.blot"),
        @embedFile("qualified-row-fixtures/reject-pure.blot"),
    }) |source| {
        try checkRows(a, source);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkRows, .{source});
    }
}
