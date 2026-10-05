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

const evaluator = @import("core_eval.zig");
fn entry(module: *const core.Module) core.BindingRef {
    for (module.bodies[1..]) |body| if (std.mem.eql(u8, module.name(body.export_name), "answer")) return .{ .unit = 1, .binding = body.binding };
    unreachable;
}
fn prove(allocator: std.mem.Allocator, module: *const core.Module) !void {
    for ([_]bool{ true, false }) |reuse| {
        var session = try evaluator.Session.init(allocator, &.{module.*});
        defer session.deinit();
        session.options.reuse_validated_calls = reuse;
        for (0..2) |_| {
            var proof = try session.bodyEvidenceFull(entry(module), 0, &.{}, &.{});
            defer proof.deinit(allocator);
            try std.testing.expect(session.diagnostic == null);
            try std.testing.expectEqual(@as(usize, 0), session.steps);
        }
    }
}
fn emit(allocator: std.mem.Allocator, module: *const core.Module, valid: bool) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (valid) {
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
        try std.testing.expect(result.bytes.len > 8);
    } else {
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(backend.Code.missing_member, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}
test "local retained receiver and callback proofs isolate lexical callers with reuse enabled or disabled" {
    for ([_][]const u8{
        @embedFile("captured-callable-fixtures/bound-method.blot"),
        @embedFile("captured-callable-fixtures/bound-cache-nominals.blot"),
        @embedFile("captured-callable-fixtures/bound-cache-effects.blot"),
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const nodes = try a.dupe(types.Node, module.types.nodes);
        defer a.free(nodes);
        const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        try prove(a, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, prove, .{&module});
        try std.testing.expectEqualSlices(types.Node, nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
    }
}
test "retained callable emission every allocation failure preserves source captures types and effects" {
    for ([_]struct { source: []const u8, valid: bool }{
        .{ .source = @embedFile("captured-callable-fixtures/bound-method.blot"), .valid = true },
        .{ .source = @embedFile("captured-callable-fixtures/bound-cache-nominals.blot"), .valid = true },
        .{ .source = @embedFile("captured-callable-fixtures/bound-cache-effects.blot"), .valid = true },
        .{ .source = @embedFile("captured-callable-fixtures/captured-builtin.blot"), .valid = true },
        .{ .source = @embedFile("captured-callable-fixtures/captured-effect.blot"), .valid = true },
        .{ .source = @embedFile("captured-callable-fixtures/bound-cache-missing.blot"), .valid = false },
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
        const core_nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(core_nodes);
        const bindings = try a.dupe(core.Binding, module.bindings);
        defer a.free(bindings);
        const closures = try a.dupe(core.ClosureInfo, module.closures);
        defer a.free(closures);
        try emit(a, &module, case.valid);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, case.valid });
        try std.testing.expectEqualSlices(types.Node, nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
        try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
        try std.testing.expectEqualSlices(types.Operation, operations, module.types.operations);
        try std.testing.expectEqualSlices(core.Node, core_nodes, module.nodes);
        try std.testing.expectEqualSlices(core.Binding, bindings, module.bindings);
        try std.testing.expectEqualSlices(core.ClosureInfo, closures, module.closures);
    }
}

fn retainedRow(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const reference = for (module.bodies[1..]) |body| {
        if (std.mem.eql(u8, module.name(body.export_name), "add_forty")) break core.BindingRef{ .unit = 1, .binding = body.binding };
    } else unreachable;
    const original = try session.richValue(reference);
    const original_header = session.closureInfo(original);
    const before_steps = session.steps;
    const principal = session.valueEvidence(original);
    const selected = try session.inferClosure(original);
    const actual = session.evidence.node(session.valueEvidence(selected));
    try std.testing.expectEqual(.function, actual.tag);
    try std.testing.expectEqual(types.u32_type, actual.a);
    try std.testing.expectEqual(types.u32_type, actual.b);
    try std.testing.expectEqual(@as(u32, 0), actual.c);
    try std.testing.expectEqual(before_steps, session.steps);
    try std.testing.expectEqual(principal, session.valueEvidence(original));
    try std.testing.expectEqual(original_header, session.closureInfo(original));
    try std.testing.expectEqual(@as(u32, 40), session.valueScalar(session.valueChildren(selected)[0]).?.bits);
}
test "retained captured closure own row inference executes no source and preserves the principal alias" {
    var module = try lower(a, @embedFile("captured-callable-fixtures/captured-builtin.blot"));
    defer module.deinit(a);
    try retainedRow(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedRow, .{&module});
}
