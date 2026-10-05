const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;
const source =
    \\infixl 60 (+) = _fixity_add
    \\const add = fn left => fn right => @u32.add left right
    \\const scalar_partial = add 21
    \\const array_value = @array.fill 2 20
    \\const unused_trap = @panic "bad\n\t\" UTF8 🦊"
    \\entry const run = fn (input: U32) -> U32 => @array.length array_value + scalar_partial input
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;
const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init() !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("callable {d}: {s}\n", .{ item.span.start, item.message() });
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
test "owned ordinary scalar wrapper partials and arrays preserve dead panic UTF8 bytes" {
    var fixture = try Fixture.init();
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 0), module.primitives.len);
    const add = module.bodies[1].root;
    try std.testing.expectEqual(core.Tag.scalar, module.node(add).tag);
    try std.testing.expectEqual(core.Op.add, module.node(add).op);
    const partial = module.node(module.bodies[2].root);
    try std.testing.expectEqual(core.Tag.apply, partial.tag);
    try std.testing.expectEqual(core.Tag.reference, module.node(partial.a).tag);
    try std.testing.expectEqual(module.bodies[1].binding, module.reference(partial.a).binding);
    try std.testing.expectEqual(@as(u32, 21), module.node(partial.b).a);
    const array = module.bodies[3].root;
    try std.testing.expectEqual(core.Tag.array_op, module.node(array).tag);
    try std.testing.expectEqual(core.ArrayOp.fill, module.arrayOperation(array));
    const dead = module.bodies[4].root;
    try std.testing.expectEqual(core.Tag.panic, module.node(dead).tag);
    try std.testing.expectEqualStrings("bad\n\t\" UTF8 🦊", module.panicMessage(dead));
    try std.testing.expectEqual(@as(usize, 6), module.body_lowerings);
}
fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 0), module.primitives.len);
    try std.testing.expectEqualStrings("bad\n\t\" UTF8 🦊", module.panicMessage(module.bodies[4].root));
}
test "all callable and panic lowering allocation failures release frozen bytes and tables" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
