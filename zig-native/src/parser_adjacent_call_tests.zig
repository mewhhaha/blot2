const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");

fn parsed(allocator: std.mem.Allocator, input: []const u8, pool: *symbols.Pool) !ast.Tree {
    var lexed = try lexer.lex(allocator, input);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var tree = try parser.parse(allocator, input, lexed.tokens.items, pool);
    errdefer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    return tree;
}

const source =
    \\const adjacent = make(probe).pick(index)
    \\const projected_argument = consume (value).field
    \\const adjacent_index = make(value)[0].field
    \\const indexed_argument = consume (value)[0]
    \\const spaced = sum counts[0].value 2
    \\const curried = factory()(value).field
    \\const nested = make(value.field).field
    \\const array_argument = identity(#[1, 2])[0]
;

fn check(tree: *const ast.Tree, pool: *const symbols.Pool) !void {
    try std.testing.expectEqual(@as(usize, 8), tree.roots.items.len);
    const adjacent_id = tree.valueDecl(tree.roots.items[0]).body;
    const adjacent = tree.node(adjacent_id);
    try std.testing.expectEqual(ast.Tag.apply, adjacent.tag);
    const pick = tree.node(adjacent.a);
    try std.testing.expectEqual(ast.Tag.field_access, pick.tag);
    try std.testing.expectEqualStrings("pick", pool.get(pick.b));
    const make = tree.node(pick.a);
    try std.testing.expectEqual(ast.Tag.apply, make.tag);
    try std.testing.expectEqualStrings("make", pool.get(tree.node(make.a).a));
    try std.testing.expectEqual(ast.Tag.group, tree.node(make.b).tag);
    try std.testing.expectEqual(ast.Tag.group, tree.node(adjacent.b).tag);

    const projected = tree.node(tree.valueDecl(tree.roots.items[1]).body);
    try std.testing.expectEqual(ast.Tag.apply, projected.tag);
    try std.testing.expectEqual(ast.Tag.name, tree.node(projected.a).tag);
    try std.testing.expectEqual(ast.Tag.field_access, tree.node(projected.b).tag);
    try std.testing.expectEqual(ast.Tag.group, tree.node(tree.node(projected.b).a).tag);

    const indexed = tree.node(tree.valueDecl(tree.roots.items[2]).body);
    try std.testing.expectEqual(ast.Tag.field_access, indexed.tag);
    const index = tree.node(indexed.a);
    try std.testing.expectEqual(ast.Tag.index_access, index.tag);
    try std.testing.expectEqual(ast.Tag.apply, tree.node(index.a).tag);
    const indexed_argument = tree.node(tree.valueDecl(tree.roots.items[3]).body);
    try std.testing.expectEqual(ast.Tag.apply, indexed_argument.tag);
    try std.testing.expectEqual(ast.Tag.index_access, tree.node(indexed_argument.b).tag);

    const spaced = tree.node(tree.valueDecl(tree.roots.items[4]).body);
    try std.testing.expectEqual(ast.Tag.apply, spaced.tag);
    const sum = tree.node(spaced.a);
    try std.testing.expectEqual(ast.Tag.apply, sum.tag);
    try std.testing.expectEqualStrings("sum", pool.get(tree.node(sum.a).a));
    try std.testing.expectEqual(ast.Tag.field_access, tree.node(sum.b).tag);
    try std.testing.expectEqual(ast.Tag.index_access, tree.node(tree.node(sum.b).a).tag);

    const curried = tree.node(tree.valueDecl(tree.roots.items[5]).body);
    try std.testing.expectEqual(ast.Tag.field_access, curried.tag);
    const second = tree.node(curried.a);
    try std.testing.expectEqual(ast.Tag.apply, second.tag);
    const first = tree.node(second.a);
    try std.testing.expectEqual(ast.Tag.apply, first.tag);
    try std.testing.expectEqual(ast.Tag.unit, tree.node(first.b).tag);

    const nested = tree.node(tree.valueDecl(tree.roots.items[6]).body);
    try std.testing.expectEqual(ast.Tag.field_access, nested.tag);
    const nested_call = tree.node(nested.a);
    try std.testing.expectEqual(ast.Tag.apply, nested_call.tag);
    const nested_argument = tree.node(tree.node(nested_call.b).a);
    try std.testing.expectEqual(ast.Tag.name, nested_argument.tag);
    try std.testing.expectEqualStrings("value.field", pool.get(nested_argument.a));

    const array = tree.node(tree.valueDecl(tree.roots.items[7]).body);
    try std.testing.expectEqual(ast.Tag.index_access, array.tag);
    const array_call = tree.node(array.a);
    try std.testing.expectEqual(ast.Tag.apply, array_call.tag);
    try std.testing.expectEqual(ast.Tag.array, tree.node(tree.node(array_call.b).a).tag);

    try std.testing.expectEqual(tree.nodes.items.len, tree.spans.items.len);
    for (tree.spans.items) |span| try std.testing.expect(span.start <= span.end and span.end <= source.len);
    try std.testing.expectEqualStrings("make(probe).pick(index)", source[tree.span(adjacent_id).start..tree.span(adjacent_id).end]);
    try std.testing.expectEqualStrings("make(probe)", source[tree.span(pick.a).start..tree.span(pick.a).end]);
    try std.testing.expectEqualStrings("(probe)", source[tree.span(make.b).start..tree.span(make.b).end]);
}

test "adjacent groups call before later members and indexes while spaced arguments retain projections" {
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try check(&tree, &pool);
}

fn retainedScenario(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var first = try parsed(allocator, source, &pool);
    defer first.deinit(allocator);
    const nodes = try allocator.dupe(ast.Node, first.nodes.items);
    defer allocator.free(nodes);
    const spans = try allocator.dupe(ast.Span, first.spans.items);
    defer allocator.free(spans);
    const lists = try allocator.dupe(ast.Id, first.extra.items);
    defer allocator.free(lists);
    {
        var second = try parsed(allocator, "const later = unrelated(argument).different[1]\n", &pool);
        defer second.deinit(allocator);
        try std.testing.expectEqual(ast.Tag.index_access, second.node(second.valueDecl(second.roots.items[0]).body).tag);
    }
    try std.testing.expectEqualDeep(nodes, first.nodes.items);
    try std.testing.expectEqualDeep(spans, first.spans.items);
    try std.testing.expectEqualDeep(lists, first.extra.items);
    try check(&first, &pool);
}

test "retained adjacent-call tree stays immutable across another parse and teardown" {
    try retainedScenario(std.testing.allocator);
}

test "adjacent-call parsing and retained publication release every allocation on OOM" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, retainedScenario, .{});
}
