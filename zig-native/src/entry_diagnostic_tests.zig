const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const scalar_ops = @import("scalar_ops.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const code_expectation = @import("code_expectation.zig");
const types = @import("types.zig");
const type_evidence = @import("type_evidence.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    return lowerWithOptions(source, .{});
}

fn lowerWithOptions(source: []const u8, options: checker.ModuleOptions) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, 1, options);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("check:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    for (module.diagnostics) |diagnostic| std.debug.print("core:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = if (module.unit == 0) 1 else module.unit, .binding = body.binding };
    unreachable;
}

const generic_source =
    \\const identity = fn value => value
    \\entry const direct = fn value => value
    \\entry const alias = identity
    \\entry const update = fn value => do:
    \\  value.lower := 42
    \\  return value
    \\const maker = fn captured => fn (value: U32) => @u32.add captured value
    \\entry const selected = maker 21
    \\entry const closed = fn (value: U32) => value
    \\const hidden = fn captured => fn value => captured
    \\entry const unclosed_capture = hidden (fn value => value)
    \\entry const unresolved_body = fn value => do:
    \\  let deferred = fn owner => owner.missing
    \\  return (deferred value, value)
;
fn entryInferenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "direct", "alias", "update" }) |name| {
        const raw = try session.richValue(target(module, name));
        const evidence = session.valueEvidence(raw);
        const before = session.steps;
        const value_count = session.values.items.len;
        const cached_count = session.specialized_closures.count();
        try std.testing.expectEqual(@as(?evaluator.ValueId, null), try session.inferEntryClosure(raw));
        try std.testing.expectEqual(before, session.steps);
        try std.testing.expectEqual(evidence, session.valueEvidence(raw));
        try std.testing.expectEqual(value_count, session.values.items.len);
        try std.testing.expectEqual(cached_count, session.specialized_closures.count());
        try std.testing.expectEqual(@as(?evaluator.ValueId, null), try session.inferEntryClosure(raw));
        try std.testing.expect(session.diagnostic == null);
        if (session.inferClosure(raw)) |_| return error.TestUnexpectedResult else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code),
            error.RequestUnwind => return error.TestUnexpectedResult,
        }
        session.diagnostic = null;
    }
    for ([_][]const u8{ "selected", "closed" }) |name| {
        const raw = try session.richValue(target(module, name));
        const before = session.steps;
        const selected = (try session.inferEntryClosure(raw)) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(before, session.steps);
        try std.testing.expectEqual(selected, try session.inferClosure(raw));
        try std.testing.expectEqual(selected, (try session.inferEntryClosure(raw)).?);
        const arrow = session.evidenceView().node(session.valueEvidence(selected));
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(types.u32_type, arrow.a);
        try std.testing.expectEqual(types.u32_type, arrow.b);
        try std.testing.expectEqual(@as(u32, 0), arrow.c);
    }
    for ([_][]const u8{ "unclosed_capture", "unresolved_body" }) |name| {
        const raw = try session.richValue(target(module, name));
        const before = session.steps;
        if (session.inferEntryClosure(raw)) |selected| {
            std.debug.print("unexpected entry proof {s}: {?d}\n", .{ name, selected });
            return error.TestUnexpectedResult;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code),
            error.RequestUnwind => return error.TestUnexpectedResult,
        }
        try std.testing.expectEqual(before, session.steps);
        session.diagnostic = null;
    }
}
test "generic export interfaces preserve strict body and captured proofs without publishing headers" {
    var module = try lowerWithOptions(generic_source, .{ .builtin_catalog = true });
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    try entryInferenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, entryInferenceScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(bindings, module.bindings);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
}

fn anonymousRecordScenario(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{
        "entry const x = { lower: 0 }\n",
        "const lower = 0\nentry const x = { lower }\n",
        "entry const x = ({ lower: missing }).lower\n",
        "entry const answer = ({ lower: 42 }).lower\n",
        "entry const x = #Missing { lower: 0 }\n",
        "type Box is data = #Box { lower: U32 }\nentry const x = (#Box { lower: 42 }).lower\n",
    }, 0..) |source, index| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer syntax.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
        var checked = try checker.check(allocator, &syntax, &pool);
        defer checked.deinit(allocator);
        if (index == 5) {
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        } else {
            try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
            try std.testing.expectEqual(if (index == 4) checker.Code.unknown_constructor else checker.Code.unsupported_expression, checked.diagnostics[0].code);
            if (index < 4) {
                const opening = std.mem.indexOfScalar(u8, source, '{').?;
                try std.testing.expectEqual(@as(u32, @intCast(opening)), checked.diagnostics[0].span.start);
                try std.testing.expectEqual(checked.diagnostics[0].span.start, checked.diagnostics[0].span.end);
            }
        }
    }
}
test "anonymous record rejection precedes children and preserves named constructor checks" {
    try anonymousRecordScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, anonymousRecordScenario, .{});
}
