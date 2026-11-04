const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const eval = @import("../eval/core_eval.zig");
const receipts = @import("specialization_receipt.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    result.unit = 1;
    return result;
}

fn checkedHeaderQuery(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const refinement = @import("refinement_receipt.zig");
    var context = @import("code_artifacts.zig").Context.init(allocator);
    defer context.deinit();
    const Consumer = struct {
        allocator: std.mem.Allocator,
        evaluator: eval.Session,
        refinement_owner: ?*@import("code_artifacts.zig").Context,
        refinement_stats: refinement.Stats = .{},
    };
    var g: Consumer = .{ .allocator = allocator, .evaluator = try eval.Session.init(allocator, &.{module.*}), .refinement_owner = &context };
    defer g.evaluator.deinit();
    var expected = try @import("code_expectation.zig").Store.init(allocator);
    defer expected.deinit();
    const delayed = try expected.intern(.function, 1, 3, &.{});
    const callback = try expected.intern(.function, delayed, 3, &.{});
    const signature = try expected.intern(.function, callback, 3, &.{});
    const target: core.BindingRef = .{ .unit = 1, .binding = module.bodies[1].binding };
    var tape: receipts.Tape = .{};
    defer tape.deinit(allocator);
    var observed: refinement.Observation = .{};
    g.evaluator.receipt_tape = &tape;
    g.evaluator.refinement_observation = &observed;
    const before = .{ g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps };
    var solved = try g.evaluator.bodyEvidencePartialFullCode(target, expected.view(), signature, &.{}, &.{}, null);
    defer solved.deinit(allocator);
    g.evaluator.receipt_tape = null;
    g.evaluator.refinement_observation = null;
    try std.testing.expectEqual(@as(usize, 1), observed.regions);
    try std.testing.expect(observed.complete);
    try std.testing.expect(tape.collected != 0);
    try std.testing.expect(!tape.unknown and !tape.nested);
    try std.testing.expectEqual(before, .{ g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps });
    try refinement.record(&g, .{ .body = target }, signature, &.{}, &.{}, solved, &tape, observed, before[0], before[1], before[2]);
    try std.testing.expectEqual(@as(usize, 1), context.refinement_queries.records.items.len);
    var hit = (try refinement.lookupLocal(&g, .{ .body = target }, signature, &.{}, &.{})) orelse return error.TestUnexpectedResult;
    defer hit.deinit(allocator);
    try std.testing.expectEqualDeep(solved, hit);
    try std.testing.expectEqual(before, .{ g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps });
}
