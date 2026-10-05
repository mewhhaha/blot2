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

fn compile(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

test "callback use rows compose Foreign and handled effects without changing frozen evidence" {
    for ([_][]const u8{
        @embedFile("callback-fixtures/parameter.blot"),
        @embedFile("callback-fixtures/record.blot"),
        @embedFile("callback-fixtures/capture.blot"),
        @embedFile("callback-fixtures/factory.blot"),
    }) |source| {
        var module = try lower(a, source);
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
        try compile(a, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, compile, .{&module});
        try std.testing.expectEqualSlices(types.Node, nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
        try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
        try std.testing.expectEqualSlices(types.Operation, operations, module.types.operations);
    }
}

fn checkRows(allocator: std.mem.Allocator, source: []const u8, valid: bool) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    if (valid) {
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    } else {
        try std.testing.expect(checked.diagnostics.len > 0);
        try std.testing.expectEqual(check.Code.effect_mismatch, checked.diagnostics[0].code);
    }
}

test "callback row checking releases every failed allocation and preserves pure requirements" {
    const valid = @embedFile("callback-fixtures/record.blot");
    const invalid = "const invoke: (Unit -> F32) -> F32 = fn callback => callback ()\nentry const answer = fn (host:Unit -> F32 ! {Foreign}) => invoke host\n";
    try checkRows(a, valid, true);
    try checkRows(a, invalid, false);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkRows, .{ valid, true });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkRows, .{ invalid, false });
}
