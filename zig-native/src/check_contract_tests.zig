const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");

fn law(allocator: std.mem.Allocator) !void {
    const source =
        \\type Read a is contract = { field "value" a U32 }
        \\type ReadAgain a is contract = { Read a }
        \\type Scalar = U32
        \\type Box is data = #Box { value: Scalar }
        \\type Different is data = #Different { value: U32, enabled: Bool }
        \\const read: a -> U32 where { ReadAgain a } = fn value => value.value
        \\entry const first = fn () => read (#Box { value: 42 })
        \\entry const second = fn () => read (#Different { value: 11, enabled: #True })
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
    try std.testing.expectEqual(@as(usize, 2), checked.contracts.len);
    try std.testing.expectEqual(@as(u32, 1), checked.contracts[1].predicates.len);
}
test "named contracts preserve independent evidence and release all allocation failures" {
    try law(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{});
}

test "contracts validate unused bodies, arity, parameter kinds and cycles" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "type Loop a is contract = { Loop a }\nentry const answer = 42\n",
        "type A a is contract = { B a }\ntype B a is contract = { A a }\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a b }\nentry const answer = 42\n",
        "type A a is contract = { Unknown a }\nentry const answer = 42\n",
        "entry const answer: U32 where { Type_rep U32 } = 42\n",
        "type A a is contract = { field \"x\" a U32 }\nconst f: a -> U32 where { A } = fn x => x.x\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a U32 }\nconst f: a -> U32 where { A a U32 } = fn x => x.x\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a U32 }\ntype A = U32\nentry const answer = 42\n",
    }) |source| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
    }
}
