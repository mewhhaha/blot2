const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const types = @import("../check/types.zig");
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn emitScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "request backend frozen Core teardown and every allocation failure preserve owners and types" {
    const a = std.testing.allocator;
    const sources = [_][]const u8{
        @import("fixtures").source("request-fixtures/suspended.blot"),
        @import("fixtures").source("request-fixtures/mixed-cancel.blot"),
        @import("fixtures").source("request-fixtures/nested-owner.blot"),
        @import("fixtures").source("request-fixtures/function-state.blot"),
        @import("fixtures").source("request-fixtures/template-local-state-typed-scopes.blot"),
        @import("fixtures").source("request-fixtures/template-factory-demand.blot"),
        @import("fixtures").source("request-fixtures/template-nested-captured-factory.blot"),
        @import("fixtures").source("request-fixtures/template-local-f32-discard.blot"),
        @import("fixtures").source("request-fixtures/template-local-snapshot.blot"),
        @import("fixtures").source("request-fixtures/template-local-effects.blot"),
        @import("fixtures").source("request-fixtures/template-local-factory.blot"),
        @import("fixtures").source("request-fixtures/f32-foreign-nested.blot"),
        @import("fixtures").source("request-fixtures/template-delegated.blot"),
        @import("fixtures").source("request-fixtures/template-unsupported.blot"),
        @import("fixtures").source("request-fixtures/template-wrapped-action.blot"),
        @import("fixtures").source("request-fixtures/template-effect-bottom.blot"),
        @import("fixtures").source("request-fixtures/template-effects.blot"),
        @import("fixtures").source("request-fixtures/template-snapshot.blot"),
        @import("fixtures").source("request-fixtures/template-wrapped-reuse.blot"),
        @import("fixtures").source("request-fixtures/template-reuse.blot"),
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const type_nodes = try a.dupe(types.Node, module.types.nodes);
        defer a.free(type_nodes);
        const type_extra = try a.dupe(types.Id, module.types.extra);
        defer a.free(type_extra);
        const effect_rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(effect_rows);
        const effect_labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
        defer a.free(effect_labels);
        const operations = try a.dupe(types.Operation, module.types.operations);
        defer a.free(operations);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const bindings = try a.dupe(core.Binding, module.bindings);
        defer a.free(bindings);
        const closures = try a.dupe(core.ClosureInfo, module.closures);
        defer a.free(closures);
        const loops = try a.dupe(core.RequestLoopInfo, module.request_loops);
        defer a.free(loops);
        const arms = try a.dupe(core.RequestArm, module.request_arms);
        defer a.free(arms);
        const extra = try a.dupe(u32, module.extra);
        defer a.free(extra);
        try emitScenario(a, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{&module});
        try std.testing.expectEqualSlices(types.Node, type_nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Id, type_extra, module.types.extra);
        try std.testing.expectEqualSlices(types.Effects.Row, effect_rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, effect_labels, module.types.effects.labels);
        try std.testing.expectEqualSlices(types.Operation, operations, module.types.operations);
        try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
        try std.testing.expectEqualSlices(core.Binding, bindings, module.bindings);
        try std.testing.expectEqualSlices(core.ClosureInfo, closures, module.closures);
        try std.testing.expectEqualSlices(core.RequestLoopInfo, loops, module.request_loops);
        try std.testing.expectEqualSlices(core.RequestArm, arms, module.request_arms);
        try std.testing.expectEqualSlices(u32, extra, module.extra);
    }
}
