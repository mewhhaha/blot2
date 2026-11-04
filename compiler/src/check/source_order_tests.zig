const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const ast = @import("../parse/ast.zig");
const check = @import("check.zig");
const a = std.testing.allocator;
const Case = struct { source: []const u8, code: check.Code, point: u32, message: []const u8 };
const cases = [_]Case{
    .{ .source = "entry const answer=do:\n  break missing\n  0\n", .code = .unreachable_statement, .point = 41, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  break 42\n  missing\n", .code = .unreachable_statement, .point = 36, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  missing\n  break 42\n  0\n", .code = .unknown_value, .point = 25, .message = "unknown value: missing" },
    .{ .source = "entry const answer=do:\n  let value=missing\n  break 42\n  0\n", .code = .unknown_value, .point = 35, .message = "unknown value: missing" },
    .{ .source = "entry const answer=do:\n  break missing\n  let value=missing_too\n  break 42\n", .code = .unreachable_statement, .point = 41, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  break missing\n  break missing_too\n", .code = .unreachable_statement, .point = 41, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  break\n  missing\n", .code = .unreachable_statement, .point = 33, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  yield missing\n  0\n", .code = .unreachable_statement, .point = 41, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  break $ missing\n  0\n", .code = .unreachable_statement, .point = 43, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  let callback=func()=> return do:\n    break missing\n    0\n  break 42\n", .code = .unreachable_statement, .point = 80, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=do:\n  for index in missing..missing_too:\n    break\n    missing_three\n  break 42\n", .code = .unreachable_statement, .point = 74, .message = "statement after return in the same suite" },
    .{ .source = "entry const answer=func(flag:Bool)=> return do:\n  if missing:\n    break missing_too\n    0\n  else:\n    missing_three\n  break 42\n", .code = .unknown_value, .point = 53, .message = "unknown value: missing" },
    .{ .source = "entry const answer=do:\n  saved:=missing\n  break 42\n", .code = .unknown_rebinding, .point = 25, .message = ":= requires an existing local binding: saved" },
    .{ .source = "const saved=42\nentry const answer=do:\n  saved:=missing\n  break 42\n", .code = .unknown_rebinding, .point = 40, .message = ":= requires an existing local binding: saved" },
    .{ .source = "entry const answer=do:\n  saved.value:=missing\n  break 42\n", .code = .unknown_rebinding, .point = 25, .message = ":= requires an existing local binding: saved" },
    .{ .source = "entry const answer=do:\n  saved[missing]:=missing_too\n  break 42\n", .code = .unknown_rebinding, .point = 25, .message = ":= requires an existing local binding: saved" },
    .{ .source = "entry const answer=do:\n  self:=missing\n  break 42\n", .code = .unknown_rebinding, .point = 25, .message = ":= requires an existing local binding: self" },
};
fn checking(allocator: std.mem.Allocator, case: Case) !void {
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var lexed = try lexer.lex(allocator, case.source);
    defer lexed.deinit(allocator);
    var tree = try parser.parse(allocator, case.source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const nodes = try allocator.dupe(ast.Node, tree.nodes.items);
    defer allocator.free(nodes);
    const spans = try allocator.dupe(ast.Span, tree.spans.items);
    defer allocator.free(spans);
    const extra = try allocator.dupe(u32, tree.extra.items);
    defer allocator.free(extra);
    var checked = try check.check(allocator, &tree, &names);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    const diagnostic = checked.diagnostics[0];
    try std.testing.expectEqual(case.code, diagnostic.code);
    try std.testing.expectEqual(ast.Span{ .start = case.point, .end = case.point }, diagnostic.span);
    const message = if (diagnostic.symbol == 0) try allocator.dupe(u8, diagnostic.message()) else try allocator.print("{s}: {s}", .{ diagnostic.message(), names.get(diagnostic.symbol) });
    defer allocator.free(message);
    try std.testing.expectEqualStrings(case.message, message);
    try std.testing.expectEqualSlices(ast.Node, nodes, tree.nodes.items);
    try std.testing.expectEqualSlices(ast.Span, spans, tree.spans.items);
    try std.testing.expectEqualSlices(u32, extra, tree.extra.items);
}
test "source control lowering reports actual frozen failure order points and text without changing syntax" {
    for (cases) |case| try checking(a, case);
}
test "source lowering early exits and rebinding failures release all owners on every allocation failure" {
    for ([_]usize{ 0, 2, 9, 10, 12, 14, 15, 16 }) |index| try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checking, .{cases[index]});
}
