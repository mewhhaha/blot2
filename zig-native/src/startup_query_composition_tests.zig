const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
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
    var module = try lower("const keep = fn ~(value: Unit -> U32) => value\nconst helper = fn () => 42\nconst pending = keep helper\nentry const answer = 42\n");
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
    try std.testing.expect(session.source_suspensions.items.len != 0);
    try std.testing.expect(session.suspensionCached(pending) == null);
    const source = session.source_suspensions.items[0];
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
    var module = try lower("const keep = fn ~(value: Unit -> U32) => value\nconst helper = fn () => 42\nconst pending = keep helper\nentry const answer = 42\n");
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
    try std.testing.expectEqual(@as(usize, 0), session.specialization_receipts.items.len);
}
