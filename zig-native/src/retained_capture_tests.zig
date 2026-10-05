const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &tree, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
const evaluator = @import("core_eval.zig");
const code_expectation = @import("code_expectation.zig");

fn expectDeclined(allocator: std.mem.Allocator, result: evaluator.Error!evaluator.SolvedEvidence) !void {
    if (result) |value| {
        var unexpected = value;
        unexpected.deinit(allocator);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.Declined => {},
        else => return err,
    }
}
fn captureProofScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const source = @embedFile("retained-state-fixtures/state-annotation-scopes.blot");
    var catalog: ?u32 = null;
    var witness: core.Id = 0;
    var other: core.Id = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag != .reference) continue;
        const span = module.span(@intCast(index));
        const spelling = source[span.start..span.end];
        if (std.mem.eql(u8, spelling, "witness32")) witness = @intCast(index);
        if (std.mem.eql(u8, spelling, "witnessf")) other = @intCast(index);
    }
    for (module.closures, 0..) |closure, index| {
        const span = module.span(closure.body);
        if (closure.captures.len == 1 and std.mem.eql(u8, source[span.start..span.end], "@state.get witness")) {
            catalog = @intCast(index);
            break;
        }
    }
    try std.testing.expect(catalog != null and witness != 0 and other != 0);
    const closure = module.closures[catalog.?];
    const binding = module.extra[closure.captures.start];
    var expected = try code_expectation.Store.init(allocator);
    defer expected.deinit();
    const identity = module.nominals[1].identity;
    const cell = try expected.intern(.nominal, identity.unit, identity.decl, &.{types.u32_type});
    const shape = try expected.intern(.function, types.unit, cell, &.{});
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const row = module.types.row(module.types.node(closure.function_type).c);
    const concrete_cell = try session.evidence.intern(.nominal, identity.unit, identity.decl, &.{types.u32_type});
    const state_read = try session.evidence.effects.internOperation(types.builtin_state_read, &.{concrete_cell});
    const selected_row = try session.evidence.effects.internRow(&.{state_read});
    const row_seeds: []const @import("type_evidence.zig").RowMapping = if (row.tail == .variable) &.{.{ .variable = row.tail.variable, .evidence = if (row.labels.len == 0) selected_row else 0 }} else &.{};
    try expectDeclined(allocator, session.closureEvidencePartialFull(1, catalog.?, expected.view(), shape, &.{}, row_seeds));
    try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code);
    session.diagnostic = null;
    const hint: evaluator.RetainedCapture = .{ .binding = binding, .unit = 1, .node = witness };
    var proof = try session.closureEvidencePartialCaptures(1, catalog.?, expected.view(), shape, &.{}, row_seeds, &.{hint});
    defer proof.deinit(allocator);
    try std.testing.expectError(error.UnresolvedType, session.evidence.projectWithRows(&module.types, module.binding(binding).ty, proof.types, proof.rows));
    try std.testing.expectEqual(@as(usize, 0), session.proofs.proof_published);
    const actual = try session.evidence.projectWithRows(&module.types, closure.function_type, proof.types, proof.rows);
    const arrow = session.evidence.node(actual);
    try std.testing.expectEqual(types.unit, arrow.a);
    const result = session.evidence.node(arrow.b);
    try std.testing.expectEqual(.nominal, result.tag);
    try std.testing.expectEqual(identity.unit, result.a);
    try std.testing.expectEqual(identity.decl, result.b);
    try std.testing.expectEqualSlices(u32, &.{types.u32_type}, session.evidence.children(arrow.b));
    const effects = session.evidence.view().effects;
    const labels = effects.rowLabels(arrow.c);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    const operation = effects.operation(labels[0]);
    try std.testing.expectEqual(types.builtin_state_read, operation.identity);
    try std.testing.expectEqualSlices(u32, &.{arrow.b}, effects.operationArguments(labels[0]));
    session.diagnostic = null;
    const wrong: evaluator.RetainedCapture = .{ .binding = binding, .unit = 1, .node = other };
    try expectDeclined(allocator, session.closureEvidencePartialCaptures(1, catalog.?, expected.view(), shape, &.{}, row_seeds, &.{wrong}));
    try std.testing.expectEqual(evaluator.Code.type_mismatch, session.diagnostic.?.code);
    session.diagnostic = null;
    try expectDeclined(allocator, session.closureEvidencePartialCaptures(1, catalog.?, expected.view(), shape, &.{}, row_seeds, &.{ hint, wrong }));
    try std.testing.expectEqual(evaluator.Code.type_mismatch, session.diagnostic.?.code);
    const invalid: evaluator.RetainedCapture = .{ .binding = closure.parameter.binding, .unit = 1, .node = witness, .values = &.{.{ .binding = binding, .evidence = types.u32_type }} };
    try expectDeclined(allocator, session.closureEvidencePartialCaptures(1, catalog.?, expected.view(), shape, &.{}, row_seeds, &.{invalid}));
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}
test "retained State capture proof preserves exact nominal operation without witness evaluation" {
    const allocator = std.testing.allocator;
    var module = try lower(allocator, @embedFile("retained-state-fixtures/state-annotation-scopes.blot"));
    defer module.deinit(allocator);
    try captureProofScenario(allocator, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, captureProofScenario, .{&module});
}
fn emitScenario(allocator: std.mem.Allocator, module: *const core.Module, succeeds: bool) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (succeeds) {
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
        try std.testing.expect(result.bytes.len > 8);
    } else {
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}
test "retained State callable backend every allocation failure preserves frozen Core and semantic types" {
    const a = std.testing.allocator;
    const sources = [_][]const u8{
        @embedFile("retained-state-fixtures/state-annotation-scopes.blot"),
        @embedFile("retained-state-fixtures/local-aliases.blot"),
        @embedFile("retained-state-fixtures/local-snapshots-called.blot"),
        @embedFile("retained-state-fixtures/latent-never-called.blot"),
        @embedFile("retained-state-fixtures/local-initializer-effects.blot"),
        @embedFile("retained-state-fixtures/state-annotation-shared.blot"),
        @embedFile("retained-state-fixtures/where-annotation-scope.blot"),
        @embedFile("retained-state-fixtures/unmet-qualifier.blot"),
    };
    for (sources, 0..) |source, index| {
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
        const succeeds = index != sources.len - 1;
        try emitScenario(a, &module, succeeds);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &module, succeeds });
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
