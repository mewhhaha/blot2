const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");

fn law(allocator: std.mem.Allocator) !void {
    const source =
        \\const unfinished = fn (value: U32) -> F32 => do:
        \\  let original = value
        \\  value := #True
        \\  return @hole
        \\entry const answer = 42
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    const hole = checked.diagnostics[0];
    try std.testing.expectEqual(check.Code.typed_hole, hole.code);
    try std.testing.expectEqualStrings("@hole", source[hole.span.start..hole.span.end]);
    const message = hole.message();
    try std.testing.expect(std.mem.startsWith(u8, message, "Unfilled expression; expected: F32; in scope:"));
    try std.testing.expect(std.mem.find(u8, message, "value: Bool") != null);
    try std.testing.expect(std.mem.find(u8, message, "original: U32") != null);
    try std.testing.expect(std.mem.find(u8, message, "value: U32") == null);
    const snapshot = hole.hole.?;
    try std.testing.expectEqual(.f32, snapshot.nodes[snapshot.expected].kind);
    for (snapshot.scope) |binding| {
        if (std.mem.eql(u8, binding.name, "value")) try std.testing.expectEqual(.boolean, snapshot.nodes[binding.type].kind);
        if (std.mem.eql(u8, binding.name, "original")) try std.testing.expectEqual(.u32, snapshot.nodes[binding.type].kind);
    }
    const copy = try snapshot.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqualDeep(snapshot, copy);
    for (snapshot.scope, copy.scope) |original, copied| try std.testing.expect(original.name.ptr != copied.name.ptr);
}
test "typed holes infer unused bodies and preserve lexical shadowing under allocation failure" {
    try law(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{});
}
test "typed holes report contextual functions and effects after solving" {
    const allocator = std.testing.allocator;
    for ([_]struct { source: []const u8, expected: []const u8 }{
        .{ .source = "entry const answer: U32 -> Bool ! {Foreign} = @hole\n", .expected = "(U32 -> Bool ! {Foreign})" },
        .{ .source = "entry const answer = fn () => @u32.add @hole 2\n", .expected = "U32" },
        .{ .source = "type Box a is data = #Box a\nconst unused: Box U32 = @hole\nentry const answer = 42\n", .expected = "Box U32" },
        .{ .source = "const unused: Array F32 = @hole\nentry const answer = 42\n", .expected = "Array F32" },
    }) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        const hole = checked.diagnostics[0];
        try std.testing.expectEqual(check.Code.typed_hole, hole.code);
        try std.testing.expect(std.mem.find(u8, hole.message(), item.expected) != null);
    }
}

test "typed hole diagnostics bound wide type graphs" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "const unfinished: (");
    for (0..4096) |_| try source.appendSlice(allocator, "U32,");
    try source.appendSlice(allocator, "U32) = @hole\nentry const answer = 42\n");
    var tokens = try lexer.lex(allocator, source.items);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source.items, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    const message = checked.diagnostics[0].message();
    try std.testing.expect(message.len < 8192);
    try std.testing.expect(std.mem.find(u8, message, "...") != null);
    const snapshot = checked.diagnostics[0].hole.?;
    try std.testing.expect(snapshot.truncated);
    try std.testing.expect(snapshot.nodes.len <= 1025);
    try std.testing.expect(snapshot.edges.len <= 4096);
}

test "typed hole graphs preserve nominal arguments, effect identities and generic requirements" {
    const allocator = std.testing.allocator;
    const source =
        \\type Read a is effect = Unit -> a
        \\type Box a is data = #Box a
        \\type Add a is contract = { associated "add" a a a }
        \\const unfinished: a -> a where { Add a } = fn value => do:
        \\  let other = value
        \\  return @hole
        \\const callback: Unit -> Box U32 ! {Read U32 | e} = @hole
        \\entry const answer = 42
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), checked.diagnostics.len);
    const generic = checked.diagnostics[0].hole.?;
    try std.testing.expectEqual(@as(u32, 1), generic.enclosing.len);
    const constraint = generic.requirements[generic.enclosing.start];
    try std.testing.expectEqual(.dispatch, constraint.kind);
    try std.testing.expectEqualStrings("add", constraint.name.?);
    try std.testing.expectEqual(constraint.subject, generic.expected);
    const callback = checked.diagnostics[1].hole.?;
    const function = callback.nodes[callback.expected];
    try std.testing.expectEqual(.function, function.kind);
    const returned = callback.nodes[callback.edges[function.children.start + 1].type];
    try std.testing.expectEqualStrings("Box", returned.name.?);
    try std.testing.expectEqual(.u32, callback.nodes[callback.edges[returned.children.start].type].kind);
    const effects = callback.nodes[function.effects.?];
    try std.testing.expectEqual(@as(u32, 2), effects.children.len);
    const operation = callback.nodes[callback.edges[effects.children.start].type];
    try std.testing.expectEqualStrings("Read", operation.name.?);
    try std.testing.expectEqual(.u32, callback.nodes[callback.edges[operation.children.start].type].kind);
    try std.testing.expectEqual(.row_variable, callback.nodes[callback.edges[effects.children.start + 1].type].kind);
}

test "typed holes bound lexical capture and prioritize the nearest unshadowed bindings" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "entry const answer = fn () -> U32 => do:\n");
    for (0..4096) |i| {
        const line = try allocator.print("  let local_{d} = {d}\n", .{ i, i });
        defer allocator.free(line);
        try source.appendSlice(allocator, line);
    }
    try source.appendSlice(allocator, "  local_4095 := #True\n  return @hole\n");
    var tokens = try lexer.lex(allocator, source.items);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source.items, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    const hole = checked.diagnostics[0].hole.?;
    try std.testing.expect(hole.truncated);
    try std.testing.expectEqual(@as(usize, 32), hole.scope.len);
    try std.testing.expectEqualStrings("local_4095", hole.scope[0].name);
    try std.testing.expectEqual(.boolean, hole.nodes[hole.scope[0].type].kind);
    try std.testing.expectEqualStrings("local_4064", hole.scope[31].name);
}
