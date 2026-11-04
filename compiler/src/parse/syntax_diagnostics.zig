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
