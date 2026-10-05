const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");

const Case = struct { source: []const u8, valid: bool, start: u32 = 0, end: u32 = 0 };
const cases = [_]Case{
    // local_upper
    .{ .source =
    \\entry const x = do:
    \\  let X = 0
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // local_lower
    .{ .source =
    \\entry const x = do:
    \\  let x = 0
    \\  return 0
    \\
    , .valid = true },
    // const_upper
    .{ .source =
    \\const x = do:
    \\  let X = 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // let_upper
    .{ .source =
    \\let x = do:
    \\  let X = 0
    \\
    , .valid = false, .start = 0, .end = 3 },
    // nested_upper
    .{ .source =
    \\entry const x = do:
    \\  let nested = do:
    \\    let X = 0
    \\    return 0
    \\  return nested
    \\
    , .valid = false, .start = 0, .end = 5 },
    // tuple_upper
    .{ .source =
    \\entry const x = do:
    \\  let (X, y) = (0, 1)
    \\  return y
    \\
    , .valid = false, .start = 0, .end = 5 },
    // record_upper
    .{ .source =
    \\entry const x = do:
    \\  let {X} = {x: 0}
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // lambda_upper
    .{ .source =
    \\entry const x = fn X => 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // range_upper
    .{ .source =
    \\entry const x = do:
    \\  for X in 0 .. 1:
    \\    0
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // request_upper
    .{ .source =
    \\entry const x = do:
    \\  for Request in @requests (@computation (fn () => 0)):
    \\    case request of
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 0, .end = 5 },
    // effect_payload_upper
    .{ .source =
    \\effect tick: Unit -> U32
    \\entry const x = do:
    \\  for request in @requests (@computation (fn () => tick ())):
    \\    case request of
    \\      effect tick X =>
    \\        yield 0
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 25, .end = 30 },
    // complete_payload_upper
    .{ .source =
    \\entry const x = do:
    \\  for request in @requests (@computation (fn () => 0)):
    \\    case request of
    \\      complete X =>
    \\        return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // uppercase_value_pattern
    .{ .source =
    \\entry const x = do:
    \\  let ^X = 0
    \\  return 0
    \\
    , .valid = true },
    // uppercase_constructor_pattern
    .{ .source =
    \\type T is data = #X U32
    \\entry const x = do:
    \\  let #X value = #X 0
    \\  return value
    \\
    , .valid = true },
    // attribute_upper
    .{ .source =
    \\@[fn value => value]
    \\entry const x = do:
    \\  let X = 0
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 1 },
    // lambda_annotated_upper
    .{ .source =
    \\entry const x = fn (X: U32) => 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // lambda_demand_upper
    .{ .source =
    \\entry const x = fn ~X => 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // record_payload_upper
    .{ .source =
    \\entry const x = do:
    \\  let {x: X} = {x: 0}
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // boolean_name_upper
    .{ .source =
    \\entry const x = do:
    \\  let True = 0
    \\  return 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // lambda_boolean_upper
    .{ .source =
    \\entry const x = fn True => 0
    \\
    , .valid = false, .start = 0, .end = 5 },
    // uppercase_global
    .{ .source =
    \\entry const X = 0
    \\
    , .valid = true },
    // qualified_namespace
    .{ .source =
    \\const Foo.bar = fn x => x
    \\
    , .valid = true },
    // boolean_constructor_pattern
    .{ .source =
    \\entry const x = do:
    \\  let #True = #True
    \\  return 0
    \\
    , .valid = true },
};

fn binderGrammar(allocator: std.mem.Allocator) !void {
    for (cases) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        if (item.valid) {
            try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        } else {
            try std.testing.expect(tree.diagnostics.items.len != 0);
            const diagnostic = tree.diagnostics.items[0];
            try std.testing.expectEqual(ast.Code.GPU_FRONTEND_SYNTAX_ERROR, diagnostic.code);
            try std.testing.expectEqual(item.start, diagnostic.start);
            try std.testing.expectEqual(item.end, diagnostic.end);
        }
    }
}

test "binder grammar preserves explicit uppercase patterns and rejects bare uppercase names at frozen declaration spans" {
    try binderGrammar(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, binderGrammar, .{});
}
