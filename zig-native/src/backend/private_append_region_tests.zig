const std = @import("std");
const core = @import("../check/core.zig");
const region = @import("private_append_region.zig");
const a = std.testing.allocator;
fn lower(source: []const u8) !core.Module {
    var tokens = try @import("../parse/lexer.zig").lex(a, source);
    defer tokens.deinit(a);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("../parse/parser.zig").parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true, .prelude_unit = 1 });
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("private append check: {s}\n", .{diagnostic.message()});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn plans(module: *const core.Module) usize {
    var found: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .block and region.analyze(module, @intCast(id)) != null) found += 1;
    }
    return found;
}

test "private append regions preserve guarded nested and dependent generator order" {
    const sources = [_][]const u8{
        "entry const run = func (values: Array U32) => return #[x | x <- values, @u32.lt 1 x]\n",
        "entry const run = func (values: Array U32) => return #[@u32.add x y | x <- values, y <- #[x, 1], @u32.lt 0 y]\n",
        "const scalar = func (value: U32) => return @u32.add value 1\nentry const run = func (values: Array U32) => return #[scalar x | x <- values, let y = @u32.add x 1, @u32.lt x y]\n",
        "const accept = func predicate => return predicate 1\nentry const run = func (values: Array U32) => return #[x | x <- values, accept (func id => return @u32.eq id x)]\n",
    };
    for (sources) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), plans(&module));
    }
}

test "private append regions reject accumulator observations captures and public Lists" {
    const sources = [_][]const u8{
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  for x in 0..count:\n    rows := @list.append rows (@list.length rows)\n  break @array.from_list rows\n",
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  let old = rows\n  for x in 0..count:\n    rows := @list.append rows (@list.length old)\n  break @array.from_list rows\n",
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  for x in 0..count:\n    let observed = func () => return @list.length rows\n    rows := @list.append rows (observed ())\n  break @array.from_list rows\n",
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  let old = rows\n  for x in 0..count:\n    let observed = func () => return func () => return @list.length old\n    rows := @list.append rows (observed () ())\n  break @array.from_list rows\n",
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  for x in 0..count:\n    let box = {rows}\n    let observed = func () => return @list.length box.rows\n    rows := @list.append rows (observed ())\n  break @array.from_list rows\n",
        "entry const run = func (count: U32) => return do:\n  let rows: List U32 = []\n  for x in 0..count:\n    rows := @list.append rows x\n    rows := @list.append rows 2\n  break @array.from_list rows\n",
        "entry const run = func (values: Array U32) => return [x | x <- values]\n",
    };
    for (sources) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), plans(&module));
    }
}

test "private append iterator exits retain exact targets carries and exhaustion" {
    const source =
        \\type Step is data = $More (U32, U32) | $End
        \\const next = func (count: U32) -> (index: U32) => return
        \\  if @u32.lt index count then $More (index, @u32.add index 1) else $End
        \\entry const run = func (count: U32) => return do:
        \\  let rows: List U32 = []
        \\  let cursor: U32 = 0
        \\  for ever:
        \\    let $More (item, rest) = next count cursor else:
        \\      break
        \\    cursor := rest
        \\    rows := @list.append rows item
        \\  break @array.from_list rows
    ;
    var module = try lower(source);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), plans(&module));
    var exit: core.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .break_) {
        exit = @intCast(id);
    };
    try std.testing.expect(exit != 0);
    const original = module.nodes[exit];
    const carry_range = module.loopInfo(original.a).carries;
    try std.testing.expectEqual(@as(u32, 2), carry_range.len);
    module.nodes[exit].op = .continue_;
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    module.nodes[exit] = original;
    module.nodes[exit].a = 0;
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    module.nodes[exit] = original;
    module.nodes[exit].c -= 1;
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    module.nodes[exit] = original;
    std.mem.swap(core.Id, &module.extra[original.b], &module.extra[original.b + 1]);
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    std.mem.swap(core.Id, &module.extra[original.b], &module.extra[original.b + 1]);
    module.nodes[exit].tag = .return_;
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    module.nodes[exit] = original;
    const body = module.loopInfo(original.a).body;
    const statements = module.children(body);
    const body_start = module.nodes[body].a;
    std.mem.swap(core.Id, &module.extra[body_start], &module.extra[body_start + statements.len - 1]);
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    std.mem.swap(core.Id, &module.extra[body_start], &module.extra[body_start + statements.len - 1]);
    const saved = module.loop_carries[carry_range.start];
    module.loop_carries[carry_range.start].backedge = module.loop_carries[carry_range.start + 1].backedge;
    try std.testing.expectEqual(@as(usize, 0), plans(&module));
    module.loop_carries[carry_range.start] = saved;
    try std.testing.expectEqual(@as(usize, 1), plans(&module));
}
