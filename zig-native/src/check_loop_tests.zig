const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const ast = @import("ast.zig");
const a = std.testing.allocator;
const source =
    \\entry const run = fn () => do:
    \\  let total = 0
    \\  for index in 0..3:
    \\    if #True:
    \\      total := @u32.add self 1
    \\      let total = 99
    \\      use total
    \\  for ever:
    \\    total := @u32.add self 1
    \\    let total = 42
    \\    break
    \\  return total
;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: ast.Tree,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        return .{ .pool = pool, .tree = tree };
    }
    fn deinit(self: *Fixture) void {
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
};
test "loop normal successors and break lexical snapshots retain distinct binding identities" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    for (checked.diagnostics) |d| std.debug.print("{s} at {d}\n", .{ @tagName(d.code), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), checked.loop_carries.len);
    try std.testing.expectEqual(@as(usize, 1), checked.loop_exits.len);
    const first = checked.loop_carries[0];
    try std.testing.expectEqual(first.incoming, checked.bindings[first.iteration].predecessor);
    try std.testing.expectEqual(first.incoming, checked.bindings[first.outgoing].predecessor);
    // Conditional merging keeps the real := successor despite a later let.
    try std.testing.expect(first.backedge != first.iteration);
    try std.testing.expectEqual(first.iteration, checked.bindings[first.backedge].predecessor);
    const second = checked.loop_carries[1];
    const captured = checked.types.list(checked.loop_exits[0].bindings)[0];
    try std.testing.expect(captured != second.backedge);
    try std.testing.expectEqual(@as(u32, 0), checked.bindings[captured].predecessor);
    try std.testing.expectEqual(second.iteration, checked.bindings[second.backedge].predecessor);
}
test "loop breaks isolate lambdas and named use remains monomorphic" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "const bad = fn () => do:\n  break\n", .code = .break_scope },
        .{ .source = "const bad = fn () => do:\n  for ever:\n    let nested = fn () => do:\n      break\n    break\n", .code = .break_scope },
        .{ .source = "const identity = fn value => value\nconst bad = fn () => do:\n  use once <- identity\n  use once 1\n  return once 1.0\n", .code = .type_mismatch },
        .{ .source = "const bad = fn () => do:\n  for ever:\n    break\n    use ()\n", .code = .unreachable_statement },
    };
    for (cases) |case| {
        var fixture = try Fixture.init(case.source);
        defer fixture.deinit();
        var checked = try check.check(a, &fixture.tree, &fixture.pool);
        defer checked.deinit(a);
        var found = false;
        for (checked.diagnostics) |d| found = found or d.code == case.code;
        try std.testing.expect(found);
    }
}
fn allocationFailure(allocator: std.mem.Allocator, tree: *const ast.Tree, pool: *symbols.Pool) !void {
    var checked = try check.check(allocator, tree, pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
test "loop carry frames break snapshots and publication release every failed allocation" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture.tree, &fixture.pool });
}
