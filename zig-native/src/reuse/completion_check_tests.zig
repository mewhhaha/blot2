const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const probe = @import("completion_probe.zig");

fn expressionLaw(a: std.mem.Allocator) !void {
    const source =
        \\const unfinished = func (value: U32) : F32 => return do:
        \\  let original = value
        \\  value := true
        \\  break fi
    ;
    const cursor = (try probe.capture(a, source, @intCast(source.len))).?;
    defer cursor.deinit(a);
    var tokens = try lexer.lex(a, cursor.source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, cursor.source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .editor = .{ .span = cursor.marker, .kind = cursor.kind } });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const context = checked.editor.?.context.?;
    try std.testing.expectEqual(.f32, context.nodes[context.expected].kind);
    try std.testing.expectEqualStrings("value", context.scope[0].name);
    try std.testing.expectEqual(.boolean, context.nodes[context.scope[0].type].kind);
    try std.testing.expectEqualStrings("original", context.scope[1].name);
    try std.testing.expectEqual(.u32, context.nodes[context.scope[1].type].kind);
}

test "completion private expression keeps contextual types shadowing and allocation ownership" {
    try expressionLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, expressionLaw, .{});
}

test "completion private members and selectors retain receiver and expected arrow" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "type Point = { x: U32, y: F32 }\nconst work = func (point: Point) : F32 => return point.y\n",
        "type Point = { x: U32, y: F32 }\nconst work: Point -> F32 = .y\n",
    }) |source| {
        const position = std.mem.findLast(u8, source, "y").? + 1;
        const cursor = (try probe.capture(a, source, @intCast(position))).?;
        defer cursor.deinit(a);
        var tokens = try lexer.lex(a, cursor.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, cursor.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .editor = .{ .span = cursor.marker, .kind = cursor.kind } });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const captured = checked.editor.?;
        const receiver = try checked.types.resolve(captured.receiver, 0);
        try std.testing.expectEqual(.record, checked.types.node(receiver).tag);
        const context = captured.context.?;
        if (cursor.kind == .selector) {
            try std.testing.expectEqual(.function, context.nodes[context.expected].kind);
        } else {
            try std.testing.expectEqual(.f32, context.nodes[context.expected].kind);
        }
    }
}

test "completion private fitting follows actual declared generic requirements" {
    const a = std.testing.allocator;
    const source =
        \\type Add a is contract = { associated "add" a a a }
        \\const twice: a -> a where { Add a } = func value => return value
        \\const work: a -> a where { Add a } = tw
    ;
    const cursor = (try probe.capture(a, source, @intCast(source.len))).?;
    defer cursor.deinit(a);
    var tokens = try lexer.lex(a, cursor.source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, cursor.source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .editor = .{ .span = cursor.marker, .kind = cursor.kind, .prefix = cursor.prefix } });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const capture = checked.editor.?;
    var candidate: check.BindingId = 0;
    for (checked.bindings, 0..) |binding, index| {
        if (std.mem.eql(u8, pool.get(binding.name), "twice")) candidate = @intCast(index);
    }
    try std.testing.expect(candidate != 0);
    const fitting = @import("completion_fit.zig");
    var budget: fitting.Budget = .{};
    try std.testing.expectEqual(fitting.Match.compatible, try fitting.fit(a, &checked.types, checked.expr_types[capture.node], checked.bindings[candidate].scheme, checked.bindings[capture.owner].scheme, checked.obligations, &budget));
}

test "completion private item scope exceeds the display graph and keeps the latest binder" {
    const a = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const work = func () : Bool => return do:\n");
    for (0..100) |index| {
        const line = try a.print("  let match_{d} = {d}\n", .{ index, index });
        defer a.free(line);
        try source.appendSlice(a, line);
    }
    try source.appendSlice(a, "  match_0 := true\n  break mat");
    const cursor = (try probe.capture(a, source.items, @intCast(source.items.len))).?;
    defer cursor.deinit(a);
    var tokens = try lexer.lex(a, cursor.source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, cursor.source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .editor = .{ .span = cursor.marker, .kind = cursor.kind, .prefix = cursor.prefix } });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const capture = checked.editor.?;
    try std.testing.expectEqual(@as(u32, 100), capture.visible.len);
    const context = capture.context.?;
    try std.testing.expectEqual(@as(usize, 32), context.scope.len);
    try std.testing.expect(context.truncated);
    const bindings = checked.types.list(capture.visible);
    try std.testing.expectEqualStrings("match_0", pool.get(checked.bindings[bindings[0]].name));
    try std.testing.expectEqual(.boolean, checked.types.node(checked.types.head(checked.bindings[bindings[0]].ty, 0)).tag);
    var count: usize = 0;
    for (bindings) |binding| if (std.mem.eql(u8, pool.get(checked.bindings[binding].name), "match_0")) {
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "completion private project shares inference budget without evaluating initializers or requiring entries" {
    const a = std.testing.allocator;
    const project = @import("project.zig");
    const inputs = @import("revision_inputs.zig");
    const project_check = @import("project_check.zig");
    const text = "import { value } from \"./library\"\nconst work = func () : F32 => return va\n";
    const position: u32 = @intCast(std.mem.findLast(u8, text, "va").? + 2);
    const cursor = (try probe.capture(a, text, position)).?;
    defer cursor.deinit(a);
    var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{
        .{ .path = "/blot-editor/main.blot", .contents = cursor.source },
        .{ .path = "/blot-editor/library.blot", .contents = "const value = 42\nconst never_evaluated = @u32.div 1 0\n" },
    });
    defer snapshot.deinit();
    var loaded = try project.loadWithInputs(a, std.testing.io, "/blot-editor/main.blot", .{}, snapshot.provider());
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    const fitting = @import("completion_fit.zig");
    var budget: fitting.Budget = .{};
    var checked = try project_check.checkProjectForEditor(a, &loaded, .{ .unit = loaded.entry, .marker = .{ .span = cursor.marker, .kind = cursor.kind, .prefix = cursor.prefix }, .budget = &budget });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const module = checked.module(loaded.entry);
    try std.testing.expect(module.checked.editor != null);
    const context = module.checked.editor.?.context.?;
    try std.testing.expectEqual(.f32, context.nodes[context.expected].kind);
    var steps: usize = 0;
    for (checked.modules) |item| if (item) |value| {
        steps += @intCast(value.checked.counters.inference_steps);
    };
    try std.testing.expect(steps > 0);
    try std.testing.expectEqual(1_000_000 - steps, budget.remaining);
    var small: fitting.Budget = .{ .remaining = 1 };
    var limited = try project_check.checkProjectForEditor(a, &loaded, .{ .unit = loaded.entry, .marker = .{ .span = cursor.marker, .kind = cursor.kind }, .budget = &small });
    defer limited.deinit(a);
    try std.testing.expect(small.exhausted);
    try std.testing.expect(small.remaining <= 1);
    try std.testing.expect(limited.diagnostics.len != 0);
}
