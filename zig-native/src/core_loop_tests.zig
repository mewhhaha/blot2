const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

const source =
    \\const make = fn (start: U32) => do:
    \\  let total = start
    \\  return fn (limit: U32) => do:
    \\    for index in 0..limit:
    \\      total := @u32.add self index
    \\      if @u32.lt 2 index:
    \\        break
    \\    return total
    \\entry const run = fn (limit: U32) -> U32 => (make 40) limit
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
        for (checked.diagnostics) |item| std.debug.print("loop {d}: {s}\n", .{ item.span.start, item.message() });
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

fn verify(module: *const core.Module) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), module.loops.len);
    try std.testing.expectEqual(@as(usize, 1), module.closures.len);
    var loop_id: core.Id = 0;
    var break_id: core.Id = 0;
    var closure_id: core.Id = 0;
    for (module.nodes, 0..) |value, id| switch (value.tag) {
        .loop => loop_id = @intCast(id),
        .break_ => break_id = @intCast(id),
        .closure => closure_id = @intCast(id),
        else => {},
    };
    try std.testing.expect(loop_id != 0 and break_id != 0 and closure_id != 0);
    const loop = module.loopInfo(loop_id);
    try std.testing.expectEqual(core.LoopKind.range, loop.kind);
    try std.testing.expectEqual(core.Tag.constant, module.node(loop.first).tag);
    try std.testing.expectEqual(core.Tag.reference, module.node(loop.end).tag);
    try std.testing.expectEqual(core.Tag.suite, module.node(loop.body).tag);
    try std.testing.expectEqual(core.PatternTag.bind, module.pattern(loop.pattern).tag);
    const carries = module.loopCarries(loop_id);
    try std.testing.expectEqual(@as(usize, 1), carries.len);
    const carry = carries[0];
    try std.testing.expect(carry.incoming != carry.iteration);
    try std.testing.expect(carry.iteration != carry.backedge);
    try std.testing.expect(carry.backedge != carry.outgoing);
    try std.testing.expectEqual(loop_id, module.node(break_id).a);
    const values = module.breakValues(break_id);
    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(carry.backedge, module.reference(values[0]).binding);
    // Only the initial outer lexical value escapes into the closure's frozen
    // environment; iteration, iterator and outgoing bindings are body locals.
    const captures = module.closureCaptures(closure_id);
    try std.testing.expectEqualSlices(core.BindingId, &.{carry.incoming}, captures);
}

test "owned loop bodies and lexical carries survive frontend teardown" {
    var fixture = try Fixture.init();
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verify(&module);
}

fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verify(&module);
}

test "loop carry, break value and capture allocation failures release owned state" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
