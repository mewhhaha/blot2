//! A publication projection over owned frontend failure evidence.
//! Byte offsets remain the native contract; UTF-16 offsets are explicit.
const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const token = @import("token.zig");

pub const Cause = enum { grammar, delimiter, lexical, native_detail };
pub const Publication = struct {
    cause: Cause,
    code: []const u8,
    span: ast.Span,
    message: []const u8,
    expected_token: ?token.Tag = null,
    actual_token: ?token.Tag = null,

    pub fn utf16(self: Publication, source: []const u8) ?ast.Span {
        return .{ .start = utf16Offset(source, self.span.start) orelse return null, .end = utf16Offset(source, self.span.end) orelse return null };
    }
};

fn grammarFailure(code: ast.Code) bool {
    return switch (code) {
        .expected_token, .expected_expression, .expected_type, .expected_pattern, .unexpected_token, .GPU_FRONTEND_SYNTAX_ERROR => true,
        // Literal validity, private source markers and resource limits are
        // separate causes even when the parser happens to observe them.
        else => false,
    };
}

fn closer(tag: token.Tag) ?token.Tag {
    return switch (tag) {
        .l_paren => .r_paren,
        .l_bracket => .r_bracket,
        .l_brace => .r_brace,
        else => null,
    };
}
fn closing(tag: token.Tag) bool {
    return switch (tag) {
        .r_paren, .r_bracket, .r_brace => true,
        else => false,
    };
}

fn keepEarlier(candidate: *?Publication, span: ast.Span, expected: ?token.Tag, actual: token.Tag) void {
    if (candidate.*) |previous| if (previous.span.start <= span.start) return;
    candidate.* = .{ .cause = .delimiter, .code = "GPU_FRONTEND_MALFORMED_DELIMITER", .span = span, .message = "A source delimiter does not match its enclosing pair", .expected_token = expected, .actual_token = actual };
}

// Only run after recognition fails. Successful compilation pays no second
// token scan or delimiter stack allocation. This examines actual pairs, not
// an assumed meaning of expected_token.
fn delimiters(allocator: std.mem.Allocator, tokens: []const token.Token) std.mem.Allocator.Error!?Publication {
    var stack: std.ArrayList(token.Token) = .empty;
    defer stack.deinit(allocator);
    var failure: ?Publication = null;
    for (tokens) |current| {
        if (closer(current.tag) != null) {
            try stack.append(allocator, current);
        } else if (closing(current.tag)) {
            const open = stack.pop();
            const expected = if (open) |value| closer(value.tag) else null;
            if (expected == null or expected.? != current.tag)
                keepEarlier(&failure, .{ .start = current.start, .end = current.end }, expected, current.tag);
        }
    }
    for (stack.items) |open| keepEarlier(&failure, .{ .start = open.start, .end = open.end }, closer(open.tag), .eof);
    return failure;
}

pub fn parse(allocator: std.mem.Allocator, tokens: []const token.Token, detail: ast.Diagnostic) std.mem.Allocator.Error!Publication {
    if (grammarFailure(detail.code)) {
        if (try delimiters(allocator, tokens)) |failure| return failure;
        return .{ .cause = .grammar, .code = "GPU_FRONTEND_SYNTAX_ERROR", .span = detail.declaration_origin orelse .{ .start = detail.start, .end = detail.end }, .message = "This declaration does not match the source grammar", .expected_token = detail.expected_token, .actual_token = detail.actual_token };
    }
    return .{ .cause = .native_detail, .code = @tagName(detail.code), .span = .{ .start = detail.start, .end = detail.end }, .message = detail.message(), .expected_token = detail.expected_token, .actual_token = detail.actual_token };
}

pub fn lexical(tokens: []const token.Token, detail: lexer.Diagnostic) Publication {
    switch (detail.code) {
        .lexical_error => return .{ .cause = .lexical, .code = "LEX_UNEXPECTED_CHARACTER", .span = .{ .start = detail.start, .end = detail.end }, .message = "No token matches this source character" },
        .string_literal, .string_escape => {
            // The string token itself cannot be recognized by the grammar's
            // STRING rule. Preserve the escape/termination detail separately.
            for (tokens) |current| {
                if (current.tag == .string and current.start <= detail.start and detail.start <= current.end)
                    return .{ .cause = .lexical, .code = "LEX_UNEXPECTED_CHARACTER", .span = .{ .start = current.start, .end = current.start + 1 }, .message = "The source string token cannot be recognized" };
            }
        },
        else => {},
    }
    return .{ .cause = .native_detail, .code = @tagName(detail.code), .span = .{ .start = detail.start, .end = detail.end }, .message = detail.message() };
}

// A failed UTF-8 source retains its byte diagnostic without claiming a
// meaningful UTF-16 location. Conversion is done only for publication.
fn utf16Offset(source: []const u8, byte_offset: u32) ?u32 {
    if (byte_offset > source.len) return null;
    var byte: usize = 0;
    var units: u32 = 0;
    while (byte < byte_offset) {
        const width = std.unicode.utf8ByteSequenceLength(source[byte]) catch return null;
        if (width > byte_offset - byte) return null;
        const point = lexer.decodePoint(source[byte..][0..width]) catch return null;
        units += if (point > 0xffff) @as(u32, 2) else 1;
        byte += width;
    }
    return units;
}

test "grammar publication retains local evidence and containing top-level origin" {
    const parser = @import("parser.zig");
    const symbols = @import("symbols.zig");
    const allocator = std.testing.allocator;
    const cases = [_]struct { source: []const u8, start: u32, end: u32, utf16_start: u32 }{
        .{ .source = "const bad = fn () => do:\n  use\n  return 0\n", .start = 0, .end = 5, .utf16_start = 0 },
        .{ .source = "const earlier = 42\nconst bad = fn () => do:\n  use\n  return 0\n", .start = 19, .end = 24, .utf16_start = 19 },
        .{ .source = "@[42]\nconst bad = fn () => do:\n  use\n  return 0\n", .start = 0, .end = 1, .utf16_start = 0 },
        .{ .source = "// 雪🙂\nconst bad = fn () => do:\n  use\n  return 0\n", .start = 11, .end = 16, .utf16_start = 7 },
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
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
        .{ .source = "const bad = fn () => do:\n  return (42\n", .span = .{ .start = 34, .end = 35 }, .expected = .r_paren },
        .{ .source = "const bad = fn () => do:\n  let values = [42\n  return 0\n", .span = .{ .start = 40, .end = 41 }, .expected = .r_bracket },
        .{ .source = "const bad = fn () => do:\n  let value = { field: 42\n  return 0\n", .span = .{ .start = 39, .end = 40 }, .expected = .r_brace },
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, nestedDelimiterAllocationScenario, .{});
}
