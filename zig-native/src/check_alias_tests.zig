const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");

fn law(allocator: std.mem.Allocator) !void {
    const source =
        \\type Position = Vec2
        \\type Pair a = (a, a)
        \\type NumberPair = Pair U32
        \\type Vec2 is data = #Vec2 { x: F32, y: F32 }
        \\type Action a = Unit -> a ! {| e}
        \\const position: Position = #Vec2 { x: 1.0, y: 2.0 }
        \\const first = fn (pair: NumberPair) => @product.get pair 0
        \\const apply = fn (action: Action U32) => action ()
        \\entry const answer = fn () => first (42, 1)
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
    for (checked.diagnostics) |d| std.debug.print("{s}: {s}\n", .{ @tagName(d.code), d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.nominals[1].alias != 0);
    const target = checked.types.node(checked.nominals[1].alias);
    try std.testing.expectEqual(@import("types.zig").Tag.nominal, target.tag);
    try std.testing.expectEqual(checked.nominals[4].identity.decl, target.b);
}
test "transparent aliases preserve generic and nominal identities through allocation failures" {
    try law(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{});
}
test "recursive and invalid unused aliases fail explicitly" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "type Loop = Loop\nentry const answer = 42\n",
        "type First a = Second a\ntype Second a = First a\nentry const answer = 42\n",
        "type Missing = Unknown\nentry const answer = 42\n",
        "type Missing = a\nentry const answer = 42\n",
        "type Pair a = (a, a)\nconst bad: Pair = ()\nentry const answer = 42\n",
        "type Action a = Unit -> a ! {| e}\ntype Box is data = #Box (Action U32)\nentry const answer = 42\n",
        "type Action a = Unit -> a ! {| e}\ntype Read is effect = Unit -> (Action U32)\nentry const answer = 42\n",
    }) |source| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
    }
}
test "forward alias expansion has a bounded call stack" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..300) |index| {
        var buffer: [64]u8 = undefined;
        const line = try std.mem.print(&buffer, "type A{d} = A{d}\n", .{ index, index + 1 });
        try source.appendSlice(allocator, line);
    }
    try source.appendSlice(allocator, "type A300 = U32\nentry const answer = 42\n");
    var tokens = try lexer.lex(allocator, source.items);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source.items, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectError(error.TypeLimit, check.check(allocator, &tree, &pool));
}
