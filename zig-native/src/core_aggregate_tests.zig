const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    pool: symbols.Pool,
    tree: ast.Tree,
    checked: check.Checked,
    fn init(source: []const u8) !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("check:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .pool = pool, .tree = tree, .checked = checked };
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
const records_source = "infixl 60 (+) = _fixity_add\n" ++ records_body ++ "\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n";
const records_body =
    \\type Vec2 is data = #Vec2 { x: F32, y: F32 }
    \\const sum = fn point => do:
    \\  let #Vec2 { x, y } = point
    \\  return x + y
    \\const origin = #Vec2 { y: 2.0, x: 20.0 }
    \\entry const answer = fn () -> F32 => sum origin
    \\entry const projected = fn () -> F32 => origin.x
    \\entry const tuple = fn () -> U32 => @product.get (20, 22) 1
;
test "owned nominal core preserves written values canonical pattern fields and typed projections" {
    var fixture = try Fixture.init(records_source);
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 6), module.body_lowerings);
    const origin = module.node(module.bodies[2].root);
    try std.testing.expectEqual(core.Tag.construct, origin.tag);
    const payload = module.node(origin.b);
    try std.testing.expectEqual(core.Tag.record, payload.tag);
    const values = module.children(origin.b);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 2.0))), module.node(values[0]).a);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 20.0))), module.node(values[1]).a);
    try std.testing.expectEqualSlices(u32, &.{ 1, 0 }, module.recordDestinations(origin.b));
    const constructor = module.constructor(origin.a);
    try std.testing.expectEqual(@as(u32, 0), constructor.tag);
    try std.testing.expectEqual(T.Tag.record, module.types.node(constructor.payload).tag);
    const sum_block = module.bodies[1].root;
    const binding = module.node(module.children(sum_block)[0]);
    try std.testing.expectEqual(core.Tag.pattern_bind, binding.tag);
    const outer = module.pattern(binding.a);
    try std.testing.expectEqual(core.PatternTag.constructor, outer.tag);
    const fields = module.patternChildren(outer.b);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqual(core.PatternTag.bind, module.pattern(fields[0]).tag);
    try std.testing.expectEqual(core.PatternTag.bind, module.pattern(fields[1]).tag);
    try std.testing.expectEqual(T.f32_type, module.pattern(fields[0]).ty);
    const projected = module.node(module.bodies[4].root);
    try std.testing.expectEqual(core.Tag.project, projected.tag);
    try std.testing.expectEqual(T.f32_type, module.projection(projected.b).result_type);
    try std.testing.expectEqual(@as(u32, 0), module.projectionVariants(projected.b)[0].field);
    const tuple = module.node(module.bodies[5].root);
    try std.testing.expectEqual(core.Tag.project, tuple.tag);
    try std.testing.expectEqual(core.Tag.product, module.node(tuple.a).tag);
    try std.testing.expectEqual(@as(u32, 1), module.projectionVariants(tuple.b)[0].field);
}

const alternatives_source = "infix 30 (>=) = _fixity_ge\ninfixl 60 (+) = _fixity_add\n" ++ alternatives_body ++ "\nconst _fixity_ge = fn left => fn right => @type.call \"ge\" left right\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n";
const alternatives_body =
    \\type Choice is data = #First U32 | #Second U32 | #Empty
    \\const choose = fn candidate => case candidate of
    \\  #First value | #Second value if value >= 40 => value
    \\  #First value | #Second value => value + 2
    \\  #Empty => 0
    \\entry const choice_answer = choose (#Second 42)
;
test "ordered alternatives share their checked binding guard and body" {
    var fixture = try Fixture.init(alternatives_source);
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const match = module.bodies[1].root;
    const arms = module.matchArms(match);
    try std.testing.expectEqual(@as(usize, 3), arms.len);
    try std.testing.expectEqual(@as(usize, 1), module.matchInputs(match).len);
    const alternatives = module.armRows(arms[0]);
    try std.testing.expectEqual(@as(usize, 2), alternatives.len);
    const first = module.pattern(module.rowPatterns(alternatives[0])[0]);
    const second = module.pattern(module.rowPatterns(alternatives[1])[0]);
    try std.testing.expect(first.a != second.a);
    try std.testing.expectEqual(module.pattern(first.b).a, module.pattern(second.b).a);
    try std.testing.expectEqual(core.Tag.call, module.node(arms[0].guard).tag);
    try std.testing.expectEqual(core.Tag.reference, module.node(arms[0].body).tag);
    try std.testing.expectEqual(@as(core.Id, 0), arms[1].guard);
}

test "variant field projections retain constructor-specific canonical indices" {
    var fixture = try Fixture.init(
        \\type Point is data = #Left { x: U32, y: F32 } | #Right { y: F32, x: U32 }
        \\const pick = fn (point: Point) -> U32 => point.x
        \\entry const answer = pick (#Right { x: 42, y: 1.5 })
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const projected = module.node(module.bodies[1].root);
    try std.testing.expectEqual(core.Tag.project, projected.tag);
    const variants = module.projectionVariants(projected.b);
    try std.testing.expectEqual(@as(usize, 2), variants.len);
    try std.testing.expectEqual(core.ProjectionVariant{ .tag = 0, .field = 0 }, variants[0]);
    try std.testing.expectEqual(core.ProjectionVariant{ .tag = 1, .field = 1 }, variants[1]);
    try std.testing.expectEqual(T.u32_type, module.projection(projected.b).result_type);
}

test "refutable let and conditional matches preserve the outer return boundary" {
    var fixture = try Fixture.init(
        \\type Choice is data = #Some U32 | #Nothing
        \\const pick = fn candidate => do:
        \\  let #Some value = candidate else:
        \\    return 0
        \\  if let #Some other = candidate:
        \\    return other
        \\  return value
        \\entry const answer = pick (#Some 42)
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const block = module.bodies[1].root;
    const statements = module.children(block);
    const binding = module.node(statements[0]);
    try std.testing.expectEqual(core.Tag.pattern_bind, binding.tag);
    try std.testing.expectEqual(block, module.node(module.children(binding.c)[0]).b);
    const arms = module.matchArms(statements[1]);
    try std.testing.expect(module.matchInfo(statements[1]).statement);
    try std.testing.expectEqual(block, module.node(module.children(arms[0].body)[0]).b);
    try std.testing.expectEqual(@as(core.Id, 0), arms[1].body);
    try std.testing.expectEqual(block, module.node(statements[2]).b);
}

fn allocationScenario(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(fixture.checked.body_elaborations, module.body_lowerings);
}
test "aggregate catalogs projections and pattern artifacts release on every allocation failure" {
    var fixture = try Fixture.init(
        "infix 30 (>=) = _fixity_ge\ninfixl 60 (+) = _fixity_add\n" ++
            records_body ++ "\n" ++ alternatives_body ++
            "\nconst _fixity_ge = fn left => fn right => @type.call \"ge\" left right\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n",
    );
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{&fixture});
}
