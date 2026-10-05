const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const targets = @import("loop_targets.zig");
const a = std.testing.allocator;
const source =
    \\const run = fn values => do:
    \\  for iterator in values:
    \\    before := 1
    \\    let before = 99
    \\    before := 100
    \\    let local = 0
    \\    local := 1
    \\    iterator := 2
    \\    if #True:
    \\      branch := 3
    \\      let other = 0
    \\      other := 4
    \\    else:
    \\      let branch = 0
    \\      branch := 4
    \\    if let #Some payload = candidate:
    \\      payload := 5
    \\      conditional := 6
    \\    else:
    \\      conditional := 7
    \\    for nested in values:
    \\      nested := 8
    \\      parent := 9
    \\    for 0..1:
    \\      unnamed := 10
    \\    for ever:
    \\      repeated := 11
    \\      break
    \\    use used <- 0
    \\    used := 12
    \\    object.field := 13
    \\    array[0] := 14
    \\    let ignored = do:
    \\      separate := 15
    \\      return 0
    \\    let closure = fn () => do:
    \\      separate_closure := 16
    \\      return 0
    \\  return 0
;

const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    pattern: ast.Id,
    body: ast.Id,
    fn init() !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const function = tree.node(tree.valueDecl(tree.roots.items[0]).body);
        const loop = tree.node(tree.children(function.b)[0]);
        try std.testing.expectEqual(ast.Tag.for_stmt, loop.tag);
        return .{ .tree = tree, .pool = pool, .pattern = loop.a, .body = tree.extra.items[loop.c + 1] };
    }
    fn deinit(self: *Fixture) void {
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
};

fn verify(fixture: *const Fixture, found: []const symbols.Symbol) !void {
    const expected = [_][]const u8{ "before", "branch", "conditional", "parent", "unnamed", "repeated", "object", "array" };
    try std.testing.expectEqual(expected.len, found.len);
    for (expected, found) |name, symbol| try std.testing.expectEqualStrings(name, fixture.pool.get(symbol));
}

test "loop targets retain outer successors through nested scopes without carrying shadowed locals" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const found = try targets.collect(a, &fixture.tree, &fixture.pool, fixture.pattern, fixture.body);
    defer a.free(found);
    try verify(&fixture, found);
}

fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    const found = try targets.collect(allocator, &fixture.tree, &fixture.pool, fixture.pattern, fixture.body);
    defer allocator.free(found);
    try verify(fixture, found);
}

test "loop target discovery releases scope trails and numeric sets on every allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
