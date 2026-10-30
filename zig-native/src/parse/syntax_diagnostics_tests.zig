const std = @import("std");
const production = @import("syntax_diagnostics.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const token = @import("token.zig");
const parse = production.parse;
const lexical = production.lexical;
const Publication = production.Publication;
const Cause = production.Cause;

test "grammar publication retains local evidence and containing top-level origin" {
    const parser = @import("parser.zig");
    const symbols = @import("symbols.zig");
    const allocator = std.testing.allocator;
    const cases = [_]struct { source: []const u8, start: u32, end: u32, utf16_start: u32 }{
        .{ .source = "const bad = func () => return do:\n  use\n  break 0\n", .start = 0, .end = 5, .utf16_start = 0 },
        .{ .source = "const earlier = 42\nconst bad = func () => return do:\n  use\n  break 0\n", .start = 19, .end = 24, .utf16_start = 19 },
        .{ .source = "@[42]\nconst bad = func () => return do:\n  use\n  break 0\n", .start = 0, .end = 1, .utf16_start = 0 },
        .{ .source = "// 雪🙂\nconst bad = func () => return do:\n  use\n  break 0\n", .start = 11, .end = 16, .utf16_start = 7 },
    };
    for (cases) |item| {
        var lexed = try lexer.lex(allocator, item.source);
        defer lexed.deinit(allocator);
        var names: symbols.Pool = .{};
        defer names.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, lexed.tokens.items, &names);
        defer tree.deinit(allocator);
        const original = tree.diagnostics.items[0];
        const published = try parse(allocator, lexed.tokens.items, original);
        try std.testing.expectEqual(Cause.grammar, published.cause);
        try std.testing.expectEqualStrings("GPU_FRONTEND_SYNTAX_ERROR", published.code);
        try std.testing.expectEqual(ast.Span{ .start = item.start, .end = item.end }, published.span);
        try std.testing.expectEqual(item.utf16_start, published.utf16(item.source).?.start);
        try std.testing.expect(original.start > published.span.end);
        try std.testing.expectEqualDeep(original, tree.diagnostics.items[0]);
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    const parser = @import("parser.zig");
    const symbols = @import("symbols.zig");
    const source = "const bad = (42]\n";
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    const published = try parse(allocator, lexed.tokens.items, tree.diagnostics.items[0]);
    try std.testing.expectEqual(Cause.delimiter, published.cause);
    try std.testing.expectEqual(token.Tag.r_paren, published.expected_token.?);
    try std.testing.expectEqual(token.Tag.r_bracket, published.actual_token.?);
    try std.testing.expectEqual(ast.Span{ .start = 15, .end = 16 }, published.span);
}

test "delimiter publication uses actual pairs and releases scratch on every allocation failure" {
    try allocationScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
    const tokens = [_]token.Token{ .{ .tag = .l_paren, .start = 12, .end = 13 }, .{ .tag = .eof, .start = 16, .end = 16 } };
    const published = try parse(std.testing.allocator, &tokens, .{ .code = .expected_token, .start = 16, .end = 16, .declaration_origin = .{ .start = 0, .end = 5 } });
    try std.testing.expectEqual(ast.Span{ .start = 12, .end = 13 }, published.span);
    try std.testing.expectEqual(token.Tag.eof, published.actual_token.?);
}

test "lexical publication retains string evidence and explicit Unicode positions" {
    const allocator = std.testing.allocator;
    const source = "// 雪🙂\nconst bad = \"\\q\"\n";
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    const detail = lexed.diagnostics.items[0];
    try std.testing.expectEqual(lexer.Code.string_escape, detail.code);
    const published = lexical(lexed.tokens.items, detail);
    try std.testing.expectEqualStrings("LEX_UNEXPECTED_CHARACTER", published.code);
    try std.testing.expectEqual(ast.Span{ .start = 23, .end = 24 }, published.span);
    try std.testing.expectEqual(ast.Span{ .start = 19, .end = 20 }, published.utf16(source).?);
    try std.testing.expectEqual(detail.start, lexed.diagnostics.items[0].start);
    const invalid = lexical(&.{}, .{ .code = .invalid_utf8, .start = 1, .end = 2 });
    try std.testing.expect(invalid.utf16("a\xff") == null);
}

test "parser resource and marker failures retain their categories despite malformed delimiters" {
    const tokens = [_]token.Token{.{ .tag = .l_paren, .start = 0, .end = 1 }};
    for ([_]ast.Code{ .nesting_limit, .table_limit, .private_marker, .invalid_literal }) |code| {
        const published = try parse(std.testing.allocator, &tokens, .{ .code = code, .start = 7, .end = 8 });
        try std.testing.expectEqual(Cause.native_detail, published.cause);
        try std.testing.expectEqualStrings(@tagName(code), published.code);
        try std.testing.expectEqual(ast.Span{ .start = 7, .end = 8 }, published.span);
    }
}

test "UTF16 publication counts supplementary scalars and declines split byte boundaries" {
    const source = "a雪🙂e\u{301}z";
    const offsets = [_]struct { byte: u32, utf16: u32 }{
        .{ .byte = 0, .utf16 = 0 },  .{ .byte = 1, .utf16 = 1 },
        .{ .byte = 4, .utf16 = 2 },  .{ .byte = 8, .utf16 = 4 },
        .{ .byte = 9, .utf16 = 5 },  .{ .byte = 11, .utf16 = 6 },
        .{ .byte = 12, .utf16 = 7 },
    };
    for (offsets) |offset| {
        const published: Publication = .{ .cause = .grammar, .code = "GPU_FRONTEND_SYNTAX_ERROR", .span = .{ .start = offset.byte, .end = offset.byte }, .message = "grammar" };
        try std.testing.expectEqual(ast.Span{ .start = offset.utf16, .end = offset.utf16 }, published.utf16(source).?);
    }
    for ([_]u32{ 2, 3, 5, 6, 7, 10, 13 }) |byte| {
        const published: Publication = .{ .cause = .grammar, .code = "GPU_FRONTEND_SYNTAX_ERROR", .span = .{ .start = byte, .end = byte }, .message = "grammar" };
        try std.testing.expect(published.utf16(source) == null);
    }
}

fn nestedDelimiterAllocationScenario(allocator: std.mem.Allocator) !void {
    const parser = @import("parser.zig");
    const symbols = @import("symbols.zig");
    const cases = [_]struct { source: []const u8, span: ast.Span, expected: token.Tag }{
        .{ .source = "const bad = func () => return do:\n  break (42\n", .span = .{ .start = 42, .end = 43 }, .expected = .r_paren },
        .{ .source = "const bad = func () => return do:\n  let values = [42\n  break 0\n", .span = .{ .start = 49, .end = 50 }, .expected = .r_bracket },
        .{ .source = "const bad = func () => return do:\n  let value = { field: 42\n  break 0\n", .span = .{ .start = 48, .end = 49 }, .expected = .r_brace },
    };
    for (cases) |item| {
        var lexed = try lexer.lex(allocator, item.source);
        defer lexed.deinit(allocator);
        var names: symbols.Pool = .{};
        defer names.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, lexed.tokens.items, &names);
        defer tree.deinit(allocator);
        const published = try parse(allocator, lexed.tokens.items, tree.diagnostics.items[0]);
        try std.testing.expectEqual(Cause.delimiter, published.cause);
        try std.testing.expectEqual(item.span, published.span);
        try std.testing.expectEqual(item.expected, published.expected_token.?);
        try std.testing.expectEqual(token.Tag.eof, published.actual_token.?);
    }
}

test "synthetic layout frames cannot replace actual missing delimiter origins under every allocation failure" {
    try nestedDelimiterAllocationScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, nestedDelimiterAllocationScenario, .{});
}
