const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const ast = @import("../parse/ast.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;

const source =
    \\infixl 60 (+) = _fixity_add
    \\infixl 70 (*) = _fixity_mul
    \\const add = func amount => return func value => return value + amount
    \\const twice = func value => return value * 2
    \\@[add 1]
    \\@[twice]
    \\entry const answer: U32 = 20
    \\@[func function => return func value => return function value + 1]
    \\entry const next: U32 -> U32 = func (value: U32) => return value
    \\@[func function => return function 41]
    \\entry const reduced: U32 = func (value: U32) => return value + 1
    \\@[func value => return @panic "unreachable"]
    \\const unused: U32 = 1
    \\const _fixity_add = func left => return func right => return @u32.add left right
    \\const _fixity_mul = func left => return func right => return @u32.mul left right
;
fn lower(allocator: std.mem.Allocator, text: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const nodes = try allocator.dupe(ast.Node, tree.nodes.items);
    defer allocator.free(nodes);
    const spans = try allocator.dupe(ast.Span, tree.spans.items);
    defer allocator.free(spans);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |item| std.debug.print("{s}:{d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    module.unit = 1;
    errdefer module.deinit(allocator);
    try std.testing.expectEqualDeep(nodes, tree.nodes.items);
    try std.testing.expectEqualDeep(spans, tree.spans.items);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn validScenario(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), module.tag_calls.len);
    for (module.tag_calls) |id| {
        try std.testing.expect(module.isTagCall(id));
        try std.testing.expectEqual(core.Tag.apply, module.node(id).tag);
    }
    var result = try backend.compile(allocator, &.{module}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |item| std.debug.print("backend {s}:{d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "tags wrap complete initializers without mutating source and preserve ordinary eager tag arguments" {
    try validScenario(a);
}
test "tag checking lowering and backend ownership survives every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, validScenario, .{});
}
test "tag and original initializer diagnostics retain their distinct source ownership" {
    const cases = [_]struct { text: []const u8, code: check.Code, marker: []const u8 }{
        .{ .text = "@[1] entry const answer=42\n", .code = .type_mismatch, .marker = "@[" },
        .{ .text = "@[func value=> return value]\n@[1] entry const answer=42\n", .code = .type_mismatch, .marker = "@[1]" },
        .{ .text = "@[func value=> return @u32.add true 1] entry const answer=42\n", .code = .type_mismatch, .marker = "@[" },
        .{ .text = "@[func value=> return value] entry const answer=answer\n", .code = .recursive_tag, .marker = "@[" },
        .{ .text = "@[answer] entry const answer:U32=42\n", .code = .recursive_tag, .marker = "@[" },
        .{ .text = "@[func value=> return value] entry const answer=func ()=> return answer ()\n", .code = .recursive_tag, .marker = "@[" },
        .{ .text = "@[func value=> return case value of\n  true=>1]\nentry const answer:U32=true\n", .code = .non_exhaustive_match, .marker = "@[" },
        .{ .text = "@[func value=> return value]\nentry const answer:U32=case true of\n  true=>1\n", .code = .non_exhaustive_match, .marker = "case" },
        .{ .text = "@[func value=> return true] entry const answer:U32=42\n", .code = .type_mismatch, .marker = "U32" },
        .{ .text = "const expected=(1,2)\n@[func value=> return case value of\n  ^expected=>1\n  _=>0] entry const answer=expected\n", .code = .value_pattern_type, .marker = "@[" },
        .{ .text = "const expected=(1,2)\n@[func value=> return value] entry const answer=case expected of\n  ^expected=>1\n  _=>0\n", .code = .value_pattern_type, .marker = "case" },
        .{ .text = "@[func ~value=> return @demand value] entry const answer:U32=42\n", .code = .type_mismatch, .marker = "@[" },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(a, item.text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, item.text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
        try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, item.text, item.marker).?)), checked.diagnostics[0].span.start);
    }
}
