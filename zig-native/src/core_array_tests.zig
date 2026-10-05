const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

const source =
    \\infixl 60 (+) = _fixity_add
    \\const marker = fn (value: U32) -> U32 => value + 1
    \\entry const snapshots = fn (value: U32) -> U32 => do:
    \\  let before = #[value, marker value]
    \\  let after = @array.set before 0 (marker value)
    \\  let filled = @array.fill 2 (marker value)
    \\  return before[0] + after[0] + @array.length filled
    \\entry const empty = fn () -> Array F32 => #[]
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;
const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init() !Fixture {
        var lexed = try lexer.lex(a, source);
        defer lexed.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, lexed.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("array check {d}: {s}\n", .{ item.span.start, item.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .pool = pool, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.pool, &self.checked);
    }
};
test "owned array core preserves single evaluation operand order and snapshot references" {
    var fixture = try Fixture.init();
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 4), module.body_lowerings);
    const statements = module.children(module.bodies[2].root);
    const before = module.node(statements[0]);
    const initial = module.node(before.b);
    try std.testing.expectEqual(core.Tag.array, initial.tag);
    try std.testing.expectEqual(@as(usize, 2), module.children(before.b).len);
    try std.testing.expectEqual(core.Tag.call, module.node(module.children(before.b)[1]).tag);
    const replacement = module.node(statements[1]).b;
    try std.testing.expectEqual(core.ArrayOp.set, module.arrayOperation(replacement));
    const arguments = module.children(replacement);
    try std.testing.expectEqual(@as(usize, 3), arguments.len);
    try std.testing.expectEqual(before.a, module.reference(arguments[0]).binding);
    try std.testing.expectEqual(@as(u32, 0), module.node(arguments[1]).a);
    try std.testing.expectEqual(core.Tag.call, module.node(arguments[2]).tag);
    const filled = module.node(statements[2]).b;
    try std.testing.expectEqual(core.ArrayOp.fill, module.arrayOperation(filled));
    try std.testing.expectEqual(@as(usize, 2), module.children(filled).len);
    try std.testing.expectEqual(core.Tag.call, module.node(module.children(filled)[1]).tag);
    try std.testing.expectEqual(core.Tag.array, module.node(module.bodies[3].root).tag);
    try std.testing.expectEqual(@as(usize, 0), module.children(module.bodies[3].root).len);
    var gets: usize = 0;
    var lengths: usize = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag != .array_op) continue;
        const op = module.arrayOperation(@intCast(index));
        if (op == .get) gets += 1;
        if (op == .length) lengths += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), gets);
    try std.testing.expectEqual(@as(usize, 1), lengths);
}
fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
}
test "all array lowering allocation failures release operand lists and frozen types" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
