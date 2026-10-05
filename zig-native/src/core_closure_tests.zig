const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

const Fixture = struct {
    tree: ast.Tree,
    names: symbols.Pool,
    checked: check.Checked,
    fn init(source: []const u8) !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var names: symbols.Pool = .{};
        errdefer names.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &names);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &names);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("closure check at {d}: {s}\n", .{ item.span.start, item.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .names = names, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.names.deinit(a);
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.names, &self.checked);
    }
    fn binding(self: *const Fixture, root: usize) u32 {
        var position: usize = 0;
        for (self.tree.roots.items) |id| if (self.tree.node(id).tag == .value_decl) {
            if (position == root) return self.checked.resolved[id];
            position += 1;
        };
        unreachable;
    }
};

const snapshot_source =
    \\infixl 60 (+) = _fixity_add
    \\const add = fn (left: U32) => fn (right: U32) => left + right
    \\entry const snapshot = fn (input: U32) -> U32 => do:
    \\  let saved = input
    \\  let nested = fn (first: U32) => fn (second: U32) => saved + first + second
    \\  saved := 0
    \\  let partial = add input
    \\  let inner = nested 1
    \\  return inner (partial 1)
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;

test "closures own transitive local snapshots and unary applications after frontend teardown" {
    var fixture = try Fixture.init(snapshot_source);
    const global = fixture.binding(1);
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), module.body_lowerings);
    try std.testing.expectEqual(@as(usize, 2), module.closures.len);
    const statements = module.children(module.body(global).?.root);
    const saved = module.node(statements[0]).a;
    const outer_id = module.node(statements[1]).b;
    const successor = module.node(statements[2]).a;
    const outer = module.closure(outer_id);
    try std.testing.expectEqualSlices(u32, &.{saved}, module.closureCaptures(outer_id));
    const inner_id = outer.body;
    const inner = module.closure(inner_id);
    try std.testing.expectEqualSlices(u32, &.{ saved, outer.parameter.binding }, module.closureCaptures(inner_id));
    try std.testing.expect(saved != successor);
    try std.testing.expect(outer.parameter.binding != inner.parameter.binding);
    const partial = module.node(module.node(statements[3]).b);
    try std.testing.expectEqual(core.Tag.apply, partial.tag);
    try std.testing.expectEqual(core.Tag.reference, module.node(partial.a).tag);
    const invoke = module.node(module.node(statements[4]).b);
    try std.testing.expectEqual(core.Tag.apply, invoke.tag);
    const result = module.node(module.node(statements[5]).a);
    try std.testing.expectEqual(core.Tag.apply, result.tag);
    try std.testing.expectEqual(core.Tag.apply, module.node(result.b).tag);
    try std.testing.expectEqualStrings("snapshot", module.name(module.body(global).?.export_name));
}

test "closure captures exclude own lexical patterns and include nested pinned references" {
    var fixture = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\entry const inspect = fn (selected: U32) -> U32 => do:
        \\  let choose = fn input -> U32 => case input of
        \\    (^selected, value) => value
        \\    (_, value) => value + 1
        \\  return choose (selected, 41)
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const body = module.body(fixture.binding(0)).?;
    const closure_id = module.node(module.children(body.root)[0]).b;
    try std.testing.expectEqualSlices(u32, &.{module.bodyParameters(body)[0].binding}, module.closureCaptures(closure_id));
    const info = module.closure(closure_id);
    try std.testing.expectEqual(core.Tag.match, module.node(info.body).tag);
}

test "unary constructor values retain catalog and instantiated function type" {
    var fixture = try Fixture.init(
        \\type Box value is data = #Box value
        \\entry const boxed = fn () -> U32 => do:
        \\  let wrap = #Box
        \\  let result = wrap 42
        \\  return case result of
        \\    #Box value => value
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const body = module.body(fixture.binding(0)).?;
    const statements = module.children(body.root);
    const constructor = module.node(module.node(statements[0]).b);
    try std.testing.expectEqual(core.Tag.constructor_function, constructor.tag);
    try std.testing.expectEqual(@as(u32, 1), constructor.a);
    try std.testing.expectEqual(@import("types.zig").Tag.function, module.types.node(constructor.ty).tag);
    try std.testing.expectEqual(core.Tag.apply, module.node(module.node(statements[1]).b).tag);
}

fn lowerFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), module.closures.len);
}

test "all closure projection allocation failures release bodies captures and scratch" {
    var fixture = try Fixture.init(snapshot_source);
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerFailure, .{&fixture});
}
