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

test "source suspension creation and lookup remain outside completed specialization receipts" {
    var module = try lower("const keep = func ~(value: Unit -> U32) => return value\nconst helper = func () => return 42\nconst pending = keep helper\nentry const answer = 42\n");
    defer module.deinit(a);
    const units = [_]core.Module{module};
    var session = try eval.Session.init(a, &units);
    defer session.deinit();
    session.options.retain_source_suspensions = true;
    const target: core.BindingRef = for (module.bodies[1..]) |body| {
        if (!body.is_function and module.types.node(body.scheme.root).tag == .demand) break .{ .unit = 1, .binding = body.binding };
    } else return error.MissingWaitingSource;
    var tape: receipts.Tape = .{};
    defer tape.deinit(a);
    session.receipt_tape = &tape;
    defer session.receipt_tape = null;
    const pending = try session.richValue(target);
    try std.testing.expect(tape.unknown);
    try std.testing.expect(session.retained.source_suspensions.items.len != 0);
    try std.testing.expect(session.suspensionCached(pending) == null);
    const source = session.retained.source_suspensions.items[0];
    tape.unknown = false;
    try std.testing.expectEqual(source.value, session.singleSourceSuspension(source.producer, source.unit, source.node).?);
    try std.testing.expect(tape.unknown);
    tape.unknown = false;
    try std.testing.expect(session.singleSourceSuspension(source.producer, source.unit, std.math.maxInt(u32)) == null);
    try std.testing.expect(tape.unknown);
    session.receipt_tape = null;
    tape.unknown = false;
    try std.testing.expectEqual(source.value, session.singleSourceSuspension(source.producer, source.unit, source.node).?);
    try std.testing.expect(!tape.unknown);
}

test "full suspension inference and its same-session cache hit both invalidate a specialization tape" {
    var module = try lower("const keep = func ~(value: Unit -> U32) => return value\nconst helper = func () => return 42\nconst pending = keep helper\nentry const answer = 42\n");
    defer module.deinit(a);
    const units = [_]core.Module{module};
    var session = try eval.Session.init(a, &units);
    defer session.deinit();
    const target: core.BindingRef = for (module.bodies[1..]) |body| {
        if (!body.is_function and module.types.node(body.scheme.root).tag == .demand) break .{ .unit = 1, .binding = body.binding };
    } else return error.MissingWaitingSource;
    const pending = try session.richValue(target);
    var tape: receipts.Tape = .{};
    defer tape.deinit(a);
    session.receipt_tape = &tape;
    defer session.receipt_tape = null;
    const selected = try session.inferSuspension(pending);
    try std.testing.expect(tape.nested);
    try std.testing.expect(session.suspensionCached(pending) == null);
    try std.testing.expect(session.suspensionCached(selected) == null);
    const before = session.steps;
    tape.nested = false;
    try std.testing.expectEqual(selected, try session.inferSuspension(pending));
    try std.testing.expect(tape.nested);
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expectEqual(@as(usize, 0), session.retained.specialization_receipts.items.len);
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
    const demand = try expected.intern(.demand, 3, 0, &.{});
    const callback = try expected.intern(.function, demand, 3, &.{});
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

test "checked suspension header refinement owns no producer execution and survives every allocation failure" {
    var module = try lower("const call_lazy = func (transform: ~U32 -> U32) => return transform 21\n");
    defer module.deinit(a);
    var found = false;
    for (module.nodes) |node| found = found or node.tag == .suspend_;
    try std.testing.expect(found);
    try checkedHeaderQuery(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkedHeaderQuery, .{&module});
}
