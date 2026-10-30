const std = @import("std");
const ast = @import("../parse/ast.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

// The second arm leaves `count` alone; the third keeps its own local.
const source =
    \\type Tri is data = #Rise | #Fall | #Still
    \\entry const run = func (n: U32) : U32 => return do:
    \\  let beat = if @u32.eq n 0 then #Fall else if @u32.eq n 1 then #Rise else #Still
    \\  let count = 0
    \\  case beat of
    \\    #Rise => do:
    \\      count := 7
    \\    #Fall => do:
    \\      let unused = 1
    \\    #Still => do:
    \\      count := @u32.add self 11
    \\  break count
;

const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.check(a, &tree, &pool);
        return .{ .tree = tree, .pool = pool, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn only(self: *const Fixture, tag: ast.Tag) !ast.Id {
        var found: ast.Id = 0;
        for (self.tree.nodes.items, 0..) |node, id| if (node.tag == tag) {
            try std.testing.expectEqual(@as(ast.Id, 0), found);
            found = @intCast(id);
        };
        try std.testing.expect(found != 0);
        return found;
    }
};

test "statement case arms carry rebinding through one binary merge per nested level" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    const checked = &fixture.checked;
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const case_node = fixture.tree.node(try fixture.only(.case_expr));
    const arms = fixture.tree.list(.{ .start = case_node.b, .len = case_node.c });
    try std.testing.expectEqual(@as(usize, 3), arms.len);
    var bodies: [3]ast.Id = undefined;
    for (arms, &bodies) |arm, *body| body.* = fixture.tree.extra.items[fixture.tree.node(arm).c + 1];
    // Only the arms that rebind lower their do: statements as a suite.
    try std.testing.expectEqual(@as(usize, 2), checked.statement_arms.len);
    try std.testing.expectEqual(bodies[0], checked.statement_arms[0].node);
    try std.testing.expectEqual(bodies[2], checked.statement_arms[1].node);
    // Level 1 joins the last two arms; level 0 joins arm 0 with level 1.
    try std.testing.expectEqual(@as(usize, 2), checked.merges.len);
    const inner = checked.merges[0];
    const outer = checked.merges[1];
    try std.testing.expectEqual(arms[1], inner.node);
    try std.testing.expectEqual(arms[0], outer.node);
    const incoming = checked.bindings[outer.then_binding].predecessor;
    try std.testing.expect(incoming != 0);
    try std.testing.expectEqual(incoming, inner.then_binding);
    try std.testing.expectEqual(incoming, checked.bindings[inner.else_binding].predecessor);
    try std.testing.expectEqual(inner.result, outer.else_binding);
    var returned: ast.Id = 0;
    for (fixture.tree.nodes.items) |node| if (node.tag == .return_stmt) {
        returned = node.a;
    };
    try std.testing.expectEqual(outer.result, checked.resolved[returned]);

    var module = try core.lower(a, &fixture.tree, &fixture.pool, checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var levels: [2]core.Id = .{ 0, 0 };
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .match and module.matchInfo(@intCast(id)).statement) {
        try std.testing.expect(count < levels.len);
        levels[count] = @intCast(id);
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), count);
    // The deeper level is lowered first and tests arm 1 against arm 2.
    const deeper = levels[0];
    const top = levels[1];
    for (levels) |level| try std.testing.expectEqual(@as(usize, 2), module.matchArms(level).len);
    const fallback = module.matchArms(top)[1];
    const binder = module.pattern(module.rowPatterns(module.armRows(fallback)[0])[0]);
    try std.testing.expectEqual(core.PatternTag.bind, binder.tag);
    const level_input = module.matchInputs(deeper)[0];
    try std.testing.expectEqual(core.Tag.reference, module.node(level_input).tag);
    try std.testing.expectEqual(binder.a, module.reference(level_input).binding);
    try std.testing.expectEqualSlices(core.Id, &.{deeper}, module.children(fallback.body));
    try std.testing.expectEqual(core.Tag.suite, module.node(module.matchArms(top)[0].body).tag);
    for (module.matchArms(deeper)) |arm| try std.testing.expectEqual(core.Tag.suite, module.node(arm.body).tag);
    const top_merges = module.branchMerges(top);
    const deeper_merges = module.branchMerges(deeper);
    try std.testing.expectEqual(@as(usize, 1), top_merges.len);
    try std.testing.expectEqual(@as(usize, 1), deeper_merges.len);
    try std.testing.expectEqual(deeper_merges[0].result, top_merges[0].else_binding);
    // Portable Core admits the level locals and binary merges unchanged.
    module.unit = 1;
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
}

test "statement case arms reject a nested return but end at a direct one" {
    const nested =
        \\type Beat is data = #Up | #Down
        \\entry const run = func (n: U32) : U32 => return do:
        \\  let beat = if @u32.lt 0 n then #Up else #Down
        \\  let count = 0
        \\  case beat of
        \\    #Up => do:
        \\      count := 7
        \\      if @u32.lt 4 n:
        \\        break ()
        \\    #Down => do:
        \\      count := 3
        \\      break ()
        \\  break count
    ;
    var fixture = try Fixture.init(nested);
    defer fixture.deinit();
    try std.testing.expectEqual(@as(usize, 1), fixture.checked.diagnostics.len);
    try std.testing.expectEqual(check.Code.case_arm_return, fixture.checked.diagnostics[0].code);
    const inner = std.mem.find(u8, nested, "break ()").?;
    try std.testing.expectEqual(@as(u32, @intCast(inner)), fixture.checked.diagnostics[0].span.start);
}

test "a plain nested do keeps its scope and an arm local stays dead" {
    inline for (.{
        \\entry const run = func (n: U32) : U32 => return do:
        \\  let count = n
        \\  do:
        \\    count := @u32.add self 1
        \\  break count
        ,
        \\type Maybe a is data = #None | #Some a
        \\entry const run = func (n: U32) : U32 => return do:
        \\  let count = 0
        \\  case #Some n of
        \\    #Some value => do:
        \\      value := @u32.add self 1
        \\    #None => do:
        \\      count := 3
        \\  break count
    }) |text| {
        var fixture = try Fixture.init(text);
        defer fixture.deinit();
        try std.testing.expectEqual(@as(usize, 1), fixture.checked.diagnostics.len);
        try std.testing.expectEqual(check.Code.dead_rebinding, fixture.checked.diagnostics[0].code);
    }
}
