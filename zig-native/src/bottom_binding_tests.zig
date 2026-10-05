const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn lower() !core.Module {
    const source = @embedFile("bottom_bindings.blot");
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &names);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

test "diverging binding initializers never destructure or fall through and preserve frozen Core under every allocation failure" {
    var module = try lower();
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const typed = try a.dupe(types.Node, module.types.nodes);
    defer a.free(typed);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
    defer a.free(labels);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
    try std.testing.expectEqualSlices(types.Node, typed, module.types.nodes);
    try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
    try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
}
