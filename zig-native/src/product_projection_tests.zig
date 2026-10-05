const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn checkSource(allocator: std.mem.Allocator, source: []const u8, expected: ?checker.Code) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    if (expected) |code| {
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(code, checked.diagnostics[0].code);
        try std.testing.expectEqual(checked.diagnostics[0].span.start, checked.diagnostics[0].span.end);
    } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

const mixed_source =
    \\const first = fn (value: (a,b)) => @product.get value 0
    \\const capture = fn (value: (U32,Bool)) => fn () => @product.get value 0
    \\entry const answer = fn () => @u32.add (first (20,#True)) ((capture (22,#False)) ())
    \\entry const folded = answer ()
;
fn evaluate(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), "folded")) {
        try std.testing.expectEqual(@as(u32, 42), (try session.value(.{ .unit = 1, .binding = body.binding })).bits);
        return;
    };
    return error.TestUnexpectedResult;
}

test "known product shapes and literal projection indices keep distinct source diagnostics under every failed allocation" {
    for ([_]struct { source: []const u8, code: ?checker.Code }{
        .{ .source = "entry const answer = fn () => @product.get (42,#True) 0\n", .code = null },
        .{ .source = "entry const answer = fn () => @product.get (42,#True) 2\n", .code = .product_index },
        .{ .source = "entry const answer = fn () => @product.get (42,#True) 4294967295\n", .code = .product_index },
        .{ .source = "entry const answer = fn () => @product.get (42,#True) (0)\n", .code = .product_index_literal },
        .{ .source = "entry const answer = fn () => @product.get (42,#True) 0.0\n", .code = .product_index_literal },
        .{ .source = "entry const answer = fn () => @product.get (42,#True) #False\n", .code = .product_index_literal },
        .{ .source = "entry const answer = fn value => @product.get value 0\n", .code = .unknown_product_shape },
        .{ .source = "entry const answer = fn () => @product.get () 0\n", .code = .type_mismatch },
    }) |case| {
        try checkSource(a, case.source, case.code);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkSource, .{ case.source, case.code });
    }
}

test "product projections preserve captured and generic value types across frozen Core evaluation and emission" {
    var module = try lower(a, mixed_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const type_extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(type_extra);
    try evaluate(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evaluate, .{&module});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
    try std.testing.expectEqualSlices(types.Node, type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, type_extra, module.types.extra);
}

test "a projected Never operand retains its panic without inventing a product layout" {
    const source = "entry const answer: Unit -> U32 = fn () => @product.get (@panic \"projected\") 0\n";
    try checkSource(a, source, null);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkSource, .{ source, @as(?checker.Code, null) });
    var module = try lower(a, source);
    defer module.deinit(a);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
