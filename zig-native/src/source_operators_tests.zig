const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const a = std.testing.allocator;
const Case = struct { source: []const u8, code: ?check.Code, point: u32 = 0 };
const cases = [_]Case{
    .{ .source = "entry const answer = 20 + 22\n", .code = .unknown_operator, .point = 24 },
    .{ .source = "entry const answer = @u32.add #True 0 + 1\n", .code = .unknown_operator, .point = 38 },
    .{ .source = "entry const answer = missing + 1\n", .code = .unknown_value, .point = 21 },
    .{ .source = "entry const answer = 1 + missing\n", .code = .unknown_operator, .point = 23 },
    .{ .source = "entry const answer = @u32.ne 1 2\n", .code = .unknown_intrinsic, .point = 21 },
    .{ .source = "entry const answer = #Type 42\n", .code = .unknown_value, .point = 22 },
    .{ .source = "entry const answer = :42\n", .code = .unknown_value, .point = 21 },
    .{ .source = "entry const answer = +1.5\n", .code = .unsupported_prefix, .point = 21 },
    .{ .source = "entry const answer = @product.get missing other\n", .code = .unknown_value, .point = 34 },
    .{ .source = "entry const answer = @product.get (@u32.add #True 1) missing\n", .code = .product_index_literal, .point = 53 },
    .{ .source = "infixl 60 (+) = add\nconst add = fn left => fn right => @u32.add left right\nentry const answer = 20 + 22\n", .code = null },
    .{ .source = "entry const answer = do:\n  let minus = fn left => fn right => @u32.sub left right\n  return 50 `minus` 8\n", .code = null },
    .{ .source = "infixl 256 (+) = add\nconst add = fn left => fn right => @u32.add left right\nentry const answer = 20 + 22\n", .code = .operator_precedence, .point = 0 },
    .{ .source = "const add = fn left => fn right => @u32.add left right\ninfixl 60 (+) = add\nentry const answer = 20 + 22\n", .code = .operator_header_order, .point = 55 },
    .{ .source = "infixl 60 (+) = add\ninfixl 70 (+) = add\nconst add = fn left => fn right => @u32.add left right\nentry const answer = 20 + 22\n", .code = .duplicate_operator, .point = 0 },
    .{ .source = "infixl 60 (+) = missing\nentry const answer = 42\n", .code = .unknown_value, .point = 16 },
    .{ .source = "infix 30 (<) = lt\nconst lt = fn left => fn right => @u32.lt left right\nentry const answer = 1 < 2 < 3\n", .code = .operator_associativity, .point = 98 },
    .{ .source = "entry const answer = do:\n  for index in missing .. 2:\n    absent\n  return 42\n", .code = .unknown_value, .point = 58 },
    .{ .source = "entry const answer = do:\n  for index in missing .. 2:\n    break\n  return absent\n", .code = .unknown_value, .point = 73 },
    .{ .source = "entry const answer = do:\n  for value in missing:\n    absent\n  return 42\n", .code = .unknown_value, .point = 53 },
    .{ .source = "entry const answer = do:\n  if missing:\n    return absent\n  return 42\n", .code = .unknown_value, .point = 30 },
    .{ .source = "entry const answer = do:\n  if let #Missing value = absent:\n    return value\n  return 42\n", .code = .unknown_value, .point = 35 },
    .{ .source = "entry const answer = do:\n  let #Missing value = absent else:\n    return 0\n  return value\n", .code = .unknown_value, .point = 32 },
    .{ .source = "entry const answer = case 42 of\n  #Missing value => absent\n", .code = .unknown_value, .point = 35 },
    .{ .source = "entry const answer = case 42 of\n  value if absent => missing\n", .code = .unknown_value, .point = 53 },
    .{ .source = "const repeated = 1\nconst repeated = 2 + 3\nentry const answer = 42\n", .code = .duplicate_name, .point = 0 },
    .{ .source = "type Box is data = #Box Missing\nentry const answer = 20 + 22\n", .code = .unknown_operator, .point = 56 },
    .{ .source = "@[missing_tag]\neffect Read: Unit -> U32\nentry const answer = 20 + 22\n", .code = .unknown_operator, .point = 64 },
    .{ .source = "entry const answer = @u32.add\n", .code = .call_arity, .point = 21 },
    .{ .source = "const plusone = @u32.add 1\nentry const answer = plusone 41\n", .code = .call_arity, .point = 16 },
    .{ .source = "entry const answer = @panic (\"stop\")\n", .code = .literal_required, .point = 28 },
    .{ .source = "entry const answer = @u32.add missing\n", .code = .call_arity, .point = 21 },
    .{ .source = "entry const answer = @product.get (@foo 1) other\n", .code = .unknown_intrinsic, .point = 35 },
    .{ .source = "type Read is effect = { first: Unit -> U32, second: Unit -> U32 }\nentry const answer = do:\n  for request in @requests missing_action:\n    case request of\n      effect Read.first value =>\n        yield absent_first\n      effect Read.second value =>\n        yield absent_second\n      complete value =>\n        return absent_complete\n  return absent_suffix\n", .code = .unknown_value, .point = 118 },
    .{ .source = "type Read is effect = { first: Unit -> U32, second: Unit -> U32 }\nentry const answer = do:\n  for request in @requests (@computation (fn () => Read.first ())):\n    case request of\n      effect Read.first value =>\n        yield absent_first\n      effect Read.second value =>\n        yield absent_second\n      complete value =>\n        return absent_complete\n  return absent_suffix\n", .code = .unknown_value, .point = 340 },
    .{ .source = "type Read is effect = { first: Unit -> U32, second: Unit -> U32 }\nentry const answer = do:\n  for request in @requests (@computation (fn () => Read.first ())):\n    case request of\n      effect Read.first value =>\n        yield absent_first\n      effect Read.second value =>\n        yield absent_second\n      complete value =>\n        break\n  return absent_suffix\n", .code = .unknown_value, .point = 348 },
    .{ .source = "type Read is effect = { first: Unit -> U32, second: Unit -> U32 }\nentry const answer = do:\n  for request in @requests (@computation (fn () => Read.first ())):\n    case request of\n      effect Read.first value =>\n        yield absent_first\n      effect Read.second value =>\n        yield absent_second\n      complete value =>\n        break\n  return 42\n", .code = .unknown_value, .point = 226 },
    .{ .source = "type Reader is effect = Unit -> U32\nentry const answer = do:\n  use value <- Reader missing\n  return value\n", .code = .unknown_value, .point = 83 },
    .{ .source = "type Box is data = #Box\nentry const answer = Box missing\n", .code = .unknown_value, .point = 49 },
    .{ .source = "entry const answer = (@u32.add) 20 22\n", .code = .call_arity, .point = 22 },
    .{ .source = "entry const answer = ((@u32.add)) 20 22\n", .code = .call_arity, .point = 23 },
    .{ .source = "entry const answer = (@u32.add 20) 22\n", .code = .call_arity, .point = 22 },
    .{ .source = "entry const answer = fn value => case value of\n  _ if missing_guard => missing_body\n", .code = .unknown_value, .point = 71 },
    .{ .source = "type Choice is data = #First U32 | #Second U32\nentry const answer = fn value => case value of\n  #First x | #Missing x => missing_body\n", .code = .unknown_value, .point = 108 },
    .{ .source = "type Choice is data = #First U32 | #Second U32\nentry const answer = fn value => case value of\n  #First x | #Second y => missing_body\n", .code = .alternative_bindings, .point = 107 },
    .{ .source = "type Choice is data = #First U32 | #Second U32\nentry const answer = fn value => case value of\n  #First x | ^missing_pattern => missing_body\n", .code = .unknown_value, .point = 108 },
    .{ .source = "const invalid = fn value => case value of\n  (same, same) => 0\n", .code = .duplicate_pattern_binding, .point = 51 },
    .{ .source = "data Pair = #Pair { x: U32, y: U32 }\nconst invalid = fn value => case value of\n  #Pair { x: same, y: same } => 0\n", .code = .duplicate_pattern_binding, .point = 98 },
    .{ .source = "data Pair = #Pair { x: U32, y: U32 }\nconst invalid = fn value => case value of\n  #Pair { x, x } => 0\n", .code = .duplicate_record_field, .point = 92 },
    .{ .source = "entry const answer = fn (value:U32) => case value, value, value, value, value, value, value, value, value, value, value, value of\n  field0, field1, field2, field3, field4, field5, field6, field7, field8, field9, field10, field11 => field0\n", .code = null },
};
fn scenario(allocator: std.mem.Allocator, case: Case) !void {
    var tokens = try lexer.lex(allocator, case.source);
    defer tokens.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, case.source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    // Missing declarations and invalid associations are lowering errors, not
    // syntax errors. Parsing retains source order and operator provenance.
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const node_count = tree.nodes.items.len;
    const symbol_count = pool.entries.items.len;
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    if (case.code) |code| {
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(code, checked.diagnostics[0].code);
        try std.testing.expectEqual(ast.Span{ .start = case.point, .end = case.point }, checked.diagnostics[0].span);
    } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(node_count, tree.nodes.items.len);
    try std.testing.expectEqual(symbol_count, pool.entries.items.len);
}
test "source fixity uses explicit declarations and preserves frozen lowering error order" {
    for (cases) |case| try scenario(a, case);
}
test "source fixity validation releases every failed allocation for successful and rejected graphs" {
    for ([_]usize{ 0, 3, 10, 12, 14, 16, 17, 21, 25, 48, 49 }) |index| try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{cases[index]});
}
test "source fixity checking preserves the complete immutable parsed tree" {
    var tokens = try lexer.lex(a, cases[16].source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, cases[16].source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    const nodes = try a.dupe(ast.Node, tree.nodes.items);
    defer a.free(nodes);
    const spans = try a.dupe(ast.Span, tree.spans.items);
    defer a.free(spans);
    const extra = try a.dupe(u32, tree.extra.items);
    defer a.free(extra);
    const origins = try a.dupe(@TypeOf(tree.operator_origins.items[0]), tree.operator_origins.items);
    defer a.free(origins);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqualDeep(nodes, tree.nodes.items);
    try std.testing.expectEqualDeep(spans, tree.spans.items);
    try std.testing.expectEqualDeep(extra, tree.extra.items);
    try std.testing.expectEqualDeep(origins, tree.operator_origins.items);
}
