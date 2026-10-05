const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

const source =
    \\type Point is data = #Point { x: U32 }
    \\type Bucket is data = #Bucket { points: Array Point }
    \\const make = fn (initial: Bucket) => do:
    \\  let bucket = initial
    \\  return fn (index: U32) => do:
    \\    bucket.points[index].x := do:
    \\      let other = #[40]
    \\      other[0] := @u32.add self 2
    \\      return other[0]
    \\    return bucket.points[index].x
    \\entry const run = fn () -> U32 => (make (#Bucket { points: #[#Point { x: 1 }] })) 0
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
        for (checked.diagnostics) |item| std.debug.print("update {d}: {s}\n", .{ item.span.start, item.message() });
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
    try std.testing.expectEqual(@as(usize, 2), module.updates.len);
    try std.testing.expectEqual(@as(usize, 4), module.update_steps.len);
    try std.testing.expectEqual(@as(usize, 1), module.closures.len);
    var inner: core.Id = 0;
    var outer: core.Id = 0;
    var closure: core.Id = 0;
    for (module.nodes, 0..) |node, id| switch (node.tag) {
        .update => if (node.a == 0) {
            inner = @intCast(id);
        } else {
            outer = @intCast(id);
        },
        .closure => closure = @intCast(id),
        else => {},
    };
    try std.testing.expect(inner != 0 and outer != 0 and closure != 0);
    const inner_steps = module.updateSelectors(inner);
    const steps = module.updateSelectors(outer);
    try std.testing.expectEqual(@as(usize, 1), inner_steps.len);
    try std.testing.expectEqual(@as(usize, 3), steps.len);
    try std.testing.expectEqual(core.UpdateKind.field, steps[0].kind);
    try std.testing.expectEqual(core.UpdateKind.index, steps[1].kind);
    try std.testing.expectEqual(core.UpdateKind.field, steps[2].kind);
    try std.testing.expectEqual(core.UpdateKind.index, inner_steps[0].kind);
    try std.testing.expectEqual(core.Tag.reference, module.node(steps[1].index).tag);
    try std.testing.expectEqual(core.Tag.constant, module.node(inner_steps[0].index).tag);
    try std.testing.expectEqual(@as(usize, 0), module.updatePath(outer).len);
    const outer_info = module.updateInfo(outer);
    try std.testing.expectEqual(core.Tag.block, module.node(outer_info.value).tag);
    const captures = module.closureCaptures(closure);
    try std.testing.expectEqualSlices(core.BindingId, &.{module.reference(outer_info.root).binding}, captures);
    // No selector source nodes, checker tables or shared symbol bytes remain
    // borrowed by these instruction and projection identities.
    try std.testing.expectEqual(steps[0].result_type, module.projection(steps[0].projection).result_type);
    try std.testing.expectEqual(steps[2].result_type, module.projection(steps[2].projection).result_type);
}

test "owned mixed selectors retain nested update identities and lexical captures after frontend teardown" {
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

test "mixed selector and nested update allocation failures release every owned table" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
