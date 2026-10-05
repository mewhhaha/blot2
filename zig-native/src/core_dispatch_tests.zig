const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const source =
    \\infixl 60 (+) = _fixity_add
    \\type Point is data = #Point { x: U32 }
    \\const Point.add = fn (left: Point) => fn (right: U32) => @u32.add left.x right
    \\const combine = fn left => fn right => left + right
    \\entry const run = fn (value: U32) -> U32 => combine (#Point { x: value }) 22
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;
const Fixture = struct {
    tree: ast.Tree,
    names: symbols.Pool,
    checked: check.Checked,
    fn init() !Fixture {
        return initSource(source);
    }
    fn initSource(contents: []const u8) !Fixture {
        var tokens = try lexer.lex(a, contents);
        defer tokens.deinit(a);
        var names: symbols.Pool = .{};
        errdefer names.deinit(a);
        var tree = try parser.parse(a, contents, tokens.tokens.items, &names);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &names);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("dispatch {d}: {s}\n", .{ item.span.start, item.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .names = names, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.names.deinit(a);
    }
    fn binding(self: *const Fixture, name: []const u8) core.BindingId {
        for (self.checked.bindings, 0..) |binding_, id| {
            if (binding_.kind == .global and std.mem.eql(u8, self.names.get(binding_.name), name)) return @intCast(id);
        }
        unreachable;
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.names, &self.checked);
    }
};
test "associated catalog and independent dispatch principal types survive frontend teardown" {
    var fixture = try Fixture.init();
    const method = fixture.binding("Point.add");
    const generic = fixture.binding("combine");
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), module.associated.len);
    try std.testing.expectEqual(method, module.associated[0].target.binding);
    try std.testing.expectEqual(types.Operator.add, module.associated[0].operator);
    const body = module.body(generic).?;
    try std.testing.expect(body.root != 0);
    try std.testing.expectEqual(@as(u32, 3), body.scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), body.scheme.obligations.len);
    const constraint = module.obligations[body.scheme.obligations.start];
    try std.testing.expectEqual(types.ObligationKind.dispatch, constraint.kind);
    try std.testing.expectEqual(types.Operator.add, constraint.operator);
    try std.testing.expectEqual(types.Tag.variable, module.types.node(constraint.ty).tag);
    try std.testing.expectEqual(types.Tag.variable, module.types.node(constraint.other).tag);
    try std.testing.expectEqual(types.Tag.variable, module.types.node(constraint.result).tag);
    var emitted = try @import("core_backend.zig").compile(a, &.{module}, 1);
    defer emitted.deinit(a);
    try std.testing.expect(emitted.diagnostic == null and emitted.bytes.len != 0);
}
test "literal type calls retain arbitrary associated member identities without strings" {
    var fixture = try Fixture.initSource(
        \\infixl 60 (+) = _fixity_add
        \\type Point is data = #Point { x: U32 }
        \\const Point.merge = fn (left: Point) => fn (right: U32) => @u32.add left.x right
        \\const combine = fn left => fn right => @type.call "merge" left right
        \\entry const run = fn (value: U32) -> U32 => combine (#Point { x: value }) 22
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    );
    const generic = fixture.binding("combine");
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const body = module.body(generic).?;
    try std.testing.expect(body.root != 0);
    try std.testing.expectEqual(@as(u32, 1), body.scheme.obligations.len);
    const constraint = module.obligations[body.scheme.obligations.start];
    try std.testing.expectEqual(module.associated[0].member, constraint.name);
    try std.testing.expectEqual(types.Operator.none, constraint.operator);
    try std.testing.expectEqual(@as(u32, 3), body.scheme.variables.len);
    var emitted = try @import("core_backend.zig").compile(a, &.{module}, 1);
    defer emitted.deinit(a);
    try std.testing.expect(emitted.diagnostic == null and emitted.bytes.len != 0);
}
fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), module.associated.len);
}
test "every associated catalog allocation failure releases principal artifacts" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
